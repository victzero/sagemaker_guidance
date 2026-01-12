#!/bin/bash
# =============================================================================
# set-instance-whitelist.sh - 管理项目的实例类型白名单
# =============================================================================
#
# 功能:
#   设置项目在 SageMaker Studio 中可使用的实例类型白名单
#   防止用户启动高成本或未授权的实例类型
#
# 使用:
#   ./set-instance-whitelist.sh <team> <project> <action> [args]
#
# Actions:
#   preset <name>     使用预设白名单 (default/gpu/large_memory/high_performance/unrestricted)
#   custom <types>    自定义实例类型列表 (逗号分隔)
#   show              显示当前配置
#   reset             重置为 .env.shared 中的初始配置
#
# 示例:
#   ./set-instance-whitelist.sh rc fraud preset gpu          # 升级到 GPU 预设
#   ./set-instance-whitelist.sh rc fraud preset default      # 降级回默认预设
#   ./set-instance-whitelist.sh rc fraud preset unrestricted # 移除限制
#   ./set-instance-whitelist.sh rc fraud custom "ml.t3.medium,ml.p3.2xlarge,system"
#   ./set-instance-whitelist.sh rc fraud show                # 查看当前配置
#   ./set-instance-whitelist.sh rc fraud reset               # 重置到初始配置
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# =============================================================================
# 使用帮助
# =============================================================================
print_usage() {
    echo ""
    echo "Usage: $0 <team> <project> <action> [args]"
    echo ""
    echo "Actions:"
    echo "  preset <name>     使用预设白名单"
    echo "                    可用预设: default, gpu, large_memory, high_performance, unrestricted"
    echo "  custom <types>    自定义实例类型列表 (逗号分隔, 必须包含 'system')"
    echo "  show              显示当前配置"
    echo "  reset             重置为 .env.shared 中的初始配置"
    echo ""
    echo "Examples:"
    echo "  $0 rc fraud preset gpu"
    echo "  $0 rc fraud preset default"
    echo "  $0 rc fraud preset unrestricted"
    echo "  $0 rc fraud custom \"ml.t3.medium,ml.p3.2xlarge,system\""
    echo "  $0 rc fraud show"
    echo "  $0 rc fraud reset"
    echo ""
    echo "Available presets:"
    print_preset_details
    exit 1
}

# =============================================================================
# 参数解析
# =============================================================================
TEAM=$1
PROJECT=$2
ACTION=$3
ARG=$4

if [[ -z "$TEAM" ]] || [[ -z "$PROJECT" ]] || [[ -z "$ACTION" ]]; then
    print_usage
fi

