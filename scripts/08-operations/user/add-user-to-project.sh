#!/bin/bash
# =============================================================================
# add-user-to-project.sh - 将已有用户添加到新项目
# =============================================================================
#
# 场景: 员工跨项目协作，需要访问另一个项目
#
# 涉及资源 (通过 lib/ 工厂函数):
#   - IAM User: 已存在，不变更
#   - IAM Group: 加入新项目组
#   - User Profile: 创建新项目的 profile-{team}-{project}-{user}
#   - Private Space: 创建新项目的 space-{team}-{project}-{user}
#
# 使用方法: ./add-user-to-project.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# 加载工厂函数库
source "${SCRIPTS_ROOT}/lib/discovery.sh"
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 将已有用户添加到新项目"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. 输入已有的 IAM 用户名
# -----------------------------------------------------------------------------
echo "请输入已有的 IAM 用户名"
echo "格式: sm-{team}-{user}, 例如: sm-rc-alice"
echo ""

while true; do
    read -p "IAM 用户名: " IAM_USERNAME
    
    # 验证格式
    if [[ ! "$IAM_USERNAME" =~ ^sm-[a-z]+-[a-z0-9]+$ ]]; then
        log_error "用户名格式不正确，应为 sm-{team}-{user}"
        continue
    fi
    
    # 检查用户是否存在
    if ! iam_user_exists "$IAM_USERNAME"; then
        log_error "IAM 用户 $IAM_USERNAME 不存在"
        log_info "如需创建新用户，请使用 add-user.sh"
        continue
    fi
    
    break
done

