#!/bin/bash
# =============================================================================
# setup-all.sh - SageMaker Domain 主控脚本
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
echo -e " SageMaker Domain Setup - Master Script"
echo -e "==============================================${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
check_aws_cli

# 设置 Domain 特有配置
export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
export DOMAIN_NAME="${DOMAIN_NAME:-${COMPANY}-ml-platform}"
export IDLE_TIMEOUT_MINUTES="${IDLE_TIMEOUT_MINUTES:-60}"
export DEFAULT_INSTANCE_TYPE="${DEFAULT_INSTANCE_TYPE:-ml.t3.medium}"
export DEFAULT_EBS_SIZE_GB="${DEFAULT_EBS_SIZE_GB:-100}"

# 验证 VPC 配置
if [[ -z "$VPC_ID" || -z "$PRIVATE_SUBNET_1_ID" || -z "$PRIVATE_SUBNET_2_ID" ]]; then
    echo -e "${RED}[ERROR]${NC} Missing VPC configuration"
    echo "  Required: VPC_ID, PRIVATE_SUBNET_1_ID, PRIVATE_SUBNET_2_ID"
    echo "  Please configure in .env.shared"
    exit 1
fi

# 获取安全组 ID
SG_NAME="${TAG_PREFIX}-studio"
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
    echo -e "${RED}[ERROR]${NC} Security group ${SG_NAME} not found"
    echo "  Please run scripts/02-vpc/setup-all.sh first"
    exit 1
fi

# 确认执行
echo -e "${YELLOW}This script will create the following SageMaker resources:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  Region:        $AWS_REGION"
echo "  VPC ID:        $VPC_ID"
subnet_list="$PRIVATE_SUBNET_1_ID, $PRIVATE_SUBNET_2_ID"
[[ -n "$PRIVATE_SUBNET_3_ID" ]] && subnet_list="$subnet_list, $PRIVATE_SUBNET_3_ID"
echo "  Subnets:       $subnet_list"
echo "  Security Group: $SG_ID"
echo ""

# ========== Domain ==========
echo -e "${BLUE}【SageMaker Domain】${NC}"
echo "  Domain Name:       $DOMAIN_NAME"
echo "  Auth Mode:         IAM"
echo "  Network Mode:      VpcOnly"
echo "  Default Instance:  $DEFAULT_INSTANCE_TYPE"
echo "  Default EBS Size:  ${DEFAULT_EBS_SIZE_GB} GB"
echo "  Idle Shutdown:     ${IDLE_TIMEOUT_MINUTES} minutes (built-in)"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: 1 Domain (with built-in idle shutdown)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws sagemaker list-domains --query \"Domains[?DomainName=='${DOMAIN_NAME}']\""
echo ""

# 运行前置检查
echo ""
echo -e "${YELLOW}Running pre-flight checks...${NC}"
echo ""

if ! "${SCRIPT_DIR}/check.sh" --quick; then
    echo ""
    echo -e "${RED}Pre-flight checks failed. Please fix the issues above.${NC}"
    echo ""
    echo "For detailed diagnostics, run:"
    echo "  ./check.sh"
    echo ""
    exit 1
fi

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
run_step 1 "01-create-domain.sh" "Create SageMaker Domain (with built-in idle shutdown)"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}=============================================="
echo -e " SageMaker Domain Setup Complete!"
echo -e "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${GREEN}Created Resources:${NC}"
echo ""
echo "  Domain:"
echo "    - Name: $DOMAIN_NAME"
echo "    - Mode: VpcOnly + IAM Auth"
echo "    - Idle Shutdown: ${IDLE_TIMEOUT_MINUTES} minutes (built-in)"
echo ""
echo "Resource info saved to:"
echo "  - ${SCRIPT_DIR}/output/domain-info.env"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Create User Profiles: cd ../05-user-profiles && ./setup-all.sh"
echo "  Users can now login to Studio and use Private Space"
echo ""

