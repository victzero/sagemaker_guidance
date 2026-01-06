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
# S3 Bucket 创建
# =============================================================================

# 创建项目 S3 Bucket
# 用法: create_project_bucket <team> <project>
create_project_bucket() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    local team_fullname=$(get_team_fullname "$team")
    
    log_info "Creating S3 bucket: $bucket_name"
    
    # 检查是否已存在
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warn "Bucket $bucket_name already exists, skipping creation..."
        return 0
    fi
    
    # 创建 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$bucket_name"
    else
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # 启用版本控制
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled
    
    # 阻止公共访问
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # 创建标准目录结构
    local directories=(
        "data/"
        "raw/"
        "processed/"
        "features/"
        "datasets/"
        "models/"
        "training-output/"
        "checkpoints/"
        "inference/"
        "inference/output/"
        "batch-transform/"
        "notebooks/"
        "logs/"
    )
    
    for dir in "${directories[@]}"; do
        aws s3api put-object --bucket "$bucket_name" --key "$dir"
    done
    
    # 添加标签
    aws s3api put-bucket-tagging \
        --bucket "$bucket_name" \
        --tagging "TagSet=[{Key=Team,Value=${team_fullname}},{Key=Project,Value=${project}},{Key=ManagedBy,Value=${COMPANY}-sagemaker}]"
    
    log_success "S3 Bucket created: $bucket_name"
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