# 解析用户名获取团队和用户
# sm-rc-alice -> team=rc, user=alice
PARTS=(${IAM_USERNAME//-/ })
USER_TEAM="${PARTS[1]}"
USER_NAME="${PARTS[2]}"

# 获取团队全称
USER_TEAM_FULLNAME=$(get_team_fullname "$USER_TEAM")
if [[ -z "$USER_TEAM_FULLNAME" ]]; then
    log_error "无法识别团队: $USER_TEAM"
    exit 1
fi

log_info "已识别用户: $USER_NAME (团队: $USER_TEAM / $USER_TEAM_FULLNAME)"
echo ""

# -----------------------------------------------------------------------------
# 2. 获取用户当前所属项目
# -----------------------------------------------------------------------------
echo "查询用户当前所属项目..."

CURRENT_GROUPS=$(aws iam list-groups-for-user --user-name "$IAM_USERNAME" \
    --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")

echo "当前所属 Groups:"
for group in $CURRENT_GROUPS; do
    echo "  - $group"
done
echo ""

# -----------------------------------------------------------------------------
# 3. 选择要加入的项目 (使用动态发现)
# -----------------------------------------------------------------------------
echo "可加入的项目 (团队 $USER_TEAM):"

# 使用动态发现获取项目列表
projects=($(get_project_list_dynamic "$USER_TEAM"))

if [[ ${#projects[@]} -eq 0 ]]; then
    log_error "团队 $USER_TEAM 没有可用项目"
    log_info "请先使用 project/add-project.sh 创建项目"
    exit 1
fi

# 过滤已加入的项目
available_projects=()
for project in "${projects[@]}"; do
    project_group="sagemaker-${USER_TEAM}-${project}"
    if [[ "$CURRENT_GROUPS" == *"$project_group"* ]]; then
        echo "  [-] $project (已加入)"
    else
        available_projects+=("$project")
        echo "  [${#available_projects[@]}] $project"
    fi
done
echo ""

if [[ ${#available_projects[@]} -eq 0 ]]; then
    log_warn "用户已加入所有可用项目"
    exit 0
fi

while true; do
    read -p "请选择要加入的项目 [1-${#available_projects[@]}]: " project_choice
    if [[ "$project_choice" =~ ^[0-9]+$ ]] && [ "$project_choice" -ge 1 ] && [ "$project_choice" -le "${#available_projects[@]}" ]; then
        SELECTED_PROJECT="${available_projects[$((project_choice-1))]}"
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择项目: $SELECTED_PROJECT"
echo ""

# =============================================================================
# 计算资源变更
# =============================================================================

PROJECT_SHORT=$(get_project_short "$SELECTED_PROJECT")
PROFILE_NAME="profile-${USER_TEAM}-${PROJECT_SHORT}-${USER_NAME}"
SPACE_NAME="space-${USER_TEAM}-${PROJECT_SHORT}-${USER_NAME}"
TEAM_FORMATTED=$(format_name "$USER_TEAM_FULLNAME")
PROJECT_FORMATTED=$(format_name "$SELECTED_PROJECT")
EXECUTION_ROLE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ExecutionRole"

PROJECT_GROUP="sagemaker-${USER_TEAM}-${SELECTED_PROJECT}"

# 检查 Profile 是否已存在
if profile_exists "$PROFILE_NAME"; then
    log_error "User Profile $PROFILE_NAME 已存在"
    exit 1
fi

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "将用户添加到新项目"

echo ""
echo -e "${BLUE}【已有资源 - 不变更】${NC}"
echo ""
echo "  IAM User: $IAM_USERNAME"
echo ""

echo -e "${BLUE}【新增/变更资源】${NC}"
echo ""
echo "  IAM Group 成员变更:"
echo "    - 加入项目组: $PROJECT_GROUP"
echo ""
echo "  SageMaker User Profile (新建):"
echo "    - $PROFILE_NAME"
echo "      Domain: $DOMAIN_ID"
echo "      Execution Role: $EXECUTION_ROLE"
echo ""
echo "  SageMaker Private Space (新建):"
echo "    - $SPACE_NAME"
echo "      Owner: $PROFILE_NAME"
echo "      EBS Size: ${SPACE_EBS_SIZE_GB} GB"
echo ""

print_separator
echo -e "${CYAN}Summary: 1 Group Membership, 1 Profile (新建), 1 Space (新建)${NC}"
print_separator

# =============================================================================
# 确认执行
# =============================================================================

if ! print_confirm_prompt; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 执行创建
# =============================================================================

echo ""
log_step "开始创建资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 添加到项目 Group (使用 lib/iam-core.sh)
# -----------------------------------------------------------------------------
log_info "Step 1/2: 添加到项目 Group..."

add_user_to_group "$IAM_USERNAME" "$PROJECT_GROUP"

# -----------------------------------------------------------------------------
# Step 2: 创建 User Profile 和 Private Space (使用 lib/sagemaker-factory.sh)
# -----------------------------------------------------------------------------
log_info "Step 2/2: 创建 User Profile 和 Private Space..."

SG_ID=$(get_studio_security_group)

create_user_profile_and_space \
    "$DOMAIN_ID" \
    "$USER_TEAM" \
    "$SELECTED_PROJECT" \
    "$USER_NAME" \
    "$IAM_USERNAME" \
    "$SG_ID" \
    "${SPACE_EBS_SIZE_GB}"

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 用户已添加到新项目!${NC}"
print_separator
echo ""
echo "变更的资源:"
echo "  - 新加入 Group: $PROJECT_GROUP"
echo "  - 新 User Profile: $PROFILE_NAME"
echo "  - 新 Private Space: $SPACE_NAME"
echo ""

echo "用户当前可访问的项目 Profiles:"
aws sagemaker list-user-profiles \
    --domain-id "$DOMAIN_ID" \
    --query 'UserProfiles[?contains(UserProfileName, `'"${USER_NAME}"'`)].UserProfileName' \
    --output table \
    --region "$AWS_REGION" 2>/dev/null || true
echo ""

echo -e "${YELLOW}📌 用户登录后:${NC}"
echo "  1. 在 SageMaker Studio 中可以看到新的 Profile"
echo "  2. 切换 Profile 即可访问不同项目的资源"
echo "  3. 每个项目有独立的 Private Space"
echo ""

echo "验证命令:"
echo "  aws sagemaker describe-user-profile --domain-id $DOMAIN_ID --user-profile-name $PROFILE_NAME"
echo "  aws sagemaker describe-space --domain-id $DOMAIN_ID --space-name $SPACE_NAME"
echo ""
