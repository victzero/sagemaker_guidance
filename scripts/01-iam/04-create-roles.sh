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
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 创建 Execution Role 函数
# -----------------------------------------------------------------------------
create_execution_role() {
    local team=$1
    local project=$2
    
    # 格式化名称 (risk-control -> RiskControl, project-a -> ProjectA)
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(echo "$team_fullname" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
    local project_formatted=$(echo "$project" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy"
    
    log_info "Creating execution role: $role_name"
    
    # 保存 trust policy
    local trust_policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
    generate_trust_policy > "$trust_policy_file"
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, skipping creation..."
    else
        run_cmd aws iam create-role \
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
    
    # 附加策略到 Role
    log_info "Attaching policy to role..."
    
    # 检查策略是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy $policy_name already attached to $role_name"
    else
        run_cmd aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
        
        log_success "Policy $policy_name attached to $role_name"
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
    
    # 为每个项目创建 Execution Role
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
