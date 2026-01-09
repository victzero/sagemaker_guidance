#!/bin/bash
# =============================================================================
# add-team.sh - 新增团队
# =============================================================================
#
# 场景: 组织扩展，新部门需要独立环境
#
# 涉及资源创建:
#   - IAM Group (团队级): sagemaker-{team-fullname}
#   - IAM Policy (团队级): SageMaker-{TeamFullname}-Team-Access
#
# 后续步骤:
#   - 使用 project/add-project.sh 创建项目
#   - 使用 user/add-user.sh 添加用户
#
# 使用方法: ./add-team.sh
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
# 交互式输入
# =============================================================================

echo ""
echo "=============================================="
echo " 新增团队"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. 输入团队 ID
# -----------------------------------------------------------------------------
echo "请输入团队 ID (短名称)"
echo "格式: 2-4 个小写字母，例如: ds, ml, algo"
echo ""

while true; do
    read -p "团队 ID: " TEAM_ID
    
    # 验证格式
    if [[ ! "$TEAM_ID" =~ ^[a-z]{2,4}$ ]]; then
        log_error "团队 ID 格式不正确，应为 2-4 个小写字母"
        continue
    fi
    
    # 检查是否已存在 (动态发现)
    existing_teams=$(discover_teams)
    if [[ " $existing_teams " == *" $TEAM_ID "* ]]; then
        log_error "团队 ID '$TEAM_ID' 已存在 (IAM Group 已创建)"
        continue
    fi
    
    break
done

log_info "团队 ID: $TEAM_ID"
echo ""

# -----------------------------------------------------------------------------
# 2. 输入团队全称
# -----------------------------------------------------------------------------
echo "请输入团队全称 (用于命名)"
echo "格式: 小写字母、连字符，例如: data-science, machine-learning"
echo ""

while true; do
    read -p "团队全称: " TEAM_FULLNAME
    
    # 验证格式
    if [[ ! "$TEAM_FULLNAME" =~ ^[a-z][a-z-]*[a-z]$ ]]; then
        log_error "团队全称格式不正确"
        continue
    fi
    
    if [[ ${#TEAM_FULLNAME} -lt 3 || ${#TEAM_FULLNAME} -gt 30 ]]; then
        log_error "团队全称长度应为 3-30 字符"
        continue
    fi
    
    # 检查 Group 是否已存在 (使用 lib/iam-core.sh)
    if iam_group_exists "sagemaker-${TEAM_FULLNAME}"; then
        log_error "团队 Group 'sagemaker-${TEAM_FULLNAME}' 已存在"
        continue
    fi
    
    break
done

log_info "团队全称: $TEAM_FULLNAME"
echo ""

# =============================================================================
# 计算资源
# =============================================================================

TEAM_FORMATTED=$(format_name "$TEAM_FULLNAME")
GROUP_NAME="sagemaker-${TEAM_FULLNAME}"
POLICY_NAME="SageMaker-${TEAM_FORMATTED}-Team-Access"

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "新增团队"

echo ""
echo -e "${BLUE}【将创建的资源】${NC}"
echo ""
echo "  团队 ID: $TEAM_ID"
echo "  团队全称: $TEAM_FULLNAME"
echo "  格式化名称: $TEAM_FORMATTED"
echo ""
echo "  IAM Group:"
echo "    - $GROUP_NAME"
echo ""
echo "  IAM Policy:"
echo "    - $POLICY_NAME"
echo ""

print_separator
echo -e "${CYAN}Summary: 1 Group, 1 Policy${NC}"
print_separator

# =============================================================================
# 确认执行
# =============================================================================

if ! print_confirm_prompt; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 执行创建 (使用 lib/iam-core.sh 工厂函数)
# =============================================================================

echo ""
log_step "开始创建资源..."
echo ""

# 设置临时环境变量，供 get_team_fullname() 使用
# (新团队尚未添加到 .env.shared)
export "TEAM_${TEAM_ID^^}_FULLNAME=${TEAM_FULLNAME}"

# 使用一站式函数创建团队 IAM 资源
# 包含: Group 创建 + Policy 创建 + 策略绑定
create_team_iam "$TEAM_ID"

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 团队创建完成!${NC}"
print_separator
echo ""
echo "创建的资源:"
echo "  - IAM Group: $GROUP_NAME"
echo "  - IAM Policy: $POLICY_NAME"
echo ""

echo -e "${YELLOW}📌 后续步骤:${NC}"
echo ""
echo "  1. 更新 .env.shared 添加团队配置:"
echo "     ────────────────────────────────────────"
echo "     TEAMS=\"\$TEAMS $TEAM_ID\""
echo "     TEAM_${TEAM_ID^^}_FULLNAME=$TEAM_FULLNAME"
echo "     ${TEAM_ID^^}_PROJECTS=\"\""
echo "     ────────────────────────────────────────"
echo ""
echo "  2. 创建项目:"
echo "     cd ../project && ./add-project.sh"
echo ""
echo "  3. 添加用户:"
echo "     cd ../user && ./add-user.sh"
echo ""

echo "验证命令:"
echo "  aws iam get-group --group-name $GROUP_NAME"
echo "  aws iam list-attached-group-policies --group-name $GROUP_NAME"
echo ""