# =============================================================================
# 验证团队和项目
# =============================================================================
validate_team_project() {
    local team=$1
    local project=$2
    
    # 检查团队是否存在
    local team_fullname=$(get_team_fullname "$team")
    if [[ -z "$team_fullname" ]]; then
        log_error "Unknown team: $team"
        log_info "Available teams: $TEAMS"
        exit 1
    fi
    
    # 检查项目是否存在 (通过检查 Execution Role)
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_error "Project not found or Execution Role does not exist: $team/$project"
        log_info "Expected role: $role_name"
        exit 1
    fi
}

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_silent
    
    echo ""
    echo "=============================================="
    echo " 实例类型白名单管理"
    echo "=============================================="
    echo "Team:    $TEAM"
    echo "Project: $PROJECT"
    echo "Action:  $ACTION"
    echo ""
    
    # 验证团队和项目
    validate_team_project "$TEAM" "$PROJECT"
    
    local team_fullname=$(get_team_fullname "$TEAM")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$PROJECT")
    
    case "$ACTION" in
        preset)
            if [[ -z "$ARG" ]]; then
                log_error "Missing preset name"
                echo ""
                echo "Available presets: $(get_available_presets)"
                exit 1
            fi
            
            if ! validate_preset_name "$ARG"; then
                log_error "Invalid preset name: $ARG"
                echo ""
                echo "Available presets: $(get_available_presets)"
                exit 1
            fi
            
            # 显示变更预览
            local current=$(get_current_whitelist "$TEAM" "$PROJECT")
            local new_types=$(get_preset_instance_types "$ARG")
            
            print_changes_header "更新实例类型白名单"
            echo ""
            echo "Team/Project:  $TEAM / $PROJECT"
            echo "Current:       $current"
            echo "New Preset:    $ARG"
            if [[ -n "$new_types" ]]; then
                echo "New Types:     $new_types"
            else
                echo "New Types:     (unrestricted - no limits)"
            fi
            echo ""
            
            if ! print_confirm_prompt; then
                log_info "Cancelled."
                exit 0
            fi
            
            update_project_whitelist_preset "$TEAM" "$PROJECT" "$ARG"
            
            echo ""
            log_success "实例类型白名单已更新!"
            echo ""
            echo "📌 注意事项:"
            echo "   • 新配置立即生效"
            echo "   • 已运行的 Space 不受影响"
            echo "   • 用户下次启动 Space 时将应用新限制"
            ;;
            
        custom)
            if [[ -z "$ARG" ]]; then
                log_error "Missing instance types list"
                echo ""
                echo "Example: $0 $TEAM $PROJECT custom \"ml.t3.medium,ml.m5.xlarge,system\""
                exit 1
            fi
            
            # 验证实例类型
            if ! validate_instance_types "$ARG"; then
                log_error "Invalid instance types in list"
                exit 1
            fi
            
            # 检查是否包含 system
            if [[ ! "$ARG" =~ "system" ]]; then
                log_warn "Warning: 'system' not included in list"
                log_warn "JupyterLab default app may not work without 'system'"
                echo ""
                read -p "Continue anyway? [y/N]: " response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    log_info "Cancelled. Add 'system' to your list."
                    exit 0
                fi
            fi
            
            # 显示变更预览
            local current=$(get_current_whitelist "$TEAM" "$PROJECT")
            
            print_changes_header "更新实例类型白名单 (自定义)"
            echo ""
            echo "Team/Project:  $TEAM / $PROJECT"
            echo "Current:       $current"
            echo "New Types:     $ARG"
            echo ""
            
            if ! print_confirm_prompt; then
                log_info "Cancelled."
                exit 0
            fi
            
            update_project_whitelist_custom "$TEAM" "$PROJECT" "$ARG"
            
            echo ""
            log_success "实例类型白名单已更新!"
            ;;
            
        show)
            local current=$(get_current_whitelist "$TEAM" "$PROJECT")
            local preset=$(get_project_whitelist_preset "$TEAM" "$PROJECT")
            local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
            local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
            
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "项目实例类型白名单配置"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Team:           $TEAM ($(get_team_fullname "$TEAM"))"
            echo "Project:        $PROJECT"
            echo ""
            echo "Initial Preset: $preset"
            echo "Current Config: $current"
            echo ""
            
            # 检查策略是否存在
            if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
                echo "Policy ARN:     $policy_arn"
                local version=$(aws iam get-policy --policy-arn "$policy_arn" \
                    --query 'Policy.DefaultVersionId' --output text 2>/dev/null)
                echo "Policy Version: $version"
            else
                echo "Policy Status:  Not created (unrestricted)"
            fi
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
            
        reset)
            local current=$(get_current_whitelist "$TEAM" "$PROJECT")
            local preset=$(get_project_whitelist_preset "$TEAM" "$PROJECT")
            local preset_types=$(get_preset_instance_types "$preset")
            
            print_changes_header "重置实例类型白名单"
            echo ""
            echo "Team/Project:   $TEAM / $PROJECT"
            echo "Current:        $current"
            echo "Reset To:       $preset (from .env.shared)"
            if [[ -n "$preset_types" ]]; then
                echo "Reset Types:    $preset_types"
            else
                echo "Reset Types:    (unrestricted)"
            fi
            echo ""
            
            if ! print_confirm_prompt; then
                log_info "Cancelled."
                exit 0
            fi
            
            reset_project_whitelist "$TEAM" "$PROJECT"
            
            echo ""
            log_success "实例类型白名单已重置!"
            ;;
            
        *)
            log_error "Unknown action: $ACTION"
            print_usage
            ;;
    esac
}

main

