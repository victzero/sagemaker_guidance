#!/bin/bash
# =============================================================================
# 04-create-roles.sh - 创建 IAM Execution Roles
# =============================================================================
# 使用方法: ./04-create-roles.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# Trust Policy for SageMaker
# 参考: https://docs.aws.amazon.com/sagemaker/latest/dg/trustedidentitypropagation-setup.html
# 注意: sts:SetContext 是 Trusted Identity Propagation 必需的权限
# -----------------------------------------------------------------------------
generate_trust_policy() {
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:SetContext"
      ]
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 创建 Domain 默认 Execution Role
# -----------------------------------------------------------------------------
create_domain_default_role() {
    local role_name="SageMaker-Domain-DefaultExecutionRole"
    
    log_info "Creating Domain default execution role: $role_name"
    
    # 保存 trust policy
    local trust_policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
    generate_trust_policy > "$trust_policy_file"
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        # 确保 trust policy 正确（修复之前创建的 role）
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --path "${IAM_PATH}" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "Default execution role for SageMaker Domain" \
            --tags \
                "Key=Purpose,Value=DomainDefault" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        
        log_success "Role $role_name created"
    fi
    
    # 附加 AmazonSageMakerFullAccess 托管策略（Domain 默认需要）
    log_info "Attaching AmazonSageMakerFullAccess to domain default role..."
    
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "AmazonSageMakerFullAccess already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        log_success "AmazonSageMakerFullAccess attached to $role_name"
    fi
    
    # 输出 Role ARN 供后续使用
    echo ""
    log_info "Domain Default Execution Role ARN:"
    aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text
}

# -----------------------------------------------------------------------------
# 创建项目 Execution Role 函数
# -----------------------------------------------------------------------------
create_execution_role() {
    local team=$1
    local project=$2
    
    # 格式化名称 (risk-control -> RiskControl, project-a -> ProjectA)
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy"
    
    log_info "Creating execution role: $role_name"
    
    # 保存 trust policy
    local trust_policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
    generate_trust_policy > "$trust_policy_file"
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        # 确保 trust policy 正确（修复之前创建的 role）
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --path "${IAM_PATH}" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "SageMaker Execution Role for ${team}/${project}" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        
        log_success "Role $role_name created"
    fi
    
    # 附加项目自定义策略到 Role
    log_info "Attaching project policy to role..."
    
    # 检查策略是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy $policy_name already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
        
        log_success "Policy $policy_name attached to $role_name"
    fi
    
    # 附加 AmazonSageMakerFullAccess 托管策略（启用 Processing/Training/Inference）
    log_info "Attaching AmazonSageMakerFullAccess to role (for ML Jobs)..."
    
    local sm_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sm_attached" ]]; then
        log_warn "AmazonSageMakerFullAccess already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        log_success "AmazonSageMakerFullAccess attached to $role_name"
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Execution Roles"
    echo "=============================================="
    echo ""
    
    # 1. 创建 Domain 默认 Execution Role（必须先创建）
    log_info "Creating Domain default execution role..."
    create_domain_default_role
    
    echo ""
    
    # 2. 为每个项目创建 Execution Role
    for team in $TEAMS; do
        log_info "Creating execution roles for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            create_execution_role "$team" "$project"
        done
    done
    
    echo ""
    log_success "All execution roles created successfully!"
    echo ""
    
    # 显示创建的 Roles
    echo "Created Execution Roles:"
    aws iam list-roles --path-prefix "${IAM_PATH}" \
        --query 'Roles[?contains(RoleName, `ExecutionRole`)].{Name:RoleName,Arn:Arn}' \
        --output table
}

main
