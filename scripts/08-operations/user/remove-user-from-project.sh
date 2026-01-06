#!/bin/bash
# =============================================================================
# remove-user-from-project.sh - 从项目移除用户
# =============================================================================
#
# 场景: 员工退出项目，但仍在其他项目工作
#
# 涉及资源删除（按顺序）:
#   1. Private Space (先停止 App)
#   2. User Profile
#   3. IAM Group 成员
#
# 注意: Space 中的数据会丢失，请提前备份到 S3
#
# 使用方法: ./remove-user-from-project.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# 加载工厂函数库
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 从项目移除用户"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. 输入 IAM 用户名
# -----------------------------------------------------------------------------
echo "请输入 IAM 用户名"
echo "格式: sm-{team}-{user}, 例如: sm-rc-alice"
echo ""

while true; do
    read -p "IAM 用户名: " IAM_USERNAME
    
    if [[ ! "$IAM_USERNAME" =~ ^sm-[a-z]+-[a-z0-9]+$ ]]; then
        log_error "用户名格式不正确，应为 sm-{team}-{user}"
        continue
    fi
    
    if ! iam_user_exists "$IAM_USERNAME"; then
        log_error "IAM 用户 $IAM_USERNAME 不存在"
        continue
    fi
    
    break
done

# 解析用户名
PARTS=(${IAM_USERNAME//-/ })
USER_TEAM="${PARTS[1]}"
USER_NAME="${PARTS[2]}"
USER_TEAM_FULLNAME=$(get_team_fullname "$USER_TEAM")

log_info "已识别用户: $USER_NAME (团队: $USER_TEAM)"
echo ""

# -----------------------------------------------------------------------------
# 2. 获取用户当前所属项目
# -----------------------------------------------------------------------------
echo "查询用户当前所属项目..."

CURRENT_GROUPS=$(aws iam list-groups-for-user --user-name "$IAM_USERNAME" \
    --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")

# 筛选项目组 (格式: sagemaker-{team}-{project})
PROJECT_GROUPS=()
for group in $CURRENT_GROUPS; do
    if [[ "$group" =~ ^sagemaker-${USER_TEAM}-[a-z] ]]; then
        PROJECT_GROUPS+=("$group")
    fi
done

if [[ ${#PROJECT_GROUPS[@]} -eq 0 ]]; then
    log_warn "用户未加入任何项目"
    exit 0
fi

echo "用户当前所属项目组:"
for i in "${!PROJECT_GROUPS[@]}"; do
    group="${PROJECT_GROUPS[$i]}"
    # 从组名提取项目名 (sagemaker-rc-fraud-detection -> fraud-detection)
    project="${group#sagemaker-${USER_TEAM}-}"
    echo "  [$((i+1))] $project"
done
echo ""

# -----------------------------------------------------------------------------
# 3. 选择要退出的项目
# -----------------------------------------------------------------------------
while true; do
    read -p "请选择要退出的项目 [1-${#PROJECT_GROUPS[@]}]: " project_choice
    if [[ "$project_choice" =~ ^[0-9]+$ ]] && [ "$project_choice" -ge 1 ] && [ "$project_choice" -le "${#PROJECT_GROUPS[@]}" ]; then
        SELECTED_GROUP="${PROJECT_GROUPS[$((project_choice-1))]}"
        SELECTED_PROJECT="${SELECTED_GROUP#sagemaker-${USER_TEAM}-}"
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择退出项目: $SELECTED_PROJECT"
echo ""

# =============================================================================
# 计算资源变更
# =============================================================================

PROJECT_SHORT=$(get_project_short "$SELECTED_PROJECT")
PROFILE_NAME="profile-${USER_TEAM}-${PROJECT_SHORT}-${USER_NAME}"
SPACE_NAME="space-${USER_TEAM}-${PROJECT_SHORT}-${USER_NAME}"
PROJECT_GROUP="sagemaker-${USER_TEAM}-${SELECTED_PROJECT}"

# 检查 Profile 和 Space 是否存在
PROFILE_EXISTS=false
SPACE_EXISTS=false

if profile_exists "$PROFILE_NAME"; then
    PROFILE_EXISTS=true
fi

if space_exists "$SPACE_NAME"; then
    SPACE_EXISTS=true
fi

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "从项目移除用户"

echo ""
echo -e "${YELLOW}⚠️  警告: Space 中的数据将被删除！${NC}"
echo -e "${YELLOW}   请确保重要数据已保存到 S3${NC}"
echo ""

echo -e "${BLUE}【将删除的资源】${NC}"
echo ""

if [[ "$SPACE_EXISTS" == "true" ]]; then
    echo "  SageMaker Private Space:"
    echo "    - $SPACE_NAME (将删除)"
else
    echo "  SageMaker Private Space:"
    echo "    - $SPACE_NAME (不存在，跳过)"
fi
echo ""

if [[ "$PROFILE_EXISTS" == "true" ]]; then
    echo "  SageMaker User Profile:"
    echo "    - $PROFILE_NAME (将删除)"
else
    echo "  SageMaker User Profile:"
    echo "    - $PROFILE_NAME (不存在，跳过)"
fi
echo ""

echo "  IAM Group 成员变更:"
echo "    - 从项目组移除: $PROJECT_GROUP"
echo ""

print_separator
echo -e "${CYAN}Summary: 删除 1 Space, 1 Profile, 移除 1 Group 成员${NC}"
print_separator

# =============================================================================
# 确认执行
# =============================================================================

echo ""
echo -e "${RED}此操作不可逆！Space 数据将永久丢失！${NC}"
echo ""

if ! print_confirm_prompt; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 执行删除 (使用 lib/ 工厂函数)
# =============================================================================

echo ""
log_step "开始删除资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 删除 Private Space
# -----------------------------------------------------------------------------
if [[ "$SPACE_EXISTS" == "true" ]]; then
    log_info "Step 1/3: 删除 Private Space..."
    delete_private_space "$DOMAIN_ID" "$SPACE_NAME"
else
    log_info "Step 1/3: 跳过 (Space 不存在)"
fi

# -----------------------------------------------------------------------------
# Step 2: 删除 User Profile
# -----------------------------------------------------------------------------
if [[ "$PROFILE_EXISTS" == "true" ]]; then
    log_info "Step 2/3: 删除 User Profile..."
    delete_sagemaker_user_profile "$DOMAIN_ID" "$PROFILE_NAME"
else
    log_info "Step 2/3: 跳过 (Profile 不存在)"
fi

# -----------------------------------------------------------------------------
# Step 3: 从项目组移除 (使用 lib/iam-core.sh)
# -----------------------------------------------------------------------------
log_info "Step 3/3: 从项目组移除..."

remove_user_from_group "$IAM_USERNAME" "$PROJECT_GROUP"

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 用户已从项目移除!${NC}"
print_separator
echo ""
echo "删除的资源:"
if [[ "$SPACE_EXISTS" == "true" ]]; then
    echo "  - Private Space: $SPACE_NAME"
fi
if [[ "$PROFILE_EXISTS" == "true" ]]; then
    echo "  - User Profile: $PROFILE_NAME"
fi
echo "  - Group 成员: $PROJECT_GROUP"
echo ""

# 显示用户剩余的项目
echo "用户 $IAM_USERNAME 剩余的项目组:"
aws iam list-groups-for-user --user-name "$IAM_USERNAME" \
    --query "Groups[?starts_with(GroupName, 'sagemaker-${USER_TEAM}-')].GroupName" \
    --output table 2>/dev/null || echo "  (无)"
echo ""

