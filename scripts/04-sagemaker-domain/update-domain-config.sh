#!/bin/bash
# =============================================================================
# update-domain-config.sh - 更新 Domain 配置 (LCC + Idle Shutdown)
# =============================================================================
#
# 功能:
#   1. 部署/更新 "disable-download" Lifecycle Config
#   2. 更新 Domain 默认配置：
#      - 启用 disable-download LCC
#      - 启用内置 Idle Shutdown
#
# 使用:
#   ./update-domain-config.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"
source "${SCRIPT_DIR}/../lib/sagemaker-factory.sh"

init

# =============================================================================
# 全局变量
# =============================================================================
DOMAIN_ID=""
CURRENT_LCC_ARN=""
CURRENT_IDLE_SETTINGS=""
EXPECTED_LCC_ARN=""
LCC_NAME="${TAG_PREFIX}-disable-download"
LCC_SCRIPT="${SCRIPT_DIR}/lifecycle-scripts/disable-download.sh"

# =============================================================================
# 辅助函数
# =============================================================================

print_separator() {
    echo "────────────────────────────────────────────────────────────────────────────────"
}

# =============================================================================
# 准备 Lifecycle Config
# =============================================================================

prepare_lcc() {
    echo ""
    log_info "检查/部署 Lifecycle Config: $LCC_NAME"
    
    if [[ ! -f "$LCC_SCRIPT" ]]; then
        log_error "LCC 脚本未找到: $LCC_SCRIPT"
        exit 1
    fi
    
    EXPECTED_LCC_ARN=$(create_lifecycle_config "$LCC_NAME" "$LCC_SCRIPT" "JupyterLab")
}

# =============================================================================
# 扫描当前配置
# =============================================================================

scan_current_config() {
    echo ""
    echo "=============================================="
    echo " 扫描当前配置"
    echo "=============================================="
    echo ""
    
    # 获取 Domain ID
    get_domain_id
    
    log_info "Domain ID: $DOMAIN_ID"
    
    # 获取当前配置
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION")
    
    CURRENT_LCC_ARN=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.LifecycleConfigArn // ""')
    CURRENT_IDLE_SETTINGS=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings // {}')
    
    local current_idle_enabled=$(echo "$CURRENT_IDLE_SETTINGS" | jq -r '.LifecycleManagement // "DISABLED"')
    local current_idle_timeout=$(echo "$CURRENT_IDLE_SETTINGS" | jq -r '.IdleTimeoutInMinutes // "N/A"')
}

# =============================================================================
# 显示变更计划
# =============================================================================

show_changes_plan() {
    echo ""
    echo "=============================================="
    echo " 变更计划"
    echo "=============================================="
    echo ""
    
    local current_idle_enabled=$(echo "$CURRENT_IDLE_SETTINGS" | jq -r '.LifecycleManagement // "DISABLED"')
    local current_idle_timeout=$(echo "$CURRENT_IDLE_SETTINGS" | jq -r '.IdleTimeoutInMinutes // "N/A"')
    
    echo "【Domain: $DOMAIN_ID】"
    print_separator
    printf "| %-30s | %-50s |\n" "配置项" "当前值"
    print_separator
    printf "| %-30s | %-50s |\n" "Lifecycle Config (Disable DL)" "${CURRENT_LCC_ARN:-无}"
    printf "| %-30s | %-50s |\n" "期望 Lifecycle Config" "$EXPECTED_LCC_ARN"
    print_separator
    printf "| %-30s | %-50s |\n" "内置 Idle Shutdown" "$current_idle_enabled ($current_idle_timeout min)"
    printf "| %-30s | %-50s |\n" "期望 Idle Shutdown" "ENABLED (${IDLE_TIMEOUT_MINUTES} min)"
    print_separator
    echo ""
    
    # 检查是否需要修复
    local need_fix=false
    
    if [[ "$CURRENT_LCC_ARN" != "$EXPECTED_LCC_ARN" ]]; then
        log_warn "需要更新 Lifecycle Config"
        need_fix=true
    fi
    
    if [[ "$current_idle_enabled" != "ENABLED" ]] || [[ "$current_idle_timeout" != "$IDLE_TIMEOUT_MINUTES" ]]; then
        log_warn "需要更新 Idle Shutdown 配置"
        need_fix=true
    fi
    
    if [[ "$need_fix" == "false" ]]; then
        echo ""
        log_success "配置已经是最佳状态，无需变更！"
        return 1
    fi
    
    return 0
}

