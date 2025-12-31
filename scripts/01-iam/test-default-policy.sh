#!/bin/bash
# =============================================================================
# test-default-policy.sh - 临时应用 AWS 默认配置进行测试
# =============================================================================
# 目的: 验证是否是自定义权限配置导致的问题
#
# 方案 A: AWS 默认配置
#   ✅ 开箱即用，无兼容性问题
#   ✅ AWS 官方支持的标准配置
#   ❌ S3 权限过大 (arn:aws:s3:::*)
#   ❌ 仅用于测试，测试完成后应恢复
#
# 使用方法:
#   ./test-default-policy.sh apply <username>   # 应用默认配置
#   ./test-default-policy.sh revert <username>  # 恢复原配置
#   ./test-default-policy.sh status <username>  # 查看当前状态
#
# 示例:
#   ./test-default-policy.sh apply sm-algo-david
#   ./test-default-policy.sh revert sm-algo-david
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

ACTION="${1:-status}"
USERNAME="${2:-}"

if [[ -z "$USERNAME" ]]; then
    echo "Usage: $0 <apply|revert|status> <username>"
    echo ""
    echo "Example:"
    echo "  $0 apply sm-algo-david"
    echo "  $0 revert sm-algo-david"
    echo "  $0 status sm-algo-david"
    exit 1
fi

# 测试策略名称
TEST_POLICY_NAME="SageMaker-Test-FullAccess"
TEST_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${TEST_POLICY_NAME}"

# -----------------------------------------------------------------------------
# 生成 AWS 默认风格的完全开放策略
# -----------------------------------------------------------------------------
generate_test_full_access_policy() {
    cat << POLICYEOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAllSageMaker",
      "Effect": "Allow",
      "Action": "sagemaker:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowAllS3",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:CreateBucket",
        "s3:ListAllMyBuckets"
      ],
      "Resource": "arn:aws:s3:::*"
    },
    {
      "Sid": "AllowDataScienceAssistant",
      "Effect": "Allow",
      "Action": [
        "sagemaker-data-science-assistant:SendConversation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAmazonQ",
      "Effect": "Allow",
      "Action": [
        "q:SendMessage",
        "q:StartConversation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSTS",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "sts:AssumeRole",
        "sts:GetSessionToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowECR",
      "Effect": "Allow",
      "Action": "ecr:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowLogs",
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowIAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AllowIAMRead",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:ListRoles"
      ],
      "Resource": "*"
    }
  ]
}
POLICYEOF
}

# -----------------------------------------------------------------------------
# 创建测试策略
# -----------------------------------------------------------------------------
create_test_policy() {
    log_info "Checking test policy: $TEST_POLICY_NAME"
    
    if aws iam get-policy --policy-arn "$TEST_POLICY_ARN" &> /dev/null; then
        log_warn "Test policy already exists"
        return 0
    fi
    
    local policy_file="${SCRIPT_DIR}/.output/policy-test-fullaccess.json"
    mkdir -p "${SCRIPT_DIR}/.output"
    generate_test_full_access_policy > "$policy_file"
    
    aws iam create-policy \
        --policy-name "$TEST_POLICY_NAME" \
        --path "${IAM_PATH}" \
        --policy-document "file://${policy_file}" \
        --description "TEST ONLY - Full access policy for troubleshooting"
    
    log_success "Created test policy: $TEST_POLICY_NAME"
}

