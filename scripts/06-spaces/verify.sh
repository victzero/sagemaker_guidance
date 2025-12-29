#!/bin/bash
# =============================================================================
# verify.sh - 验证 Shared Spaces 配置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Shared Spaces Verification"
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

get_project_owner() {
    local team=$1
    local project=$2
    local users=$(get_users_for_project "$team" "$project")
    echo "$users" | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# 验证 Shared Spaces
# -----------------------------------------------------------------------------
verify_section "Shared Spaces"

expected_count=0
actual_count=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    projects=$(get_projects_for_team "$team")
    
    echo ""
    echo "Team [$team - $team_fullname]:"
    
    for project in $projects; do
        space_name="space-${team}-${project}"
        expected_owner="profile-${team}-$(get_project_owner "$team" "$project")"
        ((expected_count++)) || true
        
        # 检查 Space 是否存在
        space_info=$(aws sagemaker describe-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$space_info" ]]; then
            status=$(echo "$space_info" | jq -r '.Status')
            actual_owner=$(echo "$space_info" | jq -r '.OwnershipSettings.OwnerUserProfileName // "N/A"')
            sharing_type=$(echo "$space_info" | jq -r '.SpaceSharingSettings.SharingType // "N/A"')
            ebs_size=$(echo "$space_info" | jq -r '.SpaceSettings.SpaceStorageSettings.EbsStorageSettings.EbsVolumeSizeInGb // "N/A"')
            
            if [[ "$status" == "InService" ]]; then
                echo -e "  ${GREEN}✓${NC} $space_name"
                echo "      Status: $status"
                echo "      Owner:  $actual_owner"
                echo "      Type:   $sharing_type"
                echo "      EBS:    ${ebs_size} GB"
                ((actual_count++)) || true
                
                # 检查 Owner 是否正确
                if [[ "$actual_owner" != "$expected_owner" ]]; then
                    echo -e "      ${YELLOW}!${NC} Owner mismatch (expected: $expected_owner)"
                fi
            else
                echo -e "  ${YELLOW}!${NC} $space_name - Status: $status"
                ((errors++)) || true
            fi
        else
            echo -e "  ${RED}✗${NC} $space_name - NOT FOUND"
            ((errors++)) || true
        fi
    done
done

# -----------------------------------------------------------------------------
# 验证标签
# -----------------------------------------------------------------------------
verify_section "Space Tags (sample check)"

# 随机检查一个 Space 的标签
sample_space=$(aws sagemaker list-spaces \
    --domain-id "$DOMAIN_ID" \
    --query 'Spaces[0].SpaceName' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -n "$sample_space" && "$sample_space" != "None" ]]; then
    tags=$(aws sagemaker list-tags \
        --resource-arn "arn:aws:sagemaker:${AWS_REGION}:${AWS_ACCOUNT_ID}:space/${DOMAIN_ID}/${sample_space}" \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    team_tag=$(echo "$tags" | jq -r '.Tags[] | select(.Key=="Team") | .Value // "N/A"')
    project_tag=$(echo "$tags" | jq -r '.Tags[] | select(.Key=="Project") | .Value // "N/A"')
    
    echo "Sample Space: $sample_space"
    echo "  Team:    $team_tag"
    echo "  Project: $project_tag"
    
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
echo "Expected Spaces: $expected_count"
echo "Verified Spaces: $actual_count"
echo "Errors:         $errors"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ $errors -eq 0 && $expected_count -eq $actual_count ]]; then
    echo -e "${GREEN}Verification PASSED${NC} - All Shared Spaces configured correctly"
else
    echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
fi
echo "=============================================="
echo ""
echo "List all spaces with:"
echo "  aws sagemaker list-spaces --domain-id $DOMAIN_ID"
echo ""

exit $errors

