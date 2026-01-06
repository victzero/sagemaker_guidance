#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 User Profiles 和 Private Spaces (危险操作!)
# =============================================================================
#
# 命名规范:
#   User Profile: profile-{team}-{project}-{user}
#   Private Space: space-{team}-{project}-{user}
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 加载删除函数库 (统一实现，避免代码重复)
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"

FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: User Profiles & Private Spaces Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following resources:"
echo "  - All User Profiles created by this script"
echo "  - All Private Spaces created by this script"
echo "  - User home directories (EFS data)"
echo ""
echo "Domain ID: $DOMAIN_ID"
echo ""

# 列出将要删除的资源
profile_count=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        # 简化项目名用于命名 (使用 lib 函数)
        project_short=$(get_project_short "$project")
        
        for user in $users; do
            profile_name="profile-${team}-${project_short}-${user}"
            space_name="space-${team}-${project_short}-${user}"
            echo "  - Profile: $profile_name"
            echo "    Space:   $space_name"
            ((profile_count++)) || true
        done
    done
done

echo ""
echo "Total: $profile_count profiles + $profile_count spaces"
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
# 删除 Private Spaces (必须先于 User Profiles)
# 注意: 删除函数已移至 lib/sagemaker-factory.sh 统一维护
# 可用函数: delete_private_space, delete_sagemaker_user_profile
# -----------------------------------------------------------------------------
log_info "Deleting Private Spaces..."

space_deleted=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        project_short=$(get_project_short "$project")
        
        for user in $users; do
            space_name="space-${team}-${project_short}-${user}"
            delete_private_space "$DOMAIN_ID" "$space_name"
            ((space_deleted++)) || true
            sleep 2
        done
    done
done

# 等待 Spaces 完全删除
if [[ $space_deleted -gt 0 ]]; then
    log_info "Waiting for Spaces to be fully deleted..."
    sleep 10
fi

# -----------------------------------------------------------------------------
# 删除 User Profiles
# -----------------------------------------------------------------------------
log_info "Deleting User Profiles..."

profile_deleted=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        project_short=$(get_project_short "$project")
        
        for user in $users; do
            profile_name="profile-${team}-${project_short}-${user}"
            delete_sagemaker_user_profile "$DOMAIN_ID" "$profile_name"
            ((profile_deleted++)) || true
            sleep 1
        done
    done
done

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
log_info "Cleaning up output files..."
rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/user-profiles.csv" 2>/dev/null || true
rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/private-spaces.csv" 2>/dev/null || true

echo ""
log_success "Cleanup complete!"
echo ""
echo "Deleted:"
echo "  - Spaces:   $space_deleted"
echo "  - Profiles: $profile_deleted"
echo ""
echo "Note: EFS home directories will be deleted with the profiles."
