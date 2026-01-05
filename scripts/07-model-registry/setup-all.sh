#!/bin/bash
# =============================================================================
# setup-all.sh - Model Registry 一键设置
# =============================================================================
# 用法: ./setup-all.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗"
echo -e "║                  SageMaker Model Registry Setup (Phase 2C)                 ║"
echo -e "╠════════════════════════════════════════════════════════════════════════════╣"
echo -e "║  This script will create Model Package Groups for model version control    ║"
echo -e "╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
validate_team_env
check_aws_cli

# Model Registry 默认配置
export ENABLE_MODEL_REGISTRY="${ENABLE_MODEL_REGISTRY:-true}"

# 检查是否启用
if [[ "$ENABLE_MODEL_REGISTRY" != "true" ]]; then
    echo -e "${YELLOW}Model Registry module is disabled. Set ENABLE_MODEL_REGISTRY=true to enable.${NC}"
    exit 0
fi

# 检查团队配置
if [[ -z "$TEAMS" ]]; then
    echo -e "${YELLOW}No teams configured. Please set TEAMS in .env.shared${NC}"
    exit 1
fi

# 工具函数
get_model_group_name() {
    local team=$1
    local project=$2
    echo "${team}-${project}"
}

# =============================================================================
# 资源预览
# =============================================================================
echo -e "${YELLOW}This script will create the following AWS SageMaker Model Registry resources:${NC}"
echo ""
echo "  Company:   $COMPANY"
echo "  Region:    $AWS_REGION"
echo ""

# ========== Model Package Groups ==========
echo -e "${BLUE}【Model Package Groups】${NC}"
group_count=0
for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    projects=$(get_projects_for_team "$team")
    
    if [[ -n "$projects" ]]; then
        echo "  Team [$team - $team_fullname]:"
        for project in $projects; do
            group_name=$(get_model_group_name "$team" "$project")
            echo "    - $group_name"
            ((group_count++)) || true
        done
    fi
done
echo "  Total: $group_count model package groups"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $group_count model package groups${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws sagemaker list-model-package-groups --query 'ModelPackageGroupSummaryList[].ModelPackageGroupName'"
echo ""

# =============================================================================
# 确认执行
# =============================================================================
read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 记录开始时间
START_TIME=$(date +%s)

# 步骤执行函数
run_step() {
    local step_num=$1
    local script_name=$2
    local description=$3
    
    echo ""
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────────────────────────┐"
    echo -e "│ Step $step_num: $description"
    echo -e "└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    if [[ -f "${SCRIPT_DIR}/${script_name}" ]]; then
        bash "${SCRIPT_DIR}/${script_name}"
        echo -e "${GREEN}[OK]${NC} Step $step_num completed"
    else
        echo -e "${RED}[ERROR]${NC} Script not found: ${script_name}"
        exit 1
    fi
}

# 执行步骤
run_step 1 "01-create-model-groups.sh" "Create Model Package Groups"

# 验证
echo ""
echo -e "${BLUE}┌──────────────────────────────────────────────────────────────────────────────┐"
echo -e "│ Verification"
echo -e "└──────────────────────────────────────────────────────────────────────────────┘${NC}"
echo ""

bash "${SCRIPT_DIR}/verify.sh"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 完成
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗"
echo -e "║                    ✅ Model Registry Setup Completed!                      ║"
echo -e "╠════════════════════════════════════════════════════════════════════════════╣"
echo -e "║                                                                            ║"
echo -e "║  Duration: ${DURATION} seconds                                                       ║"
echo -e "║                                                                            ║"
echo -e "║  Output files:                                                             ║"
echo -e "║    - 07-model-registry/output/model-groups.env                             ║"
echo -e "║                                                                            ║"
echo -e "║  Next Steps:                                                               ║"
echo -e "║    1. Start using Processing/Training Jobs                                 ║"
echo -e "║    2. Register trained models to Model Registry                            ║"
echo -e "║    3. Deploy models to endpoints                                           ║"
echo -e "║                                                                            ║"
echo -e "╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
