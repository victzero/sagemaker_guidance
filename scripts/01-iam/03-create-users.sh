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

# 策略模板目录 (lib/iam-core.sh 依赖)
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# -----------------------------------------------------------------------------
# 加载核心函数库 (复用 lib/ 中的 User 创建函数)
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# -----------------------------------------------------------------------------
# 解析命令行参数
# -----------------------------------------------------------------------------
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
# 注意: create_iam_user(), create_admin_user() 已移至 lib/iam-core.sh 统一维护
# -----------------------------------------------------------------------------

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
        local password=$(create_admin_user "$admin" "$ENABLE_CONSOLE")
        
        # 保存凭证（如果启用了 Console 登录）
        if [[ "$ENABLE_CONSOLE" == "true" && -n "$password" ]]; then
            echo "sm-admin-${admin}:${password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
        fi
    done
    
    # 2. 创建团队用户
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        log_info "Creating users for team: $team ($team_fullname)"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            log_info "  Project: $project"
            
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                local username="sm-${team}-${user}"
                # 传入 team_fullname 和 project 用于 Tags
                local password=$(create_iam_user "$username" "$team_fullname" "$ENABLE_CONSOLE" "$project")
                
                # 保存凭证（如果启用了 Console 登录）
                if [[ "$ENABLE_CONSOLE" == "true" && -n "$password" ]]; then
                    echo "${username}:${password}" >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-credentials.txt"
                fi
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
