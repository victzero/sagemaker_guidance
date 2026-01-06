#!/bin/bash
# =============================================================================
# 01-create-buckets.sh - 创建 S3 Buckets
# =============================================================================
# 使用方法: ./01-create-buckets.sh
#
# 注意: create_s3_bucket(), create_directory_structure(), create_project_bucket(),
#       create_shared_bucket() 已移至 lib/s3-factory.sh 统一维护
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 加载工厂函数库 (复用 lib/ 中的 S3 创建函数)
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating S3 Buckets"
    echo "=============================================="
    echo ""
    
    declare -a CREATED_BUCKETS
    
    # 显示配置
    echo "Configuration:"
    echo "  Versioning: ${ENABLE_VERSIONING:-true}"
    echo "  Encryption: ${ENCRYPTION_TYPE:-SSE-AES}"
    if [[ "${ENCRYPTION_TYPE}" == "SSE-KMS" && -n "${KMS_KEY_ID}" ]]; then
        echo "  KMS Key: ${KMS_KEY_ID}"
    fi
    echo ""
    
    # 1. 创建项目 Buckets
    log_step "Creating project buckets..."
    for team in $TEAMS; do
        log_info "Creating buckets for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local bucket_name=$(get_bucket_name "$team" "$project")
            
            # 使用 lib 函数创建 bucket
            create_project_bucket "$team" "$project"
            
            CREATED_BUCKETS+=("$bucket_name")
        done
    done
    echo ""
    
    # 2. 创建共享 Bucket (可选)
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        log_step "Creating shared assets bucket..."
        create_shared_bucket
        local shared_bucket=$(get_shared_bucket_name)
        CREATED_BUCKETS+=("$shared_bucket")
        echo ""
    fi
    
    # 保存 Bucket 列表
    cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/buckets.env" << EOF
# S3 Buckets - Generated $(date)
BUCKETS="${CREATED_BUCKETS[*]}"
SHARED_BUCKET=$(get_shared_bucket_name)
EOF
    
    echo ""
    log_success "All buckets created successfully!"
    echo ""
    echo "Created Buckets:"
    for bucket in "${CREATED_BUCKETS[@]}"; do
        echo "  - $bucket"
    done
    echo ""
    echo "Bucket list saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/buckets.env"
}

main
