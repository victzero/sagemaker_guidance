#!/bin/bash
# =============================================================================
# 01-create-user-profiles.sh - 批量创建 User Profiles
# =============================================================================
#
# 命名规范: profile-{team}-{project}-{user}
#
# 设计说明:
# - 每个用户在每个参与的项目中有独立的 User Profile
# - User Profile 绑定项目级 Execution Role
# - 用户登录 Studio 后使用 Private Space，可访问项目 S3 桶
#
# 示例:
#   Alice 参与 fraud-detection 和 aml 两个项目:
#   - profile-rc-fraud-alice → SageMaker-RC-Fraud-ExecutionRole
#   - profile-rc-aml-alice   → SageMaker-RC-AML-ExecutionRole
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 注意: get_studio_sg() 和 create_user_profile() 已移至 lib/sagemaker-factory.sh
# 本脚本复用 lib 版本，保持逻辑一致
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 主函数 (使用 lib/sagemaker-factory.sh 中的 create_user_profile)
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating User Profiles"
    echo "=============================================="
    echo ""
    echo "Naming format: profile-{team}-{project}-{user}"
    echo ""
    
    # 使用 lib 函数获取 Security Group
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
            local execution_role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
            local execution_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${execution_role_name}"
            local users=$(get_users_for_project "$team" "$project")
            
            # 简化项目名用于 Profile 命名 (fraud-detection -> fraud)
            local project_short=$(get_project_short "$project")
            
            for user in $users; do
                # 新命名格式: profile-{team}-{project}-{user}
                local profile_name="profile-${team}-${project_short}-${user}"
                local iam_user="sm-${team}-${user}"
                
                if aws sagemaker describe-user-profile \
                    --domain-id "$DOMAIN_ID" \
                    --user-profile-name "$profile_name" \
                    --region "$AWS_REGION" &> /dev/null; then
                    ((skipped++)) || true
                    log_warn "Skipping existing: $profile_name"
                else
                    # 使用 lib/sagemaker-factory.sh 中的 create_user_profile
                    # 参数顺序: domain_id, profile_name, execution_role_arn, sg_id, team, project, iam_username
                    create_user_profile \
                        "$DOMAIN_ID" \
                        "$profile_name" \
                        "$execution_role_arn" \
                        "$sg_id" \
                        "$team" \
                        "$project" \
                        "$iam_user"
                    ((created++)) || true
                fi
                
                profile_list+="${profile_name},${iam_user},${team_fullname},${project},${execution_role_name}\n"
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
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 User Profile 说明:"
    echo ""
    echo "  • 每个用户在每个参与的项目中有独立的 Profile"
    echo "  • Profile 绑定项目级 Execution Role"
    echo "  • 用户登录 Studio 时选择对应项目的 Profile"
    echo "  • 在 Private Space 中可访问项目 S3 桶"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main
