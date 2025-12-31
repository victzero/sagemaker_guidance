#!/bin/bash
# =============================================================================
# fix-trust-policy-v2.sh - 修复 Execution Role Trust Policy
# =============================================================================
# 问题: "Error acquiring credentials" 在 VPC 配置正确的情况下
#
# 原因: SageMaker 需要以下 STS 权限来管理会话:
#   - sts:AssumeRole (基本)
#   - sts:SetSourceIdentity (用于审计追踪，新版 Studio 需要)
#   - sts:TagSession (可选，用于会话标签)
#
# 参考: 
#   https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam-awsmanpol.html
#   https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Fix Execution Role Trust Policy"
echo "=============================================="
echo ""

# 生成更新后的 Trust Policy
generate_updated_trust_policy() {
    cat << 'EOF'
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
        "sts:SetSourceIdentity"
      ]
    }
  ]
}
EOF
}

# 保存 trust policy 到文件
TRUST_POLICY_FILE="${SCRIPT_DIR}/.output/trust-policy-updated.json"
mkdir -p "${SCRIPT_DIR}/.output"
generate_updated_trust_policy > "$TRUST_POLICY_FILE"

echo "Updated Trust Policy:"
echo "----------------------------------------"
cat "$TRUST_POLICY_FILE"
echo "----------------------------------------"
echo ""

# 获取所有需要更新的 Execution Roles
echo "Checking Execution Roles..."
echo ""

ROLES_TO_UPDATE=()

# 1. Domain Default Execution Role
DEFAULT_ROLE="SageMaker-Domain-DefaultExecutionRole"
if aws iam get-role --role-name "$DEFAULT_ROLE" &> /dev/null; then
    ROLES_TO_UPDATE+=("$DEFAULT_ROLE")
    echo "  Found: $DEFAULT_ROLE"
fi

# 2. Project-specific Execution Roles
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    projects=$(get_projects_for_team "$team")
    
    for project in $projects; do
        project_formatted=$(format_name "$project")
        role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
        
        if aws iam get-role --role-name "$role_name" &> /dev/null; then
            ROLES_TO_UPDATE+=("$role_name")
            echo "  Found: $role_name"
        fi
    done
done

echo ""
echo "Total roles to update: ${#ROLES_TO_UPDATE[@]}"
echo ""

# 确认更新
read -p "Update trust policy for all these roles? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    log_info "Cancelled."
    exit 0
fi

echo ""

# 更新每个 Role 的 Trust Policy
for role_name in "${ROLES_TO_UPDATE[@]}"; do
    log_info "Updating: $role_name"
    
    # 获取当前 trust policy
    current_policy=$(aws iam get-role --role-name "$role_name" \
        --query 'Role.AssumeRolePolicyDocument' --output json)
    
    # 检查是否已包含 SetSourceIdentity
    if echo "$current_policy" | grep -q "SetSourceIdentity"; then
        log_warn "  Already has SetSourceIdentity, skipping..."
        continue
    fi
    
    # 更新 trust policy
    aws iam update-assume-role-policy \
        --role-name "$role_name" \
        --policy-document "file://${TRUST_POLICY_FILE}"
    
    log_success "  Updated!"
done

echo ""
log_success "All trust policies updated!"
echo ""

# 验证
echo "=============================================="
echo " Verification"
echo "=============================================="
echo ""

for role_name in "${ROLES_TO_UPDATE[@]}"; do
    echo "Role: $role_name"
    aws iam get-role --role-name "$role_name" \
        --query 'Role.AssumeRolePolicyDocument.Statement[0].Action' --output json
    echo ""
done

echo "=============================================="
echo " Next Steps"
echo "=============================================="
echo ""
echo "1. Ask David to clear browser cache (or use incognito)"
echo "2. Wait 1-2 minutes for IAM changes to propagate"
echo "3. Try accessing SageMaker Studio again"
echo ""
echo "If still failing, check execution role has EFS permissions:"
echo "  aws iam list-attached-role-policies --role-name SageMaker-Algorithm-RecommendationEngine-ExecutionRole"
echo ""

