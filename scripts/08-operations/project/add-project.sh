#!/bin/bash
# =============================================================================
# add-project.sh - 新增项目到已有团队
# =============================================================================
#
# 场景: 团队启动新的 ML 项目
#
# 涉及资源创建 (通过 lib/ 工厂函数):
#   - IAM Group: sagemaker-{team}-{project}
#   - IAM Policies: 完整项目策略 (10+)
#   - IAM Roles: Execution, Training, Processing, Inference (4个)
#   - S3 Bucket: {company}-sm-{team}-{project} (可选)
#
# 使用方法: ./add-project.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# 加载工厂函数库
source "${SCRIPTS_ROOT}/lib/discovery.sh"
POLICY_TEMPLATES_DIR="${SCRIPTS_ROOT}/01-iam/policies"  # iam-core.sh 依赖
source "${SCRIPTS_ROOT}/lib/iam-core.sh"
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 新增项目到已有团队"
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
# 2. 输入项目名称
# -----------------------------------------------------------------------------
echo "请输入项目名称"
echo "格式: 小写字母、数字、连字符，例如: fraud-detection"
echo ""

while true; do
    read -p "项目名称: " PROJECT_NAME
    
    # 验证格式
    if [[ ! "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        log_error "项目名格式不正确，应为小写字母开头，可包含连字符"
        continue
    fi
    
    if [[ ${#PROJECT_NAME} -lt 3 || ${#PROJECT_NAME} -gt 30 ]]; then
        log_error "项目名长度应为 3-30 字符"
        continue
    fi
    
    # 检查项目是否已存在 (通过 discovery 函数)
    if project_exists "$SELECTED_TEAM" "$PROJECT_NAME"; then
        log_error "项目 $PROJECT_NAME 已存在 (Group sagemaker-${SELECTED_TEAM}-${PROJECT_NAME})"
        continue
    fi
    
    break
done

log_info "项目名称: $PROJECT_NAME"
echo ""

# -----------------------------------------------------------------------------
# 3. 是否创建 S3 Bucket
# -----------------------------------------------------------------------------
read -p "是否创建项目 S3 Bucket? [Y/n]: " create_bucket
CREATE_BUCKET=true
if [[ "$create_bucket" =~ ^[Nn]$ ]]; then
    CREATE_BUCKET=false
fi

# =============================================================================
# 计算资源
# =============================================================================

TEAM_FORMATTED=$(format_name "$SELECTED_TEAM_FULLNAME")
PROJECT_FORMATTED=$(format_name "$PROJECT_NAME")

GROUP_NAME="sagemaker-${SELECTED_TEAM}-${PROJECT_NAME}"
BUCKET_NAME="${COMPANY}-sm-${SELECTED_TEAM}-${PROJECT_NAME}"

# 策略名称 (与 iam-factory 一致)
POLICY_PREFIX="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}"

# 角色名称
ROLE_EXECUTION="${POLICY_PREFIX}-ExecutionRole"
ROLE_TRAINING="${POLICY_PREFIX}-TrainingRole"
ROLE_PROCESSING="${POLICY_PREFIX}-ProcessingRole"
ROLE_INFERENCE="${POLICY_PREFIX}-InferenceRole"

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "新增项目"

echo ""
echo -e "${BLUE}【将创建的资源】${NC}"
echo ""
echo "  团队: $SELECTED_TEAM ($SELECTED_TEAM_FULLNAME)"
echo "  项目: $PROJECT_NAME"
echo ""
echo "  IAM Group:"
echo "    - $GROUP_NAME"
echo ""
echo "  IAM Policies (完整策略集):"
echo "    - ${POLICY_PREFIX}-Access"
echo "    - ${POLICY_PREFIX}-S3Access"
echo "    - ${POLICY_PREFIX}-PassRole (含 Deny 跨项目)"
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
echo "  IAM Roles (4个):"
echo "    - $ROLE_EXECUTION (开发/Notebook + Canvas + MLflow)"
echo "    - $ROLE_TRAINING (训练作业)"
echo "    - $ROLE_PROCESSING (数据处理)"
echo "    - $ROLE_INFERENCE (推理服务)"
echo ""

if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  S3 Bucket:"
    echo "    - $BUCKET_NAME"
    echo "    - 目录结构: data/, raw/, processed/, models/, notebooks/, logs/ 等"
    echo ""
fi

print_separator
echo -e "${CYAN}Summary: 1 Group, 12 Policies, 4 Roles$([ "$CREATE_BUCKET" == "true" ] && echo ", 1 Bucket")${NC}"
print_separator

# =============================================================================
# 确认执行
# =============================================================================

if ! print_confirm_prompt; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 执行创建 (使用工厂函数)
# =============================================================================

echo ""
log_step "开始创建资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1-4: 创建 IAM 资源 (使用 iam-factory)
# -----------------------------------------------------------------------------
log_info "Step 1/2: 创建 IAM 资源 (Group, Policies, Roles)..."

create_project_iam "$SELECTED_TEAM" "$PROJECT_NAME"

# -----------------------------------------------------------------------------
# Step 5: 创建 S3 Bucket (可选，使用 s3-factory)
# -----------------------------------------------------------------------------
if [[ "$CREATE_BUCKET" == "true" ]]; then
    log_info "Step 2/2: 创建 S3 Bucket..."
    
    create_project_s3 "$SELECTED_TEAM" "$PROJECT_NAME" --with-lifecycle
else
    log_info "Step 2/2: 跳过 S3 Bucket 创建"
fi

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 项目创建完成!${NC}"
print_separator
echo ""
echo "创建的资源:"
echo "  - IAM Group: $GROUP_NAME"
echo "  - IAM Policies: 12 个完整策略 (含跨项目资源隔离)"
echo "  - IAM Roles: $ROLE_EXECUTION, $ROLE_TRAINING, $ROLE_PROCESSING, $ROLE_INFERENCE"
if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  - S3 Bucket: $BUCKET_NAME"
fi
echo ""

echo -e "${YELLOW}📌 后续步骤:${NC}"
echo ""
echo "  1. 添加用户到项目:"
echo "     cd ../user && ./add-user.sh"
echo "     或"
echo "     cd ../user && ./add-user-to-project.sh"
echo ""
echo "  2. (可选) 更新 .env.shared 添加项目配置:"
echo "     ${SELECTED_TEAM^^}_PROJECTS=\"... ${PROJECT_NAME}\""
echo "     (注: 不更新也可，系统会动态发现项目)"
echo ""

echo "验证命令:"
echo "  aws iam get-group --group-name $GROUP_NAME"
echo "  aws iam get-role --role-name $ROLE_EXECUTION"
if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  aws s3 ls s3://$BUCKET_NAME/"
fi
echo ""
