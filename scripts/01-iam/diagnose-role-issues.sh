#!/bin/bash
# =============================================================================
# diagnose-role-issues.sh - 诊断 SageMaker Execution Role 问题
# =============================================================================
# 快速诊断以下问题:
#   - Trust Policy 是否正确
#   - STS 区域端点是否激活
#   - VPC 权限是否完整
#   - 角色路径是否匹配 Domain 配置
#
# 使用: ./diagnose-role-issues.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " SageMaker Execution Role Diagnostic"
echo "=============================================="
echo ""
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo ""

# =============================================================================
# 1. 检查 SageMaker Domain
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[1/5] Checking SageMaker Domain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

domains=$(aws sagemaker list-domains --region "$AWS_REGION" --output json 2>/dev/null || echo '{"Domains":[]}')
domain_count=$(echo "$domains" | jq '.Domains | length')

if [[ "$domain_count" -eq 0 ]]; then
    echo "  ⚠️  No SageMaker Domain found in $AWS_REGION"
    echo ""
else
    echo "$domains" | jq -r '.Domains[] | "  Domain ID: \(.DomainId)\n  Name: \(.DomainName)\n  Status: \(.Status)"'
    
    # 获取第一个 Domain 的详细信息
    domain_id=$(echo "$domains" | jq -r '.Domains[0].DomainId')
    domain_info=$(aws sagemaker describe-domain --domain-id "$domain_id" --region "$AWS_REGION" 2>/dev/null || echo '{}')
    
    expected_role=$(echo "$domain_info" | jq -r '.DefaultUserSettings.ExecutionRole // "N/A"')
    network_mode=$(echo "$domain_info" | jq -r '.AppNetworkAccessType // "N/A"')
    vpc_id=$(echo "$domain_info" | jq -r '.VpcId // "N/A"')
    
    echo ""
    echo "  Network Mode: $network_mode"
    echo "  VPC ID: $vpc_id"
    echo "  Expected Execution Role: $expected_role"
fi
echo ""

# =============================================================================
# 2. 检查期望的 Execution Role 是否存在
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[2/5] Checking Expected Execution Role"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$expected_role" && "$expected_role" != "N/A" ]]; then
    # 从 ARN 提取角色名
    role_name=$(echo "$expected_role" | awk -F'/' '{print $NF}')
    role_path=$(echo "$expected_role" | sed 's|.*:role||' | sed "s|/$role_name||")
    
    echo "  Role Name: $role_name"
    echo "  Role Path: ${role_path:-/}"
    echo ""
    
    # 检查角色是否存在
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        actual_role=$(aws iam get-role --role-name "$role_name" --output json)
        actual_arn=$(echo "$actual_role" | jq -r '.Role.Arn')
        actual_path=$(echo "$actual_role" | jq -r '.Role.Path')
        
        echo "  ✅ Role exists"
        echo "  Actual ARN: $actual_arn"
        echo "  Actual Path: $actual_path"
        
        # 检查 ARN 是否完全匹配
        if [[ "$actual_arn" == "$expected_role" ]]; then
            echo "  ✅ Role ARN matches Domain configuration"
        else
            echo "  ❌ Role ARN MISMATCH!"
            echo "     Expected: $expected_role"
            echo "     Actual:   $actual_arn"
            echo ""
            echo "  💡 Fix: Update Domain to use the correct role ARN"
        fi
    else
        echo "  ❌ Role NOT FOUND: $role_name"
        echo ""
        echo "  💡 The Domain expects a role that doesn't exist."
        echo "     Either create the role or update the Domain configuration."
    fi
else
    echo "  ⚠️  Could not determine expected execution role"
fi
echo ""

# =============================================================================
# 3. 检查 Trust Policy
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[3/5] Checking Trust Policy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$role_name" ]] && aws iam get-role --role-name "$role_name" &>/dev/null; then
    trust_policy=$(aws iam get-role --role-name "$role_name" \
        --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)
    
    echo "  Current Trust Policy:"
    echo "$trust_policy" | jq '.' | sed 's/^/    /'
    echo ""
    
    # 检查必需的 Actions
    has_assume=$(echo "$trust_policy" | jq 'any(.Statement[]; .Action | if type == "array" then . else [.] end | contains(["sts:AssumeRole"]))')
    has_context=$(echo "$trust_policy" | jq 'any(.Statement[]; .Action | if type == "array" then . else [.] end | contains(["sts:SetContext"]))')
    has_sagemaker=$(echo "$trust_policy" | jq 'any(.Statement[]; .Principal.Service == "sagemaker.amazonaws.com")')
    
    if [[ "$has_sagemaker" == "true" ]]; then
        echo "  ✅ Trust: sagemaker.amazonaws.com"
    else
        echo "  ❌ Missing Trust: sagemaker.amazonaws.com"
    fi
    
    if [[ "$has_assume" == "true" ]]; then
        echo "  ✅ Action: sts:AssumeRole"
    else
        echo "  ❌ Missing Action: sts:AssumeRole"
    fi
    
    if [[ "$has_context" == "true" ]]; then
        echo "  ✅ Action: sts:SetContext (required for Trusted Identity Propagation)"
    else
        echo "  ⚠️  Missing Action: sts:SetContext"
        echo "     This may cause authentication issues with Identity Center"
    fi
else
    echo "  ⚠️  Cannot check trust policy - role not found"
fi
echo ""

# =============================================================================
# 4. 检查附加的策略
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[4/5] Checking Attached Policies"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -n "$role_name" ]] && aws iam get-role --role-name "$role_name" &>/dev/null; then
    attached=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[*].PolicyName' --output json 2>/dev/null || echo '[]')
    
    echo "  Attached Policies:"
    echo "$attached" | jq -r '.[] | "    - \(.)"'
    echo ""
    
    # 检查关键策略
    has_sm_full=$(echo "$attached" | jq 'any(. == "AmazonSageMakerFullAccess")')
    
    if [[ "$has_sm_full" == "true" ]]; then
        echo "  ✅ AmazonSageMakerFullAccess attached"
        echo "     (includes ec2:CreateNetworkInterface and VPC permissions)"
    else
        echo "  ❌ AmazonSageMakerFullAccess NOT attached"
        echo "     This is likely causing the VPC permission errors!"
    fi
else
    echo "  ⚠️  Cannot check policies - role not found"
fi
echo ""

# =============================================================================
# 5. 检查 STS 区域端点
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[5/5] STS Regional Endpoint Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "  The error message mentions checking if STS regional endpoint"
echo "  is activated for region '$AWS_REGION'."
echo ""
echo "  To check STS regional endpoints:"
echo "    1. Go to IAM Console → Account settings"
echo "    2. Find 'Security Token Service (STS)' section"
echo "    3. Verify '$AWS_REGION' endpoint status is 'Active'"
echo ""
echo "  Or visit:"
echo "    https://console.aws.amazon.com/iam/home#/account_settings"
echo ""

# =============================================================================
# 诊断总结
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Diagnostic Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If you're seeing 'SageMaker was unable to assume the role' error:"
echo ""
echo "  1. Run: ./fix-execution-role.sh"
echo "     This will fix trust policy and add VPC permissions"
echo ""
echo "  2. Verify STS regional endpoint is active"
echo "     Go to IAM Console → Account settings"
echo ""
echo "  3. If role path mismatch detected:"
echo "     Either recreate the role or update Domain configuration"
echo ""
echo "  4. Wait 2-3 minutes after fixing, then retry"
echo ""


