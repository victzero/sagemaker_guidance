#!/bin/bash
# =============================================================================
# cleanup.sh - 清理所有 IAM 资源 (危险操作!)
# =============================================================================
# 使用方法: ./cleanup.sh [--force]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 检查 force 参数
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: IAM Resource Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following resources:"
echo "  - All IAM Users with path ${IAM_PATH}"
echo "  - All IAM Groups with path ${IAM_PATH}"
echo "  - All IAM Roles with path ${IAM_PATH}"
echo "  - All IAM Policies with path ${IAM_PATH}"
echo ""

if [[ "$FORCE" != "true" ]]; then
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# 清理函数
# -----------------------------------------------------------------------------

# 移除用户的所有组关系
remove_user_from_groups() {
    local username=$1
    
    local groups=$(aws iam list-groups-for-user --user-name "$username" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
    
    for group in $groups; do
        log_info "Removing $username from group $group"
        run_cmd aws iam remove-user-from-group \
            --user-name "$username" \
            --group-name "$group"
    done
}

# 删除用户的登录配置
delete_user_login_profile() {
    local username=$1
    
    if aws iam get-login-profile --user-name "$username" &> /dev/null; then
        log_info "Deleting login profile for $username"
        run_cmd aws iam delete-login-profile --user-name "$username"
    fi
}

# 删除用户的 Access Keys
delete_user_access_keys() {
    local username=$1
    
    local keys=$(aws iam list-access-keys --user-name "$username" \
        --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
    
    for key in $keys; do
        log_info "Deleting access key $key for $username"
        run_cmd aws iam delete-access-key \
            --user-name "$username" \
            --access-key-id "$key"
    done
}

# 删除用户的 Permissions Boundary
delete_user_boundary() {
    local username=$1
    
    log_info "Removing permissions boundary for $username"
    run_cmd aws iam delete-user-permissions-boundary \
        --user-name "$username" 2>/dev/null || true
}

# 删除用户
delete_user() {
    local username=$1
    
    log_info "Preparing to delete user: $username"
    
    # 先清理用户的所有关联
    remove_user_from_groups "$username"
    delete_user_login_profile "$username"
    delete_user_access_keys "$username"
    delete_user_boundary "$username"
    
    # 删除用户
    log_info "Deleting user: $username"
    run_cmd aws iam delete-user --user-name "$username"
    
    log_success "User $username deleted"
}

# 分离组的所有策略
detach_group_policies() {
    local group_name=$1
    
    local policies=$(aws iam list-attached-group-policies --group-name "$group_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $policies; do
        log_info "Detaching policy from group $group_name"
        run_cmd aws iam detach-group-policy \
            --group-name "$group_name" \
            --policy-arn "$policy_arn"
    done
}

# 删除组
delete_group() {
    local group_name=$1
    
    log_info "Preparing to delete group: $group_name"
    
    # 先分离所有策略
    detach_group_policies "$group_name"
    
    # 删除组
    log_info "Deleting group: $group_name"
    run_cmd aws iam delete-group --group-name "$group_name"
    
    log_success "Group $group_name deleted"
}

# 分离角色的所有策略
detach_role_policies() {
    local role_name=$1
    
    local policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $policies; do
        log_info "Detaching policy from role $role_name"
        run_cmd aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
    done
}

# 删除角色
delete_role() {
    local role_name=$1
    
    log_info "Preparing to delete role: $role_name"
    
    # 先分离所有策略
    detach_role_policies "$role_name"
    
    # 删除角色
    log_info "Deleting role: $role_name"
    run_cmd aws iam delete-role --role-name "$role_name"
    
    log_success "Role $role_name deleted"
}

# 删除策略的所有版本
delete_policy_versions() {
    local policy_arn=$1
    
    local versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
    
    for version in $versions; do
        log_info "Deleting policy version $version"
        run_cmd aws iam delete-policy-version \
            --policy-arn "$policy_arn" \
            --version-id "$version"
    done
}

# 删除策略
delete_policy() {
    local policy_arn=$1
    
    log_info "Preparing to delete policy: $policy_arn"
    
    # 先删除非默认版本
    delete_policy_versions "$policy_arn"
    
    # 删除策略
    log_info "Deleting policy: $policy_arn"
    run_cmd aws iam delete-policy --policy-arn "$policy_arn"
    
    log_success "Policy deleted"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    log_info "Starting cleanup..."
    
    # 1. 删除用户
    log_info "Step 1: Deleting users..."
    local users=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'Users[].UserName' --output text 2>/dev/null || echo "")
    
    for user in $users; do
        delete_user "$user"
    done
    
    # 2. 删除组
    log_info "Step 2: Deleting groups..."
    local groups=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
    
    for group in $groups; do
        delete_group "$group"
    done
    
    # 3. 删除角色
    log_info "Step 3: Deleting roles..."
    local roles=$(aws iam list-roles --path-prefix "${IAM_PATH}" \
        --query 'Roles[].RoleName' --output text 2>/dev/null || echo "")
    
    for role in $roles; do
        delete_role "$role"
    done
    
    # 4. 删除策略
    log_info "Step 4: Deleting policies..."
    local policies=$(aws iam list-policies --scope Local --path-prefix "${IAM_PATH}" \
        --query 'Policies[].Arn' --output text 2>/dev/null || echo "")
    
    for policy in $policies; do
        delete_policy "$policy"
    done
    
    echo ""
    log_success "Cleanup complete!"
}

main
