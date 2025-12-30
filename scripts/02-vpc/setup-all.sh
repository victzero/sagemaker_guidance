#!/bin/bash
# =============================================================================
# setup-all.sh - VPC 网络配置主控脚本
# =============================================================================
# 使用方法: ./setup-all.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================="
echo -e " SageMaker VPC Setup - Master Script"
echo -e "==============================================${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
check_aws_cli

# VPC 特有验证
validate_vpc_env() {
    log_info "Validating VPC environment variables..."
    
    local required_vars=(
        "VPC_ID"
        "VPC_CIDR"
        "PRIVATE_SUBNET_1_ID"
        "PRIVATE_SUBNET_2_ID"
    )
    
    local missing=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required VPC environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        log_info "Please configure these in .env.shared or .env.local"
        exit 1
    fi
    
    log_success "VPC environment variables validated"
}

validate_vpc_env

# 设置 VPC 特有配置（export 使子脚本可访问）
export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
export CREATE_ECR_ENDPOINTS="${CREATE_ECR_ENDPOINTS:-false}"
export CREATE_KMS_ENDPOINT="${CREATE_KMS_ENDPOINT:-false}"
export CREATE_SSM_ENDPOINT="${CREATE_SSM_ENDPOINT:-false}"

# 确认执行
echo -e "${YELLOW}This script will create the following AWS VPC resources:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  Region:        $AWS_REGION"
echo "  VPC ID:        $VPC_ID"
echo "  VPC CIDR:      $VPC_CIDR"
echo "  Subnet 1:      $PRIVATE_SUBNET_1_ID"
echo "  Subnet 2:      $PRIVATE_SUBNET_2_ID"
echo ""

# ========== Security Groups ==========
echo -e "${BLUE}【Security Groups】${NC}"
sg_count=0

echo "  SageMaker Studio security group:"
echo "    - ${TAG_PREFIX}-studio"
echo "      Ingress rules:"
echo "        • Allow all from self (internal communication)"
echo "        • Allow HTTPS (443) from VPC CIDR"
echo "      Egress rules:"
echo "        • Allow all to self"
((sg_count++)) || true

echo "  VPC Endpoints security group:"
echo "    - ${TAG_PREFIX}-vpc-endpoints"
echo "      Ingress rules:"
echo "        • Allow HTTPS (443) from VPC CIDR"
((sg_count++)) || true

echo "  Total: $sg_count security groups"
echo ""

# ========== VPC Endpoints (Required) ==========
echo -e "${BLUE}【VPC Endpoints - Required】${NC}"
endpoint_count=0

echo "  Interface Endpoints (PrivateLink):"
echo "    - vpce-${TAG_PREFIX}-sagemaker-api"
echo "        Service: com.amazonaws.${AWS_REGION}.sagemaker.api"
((endpoint_count++)) || true

echo "    - vpce-${TAG_PREFIX}-sagemaker-runtime"
echo "        Service: com.amazonaws.${AWS_REGION}.sagemaker.runtime"
((endpoint_count++)) || true

echo "    - vpce-${TAG_PREFIX}-sagemaker-studio"
echo "        Service: aws.sagemaker.${AWS_REGION}.studio"
((endpoint_count++)) || true

echo "    - vpce-${TAG_PREFIX}-sts"
echo "        Service: com.amazonaws.${AWS_REGION}.sts"
((endpoint_count++)) || true

echo "    - vpce-${TAG_PREFIX}-logs"
echo "        Service: com.amazonaws.${AWS_REGION}.logs"
((endpoint_count++)) || true

echo ""
echo "  Gateway Endpoints:"
echo "    - vpce-${TAG_PREFIX}-s3"
echo "        Service: com.amazonaws.${AWS_REGION}.s3"
((endpoint_count++)) || true

echo ""

# ========== VPC Endpoints (Optional) ==========
echo -e "${BLUE}【VPC Endpoints - Optional】${NC}"
optional_count=0

if [[ "${CREATE_ECR_ENDPOINTS}" == "true" ]]; then
    echo "  ECR Endpoints (enabled):"
    echo "    - vpce-${TAG_PREFIX}-ecr-api"
    echo "        Service: com.amazonaws.${AWS_REGION}.ecr.api"
    ((endpoint_count++)) || true
    ((optional_count++)) || true
    
    echo "    - vpce-${TAG_PREFIX}-ecr-dkr"
    echo "        Service: com.amazonaws.${AWS_REGION}.ecr.dkr"
    ((endpoint_count++)) || true
    ((optional_count++)) || true
else
    echo "  ECR Endpoints: disabled (set CREATE_ECR_ENDPOINTS=true to enable)"
fi

