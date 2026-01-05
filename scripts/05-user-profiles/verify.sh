#!/bin/bash
# =============================================================================
# verify.sh - 验证 User Profiles 和 Private Spaces 配置
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

echo ""
echo "=============================================="
echo " User Profiles & Private Spaces Verification"
echo "=============================================="
echo ""
echo "Domain ID: $DOMAIN_ID"
echo "Naming format:"
echo "  Profile: profile-{team}-{project}-{user}"
echo "  Space:   space-{team}-{project}-{user}"
echo ""

errors=0
profile_verified=0
space_verified=0

# -----------------------------------------------------------------------------
# 辅助函数
# -----------------------------------------------------------------------------
verify_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

# -----------------------------------------------------------------------------
# 验证 User Profiles
# -----------------------------------------------------------------------------
verify_section "User Profiles"

expected_count=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    team_formatted=$(format_name "$team_fullname")
    projects=$(get_projects_for_team "$team")
    
    echo ""
    echo "Team [$team - $team_fullname]:"
    
    for project in $projects; do
        project_formatted=$(format_name "$project")
        expected_role="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
        users=$(get_users_for_project "$team" "$project")
        
        # 简化项目名用于命名
        project_short=$(echo "$project" | cut -d'-' -f1)
        
        echo "  Project [$project]:"
        
        for user in $users; do
            profile_name="profile-${team}-${project_short}-${user}"
            ((expected_count++)) || true
            
            # 检查 Profile 是否存在
            profile_info=$(aws sagemaker describe-user-profile \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$profile_name" \
                --region "$AWS_REGION" 2>/dev/null || echo "")
            
            if [[ -n "$profile_info" ]]; then
                status=$(echo "$profile_info" | jq -r '.Status')
                actual_role=$(echo "$profile_info" | jq -r '.UserSettings.ExecutionRole // "N/A"' | awk -F'/' '{print $NF}')
                
                if [[ "$status" == "InService" ]]; then
                    if [[ "$actual_role" == "$expected_role" ]]; then
                        echo -e "    ${GREEN}✓${NC} $profile_name"
                        ((profile_verified++)) || true
                    else
                        echo -e "    ${YELLOW}!${NC} $profile_name - Role mismatch"
                        echo "        Expected: $expected_role"
                        echo "        Actual:   $actual_role"
                        ((errors++)) || true
                    fi
                else
                    echo -e "    ${YELLOW}!${NC} $profile_name - Status: $status"
                    ((errors++)) || true
                fi
            else
                echo -e "    ${RED}✗${NC} $profile_name - NOT FOUND"
                ((errors++)) || true
            fi
        done
    done
done

# -----------------------------------------------------------------------------
# 验证 Private Spaces
# -----------------------------------------------------------------------------
verify_section "Private Spaces"

space_expected=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    projects=$(get_projects_for_team "$team")
    
    echo ""
    echo "Team [$team - $team_fullname]:"
    
    for project in $projects; do
        users=$(get_users_for_project "$team" "$project")
        project_short=$(echo "$project" | cut -d'-' -f1)
        
        echo "  Project [$project]:"
        
        for user in $users; do
            space_name="space-${team}-${project_short}-${user}"
            profile_name="profile-${team}-${project_short}-${user}"
            ((space_expected++)) || true
            
            # 检查 Space 是否存在
            space_info=$(aws sagemaker describe-space \
                --domain-id "$DOMAIN_ID" \
                --space-name "$space_name" \
                --region "$AWS_REGION" 2>/dev/null || echo "")
            
            if [[ -n "$space_info" ]]; then
                status=$(echo "$space_info" | jq -r '.Status')
                owner=$(echo "$space_info" | jq -r '.OwnershipSettings.OwnerUserProfileName // "N/A"')
                sharing_type=$(echo "$space_info" | jq -r '.SpaceSharingSettings.SharingType // "N/A"')
                
                if [[ "$status" == "InService" ]]; then
                    if [[ "$owner" == "$profile_name" && "$sharing_type" == "Private" ]]; then
                        echo -e "    ${GREEN}✓${NC} $space_name (Owner: $owner)"
                        ((space_verified++)) || true
                    else
                        echo -e "    ${YELLOW}!${NC} $space_name - Config mismatch"
                        echo "        Expected Owner: $profile_name"
                        echo "        Actual Owner:   $owner"
                        echo "        Sharing Type:   $sharing_type"
                        ((errors++)) || true
                    fi
                else
                    echo -e "    ${YELLOW}!${NC} $space_name - Status: $status"
                    ((errors++)) || true
                fi
            else
                echo -e "    ${RED}✗${NC} $space_name - NOT FOUND"
                ((errors++)) || true
            fi
        done
    done
done

# -----------------------------------------------------------------------------
# 验证标签
# -----------------------------------------------------------------------------
verify_section "Profile Tags (sample check)"

# 随机检查一个 Profile 的标签
sample_profile=$(aws sagemaker list-user-profiles \
    --domain-id "$DOMAIN_ID" \
    --query 'UserProfiles[0].UserProfileName' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -n "$sample_profile" && "$sample_profile" != "None" ]]; then
    tags=$(aws sagemaker list-tags \
        --resource-arn "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:user-profile/${DOMAIN_ID}/${sample_profile}" \
        --region "$AWS_REGION" 2>/dev/null || echo '{"Tags":[]}')
    
    # Handle null or empty Tags array
    team_tag=$(echo "$tags" | jq -r '(.Tags // [])[] | select(.Key=="Team") | .Value' 2>/dev/null || echo "N/A")
    project_tag=$(echo "$tags" | jq -r '(.Tags // [])[] | select(.Key=="Project") | .Value' 2>/dev/null || echo "N/A")
    owner_tag=$(echo "$tags" | jq -r '(.Tags // [])[] | select(.Key=="Owner") | .Value' 2>/dev/null || echo "N/A")
    
    # Set default if empty
    [[ -z "$team_tag" ]] && team_tag="N/A"
    [[ -z "$project_tag" ]] && project_tag="N/A"
    [[ -z "$owner_tag" ]] && owner_tag="N/A"
    
    echo "Sample Profile: $sample_profile"
    echo "  Team:    $team_tag"
    echo "  Project: $project_tag"
    echo "  Owner:   $owner_tag"
    
    if [[ "$team_tag" != "N/A" && "$project_tag" != "N/A" ]]; then
        echo -e "  ${GREEN}✓${NC} Tags configured correctly"
    else
        echo -e "  ${YELLOW}!${NC} Some tags may be missing"
    fi
else
    echo "No profiles found to check tags"
fi

# -----------------------------------------------------------------------------
# 统计
# -----------------------------------------------------------------------------
verify_section "Summary"

echo ""
echo "User Profiles:"
echo "  Expected: $expected_count"
echo "  Verified: $profile_verified"
echo ""
echo "Private Spaces:"
echo "  Expected: $space_expected"
echo "  Verified: $space_verified"
echo ""
echo "Errors: $errors"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ $errors -eq 0 && $expected_count -eq $profile_verified && $space_expected -eq $space_verified ]]; then
    echo -e "${GREEN}Verification PASSED${NC} - All resources configured correctly"
else
    echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
fi
echo "=============================================="
echo ""
echo "List all resources with:"
echo "  aws sagemaker list-user-profiles --domain-id $DOMAIN_ID"
echo "  aws sagemaker list-spaces --domain-id $DOMAIN_ID"
echo ""

exit $errors
