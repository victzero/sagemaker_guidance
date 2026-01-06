#!/bin/bash
# =============================================================================
# lib/s3-factory.sh - S3 资源创建工厂函数
# =============================================================================
# 封装 03-s3 模块的创建逻辑，供其他模块复用
# =============================================================================

# 防止重复加载
if [[ -n "$_LIB_S3_FACTORY_LOADED" ]]; then
    return 0
fi
_LIB_S3_FACTORY_LOADED=1

# 确保 common.sh 已加载
if [[ -z "$_SAGEMAKER_COMMON_LOADED" ]]; then
    source "${SCRIPTS_ROOT}/common.sh"
fi

# =============================================================================
# S3 Bucket 创建 (通用函数)
# =============================================================================

# 创建 S3 Bucket (通用函数，带完整配置)
# 用法: create_s3_bucket <bucket_name> <team> <project> [options]
# 选项:
#   --enable-versioning    启用版本控制 (默认: true)
#   --encryption-type TYPE SSE-AES 或 SSE-KMS (默认: SSE-AES)
#   --kms-key-id KEY_ID    KMS Key ID (仅 SSE-KMS 时使用)
#   --environment ENV      环境标签 (默认: production)
#   --cost-center CENTER   成本中心标签 (可选)
# 依赖: AWS_REGION, COMPANY
create_s3_bucket() {
    local bucket_name=$1
    local team=$2
    local project=$3
    shift 3
    
    # 默认选项
    local enable_versioning=true
    local encryption_type="SSE-AES"
    local kms_key_id=""
    local environment="${ENVIRONMENT:-production}"
    local cost_center="${COST_CENTER:-}"
    
    # 解析选项
    while [[ $# -gt 0 ]]; do
        case $1 in
            --enable-versioning)
                enable_versioning=true
                shift
                ;;
            --no-versioning)
                enable_versioning=false
                shift
                ;;
            --encryption-type)
                encryption_type="$2"
                shift 2
                ;;
            --kms-key-id)
                kms_key_id="$2"
                shift 2
                ;;
            --environment)
                environment="$2"
                shift 2
                ;;
            --cost-center)
                cost_center="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log_info "Creating S3 bucket: $bucket_name"
    
    # 检查是否已存在
    if aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
        log_warn "Bucket $bucket_name already exists, skipping creation..."
        return 0
    fi
    
    # 创建 bucket (注意: us-east-1 不需要 LocationConstraint)
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
    local tag_set="[{\"Key\":\"Team\",\"Value\":\"${team}\"},{\"Key\":\"Project\",\"Value\":\"${project}\"},{\"Key\":\"Environment\",\"Value\":\"${environment}\"},{\"Key\":\"ManagedBy\",\"Value\":\"${COMPANY}-sagemaker\"}"
    if [[ -n "$cost_center" ]]; then
        tag_set="${tag_set},{\"Key\":\"CostCenter\",\"Value\":\"${cost_center}\"}"
    fi
    tag_set="${tag_set}]"
    
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "{\"TagSet\":${tag_set}}" \
        --region "$AWS_REGION"
    
    # 阻止公开访问
    log_info "Blocking public access for $bucket_name"
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"
    
    # 启用版本控制 (可选)
    if [[ "$enable_versioning" == "true" ]]; then
        log_info "Enabling versioning for $bucket_name"
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled \
            --region "$AWS_REGION"
    fi
    
    # 配置加密
    log_info "Configuring encryption for $bucket_name"
    if [[ "$encryption_type" == "SSE-KMS" && -n "$kms_key_id" ]]; then
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'"${kms_key_id}"'"
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

# 创建目录结构
# 用法: create_directory_structure <bucket_name> [--shared]
create_directory_structure() {
    local bucket_name=$1
    local is_shared=false
    
    if [[ "$2" == "--shared" ]]; then
        is_shared=true
    fi
    
    log_info "Creating directory structure for $bucket_name"
    
    local directories
    if [[ "$is_shared" == "true" ]]; then
        # 共享 Bucket 结构
        directories=(
            "scripts/preprocessing/"
            "scripts/utils/"
            "containers/dockerfiles/"
            "datasets/reference/"
            "documentation/"
        )
    else
        # 项目 Bucket 结构
        directories=(
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
            "logs/"
            "checkpoints/"
        )
    fi
    
    for dir in "${directories[@]}"; do
        aws s3api put-object \
            --bucket "$bucket_name" \
            --key "$dir" \
            --region "$AWS_REGION" 2>/dev/null || true
    done
    
    log_success "Directory structure created for $bucket_name"
}

# 创建项目 S3 Bucket (简化接口)
# 用法: create_project_bucket <team> <project>
# 与 03-s3/01-create-buckets.sh 逻辑一致
create_project_bucket() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    local team_fullname=$(get_team_fullname "$team")
    
    # 使用通用函数创建 bucket
    create_s3_bucket "$bucket_name" "$team_fullname" "$project" \
        --enable-versioning \
        --encryption-type "${ENCRYPTION_TYPE:-SSE-AES}" \
        ${KMS_KEY_ID:+--kms-key-id "$KMS_KEY_ID"}
    
    # 创建项目目录结构
    create_directory_structure "$bucket_name"
}

# 创建共享 S3 Bucket
# 用法: create_shared_bucket
create_shared_bucket() {
    local bucket_name="${COMPANY}-sm-shared-assets"
    
    log_step "Creating shared assets bucket: $bucket_name"
    
    # 使用通用函数创建 bucket
    create_s3_bucket "$bucket_name" "shared" "shared" \
        --enable-versioning \
        --encryption-type "${ENCRYPTION_TYPE:-SSE-AES}" \
        ${KMS_KEY_ID:+--kms-key-id "$KMS_KEY_ID"}
    
    # 创建共享目录结构
    create_directory_structure "$bucket_name" --shared
    
    log_success "Shared bucket created: $bucket_name"
}

