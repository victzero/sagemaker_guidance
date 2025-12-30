#!/bin/bash
# =============================================================================
# 00-init.sh - S3 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# S3 特有配置（设置默认值）
# -----------------------------------------------------------------------------
setup_s3_defaults() {
    # 加密类型（默认 SSE-S3）
    ENCRYPTION_TYPE="${ENCRYPTION_TYPE:-SSE-S3}"
    
    # 是否启用版本控制（默认 true）
    ENABLE_VERSIONING="${ENABLE_VERSIONING:-true}"
    
    # Lifecycle 配置
    ABORT_INCOMPLETE_DAYS="${ABORT_INCOMPLETE_DAYS:-7}"
    NONCURRENT_EXPIRATION_DAYS="${NONCURRENT_EXPIRATION_DAYS:-90}"
    DELETE_EXPIRED_MARKERS="${DELETE_EXPIRED_MARKERS:-true}"
    
    export ENCRYPTION_TYPE ENABLE_VERSIONING
    export ABORT_INCOMPLETE_DAYS NONCURRENT_EXPIRATION_DAYS DELETE_EXPIRED_MARKERS
}

# -----------------------------------------------------------------------------
# 统计预期 Bucket 数量
# -----------------------------------------------------------------------------
count_expected_buckets() {
    local bucket_count=0
    
    # 计算项目 Bucket 数量
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            ((bucket_count++)) || true
        done
    done
    
    # 加上共享 Bucket
    ((bucket_count++)) || true
    
    EXPECTED_BUCKETS=$bucket_count
    export EXPECTED_BUCKETS
}

# -----------------------------------------------------------------------------
# S3 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_s3_summary() {
    echo "  Encryption:   $ENCRYPTION_TYPE"
    echo "  Versioning:   $ENABLE_VERSIONING"
    echo ""
    echo "Expected Resources:"
    echo "  Buckets:      $EXPECTED_BUCKETS"
    echo ""
    echo "Lifecycle Settings:"
    echo "  Abort incomplete uploads: ${ABORT_INCOMPLETE_DAYS} days"
    echo "  Noncurrent expiration:    ${NONCURRENT_EXPIRATION_DAYS} days"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker S3 Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_team_env
    check_aws_cli
    setup_s3_defaults
    ensure_output_dir
    count_expected_buckets
    
    print_config_summary "S3" print_s3_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
