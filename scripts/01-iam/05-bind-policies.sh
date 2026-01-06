#!/bin/bash
# =============================================================================
# 05-bind-policies.sh - 绑定 Policies 到 Groups
# =============================================================================
# 使用方法: ./05-bind-policies.sh
#
# 注意: attach_policy_to_group(), bind_team_policies(), bind_policies_to_project_group()
#       已移至 lib/iam-core.sh 统一维护
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 加载核心函数库 (复用 lib/ 中的绑定函数)
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Binding Policies to Groups"
    echo "=============================================="
    echo ""
    
    local policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    # 1. 绑定管理员 Group 策略
    log_step "Binding admin group policies..."
    attach_policy_to_group "sagemaker-admins" \
        "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
    attach_policy_to_group "sagemaker-admins" \
        "${policy_prefix}SageMaker-User-SelfService"
    echo ""
    
    # 2. 绑定只读 Group 策略
    log_step "Binding readonly group policies..."
    attach_policy_to_group "sagemaker-readonly" \
        "${policy_prefix}SageMaker-ReadOnly-Access"
    attach_policy_to_group "sagemaker-readonly" \
        "${policy_prefix}SageMaker-User-SelfService"
    echo ""
    
    # 3. 绑定团队 Group 策略 (使用 lib 函数)
    log_step "Binding team group policies..."
    for team in $TEAMS; do
        bind_team_policies "$team"
        echo ""
    done
    
    # 4. 绑定项目 Group 策略 (使用 lib 函数)
    log_step "Binding project group policies..."
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            bind_policies_to_project_group "$team" "$project"
            echo ""
        done
    done
    
    echo ""
    log_success "All policies bound to groups successfully!"
    echo ""
    
    # 显示绑定关系
    echo "Policy Bindings Summary:"
    echo "========================"
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        echo ""
        echo "Team: $team_fullname"
        aws iam list-attached-group-policies \
            --group-name "sagemaker-${team_fullname}" \
            --query 'AttachedPolicies[].PolicyName' --output table 2>/dev/null || true
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            echo ""
            echo "Project: $team/$project"
            aws iam list-attached-group-policies \
                --group-name "sagemaker-${team}-${project}" \
                --query 'AttachedPolicies[].PolicyName' --output table 2>/dev/null || true
        done
    done
}

main
