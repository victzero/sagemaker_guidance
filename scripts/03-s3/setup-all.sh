#!/bin/bash
# =============================================================================
# setup-all.sh - S3 配置主控脚本
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
echo " SageMaker S3 Setup - Master Script"
echo "==============================================${NC}"
echo ""

if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} .env file not found!"
    echo "Please create .env file first: cp .env.example .env"
    exit 1
fi

echo "This script will create and configure:"
echo "  - S3 Buckets for each project"
echo "  - Shared assets bucket"
echo "  - Bucket policies"
echo "  - Lifecycle rules"
echo ""

read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

START_TIME=$(date +%s)

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

run_step 1 "01-create-buckets.sh" "Create S3 Buckets"
run_step 2 "02-configure-policies.sh" "Configure Bucket Policies"
run_step 3 "03-configure-lifecycle.sh" "Configure Lifecycle Rules"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=============================================="
echo " S3 Setup Complete!"
echo "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Create SageMaker Domain (see docs/05-sagemaker-domain.md)"
echo ""
echo "Created Buckets:"
source "${SCRIPT_DIR}/00-init.sh" 2>/dev/null
load_env 2>/dev/null
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        echo "  - $(get_bucket_name "$team" "$project")"
    done
done
if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  - $(get_shared_bucket_name)"
fi
