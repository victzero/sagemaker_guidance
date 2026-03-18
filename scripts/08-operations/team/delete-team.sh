#!/bin/bash
# =============================================================================
# delete-team.sh - 删除团队
# =============================================================================
#
# 场景: 部门重组或撤销
#
# 前提条件:
#   - 团队下所有项目已删除
#   - 团队下所有用户已移除
#
# 涉及资源删除:
#   - IAM Group (团队级)
#   - IAM Policy (团队级)
#
# 安全机制: 需要两次确认
#
# 使用方法: ./delete-team.sh
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
source "${SCRIPTS_ROOT}/lib/discovery.sh"

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 删除团队"
echo "=============================================="
echo ""
echo -e "${RED}⚠️  警告: 此操作将删除团队的所有 IAM 资源!${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. 获取所有团队级 Groups
# -----------------------------------------------------------------------------
echo "查询可删除的团队..."

# 获取所有 sagemaker-* Groups
ALL_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
    --query 'Groups[?starts_with(GroupName, `sagemaker-`)].GroupName' \
    --output text 2>/dev/null || echo "")

# 筛选团队级 Groups (排除 admins, readonly, 和项目级 groups)
TEAM_GROUPS=()
for group in $ALL_GROUPS; do
    # 跳过平台级 Groups
    if [[ "$group" == "sagemaker-admins" || "$group" == "sagemaker-readonly" ]]; then
        continue
    fi
    
    # 跳过项目级 Groups (包含两个或以上连字符的)
    local_name="${group#sagemaker-}"
    dash_count=$(echo "$local_name" | tr -cd '-' | wc -c)
    
    if [[ $dash_count -eq 0 || ! "$local_name" =~ - ]]; then
        # 这是团队级 Group (如 sagemaker-risk-control)
        TEAM_GROUPS+=("$group")
    fi
done

