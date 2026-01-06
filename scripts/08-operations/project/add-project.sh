#!/bin/bash
# =============================================================================
# add-project.sh - 新增项目到已有团队
# =============================================================================
#
# 场景: 团队启动新的 ML 项目
#
# 涉及资源创建:
#   - IAM Group: sagemaker-{team}-{project}
#   - IAM Policies: 项目访问、S3 访问、PassRole (3个)
#   - IAM Roles: Execution, Training, Processing, Inference (4个)
#   - S3 Bucket: {company}-sm-{team}-{project}
#   - S3 目录结构
#
# 使用方法: ./add-project.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# 静默初始化
init_silent

# 策略模板目录
POLICY_TEMPLATES_DIR="${SCRIPTS_ROOT}/01-iam/policies"

# =============================================================================
# 辅助函数
# =============================================================================

# 从模板生成策略 JSON
generate_policy_from_template() {
    local template_file=$1
    local output_file=$2
    local team=$3
    local project=$4
    
    local team_formatted=$(format_name "$(get_team_fullname "$team")")
    local project_formatted=$(format_name "$project")
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    
    sed -e "s/\${COMPANY}/${COMPANY}/g" \
        -e "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
        -e "s/\${AWS_REGION}/${AWS_REGION}/g" \
        -e "s/\${TEAM}/${team}/g" \
        -e "s/\${TEAM_FORMATTED}/${team_formatted}/g" \
        -e "s/\${PROJECT}/${project}/g" \
        -e "s/\${PROJECT_FORMATTED}/${project_formatted}/g" \
        -e "s/\${BUCKET_NAME}/${bucket_name}/g" \
        -e "s/\${IAM_PATH//\//\\/}/${IAM_PATH//\//\\/}/g" \
        "$template_file" > "$output_file"
}

# 创建或更新 IAM 策略
create_or_update_policy() {
    local policy_name=$1
    local policy_file=$2
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "Policy $policy_name already exists, creating new version..."
        aws iam create-policy-version \
            --policy-arn "$policy_arn" \
            --policy-document "file://${policy_file}" \
            --set-as-default
    else
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "${IAM_PATH}" \
            --policy-document "file://${policy_file}"
        log_success "Policy created: $policy_name"
    fi
}

# =============================================================================
# 交互式选择
# =============================================================================

echo ""
echo "=============================================="
echo " 新增项目到已有团队"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. 选择团队
# -----------------------------------------------------------------------------
echo "可用团队:"
teams=($TEAMS)
for i in "${!teams[@]}"; do
    team="${teams[$i]}"
    fullname=$(get_team_fullname "$team")
    echo "  [$((i+1))] $team ($fullname)"
done
echo ""

while true; do
    read -p "请选择团队 [1-${#teams[@]}]: " team_choice
    if [[ "$team_choice" =~ ^[0-9]+$ ]] && [ "$team_choice" -ge 1 ] && [ "$team_choice" -le "${#teams[@]}" ]; then
        SELECTED_TEAM="${teams[$((team_choice-1))]}"
        SELECTED_TEAM_FULLNAME=$(get_team_fullname "$SELECTED_TEAM")
        break
    fi
    echo "无效选择，请重试"
done

log_info "选择团队: $SELECTED_TEAM ($SELECTED_TEAM_FULLNAME)"
echo ""

# -----------------------------------------------------------------------------
# 2. 输入项目名称
# -----------------------------------------------------------------------------
echo "请输入项目名称"
echo "格式: 小写字母、数字、连字符，例如: fraud-detection"
echo ""

