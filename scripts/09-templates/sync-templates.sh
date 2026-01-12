#!/bin/bash
# =============================================================================
# sync-templates.sh - 同步模板到 S3 共享桶
# =============================================================================
#
# 将 sdk/ 和 notebooks/ 同步到 S3 共享资产桶，供用户下载使用
#
# 使用方法: ./sync-templates.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env

# =============================================================================
# 配置
# =============================================================================

SHARED_BUCKET="${COMPANY}-sm-shared-assets"
TEMPLATES_PREFIX="templates"

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo "=============================================="
    echo " 同步模板到 S3 共享桶"
    echo "=============================================="
    echo ""
    echo "Source: ${PROJECT_ROOT}"
    echo "Target: s3://${SHARED_BUCKET}/${TEMPLATES_PREFIX}/"
    echo ""

    # 检查共享桶是否存在
    if ! aws s3api head-bucket --bucket "$SHARED_BUCKET" 2>/dev/null; then
        log_error "共享桶不存在: $SHARED_BUCKET"
        log_info "请先执行 03-s3/setup-all.sh 创建共享桶"
        exit 1
    fi

    # 同步 SDK
    log_info "同步 SDK..."
    aws s3 sync "${PROJECT_ROOT}/sdk/" "s3://${SHARED_BUCKET}/${TEMPLATES_PREFIX}/sdk/" \
        --exclude "*.pyc" \
        --exclude "__pycache__/*" \
        --exclude ".DS_Store" \
        --delete

    # 同步 Notebooks
    log_info "同步 Notebooks..."
    aws s3 sync "${PROJECT_ROOT}/notebooks/" "s3://${SHARED_BUCKET}/${TEMPLATES_PREFIX}/notebooks/" \
        --exclude ".ipynb_checkpoints/*" \
        --exclude ".DS_Store" \
        --delete

    echo ""
    log_success "同步完成!"
    echo ""
    echo "用户可通过以下命令下载模板:"
    echo ""
    echo "  # 下载 SDK"
    echo "  aws s3 cp s3://${SHARED_BUCKET}/${TEMPLATES_PREFIX}/sdk/ ./sdk/ --recursive"
    echo ""
    echo "  # 下载 Notebooks"
    echo "  aws s3 cp s3://${SHARED_BUCKET}/${TEMPLATES_PREFIX}/notebooks/ ./notebooks/ --recursive"
    echo ""
}

main


