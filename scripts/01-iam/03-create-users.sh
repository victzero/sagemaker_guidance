#!/bin/bash
# =============================================================================
# 03-create-users.sh - 创建 IAM Users
# =============================================================================
# 使用方法: ./03-create-users.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 创建 User 函数
# -----------------------------------------------------------------------------
create_user() {
    local username=$1
    local team=$2
    local initial_password="${PASSWORD_PREFIX}${username}${PASSWORD_SUFFIX}"
    
    log_info "Creating user: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists, skipping..."
        return 0
    fi
    
    # 创建用户
    aws iam create-user \
        --user-name "$username" \
        --path "${IAM_PATH}" \
        --tags \
            "Key=Team,Value=${team}" \
            "Key=ManagedBy,Value=sagemaker-iam-script" \
            "Key=Owner,Value=${username}"
    
    # 设置初始密码 (需要首次登录重置)
    aws iam create-login-profile \
        --user-name "$username" \
        --password "$initial_password" \
        --password-reset-required
    
    log_success "User $username created with initial password"
    
    # 保存凭证到文件 (仅供参考，应安全传递给用户)
    echo "${username}:${initial_password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    
    # 应用 Permissions Boundary
    aws iam put-user-permissions-boundary \
        --user-name "$username" \
        --permissions-boundary "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-User-Boundary"
    
    log_success "Applied permissions boundary to $username"
}

# 创建管理员用户
create_admin_user() {
    local username="sm-admin-$1"
    
    log_info "Creating admin user: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists, skipping..."
        return 0
    fi
    
    local initial_password="${PASSWORD_PREFIX}${1}${PASSWORD_SUFFIX}"
    
    aws iam create-user \
        --user-name "$username" \
        --path "${IAM_PATH}" \
        --tags \
            "Key=Role,Value=admin" \
            "Key=ManagedBy,Value=sagemaker-iam-script"
    
    aws iam create-login-profile \
        --user-name "$username" \
        --password "$initial_password" \
        --password-reset-required
    
    echo "${username}:${initial_password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    
    log_success "Admin user $username created"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Users"
    echo "=============================================="
    echo ""
    
    # 清空凭证文件
    > "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    chmod 600 "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    
    # 1. 创建管理员用户
    log_info "Creating admin users..."
    for admin in $ADMIN_USERS; do
        create_admin_user "$admin"
    done
    
    # 2. 创建团队用户
    for team in $TEAMS; do
        log_info "Creating users for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            log_info "  Project: $project"
            
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                local username="sm-${team}-${user}"
                create_user "$username" "$team"
            done
        done
    done
    
    echo ""
    log_success "All users created successfully!"
    echo ""
    
    # 显示创建的 Users
    echo "Created Users:"
    aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'Users[].UserName' --output table
    
    echo ""
    log_warn "Initial credentials saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    log_warn "Please distribute credentials securely and delete this file!"
}

main
