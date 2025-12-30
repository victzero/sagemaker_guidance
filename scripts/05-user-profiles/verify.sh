#!/bin/bash
# =============================================================================
# verify.sh - 验证 User Profiles 配置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " User Profiles Verification"
echo "=============================================="
echo ""
echo "Domain ID: $DOMAIN_ID"
echo ""

errors=0
verified=0

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
actual_count=0

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
        
        for user in $users; do
            profile_name="profile-${team}-${user}"
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
                        echo -e "  ${GREEN}✓${NC} $profile_name (Role: $actual_role)"
                        ((actual_count++)) || true
                    else
                        echo -e "  ${YELLOW}!${NC} $profile_name - Role mismatch"
                        echo "      Expected: $expected_role"
                        echo "      Actual:   $actual_role"
                        ((errors++)) || true
                    fi
                else
                    echo -e "  ${YELLOW}!${NC} $profile_name - Status: $status"
                    ((errors++)) || true
                fi
            else
                echo -e "  ${RED}✗${NC} $profile_name - NOT FOUND"
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
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    team_tag=$(echo "$tags" | jq -r '.Tags[] | select(.Key=="Team") | .Value // "N/A"')
    project_tag=$(echo "$tags" | jq -r '.Tags[] | select(.Key=="Project") | .Value // "N/A"')
    owner_tag=$(echo "$tags" | jq -r '.Tags[] | select(.Key=="Owner") | .Value // "N/A"')
    
    echo "Sample Profile: $sample_profile"
    echo "  Team:    $team_tag"
    echo "  Project: $project_tag"
    echo "  Owner:   $owner_tag"
    
    if [[ "$team_tag" != "N/A" && "$project_tag" != "N/A" ]]; then
        echo -e "  ${GREEN}✓${NC} Tags configured correctly"
    else
        echo -e "  ${YELLOW}!${NC} Some tags may be missing"
    fi
fi

# -----------------------------------------------------------------------------
# 统计
# -----------------------------------------------------------------------------
verify_section "Summary"

echo ""
echo "Expected Profiles: $expected_count"
echo "Verified Profiles: $actual_count"
echo "Errors:           $errors"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ $errors -eq 0 && $expected_count -eq $actual_count ]]; then
    echo -e "${GREEN}Verification PASSED${NC} - All User Profiles configured correctly"
else
    echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
fi
echo "=============================================="
echo ""
echo "List all profiles with:"
echo "  aws sagemaker list-user-profiles --domain-id $DOMAIN_ID"
echo ""

exit $errors

