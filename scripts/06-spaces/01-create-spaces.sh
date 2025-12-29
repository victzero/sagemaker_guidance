#!/bin/bash
# =============================================================================
# 01-create-spaces.sh - 批量创建 Shared Spaces
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 获取项目的 Owner（第一个用户）
# -----------------------------------------------------------------------------
get_project_owner() {
    local team=$1
    local project=$2
    
    local users=$(get_users_for_project "$team" "$project")
    echo "$users" | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# 创建 Shared Space
# -----------------------------------------------------------------------------
create_space() {
    local space_name=$1
    local team=$2
    local team_fullname=$3
    local project=$4
    local owner_profile=$5
    
    # 检查是否已存在
    if aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Space already exists: $space_name"
        return 0
    fi
    
    log_info "Creating Shared Space: $space_name"
    log_info "  Owner: $owner_profile"
    
    local space_settings=$(cat <<EOF
{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
        "EbsStorageSettings": {
            "EbsVolumeSizeInGb": ${SPACE_EBS_SIZE_GB}
        }
    }
}
EOF
)
    
    aws sagemaker create-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --space-sharing-settings '{"SharingType": "Shared"}' \
        --ownership-settings "{\"OwnerUserProfileName\": \"${owner_profile}\"}" \
        --space-settings "$space_settings" \
        --tags \
            Key=Team,Value="$team_fullname" \
            Key=Project,Value="$project" \
            Key=Owner,Value="$owner_profile" \
            Key=Environment,Value=production \
            Key=ManagedBy,Value="${TAG_PREFIX}" \
        --region "$AWS_REGION"
    
    log_success "Created: $space_name"
    
    # 避免 API 限流
    sleep 2
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating Shared Spaces"
    echo "=============================================="
    echo ""
    
    local created=0
    local skipped=0
    local space_list=""
    
    # 遍历所有团队和项目
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_formatted=$(format_name "$team_fullname")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local space_name="space-${team}-${project}"
            local owner_user=$(get_project_owner "$team" "$project")
            
            if [[ -z "$owner_user" ]]; then
                log_warn "No users found for project $team/$project, skipping"
                continue
            fi
            
            local owner_profile="profile-${team}-${owner_user}"
            local members=$(get_users_for_project "$team" "$project")
            
            # 验证 Owner Profile 存在
            if ! aws sagemaker describe-user-profile \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$owner_profile" \
                --region "$AWS_REGION" &> /dev/null; then
                log_error "Owner Profile not found: $owner_profile"
                log_info "Please run 05-user-profiles/setup-all.sh first"
                exit 1
            fi
            
            if aws sagemaker describe-space \
                --domain-id "$DOMAIN_ID" \
                --space-name "$space_name" \
                --region "$AWS_REGION" &> /dev/null; then
                ((skipped++)) || true
            else
                create_space \
                    "$space_name" \
                    "$team" \
                    "$team_fullname" \
                    "$project" \
                    "$owner_profile"
                ((created++)) || true
            fi
            
            # 生成成员列表（用分号分隔）
            local member_profiles=""
            for user in $members; do
                [[ "$user" == "$owner_user" ]] && continue
                member_profiles+="profile-${team}-${user};"
            done
            member_profiles="${member_profiles%;}"  # 移除尾部分号
            
            space_list+="${space_name},${team_fullname},${project},${owner_profile},${member_profiles}\n"
        done
    done
    
    # 保存 Space 清单
    echo -e "space_name,team,project,owner_profile,members" > "${SCRIPT_DIR}/${OUTPUT_DIR}/spaces.csv"
    echo -e "$space_list" | sed '/^$/d' >> "${SCRIPT_DIR}/${OUTPUT_DIR}/spaces.csv"
    
    echo ""
    log_success "Shared Spaces creation complete!"
    echo ""
    echo "Summary:"
    echo "  Created:  $created spaces"
    echo "  Skipped:  $skipped spaces (already exist)"
    echo "  Total:    $((created + skipped)) spaces"
    echo ""
    echo "Space list saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/spaces.csv"
}

main

