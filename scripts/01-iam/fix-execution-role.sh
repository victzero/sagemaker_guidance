#!/bin/bash
# =============================================================================
# fix-execution-role.sh - 综合修复 Execution Role 问题
# =============================================================================
# 解决的问题:
#   1. Trust Policy: SageMaker 无法 AssumeRole
#      - 添加 sts:SetContext (Trusted Identity Propagation 必需)
#      - 确保 sagemaker.amazonaws.com 信任
#
#   2. VPC 权限: ec2:CreateNetworkInterface 缺失
#      - 附加 VPC 网络接口相关权限
#      - 确保 SageMaker 能在 VPC 模式下创建 ENI
#
#   3. 路径问题: 角色 ARN 路径不匹配
#      - 检查并修复角色路径
#
# 使用: ./fix-execution-role.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# =============================================================================
# Step 1: 正确的 Trust Policy (包含 SetContext)
# =============================================================================
CORRECT_TRUST_POLICY='{
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
}'

# =============================================================================
# Step 2: VPC 网络权限策略
# 这些权限是在 VpcOnly 模式下启动 JupyterLab/Notebook 必需的
# =============================================================================
VPC_NETWORK_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPCNetworkInterfacePermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:CreateNetworkInterfacePermission",
        "ec2:DeleteNetworkInterface",
        "ec2:DeleteNetworkInterfacePermission",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeDhcpOptions"
      ],
      "Resource": "*"
    }
  ]
}'

VPC_POLICY_NAME="SageMaker-VpcNetworkPermissions"

echo ""
echo "=============================================="
echo " Comprehensive Execution Role Fix"
echo "=============================================="
echo ""
echo "This script will fix:"
echo "  1. Trust Policy (add sts:SetContext)"
echo "  2. VPC Network Permissions (ec2:CreateNetworkInterface)"
echo "  3. Verify role path and AmazonSageMakerFullAccess attachment"
echo ""

# =============================================================================
# 查找所有 SageMaker Execution Roles
# =============================================================================
log_info "Step 1: Finding all SageMaker Execution Roles..."

# 搜索所有可能的位置（带路径和不带路径）
roles_without_path=$(aws iam list-roles \
    --query "Roles[?starts_with(RoleName, 'SageMaker-') && contains(RoleName, 'ExecutionRole')].{Name:RoleName,Path:Path,Arn:Arn}" \
    --output json 2>/dev/null || echo "[]")

echo ""
log_info "Found roles:"
echo "$roles_without_path" | jq -r '.[] | "  - \(.Arn)"'
echo ""

# 获取所有角色名列表
role_names=$(echo "$roles_without_path" | jq -r '.[].Name')

if [ -z "$role_names" ]; then
    log_error "No SageMaker Execution Roles found!"
    log_info "Please create roles first: ./04-create-roles.sh"
    exit 1
fi

# =============================================================================
# Step 2: 创建/更新 VPC 网络权限策略
# =============================================================================
log_info "Step 2: Creating/Updating VPC Network Permissions Policy..."

IAM_PATH=$(get_iam_path)
VPC_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${VPC_POLICY_NAME}"

