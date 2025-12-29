#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 User Profiles (危险操作!)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: User Profiles Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following User Profiles:"
echo "  - All profiles created by this script"
echo "  - User home directories (EFS data)"
echo ""
echo "Domain ID: $DOMAIN_ID"
echo ""

# 列出将要删除的 Profiles
profile_count=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        for user in $users; do
            profile_name="profile-${team}-${user}"
            echo "  - $profile_name"
            ((profile_count++)) || true
        done
    done
done

echo ""
echo "Total: $profile_count profiles"
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
# 删除 User Profiles
# -----------------------------------------------------------------------------
log_info "Deleting User Profiles..."

deleted=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        for user in $users; do
            profile_name="profile-${team}-${user}"
            
            # 检查是否存在
            if ! aws sagemaker describe-user-profile \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$profile_name" \
                --region "$AWS_REGION" &> /dev/null; then
                log_info "Profile not found, skipping: $profile_name"
                continue
            fi
            
            # 先删除所有 Apps
            log_info "Deleting Apps for: $profile_name"
            apps=$(aws sagemaker list-apps \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$profile_name" \
                --query 'Apps[?Status!=`Deleted`].[AppType,AppName]' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
            
            while IFS=$'\t' read -r app_type app_name; do
                [[ -z "$app_name" ]] && continue
                log_info "  Deleting App: $app_type/$app_name"
                aws sagemaker delete-app \
                    --domain-id "$DOMAIN_ID" \
                    --user-profile-name "$profile_name" \
                    --app-type "$app_type" \
                    --app-name "$app_name" \
                    --region "$AWS_REGION" 2>/dev/null || true
            done <<< "$apps"
            
            # 等待 Apps 删除
            if [[ -n "$apps" ]]; then
                sleep 10
            fi
            
            # 删除 Profile
            log_info "Deleting Profile: $profile_name"
            aws sagemaker delete-user-profile \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$profile_name" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete $profile_name"
            
            ((deleted++)) || true
            sleep 1
        done
    done
done

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
log_info "Cleaning up output files..."
rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/user-profiles.csv" 2>/dev/null || true

echo ""
log_success "Cleanup complete!"
echo ""
echo "Deleted: $deleted profiles"
echo ""
echo "Note: EFS home directories will be deleted with the profiles."

