#!/bin/bash
# =============================================================================
# add-user.sh - 新增用户到已有项目
# =============================================================================
#
# 场景: 新员工入职，需要加入现有项目
#
# 涉及资源:
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
teams=($TEAMS)
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
# 2. 选择项目
# -----------------------------------------------------------------------------
echo "可用项目:"
projects=($(get_project_list "$SELECTED_TEAM"))

if [[ ${#projects[@]} -eq 0 ]]; then
    log_error "团队 $SELECTED_TEAM 没有配置项目"
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
# Step 1: 创建 IAM User
# -----------------------------------------------------------------------------
log_info "Step 1/6: 创建 IAM User..."

aws iam create-user \
    --user-name "$IAM_USERNAME" \
    --path "${IAM_PATH}" \
    --tags \
        "Key=Team,Value=${SELECTED_TEAM_FULLNAME}" \
        "Key=Project,Value=${SELECTED_PROJECT}" \
        "Key=ManagedBy,Value=sagemaker-operations" \
        "Key=Owner,Value=${IAM_USERNAME}"

log_success "IAM User 创建完成: $IAM_USERNAME"

# -----------------------------------------------------------------------------
# Step 2: 设置 Permissions Boundary
# -----------------------------------------------------------------------------
log_info "Step 2/6: 设置 Permissions Boundary..."

aws iam put-user-permissions-boundary \
    --user-name "$IAM_USERNAME" \
    --permissions-boundary "$BOUNDARY_POLICY"

log_success "Permissions Boundary 已绑定"

# -----------------------------------------------------------------------------
# Step 3: 创建 Console Login (可选)
# -----------------------------------------------------------------------------
if [[ "$ENABLE_CONSOLE" == "true" ]]; then
    log_info "Step 3/6: 创建 Console Login..."
    
    aws iam create-login-profile \
        --user-name "$IAM_USERNAME" \
        --password "$INITIAL_PASSWORD" \
        --password-reset-required
    
    log_success "Console Login 已启用"
else
    log_info "Step 3/6: 跳过 Console Login (已禁用)"
fi

# -----------------------------------------------------------------------------
# Step 4: 添加到 Groups
# -----------------------------------------------------------------------------
log_info "Step 4/6: 添加到 IAM Groups..."

# 添加到团队组
aws iam add-user-to-group \
    --user-name "$IAM_USERNAME" \
    --group-name "$TEAM_GROUP"
log_success "已加入团队组: $TEAM_GROUP"

# 添加到项目组
aws iam add-user-to-group \
    --user-name "$IAM_USERNAME" \
    --group-name "$PROJECT_GROUP"
log_success "已加入项目组: $PROJECT_GROUP"

# -----------------------------------------------------------------------------
# Step 5: 创建 User Profile
# -----------------------------------------------------------------------------
log_info "Step 5/6: 创建 SageMaker User Profile..."

SG_ID=$(get_studio_sg)

USER_SETTINGS=$(cat <<EOF
{
    "ExecutionRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EXECUTION_ROLE}",
    "SecurityGroups": ["${SG_ID}"]
}
EOF
)

aws sagemaker create-user-profile \
    --domain-id "$DOMAIN_ID" \
    --user-profile-name "$PROFILE_NAME" \
    --user-settings "$USER_SETTINGS" \
    --tags \
        Key=Team,Value="$SELECTED_TEAM_FULLNAME" \
        Key=Project,Value="$SELECTED_PROJECT" \
        Key=Owner,Value="$IAM_USERNAME" \
        Key=Environment,Value=production \
        Key=ManagedBy,Value="${TAG_PREFIX}" \
    --region "$AWS_REGION"

log_success "User Profile 创建完成: $PROFILE_NAME"

# 等待 Profile 状态变为 InService
log_info "等待 User Profile 状态变为 InService..."
MAX_WAIT=120
WAIT_INTERVAL=5
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    PROFILE_STATUS=$(aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$PROFILE_NAME" \
        --query 'Status' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "Unknown")
    
    if [ "$PROFILE_STATUS" == "InService" ]; then
        log_success "User Profile 状态: InService"
        break
    fi
    
    echo -n "."
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done
echo ""

if [ "$PROFILE_STATUS" != "InService" ]; then
    log_error "User Profile 未能在 ${MAX_WAIT}s 内变为 InService (当前状态: $PROFILE_STATUS)"
    log_error "请稍后手动创建 Private Space"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6: 创建 Private Space
# -----------------------------------------------------------------------------
log_info "Step 6/6: 创建 Private Space..."

SPACE_SETTINGS=$(cat <<EOF
{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
        "EbsStorageSettings": {
            "EbsVolumeSizeInGb": ${SPACE_EBS_SIZE_GB}
        }
    }
}
EOF
)

aws sagemaker create-space \
    --domain-id "$DOMAIN_ID" \
    --space-name "$SPACE_NAME" \
    --space-sharing-settings '{"SharingType": "Private"}' \
    --ownership-settings "{\"OwnerUserProfileName\": \"${PROFILE_NAME}\"}" \
    --space-settings "$SPACE_SETTINGS" \
    --tags \
        Key=Team,Value="$SELECTED_TEAM_FULLNAME" \
        Key=Project,Value="$SELECTED_PROJECT" \
        Key=Owner,Value="$INPUT_USERNAME" \
        Key=SpaceType,Value="private" \
        Key=Environment,Value=production \
        Key=ManagedBy,Value="${TAG_PREFIX}" \
    --region "$AWS_REGION"

log_success "Private Space 创建完成: $SPACE_NAME"

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

