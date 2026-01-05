#!/bin/bash
# =============================================================================
# 05-bind-policies.sh - 绑定 Policies 到 Groups
# =============================================================================
# 使用方法: ./05-bind-policies.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 绑定 Policy 到 Group 函数
# -----------------------------------------------------------------------------
attach_policy_to_group() {
    local group_name=$1
    local policy_arn=$2
    
    log_info "Attaching policy to group: $group_name"
    log_info "  Policy: $policy_arn"
    
    # 检查是否已绑定
    local attached=$(aws iam list-attached-group-policies \
        --group-name "$group_name" \
        --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy already attached to $group_name, skipping..."
        return 0
    fi
    
    aws iam attach-group-policy \
        --group-name "$group_name" \
        --policy-arn "$policy_arn"
    
    log_success "Policy attached to $group_name"
}

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
    log_info "Binding admin group policies..."
    attach_policy_to_group "sagemaker-admins" \
        "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
    attach_policy_to_group "sagemaker-admins" \
        "${policy_prefix}SageMaker-User-SelfService"
    
    # 2. 绑定只读 Group 策略
    log_info "Binding readonly group policies..."
    attach_policy_to_group "sagemaker-readonly" \
        "${policy_prefix}SageMaker-ReadOnly-Access"
    attach_policy_to_group "sagemaker-readonly" \
        "${policy_prefix}SageMaker-User-SelfService"
    
    # 3. 绑定团队 Group 策略
    log_info "Binding team group policies..."
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        local group_name="sagemaker-${team_fullname}"
        
        # AWS 托管策略 - 完整 SageMaker 权限
        attach_policy_to_group "$group_name" \
            "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        # 基础访问策略
        attach_policy_to_group "$group_name" \
            "${policy_prefix}SageMaker-Studio-Base-Access"
        
        # 用户自服务策略（修改密码、MFA、Access Key）
        attach_policy_to_group "$group_name" \
            "${policy_prefix}SageMaker-User-SelfService"
        
        # 团队访问策略（S3 bucket 权限）
        attach_policy_to_group "$group_name" \
            "${policy_prefix}SageMaker-${team_capitalized}-Team-Access"
    done
    
    # 4. 绑定项目 Group 策略
    log_info "Binding project group policies..."
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local group_name="sagemaker-${team}-${project}"
            
            # 项目访问策略 (Space, UserProfile)
            attach_policy_to_group "$group_name" \
                "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-Access"
            
            # 共享策略 - Deny Admin Actions (安全限制)
            attach_policy_to_group "$group_name" \
                "${policy_prefix}SageMaker-Shared-DenyAdmin"
            
            # 共享策略 - S3 项目访问 (与 Execution Role 共用)
            attach_policy_to_group "$group_name" \
                "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-S3Access"
            
            # 共享策略 - PassRole 到项目角色
            attach_policy_to_group "$group_name" \
                "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-PassRole"
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
