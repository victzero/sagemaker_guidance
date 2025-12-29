#!/bin/bash
# =============================================================================
# setup-all.sh - 主控脚本：按顺序执行所有 IAM 设置
# =============================================================================
# 使用方法: ./setup-all.sh [--dry-run]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查参数
if [[ "$1" == "--dry-run" ]]; then
    export DRY_RUN=true
    echo "Running in DRY-RUN mode (commands will be printed but not executed)"
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================="
echo " SageMaker IAM Setup - Master Script"
echo "==============================================${NC}"
echo ""

# 检查 .env 文件
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo -e "${RED}[ERROR]${NC} .env file not found!"
    echo ""
    echo "Please create .env file first:"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your values"
    echo ""
    exit 1
fi

# 确认执行
echo -e "${YELLOW}This script will create the following AWS IAM resources:${NC}"
echo "  - IAM Policies (base, team, project, execution)"
echo "  - IAM Groups (admin, readonly, team, project)"
echo "  - IAM Users (admin and team members)"
echo "  - IAM Roles (SageMaker Execution Roles)"
echo "  - Policy bindings and group memberships"
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
    read -p "Do you want to proceed? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
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
run_step 1 "01-create-policies.sh" "Create IAM Policies"
run_step 2 "02-create-groups.sh" "Create IAM Groups"
run_step 3 "03-create-users.sh" "Create IAM Users"
run_step 4 "04-create-roles.sh" "Create Execution Roles"
run_step 5 "05-bind-policies.sh" "Bind Policies to Groups"
run_step 6 "06-add-users-to-groups.sh" "Add Users to Groups"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=============================================="
echo " Setup Complete!"
echo "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo "Next Steps:"
echo "  1. Distribute user credentials securely"
echo "  2. Create SageMaker Domain (see 05-sagemaker-domain.md)"
echo "  3. Create User Profiles (see 06-user-profile.md)"
echo "  4. Create Shared Spaces (see 07-shared-space.md)"
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
    echo -e "${YELLOW}[IMPORTANT]${NC} User credentials saved to:"
    echo "  ${SCRIPT_DIR}/output/user-credentials.txt"
    echo ""
    echo "Please distribute these credentials securely and delete the file!"
fi
