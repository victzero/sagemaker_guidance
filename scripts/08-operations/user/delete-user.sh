#!/bin/bash
# =============================================================================
# delete-user.sh - 完全删除用户
# =============================================================================
#
# 场景: 员工离职，需要彻底删除用户
#
# 涉及资源删除（按顺序）:
#   1. 所有 Private Spaces
#   2. 所有 User Profiles
#   3. 从所有 IAM Groups 移除
#   4. IAM User (含 Access Key, MFA, LoginProfile)
#
# 注意: 此操作不可逆，所有 Space 数据将永久丢失
#
# 使用方法: ./delete-user.sh
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

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 完全删除用户"
echo "=============================================="
echo ""
echo -e "${RED}⚠️  警告: 此操作将永久删除用户及所有相关资源!${NC}"
echo ""

# -----------------------------------------------------------------------------
# 1. 输入 IAM 用户名
# -----------------------------------------------------------------------------
echo "请输入要删除的 IAM 用户名"
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

log_info "已选择用户: $IAM_USERNAME"
echo ""

# =============================================================================
# 查询用户相关资源
# =============================================================================

log_info "正在查询用户相关资源..."

# 查询所属 Groups
USER_GROUPS=$(aws iam list-groups-for-user --user-name "$IAM_USERNAME" \
    --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")

# 查询 User Profiles
USER_PROFILES=$(aws sagemaker list-user-profiles \
    --domain-id "$DOMAIN_ID" \
    --query "UserProfiles[?contains(UserProfileName, '${USER_NAME}')].UserProfileName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# 查询 Private Spaces
USER_SPACES=$(aws sagemaker list-spaces \
    --domain-id "$DOMAIN_ID" \
    --query "Spaces[?contains(SpaceName, '${USER_NAME}')].SpaceName" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# 查询 Access Keys
ACCESS_KEYS=$(aws iam list-access-keys --user-name "$IAM_USERNAME" \
    --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")

# 查询 MFA 设备
MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$IAM_USERNAME" \
    --query 'MFADevices[].SerialNumber' --output text 2>/dev/null || echo "")

# 查询 Login Profile
HAS_LOGIN_PROFILE=false
if aws iam get-login-profile --user-name "$IAM_USERNAME" &> /dev/null; then
    HAS_LOGIN_PROFILE=true
fi

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "完全删除用户"

echo ""
echo -e "${RED}⚠️  以下所有资源将被永久删除!${NC}"
echo ""

echo -e "${BLUE}【将删除的 SageMaker 资源】${NC}"
echo ""
echo "  Private Spaces:"
if [[ -n "$USER_SPACES" ]]; then
    for space in $USER_SPACES; do
        echo "    - $space"
    done
else
    echo "    (无)"
fi
echo ""
echo "  User Profiles:"
if [[ -n "$USER_PROFILES" ]]; then
    for profile in $USER_PROFILES; do
        echo "    - $profile"
    done
else
    echo "    (无)"
fi
echo ""

echo -e "${BLUE}【将变更的 IAM 资源】${NC}"
echo ""
echo "  将从以下 Groups 移除:"
if [[ -n "$USER_GROUPS" ]]; then
    for group in $USER_GROUPS; do
        echo "    - $group"
    done
else
    echo "    (无)"
fi
echo ""

echo -e "${BLUE}【将删除的 IAM User】${NC}"
echo ""
echo "  IAM User: $IAM_USERNAME"
echo "  Access Keys:"
if [[ -n "$ACCESS_KEYS" ]]; then
    for key in $ACCESS_KEYS; do
        echo "    - $key"
    done
else
    echo "    (无)"
fi
echo "  MFA 设备:"
if [[ -n "$MFA_DEVICES" ]]; then
    for mfa in $MFA_DEVICES; do
        echo "    - $mfa"
    done
else
    echo "    (无)"
fi
echo "  Login Profile: $([ "$HAS_LOGIN_PROFILE" == "true" ] && echo "有" || echo "无")"
echo ""

# 统计
SPACE_COUNT=$(echo "$USER_SPACES" | wc -w | tr -d ' ')
PROFILE_COUNT=$(echo "$USER_PROFILES" | wc -w | tr -d ' ')
GROUP_COUNT=$(echo "$USER_GROUPS" | wc -w | tr -d ' ')

print_separator
echo -e "${CYAN}Summary: 删除 $SPACE_COUNT Spaces, $PROFILE_COUNT Profiles, 从 $GROUP_COUNT Groups 移除, 删除 1 IAM User${NC}"
print_separator

# =============================================================================
# 二次确认
# =============================================================================

echo ""
echo -e "${RED}此操作不可逆！所有数据将永久丢失！${NC}"
echo ""
read -p "请输入用户名 '$IAM_USERNAME' 确认删除: " confirm_username

if [[ "$confirm_username" != "$IAM_USERNAME" ]]; then
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
log_info "Step 1/4: 删除 Private Spaces..."

for space in $USER_SPACES; do
    if [[ -n "$space" ]]; then
        delete_private_space "$DOMAIN_ID" "$space"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 2: 删除所有 User Profiles
# -----------------------------------------------------------------------------
log_info "Step 2/4: 删除 User Profiles..."

for profile in $USER_PROFILES; do
    if [[ -n "$profile" ]]; then
        delete_sagemaker_user_profile "$DOMAIN_ID" "$profile"
        sleep 2
    fi
done

# -----------------------------------------------------------------------------
# Step 3: 从所有 Groups 移除
# -----------------------------------------------------------------------------
log_info "Step 3/4: 从 IAM Groups 移除..."

remove_user_from_groups "$IAM_USERNAME"

# -----------------------------------------------------------------------------
# Step 4: 删除 IAM User (包含所有清理步骤)
# -----------------------------------------------------------------------------
log_info "Step 4/4: 删除 IAM User..."

# 删除 MFA 设备 (需要单独处理，因为 delete_iam_user 不包含 MFA)
for mfa in $MFA_DEVICES; do
    if [[ -n "$mfa" ]]; then
        aws iam deactivate-mfa-device \
            --user-name "$IAM_USERNAME" \
            --serial-number "$mfa" 2>/dev/null || true
        aws iam delete-virtual-mfa-device \
            --serial-number "$mfa" 2>/dev/null || true
        log_success "  已删除 MFA: $mfa"
    fi
done

# 删除 IAM User (包含 Access Keys, Login Profile, Boundary)
delete_user_access_keys "$IAM_USERNAME"
delete_user_login_profile "$IAM_USERNAME"
delete_user_boundary "$IAM_USERNAME"

# 删除用户
aws iam delete-user --user-name "$IAM_USERNAME"
log_success "  已删除 IAM User: $IAM_USERNAME"

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 用户已完全删除!${NC}"
print_separator
echo ""
echo "删除的资源:"
echo "  - Private Spaces: $SPACE_COUNT"
echo "  - User Profiles: $PROFILE_COUNT"
echo "  - IAM Group 成员: $GROUP_COUNT"
echo "  - IAM User: $IAM_USERNAME"
echo ""
echo -e "${YELLOW}📌 后续建议:${NC}"
echo "  1. 更新 .env.shared 移除用户配置"
echo "  2. 检查用户创建的 S3 数据是否需要归档"
echo "  3. 审计日志已记录此操作"
echo ""

