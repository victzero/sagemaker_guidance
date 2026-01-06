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
    --query "Groups[?starts_with(GroupName, 'sagemaker-')].GroupName" \
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
    
    # 检查是否有关联项目
    project_count=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query "Groups[?starts_with(GroupName, 'sagemaker-') && contains(GroupName, '-${team_name}-')].GroupName | length(@)" \
        --output text 2>/dev/null || echo "0")
    
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

# 检查关联项目
PROJECT_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
    --query "Groups[?starts_with(GroupName, 'sagemaker-') && contains(GroupName, '-')].GroupName" \
    --output text 2>/dev/null || echo "")

TEAM_PROJECTS=()
for group in $PROJECT_GROUPS; do
    # 检查是否是这个团队的项目 (sagemaker-{team}-{project})
    if [[ "$group" =~ ^sagemaker-[a-z]+-${SELECTED_TEAM}- || "$group" == "sagemaker-"*"-${SELECTED_TEAM}" ]]; then
        continue
    fi
    # 提取团队部分进行匹配
    group_team=$(echo "${group#sagemaker-}" | cut -d'-' -f1)
    if [[ -n "$group_team" ]]; then
        # 检查是否与选中的团队相关
        local_name="${group#sagemaker-}"
        if [[ "$local_name" =~ ^[a-z]+-[a-z] ]]; then
            first_part="${local_name%%-*}"
            # 需要从配置中查找团队 ID 对应关系
            for team in $TEAMS; do
                team_fullname=$(get_team_fullname "$team")
                if [[ "$SELECTED_TEAM" == "$team_fullname" && "$first_part" == "$team" ]]; then
                    project="${local_name#*-}"
                    TEAM_PROJECTS+=("$project")
                fi
            done
        fi
    fi
done

# 简化：直接查找包含团队缩写的项目组
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    if [[ "$SELECTED_TEAM" == "$team_fullname" ]]; then
        # 找到团队 ID，查找其项目
        PROJECTS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
            --query "Groups[?starts_with(GroupName, 'sagemaker-${team}-')].GroupName" \
            --output text 2>/dev/null || echo "")
        
        for proj_group in $PROJECTS; do
            project="${proj_group#sagemaker-${team}-}"
            if [[ -n "$project" ]]; then
                TEAM_PROJECTS+=("$project")
            fi
        done
        break
    fi
done

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

# 检查策略是否存在
POLICY_EXISTS=false
if aws iam get-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
    POLICY_EXISTS=true
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
echo "  IAM Policy:"
if [[ "$POLICY_EXISTS" == "true" ]]; then
    echo "    - $POLICY_NAME"
else
    echo "    - $POLICY_NAME (不存在，跳过)"
fi
echo ""

print_separator
echo -e "${CYAN}Summary: 删除 1 Group, $([ "$POLICY_EXISTS" == "true" ] && echo "1" || echo "0") Policy${NC}"
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
# 执行删除
# =============================================================================

echo ""
log_step "开始删除资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 分离并删除 Group
# -----------------------------------------------------------------------------
log_info "Step 1/2: 删除 IAM Group..."

# 分离所有策略
ATTACHED_POLICIES=$(aws iam list-attached-group-policies \
    --group-name "$SELECTED_GROUP" \
    --query 'AttachedPolicies[].PolicyArn' \
    --output text 2>/dev/null || echo "")

for policy_arn in $ATTACHED_POLICIES; do
    if [[ -n "$policy_arn" ]]; then
        aws iam detach-group-policy \
            --group-name "$SELECTED_GROUP" \
            --policy-arn "$policy_arn" 2>/dev/null || true
        log_info "  已分离策略: ${policy_arn##*/}"
    fi
done

# 删除 Group
aws iam delete-group --group-name "$SELECTED_GROUP"
log_success "已删除 Group: $SELECTED_GROUP"

# -----------------------------------------------------------------------------
# Step 2: 删除团队 Policy
# -----------------------------------------------------------------------------
log_info "Step 2/2: 删除 IAM Policy..."

if [[ "$POLICY_EXISTS" == "true" ]]; then
    # 删除所有非默认版本
    VERSIONS=$(aws iam list-policy-versions \
        --policy-arn "$POLICY_ARN" \
        --query 'Versions[?!IsDefaultVersion].VersionId' \
        --output text 2>/dev/null || echo "")
    
    for version in $VERSIONS; do
        if [[ -n "$version" ]]; then
            aws iam delete-policy-version \
                --policy-arn "$POLICY_ARN" \
                --version-id "$version" 2>/dev/null || true
        fi
    done
    
    # 删除策略
    aws iam delete-policy --policy-arn "$POLICY_ARN"
    log_success "已删除 Policy: $POLICY_NAME"
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
echo ""
echo -e "${YELLOW}📌 后续建议:${NC}"
echo "  1. 更新 .env.shared 移除团队配置"
echo "  2. 通知相关人员团队已删除"
echo ""

