#!/bin/bash
# =============================================================================
# diagnose-vpc-credentials.sh - 诊断 VpcOnly 模式下的凭证获取问题
# =============================================================================
# 在 VpcOnly 模式下，"Error acquiring credentials" 通常是由于：
# 1. STS VPC Endpoint 缺失或配置错误
# 2. VPC Endpoint 的 Security Group 不允许 HTTPS (443) 入站
# 3. VPC Endpoint Policy 限制了访问
#
# 参考: https://docs.aws.amazon.com/sagemaker/latest/dg/studio-notebooks-and-internet-access.html
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Diagnosing VpcOnly Mode Credentials Issue"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: 获取 Domain 信息
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 1: SageMaker Domain Configuration"
echo "=============================================="

DOMAIN_INFO=$(aws sagemaker list-domains --query 'Domains[0]' --output json)
DOMAIN_ID=$(echo "$DOMAIN_INFO" | jq -r '.DomainId')

DOMAIN_DETAIL=$(aws sagemaker describe-domain --domain-id "$DOMAIN_ID")
VPC_ID=$(echo "$DOMAIN_DETAIL" | jq -r '.VpcId')
SUBNET_IDS=$(echo "$DOMAIN_DETAIL" | jq -r '.SubnetIds[]')
APP_NETWORK_ACCESS=$(echo "$DOMAIN_DETAIL" | jq -r '.AppNetworkAccessType')

echo ""
echo "Domain ID:           $DOMAIN_ID"
echo "VPC ID:              $VPC_ID"
echo "App Network Access:  $APP_NETWORK_ACCESS"
echo "Subnet IDs:"
for subnet in $SUBNET_IDS; do
    echo "  - $subnet"
done

if [[ "$APP_NETWORK_ACCESS" != "VpcOnly" ]]; then
    log_warn "Domain is NOT in VpcOnly mode ($APP_NETWORK_ACCESS)"
    log_info "Credentials issue may not be VPC related"
else
    log_info "Domain is in VpcOnly mode - checking VPC Endpoints..."
fi

echo ""

# -----------------------------------------------------------------------------
# Step 2: 检查必需的 VPC Endpoints
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 2: Required VPC Endpoints"
echo "=============================================="

# SageMaker Studio in VpcOnly mode requires these endpoints
REQUIRED_ENDPOINTS=(
    "com.amazonaws.${AWS_REGION}.sagemaker.api"
    "com.amazonaws.${AWS_REGION}.sagemaker.runtime"
    "aws.sagemaker.${AWS_REGION}.studio"
    "com.amazonaws.${AWS_REGION}.sts"      # CRITICAL for credentials!
    "com.amazonaws.${AWS_REGION}.s3"
)

echo ""
echo "Checking VPC Endpoints in VPC: $VPC_ID"
echo ""

MISSING_ENDPOINTS=()
STS_ENDPOINT_ID=""

for service in "${REQUIRED_ENDPOINTS[@]}"; do
    endpoint_info=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${service}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[0]' --output json 2>/dev/null || echo "null")
    
    if [[ "$endpoint_info" == "null" ]]; then
        log_error "MISSING: $service"
        MISSING_ENDPOINTS+=("$service")
    else
        endpoint_id=$(echo "$endpoint_info" | jq -r '.VpcEndpointId')
        endpoint_state=$(echo "$endpoint_info" | jq -r '.State')
        endpoint_type=$(echo "$endpoint_info" | jq -r '.VpcEndpointType')
        
        if [[ "$endpoint_state" == "available" ]]; then
            log_success "OK: $service ($endpoint_id, $endpoint_type)"
        else
            log_warn "DEGRADED: $service ($endpoint_id, state=$endpoint_state)"
        fi
        
        # 保存 STS endpoint ID 供后续检查
        if [[ "$service" == "com.amazonaws.${AWS_REGION}.sts" ]]; then
            STS_ENDPOINT_ID="$endpoint_id"
        fi
    fi
done

echo ""

