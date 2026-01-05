#!/bin/bash
# =============================================================================
# setup-all.sh - ECR 一键设置
# =============================================================================
# 用法: ./setup-all.sh [--skip-lifecycle]
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

# 参数解析
SKIP_LIFECYCLE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-lifecycle)
            SKIP_LIFECYCLE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-lifecycle]"
            echo ""
            echo "Options:"
            echo "  --skip-lifecycle  Skip lifecycle policy configuration"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗"
echo -e "║                       SageMaker ECR Setup (Phase 2B)                       ║"
echo -e "╠════════════════════════════════════════════════════════════════════════════╣"
echo -e "║  This script will create ECR repositories for SageMaker                    ║"
echo -e "╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
check_aws_cli

# ECR 默认配置
export ENABLE_ECR="${ENABLE_ECR:-true}"
export ECR_SHARED_REPOS="${ECR_SHARED_REPOS:-base-sklearn base-pytorch base-xgboost}"
export ECR_PROJECT_REPOS="${ECR_PROJECT_REPOS:-preprocessing training inference}"
export ECR_CREATE_PROJECT_REPOS="${ECR_CREATE_PROJECT_REPOS:-false}"
export ECR_IMAGE_RETENTION="${ECR_IMAGE_RETENTION:-10}"

# 检查是否启用
if [[ "$ENABLE_ECR" != "true" ]]; then
    echo -e "${YELLOW}ECR module is disabled. Set ENABLE_ECR=true to enable.${NC}"
    exit 0
fi

# 工具函数
get_shared_repo_name() {
    local repo_type=$1
    echo "${COMPANY}-sagemaker-shared/${repo_type}"
}

get_project_repo_name() {
    local team=$1
    local project=$2
    local repo_type=$3
    echo "${COMPANY}-sm-${team}-${project}/${repo_type}"
}

get_ecr_registry() {
    echo "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

# =============================================================================
# 资源预览
# =============================================================================
echo -e "${YELLOW}This script will create the following AWS ECR resources:${NC}"
echo ""
echo "  Company:          $COMPANY"
echo "  Region:           $AWS_REGION"
echo "  Registry:         $(get_ecr_registry)"
echo "  Image Retention:  $ECR_IMAGE_RETENTION images"
echo ""

# ========== Shared Repositories ==========
repo_count=0
echo -e "${BLUE}【Shared Repositories】${NC}"
for repo_type in $ECR_SHARED_REPOS; do
    repo_name=$(get_shared_repo_name "$repo_type")
    echo "    - $repo_name"
    ((repo_count++)) || true
done
echo "  Total: $repo_count shared repositories"
echo ""

# ========== Project Repositories ==========
project_repo_count=0
if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" ]]; then
    echo -e "${BLUE}【Project Repositories】${NC}"
    for team in $TEAMS; do
        projects=$(get_projects_for_team "$team")
        if [[ -n "$projects" ]]; then
            echo "  Team [$team]:"
            for project in $projects; do
                for repo_type in $ECR_PROJECT_REPOS; do
                    repo_name=$(get_project_repo_name "$team" "$project" "$repo_type")
                    echo "    - $repo_name"
                    ((project_repo_count++)) || true
                done
            done
        fi
    done
    echo "  Total: $project_repo_count project repositories"
    echo ""
else
    echo -e "${BLUE}【Project Repositories】${NC}"
    echo "  Not enabled (set ECR_CREATE_PROJECT_REPOS=true to enable)"
    echo ""
fi

# ========== Summary ==========
total_repos=$((repo_count + project_repo_count))
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $total_repos repositories ($repo_count shared, $project_repo_count project)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, \`${COMPANY}-\`)].repositoryName'"
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
run_step 1 "01-create-repositories.sh" "Create ECR Repositories"

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
echo -e "║                      ✅ ECR Setup Completed!                               ║"
echo -e "╠════════════════════════════════════════════════════════════════════════════╣"
echo -e "║                                                                            ║"
echo -e "║  Duration: ${DURATION} seconds                                                       ║"
echo -e "║                                                                            ║"
echo -e "║  Output files:                                                             ║"
echo -e "║    - 06-ecr/output/repositories.env                                        ║"
echo -e "║                                                                            ║"
echo -e "║  Next Steps:                                                               ║"
echo -e "║    1. Build and push custom images (if needed)                             ║"
echo -e "║    2. Continue to 07-model-registry                                        ║"
echo -e "║                                                                            ║"
echo -e "╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
