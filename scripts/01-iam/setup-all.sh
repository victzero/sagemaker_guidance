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

# 解析命令行参数
ENABLE_CONSOLE=""
for arg in "$@"; do
    case $arg in
        --enable-console-login)
            ENABLE_CONSOLE="--enable-console-login"
            shift
            ;;
    esac
done

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
validate_team_env
check_aws_cli

# 设置 IAM 特有配置
if [[ -z "$IAM_PATH" ]]; then
    IAM_PATH="/${COMPANY}-sagemaker/"
fi
export IAM_PATH

# Console 登录设置
ENABLE_CONSOLE_LOGIN_DISPLAY="DISABLED (default)"
if [[ -n "$ENABLE_CONSOLE" ]] || [[ "$ENABLE_CONSOLE_LOGIN" == "true" ]]; then
    ENABLE_CONSOLE_LOGIN_DISPLAY="ENABLED"
fi

# Canvas 功能设置（默认开启）
ENABLE_CANVAS="${ENABLE_CANVAS:-true}"
ENABLE_CANVAS_DISPLAY="ENABLED (default)"
if [[ "$ENABLE_CANVAS" != "true" ]]; then
    ENABLE_CANVAS_DISPLAY="DISABLED"
fi

# MLflow 功能设置（默认开启）
ENABLE_MLFLOW="${ENABLE_MLFLOW:-true}"
ENABLE_MLFLOW_DISPLAY="ENABLED (default)"
if [[ "$ENABLE_MLFLOW" != "true" ]]; then
    ENABLE_MLFLOW_DISPLAY="DISABLED"
fi

# 别名函数（兼容旧代码）
get_projects() { get_projects_for_team "$@"; }
get_users() { get_users_for_project "$@"; }

# 确认执行
echo -e "${YELLOW}This script will create the following AWS IAM resources:${NC}"
echo ""
echo "  Company:          $COMPANY"
echo "  IAM Path:         ${IAM_PATH}"
echo "  Console Login:    ${ENABLE_CONSOLE_LOGIN_DISPLAY}"
echo "  Canvas (ML):      ${ENABLE_CANVAS_DISPLAY}"
echo "  MLflow (Track):   ${ENABLE_MLFLOW_DISPLAY}"
echo "  Studio Isolation: ENABLED (always)"
echo ""

# ========== Policies ==========
echo -e "${BLUE}【Policies】${NC}"
echo "  Base policies:"
echo "    - SageMaker-Studio-Base-Access"
echo "    - SageMaker-ReadOnly-Access"
echo "    - SageMaker-User-SelfService (password, MFA only)"
echo "    - SageMaker-User-Boundary"

policy_count=4
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    echo "  Team [$team] policies:"
    echo "    - SageMaker-${team_formatted}-Team-Access"
    ((policy_count++)) || true
    
    projects=$(get_projects "$team")
    for project in $projects; do
        project_formatted=$(format_name "$project")
        echo "    - SageMaker-${team_formatted}-${project_formatted}-Access"
        echo "    - SageMaker-${team_formatted}-${project_formatted}-ExecutionPolicy"
        ((policy_count+=2)) || true
    done
done
echo "  Total: $policy_count policies"
echo ""

# ========== Groups ==========
echo -e "${BLUE}【Groups】${NC}"
echo "  Platform groups:"
echo "    - sagemaker-admins"
echo "    - sagemaker-readonly"

group_count=2
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    echo "  Team [$team] groups:"
    echo "    - sagemaker-${team_fullname}"
    ((group_count++)) || true
    
    projects=$(get_projects "$team")
    for project in $projects; do
        echo "    - sagemaker-${team}-${project}"
        ((group_count++)) || true
    done
done
echo "  Total: $group_count groups"
echo ""

# ========== Users ==========
echo -e "${BLUE}【Users】${NC}"
echo "  Admin users:"
user_count=0
for admin in $ADMIN_USERS; do
    echo "    - sm-admin-${admin}"
    ((user_count++)) || true
done

for team in $TEAMS; do
    projects=$(get_projects "$team")
    for project in $projects; do
        users=$(get_users "$team" "$project")
        if [[ -n "$users" ]]; then
            echo "  Team [$team] project [$project] users:"
            for user in $users; do
                echo "    - sm-${team}-${user}"
                ((user_count++)) || true
            done
        fi
    done
done
echo "  Total: $user_count users"
echo ""

# ========== Roles ==========
echo -e "${BLUE}【Execution Roles】${NC}"
echo "  Domain default role:"
echo "    - SageMaker-Domain-DefaultExecutionRole"
role_count=1

echo "  Project roles:"
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    
    projects=$(get_projects "$team")
    for project in $projects; do
        project_formatted=$(format_name "$project")
        echo "    - SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
        ((role_count++)) || true
    done
done
echo "  Total: $role_count roles"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $policy_count policies, $group_count groups, $user_count users, $role_count roles${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws iam list-policies --scope Local --path-prefix ${IAM_PATH}"
echo "  aws iam list-groups --path-prefix ${IAM_PATH}"
echo "  aws iam list-users --path-prefix ${IAM_PATH}"
echo "  aws iam list-roles --path-prefix ${IAM_PATH}"
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
    local extra_args=${4:-}
    
    echo ""
    echo -e "${BLUE}=============================================="
    echo -e " Step ${step}: ${description}"
    echo -e "==============================================${NC}"
    
    if [[ -x "${SCRIPT_DIR}/${script}" ]]; then
        "${SCRIPT_DIR}/${script}" $extra_args
        echo -e "${GREEN}[OK]${NC} Step ${step} completed"
    else
        echo -e "${RED}[ERROR]${NC} Script ${script} not found or not executable"
        exit 1
    fi
}

# 执行所有步骤
run_step 1 "01-create-policies.sh" "Create IAM Policies"
run_step 2 "02-create-groups.sh" "Create IAM Groups"
run_step 3 "03-create-users.sh" "Create IAM Users" "$ENABLE_CONSOLE"
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
if [[ -n "$ENABLE_CONSOLE" ]] || [[ "$ENABLE_CONSOLE_LOGIN" == "true" ]]; then
    echo -e "${YELLOW}[IMPORTANT]${NC} Console login is ENABLED."
    echo "  User credentials saved to: ${SCRIPT_DIR}/output/user-credentials.txt"
    echo ""
    echo "Please distribute these credentials securely and delete the file!"
else
    echo "Console login is DISABLED (default)."
    echo "Users can access SageMaker via CreatePresignedDomainUrl API."
fi
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
