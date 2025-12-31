#!/bin/bash
# =============================================================================
# diagnose-credentials.sh - 诊断 Studio 凭证获取错误
# =============================================================================
# 使用方法: ./diagnose-credentials.sh <iam-username> <profile-name>
# 示例:     ./diagnose-credentials.sh sm-algo-david profile-algo-david
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 参数
IAM_USER="${1:-sm-algo-david}"
PROFILE_NAME="${2:-profile-algo-david}"

echo ""
echo "=============================================="
echo " Diagnosing Studio Credentials Error"
echo "=============================================="
echo ""
echo "IAM User:     $IAM_USER"
echo "Profile Name: $PROFILE_NAME"
echo ""

# -----------------------------------------------------------------------------
# Step 1: 检查 IAM User 存在性
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 1: Check IAM User"
echo "=============================================="

if aws iam get-user --user-name "$IAM_USER" &> /dev/null; then
    log_success "IAM User exists: $IAM_USER"
    aws iam get-user --user-name "$IAM_USER" --query 'User.{UserName:UserName,Path:Path,Arn:Arn}' --output table
else
    log_error "IAM User not found: $IAM_USER"
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: 检查 User 所属 Groups 和 Policies
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 2: Check User Groups & Policies"
echo "=============================================="

echo ""
echo "Groups:"
aws iam list-groups-for-user --user-name "$IAM_USER" --query 'Groups[].GroupName' --output table

echo ""
echo "Attached Policies (direct):"
aws iam list-attached-user-policies --user-name "$IAM_USER" --query 'AttachedPolicies[].PolicyName' --output table 2>/dev/null || echo "  (none)"

echo ""
echo "Group Policies:"
for group in $(aws iam list-groups-for-user --user-name "$IAM_USER" --query 'Groups[].GroupName' --output text); do
    echo "  Group: $group"
    aws iam list-attached-group-policies --group-name "$group" --query 'AttachedPolicies[].PolicyName' --output text | tr '\t' '\n' | sed 's/^/    - /'
done

echo ""

# -----------------------------------------------------------------------------
# Step 3: 检查 SageMaker Domain
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 3: Check SageMaker Domain"
echo "=============================================="

DOMAIN_INFO=$(aws sagemaker list-domains --query 'Domains[0]' --output json)
DOMAIN_ID=$(echo "$DOMAIN_INFO" | jq -r '.DomainId')
DOMAIN_NAME=$(echo "$DOMAIN_INFO" | jq -r '.DomainName')

echo ""
echo "Domain ID:   $DOMAIN_ID"
echo "Domain Name: $DOMAIN_NAME"
echo ""

# -----------------------------------------------------------------------------
# Step 4: 检查 User Profile
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 4: Check User Profile"
echo "=============================================="

if aws sagemaker describe-user-profile --domain-id "$DOMAIN_ID" --user-profile-name "$PROFILE_NAME" &> /dev/null; then
    log_success "User Profile exists: $PROFILE_NAME"
    
    PROFILE_INFO=$(aws sagemaker describe-user-profile --domain-id "$DOMAIN_ID" --user-profile-name "$PROFILE_NAME")
    
    echo ""
    echo "Profile Status: $(echo "$PROFILE_INFO" | jq -r '.Status')"
    echo "Execution Role: $(echo "$PROFILE_INFO" | jq -r '.UserSettings.ExecutionRole // "inherited from domain"')"
    
    # 获取 Tags
    PROFILE_ARN=$(echo "$PROFILE_INFO" | jq -r '.UserProfileArn')
    echo ""
    echo "Profile Tags:"
    aws sagemaker list-tags --resource-arn "$PROFILE_ARN" --query 'Tags' --output table 2>/dev/null || echo "  (failed to list tags - permission denied?)"
    
    # 关键检查: Owner tag
    OWNER_TAG=$(aws sagemaker list-tags --resource-arn "$PROFILE_ARN" --query "Tags[?Key=='Owner'].Value" --output text 2>/dev/null || echo "")
    echo ""
    if [[ "$OWNER_TAG" == "$IAM_USER" ]]; then
        log_success "Owner tag matches IAM username: $OWNER_TAG"
    elif [[ -z "$OWNER_TAG" ]]; then
        log_error "Owner tag is MISSING!"
        log_warn "This will cause CreatePresignedDomainUrl to fail with condition check"
    else
        log_error "Owner tag MISMATCH!"
        echo "  Expected: $IAM_USER"
        echo "  Actual:   $OWNER_TAG"
        log_warn "This will cause CreatePresignedDomainUrl to fail with condition check"
    fi
