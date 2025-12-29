#!/bin/bash
# =============================================================================
# setup-all.sh - VPC 网络配置主控脚本
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================="
echo " SageMaker VPC Setup - Master Script"
echo "==============================================${NC}"
echo ""

# 检查 .env
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} .env file not found!"
    echo "Please create .env file first: cp .env.example .env"
    exit 1
fi

# 确认
echo "This script will create:"
echo "  - Security Groups (Studio, VPC Endpoints)"
echo "  - VPC Endpoints (SageMaker, STS, S3, Logs, etc.)"
echo ""

read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

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
    
    "${SCRIPT_DIR}/${script}"
    echo -e "${GREEN}[OK]${NC} Step ${step} completed"
}

run_step 1 "01-create-security-groups.sh" "Create Security Groups"
run_step 2 "02-create-vpc-endpoints.sh" "Create VPC Endpoints"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=============================================="
echo " VPC Setup Complete!"
echo "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Create S3 Buckets (see scripts/s3/)"
echo "  3. Create SageMaker Domain (see docs/05-sagemaker-domain.md)"