# 检查策略是否存在
if aws iam get-policy --policy-arn "$VPC_POLICY_ARN" &>/dev/null; then
    log_warn "Policy ${VPC_POLICY_NAME} already exists, updating..."
    
    # 获取当前版本
    versions=$(aws iam list-policy-versions --policy-arn "$VPC_POLICY_ARN" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    
    # 删除旧版本（保留最新的默认版本）
    for v in $versions; do
        aws iam delete-policy-version --policy-arn "$VPC_POLICY_ARN" --version-id "$v" 2>/dev/null || true
    done
    
    # 创建新版本
    aws iam create-policy-version \
        --policy-arn "$VPC_POLICY_ARN" \
        --policy-document "$VPC_NETWORK_POLICY" \
        --set-as-default
    
    log_success "Policy updated: ${VPC_POLICY_NAME}"
else
    aws iam create-policy \
        --policy-name "$VPC_POLICY_NAME" \
        --path "$IAM_PATH" \
        --policy-document "$VPC_NETWORK_POLICY" \
        --description "VPC network interface permissions for SageMaker in VpcOnly mode"
    
    log_success "Policy created: ${VPC_POLICY_NAME}"
fi

echo ""

# =============================================================================
# Step 3: 修复每个 Execution Role
# =============================================================================
log_info "Step 3: Fixing each Execution Role..."
echo ""

for role_name in $role_names; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Processing: $role_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # -------------------------------------------------------------------------
    # 3.1 修复 Trust Policy
    # -------------------------------------------------------------------------
    log_info "  [3.1] Checking Trust Policy..."
    
    current_trust=$(aws iam get-role --role-name "$role_name" \
        --query "Role.AssumeRolePolicyDocument" --output json 2>/dev/null || echo "{}")
    
    # 检查是否包含 SetContext
    if echo "$current_trust" | grep -q "SetContext"; then
        log_success "  Trust policy already includes SetContext"
    else
        log_warn "  Updating trust policy to include SetContext..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "$CORRECT_TRUST_POLICY"
        log_success "  Trust policy updated"
    fi
    
    # -------------------------------------------------------------------------
    # 3.2 确保 AmazonSageMakerFullAccess 已附加
    # -------------------------------------------------------------------------
    log_info "  [3.2] Checking AmazonSageMakerFullAccess..."
    
    sm_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sm_attached" ]]; then
        log_success "  AmazonSageMakerFullAccess is attached"
    else
        log_warn "  Attaching AmazonSageMakerFullAccess..."
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        log_success "  AmazonSageMakerFullAccess attached"
    fi
    
    # -------------------------------------------------------------------------
    # 3.3 附加 VPC 网络权限策略
    # -------------------------------------------------------------------------
    log_info "  [3.3] Checking VPC Network Permissions..."
    
    vpc_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${VPC_POLICY_NAME}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_attached" ]]; then
        log_success "  ${VPC_POLICY_NAME} is attached"
    else
        log_warn "  Attaching ${VPC_POLICY_NAME}..."
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$VPC_POLICY_ARN"
        log_success "  ${VPC_POLICY_NAME} attached"
    fi
    
    echo ""
done

# =============================================================================
# Step 4: 验证 STS 区域端点
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 4: Checking STS Regional Endpoint..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Important: STS Regional Endpoint must be activated for region: $AWS_REGION"
echo ""
echo "To verify/activate STS regional endpoints:"
echo "  1. Go to AWS Console → IAM → Account settings"
echo "  2. Find 'Security Token Service (STS)' section"
echo "  3. Ensure '$AWS_REGION' endpoint is ACTIVE"
echo ""
echo "Or use AWS CLI:"
echo "  aws iam set-security-token-service-preferences \\"
echo "    --global-endpoint-token-version v2Token"
echo ""

# =============================================================================
# Step 5: 显示结果摘要
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Fix completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "What was fixed:"
echo "  ✓ Trust Policy: Added sts:SetContext for Trusted Identity Propagation"
echo "  ✓ VPC Permissions: Added ec2:CreateNetworkInterface and related permissions"
echo "  ✓ Verified: AmazonSageMakerFullAccess is attached to all roles"
echo ""
echo "Roles updated:"
for role_name in $role_names; do
    local role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null)
    echo "  - $role_arn"
done
echo ""
echo "Next steps:"
echo "  1. Wait 2-3 minutes for IAM changes to propagate"
echo "  2. Verify STS regional endpoint is active for $AWS_REGION"
echo "  3. Clear browser cache or use incognito mode"
echo "  4. Try launching JupyterLab again in SageMaker Studio"
echo ""

# =============================================================================
# Step 6: 可选 - 检查角色路径问题
# =============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 6: Checking Role Path Issues..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查 Domain 使用的角色
log_info "Checking SageMaker Domain configuration..."

domain_id=$(aws sagemaker list-domains \
    --query 'Domains[0].DomainId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -n "$domain_id" && "$domain_id" != "None" ]]; then
    domain_role=$(aws sagemaker describe-domain \
        --domain-id "$domain_id" \
        --query 'DefaultUserSettings.ExecutionRole' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    echo "  Domain ID: $domain_id"
    echo "  Domain Execution Role: $domain_role"
    echo ""
    
    # 检查角色是否存在
    role_name_from_arn=$(echo "$domain_role" | sed 's/.*role\///' | sed 's/.*\///')
    
    if aws iam get-role --role-name "$role_name_from_arn" &>/dev/null; then
        log_success "Role exists and is accessible"
    else
        log_error "Role does not exist or is not accessible!"
        echo ""
        echo "The Domain is configured to use: $domain_role"
        echo "But this role was not found."
        echo ""
        echo "Possible fixes:"
        echo "  Option 1: Recreate the role at the expected path"
        echo "  Option 2: Update the Domain to use a different role"
        echo ""
        echo "To update Domain execution role:"
        echo "  aws sagemaker update-domain \\"
        echo "    --domain-id $domain_id \\"
        echo "    --default-user-settings '{\"ExecutionRole\": \"NEW_ROLE_ARN\"}'"
    fi
else
    log_warn "No SageMaker Domain found in region $AWS_REGION"
fi

echo ""
log_success "Diagnostic complete!"

