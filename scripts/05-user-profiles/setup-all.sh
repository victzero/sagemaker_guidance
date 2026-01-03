#!/bin/bash
# =============================================================================
# setup-all.sh - User Profiles & Private Spaces 主控脚本
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
echo -e " User Profiles & Private Spaces Setup"
echo -e "==============================================${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
validate_team_env
check_aws_cli

# 设置配置
export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
export DOMAIN_NAME="${DOMAIN_NAME:-${COMPANY}-ml-platform}"

# 获取 Domain ID
DOMAIN_INFO_FILE="${SCRIPT_DIR}/../04-sagemaker-domain/output/domain-info.env"
if [[ -f "$DOMAIN_INFO_FILE" ]]; then
    source "$DOMAIN_INFO_FILE"
fi

if [[ -z "$DOMAIN_ID" ]]; then
    DOMAIN_ID=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
fi

if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
    echo -e "${RED}[ERROR]${NC} Domain not found: $DOMAIN_NAME"
    echo "  Please run 04-sagemaker-domain/setup-all.sh first"
    exit 1
fi

# 确认执行
echo -e "${YELLOW}This script will create User Profiles and Private Spaces:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  Domain ID:     $DOMAIN_ID"
echo "  Domain Name:   $DOMAIN_NAME"
echo ""
echo "  Naming format:"
echo "    User Profile: profile-{team}-{project}-{user}"
echo "    Private Space: space-{team}-{project}-{user}"
echo ""

# ========== User Profiles & Spaces Preview ==========
echo -e "${BLUE}【Resources to Create】${NC}"
profile_count=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    projects=$(get_projects_for_team "$team")
    
    for project in $projects; do
        project_formatted=$(format_name "$project")
        execution_role="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
        users=$(get_users_for_project "$team" "$project")
        
        # 简化项目名用于命名
        project_short=$(echo "$project" | cut -d'-' -f1)
        
        if [[ -n "$users" ]]; then
            echo ""
            echo "  Team [$team] Project [$project]:"
            echo "    Execution Role: $execution_role"
            for user in $users; do
                profile_name="profile-${team}-${project_short}-${user}"
                space_name="space-${team}-${project_short}-${user}"
                iam_user="sm-${team}-${user}"
                echo "    - Profile: $profile_name"
                echo "      Space:   $space_name"
                echo "      IAM:     $iam_user"
                ((profile_count++)) || true
            done
        fi
    done
done

echo ""
echo "  Total: $profile_count user profiles + $profile_count private spaces"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: ${NC}"
echo -e "${CYAN}  - $profile_count User Profiles${NC}"
echo -e "${CYAN}  - $profile_count Private Spaces${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws sagemaker list-user-profiles --domain-id $DOMAIN_ID"
echo "  aws sagemaker list-spaces --domain-id $DOMAIN_ID"
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

# 确保脚本可执行
chmod +x "${SCRIPT_DIR}/01-create-user-profiles.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/02-create-private-spaces.sh" 2>/dev/null || true

# 执行所有步骤
run_step 1 "01-create-user-profiles.sh" "Create User Profiles"
run_step 2 "02-create-private-spaces.sh" "Create Private Spaces"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}=============================================="
echo -e " User Profiles & Private Spaces Setup Complete!"
echo -e "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${GREEN}Created Resources:${NC}"
echo ""
echo "  User Profiles:   $profile_count"
echo "  Private Spaces:  $profile_count"
echo ""
echo "Resource lists saved to:"
echo "  - ${SCRIPT_DIR}/output/user-profiles.csv"
echo "  - ${SCRIPT_DIR}/output/private-spaces.csv"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Users can now login to Studio and use their Private Space"
echo "  3. Distribute credentials to users (see 01-iam/output/user-credentials.txt)"
echo ""
