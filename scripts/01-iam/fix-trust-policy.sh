#!/bin/bash
# =============================================================================
# fix-trust-policy.sh - 修复 Execution Role Trust Policy
# =============================================================================
# 问题: "SageMaker is unable to assume your associated ExecutionRole"
#       或 "Error acquiring credentials"
#
# 原因: Trust Policy 需要包含:
#   - sts:AssumeRole (基础)
#   - sts:SetSourceIdentity (新版 Studio 需要，用于审计追踪)
#
# 使用: ./fix-trust-policy.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# Trust Policy JSON (包含 SetSourceIdentity)
TRUST_POLICY='{
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
}'

echo ""
echo "=============================================="
echo " Fix SageMaker Execution Role Trust Policy"
echo "=============================================="
echo ""

# 获取所有 SageMaker Execution Roles
log_info "Finding all SageMaker Execution Roles..."

roles=$(aws iam list-roles --path-prefix "${IAM_PATH}" --query "Roles[?contains(RoleName, 'ExecutionRole')].RoleName" --output text)

if [ -z "$roles" ]; then
    log_error "No execution roles found with path ${IAM_PATH}"
    exit 1
fi

echo ""
log_info "Found roles:"
for role in $roles; do
    echo "  - $role"
done
echo ""

# 更新每个 Role 的 trust policy
for role_name in $roles; do
    log_info "Checking trust policy for: $role_name"
    
    # 获取当前 trust policy
    current_trust=$(aws iam get-role --role-name "$role_name" --query "Role.AssumeRolePolicyDocument" --output json 2>/dev/null || echo "{}")
    
    # 检查是否已包含 SetSourceIdentity
    if echo "$current_trust" | grep -q "SetSourceIdentity"; then
        log_success "  Trust policy already includes SetSourceIdentity"
    else
        log_warn "  Updating trust policy to include SetSourceIdentity..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "$TRUST_POLICY"
        log_success "  Updated trust policy"
    fi
done

echo ""
log_success "All execution roles have correct trust policy!"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for IAM changes to propagate"
echo "  2. Clear browser cache or use incognito mode"
echo "  3. Re-login and try accessing Studio again"
echo ""
