#!/bin/bash
# =============================================================================
# add-user.sh - 新增用户到已有项目
# =============================================================================
#
# 场景: 新员工入职，需要加入现有项目
#
# 涉及资源 (通过 lib/ 工厂函数):
#   - IAM User: sm-{team}-{user}
#   - IAM Group: 加入团队组 + 项目组
#   - User Profile: profile-{team}-{project}-{user}
#   - Private Space: space-{team}-{project}-{user}
#   - Permissions Boundary: 绑定 SageMaker-User-Boundary
#   - Console Password: 可选
#
# 使用方法: ./add-user.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化（不打印太多信息）
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
echo " 新增用户到已有项目"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. 选择团队
# -----------------------------------------------------------------------------
echo "可用团队:"

# 动态发现团队 (从 IAM Groups)
teams=($(discover_teams))

if [[ ${#teams[@]} -eq 0 ]]; then
    log_error "未找到任何团队。请先使用 team/add-team.sh 创建团队。"
    exit 1
fi

for i in "${!teams[@]}"; do
    team="${teams[$i]}"
    fullname=$(get_team_fullname "$team")
    echo "  [$((i+1))] $team ($fullname)"
done
echo ""

while true; do
    read -p "请选择团队 [1-${#teams[@]}]: " team_choice
    if [[ "$team_choice" =~ ^[0-9]+$ ]] && [ "$team_choice" -ge 1 ] && [ "$team_choice" -le "${#teams[@]}" ]; then
        SELECTED_TEAM="${teams[$((team_choice-1))]}"
        SELECTED_TEAM_FULLNAME=$(get_team_fullname "$SELECTED_TEAM")
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择团队: $SELECTED_TEAM ($SELECTED_TEAM_FULLNAME)"
echo ""

# -----------------------------------------------------------------------------
# 2. 选择项目 (使用动态发现)
# -----------------------------------------------------------------------------
echo "可用项目:"

# 使用动态发现获取项目列表
projects=($(get_project_list_dynamic "$SELECTED_TEAM"))

if [[ ${#projects[@]} -eq 0 ]]; then
    log_error "团队 $SELECTED_TEAM 没有可用项目"
    log_info "请先使用 project/add-project.sh 创建项目"
    exit 1
fi

for i in "${!projects[@]}"; do
    echo "  [$((i+1))] ${projects[$i]}"
done
echo ""

while true; do
    read -p "请选择项目 [1-${#projects[@]}]: " project_choice
    if [[ "$project_choice" =~ ^[0-9]+$ ]] && [ "$project_choice" -ge 1 ] && [ "$project_choice" -le "${#projects[@]}" ]; then
        SELECTED_PROJECT="${projects[$((project_choice-1))]}"
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择项目: $SELECTED_PROJECT"
echo ""

# -----------------------------------------------------------------------------
# 3. 输入用户名
# -----------------------------------------------------------------------------
while true; do
    read -p "请输入用户名 (小写字母开头，仅字母数字，2-20字符): " INPUT_USERNAME
    if validate_username "$INPUT_USERNAME"; then
        break
    fi
done

# 构建 IAM 用户名
IAM_USERNAME="sm-${SELECTED_TEAM}-${INPUT_USERNAME}"

# 检查用户是否已存在
if iam_user_exists "$IAM_USERNAME"; then
    log_error "IAM 用户 $IAM_USERNAME 已存在"
    log_info "如需将已有用户添加到新项目，请使用 add-user-to-project.sh"
    exit 1
fi

log_info "IAM 用户名: $IAM_USERNAME"
echo ""

# -----------------------------------------------------------------------------
# 4. 是否启用 Console 登录
# -----------------------------------------------------------------------------
read -p "是否启用 AWS Console 登录? [y/N]: " enable_console
ENABLE_CONSOLE=false
if [[ "$enable_console" =~ ^[Yy]$ ]]; then
    ENABLE_CONSOLE=true
    INITIAL_PASSWORD="${PASSWORD_PREFIX}${INPUT_USERNAME}${PASSWORD_SUFFIX}"
fi

# =============================================================================
# 计算资源变更
# =============================================================================

PROJECT_SHORT=$(get_project_short "$SELECTED_PROJECT")
PROFILE_NAME="profile-${SELECTED_TEAM}-${PROJECT_SHORT}-${INPUT_USERNAME}"
SPACE_NAME="space-${SELECTED_TEAM}-${PROJECT_SHORT}-${INPUT_USERNAME}"
TEAM_FORMATTED=$(format_name "$SELECTED_TEAM_FULLNAME")
PROJECT_FORMATTED=$(format_name "$SELECTED_PROJECT")
EXECUTION_ROLE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ExecutionRole"

TEAM_GROUP="sagemaker-${SELECTED_TEAM_FULLNAME}"
PROJECT_GROUP="sagemaker-${SELECTED_TEAM}-${SELECTED_PROJECT}"
BOUNDARY_POLICY="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-User-Boundary"

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "新增用户"

echo ""
echo -e "${BLUE}【新增资源】${NC}"
echo ""
echo "  IAM User:"
echo "    - $IAM_USERNAME"
echo "      Path: $IAM_PATH"
echo "      Permissions Boundary: SageMaker-User-Boundary"
if [[ "$ENABLE_CONSOLE" == "true" ]]; then
    echo "      Console Login: 已启用 (首次登录需修改密码)"
else
    echo "      Console Login: 禁用 (仅 API 访问)"
fi
echo ""
echo "  IAM Group 成员变更:"
echo "    - 加入团队组: $TEAM_GROUP"
echo "    - 加入项目组: $PROJECT_GROUP"
echo ""
echo "  SageMaker User Profile:"
echo "    - $PROFILE_NAME"
echo "      Domain: $DOMAIN_ID"
echo "      Execution Role: $EXECUTION_ROLE"
echo ""
echo "  SageMaker Private Space:"
echo "    - $SPACE_NAME"
echo "      Owner: $PROFILE_NAME"
echo "      EBS Size: ${SPACE_EBS_SIZE_GB} GB"
echo ""

print_separator
echo -e "${CYAN}Summary: 1 IAM User, 2 Group Memberships, 1 Profile, 1 Space${NC}"
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
# Step 1: 创建 IAM User (使用 lib/iam-core.sh)
# 包含: 创建用户 + 设置 Permissions Boundary + Console Login (可选)
# -----------------------------------------------------------------------------
log_info "Step 1/3: 创建 IAM User..."

# lib 函数返回密码（如果启用 console login）
RETURNED_PASSWORD=$(create_iam_user "$IAM_USERNAME" "$SELECTED_TEAM_FULLNAME" "$ENABLE_CONSOLE" "$SELECTED_PROJECT")
if [[ -n "$RETURNED_PASSWORD" && "$ENABLE_CONSOLE" == "true" ]]; then
    INITIAL_PASSWORD="$RETURNED_PASSWORD"
fi

# -----------------------------------------------------------------------------
# Step 2: 添加到 Groups (使用 lib/iam-core.sh)
# -----------------------------------------------------------------------------
log_info "Step 2/3: 添加到 IAM Groups..."

# 添加到团队组
add_user_to_group "$IAM_USERNAME" "$TEAM_GROUP"

# 添加到项目组
add_user_to_group "$IAM_USERNAME" "$PROJECT_GROUP"

# -----------------------------------------------------------------------------
# Step 3: 创建 User Profile 和 Private Space (使用 lib/sagemaker-factory.sh)
# -----------------------------------------------------------------------------
log_info "Step 3/3: 创建 User Profile 和 Private Space..."

SG_ID=$(get_studio_security_group)

create_user_profile_and_space \
    "$DOMAIN_ID" \
    "$SELECTED_TEAM" \
    "$SELECTED_PROJECT" \
    "$INPUT_USERNAME" \
    "$IAM_USERNAME" \
    "$SG_ID" \
    "${SPACE_EBS_SIZE_GB}"

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 用户创建完成!${NC}"
print_separator
echo ""
echo "创建的资源:"
echo "  - IAM User:      $IAM_USERNAME"
echo "  - User Profile:  $PROFILE_NAME"
echo "  - Private Space: $SPACE_NAME"
echo ""

if [[ "$ENABLE_CONSOLE" == "true" ]]; then
    echo -e "${YELLOW}📌 登录信息 (请安全传递给用户):${NC}"
    echo ""
    echo "  Console URL: https://${AWS_ACCOUNT_ID}.signin.aws.amazon.com/console"
    echo "  用户名:      $IAM_USERNAME"
    echo "  初始密码:    $INITIAL_PASSWORD"
    echo ""
    echo -e "${YELLOW}⚠️  首次登录需要:${NC}"
    echo "  1. 修改密码"
    echo "  2. 绑定 MFA 设备"
    echo "  3. 重新登录后访问 SageMaker Studio"
    echo ""
else
    echo "用户仅有 API 访问权限，可通过 CreatePresignedDomainUrl 获取 Studio 访问链接"
    echo ""
fi

echo "验证命令:"
echo "  aws iam get-user --user-name $IAM_USERNAME"
echo "  aws sagemaker describe-user-profile --domain-id $DOMAIN_ID --user-profile-name $PROFILE_NAME"
echo ""
