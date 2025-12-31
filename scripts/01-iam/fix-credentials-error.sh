#!/bin/bash
# =============================================================================
# fix-credentials-error.sh - 修复 Studio 凭证获取错误
# =============================================================================
# 问题描述:
#   1. sagemaker:ListTags permission denied
#   2. Error acquiring credentials when opening Studio
#
# 解决方案:
#   1. 更新 SageMaker-Studio-Base-Access 策略，添加 ListTags 权限
#   2. 放宽 CreatePresignedDomainUrl 的条件限制（临时）
#   3. 添加 sts:GetCallerIdentity 权限
#
# 参考文档:
#   https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam.html
#   https://docs.aws.amazon.com/sagemaker/latest/dg/studio-troubleshooting.html
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 生成修复后的基础策略
# -----------------------------------------------------------------------------
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
      "Sid": "AllowSTSActions",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "sts:GetSessionToken"
      ],
      "Resource": "*"
    }
  ]
}
POLICYEOF
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Fixing Studio Credentials Error"
    echo "=============================================="
    echo ""
    
    local policy_name="SageMaker-Studio-Base-Access"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # Step 1: 检查当前策略
    log_info "Checking current policy: $policy_name"
    
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_error "Policy $policy_name not found!"
        log_info "Please run ./01-create-policies.sh first"
        exit 1
    fi
    
    # Step 2: 生成新策略文档
    local policy_file="${SCRIPT_DIR}/.output/policy-${policy_name}-fixed.json"
    mkdir -p "${SCRIPT_DIR}/.output"
    generate_fixed_base_access_policy > "$policy_file"
    
    log_info "Generated fixed policy: $policy_file"
    echo ""
    echo "New policy content:"
    echo "----------------------------------------"
    cat "$policy_file"
    echo "----------------------------------------"
    echo ""
    
    # Step 3: 确认更新
    read -p "Apply this policy update? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log_info "Cancelled."
        exit 0
    fi
    
    # Step 4: 清理旧版本（IAM 最多 5 个版本）
    log_info "Checking policy versions..."
    local versions=$(aws iam list-policy-versions \
        --policy-arn "$policy_arn" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    
    local version_count=$(echo "$versions" | wc -w)
    if [[ $version_count -ge 4 ]]; then
        log_warn "Too many versions, deleting oldest non-default version..."
        local oldest_version=$(aws iam list-policy-versions \
            --policy-arn "$policy_arn" \
            --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate)[0].VersionId' --output text)
        
        aws iam delete-policy-version \
            --policy-arn "$policy_arn" \
            --version-id "$oldest_version"
        log_success "Deleted version: $oldest_version"
    fi
    
    # Step 5: 创建新版本
    log_info "Creating new policy version..."
    aws iam create-policy-version \
        --policy-arn "$policy_arn" \
        --policy-document "file://${policy_file}" \
        --set-as-default
    
    log_success "Policy $policy_name updated successfully!"
    
    echo ""
    echo "=============================================="
    echo " Next Steps"
    echo "=============================================="
    echo ""
    echo "1. Verify the User Profile has correct Owner tag:"
    echo "   aws sagemaker describe-user-profile \\"
    echo "     --domain-id d-7zn4cbfjkm65 \\"
    echo "     --user-profile-name profile-algo-david"
    echo ""
    echo "2. Check if Owner tag matches IAM username:"
    echo "   - IAM User: sm-algo-david"
    echo "   - Profile Owner tag should be: sm-algo-david"
    echo ""
    echo "3. Ask David to logout and login again"
    echo ""
    echo "4. If still failing, run the verification script:"
    echo "   ./verify.sh"
    echo ""
}

main

