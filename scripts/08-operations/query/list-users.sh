#!/bin/bash
# =============================================================================
# list-users.sh - 列出所有用户
# =============================================================================
#
# 功能:
#   - 列出所有 IAM Users (sm-* 前缀)
#   - 显示用户所属 Groups
#   - 显示用户的 User Profiles
#   - 支持按团队筛选
#
# 使用方法:
#   ./list-users.sh              # 列出所有用户
#   ./list-users.sh --team rc    # 只列出 rc 团队用户
#   ./list-users.sh --detail     # 显示详细信息
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# =============================================================================
# 解析参数
# =============================================================================

FILTER_TEAM=""
SHOW_DETAIL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --team)
            FILTER_TEAM="$2"
            shift 2
            ;;
        --detail)
            SHOW_DETAIL=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# =============================================================================
# 主函数
# =============================================================================

echo ""
echo "=============================================="
echo " SageMaker 用户列表"
echo "=============================================="
echo ""

# 获取所有 IAM Users
# 注意: JMESPath 使用反引号 ` 表示字符串字面量，不是单引号 '
log_info "DEBUG: IAM_PATH=${IAM_PATH}"
if [[ -n "$FILTER_TEAM" ]]; then
    log_info "筛选团队: $FILTER_TEAM"
    USERS=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query "Users[?contains(UserName, \`sm-${FILTER_TEAM}-\`)].UserName" \
        --output text 2>/dev/null || echo "")
else
    log_info "DEBUG: Running query..."
    USERS=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'Users[?starts_with(UserName, `sm-`)].UserName' \
        --output text 2>/dev/null || echo "")
    log_info "DEBUG: Query completed, USERS=[$USERS]"
fi

if [[ -z "$USERS" ]]; then
    log_warn "未找到用户"
    exit 0
fi

log_info "DEBUG: Found users, continuing..."

# 统计
TOTAL_USERS=0
ADMIN_USERS=0
TEAM_USERS=0

echo ""
printf "%-25s %-15s %-30s %s\n" "IAM User" "团队" "所属项目 Groups" "Profiles"
echo "────────────────────────────────────────────────────────────────────────────────────────"

log_info "DEBUG: Starting for loop with USERS=[$USERS]"
for user in $USERS; do
    log_info "DEBUG: Processing user: $user"
    ((TOTAL_USERS++)) || true
    log_info "DEBUG: Step 1 - TOTAL_USERS=$TOTAL_USERS"
    
    # 解析用户类型
    if [[ "$user" =~ ^sm-admin- ]]; then
        TEAM="admin"
        ((ADMIN_USERS++)) || true
        log_info "DEBUG: Step 2a - Admin user, TEAM=$TEAM"
    else
        # sm-rc-alice -> rc
        PARTS=(${user//-/ })
        TEAM="${PARTS[1]}"
        ((TEAM_USERS++)) || true
        log_info "DEBUG: Step 2b - Team user, TEAM=$TEAM"
    fi
    
    # 获取用户所属的项目 Groups
    log_info "DEBUG: Step 3 - Getting groups for $user with TEAM=$TEAM"
    # 获取所有 groups，然后在 bash 中过滤（避免 JMESPath 变量问题）
    ALL_USER_GROUPS=$(aws iam list-groups-for-user --user-name "$user" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
    log_info "DEBUG: Step 3a - ALL_USER_GROUPS=[$ALL_USER_GROUPS]"
    
    # 在 bash 中过滤匹配 sagemaker-${TEAM}- 前缀的 groups
    log_info "DEBUG: Step 3b - Starting filter loop"
    GROUPS=""
    for g in $ALL_USER_GROUPS; do
        log_info "DEBUG: Step 3c - Checking group: $g against pattern sagemaker-${TEAM}-*"
        if [[ "$g" == sagemaker-${TEAM}-* ]]; then
            GROUPS="$GROUPS $g"
            log_info "DEBUG: Step 3d - Matched! GROUPS now: [$GROUPS]"
        fi
    done
    log_info "DEBUG: Step 3e - Loop done, GROUPS before trim: [$GROUPS]"
    # trim whitespace safely (avoid xargs issues with empty input)
    GROUPS="${GROUPS## }"
    GROUPS="${GROUPS%% }"
    log_info "DEBUG: Step 3f - Filtered GROUPS=[$GROUPS]"
    
    # 简化 Group 显示
    GROUP_DISPLAY=""
    for group in $GROUPS; do
        # sagemaker-rc-fraud-detection -> fraud-detection
        project="${group#sagemaker-${TEAM}-}"
        if [[ -n "$GROUP_DISPLAY" ]]; then
            GROUP_DISPLAY+=", $project"
        else
            GROUP_DISPLAY="$project"
        fi
    done
    
    if [[ -z "$GROUP_DISPLAY" ]]; then
        GROUP_DISPLAY="-"
    fi
    
    # 获取 Profile 数量
    # 注意: 使用 ends_with 避免误匹配 (如 alice 匹配到 alicesmith)
    # Profile 格式: profile-{team}-{project_short}-{username}
    log_info "DEBUG: Step 4 - GROUP_DISPLAY=$GROUP_DISPLAY"
    PROFILE_COUNT=0
    if [[ "$TEAM" != "admin" ]]; then
        # 从用户名提取用户标识
        USER_IDENT="${user#sm-${TEAM}-}"
        log_info "DEBUG: Step 5 - Getting profiles, DOMAIN_ID=$DOMAIN_ID, USER_IDENT=$USER_IDENT"
        PROFILE_COUNT=$(aws sagemaker list-user-profiles \
            --domain-id "$DOMAIN_ID" \
            --query "UserProfiles[?ends_with(UserProfileName, \`-${USER_IDENT}\`)].UserProfileName" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null | wc -w | tr -d ' ')
    fi
    
    log_info "DEBUG: Step 6 - About to printf: user=$user, TEAM=$TEAM, GROUP_DISPLAY=$GROUP_DISPLAY, PROFILE_COUNT=$PROFILE_COUNT"
    printf "%-25s %-15s %-30s %s\n" "$user" "$TEAM" "$GROUP_DISPLAY" "${PROFILE_COUNT} profiles"
    log_info "DEBUG: Step 7 - printf done"
    
    # 详细信息
    if [[ "$SHOW_DETAIL" == "true" && "$TEAM" != "admin" ]]; then
        USER_IDENT="${user#sm-${TEAM}-}"
        PROFILES=$(aws sagemaker list-user-profiles \
            --domain-id "$DOMAIN_ID" \
            --query "UserProfiles[?ends_with(UserProfileName, \`-${USER_IDENT}\`)].UserProfileName" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$PROFILES" ]]; then
            for profile in $PROFILES; do
                echo "    └─ $profile"
            done
        fi
    fi
done

echo ""
echo "────────────────────────────────────────────────────────────────────────────────────────"
echo ""
echo "统计:"
echo "  总用户数: $TOTAL_USERS"
echo "  管理员:   $ADMIN_USERS"
echo "  团队用户: $TEAM_USERS"
echo ""

if [[ "$SHOW_DETAIL" != "true" ]]; then
    echo "提示: 使用 --detail 查看详细 Profile 信息"
    echo ""
fi