while true; do
    read -p "项目名称: " PROJECT_NAME
    
    # 验证格式
    if [[ ! "$PROJECT_NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        log_error "项目名格式不正确，应为小写字母开头，可包含连字符"
        continue
    fi
    
    if [[ ${#PROJECT_NAME} -lt 3 || ${#PROJECT_NAME} -gt 30 ]]; then
        log_error "项目名长度应为 3-30 字符"
        continue
    fi
    
    # 检查项目组是否已存在
    if aws iam get-group --group-name "sagemaker-${SELECTED_TEAM}-${PROJECT_NAME}" &> /dev/null; then
        log_error "项目 $PROJECT_NAME 已存在 (Group sagemaker-${SELECTED_TEAM}-${PROJECT_NAME})"
        continue
    fi
    
    break
done

log_info "项目名称: $PROJECT_NAME"
echo ""

# -----------------------------------------------------------------------------
# 3. 是否创建 S3 Bucket
# -----------------------------------------------------------------------------
read -p "是否创建项目 S3 Bucket? [Y/n]: " create_bucket
CREATE_BUCKET=true
if [[ "$create_bucket" =~ ^[Nn]$ ]]; then
    CREATE_BUCKET=false
fi

# =============================================================================
# 计算资源
# =============================================================================

TEAM_FORMATTED=$(format_name "$SELECTED_TEAM_FULLNAME")
PROJECT_FORMATTED=$(format_name "$PROJECT_NAME")
PROJECT_SHORT=$(get_project_short "$PROJECT_NAME")

GROUP_NAME="sagemaker-${SELECTED_TEAM}-${PROJECT_NAME}"
BUCKET_NAME="${COMPANY}-sm-${SELECTED_TEAM}-${PROJECT_NAME}"

# 策略名称
POLICY_ACCESS="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-Access"
POLICY_S3="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-S3Access"
POLICY_PASSROLE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-PassRole"

# 角色名称
ROLE_EXECUTION="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ExecutionRole"
ROLE_TRAINING="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-TrainingRole"
ROLE_PROCESSING="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-ProcessingRole"
ROLE_INFERENCE="SageMaker-${TEAM_FORMATTED}-${PROJECT_FORMATTED}-InferenceRole"

# =============================================================================
# 显示资源变更清单
# =============================================================================

print_changes_header "新增项目"

echo ""
echo -e "${BLUE}【将创建的资源】${NC}"
echo ""
echo "  团队: $SELECTED_TEAM ($SELECTED_TEAM_FULLNAME)"
echo "  项目: $PROJECT_NAME"
echo ""
echo "  IAM Group:"
echo "    - $GROUP_NAME"
echo ""
echo "  IAM Policies (3个):"
echo "    - $POLICY_ACCESS"
echo "    - $POLICY_S3"
echo "    - $POLICY_PASSROLE"
echo ""
echo "  IAM Roles (4个):"
echo "    - $ROLE_EXECUTION (开发/Notebook)"
echo "    - $ROLE_TRAINING (训练作业)"
echo "    - $ROLE_PROCESSING (数据处理)"
echo "    - $ROLE_INFERENCE (推理服务)"
echo ""

if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  S3 Bucket:"
    echo "    - $BUCKET_NAME"
    echo "    - 目录结构: data/, models/, notebooks/, logs/"
    echo ""
fi

print_separator
echo -e "${CYAN}Summary: 1 Group, 3 Policies, 4 Roles$([ "$CREATE_BUCKET" == "true" ] && echo ", 1 Bucket")${NC}"
print_separator

# =============================================================================
# 确认执行
# =============================================================================

if ! print_confirm_prompt; then
    log_info "操作已取消"
    exit 0
fi

# =============================================================================
# 创建临时目录
# =============================================================================

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# =============================================================================
# 执行创建
# =============================================================================

echo ""
log_step "开始创建资源..."
echo ""

# -----------------------------------------------------------------------------
# Step 1: 创建 IAM Group
# -----------------------------------------------------------------------------
log_info "Step 1/5: 创建 IAM Group..."

aws iam create-group \
    --group-name "$GROUP_NAME" \
    --path "${IAM_PATH}"

log_success "IAM Group 创建完成: $GROUP_NAME"

# -----------------------------------------------------------------------------
# Step 2: 创建 IAM Policies
# -----------------------------------------------------------------------------
log_info "Step 2/5: 创建 IAM Policies..."

# 生成项目访问策略
cat > "${TEMP_DIR}/project-access.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowProjectSpaceAccess",
            "Effect": "Allow",
            "Action": [
                "sagemaker:CreateSpace",
                "sagemaker:DeleteSpace",
                "sagemaker:DescribeSpace",
                "sagemaker:ListSpaces"
            ],
            "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/*/space-${SELECTED_TEAM}-${PROJECT_SHORT}-*"
        },
        {
            "Sid": "AllowProjectProfileAccess",
            "Effect": "Allow",
            "Action": [
                "sagemaker:DescribeUserProfile",
                "sagemaker:ListUserProfiles"
            ],
            "Resource": "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/*/profile-${SELECTED_TEAM}-${PROJECT_SHORT}-*"
        }
    ]
}
EOF

create_or_update_policy "$POLICY_ACCESS" "${TEMP_DIR}/project-access.json"

# 生成 S3 访问策略
cat > "${TEMP_DIR}/s3-access.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowProjectBucketAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "AllowSageMakerDefaultBucket",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}",
                "arn:aws:s3:::sagemaker-${AWS_REGION}-${AWS_ACCOUNT_ID}/*"
            ]
        }
    ]
}
EOF

create_or_update_policy "$POLICY_S3" "${TEMP_DIR}/s3-access.json"

# 生成 PassRole 策略
cat > "${TEMP_DIR}/passrole.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPassRoleToProjectRoles",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": [
                "arn:aws:iam::${AWS_ACCOUNT_ID}:role${IAM_PATH}${ROLE_EXECUTION}",
                "arn:aws:iam::${AWS_ACCOUNT_ID}:role${IAM_PATH}${ROLE_TRAINING}",
                "arn:aws:iam::${AWS_ACCOUNT_ID}:role${IAM_PATH}${ROLE_PROCESSING}",
                "arn:aws:iam::${AWS_ACCOUNT_ID}:role${IAM_PATH}${ROLE_INFERENCE}"
            ],
            "Condition": {
                "StringEquals": {
                    "iam:PassedToService": "sagemaker.amazonaws.com"
                }
            }
        }
    ]
}
EOF

