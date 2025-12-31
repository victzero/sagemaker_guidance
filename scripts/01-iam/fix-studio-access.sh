#!/bin/bash
# =============================================================================
# fix-studio-access.sh - 修复 SageMaker Studio 访问问题
# =============================================================================
# 问题:
#   1. sagemaker:ListTags permission denied (访问 Console 时)
#   2. Error acquiring credentials (进入 Studio 时)
#
# 修复内容:
#   1. 更新 SageMaker-Studio-Base-Access 策略 - 添加 ListTags 权限
#   2. 更新 Execution Role Trust Policy - 添加 sts:SetSourceIdentity
#
# 参考:
#   https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam.html
#   https://docs.aws.amazon.com/sagemaker/latest/dg/studio-troubleshooting.html
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Fix SageMaker Studio Access Issues"
echo "=============================================="
echo ""
echo "This script will fix two common issues:"
echo "  1. ListTags permission denied"
echo "  2. Error acquiring credentials"
echo ""

# 确认执行
read -p "Continue with the fix? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    log_info "Cancelled."
    exit 0
fi

mkdir -p "${SCRIPT_DIR}/.output"

# =============================================================================
# Fix 1: 更新 SageMaker-Studio-Base-Access 策略
# =============================================================================
echo ""
echo "=============================================="
echo " Fix 1: Update Base Access Policy"
echo "=============================================="
echo ""

generate_fixed_base_access_policy() {
    cat << POLICYEOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeDomain",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeDomain",
        "sagemaker:ListDomains"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/*"
    },
    {
      "Sid": "AllowListUserProfiles",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListUserProfiles",
        "sagemaker:ListSpaces",
        "sagemaker:ListApps"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowListTags",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListTags",
        "sagemaker:AddTags"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:app/*"
      ]
    },
    {
      "Sid": "AllowDescribeOwnProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeUserProfile",
        "sagemaker:CreatePresignedDomainUrl"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Owner": "\${aws:username}"
        }
      }
    },
    {
      "Sid": "AllowSTSGetCallerIdentity",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
POLICYEOF
}

policy_name="SageMaker-Studio-Base-Access"
policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
policy_file="${SCRIPT_DIR}/.output/policy-${policy_name}-fixed.json"

log_info "Updating policy: $policy_name"

# 检查策略是否存在
if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
    log_error "Policy $policy_name not found!"
    exit 1
fi

# 生成新策略
generate_fixed_base_access_policy > "$policy_file"

# 清理旧版本
versions=$(aws iam list-policy-versions \
    --policy-arn "$policy_arn" \
    --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)

version_count=$(echo "$versions" | wc -w)
if [[ $version_count -ge 4 ]]; then
    oldest_version=$(aws iam list-policy-versions \
        --policy-arn "$policy_arn" \
        --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate)[0].VersionId' --output text)
    
    aws iam delete-policy-version \
        --policy-arn "$policy_arn" \
        --version-id "$oldest_version"
    log_info "  Deleted old version: $oldest_version"
fi

# 创建新版本
aws iam create-policy-version \
    --policy-arn "$policy_arn" \
    --policy-document "file://${policy_file}" \
    --set-as-default

log_success "Policy updated: $policy_name"

# =============================================================================
# Fix 2: 更新 Execution Role Trust Policy
# =============================================================================
echo ""
echo "=============================================="
echo " Fix 2: Update Execution Role Trust Policy"
echo "=============================================="
echo ""

generate_updated_trust_policy() {
    cat << 'TRUSTPOLICYEOF'
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
TRUSTPOLICYEOF
}

trust_policy_file="${SCRIPT_DIR}/.output/trust-policy-fixed.json"
generate_updated_trust_policy > "$trust_policy_file"

log_info "Finding Execution Roles..."

# 收集所有 Execution Roles
ROLES_TO_UPDATE=()

# Domain Default Role
DEFAULT_ROLE="SageMaker-Domain-DefaultExecutionRole"
if aws iam get-role --role-name "$DEFAULT_ROLE" &> /dev/null; then
    ROLES_TO_UPDATE+=("$DEFAULT_ROLE")
fi

# Project-specific Roles
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    projects=$(get_projects_for_team "$team")
    
    for project in $projects; do
        project_formatted=$(format_name "$project")
        role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
        
        if aws iam get-role --role-name "$role_name" &> /dev/null; then
            ROLES_TO_UPDATE+=("$role_name")
        fi
    done
done

log_info "Found ${#ROLES_TO_UPDATE[@]} Execution Roles to update"

# 更新每个 Role
for role_name in "${ROLES_TO_UPDATE[@]}"; do
    # 检查是否已有 SetSourceIdentity
    current_policy=$(aws iam get-role --role-name "$role_name" \
        --query 'Role.AssumeRolePolicyDocument' --output json)
    
    if echo "$current_policy" | grep -q "SetSourceIdentity"; then
        log_info "  $role_name - already has SetSourceIdentity, skipping"
        continue
    fi
    
    aws iam update-assume-role-policy \
        --role-name "$role_name" \
        --policy-document "file://${trust_policy_file}"
    
    log_success "  $role_name - trust policy updated"
done

# =============================================================================
# 完成
# =============================================================================
echo ""
echo "=============================================="
echo " Fix Complete!"
echo "=============================================="
echo ""
echo "Changes made:"
echo "  ✓ SageMaker-Studio-Base-Access policy updated with ListTags permission"
echo "  ✓ Execution Role trust policies updated with sts:SetSourceIdentity"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for IAM changes to propagate"
echo "  2. Ask David to:"
echo "     - Clear browser cache (or use incognito mode)"
echo "     - Log out of AWS Console"
echo "     - Log back in"
echo "     - Try accessing SageMaker Studio again"
echo ""
echo "If issues persist, run the diagnostic script:"
echo "  ./diagnose-credentials.sh sm-algo-david profile-algo-david"
echo ""

