#!/bin/bash
# =============================================================================
# 01-create-policies.sh - 创建 IAM Policies
# =============================================================================
# 使用方法: ./01-create-policies.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# Policy 生成函数
# -----------------------------------------------------------------------------

# 生成基础策略 - SageMaker-Studio-Base-Access
generate_base_access_policy() {
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeDomain",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeDomain",
        "sagemaker:ListDomains"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/*"
    },
    {
      "Sid": "AllowListUserProfiles",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListUserProfiles",
        "sagemaker:ListSpaces",
        "sagemaker:ListApps"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowDescribeOwnProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeUserProfile",
        "sagemaker:CreatePresignedDomainUrl"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Owner": "\${aws:username}"
        }
      }
    }
  ]
}
EOF
}

# 生成团队策略
generate_team_access_policy() {
    local team=$1
    local team_fullname=$(get_team_fullname "$team")
    
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeTeamSpaces",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeSpace",
        "sagemaker:ListApps"
      ],
      "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Team": "${team}"
        }
      }
    },
    {
      "Sid": "AllowListTeamS3Buckets",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::${COMPANY}-sm-${team}-*"
    }
  ]
}
EOF
}

# 生成项目策略
generate_project_access_policy() {
    local team=$1
    local project=$2
    
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProjectSpaceAccess",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeSpace",
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:DescribeApp"
      ],
      "Resource": [
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*/space-${team}-${project}",
        "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:app/*/*/*/*"
      ],
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Project": "${project}"
        }
      }
    },
    {
      "Sid": "AllowProjectS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${team}-${project}",
        "arn:aws:s3:::${COMPANY}-sm-${team}-${project}/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-shared-assets",
        "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"
      ]
    },
    {
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${team^}-${project^}-ExecutionRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

# 生成 Execution Role 策略
generate_execution_role_policy() {
    local team=$1
    local project=$2
    
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ProjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-${team}-${project}",
        "arn:aws:s3:::${COMPANY}-sm-${team}-${project}/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-shared-assets",
        "arn:aws:s3:::${COMPANY}-sm-shared-assets/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/sagemaker/*"
    },
    {
      "Sid": "AllowECRPull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
EOF
}

# 生成 Permissions Boundary 策略
generate_user_boundary_policy() {
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSageMakerActions",
      "Effect": "Allow",
      "Action": [
        "sagemaker:Describe*",
        "sagemaker:List*",
        "sagemaker:CreatePresignedDomainUrl",
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3SageMakerBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPANY}-sm-*",
        "arn:aws:s3:::${COMPANY}-sm-*/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchReadOnly",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyIAMChanges",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "iam:PutUserPermissionsBoundary",
        "iam:DeleteUserPermissionsBoundary"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyBoundaryModification",
      "Effect": "Deny",
      "Action": [
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion"
      ],
      "Resource": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SageMaker-User-Boundary"
    }
  ]
}
EOF
}

# 生成只读策略
generate_readonly_policy() {
    cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadOnlyAccess",
      "Effect": "Allow",
      "Action": [
        "sagemaker:Describe*",
        "sagemaker:List*",
        "s3:GetObject",
        "s3:ListBucket",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 创建策略函数
# -----------------------------------------------------------------------------
create_policy() {
    local policy_name=$1
    local policy_document=$2
    local description=$3
    
    local policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/policy-${policy_name}.json"
    echo "$policy_document" > "$policy_file"
    
    log_info "Creating policy: $policy_name"
    
    # 检查策略是否已存在
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" &> /dev/null; then
        log_warn "Policy $policy_name already exists, updating..."
        
        # 获取当前版本数量
        local versions=$(aws iam list-policy-versions \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
            --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
        
        # 如果版本数达到5个，删除最旧的非默认版本
        local version_count=$(echo "$versions" | wc -w)
        if [[ $version_count -ge 4 ]]; then
            local oldest_version=$(aws iam list-policy-versions \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate)[0].VersionId' --output text)
            
            aws iam delete-policy-version \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                --version-id "$oldest_version"
        fi
        
        aws iam create-policy-version \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
            --policy-document "file://${policy_file}" \
            --set-as-default
    else
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "${IAM_PATH}" \
            --policy-document "file://${policy_file}" \
            --description "${description:-SageMaker IAM Policy}"
    fi
    
    log_success "Policy $policy_name created/updated"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Policies"
    echo "=============================================="
    echo ""
    
    # 1. 创建基础策略
    log_info "Creating base access policy..."
    create_policy "SageMaker-Studio-Base-Access" \
        "$(generate_base_access_policy)" \
        "Base access policy for all SageMaker Studio users"
    
    # 2. 创建只读策略
    log_info "Creating readonly policy..."
    create_policy "SageMaker-ReadOnly-Access" \
        "$(generate_readonly_policy)" \
        "Read-only access for SageMaker resources"
    
    # 3. 创建 Permissions Boundary
    log_info "Creating permissions boundary..."
    create_policy "SageMaker-User-Boundary" \
        "$(generate_user_boundary_policy)" \
        "Permissions boundary for SageMaker users"
    
    # 4. 创建团队策略
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        log_info "Creating team policy for: $team ($team_fullname)"
        
        # 首字母大写
        local team_capitalized=$(echo "$team_fullname" | sed -e 's/\b\w/\u&/g' | tr -d '-')
        
        create_policy "SageMaker-${team_capitalized}-Team-Access" \
            "$(generate_team_access_policy "$team")" \
            "Team access policy for ${team_fullname} team"
    done
    
    # 5. 创建项目策略
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            log_info "Creating project policy for: $team / $project"
            
            # 格式化名称 (project-a -> ProjectA)
            local project_formatted=$(echo "$project" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
            local team_fullname=$(get_team_fullname "$team")
            local team_capitalized=$(echo "$team_fullname" | sed -e 's/\b\w/\u&/g' | tr -d '-')
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-Access" \
                "$(generate_project_access_policy "$team" "$project")" \
                "Project access policy for ${team}/${project}"
            
            # 创建 Execution Role 策略
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy" \
                "$(generate_execution_role_policy "$team" "$project")" \
                "Execution role policy for ${team}/${project}"
        done
    done
    
    echo ""
    log_success "All policies created successfully!"
    echo ""
    echo "Policy JSON files saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/"
}

main
