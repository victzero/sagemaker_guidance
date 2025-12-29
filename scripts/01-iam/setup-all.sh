#!/bin/bash
# =============================================================================
# setup-all.sh - 主控脚本：按顺序执行所有 IAM 设置
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

# 加载环境变量显示预览
source "${SCRIPT_DIR}/.env"

# 计算预期资源数量
team_count=0
project_count=0
admin_count=0

for admin in $ADMIN_USERS; do ((admin_count++)) || true; done
for team in $TEAMS; do
    ((team_count++)) || true
    team_upper=$(echo "$team" | tr '[:lower:]' '[:upper:]')
    var_name="${team_upper}_PROJECTS"
    projects="${!var_name}"
    for project in $projects; do
        ((project_count++)) || true
    done
done

expected_policies=$((3 + team_count + project_count * 2))
expected_groups=$((2 + team_count + project_count))

# 确认执行
echo -e "${YELLOW}This script will create the following AWS IAM resources:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  IAM Path:      /${COMPANY}-sagemaker/"
echo ""
echo "  Resources to create:"
echo "    - Policies:  ~$expected_policies (base, team, project, execution)"
echo "    - Groups:    ~$expected_groups (admin, readonly, team, project)"
echo "    - Users:     Admin + team members"
echo "    - Roles:     $project_count (one per project)"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws iam list-* --path-prefix /${COMPANY}-sagemaker/"
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
echo -e "${YELLOW}[IMPORTANT]${NC} User credentials saved to:"
echo "  ${SCRIPT_DIR}/output/user-credentials.txt"
echo ""
echo "Please distribute these credentials securely and delete the file!"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Filter resources in AWS Console or CLI:"
echo "  aws iam list-users --path-prefix /${COMPANY}-sagemaker/"
echo "  aws iam list-groups --path-prefix /${COMPANY}-sagemaker/"
echo "  aws iam list-roles --path-prefix /${COMPANY}-sagemaker/"
echo "  aws iam list-policies --scope Local --path-prefix /${COMPANY}-sagemaker/"
echo ""
echo "Next Steps:"
echo "  1. Distribute user credentials securely"
echo "  2. Create SageMaker Domain (see 05-sagemaker-domain.md)"
echo "  3. Create User Profiles (see 06-user-profile.md)"
echo "  4. Create Shared Spaces (see 07-shared-space.md)"