if [[ ${#TEAM_GROUPS[@]} -eq 0 ]]; then
    log_warn "未找到可删除的团队"
    exit 0
fi

echo "可删除的团队:"
for i in "${!TEAM_GROUPS[@]}"; do
    group="${TEAM_GROUPS[$i]}"
    team_name="${group#sagemaker-}"
    
    # 获取成员数
    member_count=$(aws iam get-group --group-name "$group" \
        --query 'Users | length(@)' --output text 2>/dev/null || echo "0")
    
    # 找到团队短 ID，然后获取项目数
    project_count=0
    for team_id in $(discover_teams); do
        team_fullname=$(get_team_fullname "$team_id")
        if [[ "$team_name" == "$team_fullname" ]]; then
            projects=$(discover_projects_for_team "$team_id")
            project_count=$(echo "$projects" | wc -w | tr -d ' ')
            break
        fi
    done
    
    echo "  [$((i+1))] $team_name (成员: $member_count, 项目: $project_count)"
done
echo ""

# -----------------------------------------------------------------------------
# 2. 选择要删除的团队
# -----------------------------------------------------------------------------
while true; do
    read -p "请选择要删除的团队 [1-${#TEAM_GROUPS[@]}]: " team_choice
    if [[ "$team_choice" =~ ^[0-9]+$ ]] && [ "$team_choice" -ge 1 ] && [ "$team_choice" -le "${#TEAM_GROUPS[@]}" ]; then
        SELECTED_GROUP="${TEAM_GROUPS[$((team_choice-1))]}"
        SELECTED_TEAM="${SELECTED_GROUP#sagemaker-}"
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择团队: $SELECTED_TEAM"
echo ""

# =============================================================================
# 检查前提条件
# =============================================================================

log_info "检查前提条件..."

# 检查团队成员
TEAM_MEMBERS=$(aws iam get-group --group-name "$SELECTED_GROUP" \
    --query 'Users[].UserName' --output text 2>/dev/null || echo "")
MEMBER_COUNT=$(echo "$TEAM_MEMBERS" | wc -w | tr -d ' ')

# 检查关联项目 (使用动态发现)
# 首先找到团队的短 ID
TEAM_SHORT_ID=""
for team_id in $(discover_teams); do
    team_fullname=$(get_team_fullname "$team_id")
    if [[ "$SELECTED_TEAM" == "$team_fullname" ]]; then
        TEAM_SHORT_ID="$team_id"
        break
    fi
done

TEAM_PROJECTS=()
if [[ -n "$TEAM_SHORT_ID" ]]; then
    # 使用 discovery 函数获取项目列表
    projects=$(discover_projects_for_team "$TEAM_SHORT_ID")
    for project in $projects; do
        TEAM_PROJECTS+=("$project")
    done
fi

PROJECT_COUNT=${#TEAM_PROJECTS[@]}

# 如果有成员或项目，显示警告
if [[ $MEMBER_COUNT -gt 0 || $PROJECT_COUNT -gt 0 ]]; then
    echo ""
    echo -e "${RED}⚠️  团队仍有关联资源，无法直接删除!${NC}"
    echo ""
    
    if [[ $MEMBER_COUNT -gt 0 ]]; then
        echo "  剩余成员 ($MEMBER_COUNT 人):"
        for member in $TEAM_MEMBERS; do
            echo "    - $member"
        done
        echo ""
    fi
    
    if [[ $PROJECT_COUNT -gt 0 ]]; then
        echo "  剩余项目 ($PROJECT_COUNT 个):"
        for project in "${TEAM_PROJECTS[@]}"; do
            echo "    - $project"
        done
        echo ""
    fi
    
    echo "请先执行以下操作:"
    if [[ $PROJECT_COUNT -gt 0 ]]; then
        echo "  1. 删除所有项目: cd ../project && ./delete-project.sh"
    fi
    if [[ $MEMBER_COUNT -gt 0 ]]; then
        echo "  2. 删除或移除所有用户: cd ../user && ./delete-user.sh"
    fi
    echo ""
    exit 1
fi

log_success "前提条件检查通过"
echo ""

# =============================================================================
# 查询团队相关资源
# =============================================================================

TEAM_FORMATTED=$(format_name "$SELECTED_TEAM")
POLICY_NAME="SageMaker-${TEAM_FORMATTED}-Team-Access"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${POLICY_NAME}"

DENY_CROSS_TEAM_POLICY_NAME="SageMaker-${TEAM_FORMATTED}-DenyCrossTeam"
DENY_CROSS_TEAM_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${DENY_CROSS_TEAM_POLICY_NAME}"

# 检查策略是否存在 (使用 lib/iam-core.sh)
POLICY_EXISTS=false
if iam_policy_exists "$POLICY_ARN"; then
    POLICY_EXISTS=true
fi

DENY_CROSS_TEAM_EXISTS=false
if iam_policy_exists "$DENY_CROSS_TEAM_ARN"; then
    DENY_CROSS_TEAM_EXISTS=true
fi

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "删除团队"

echo ""
echo -e "${RED}⚠️  以下资源将被永久删除!${NC}"
echo ""

echo -e "${BLUE}【将删除的 IAM 资源】${NC}"
echo ""
echo "  IAM Group:"
echo "    - $SELECTED_GROUP"
echo ""
echo "  IAM Policies:"
if [[ "$POLICY_EXISTS" == "true" ]]; then
    echo "    - $POLICY_NAME"
else
    echo "    - $POLICY_NAME (不存在，跳过)"
fi
if [[ "$DENY_CROSS_TEAM_EXISTS" == "true" ]]; then
    echo "    - $DENY_CROSS_TEAM_POLICY_NAME"
else
    echo "    - $DENY_CROSS_TEAM_POLICY_NAME (不存在，跳过)"
fi
echo ""

POLICY_COUNT=0
[[ "$POLICY_EXISTS" == "true" ]] && ((POLICY_COUNT++)) || true
[[ "$DENY_CROSS_TEAM_EXISTS" == "true" ]] && ((POLICY_COUNT++)) || true

print_separator
echo -e "${CYAN}Summary: 删除 1 Group, ${POLICY_COUNT} Policies${NC}"
print_separator

# =============================================================================
# 第一次确认
# =============================================================================

echo ""
echo -e "${RED}此操作不可逆!${NC}"
echo ""
read -p "确认删除团队 '$SELECTED_TEAM'? [y/N]: " confirm1

if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 第二次确认
# =============================================================================

echo ""
echo -e "${RED}⚠️  最后确认！请输入团队名称 '$SELECTED_TEAM' 完成删除:${NC}"
read -p "> " confirm2

if [[ "$confirm2" != "$SELECTED_TEAM" ]]; then
    log_info "输入不匹配，操作已取消"
    exit 0
fi

# =============================================================================
# 执行删除 (使用 lib/iam-core.sh 工厂函数)
# =============================================================================

echo ""
log_step "开始删除资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 删除 IAM Group (包含策略分离)
# -----------------------------------------------------------------------------
log_info "Step 1/3: 删除 IAM Group..."

delete_iam_group "$SELECTED_GROUP"

# -----------------------------------------------------------------------------
# Step 2: 删除团队 Policy
# -----------------------------------------------------------------------------
log_info "Step 2/3: 删除 IAM Policy..."

if [[ "$POLICY_EXISTS" == "true" ]]; then
    delete_iam_policy "$POLICY_ARN"
else
    log_info "跳过 (策略不存在)"
fi

# -----------------------------------------------------------------------------
# Step 3: 删除跨团队 Deny Policy
# -----------------------------------------------------------------------------
log_info "Step 3/3: 删除 DenyCrossTeam Policy..."

if [[ "$DENY_CROSS_TEAM_EXISTS" == "true" ]]; then
    delete_iam_policy "$DENY_CROSS_TEAM_ARN"
else
    log_info "跳过 (策略不存在)"
fi

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 团队已删除!${NC}"
print_separator
echo ""
echo "删除的资源:"
echo "  - IAM Group: $SELECTED_GROUP"
if [[ "$POLICY_EXISTS" == "true" ]]; then
    echo "  - IAM Policy: $POLICY_NAME"
fi
if [[ "$DENY_CROSS_TEAM_EXISTS" == "true" ]]; then
    echo "  - IAM Policy: $DENY_CROSS_TEAM_POLICY_NAME"
fi
echo ""
echo -e "${YELLOW}📌 后续建议:${NC}"
echo "  1. 更新 .env.shared 移除团队配置"
echo "  2. 通知相关人员团队已删除"
echo ""

