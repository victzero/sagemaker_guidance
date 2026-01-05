#!/bin/bash
# =============================================================================
# verify.sh - 验证 SageMaker Domain 配置
# =============================================================================
# 使用场景:
#   1. 创建后验证: ./verify.sh
#   2. 详细模式: ./verify.sh --verbose
#   3. JSON 输出: ./verify.sh --json
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

# 只加载环境，不执行完整 init（避免重复验证）
load_env
validate_base_env
export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
export DOMAIN_NAME="${DOMAIN_NAME:-${COMPANY}-ml-platform}"
export IDLE_TIMEOUT_MINUTES="${IDLE_TIMEOUT_MINUTES:-60}"
export AWS_PAGER=""

# -----------------------------------------------------------------------------
# 颜色和计数器
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

errors=0
warnings=0

# -----------------------------------------------------------------------------
# 辅助函数
# -----------------------------------------------------------------------------
log_ok()      { echo -e "${GREEN}  ✓${NC} $1"; }
log_fail()    { echo -e "${RED}  ✗${NC} $1"; ((errors++)) || true; }
log_warn()    { echo -e "${YELLOW}  !${NC} $1"; ((warnings++)) || true; }
log_info()    { echo -e "    $1"; }
log_section() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# -----------------------------------------------------------------------------
# 验证 Domain 状态
# -----------------------------------------------------------------------------
verify_domain() {
    log_section "SageMaker Domain"
    
    # 查找 Domain
    DOMAIN_ID=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
        log_fail "Domain not found: $DOMAIN_NAME"
        log_info "请运行 ./setup-all.sh 创建 Domain"
        return 1
    fi
    
    # 获取 Domain 详情
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    local status=$(echo "$domain_info" | jq -r '.Status // "Unknown"')
    local auth_mode=$(echo "$domain_info" | jq -r '.AuthMode // "Unknown"')
    local network_mode=$(echo "$domain_info" | jq -r '.AppNetworkAccessType // "Unknown"')
    local vpc_id=$(echo "$domain_info" | jq -r '.VpcId // "Unknown"')
    local efs_id=$(echo "$domain_info" | jq -r '.HomeEfsFileSystemId // "Unknown"')
    
    # 检查状态
    if [[ "$status" == "InService" ]]; then
        log_ok "Domain: $DOMAIN_NAME ($DOMAIN_ID)"
    else
        log_fail "Domain 状态异常: $status (expected: InService)"
        return 1
    fi
    
    # 显示配置
    log_info "Status:       $status"
    log_info "Auth Mode:    $auth_mode"
    log_info "Network Mode: $network_mode"
    log_info "VPC:          $vpc_id"
    log_info "EFS:          $efs_id"
    
    # 验证配置是否符合最佳实践
    if [[ "$auth_mode" != "IAM" ]]; then
        log_warn "Auth Mode: $auth_mode (推荐: IAM)"
    fi
    
    if [[ "$network_mode" != "VpcOnly" ]]; then
        log_warn "Network Mode: $network_mode (推荐: VpcOnly)"
    fi
    
    # 导出供后续函数使用
    export DOMAIN_INFO="$domain_info"
}