if [[ ${#MISSING_ENDPOINTS[@]} -gt 0 ]]; then
    log_error "Missing ${#MISSING_ENDPOINTS[@]} required VPC Endpoint(s)!"
    echo ""
    echo "To fix, run:"
    echo "  cd ../02-vpc && ./setup-all.sh"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 3: 检查 STS Endpoint 的 Security Group
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 3: STS Endpoint Security Group"
echo "=============================================="

if [[ -z "$STS_ENDPOINT_ID" ]]; then
    log_error "STS Endpoint not found - this is likely the cause of 'Error acquiring credentials'!"
    echo ""
    echo "SageMaker Studio needs to call STS (Security Token Service) to get temporary"
    echo "credentials for the execution role. Without an STS VPC Endpoint, Studio cannot"
    echo "reach STS in VpcOnly mode."
    echo ""
    echo "Solution: Create the STS VPC Endpoint"
    echo "  aws ec2 create-vpc-endpoint \\"
    echo "    --vpc-id $VPC_ID \\"
    echo "    --service-name com.amazonaws.${AWS_REGION}.sts \\"
    echo "    --vpc-endpoint-type Interface \\"
    echo "    --subnet-ids <subnet-ids> \\"
    echo "    --security-group-ids <sg-id>"
else
    echo ""
    echo "STS Endpoint ID: $STS_ENDPOINT_ID"
    
    # 获取 STS endpoint 的 Security Groups
    STS_SG_IDS=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "$STS_ENDPOINT_ID" \
        --query 'VpcEndpoints[0].Groups[].GroupId' --output text)
    
    echo "Security Groups attached: $STS_SG_IDS"
    echo ""
    
    # 检查每个 Security Group 是否允许 443 入站
    for sg_id in $STS_SG_IDS; do
        echo "Checking Security Group: $sg_id"
        
        # 获取 SG 名称
        sg_name=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query 'SecurityGroups[0].GroupName' --output text)
        echo "  Name: $sg_name"
        
        # 检查是否有 443 端口的入站规则
        https_rule=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`443\` && ToPort==\`443\`]" \
            --output json)
        
        if [[ "$https_rule" == "[]" ]]; then
            log_error "  ⚠️  NO inbound rule for port 443 (HTTPS)!"
            echo "  This may prevent Studio from calling STS endpoint"
        else
            log_success "  ✓ Has inbound rule for port 443"
            echo "  Inbound sources:"
            echo "$https_rule" | jq -r '.[].IpRanges[].CidrIp // .[].UserIdGroupPairs[].GroupId' | sed 's/^/    - /'
        fi
        echo ""
    done
fi

# -----------------------------------------------------------------------------
# Step 4: 检查 SageMaker Studio Security Group
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 4: SageMaker Studio Security Group"
echo "=============================================="

# 获取 Domain 使用的 Security Group
STUDIO_SG_IDS=$(echo "$DOMAIN_DETAIL" | jq -r '.DefaultUserSettings.SecurityGroups[]' 2>/dev/null || echo "")

if [[ -z "$STUDIO_SG_IDS" ]]; then
    log_warn "Domain using default VPC security group"
else
    echo ""
    echo "Studio Security Groups: $STUDIO_SG_IDS"
    echo ""
    
    for sg_id in $STUDIO_SG_IDS; do
        echo "Checking: $sg_id"
        
        # 检查出站规则是否允许 443
        egress_443=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissionsEgress[?FromPort==\`443\` || FromPort==null]" \
            --output json)
        
        if [[ "$egress_443" == "[]" ]]; then
            log_error "  ⚠️  NO outbound rule for port 443!"
            echo "  Studio cannot reach VPC endpoints"
        else
            log_success "  ✓ Has outbound rule for port 443"
        fi
        echo ""
    done
fi

# -----------------------------------------------------------------------------
# Step 5: 检查 VPC Endpoint Policy
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Step 5: STS Endpoint Policy"
echo "=============================================="

if [[ -n "$STS_ENDPOINT_ID" ]]; then
    STS_POLICY=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "$STS_ENDPOINT_ID" \
        --query 'VpcEndpoints[0].PolicyDocument' --output text)
    
    echo ""
    echo "STS Endpoint Policy:"
    echo "$STS_POLICY" | jq . 2>/dev/null || echo "$STS_POLICY"
    echo ""
    
    # 检查是否是完全开放的策略
    if echo "$STS_POLICY" | grep -q '"Effect": "Allow"' && echo "$STS_POLICY" | grep -q '"Principal": "\*"'; then
        log_success "Policy allows all principals"
    else
        log_warn "Policy may restrict access - verify it allows your principals"
    fi
fi

echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo "=============================================="
echo " Summary & Recommendations"
echo "=============================================="
echo ""

if [[ ${#MISSING_ENDPOINTS[@]} -gt 0 ]]; then
    echo "❌ CRITICAL: Missing VPC Endpoints"
    echo "   Run: cd ../02-vpc && ./setup-all.sh"
    echo ""
fi

if [[ -z "$STS_ENDPOINT_ID" ]]; then
    echo "❌ CRITICAL: STS VPC Endpoint is missing"
    echo "   This is the most likely cause of 'Error acquiring credentials'"
    echo ""
    echo "   SageMaker Studio needs STS to:"
    echo "   - Assume the execution role"
    echo "   - Get temporary credentials for AWS API calls"
    echo ""
fi

echo "Common fixes for 'Error acquiring credentials' in VpcOnly mode:"
echo ""
echo "1. Ensure STS VPC Endpoint exists and is available"
echo "2. Ensure VPC Endpoint Security Groups allow HTTPS (443) from Studio SG"
echo "3. Ensure Studio Security Group allows outbound HTTPS (443)"
echo "4. Ensure VPC Endpoint Policies don't block access"
echo "5. Check that private DNS is enabled for Interface endpoints"
echo ""
echo "Reference:"
echo "  https://docs.aws.amazon.com/sagemaker/latest/dg/studio-notebooks-and-internet-access.html"
echo ""