else
    log_error "User Profile not found: $PROFILE_NAME"
    echo ""
    echo "Available profiles in domain:"
    aws sagemaker list-user-profiles --domain-id-equals "$DOMAIN_ID" --query 'UserProfiles[].UserProfileName' --output table
    exit 1
fi

echo ""

# -----------------------------------------------------------------------------
# Step 5: 检查 Execution Role
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 5: Check Execution Role"
echo "=============================================="

EXEC_ROLE=$(echo "$PROFILE_INFO" | jq -r '.UserSettings.ExecutionRole // empty')

if [[ -z "$EXEC_ROLE" ]]; then
    # 从 Domain 获取默认 Execution Role
    DOMAIN_DETAIL=$(aws sagemaker describe-domain --domain-id "$DOMAIN_ID")
    EXEC_ROLE=$(echo "$DOMAIN_DETAIL" | jq -r '.DefaultUserSettings.ExecutionRole')
    echo "Using Domain default execution role"
fi

EXEC_ROLE_NAME=$(echo "$EXEC_ROLE" | awk -F'/' '{print $NF}')

echo ""
echo "Execution Role ARN:  $EXEC_ROLE"
echo "Execution Role Name: $EXEC_ROLE_NAME"

# 检查 Trust Policy
echo ""
echo "Trust Policy:"
aws iam get-role --role-name "$EXEC_ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null | jq . || echo "  (failed to get role)"

# 检查 Trust Policy 是否正确
TRUST_PRINCIPAL=$(aws iam get-role --role-name "$EXEC_ROLE_NAME" --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text 2>/dev/null || echo "")

if [[ "$TRUST_PRINCIPAL" == "sagemaker.amazonaws.com" ]]; then
    log_success "Trust policy allows sagemaker.amazonaws.com"
else
    log_error "Trust policy does NOT allow sagemaker.amazonaws.com!"
    log_warn "This will cause 'Error acquiring credentials'"
fi

echo ""

# -----------------------------------------------------------------------------
# Step 6: 测试关键权限
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 6: Test Key Permissions (as admin)"
echo "=============================================="

echo ""
echo "Testing sagemaker:ListTags on domain..."
if aws sagemaker list-tags --resource-arn "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_ID}" &> /dev/null; then
    log_success "ListTags works (from admin account)"
else
    log_warn "ListTags failed even from admin - check domain exists"
fi

echo ""
echo "Testing sagemaker:CreatePresignedDomainUrl..."
PRESIGNED_URL=$(aws sagemaker create-presigned-domain-url \
    --domain-id "$DOMAIN_ID" \
    --user-profile-name "$PROFILE_NAME" \
    --query 'AuthorizedUrl' --output text 2>&1) || true

if [[ "$PRESIGNED_URL" == https* ]]; then
    log_success "CreatePresignedDomainUrl works (from admin account)"
    echo "  URL: ${PRESIGNED_URL:0:80}..."
else
    log_error "CreatePresignedDomainUrl failed!"
    echo "  Error: $PRESIGNED_URL"
fi

echo ""

# -----------------------------------------------------------------------------
# Summary & Recommendations
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Summary & Recommendations"
echo "=============================================="
echo ""

echo "Checklist:"
echo "  [ ] IAM User $IAM_USER exists"
echo "  [ ] User Profile $PROFILE_NAME exists with Status=InService"
echo "  [ ] Owner tag = $IAM_USER (for condition-based access)"
echo "  [ ] Execution Role trust policy allows sagemaker.amazonaws.com"
echo "  [ ] User has sagemaker:ListTags permission"
echo "  [ ] User has sagemaker:CreatePresignedDomainUrl permission"
echo "  [ ] User has sts:GetCallerIdentity permission"
echo ""

echo "If 'Error acquiring credentials' persists:"
echo ""
echo "1. Update base policy to add missing permissions:"
echo "   ./fix-credentials-error.sh"
echo ""
echo "2. If Owner tag is wrong, update it:"
echo "   aws sagemaker add-tags \\"
echo "     --resource-arn '$PROFILE_ARN' \\"
echo "     --tags Key=Owner,Value=$IAM_USER"
echo ""
echo "3. Verify Execution Role trust policy allows SageMaker:"
echo "   aws iam update-assume-role-policy \\"
echo "     --role-name $EXEC_ROLE_NAME \\"
echo "     --policy-document '{...}'"
echo ""
echo "4. Clear browser cache and try incognito mode"
echo ""