# -----------------------------------------------------------------------------
# 验证内置 Idle Shutdown（替代旧的 Lifecycle Config）
# -----------------------------------------------------------------------------
verify_idle_shutdown() {
    log_section "Idle Shutdown 配置"
    
    if [[ -z "$DOMAIN_INFO" ]]; then
        log_fail "Domain 信息不可用"
        return 1
    fi
    
    # 获取 Idle Shutdown 配置
    local idle_settings=$(echo "$DOMAIN_INFO" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings // {}')
    local idle_enabled=$(echo "$idle_settings" | jq -r '.LifecycleManagement // "DISABLED"')
    local idle_timeout=$(echo "$idle_settings" | jq -r '.IdleTimeoutInMinutes // 0')
    
    # 检查是否启用
    if [[ "$idle_enabled" == "ENABLED" ]]; then
        log_ok "内置 Idle Shutdown: 已启用"
        
        # 检查超时时间
        if [[ "$idle_timeout" -eq "$IDLE_TIMEOUT_MINUTES" ]]; then
            log_ok "Idle Timeout: ${idle_timeout} 分钟"
        else
            log_warn "Idle Timeout: ${idle_timeout} 分钟 (配置: ${IDLE_TIMEOUT_MINUTES})"
        fi
    else
        log_fail "内置 Idle Shutdown: 未启用"
        log_info "修复: ./fix-lifecycle-config.sh"
    fi
    
    # 检查是否残留旧的自定义 Lifecycle Config
    local lcc_arn=$(echo "$DOMAIN_INFO" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.LifecycleConfigArn // ""')
    local lcc_list=$(echo "$DOMAIN_INFO" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.LifecycleConfigArns // []')
    
    if [[ -n "$lcc_arn" && "$lcc_arn" != "null" ]]; then
        log_warn "发现旧的自定义 Lifecycle Config: $lcc_arn"
        log_info "建议移除: ./fix-lifecycle-config.sh"
    elif [[ "$lcc_list" != "[]" && "$lcc_list" != "null" ]]; then
        log_warn "发现旧的 Lifecycle Config 列表"
        log_info "建议移除: ./fix-lifecycle-config.sh"
    else
        log_ok "无自定义 Lifecycle Config (推荐)"
    fi
}

# -----------------------------------------------------------------------------
# 验证 Execution Role
# -----------------------------------------------------------------------------
verify_execution_role() {
    log_section "Execution Role"
    
    if [[ -z "$DOMAIN_INFO" ]]; then
        log_fail "Domain 信息不可用"
        return 1
    fi
    
    # 获取 Default Execution Role
    local default_role=$(echo "$DOMAIN_INFO" | jq -r '.DefaultUserSettings.ExecutionRole // ""')
    
    if [[ -z "$default_role" || "$default_role" == "null" ]]; then
        log_fail "未配置 Default Execution Role"
        return 1
    fi
    
    log_ok "Default Execution Role 已配置"
    log_info "ARN: $default_role"
    
    # 提取 Role 名称
    local role_name=$(echo "$default_role" | sed 's|.*role/||')
    
    # 验证 Role 是否存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_ok "Role 存在: $role_name"
        
        # 检查信任策略
        local trust=$(aws iam get-role --role-name "$role_name" \
            --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' \
            --output text 2>/dev/null)
        
        if [[ "$trust" == *"sagemaker"* ]]; then
            log_ok "信任策略正确 (sagemaker.amazonaws.com)"
        else
            log_warn "信任策略可能不正确: $trust"
        fi
    else
        log_fail "Role 不存在: $role_name"
        log_info "检查 Role ARN 路径是否正确（不应包含 IAM Path）"
        log_info "修复: ./fix-execution-roles.sh"
    fi
    
    # 检查是否使用了带 Path 的 ARN（常见问题）
    if echo "$default_role" | grep -qE "role/[^/]+/"; then
        log_warn "Execution Role ARN 包含 Path"
        log_info "当前: $default_role"
        log_info "可能导致 SageMaker 无法 assume role"
        log_info "修复: ./fix-execution-roles.sh"
    fi
}

# -----------------------------------------------------------------------------
# 验证 EFS 加密
# -----------------------------------------------------------------------------
verify_efs() {
    log_section "EFS 存储"
    
    if [[ -z "$DOMAIN_INFO" ]]; then
        log_fail "Domain 信息不可用"
        return 1
    fi
    
    local efs_id=$(echo "$DOMAIN_INFO" | jq -r '.HomeEfsFileSystemId // ""')
    
    if [[ -z "$efs_id" || "$efs_id" == "null" ]]; then
        log_warn "未找到 EFS 文件系统"
        return 0
    fi
    
    # 获取 EFS 详情
    local efs_info=$(aws efs describe-file-systems \
        --file-system-id "$efs_id" \
        --query 'FileSystems[0]' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    if [[ -z "$efs_info" || "$efs_info" == "{}" ]]; then
        log_warn "无法获取 EFS 信息"
        return 0
    fi
    
    local encrypted=$(echo "$efs_info" | jq -r '.Encrypted // false')
    local lifecycle_state=$(echo "$efs_info" | jq -r '.LifeCycleState // "Unknown"')
    local size_bytes=$(echo "$efs_info" | jq -r '.SizeInBytes.Value // 0')
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    log_ok "EFS: $efs_id"
    log_info "状态: $lifecycle_state"
    log_info "大小: ${size_gb} GB"
    
    # 检查加密
    if [[ "$encrypted" == "true" ]]; then
        log_ok "加密: 已启用"
    else
        log_warn "加密: 未启用 (建议启用静态加密)"
    fi
}

# -----------------------------------------------------------------------------
# 验证 Space 默认设置
# -----------------------------------------------------------------------------
verify_space_settings() {
    log_section "Space 默认设置"
    
    if [[ -z "$DOMAIN_INFO" ]]; then
        log_fail "Domain 信息不可用"
        return 1
    fi
    
    # 获取 Default Space Settings
    local space_role=$(echo "$DOMAIN_INFO" | jq -r '.DefaultSpaceSettings.ExecutionRole // ""')
    
    if [[ -n "$space_role" && "$space_role" != "null" ]]; then
        log_ok "Space Execution Role 已配置"
        log_info "ARN: $space_role"
    else
        log_warn "Space Execution Role 未配置"
    fi
    
    # 检查 JupyterLab 默认配置
    local default_instance=$(echo "$DOMAIN_INFO" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.InstanceType // "未配置"')
    log_info "JupyterLab 默认实例: $default_instance"
}

# -----------------------------------------------------------------------------
# 打印总结
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "=============================================="
    
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${GREEN}✓ 验证通过${NC} - Domain 配置正确"
    elif [[ $errors -eq 0 ]]; then
        echo -e "${YELLOW}! 验证完成${NC} - 有 $warnings 个警告"
    else
        echo -e "${RED}✗ 验证失败${NC} - $errors 个错误, $warnings 个警告"
    fi
    
    echo "=============================================="
    echo ""
    echo "常用命令:"
    echo "  aws sagemaker describe-domain --domain-id $DOMAIN_ID"
    echo "  aws sagemaker list-user-profiles --domain-id $DOMAIN_ID"
    echo ""
    
    if [[ $errors -gt 0 ]]; then
        echo "修复脚本:"
        echo "  ./fix-lifecycle-config.sh  # 修复 Idle Shutdown 配置"
        echo "  ./fix-execution-roles.sh   # 修复 Execution Role ARN"
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    local verbose=false
    local json_output=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                verbose=true
                shift
                ;;
            --json|-j)
                json_output=true
                shift
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --verbose, -v  详细输出"
                echo "  --json, -j     JSON 格式输出"
                echo "  --help, -h     显示帮助"
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}=============================================="
    echo " SageMaker Domain Verification"
    echo "==============================================${NC}"
    
    # 执行验证
    verify_domain
    
    # 仅在 Domain 验证通过后继续
    if [[ $errors -eq 0 ]]; then
        verify_idle_shutdown
        verify_execution_role
        verify_efs
        verify_space_settings
    fi
    
    # 打印总结
    print_summary
    
    exit $errors
}

main "$@"