if [[ "${CREATE_KMS_ENDPOINT}" == "true" ]]; then
    echo "  KMS Endpoint (enabled):"
    echo "    - vpce-${TAG_PREFIX}-kms"
    echo "        Service: com.amazonaws.${AWS_REGION}.kms"
    ((endpoint_count++)) || true
    ((optional_count++)) || true
else
    echo "  KMS Endpoint: disabled (set CREATE_KMS_ENDPOINT=true to enable)"
fi

if [[ "${CREATE_SSM_ENDPOINT}" == "true" ]]; then
    echo "  SSM Endpoint (enabled):"
    echo "    - vpce-${TAG_PREFIX}-ssm"
    echo "        Service: com.amazonaws.${AWS_REGION}.ssm"
    ((endpoint_count++)) || true
    ((optional_count++)) || true
else
    echo "  SSM Endpoint: disabled (set CREATE_SSM_ENDPOINT=true to enable)"
fi

echo "  Total optional: $optional_count endpoints"
echo ""

# ========== Endpoint Configuration ==========
echo -e "${BLUE}【Endpoint Configuration】${NC}"
echo "  Interface Endpoints will be configured with:"
echo "    • Subnets: $PRIVATE_SUBNET_1_ID, $PRIVATE_SUBNET_2_ID"
echo "    • Security Group: ${TAG_PREFIX}-vpc-endpoints"
echo "    • Private DNS: enabled"
echo "    • Tags: Name, ManagedBy=${TAG_PREFIX}"
echo ""
echo "  Gateway Endpoints will be configured with:"
route_table_list="$ROUTE_TABLE_1_ID"
[[ -n "$ROUTE_TABLE_2_ID" ]] && route_table_list="$route_table_list, $ROUTE_TABLE_2_ID"
[[ -n "$ROUTE_TABLE_3_ID" ]] && route_table_list="$route_table_list, $ROUTE_TABLE_3_ID"
echo "    • Route Tables: $route_table_list"
echo "    • Tags: Name, ManagedBy=${TAG_PREFIX}"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $sg_count security groups, $endpoint_count VPC endpoints${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws ec2 describe-security-groups --filters \"Name=tag:ManagedBy,Values=${TAG_PREFIX}\" --query 'SecurityGroups[].{Name:GroupName,ID:GroupId}' --output table"
echo "  aws ec2 describe-vpc-endpoints --filters \"Name=tag:ManagedBy,Values=${TAG_PREFIX}\" --query 'VpcEndpoints[].{Name:Tags[?Key==\`Name\`].Value|[0],ID:VpcEndpointId,Service:ServiceName}' --output table"
echo ""

read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 记录开始时间
START_TIME=$(date +%s)

# 执行步骤
run_step() {
    local step=$1
    local script=$2
    local description=$3
    
    echo ""
    echo -e "${BLUE}=============================================="
    echo -e " Step ${step}: ${description}"
    echo -e "==============================================${NC}"
    
    if [[ -x "${SCRIPT_DIR}/${script}" ]]; then
        "${SCRIPT_DIR}/${script}"
        echo -e "${GREEN}[OK]${NC} Step ${step} completed"
    else
        echo -e "${RED}[ERROR]${NC} Script ${script} not found or not executable"
        exit 1
    fi
}

# 执行所有步骤
run_step 1 "01-create-security-groups.sh" "Create Security Groups"
run_step 2 "02-create-vpc-endpoints.sh" "Create VPC Endpoints"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}=============================================="
echo -e " VPC Setup Complete!"
echo -e "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${GREEN}Created Resources:${NC}"
echo ""
echo "  Security Groups:"
echo "    - ${TAG_PREFIX}-studio"
echo "    - ${TAG_PREFIX}-vpc-endpoints"
echo ""
echo "  VPC Endpoints:"
echo "    - sagemaker.api, sagemaker.runtime, sagemaker.studio"
echo "    - sts, logs, s3"
if [[ "${CREATE_ECR_ENDPOINTS}" == "true" ]]; then
    echo "    - ecr.api, ecr.dkr"
fi
if [[ "${CREATE_KMS_ENDPOINT}" == "true" ]]; then
    echo "    - kms"
fi
if [[ "${CREATE_SSM_ENDPOINT}" == "true" ]]; then
    echo "    - ssm"
fi
echo ""
echo "Resource IDs saved to:"
echo "  - ${SCRIPT_DIR}/output/security-groups.env"
echo "  - ${SCRIPT_DIR}/output/vpc-endpoints.env"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Filter resources in AWS Console or CLI:"
echo "  aws ec2 describe-security-groups --filters \"Name=tag:ManagedBy,Values=${TAG_PREFIX}\""
echo "  aws ec2 describe-vpc-endpoints --filters \"Name=tag:ManagedBy,Values=${TAG_PREFIX}\""
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Create S3 Buckets (see scripts/03-s3/)"
echo "  3. Create SageMaker Domain (see docs/05-sagemaker-domain.md)"
echo ""
