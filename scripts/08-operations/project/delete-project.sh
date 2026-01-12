#!/bin/bash
# =============================================================================
# delete-project.sh - 删除项目
# =============================================================================
#
# 场景: 项目结束或合并，需要清理资源
#
# 涉及资源删除（按顺序）:
#   1. 所有 Private Spaces
#   2. 所有 User Profiles
#   3. IAM Group
#   4. IAM Roles (4个)
#   5. IAM Policies (项目级)
#   6. S3 Bucket (可选，默认保留)
#
# 安全机制: 需要两次确认
#
# 使用方法: ./delete-project.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# 加载工厂函数库
POLICY_TEMPLATES_DIR="${SCRIPTS_ROOT}/01-iam/policies"
source "${SCRIPTS_ROOT}/lib/iam-core.sh"
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"
source "${SCRIPTS_ROOT}/lib/discovery.sh"

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 删除项目"
echo "=============================================="
echo ""
echo -e "${RED}⚠️  警告: 此操作将删除项目的所有相关资源!${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. 选择团队
# -----------------------------------------------------------------------------
echo "可用团队:"

# 动态发现团队 (从 IAM Groups)
teams=($(discover_teams))

if [[ ${#teams[@]} -eq 0 ]]; then
    log_error "未找到任何团队。"
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
# 2. 获取团队的项目列表
# -----------------------------------------------------------------------------
echo "查询团队项目..."

# 从 IAM Groups 获取项目列表
ALL_RAW_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
    --query 'Groups[].GroupName' \
    --output text 2>/dev/null || echo "")

# 在 bash 中过滤
ALL_GROUPS=""
for g in $ALL_RAW_GROUPS; do
    if [[ "$g" == sagemaker-${SELECTED_TEAM}-* ]]; then
        if [[ -n "$ALL_GROUPS" ]]; then
            ALL_GROUPS="$ALL_GROUPS $g"
        else
            ALL_GROUPS="$g"
        fi
    fi
done

PROJECT_GROUPS=()
for group in $ALL_GROUPS; do
    # 提取项目名
    project="${group#sagemaker-${SELECTED_TEAM}-}"
    if [[ -n "$project" ]]; then
        PROJECT_GROUPS+=("$project")
    fi
done

if [[ ${#PROJECT_GROUPS[@]} -eq 0 ]]; then
    log_warn "团队 $SELECTED_TEAM 没有项目"
    exit 0
fi

echo "可删除的项目:"
for i in "${!PROJECT_GROUPS[@]}"; do
    echo "  [$((i+1))] ${PROJECT_GROUPS[$i]}"
done
echo ""

# -----------------------------------------------------------------------------
# 3. 选择要删除的项目
# -----------------------------------------------------------------------------
while true; do
    read -p "请选择要删除的项目 [1-${#PROJECT_GROUPS[@]}]: " project_choice
    if [[ "$project_choice" =~ ^[0-9]+$ ]] && [ "$project_choice" -ge 1 ] && [ "$project_choice" -le "${#PROJECT_GROUPS[@]}" ]; then
        SELECTED_PROJECT="${PROJECT_GROUPS[$((project_choice-1))]}"
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择项目: $SELECTED_PROJECT"
echo ""

# -----------------------------------------------------------------------------
# 4. 是否删除 S3 Bucket
# -----------------------------------------------------------------------------
read -p "是否同时删除 S3 Bucket? (数据将永久丢失) [y/N]: " delete_bucket
DELETE_BUCKET=false
if [[ "$delete_bucket" =~ ^[Yy]$ ]]; then
    DELETE_BUCKET=true
fi

# =============================================================================
# 查询项目相关资源
# =============================================================================

log_info "正在查询项目相关资源..."

TEAM_FORMATTED=$(format_name "$SELECTED_TEAM_FULLNAME")
PROJECT_FORMATTED=$(format_name "$SELECTED_PROJECT")
PROJECT_SHORT=$(get_project_short "$SELECTED_PROJECT")

GROUP_NAME="sagemaker-${SELECTED_TEAM}-${SELECTED_PROJECT}"
BUCKET_NAME="${COMPANY}-sm-${SELECTED_TEAM}-${SELECTED_PROJECT}"

# 查询项目成员
PROJECT_MEMBERS=$(aws iam get-group --group-name "$GROUP_NAME" \
    --query 'Users[].UserName' --output text 2>/dev/null || echo "")

# 查询 User Profiles
ALL_PROFILES=$(aws sagemaker list-user-profiles \
    --domain-id "$DOMAIN_ID" \
    --query 'UserProfiles[].UserProfileName' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

PROJECT_PROFILES=""
for p in $ALL_PROFILES; do
    if [[ "$p" == *"-${PROJECT_SHORT}-"* ]]; then
        PROJECT_PROFILES="$PROJECT_PROFILES $p"
    fi
done
PROJECT_PROFILES=$(echo "$PROJECT_PROFILES" | xargs)

# 查询 Private Spaces
ALL_SPACES=$(aws sagemaker list-spaces \
    --domain-id "$DOMAIN_ID" \
    --query 'Spaces[].SpaceName' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

PROJECT_SPACES=""
for s in $ALL_SPACES; do
    if [[ "$s" == *"-${PROJECT_SHORT}-"* ]]; then
        PROJECT_SPACES="$PROJECT_SPACES $s"
    fi
done
PROJECT_SPACES=$(echo "$PROJECT_SPACES" | xargs)

# 资源名称前缀 (用于显示)
POLICY_PREFIX="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}"
ROLE_PREFIX="${POLICY_PREFIX}"

# 检查 S3 Bucket
BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    BUCKET_EXISTS=true
fi

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "删除项目"

echo ""
echo -e "${RED}⚠️  以下所有资源将被永久删除!${NC}"
echo ""

SPACE_COUNT=$(echo "$PROJECT_SPACES" | wc -w | tr -d ' ')
PROFILE_COUNT=$(echo "$PROJECT_PROFILES" | wc -w | tr -d ' ')
MEMBER_COUNT=$(echo "$PROJECT_MEMBERS" | wc -w | tr -d ' ')

echo -e "${BLUE}【将删除的 SageMaker 资源】${NC}"
echo ""
echo "  Private Spaces ($SPACE_COUNT 个):"
if [[ -n "$PROJECT_SPACES" ]]; then
    for space in $PROJECT_SPACES; do
        echo "    - $space"
    done
else
    echo "    (无)"
fi
echo ""
echo "  User Profiles ($PROFILE_COUNT 个):"
if [[ -n "$PROJECT_PROFILES" ]]; then
    for profile in $PROJECT_PROFILES; do
        echo "    - $profile"
    done
else
    echo "    (无)"
fi
echo ""

echo -e "${BLUE}【将删除的 IAM 资源】${NC}"
echo ""
echo "  IAM Group:"
echo "    - $GROUP_NAME"
echo "    - 成员 ($MEMBER_COUNT 人): $PROJECT_MEMBERS"
echo ""
echo "  IAM Roles (4个):"
echo "    - ${ROLE_PREFIX}-ExecutionRole"
echo "    - ${ROLE_PREFIX}-TrainingRole"
echo "    - ${ROLE_PREFIX}-ProcessingRole"
echo "    - ${ROLE_PREFIX}-InferenceRole"
echo ""
echo "  IAM Policies (12个):"
echo "    - ${POLICY_PREFIX}-Access"
echo "    - ${POLICY_PREFIX}-S3Access"
echo "    - ${POLICY_PREFIX}-PassRole"
echo "    - ${POLICY_PREFIX}-DenyCrossProject (跨项目资源隔离)"
echo "    - ${POLICY_PREFIX}-ExecutionPolicy"
echo "    - ${POLICY_PREFIX}-ExecutionJobPolicy"
echo "    - ${POLICY_PREFIX}-TrainingPolicy"
echo "    - ${POLICY_PREFIX}-TrainingOpsPolicy"
echo "    - ${POLICY_PREFIX}-ProcessingPolicy"
echo "    - ${POLICY_PREFIX}-ProcessingOpsPolicy"
echo "    - ${POLICY_PREFIX}-InferencePolicy"
echo "    - ${POLICY_PREFIX}-InferenceOpsPolicy"
echo ""

if [[ "$DELETE_BUCKET" == "true" && "$BUCKET_EXISTS" == "true" ]]; then
    echo -e "${BLUE}【将删除的 S3 资源】${NC}"
    echo ""
    echo "  S3 Bucket:"
    echo "    - $BUCKET_NAME (包含所有数据)"
    echo ""
elif [[ "$BUCKET_EXISTS" == "true" ]]; then
    echo -e "${BLUE}【将保留的 S3 资源】${NC}"
    echo ""
    echo "  S3 Bucket (保留):"
    echo "    - $BUCKET_NAME"
    echo ""
fi

print_separator
echo -e "${CYAN}Summary: 删除 $SPACE_COUNT Spaces, $PROFILE_COUNT Profiles, 1 Group, 4 Roles, 12 Policies$([ "$DELETE_BUCKET" == "true" ] && echo ", 1 Bucket")${NC}"
print_separator

# =============================================================================
# 第一次确认
# =============================================================================

echo ""
echo -e "${RED}此操作不可逆！所有数据将永久丢失！${NC}"
echo ""
read -p "确认删除项目 '$SELECTED_PROJECT'? [y/N]: " confirm1

if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 第二次确认
# =============================================================================

echo ""
echo -e "${RED}⚠️  最后确认！请输入项目名称 '$SELECTED_PROJECT' 完成删除:${NC}"
read -p "> " confirm2

if [[ "$confirm2" != "$SELECTED_PROJECT" ]]; then
    log_info "输入不匹配，操作已取消"
    exit 0
fi

# =============================================================================
# 执行删除 (使用 lib/ 工厂函数)
# =============================================================================

echo ""
log_step "开始删除资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 删除所有 Private Spaces
# -----------------------------------------------------------------------------
log_info "Step 1/6: 删除 Private Spaces..."

for space in $PROJECT_SPACES; do
    if [[ -n "$space" ]]; then
        delete_private_space "$DOMAIN_ID" "$space"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 2: 删除所有 User Profiles
# -----------------------------------------------------------------------------
log_info "Step 2/6: 删除 User Profiles..."

for profile in $PROJECT_PROFILES; do
    if [[ -n "$profile" ]]; then
        delete_sagemaker_user_profile "$DOMAIN_ID" "$profile"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 3: 从 Group 移除所有成员并删除 Group (使用 lib/iam-core.sh)
# -----------------------------------------------------------------------------
log_info "Step 3/6: 删除 IAM Group..."

# 移除所有成员
for member in $PROJECT_MEMBERS; do
    if [[ -n "$member" ]]; then
        remove_user_from_group "$member" "$GROUP_NAME" 2>/dev/null || true
    fi
done

# 删除 Group (包含策略分离)
if iam_group_exists "$GROUP_NAME"; then
    delete_iam_group "$GROUP_NAME"
else
    log_info "Group $GROUP_NAME not found, skipping..."
fi

# -----------------------------------------------------------------------------
# Step 4: 删除 IAM Roles (使用 lib/iam-core.sh)
# -----------------------------------------------------------------------------
log_info "Step 4/6: 删除 IAM Roles..."

delete_project_roles "$SELECTED_TEAM" "$SELECTED_PROJECT"

# -----------------------------------------------------------------------------
# Step 5: 删除 IAM Policies (使用 lib/iam-core.sh)
# 注意: delete_project_iam_policies 会删除所有 12 个项目策略
# -----------------------------------------------------------------------------
log_info "Step 5/6: 删除 IAM Policies..."

delete_project_iam_policies "$SELECTED_TEAM" "$SELECTED_PROJECT"

# -----------------------------------------------------------------------------
# Step 6: 删除 S3 Bucket (可选)
# -----------------------------------------------------------------------------
if [[ "$DELETE_BUCKET" == "true" && "$BUCKET_EXISTS" == "true" ]]; then
    log_info "Step 6/6: 删除 S3 Bucket..."
    delete_bucket "$BUCKET_NAME"
else
    log_info "Step 6/6: 跳过 S3 Bucket (保留)"
fi

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 项目已删除!${NC}"
print_separator
echo ""
echo "删除的资源:"
echo "  - Private Spaces: $SPACE_COUNT"
echo "  - User Profiles: $PROFILE_COUNT"
echo "  - IAM Group: $GROUP_NAME"
echo "  - IAM Roles: 4"
echo "  - IAM Policies: 12"
if [[ "$DELETE_BUCKET" == "true" ]]; then
    echo "  - S3 Bucket: $BUCKET_NAME"
fi
echo ""
echo -e "${YELLOW}📌 后续建议:${NC}"
echo "  1. 更新 .env.shared 移除项目配置"
echo "  2. 通知相关用户项目已删除"
if [[ "$DELETE_BUCKET" != "true" && "$BUCKET_EXISTS" == "true" ]]; then
    echo "  3. S3 Bucket '$BUCKET_NAME' 已保留，如需删除请手动处理"
fi
echo ""