# =============================================================================
# 执行更新
# =============================================================================

execute_update() {
    echo ""
    echo "=============================================="
    echo " 执行更新"
    echo "=============================================="
    echo ""
    
    log_info "更新 Domain 配置..."
    
    # 更新 Domain Settings
    # 1. 设置 DefaultResourceSpec.LifecycleConfigArn (默认选中)
    # 2. 设置 LifecycleConfigArns (允许列表)
    # 3. 设置 Idle Shutdown
    
    if aws sagemaker update-domain \
        --domain-id "$DOMAIN_ID" \
        --default-user-settings '{
            "JupyterLabAppSettings": {
                "DefaultResourceSpec": {
                    "LifecycleConfigArn": "'"${EXPECTED_LCC_ARN}"'"
                },
                "LifecycleConfigArns": ["'"${EXPECTED_LCC_ARN}"'"],
                "AppLifecycleManagement": {
                    "IdleSettings": {
                        "LifecycleManagement": "ENABLED",
                        "IdleTimeoutInMinutes": '"${IDLE_TIMEOUT_MINUTES}"'
                    }
                }
            }
        }' \
        --region "$AWS_REGION"; then
        log_success "Domain 配置更新成功"
        return 0
    else
        log_error "Domain 配置更新失败"
        return 1
    fi
}

# =============================================================================
# 验证结果
# =============================================================================

verify_result() {
    echo ""
    echo "=============================================="
    echo " 验证结果"
    echo "=============================================="
    echo ""
    
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION")
    
    local new_lcc=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.LifecycleConfigArn // ""')
    local new_idle_enabled=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings.LifecycleManagement // "DISABLED"')
    
    local all_ok=true
    
    # 验证 LCC
    if [[ "$new_lcc" == "$EXPECTED_LCC_ARN" ]]; then
        log_success "Lifecycle Config: 已更新 ✓"
    else
        log_error "Lifecycle Config: 不匹配 ✗ (Got: $new_lcc)"
        all_ok=false
    fi
    
    # 验证 Idle Shutdown
    if [[ "$new_idle_enabled" == "ENABLED" ]]; then
        log_success "Idle Shutdown: 已启用 ✓"
    else
        log_error "Idle Shutdown: 未启用 ✗"
        all_ok=false
    fi
    
    echo ""
    if [[ "$all_ok" == "true" ]]; then
        log_success "所有配置更新完成！"
    else
        log_error "部分配置更新失败"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║           SageMaker Domain 配置更新                                           ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "此脚本将强制应用以下安全/成本配置："
    echo "  1. 禁用文件下载 (Lifecycle Config: disable-download)"
    echo "  2. 自动闲置关机 (Idle Shutdown: ${IDLE_TIMEOUT_MINUTES} min)"
    echo ""
    
    # 准备 LCC
    prepare_lcc
    
    # 扫描当前配置
    scan_current_config
    
    # 显示变更计划
    if ! show_changes_plan; then
        exit 0
    fi
    
    # 确认执行
    echo ""
    echo -e "${YELLOW}是否执行以上变更？${NC}"
    read -p "输入 'yes' 确认执行: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo ""
        log_info "已取消操作"
        exit 0
    fi
    
    # 执行更新
    execute_update
    
    # 验证结果
    verify_result
    
    echo ""
    echo "=============================================="
    echo " 注意事项"
    echo "=============================================="
    echo ""
    echo "  1. 对于已运行的 App，需重启后生效。"
    echo "  2. 现有 User Profile 如果覆盖了 JupyterLabAppSettings，可能需要手动更新。"
    echo "     (默认情况下 User Profile 继承 Domain 设置)"
    echo ""
}

main