create_or_update_policy "$POLICY_PASSROLE" "${TEMP_DIR}/passrole.json"

log_success "IAM Policies 创建完成"

# -----------------------------------------------------------------------------
# Step 3: 绑定策略到 Group
# -----------------------------------------------------------------------------
log_info "Step 3/5: 绑定策略到 Group..."

POLICY_ARN_PREFIX="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"

# 绑定项目策略
aws iam attach-group-policy \
    --group-name "$GROUP_NAME" \
    --policy-arn "${POLICY_ARN_PREFIX}${POLICY_ACCESS}"

aws iam attach-group-policy \
    --group-name "$GROUP_NAME" \
    --policy-arn "${POLICY_ARN_PREFIX}${POLICY_S3}"

aws iam attach-group-policy \
    --group-name "$GROUP_NAME" \
    --policy-arn "${POLICY_ARN_PREFIX}${POLICY_PASSROLE}"

# 绑定共享 Deny Admin 策略
if aws iam get-policy --policy-arn "${POLICY_ARN_PREFIX}SageMaker-Shared-DenyAdmin" &> /dev/null; then
    aws iam attach-group-policy \
        --group-name "$GROUP_NAME" \
        --policy-arn "${POLICY_ARN_PREFIX}SageMaker-Shared-DenyAdmin"
fi

log_success "策略绑定完成"

# -----------------------------------------------------------------------------
# Step 4: 创建 IAM Roles
# -----------------------------------------------------------------------------
log_info "Step 4/5: 创建 IAM Roles..."

# Trust Policy
cat > "${TEMP_DIR}/trust-policy.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "sagemaker.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# 创建 4 个角色
for role_name in "$ROLE_EXECUTION" "$ROLE_TRAINING" "$ROLE_PROCESSING" "$ROLE_INFERENCE"; do
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, skipping..."
    else
        aws iam create-role \
            --role-name "$role_name" \
            --path "${IAM_PATH}" \
            --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
            --tags \
                Key=Team,Value="$SELECTED_TEAM_FULLNAME" \
                Key=Project,Value="$PROJECT_NAME" \
                Key=ManagedBy,Value="${TAG_PREFIX}"
        
        # 附加 SageMakerFullAccess
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        # 附加 S3 访问策略
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "${POLICY_ARN_PREFIX}${POLICY_S3}"
        
        log_success "Role created: $role_name"
    fi
done

# -----------------------------------------------------------------------------
# Step 5: 创建 S3 Bucket (可选)
# -----------------------------------------------------------------------------
if [[ "$CREATE_BUCKET" == "true" ]]; then
    log_info "Step 5/5: 创建 S3 Bucket..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warn "Bucket $BUCKET_NAME already exists, skipping..."
    else
        # 创建 bucket
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "$BUCKET_NAME"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        
        # 启用版本控制
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        # 创建目录结构
        for dir in data models notebooks logs; do
            aws s3api put-object --bucket "$BUCKET_NAME" --key "${dir}/"
        done
        
        # 添加标签
        aws s3api put-bucket-tagging \
            --bucket "$BUCKET_NAME" \
            --tagging "TagSet=[{Key=Team,Value=${SELECTED_TEAM_FULLNAME}},{Key=Project,Value=${PROJECT_NAME}},{Key=ManagedBy,Value=${TAG_PREFIX}}]"
        
        log_success "S3 Bucket 创建完成: $BUCKET_NAME"
    fi
else
    log_info "Step 5/5: 跳过 S3 Bucket 创建"
fi

# =============================================================================
# 完成信息
# =============================================================================

echo ""
print_separator
echo -e "${GREEN}✅ 项目创建完成!${NC}"
print_separator
echo ""
echo "创建的资源:"
echo "  - IAM Group: $GROUP_NAME"
echo "  - IAM Policies: $POLICY_ACCESS, $POLICY_S3, $POLICY_PASSROLE"
echo "  - IAM Roles: $ROLE_EXECUTION, $ROLE_TRAINING, $ROLE_PROCESSING, $ROLE_INFERENCE"
if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  - S3 Bucket: $BUCKET_NAME"
fi
echo ""

echo -e "${YELLOW}📌 后续步骤:${NC}"
echo ""
echo "  1. 添加用户到项目:"
echo "     cd ../user && ./add-user.sh"
echo "     或"
echo "     cd ../user && ./add-user-to-project.sh"
echo ""
echo "  2. (可选) 更新 .env.shared 添加项目配置:"
echo "     ${SELECTED_TEAM^^}_PROJECTS=\"... ${PROJECT_NAME}\""
echo ""

echo "验证命令:"
echo "  aws iam get-group --group-name $GROUP_NAME"
echo "  aws iam get-role --role-name $ROLE_EXECUTION"
if [[ "$CREATE_BUCKET" == "true" ]]; then
    echo "  aws s3 ls s3://$BUCKET_NAME/"
fi
echo ""

