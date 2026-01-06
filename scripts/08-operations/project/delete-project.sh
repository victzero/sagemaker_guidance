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
# 2. 获取团队的项目列表
# -----------------------------------------------------------------------------
echo "查询团队项目..."

# 从 IAM Groups 获取项目列表
ALL_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
    --query "Groups[?starts_with(GroupName, 'sagemaker-${SELECTED_TEAM}-')].GroupName" \
    --output text 2>/dev/null || echo "")

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
PROJECT_PROFILES=$(aws sagemaker list-user-profiles \
    --domain-id "$DOMAIN_ID" \
    --query "UserProfiles[?contains(UserProfileName, '-${PROJECT_SHORT}-')].UserProfileName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# 查询 Private Spaces
PROJECT_SPACES=$(aws sagemaker list-spaces \
    --domain-id "$DOMAIN_ID" \
    --query "Spaces[?contains(SpaceName, '-${PROJECT_SHORT}-')].SpaceName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# 角色名称
ROLE_EXECUTION="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ExecutionRole"
ROLE_TRAINING="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-TrainingRole"
ROLE_PROCESSING="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ProcessingRole"
ROLE_INFERENCE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-InferenceRole"

# 策略名称
POLICY_ACCESS="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-Access"
POLICY_S3="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-S3Access"
POLICY_PASSROLE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-PassRole"

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
echo "    - $ROLE_EXECUTION"
echo "    - $ROLE_TRAINING"
echo "    - $ROLE_PROCESSING"
echo "    - $ROLE_INFERENCE"
echo ""
echo "  IAM Policies (3个):"
echo "    - $POLICY_ACCESS"
echo "    - $POLICY_S3"
echo "    - $POLICY_PASSROLE"
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
echo -e "${CYAN}Summary: 删除 $SPACE_COUNT Spaces, $PROFILE_COUNT Profiles, 1 Group, 4 Roles, 3 Policies$([ "$DELETE_BUCKET" == "true" ] && echo ", 1 Bucket")${NC}"
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
# 执行删除
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
        log_info "  删除 Space: $space"
        
        # 停止运行中的 App
        APPS=$(aws sagemaker list-apps \
            --domain-id "$DOMAIN_ID" \
            --space-name-equals "$space" \
            --query 'Apps[?Status==`InService` || Status==`Pending`].[AppName,AppType]' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$APPS" ]]; then
            while IFS=$'\t' read -r app_name app_type; do
                if [[ -n "$app_name" ]]; then
                    aws sagemaker delete-app \
                        --domain-id "$DOMAIN_ID" \
                        --space-name "$space" \
                        --app-name "$app_name" \
                        --app-type "$app_type" \
                        --region "$AWS_REGION" 2>/dev/null || true
                fi
            done <<< "$APPS"
            sleep 5
        fi
        
        aws sagemaker delete-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        log_success "  已删除: $space"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 2: 删除所有 User Profiles
# -----------------------------------------------------------------------------
log_info "Step 2/6: 删除 User Profiles..."

for profile in $PROJECT_PROFILES; do
    if [[ -n "$profile" ]]; then
        log_info "  删除 Profile: $profile"
        
        # 停止运行中的 App
        APPS=$(aws sagemaker list-apps \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name-equals "$profile" \
            --query 'Apps[?Status==`InService` || Status==`Pending`].[AppName,AppType]' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$APPS" ]]; then
            while IFS=$'\t' read -r app_name app_type; do
                if [[ -n "$app_name" ]]; then
                    aws sagemaker delete-app \
                        --domain-id "$DOMAIN_ID" \
                        --user-profile-name "$profile" \
                        --app-name "$app_name" \
                        --app-type "$app_type" \
                        --region "$AWS_REGION" 2>/dev/null || true
                fi
            done <<< "$APPS"
            sleep 5
        fi
        
        aws sagemaker delete-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        log_success "  已删除: $profile"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 3: 从 Group 移除所有成员并删除 Group
# -----------------------------------------------------------------------------
log_info "Step 3/6: 删除 IAM Group..."

# 移除所有成员
for member in $PROJECT_MEMBERS; do
    if [[ -n "$member" ]]; then
        aws iam remove-user-from-group \
            --user-name "$member" \
            --group-name "$GROUP_NAME" 2>/dev/null || true
        log_info "  已移除成员: $member"
    fi
done

# 分离所有策略
ATTACHED_POLICIES=$(aws iam list-attached-group-policies \
    --group-name "$GROUP_NAME" \
    --query 'AttachedPolicies[].PolicyArn' \
    --output text 2>/dev/null || echo "")

for policy_arn in $ATTACHED_POLICIES; do
    if [[ -n "$policy_arn" ]]; then
        aws iam detach-group-policy \
            --group-name "$GROUP_NAME" \
            --policy-arn "$policy_arn" 2>/dev/null || true
    fi
done

# 删除 Group
aws iam delete-group --group-name "$GROUP_NAME" 2>/dev/null || true
log_success "已删除 Group: $GROUP_NAME"

# -----------------------------------------------------------------------------
# Step 4: 删除 IAM Roles
# -----------------------------------------------------------------------------
log_info "Step 4/6: 删除 IAM Roles..."

for role_name in "$ROLE_EXECUTION" "$ROLE_TRAINING" "$ROLE_PROCESSING" "$ROLE_INFERENCE"; do
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        # 分离所有托管策略
        ROLE_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ROLE_POLICIES; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        done
        
        # 删除内联策略
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            if [[ -n "$policy_name" ]]; then
                aws iam delete-role-policy \
                    --role-name "$role_name" \
                    --policy-name "$policy_name" 2>/dev/null || true
            fi
        done
        
        # 删除角色
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        log_success "  已删除: $role_name"
    else
        log_warn "  跳过 (不存在): $role_name"
    fi
done

# -----------------------------------------------------------------------------
# Step 5: 删除 IAM Policies
# -----------------------------------------------------------------------------
log_info "Step 5/6: 删除 IAM Policies..."

POLICY_ARN_PREFIX="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"

for policy_name in "$POLICY_ACCESS" "$POLICY_S3" "$POLICY_PASSROLE"; do
    policy_arn="${POLICY_ARN_PREFIX}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        # 删除所有非默认版本
        VERSIONS=$(aws iam list-policy-versions \
            --policy-arn "$policy_arn" \
            --query 'Versions[?!IsDefaultVersion].VersionId' \
            --output text 2>/dev/null || echo "")
        
        for version in $VERSIONS; do
            if [[ -n "$version" ]]; then
                aws iam delete-policy-version \
                    --policy-arn "$policy_arn" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # 删除策略
        aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
        log_success "  已删除: $policy_name"
    else
        log_warn "  跳过 (不存在): $policy_name"
    fi
done

# -----------------------------------------------------------------------------
# Step 6: 删除 S3 Bucket (可选)
# -----------------------------------------------------------------------------
if [[ "$DELETE_BUCKET" == "true" && "$BUCKET_EXISTS" == "true" ]]; then
    log_info "Step 6/6: 删除 S3 Bucket..."
    
    # 清空 bucket
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
    
    # 删除 bucket
    aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null || true
    log_success "已删除 Bucket: $BUCKET_NAME"
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
echo "  - IAM Policies: 3"
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

