#!/bin/bash
# =============================================================================
# 00-init.sh - Model Registry 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# Model Registry 默认配置
# -----------------------------------------------------------------------------
# 是否启用 Model Registry 模块
export ENABLE_MODEL_REGISTRY="${ENABLE_MODEL_REGISTRY:-true}"

# Model Package Group 命名模板: {team}-{project}
# 示例: rc-fraud-detection, algo-recommendation-engine

# 输出目录
export OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# -----------------------------------------------------------------------------
# Model Registry 特有验证
# -----------------------------------------------------------------------------
validate_model_registry_env() {
    log_info "Validating Model Registry environment variables..."
    
    if [[ "$ENABLE_MODEL_REGISTRY" != "true" ]]; then
        log_warn "Model Registry module is disabled (ENABLE_MODEL_REGISTRY=$ENABLE_MODEL_REGISTRY)"
        log_info "Set ENABLE_MODEL_REGISTRY=true in .env.shared to enable"
        return 0
    fi
    
    # 验证团队配置存在
    if [[ -z "$TEAMS" ]]; then
        log_warn "TEAMS is empty - no model groups will be created"
    fi
    
    log_success "Model Registry environment variables validated"
}

# -----------------------------------------------------------------------------
# Model Registry 工具函数
# -----------------------------------------------------------------------------

# 获取 Model Package Group 名称
get_model_group_name() {
    local team=$1
    local project=$2
    echo "${team}-${project}"
}

# 获取 Model Package Group ARN
get_model_group_arn() {
    local team=$1
    local project=$2
    local group_name=$(get_model_group_name "$team" "$project")
    echo "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:model-package-group/${group_name}"
}

# -----------------------------------------------------------------------------
# Model Registry 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_model_registry_summary() {
    echo "  Model Registry Enabled: $ENABLE_MODEL_REGISTRY"
    
    if [[ -n "$TEAMS" ]]; then
        echo "  Teams:                  $TEAMS"
        
        local total_groups=0
        for team in $TEAMS; do
            local projects=$(get_projects_for_team "$team")
            for project in $projects; do
                ((total_groups++))
            done
        done
        echo "  Total Model Groups:     $total_groups"
    fi
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker Model Registry Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_team_env
    validate_model_registry_env
    check_aws_cli
    ensure_output_dir
    
    # 设置默认 TAG_PREFIX
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    
    print_config_summary "Model Registry" print_model_registry_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

