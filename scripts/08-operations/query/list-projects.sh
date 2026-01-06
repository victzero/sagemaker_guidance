#!/bin/bash
# =============================================================================
# list-projects.sh - 列出所有项目
# =============================================================================
#
# 功能:
#   - 列出所有项目 (通过 IAM Groups 识别)
#   - 显示项目关联的 Roles
#   - 显示项目成员数
#   - 显示 S3 Bucket 状态
#   - 支持按团队筛选
#
# 使用方法:
#   ./list-projects.sh              # 列出所有项目
#   ./list-projects.sh --team rc    # 只列出 rc 团队项目
#   ./list-projects.sh --detail     # 显示详细信息
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
echo " SageMaker 项目列表"
echo "=============================================="
echo ""

# 获取所有项目级 Groups (sagemaker-{team}-{project})
# 排除团队级 Groups (sagemaker-risk-control 等)
ALL_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
    --query "Groups[?starts_with(GroupName, 'sagemaker-')].GroupName" \
    --output text 2>/dev/null || echo "")

# 筛选项目 Groups
PROJECT_GROUPS=()
for group in $ALL_GROUPS; do
    # 跳过平台级 Groups
    if [[ "$group" == "sagemaker-admins" || "$group" == "sagemaker-readonly" ]]; then
        continue
    fi
    
    # 跳过团队级 Groups (只有一个连字符 sagemaker-xxx)
    # 项目级 Groups 格式: sagemaker-{team}-{project}
    local_group="${group#sagemaker-}"
    if [[ ! "$local_group" == *-* ]]; then
        continue
    fi
    
    # 按团队筛选
    if [[ -n "$FILTER_TEAM" ]]; then
        if [[ ! "$group" == "sagemaker-${FILTER_TEAM}-"* ]]; then
            continue
        fi
    fi
    
    PROJECT_GROUPS+=("$group")
done

if [[ ${#PROJECT_GROUPS[@]} -eq 0 ]]; then
    log_warn "未找到项目"
    exit 0
fi

# 统计
TOTAL_PROJECTS=0
TOTAL_MEMBERS=0

echo ""
printf "%-35s %-10s %-10s %-15s %s\n" "项目 Group" "团队" "成员数" "S3 Bucket" "Roles"
echo "────────────────────────────────────────────────────────────────────────────────────────────────────"

for group in "${PROJECT_GROUPS[@]}"; do
    ((TOTAL_PROJECTS++)) || true
    
    # 解析团队和项目名
    # sagemaker-rc-fraud-detection -> team=rc, project=fraud-detection
    local_name="${group#sagemaker-}"
    TEAM="${local_name%%-*}"
    PROJECT="${local_name#*-}"
    
    TEAM_FULLNAME=$(get_team_fullname "$TEAM")
    TEAM_FORMATTED=$(format_name "$TEAM_FULLNAME")
    PROJECT_FORMATTED=$(format_name "$PROJECT")
    
    # 获取成员数
    MEMBER_COUNT=$(aws iam get-group --group-name "$group" \
        --query 'Users | length(@)' --output text 2>/dev/null || echo "0")
    ((TOTAL_MEMBERS += MEMBER_COUNT)) || true
    
    # 检查 S3 Bucket
    BUCKET_NAME="${COMPANY}-sm-${TEAM}-${PROJECT}"
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        BUCKET_STATUS="✅ 存在"
    else
        BUCKET_STATUS="❌ 不存在"
    fi
    
    # 检查 Roles
    ROLE_PREFIX="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}"
    ROLE_COUNT=0
    for role_suffix in "ExecutionRole" "TrainingRole" "ProcessingRole" "InferenceRole"; do
        if aws iam get-role --role-name "${ROLE_PREFIX}-${role_suffix}" &> /dev/null; then
            ((ROLE_COUNT++)) || true
        fi
    done
    
    printf "%-35s %-10s %-10s %-15s %s\n" "$group" "$TEAM" "$MEMBER_COUNT" "$BUCKET_STATUS" "${ROLE_COUNT}/4 roles"
    
    # 详细信息
    if [[ "$SHOW_DETAIL" == "true" ]]; then
        # 列出成员
        MEMBERS=$(aws iam get-group --group-name "$group" \
            --query 'Users[].UserName' --output text 2>/dev/null || echo "")
        
        if [[ -n "$MEMBERS" ]]; then
            echo "    成员:"
            for member in $MEMBERS; do
                echo "      └─ $member"
            done
        fi
        
        # 列出 Roles
        echo "    Roles:"
        for role_suffix in "ExecutionRole" "TrainingRole" "ProcessingRole" "InferenceRole"; do
            role_name="${ROLE_PREFIX}-${role_suffix}"
            if aws iam get-role --role-name "$role_name" &> /dev/null; then
                echo "      └─ ✅ $role_name"
            else
                echo "      └─ ❌ $role_name (不存在)"
            fi
        done
        echo ""
    fi
done

echo ""
echo "────────────────────────────────────────────────────────────────────────────────────────────────────"
echo ""
echo "统计:"
echo "  总项目数: $TOTAL_PROJECTS"
echo "  总成员数: $TOTAL_MEMBERS"
echo ""

if [[ "$SHOW_DETAIL" != "true" ]]; then
    echo "提示: 使用 --detail 查看详细成员和 Roles 信息"
    echo ""
fi

