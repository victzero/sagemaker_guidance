#!/bin/bash
# =============================================================================
# verify.sh - 验证 VPC 网络配置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " VPC Network Verification"
echo "=============================================="
echo ""
echo "Checking resources with TAG_PREFIX: ${TAG_PREFIX}"
echo ""

errors=0

# -----------------------------------------------------------------------------
# 验证 VPC DNS 设置
# -----------------------------------------------------------------------------
verify_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

verify_section "VPC DNS Settings"

dns_hostnames=$(aws ec2 describe-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --attribute enableDnsHostnames \
    --query 'EnableDnsHostnames.Value' \
    --output text \
    --region "$AWS_REGION")

dns_support=$(aws ec2 describe-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --attribute enableDnsSupport \
    --query 'EnableDnsSupport.Value' \
    --output text \
    --region "$AWS_REGION")

if [[ "$dns_hostnames" == "True" ]]; then
    echo -e "  ${GREEN}✓${NC} DNS Hostnames: Enabled"
else
    echo -e "  ${RED}✗${NC} DNS Hostnames: Disabled (Required for VPCOnly mode)"
    ((errors++)) || true
fi

if [[ "$dns_support" == "True" ]]; then
    echo -e "  ${GREEN}✓${NC} DNS Support: Enabled"
else
    echo -e "  ${RED}✗${NC} DNS Support: Disabled (Required for VPCOnly mode)"
    ((errors++)) || true
fi

# -----------------------------------------------------------------------------
# 验证安全组
# -----------------------------------------------------------------------------
verify_section "Security Groups"

check_sg() {
    local sg_name=$1
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
        echo -e "  ${GREEN}✓${NC} $sg_name: $sg_id"
        return 0
    else
        echo -e "  ${RED}✗${NC} $sg_name: NOT FOUND"
        return 1
    fi
}

check_sg "${TAG_PREFIX}-studio" || ((errors++)) || true
check_sg "${TAG_PREFIX}-vpc-endpoints" || ((errors++)) || true

# -----------------------------------------------------------------------------
# 验证 VPC Endpoints
# -----------------------------------------------------------------------------
verify_section "VPC Endpoints"

check_endpoint() {
    local service=$1
    local full_service="com.amazonaws.${AWS_REGION}.${service}"
    
    local endpoint_id=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${full_service}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    local state=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${full_service}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[0].State' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$endpoint_id" != "None" && -n "$endpoint_id" ]]; then
        if [[ "$state" == "available" ]]; then
            echo -e "  ${GREEN}✓${NC} $service: $endpoint_id (available)"
        else
            echo -e "  ${YELLOW}!${NC} $service: $endpoint_id ($state)"
        fi
        return 0
    else
        echo -e "  ${RED}✗${NC} $service: NOT FOUND"
        return 1
    fi
}

# 必需的 Endpoints
echo "Required Endpoints:"
check_endpoint "sagemaker.api" || ((errors++)) || true
check_endpoint "sagemaker.runtime" || ((errors++)) || true
check_endpoint "notebook" || ((errors++)) || true
check_endpoint "sagemaker.studio" || ((errors++)) || true
check_endpoint "sts" || ((errors++)) || true
check_endpoint "logs" || ((errors++)) || true
check_endpoint "s3" || ((errors++)) || true

echo ""
echo "Optional Endpoints:"
check_endpoint "ecr.api" || true
check_endpoint "ecr.dkr" || true
check_endpoint "kms" || true
check_endpoint "ssm" || true

# -----------------------------------------------------------------------------
# 验证子网
# -----------------------------------------------------------------------------
check_subnet() {
    local subnet_id=$1
    
    local subnet_info=$(aws ec2 describe-subnets \
        --subnet-ids "$subnet_id" \
        --query 'Subnets[0].{AZ:AvailabilityZone,CIDR:CidrBlock,AvailableIPs:AvailableIpAddressCount}' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [[ -n "$subnet_info" && "$subnet_info" != "null" ]]; then
        local az=$(echo "$subnet_info" | jq -r '.AZ')
        local cidr=$(echo "$subnet_info" | jq -r '.CIDR')
        local available_ips=$(echo "$subnet_info" | jq -r '.AvailableIPs')
        
        if [[ $available_ips -gt 50 ]]; then
            echo -e "  ${GREEN}✓${NC} $subnet_id: $az, $cidr, $available_ips IPs available"
        else
            echo -e "  ${YELLOW}!${NC} $subnet_id: $az, $cidr, $available_ips IPs (low!)"
        fi
        return 0
    else
        echo -e "  ${RED}✗${NC} $subnet_id: NOT FOUND"
        return 1
    fi
}

verify_section "Subnets"

check_subnet "$PRIVATE_SUBNET_1_ID" || ((errors++)) || true
check_subnet "$PRIVATE_SUBNET_2_ID" || ((errors++)) || true

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}Verification PASSED${NC} - VPC network configured correctly"
else
    echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
fi
echo "=============================================="

exit $errors