# 配置 Bucket 策略 (限制只有项目角色可访问)
# 用法: configure_bucket_policy <team> <project>
configure_bucket_policy() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local role_prefix="SageMaker-${team_capitalized}-${project_formatted}"
    
    log_info "Configuring bucket policy for: $bucket_name"
    
    # 生成 Bucket Policy
    local bucket_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowProjectRolesAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-ExecutionRole",
                    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-TrainingRole",
                    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-ProcessingRole",
                    "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-InferenceRole"
                ]
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${bucket_name}",
                "arn:aws:s3:::${bucket_name}/*"
            ]
        },
        {
            "Sid": "DenyOtherRoles",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${bucket_name}",
                "arn:aws:s3:::${bucket_name}/*"
            ],
            "Condition": {
                "StringNotLike": {
                    "aws:PrincipalArn": [
                        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_prefix}-*",
                        "arn:aws:iam::${AWS_ACCOUNT_ID}:root",
                        "arn:aws:iam::${AWS_ACCOUNT_ID}:user/*"
                    ]
                }
            }
        }
    ]
}
EOF
)
    
    aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy "$bucket_policy"
    
    log_success "Bucket policy configured for: $bucket_name"
}

# 配置 Bucket 生命周期 (可选)
# 用法: configure_bucket_lifecycle <team> <project>
configure_bucket_lifecycle() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    
    log_info "Configuring lifecycle rules for: $bucket_name"
    
    local lifecycle_config=$(cat <<EOF
{
    "Rules": [
        {
            "ID": "DeleteOldCheckpoints",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "checkpoints/"
            },
            "Expiration": {
                "Days": 30
            }
        },
        {
            "ID": "TransitionOldModels",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "models/"
            },
            "Transitions": [
                {
                    "Days": 90,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 365,
                    "StorageClass": "GLACIER"
                }
            ]
        },
        {
            "ID": "DeleteOldLogs",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "logs/"
            },
            "Expiration": {
                "Days": 90
            }
        }
    ]
}
EOF
)
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration "$lifecycle_config"
    
    log_success "Lifecycle rules configured for: $bucket_name"
}

# =============================================================================
# 完整项目 S3 创建 (一站式)
# =============================================================================

# 创建项目的所有 S3 资源
# 用法: create_project_s3 <team> <project> [--with-policy] [--with-lifecycle]
create_project_s3() {
    local team=$1
    local project=$2
    shift 2
    
    local with_policy=false
    local with_lifecycle=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-policy)
                with_policy=true
                shift
                ;;
            --with-lifecycle)
                with_lifecycle=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log_step "========================================"
    log_step "Creating S3 resources for project: ${team}/${project}"
    log_step "========================================"
    
    # 1. 创建 Bucket
    create_project_bucket "$team" "$project"
    
    # 2. 配置 Bucket Policy (可选)
    if [[ "$with_policy" == "true" ]]; then
        configure_bucket_policy "$team" "$project"
    fi
    
    # 3. 配置生命周期 (可选)
    if [[ "$with_lifecycle" == "true" ]]; then
        configure_bucket_lifecycle "$team" "$project"
    fi
    
    log_success "========================================"
    log_success "Project S3 resources created: ${team}/${project}"
    log_success "========================================"
}

# =============================================================================
# S3 删除函数
# =============================================================================

# 清空 S3 Bucket (删除所有对象和版本)
# 用法: empty_bucket <bucket_name>
empty_bucket() {
    local bucket_name=$1
    
    log_info "Emptying bucket: $bucket_name"
    
    # 删除所有对象版本
    log_info "  Deleting all object versions..."
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null | \
    jq -c 'select(.Objects != null) | .Objects[]' | \
    while read -r obj; do
        local key=$(echo "$obj" | jq -r '.Key')
        local version=$(echo "$obj" | jq -r '.VersionId')
        aws s3api delete-object \
            --bucket "$bucket_name" \
            --key "$key" \
            --version-id "$version" 2>/dev/null || true
    done
    
    # 删除所有删除标记
    log_info "  Deleting all delete markers..."
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null | \
    jq -c 'select(.Objects != null) | .Objects[]' | \
    while read -r obj; do
        local key=$(echo "$obj" | jq -r '.Key')
        local version=$(echo "$obj" | jq -r '.VersionId')
        aws s3api delete-object \
            --bucket "$bucket_name" \
            --key "$key" \
            --version-id "$version" 2>/dev/null || true
    done
    
    log_success "Bucket emptied: $bucket_name"
}

# 删除 S3 Bucket (包含清空)
# 用法: delete_bucket <bucket_name>
delete_bucket() {
    local bucket_name=$1
    
    # 检查是否存在
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_info "Bucket not found, skipping: $bucket_name"
        return 0
    fi
    
    log_info "Preparing to delete bucket: $bucket_name"
    
    # 先清空 bucket
    empty_bucket "$bucket_name"
    
    # 删除 bucket
    log_info "Deleting bucket: $bucket_name"
    aws s3api delete-bucket --bucket "$bucket_name"
    
    log_success "Bucket deleted: $bucket_name"
}

# 删除项目的 S3 Bucket
# 用法: delete_project_bucket <team> <project>
delete_project_bucket() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    
    log_step "========================================"
    log_step "Deleting S3 bucket for project: ${team}/${project}"
    log_step "========================================"
    
    delete_bucket "$bucket_name"
    
    log_success "========================================"
    log_success "Project S3 bucket deleted: ${team}/${project}"
    log_success "========================================"
}

