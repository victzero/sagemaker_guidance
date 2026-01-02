#!/bin/bash
# =============================================================================
# 03-create-users.sh - 创建 IAM Users
# =============================================================================
# 使用方法: ./03-create-users.sh [--enable-console-login]
#
# 参数:
#   --enable-console-login  启用 AWS Console 登录（默认禁用）
#
# 环境变量:
#   ENABLE_CONSOLE_LOGIN=true  也可通过环境变量启用
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 解析命令行参数
ENABLE_CONSOLE=${ENABLE_CONSOLE_LOGIN:-false}
for arg in "$@"; do
    case $arg in
        --enable-console-login)
            ENABLE_CONSOLE=true
            shift
            ;;
    esac
done

if [[ "$ENABLE_CONSOLE" == "true" ]]; then
    log_warn "Console login is ENABLED - users will be able to log in to AWS Console"
else
    log_info "Console login is DISABLED (default) - users will only have API access"
    log_info "Use --enable-console-login or set ENABLE_CONSOLE_LOGIN=true to enable"
fi

# -----------------------------------------------------------------------------
# 创建 User 函数
# -----------------------------------------------------------------------------
create_user() {
    local username=$1
    local team=$2
    local initial_password="${PASSWORD_PREFIX}${username}${PASSWORD_SUFFIX}"
    local user_exists=false
    
    log_info "Creating user: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists"
        user_exists=true
    else
        # 创建用户
        aws iam create-user \
            --user-name "$username" \
            --path "${IAM_PATH}" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=ManagedBy,Value=sagemaker-iam-script" \
                "Key=Owner,Value=${username}"
        log_success "User $username created"
    fi
    
    # 根据 ENABLE_CONSOLE 决定是否创建 LoginProfile
    if [[ "$ENABLE_CONSOLE" == "true" ]]; then
        # 检查/创建 LoginProfile (允许 Console 登录)
        if ! aws iam get-login-profile --user-name "$username" &> /dev/null; then
            aws iam create-login-profile \
                --user-name "$username" \
                --password "$initial_password" \
                --password-reset-required
            log_success "LoginProfile created for $username (Console login enabled)"
            
            # 保存凭证到文件 (仅供参考，应安全传递给用户)
            echo "${username}:${initial_password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
        else
            if [[ "$user_exists" == "true" ]]; then
                log_warn "LoginProfile already exists for $username, skipping..."
            fi
        fi
    else
        # Console 登录禁用，检查是否存在 LoginProfile 并提示
        if aws iam get-login-profile --user-name "$username" &> /dev/null; then
            log_warn "User $username has LoginProfile (Console access). Consider removing it if not needed."
        fi
        log_info "Console login disabled for $username (API access only)"
    fi
    
    # 检查/应用 Permissions Boundary
    local current_boundary=$(aws iam get-user --user-name "$username" \
        --query 'User.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>/dev/null || echo "None")
    local expected_boundary="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-User-Boundary"
    
    if [[ "$current_boundary" != "$expected_boundary" ]]; then
        aws iam put-user-permissions-boundary \
            --user-name "$username" \
            --permissions-boundary "$expected_boundary"
        log_success "Applied permissions boundary to $username"
    else
        if [[ "$user_exists" == "true" ]]; then
            log_warn "Permissions boundary already applied to $username"
        fi
    fi
}

# 创建管理员用户
create_admin_user() {
    local admin_name=$1
    local username="sm-admin-${admin_name}"
    local initial_password="${PASSWORD_PREFIX}${admin_name}${PASSWORD_SUFFIX}"
    local user_exists=false
    
    log_info "Creating admin user: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists"
        user_exists=true
    else
        aws iam create-user \
            --user-name "$username" \
            --path "${IAM_PATH}" \
            --tags \
                "Key=Role,Value=admin" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        log_success "Admin user $username created"
    fi
    
    # 管理员用户：根据 ENABLE_CONSOLE 决定是否创建 LoginProfile
    if [[ "$ENABLE_CONSOLE" == "true" ]]; then
        if ! aws iam get-login-profile --user-name "$username" &> /dev/null; then
            aws iam create-login-profile \
                --user-name "$username" \
                --password "$initial_password" \
                --password-reset-required
            log_success "LoginProfile created for $username (Console login enabled)"
            
            echo "${username}:${initial_password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
        else
            if [[ "$user_exists" == "true" ]]; then
                log_warn "LoginProfile already exists for $username, skipping..."
            fi
        fi
    else
        if aws iam get-login-profile --user-name "$username" &> /dev/null; then
            log_warn "Admin $username has LoginProfile (Console access). Consider removing it if not needed."
        fi
        log_info "Console login disabled for $username (API access only)"
    fi
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
    
    echo "Console Login: $([ "$ENABLE_CONSOLE" == "true" ] && echo "ENABLED" || echo "DISABLED")"
    echo ""
    
    # 清空凭证文件（仅在启用 Console 登录时）
    if [[ "$ENABLE_CONSOLE" == "true" ]]; then
        > "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
        chmod 600 "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
    fi
    
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
    if [[ "$ENABLE_CONSOLE" == "true" ]]; then
        log_warn "Initial credentials saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
        log_warn "Please distribute credentials securely and delete this file!"
    else
        log_info "Console login disabled - no credentials file generated"
        log_info "Users can access SageMaker via CreatePresignedDomainUrl API"
    fi
}

main
