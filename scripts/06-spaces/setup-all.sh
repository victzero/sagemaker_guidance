#!/bin/bash
# =============================================================================
# setup-all.sh - Shared Spaces 主控脚本
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
echo -e " Shared Spaces Setup - Master Script"
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
export SPACE_EBS_SIZE_GB="${SPACE_EBS_SIZE_GB:-50}"

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

# 检查 DefaultSpaceSettings 是否存在
echo -e "${BLUE}[INFO]${NC} Checking Domain DefaultSpaceSettings..."
default_space_role=$(aws sagemaker describe-domain \
    --domain-id "$DOMAIN_ID" \
    --query 'DefaultSpaceSettings.ExecutionRole' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -z "$default_space_role" || "$default_space_role" == "None" ]]; then
    echo -e "${YELLOW}[WARN]${NC} DefaultSpaceSettings not configured, fixing..."
    
    # 获取 Domain 默认 Execution Role
    default_role_arn=$(aws iam get-role \
        --role-name "SageMaker-Domain-DefaultExecutionRole" \
        --query 'Role.Arn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$default_role_arn" ]]; then
        echo -e "${RED}[ERROR]${NC} Domain default execution role not found!"
        echo "  Please run: cd ../01-iam && ./04-create-roles.sh"
        exit 1
    fi
    
    # 更新 Domain 添加 DefaultSpaceSettings
    aws sagemaker update-domain \
        --domain-id "$DOMAIN_ID" \
        --default-space-settings "{\"ExecutionRole\": \"$default_role_arn\"}" \
        --region "$AWS_REGION"
    
    echo -e "${GREEN}[OK]${NC} DefaultSpaceSettings configured"
    
    # 等待 Domain 更新完成
    echo -e "${BLUE}[INFO]${NC} Waiting for Domain update..."
    sleep 5
    
    while true; do
        status=$(aws sagemaker describe-domain \
            --domain-id "$DOMAIN_ID" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION")
        
        if [[ "$status" == "InService" ]]; then
            break
        elif [[ "$status" == "Failed" ]]; then
            echo -e "${RED}[ERROR]${NC} Domain update failed"
            exit 1
        fi
        echo -n "."
        sleep 3
    done
    echo ""
else
    echo -e "${GREEN}[OK]${NC} DefaultSpaceSettings already configured"
fi

# 辅助函数：获取项目 Owner
get_project_owner() {
    local team=$1
    local project=$2
    local users=$(get_users_for_project "$team" "$project")
    echo "$users" | awk '{print $1}'
}

# 确认执行
echo -e "${YELLOW}This script will create Shared Spaces in SageMaker Domain:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  Domain ID:     $DOMAIN_ID"
echo "  Domain Name:   $DOMAIN_NAME"
echo "  EBS Size:      ${SPACE_EBS_SIZE_GB} GB per space"
echo ""

# ========== Shared Spaces ==========
echo -e "${BLUE}【Shared Spaces】${NC}"
space_count=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    projects=$(get_projects_for_team "$team")
    
    for project in $projects; do
        space_name="space-${team}-${project}"
        owner_user=$(get_project_owner "$team" "$project")
        
        if [[ -z "$owner_user" ]]; then
            continue
        fi
        
        owner_profile="profile-${team}-${owner_user}"
        members=$(get_users_for_project "$team" "$project")
        
        echo "  Team [$team] Project [$project]:"
        echo "    Space Name: $space_name"
        echo "    Owner:      $owner_profile"
        echo -n "    Members:    "
        
        member_list=""
        for user in $members; do
            member_list+="profile-${team}-${user}, "
        done
        echo "${member_list%, }"
        echo ""
        
        ((space_count++)) || true
    done
done

echo "  Total: $space_count spaces"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $space_count Shared Spaces to create${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
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

# 执行所有步骤
run_step 1 "01-create-spaces.sh" "Create Shared Spaces"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}=============================================="
echo -e " Shared Spaces Setup Complete!"
echo -e "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${GREEN}Created Resources:${NC}"
echo ""
echo "  Shared Spaces: $space_count"
echo "  EBS per Space: ${SPACE_EBS_SIZE_GB} GB"
echo ""
echo "Space list saved to:"
echo "  - ${SCRIPT_DIR}/output/spaces.csv"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Run full platform verification: cd .. && ./verify-all.sh"
echo "  3. Distribute user credentials and provide login instructions"
echo ""
echo "User Login Flow:"
echo "  1. IAM User logs into AWS Console"
echo "  2. Navigate to SageMaker → Studio"
echo "  3. Select their User Profile (profile-{team}-{name})"
echo "  4. Click 'Open Studio'"
echo "  5. Access their project's Shared Space"
echo ""

