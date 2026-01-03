#!/bin/bash
# =============================================================================
# 02-create-private-spaces.sh - 为每个 User Profile 创建 Private Space
# =============================================================================
#
# 命名规范: space-{team}-{project}-{user}
#
# 设计说明:
# - 每个 User Profile 有一个对应的 Private Space
# - Private Space 自动继承 User Profile 的 Execution Role
# - 用户登录 Studio 后可以直接使用，无需手动创建
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 默认 EBS 大小 (GB)
SPACE_EBS_SIZE_GB=${SPACE_EBS_SIZE_GB:-50}

# -----------------------------------------------------------------------------
# 创建 Private Space
# -----------------------------------------------------------------------------
create_private_space() {
    local space_name=$1
    local profile_name=$2
    local team_fullname=$3
    local project=$4
    local user=$5
    
    # 检查是否已存在
    if aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Space already exists: $space_name"
        return 0
    fi
    
    # 检查 User Profile 是否存在
    if ! aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_error "User Profile not found: $profile_name"
        log_error "Please run 01-create-user-profiles.sh first"
        return 1
    fi
    
    log_info "Creating Private Space: $space_name"
    log_info "  Owner Profile: $profile_name"
    
    # Space 设置（继承 Domain 的 idle shutdown 配置）
    local space_settings=$(cat <<EOF
{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
        "EbsStorageSettings": {
            "EbsVolumeSizeInGb": ${SPACE_EBS_SIZE_GB}
        }
    },
    "JupyterLabAppSettings": {
        "AppLifecycleManagement": {
            "IdleSettings": {
                "LifecycleManagement": "ENABLED"
            }
        }
    }
}
EOF
)
    
    aws sagemaker create-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --space-sharing-settings '{"SharingType": "Private"}' \
        --ownership-settings "{\"OwnerUserProfileName\": \"${profile_name}\"}" \
        --space-settings "$space_settings" \
        --tags \
            Key=Team,Value="$team_fullname" \
            Key=Project,Value="$project" \
            Key=Owner,Value="$user" \
            Key=SpaceType,Value="private" \
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
    echo " Creating Private Spaces"
    echo "=============================================="
    echo ""
    echo "Naming format: space-{team}-{project}-{user}"
    echo "EBS Size: ${SPACE_EBS_SIZE_GB} GB"
    echo "Idle Shutdown: ENABLED (inherits from Domain)"
    echo ""
    
    local created=0
    local skipped=0
    local space_list=""
    
    # 遍历所有团队和项目
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local users=$(get_users_for_project "$team" "$project")
            
            # 简化项目名用于命名 (fraud-detection -> fraud)
            local project_short=$(echo "$project" | cut -d'-' -f1)
            
            for user in $users; do
                # 命名格式: space-{team}-{project}-{user}
                local space_name="space-${team}-${project_short}-${user}"
                local profile_name="profile-${team}-${project_short}-${user}"
                
                if aws sagemaker describe-space \
                    --domain-id "$DOMAIN_ID" \
                    --space-name "$space_name" \
                    --region "$AWS_REGION" &> /dev/null; then
                    ((skipped++)) || true
                    log_warn "Skipping existing: $space_name"
                else
                    create_private_space \
                        "$space_name" \
                        "$profile_name" \
                        "$team_fullname" \
                        "$project" \
                        "$user"
                    ((created++)) || true
                fi
                
                space_list+="${space_name},${profile_name},${team_fullname},${project},private\n"
            done
        done
    done
    
    # 保存 Space 清单
    echo -e "space_name,profile_name,team,project,type" > "${SCRIPT_DIR}/${OUTPUT_DIR}/private-spaces.csv"
    echo -e "$space_list" | sed '/^$/d' >> "${SCRIPT_DIR}/${OUTPUT_DIR}/private-spaces.csv"
    
    echo ""
    log_success "Private Spaces creation complete!"
    echo ""
    echo "Summary:"
    echo "  Created:  $created spaces"
    echo "  Skipped:  $skipped spaces (already exist)"
    echo "  Total:    $((created + skipped)) spaces"
    echo ""
    echo "Space list saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/private-spaces.csv"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 Private Space 说明:"
    echo ""
    echo "  • 每个 User Profile 有一个对应的 Private Space"
    echo "  • Space 自动继承 User Profile 的 Execution Role"
    echo "  • 用户登录 Studio 后可以直接使用"
    echo "  • Space 中可以访问项目 S3 桶"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main

