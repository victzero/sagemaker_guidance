#!/bin/bash
# =============================================================================
# 01-create-buckets.sh - 创建 S3 Buckets
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 创建 Bucket 函数
# -----------------------------------------------------------------------------
create_bucket() {
    local bucket_name=$1
    local team=$2
    local project=$3
    
    log_info "Creating bucket: $bucket_name"
    
    # 检查是否已存在
    if aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
        log_warn "Bucket $bucket_name already exists, skipping creation..."
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] Would create bucket: $bucket_name"
        return 0
    fi
    
    # 创建 Bucket (注意: us-east-1 不需要 LocationConstraint)
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    log_success "Bucket $bucket_name created"
    
    # 添加标签
    log_info "Adding tags to $bucket_name"
    local tag_team="${team:-shared}"
    local tag_project="${project:-shared}"
    local tag_env="${ENVIRONMENT:-production}"
    local tag_cost="${COST_CENTER:-default}"
    
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "{\"TagSet\":[
            {\"Key\":\"Team\",\"Value\":\"${tag_team}\"},
            {\"Key\":\"Project\",\"Value\":\"${tag_project}\"},
            {\"Key\":\"Environment\",\"Value\":\"${tag_env}\"},
            {\"Key\":\"CostCenter\",\"Value\":\"${tag_cost}\"},
            {\"Key\":\"ManagedBy\",\"Value\":\"sagemaker-platform\"}
        ]}" \
        --region "$AWS_REGION"
    
    # 阻止公开访问
    log_info "Blocking public access for $bucket_name"
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"
    
    # 启用版本控制
    if [[ "${ENABLE_VERSIONING}" == "true" ]]; then
        log_info "Enabling versioning for $bucket_name"
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled \
            --region "$AWS_REGION"
    fi
    
    # 配置加密
    log_info "Configuring encryption for $bucket_name"
    if [[ "${ENCRYPTION_TYPE}" == "SSE-KMS" && -n "${KMS_KEY_ID}" ]]; then
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'"${KMS_KEY_ID}"'"
                    },
                    "BucketKeyEnabled": true
                }]
            }' \
            --region "$AWS_REGION"
    else
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }' \
            --region "$AWS_REGION"
    fi
    
    log_success "Bucket $bucket_name configured"
}

# -----------------------------------------------------------------------------
# 创建目录结构
# -----------------------------------------------------------------------------
create_directory_structure() {
    local bucket_name=$1
    local is_shared=$2
    
    log_info "Creating directory structure for $bucket_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] Would create directory structure"
        return 0
    fi
    
    if [[ "$is_shared" == "true" ]]; then
        # 共享 Bucket 结构
        local dirs=(
            "scripts/preprocessing/"
            "scripts/utils/"
            "containers/dockerfiles/"
            "datasets/reference/"
            "documentation/"
        )
    else
        # 项目 Bucket 结构
        local dirs=(
            "raw/uploads/"
            "raw/external/"
            "processed/cleaned/"
            "processed/transformed/"
            "features/v1/"
            "models/training/"
            "models/artifacts/"
            "models/registry/"
            "notebooks/archived/"
            "outputs/reports/"
            "outputs/predictions/"
            "temp/"
        )
    fi
    
    for dir in "${dirs[@]}"; do
        aws s3api put-object \
            --bucket "$bucket_name" \
            --key "$dir" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    
    log_success "Directory structure created for $bucket_name"
}

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
    
    # 1. 创建项目 Buckets
    for team in $TEAMS; do
        log_info "Creating buckets for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local bucket_name=$(get_bucket_name "$team" "$project")
            create_bucket "$bucket_name" "$team" "$project"
            create_directory_structure "$bucket_name" "false"
            CREATED_BUCKETS+=("$bucket_name")
        done
    done
    
    # 2. 创建共享 Bucket
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        log_info "Creating shared assets bucket..."
        local shared_bucket=$(get_shared_bucket_name)
        create_bucket "$shared_bucket" "shared" "shared"
        create_directory_structure "$shared_bucket" "true"
        CREATED_BUCKETS+=("$shared_bucket")
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
