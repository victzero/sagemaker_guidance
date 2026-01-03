#!/bin/bash
# =============================================================================
# fix-lifecycle-config.sh - 移除自定义 Lifecycle Config，启用内置 Idle Shutdown
# =============================================================================
#
# 背景:
#   旧版本脚本使用自定义 Lifecycle Config 实现自动关机功能。
#   但自定义脚本可能因环境差异导致失败。
#   
#   新版 SageMaker Studio 已内置 Idle Shutdown 功能，更稳定可靠。
#   此脚本用于将已创建的 Domain 从自定义 LCC 迁移到内置功能。
#
# 使用:
#   ./fix-lifecycle-config.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# =============================================================================
# 全局变量
# =============================================================================
DOMAIN_ID=""
CURRENT_LCC_ARN=""
CURRENT_IDLE_SETTINGS=""

# =============================================================================
# 辅助函数
# =============================================================================

print_separator() {
    echo "────────────────────────────────────────────────────────────────────────────────"
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
    DOMAIN_ID=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
        log_error "未找到 Domain: $DOMAIN_NAME"
        exit 1
    fi
    
    log_info "找到 Domain: $DOMAIN_ID"
    
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
    printf "| %-30s | %-50s |\n" "配置项" "值"
    print_separator
    printf "| %-30s | %-50s |\n" "自定义 Lifecycle Config (当前)" "${CURRENT_LCC_ARN:-无}"
    printf "| %-30s | %-50s |\n" "自定义 Lifecycle Config (修复后)" "移除"
    print_separator
    printf "| %-30s | %-50s |\n" "内置 Idle Shutdown (当前)" "$current_idle_enabled ($current_idle_timeout min)"
    printf "| %-30s | %-50s |\n" "内置 Idle Shutdown (修复后)" "ENABLED (${IDLE_TIMEOUT_MINUTES} min)"
    print_separator
    echo ""
    
    # 检查是否需要修复
    local need_fix=false
    
    if [[ -n "$CURRENT_LCC_ARN" && "$CURRENT_LCC_ARN" != "null" ]]; then
        log_warn "需要移除自定义 Lifecycle Config"
        need_fix=true
    fi
    
    if [[ "$current_idle_enabled" != "ENABLED" ]] || [[ "$current_idle_timeout" != "$IDLE_TIMEOUT_MINUTES" ]]; then
        log_warn "需要配置内置 Idle Shutdown"
        need_fix=true
    fi
    
    if [[ "$need_fix" == "false" ]]; then
        echo ""
        log_success "配置已经是最佳状态，无需修复！"
        return 1
    fi
    
    return 0
}

# =============================================================================
# 执行修复
# =============================================================================

execute_fix() {
    echo ""
    echo "=============================================="
    echo " 执行修复"
    echo "=============================================="
    echo ""
    
    log_info "更新 Domain 配置..."
    
    # 移除自定义 LCC，启用内置 Idle Shutdown
    if aws sagemaker update-domain \
        --domain-id "$DOMAIN_ID" \
        --default-user-settings '{
            "JupyterLabAppSettings": {
                "DefaultResourceSpec": {},
                "LifecycleConfigArns": [],
                "AppLifecycleManagement": {
                    "IdleSettings": {
                        "LifecycleManagement": "ENABLED",
                        "IdleTimeoutInMinutes": '"${IDLE_TIMEOUT_MINUTES}"'
                    }
                }
            }
        }' \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Domain 配置更新成功"
        return 0
    else
        log_error "Domain 配置更新失败"
        return 1
    fi
}

# =============================================================================
# 验证修复结果
# =============================================================================

verify_fix() {
    echo ""
    echo "=============================================="
    echo " 验证修复结果"
    echo "=============================================="
    echo ""
    
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION")
    
    local new_lcc=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.DefaultResourceSpec.LifecycleConfigArn // ""')
    local new_idle_enabled=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings.LifecycleManagement // "DISABLED"')
    local new_idle_timeout=$(echo "$domain_info" | jq -r '.DefaultUserSettings.JupyterLabAppSettings.AppLifecycleManagement.IdleSettings.IdleTimeoutInMinutes // 0')
    
    local all_ok=true
    
    # 验证 LCC 已移除
    if [[ -z "$new_lcc" || "$new_lcc" == "null" ]]; then
        log_success "自定义 Lifecycle Config: 已移除 ✓"
    else
        log_error "自定义 Lifecycle Config: 仍存在 ✗ ($new_lcc)"
        all_ok=false
    fi
    
    # 验证内置 Idle Shutdown
    if [[ "$new_idle_enabled" == "ENABLED" ]]; then
        log_success "内置 Idle Shutdown: 已启用 ✓"
    else
        log_error "内置 Idle Shutdown: 未启用 ✗"
        all_ok=false
    fi
    
    if [[ "$new_idle_timeout" == "$IDLE_TIMEOUT_MINUTES" ]]; then
        log_success "Idle Timeout: ${new_idle_timeout} 分钟 ✓"
    else
        log_warn "Idle Timeout: ${new_idle_timeout} 分钟 (期望: ${IDLE_TIMEOUT_MINUTES})"
    fi
    
    echo ""
    if [[ "$all_ok" == "true" ]]; then
        log_success "所有配置验证通过！"
    else
        log_error "部分配置验证失败"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║           修复 Lifecycle Config 配置                                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "此脚本将："
    echo "  1. 移除自定义 Lifecycle Config（可能导致启动失败）"
    echo "  2. 启用内置 Idle Shutdown（更稳定可靠）"
    echo ""
    echo "Idle Timeout: ${IDLE_TIMEOUT_MINUTES} 分钟"
    echo ""
    
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
    
    # 执行修复
    execute_fix
    
    # 验证结果
    verify_fix
    
    echo ""
    echo "=============================================="
    echo " 后续步骤"
    echo "=============================================="
    echo ""
    echo "  1. 刷新 SageMaker Studio 控制台页面"
    echo "  2. 重新启动 JupyterLab 应用"
    echo ""
}

main

