#!/bin/bash
#
# 修复 Execution Role Trust Policy
# 解决 "SageMaker is unable to assume your associated ExecutionRole" 错误
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# Trust Policy JSON
TRUST_POLICY='{
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
}'

echo "=============================================="
echo " Fix SageMaker Execution Role Trust Policy"
echo "=============================================="

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
    
    # 检查是否包含 sagemaker.amazonaws.com
    if echo "$current_trust" | grep -q "sagemaker.amazonaws.com"; then
        log_success "  Trust policy already includes sagemaker.amazonaws.com"
    else
        log_warn "  Trust policy missing sagemaker.amazonaws.com, updating..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "$TRUST_POLICY"
        log_success "  Updated trust policy"
    fi
done

echo ""
log_success "All execution roles have correct trust policy!"
echo ""
echo "If you still see errors, please verify:"
echo "  1. MFA is set up and you have re-logged in"
echo "  2. Wait a few minutes for IAM changes to propagate"
echo "  3. Try closing and reopening Studio"
