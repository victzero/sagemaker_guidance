#!/bin/bash
# =============================================================================
# set-user-download-access.sh - 管理用户的文件下载权限
# =============================================================================
#
# 功能:
#   开启或关闭特定 User Profile 的文件下载功能。
#   这是通过绑定/解绑 "disable-download" Lifecycle Config 来实现的。
#
# 原理:
#   - Domain 默认配置通常挂载了 disable-download LCC (默认禁用)。
#   - 要允许下载 (enable)，我们在 User Profile 级别显式设置 LCC 为空。
#   - 要禁止下载 (disable)，我们在 User Profile 级别显式设置 LCC 为 disable-download。
#   - 要重置 (reset)，我们清除 User Profile 级别设置，使其继承 Domain 默认值。
#
# 使用:
#   ./set-user-download-access.sh <user_profile_name> <enable|disable|reset>
#
# 示例:
#   ./set-user-download-access.sh profile-data-fraud-alice enable   (允许下载)
#   ./set-user-download-access.sh profile-data-fraud-alice disable  (禁止下载)
#   ./set-user-download-access.sh profile-data-fraud-alice reset    (跟随全局)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"
source "${SCRIPT_DIR}/../../lib/sagemaker-factory.sh"

# =============================================================================
# 参数解析
# =============================================================================

USER_PROFILE=$1
ACTION=$2

if [[ -z "$USER_PROFILE" ]] || [[ -z "$ACTION" ]]; then
    echo "Usage: $0 <user_profile_name> <enable|disable|reset>"
    echo ""
    echo "Actions:"
    echo "  enable  - 允许下载 (移除 LCC)"
    echo "  disable - 禁止下载 (强制绑定 LCC)"
    echo "  reset   - 重置设置 (继承 Domain 默认值)"
    exit 1
fi

# 验证 Action
if [[ "$ACTION" != "enable" && "$ACTION" != "disable" && "$ACTION" != "reset" ]]; then
    log_error "Invalid action: $ACTION. Use 'enable', 'disable', or 'reset'."
    exit 1
fi

init_script() {
    load_env
    check_aws_cli
    get_domain_id
}

# =============================================================================
# 主逻辑
# =============================================================================

main() {
    init_script
    
    echo ""
    echo "=============================================="
    echo " 管理用户下载权限: $USER_PROFILE"
    echo "=============================================="
    echo "Action: $ACTION"
    echo "Domain: $DOMAIN_ID"
    echo ""

    # 1. 验证 User Profile 是否存在
    if ! sagemaker_profile_exists "$DOMAIN_ID" "$USER_PROFILE"; then
        log_error "User Profile not found: $USER_PROFILE"
        exit 1
    fi

    # 2. 准备配置数据
    local lcc_name="${TAG_PREFIX}-disable-download"
    local lcc_arn=""
    
    # 获取 LCC ARN (如果是 disable 操作需要)
    if [[ "$ACTION" == "disable" ]]; then
        lcc_arn=$(aws sagemaker list-studio-lifecycle-configs \
            --name-contains "$lcc_name" \
            --query "StudioLifecycleConfigs[?StudioLifecycleConfigName=='${lcc_name}'].StudioLifecycleConfigArn" \
            --output text \
            --region "$AWS_REGION")
            
        if [[ -z "$lcc_arn" || "$lcc_arn" == "None" ]]; then
            log_error "Lifecycle Config not found: $lcc_name"
            log_info "请先运行 scripts/04-sagemaker-domain/update-domain-config.sh 创建 LCC"
            exit 1
        fi
    fi

    # 3. 执行更新
    log_info "Updating User Profile..."
    
    local update_json=""

    if [[ "$ACTION" == "enable" ]]; then
        # Enable: 显式设置为空字符串，覆盖 Domain 的默认值
        # 注意: 即使 Domain 有 LCC，这里设为空也会生效 (用户级别优先级高)
        update_json='{
            "JupyterLabAppSettings": {
                "DefaultResourceSpec": {
                    "LifecycleConfigArn": ""
                },
                "LifecycleConfigArns": []
            }
        }'
        
    elif [[ "$ACTION" == "disable" ]]; then
        # Disable: 显式绑定 disable-download LCC
        update_json='{
            "JupyterLabAppSettings": {
                "DefaultResourceSpec": {
                    "LifecycleConfigArn": "'"${lcc_arn}"'"
                },
                "LifecycleConfigArns": ["'"${lcc_arn}"'"]
            }
        }'
        
    elif [[ "$ACTION" == "reset" ]]; then
        # Reset: 移除 UserSettings 中的 JupyterLabAppSettings 配置
        # 但 update-user-profile API 不支持直接"删除" key。
        # 这里的 reset 比较特殊：我们通常无法通过 CLI 简单地"unset"一个配置使其回退到 null。
        # AWS API 行为：如果传入 null 或空对象，有时并不意味着"继承 Domain"。
        # 
        # 最佳实践策略：
        # 对于 reset，我们可以将其设置为 "null" (如果 API 支持) 或者
        # 更稳妥的做法是：读取 Domain 的默认值，然后应用给用户 (Sync with Domain)。
        
        log_info "Fetching Domain defaults..."
        local domain_info=$(aws sagemaker describe-domain --domain-id "$DOMAIN_ID" --region "$AWS_REGION")
        local domain_lcc=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.LifecycleConfigArn // ""')
        
        if [[ -n "$domain_lcc" ]]; then
            update_json='{
                "JupyterLabAppSettings": {
                    "DefaultResourceSpec": {
                        "LifecycleConfigArn": "'"${domain_lcc}"'"
                    },
                    "LifecycleConfigArns": ["'"${domain_lcc}"'"]
                }
            }'
            log_info "Resetting to Domain default (DISABLED)"
        else
            update_json='{
                "JupyterLabAppSettings": {
                    "DefaultResourceSpec": {
                        "LifecycleConfigArn": ""
                    },
                    "LifecycleConfigArns": []
                }
            }'
            log_info "Resetting to Domain default (ENABLED)"
        fi
    fi

    # 4. 调用 API
    if aws sagemaker update-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$USER_PROFILE" \
        --user-settings "$update_json" \
        --region "$AWS_REGION" > /dev/null; then
        
        log_success "Update successful!"
        echo ""
        echo "⚠️  注意: 用户必须【重启】JupyterLab Space 才能生效。"
        echo "   (File -> Shut Down -> Shut Down All Kernels and Terminals -> Restart Server)"
    else
        log_error "Update failed."
        exit 1
    fi
}

main

