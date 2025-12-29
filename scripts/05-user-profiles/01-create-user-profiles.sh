#!/bin/bash
# =============================================================================
# 01-create-user-profiles.sh - 批量创建 User Profiles
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 获取 Security Group ID
# -----------------------------------------------------------------------------
get_studio_sg() {
    local sg_name="${TAG_PREFIX}-studio"
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
        log_error "Security group not found: $sg_name"
        exit 1
    fi
    
    echo "$sg_id"
}

# -----------------------------------------------------------------------------
# 创建 User Profile
# -----------------------------------------------------------------------------
create_user_profile() {
    local profile_name=$1
    local iam_user=$2
    local team=$3
    local team_fullname=$4
    local project=$5
    local execution_role=$6
    local sg_id=$7
    
    # 检查是否已存在
    if aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Profile already exists: $profile_name"
        return 0
    fi
    
    log_info "Creating User Profile: $profile_name"
    
    local user_settings=$(cat <<EOF
{
    "ExecutionRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${execution_role}",
    "SecurityGroups": ["${sg_id}"]
}
EOF
)
    
    aws sagemaker create-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" \
        --user-settings "$user_settings" \
        --tags \
            Key=Team,Value="$team_fullname" \
            Key=Project,Value="$project" \
            Key=Owner,Value="$iam_user" \
            Key=Environment,Value=production \
            Key=ManagedBy,Value="${TAG_PREFIX}" \
        --region "$AWS_REGION"
    
    log_success "Created: $profile_name"
    
    # 避免 API 限流
    sleep 1
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating User Profiles"
    echo "=============================================="
    echo ""
    
    local sg_id=$(get_studio_sg)
    log_info "Using Security Group: $sg_id"
    
    local created=0
    local skipped=0
    local profile_list=""
    
    # 遍历所有团队和项目
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_formatted=$(format_name "$team_fullname")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local execution_role="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
            local users=$(get_users_for_project "$team" "$project")
            
            for user in $users; do
                local profile_name="profile-${team}-${user}"
                local iam_user="sm-${team}-${user}"
                
                if aws sagemaker describe-user-profile \
                    --domain-id "$DOMAIN_ID" \
                    --user-profile-name "$profile_name" \
                    --region "$AWS_REGION" &> /dev/null; then
                    ((skipped++)) || true
                else
                    create_user_profile \
                        "$profile_name" \
                        "$iam_user" \
                        "$team" \
                        "$team_fullname" \
                        "$project" \
                        "$execution_role" \
                        "$sg_id"
                    ((created++)) || true
                fi
                
                profile_list+="${profile_name},${iam_user},${team_fullname},${project},${execution_role}\n"
            done
        done
    done
    
    # 保存 Profile 清单
    echo -e "profile_name,iam_user,team,project,execution_role" > "${SCRIPT_DIR}/${OUTPUT_DIR}/user-profiles.csv"
    echo -e "$profile_list" | sed '/^$/d' >> "${SCRIPT_DIR}/${OUTPUT_DIR}/user-profiles.csv"
    
    echo ""
    log_success "User Profiles creation complete!"
    echo ""
    echo "Summary:"
    echo "  Created:  $created profiles"
    echo "  Skipped:  $skipped profiles (already exist)"
    echo "  Total:    $((created + skipped)) profiles"
    echo ""
    echo "Profile list saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/user-profiles.csv"
}

main