# -----------------------------------------------------------------------------
# 应用默认配置
# -----------------------------------------------------------------------------
apply_default_config() {
    local username=$1
    
    echo ""
    echo "=============================================="
    echo " Apply AWS Default Config (TEST)"
    echo "=============================================="
    echo ""
    echo "Username: $username"
    echo ""
    
    # 验证用户存在
    if ! aws iam get-user --user-name "$username" &> /dev/null; then
        log_error "User not found: $username"
        exit 1
    fi
    
    # 创建测试策略
    create_test_policy
    
    # 获取用户所属的组
    local groups=$(aws iam list-groups-for-user --user-name "$username" \
        --query 'Groups[].GroupName' --output text)
    
    echo "Current groups: $groups"
    echo ""
    
    # 保存当前状态
    local backup_file="${SCRIPT_DIR}/.output/backup-${username}.txt"
    echo "# Backup for $username - $(date)" > "$backup_file"
    echo "GROUPS=\"$groups\"" >> "$backup_file"
    log_info "Saved backup to: $backup_file"
    
    # 直接附加测试策略到用户
    log_info "Attaching test policy to user..."
    
    if aws iam list-attached-user-policies --user-name "$username" \
        --query "AttachedPolicies[?PolicyName=='$TEST_POLICY_NAME']" --output text | grep -q "$TEST_POLICY_NAME"; then
        log_warn "Test policy already attached to user"
    else
        aws iam attach-user-policy \
            --user-name "$username" \
            --policy-arn "$TEST_POLICY_ARN"
        log_success "Attached test policy to user"
    fi
    
    # 附加 AmazonSageMakerFullAccess
    local sm_full_access="arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
    if aws iam list-attached-user-policies --user-name "$username" \
        --query "AttachedPolicies[?PolicyArn=='$sm_full_access']" --output text | grep -q "AmazonSageMakerFullAccess"; then
        log_warn "AmazonSageMakerFullAccess already attached"
    else
        aws iam attach-user-policy \
            --user-name "$username" \
            --policy-arn "$sm_full_access"
        log_success "Attached AmazonSageMakerFullAccess"
    fi
    
    echo ""
    log_success "Default config applied to $username"
    echo ""
    echo "=============================================="
    echo " IMPORTANT - TEST MODE ENABLED"
    echo "=============================================="
    echo ""
    echo "⚠️  User now has FULL S3 access (arn:aws:s3:::*)"
    echo "⚠️  This is for TESTING ONLY"
    echo ""
    echo "Next steps:"
    echo "  1. Ask $username to clear browser cache"
    echo "  2. Re-login to AWS Console"
    echo "  3. Try accessing SageMaker Studio"
    echo ""
    echo "After testing, run:"
    echo "  $0 revert $username"
    echo ""
}

# -----------------------------------------------------------------------------
# 恢复原配置
# -----------------------------------------------------------------------------
revert_config() {
    local username=$1
    
    echo ""
    echo "=============================================="
    echo " Revert to Original Config"
    echo "=============================================="
    echo ""
    echo "Username: $username"
    echo ""
    
    # 移除测试策略
    log_info "Removing test policy from user..."
    
    if aws iam list-attached-user-policies --user-name "$username" \
        --query "AttachedPolicies[?PolicyName=='$TEST_POLICY_NAME']" --output text | grep -q "$TEST_POLICY_NAME"; then
        aws iam detach-user-policy \
            --user-name "$username" \
            --policy-arn "$TEST_POLICY_ARN"
        log_success "Removed test policy"
    else
        log_warn "Test policy not attached"
    fi
    
    # 移除直接附加的 AmazonSageMakerFullAccess
    local sm_full_access="arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
    if aws iam list-attached-user-policies --user-name "$username" \
        --query "AttachedPolicies[?PolicyArn=='$sm_full_access']" --output text | grep -q "AmazonSageMakerFullAccess"; then
        aws iam detach-user-policy \
            --user-name "$username" \
            --policy-arn "$sm_full_access"
        log_success "Removed AmazonSageMakerFullAccess (direct)"
    fi
    
    echo ""
    log_success "Reverted $username to original config"
    echo ""
    echo "User permissions now come from group memberships only."
    echo ""
}

# -----------------------------------------------------------------------------
# 查看状态
# -----------------------------------------------------------------------------
show_status() {
    local username=$1
    
    echo ""
    echo "=============================================="
    echo " User Policy Status"
    echo "=============================================="
    echo ""
    echo "Username: $username"
    echo ""
    
    # 验证用户存在
    if ! aws iam get-user --user-name "$username" &> /dev/null; then
        log_error "User not found: $username"
        exit 1
    fi
    
    echo "Groups:"
    aws iam list-groups-for-user --user-name "$username" \
        --query 'Groups[].GroupName' --output table
    
    echo ""
    echo "Directly Attached Policies:"
    aws iam list-attached-user-policies --user-name "$username" \
        --query 'AttachedPolicies[].PolicyName' --output table
    
    echo ""
    echo "Policies from Groups:"
    for group in $(aws iam list-groups-for-user --user-name "$username" --query 'Groups[].GroupName' --output text); do
        echo "  Group: $group"
        aws iam list-attached-group-policies --group-name "$group" \
            --query 'AttachedPolicies[].PolicyName' --output text | tr '\t' '\n' | sed 's/^/    - /'
    done
    
    echo ""
    
    # 检查是否有测试策略
    if aws iam list-attached-user-policies --user-name "$username" \
        --query "AttachedPolicies[?PolicyName=='$TEST_POLICY_NAME']" --output text | grep -q "$TEST_POLICY_NAME"; then
        echo "⚠️  TEST MODE: User has test full-access policy attached"
    else
        echo "✓ Normal mode: No test policy attached"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# 主逻辑
# -----------------------------------------------------------------------------
case "$ACTION" in
    apply)
        apply_default_config "$USERNAME"
        ;;
    revert)
        revert_config "$USERNAME"
        ;;
    status)
        show_status "$USERNAME"
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: $0 <apply|revert|status> <username>"
        exit 1
        ;;
esac

