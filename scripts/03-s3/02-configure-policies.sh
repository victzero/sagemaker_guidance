#!/bin/bash
# =============================================================================
# 02-configure-policies.sh - 配置 S3 Bucket Policies
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 生成项目 Bucket Policy
# -----------------------------------------------------------------------------
generate_project_bucket_policy() {
    local bucket_name=$1
    local team=$2
    local project=$3
    
    local team_fullname=$(get_team_fullname "$team")
    # 使用 common.sh 中的 format_name 函数，确保与 01-iam 命名一致
    local team_formatted=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local execution_role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
    
    # 注意: Execution Role 使用默认路径 (/)，不使用 IAM_PATH
    # ARN 格式: arn:aws:iam::ACCOUNT:role/ROLE_NAME
    
    local policy='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowExecutionRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::'"${AWS_ACCOUNT_ID}"':role/'"${execution_role_name}"'"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::'"${bucket_name}"'",
        "arn:aws:s3:::'"${bucket_name}"'/*"
      ]
    },
    {
      "Sid": "AllowProjectMembersConsoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::'"${AWS_ACCOUNT_ID}"':root"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::'"${bucket_name}"'",
        "arn:aws:s3:::'"${bucket_name}"'/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-'"${team}"'-*"
        }
      }
    }'
    
    # 如果启用 VPC 限制，添加拒绝规则
    if [[ "${RESTRICT_TO_VPC}" == "true" && -n "${VPC_ID}" ]]; then
        policy="${policy}"',
    {
      "Sid": "DenyNonVPCAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::'"${bucket_name}"'",
        "arn:aws:s3:::'"${bucket_name}"'/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:SourceVpc": "'"${VPC_ID}"'"
        },
        "Bool": {
          "aws:ViaAWSService": "false"
        }
      }
    }'
    fi
    
    policy="${policy}"'
  ]
}'
    
    echo "$policy"
}

# -----------------------------------------------------------------------------
# 生成共享 Bucket Policy
# -----------------------------------------------------------------------------
generate_shared_bucket_policy() {
    local bucket_name=$1
    
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAllExecutionRolesReadOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-*-ExecutionRole"
        }
      }
    },
    {
      "Sid": "AllowAllSageMakerUsersReadOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-*"
        }
      }
    },
    {
      "Sid": "AllowAdminFullAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-admin-*"
        }
      }
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 应用 Bucket Policy
# -----------------------------------------------------------------------------
apply_bucket_policy() {
    local bucket_name=$1
    local policy=$2
    local policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/policy-${bucket_name}.json"
    
    log_info "Applying policy to bucket: $bucket_name"
    
    # 保存 policy 到文件
    echo "$policy" > "$policy_file"
    
    aws s3api put-bucket-policy \
        --bucket "$bucket_name" \
        --policy "file://${policy_file}" \
        --region "$AWS_REGION"
    
    log_success "Policy applied to $bucket_name"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Configuring S3 Bucket Policies"
    echo "=============================================="
    echo ""
    
    # 1. 配置项目 Bucket Policies
    for team in $TEAMS; do
        log_info "Configuring policies for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local bucket_name=$(get_bucket_name "$team" "$project")
            
            # 检查 bucket 是否存在
            if ! aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
                log_warn "Bucket $bucket_name does not exist, skipping..."
                continue
            fi
            
            local policy=$(generate_project_bucket_policy "$bucket_name" "$team" "$project")
            apply_bucket_policy "$bucket_name" "$policy"
        done
    done
    
    # 2. 配置共享 Bucket Policy
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        local shared_bucket=$(get_shared_bucket_name)
        
        if aws s3api head-bucket --bucket "$shared_bucket" --region "$AWS_REGION" 2>/dev/null; then
            log_info "Configuring shared bucket policy..."
            local shared_policy=$(generate_shared_bucket_policy "$shared_bucket")
            apply_bucket_policy "$shared_bucket" "$shared_policy"
        fi
    fi
    
    echo ""
    log_success "All bucket policies configured!"
    echo ""
    echo "Policy files saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/"
}

main
