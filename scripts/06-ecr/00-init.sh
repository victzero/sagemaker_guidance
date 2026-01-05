#!/bin/bash
# =============================================================================
# 00-init.sh - ECR 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# ECR 默认配置
# -----------------------------------------------------------------------------
# 是否启用 ECR 模块
export ENABLE_ECR="${ENABLE_ECR:-true}"

# 共享仓库名称列表（空格分隔）
export ECR_SHARED_REPOS="${ECR_SHARED_REPOS:-base-sklearn base-pytorch base-xgboost}"

# 项目仓库类型列表（空格分隔）
export ECR_PROJECT_REPOS="${ECR_PROJECT_REPOS:-preprocessing training inference}"

# 是否创建项目级仓库
export ECR_CREATE_PROJECT_REPOS="${ECR_CREATE_PROJECT_REPOS:-false}"

# 镜像保留数量（Lifecycle Policy）
export ECR_IMAGE_RETENTION="${ECR_IMAGE_RETENTION:-10}"

# 输出目录
export OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# -----------------------------------------------------------------------------
# ECR 特有验证
# -----------------------------------------------------------------------------
validate_ecr_env() {
    log_info "Validating ECR environment variables..."
    
    if [[ "$ENABLE_ECR" != "true" ]]; then
        log_warn "ECR module is disabled (ENABLE_ECR=$ENABLE_ECR)"
        log_info "Set ENABLE_ECR=true in .env.shared to enable"
        return 0
    fi
    
    # 验证基本配置
    if [[ -z "$ECR_SHARED_REPOS" && -z "$ECR_PROJECT_REPOS" ]]; then
        log_error "No ECR repositories configured"
        log_info "Please set ECR_SHARED_REPOS or ECR_PROJECT_REPOS in .env.shared"
        exit 1
    fi
    
    log_success "ECR environment variables validated"
}

# -----------------------------------------------------------------------------
# ECR 工具函数
# -----------------------------------------------------------------------------

# 获取共享仓库名称
get_shared_repo_name() {
    local repo_type=$1
    echo "${COMPANY}-sagemaker-shared/${repo_type}"
}

# 获取项目仓库名称
get_project_repo_name() {
    local team=$1
    local project=$2
    local repo_type=$3
    echo "${COMPANY}-sm-${team}-${project}/${repo_type}"
}

# 获取 ECR Registry URL
get_ecr_registry() {
    echo "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
}

# -----------------------------------------------------------------------------
# ECR 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_ecr_summary() {
    echo "  ECR Enabled:          $ENABLE_ECR"
    echo "  Shared Repos:         $ECR_SHARED_REPOS"
    echo "  Project Repos:        $ECR_PROJECT_REPOS"
    echo "  Create Project Repos: $ECR_CREATE_PROJECT_REPOS"
    echo "  Image Retention:      $ECR_IMAGE_RETENTION"
    echo "  Registry:             $(get_ecr_registry)"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker ECR Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_ecr_env
    check_aws_cli
    ensure_output_dir
    
    # 设置默认 TAG_PREFIX
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    
    print_config_summary "ECR" print_ecr_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

