#!/bin/bash
# =============================================================================
# 06-add-users-to-groups.sh - 添加 Users 到 Groups
# =============================================================================
# 使用方法: ./06-add-users-to-groups.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 策略模板目录 (lib/iam-core.sh 依赖)
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# -----------------------------------------------------------------------------
# 加载核心函数库 (复用 lib/ 中的 add_user_to_group 函数)
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# -----------------------------------------------------------------------------
# 注意: add_user_to_group() 已移至 lib/iam-core.sh 统一维护
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Adding Users to Groups"
    echo "=============================================="
    echo ""
    
    # 1. 添加管理员到管理员组
    log_info "Adding admin users to admin group..."
    for admin in $ADMIN_USERS; do
        local username="sm-admin-${admin}"
        add_user_to_group "$username" "sagemaker-admins"
    done
    
    # 2. 添加团队用户到相应组
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        log_info "Processing team: $team ($team_fullname)"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            log_info "  Processing project: $project"
            
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                local username="sm-${team}-${user}"
                
                # 添加到团队组
                add_user_to_group "$username" "sagemaker-${team_fullname}"
                
                # 添加到项目组
                add_user_to_group "$username" "sagemaker-${team}-${project}"
            done
        done
    done
    
    echo ""
    log_success "All users added to groups successfully!"
    echo ""
    
    # 显示用户-组关系
    echo "User-Group Memberships:"
    echo "========================"
    
    # 列出所有用户的组
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                local username="sm-${team}-${user}"
                echo ""
                echo "User: $username"
                aws iam list-groups-for-user --user-name "$username" \
                    --query 'Groups[].GroupName' --output table 2>/dev/null || true
            done
        done
    done
    
    # 管理员用户
    for admin in $ADMIN_USERS; do
        local username="sm-admin-${admin}"
        echo ""
        echo "User: $username (Admin)"
        aws iam list-groups-for-user --user-name "$username" \
            --query 'Groups[].GroupName' --output table 2>/dev/null || true
    done
}

main
