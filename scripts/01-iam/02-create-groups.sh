#!/bin/bash
# =============================================================================
# 02-create-groups.sh - 创建 IAM Groups
# =============================================================================
# 使用方法: ./02-create-groups.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 策略模板目录 (lib/iam-core.sh 依赖)
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# -----------------------------------------------------------------------------
# 加载核心函数库 (复用 lib/ 中的 Group 创建函数)
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# -----------------------------------------------------------------------------
# 注意: create_iam_group(), create_team_group(), create_project_group()
# 已移至 lib/iam-core.sh 统一维护
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Groups"
    echo "=============================================="
    echo ""
    
    # 1. 创建平台级 Groups
    log_info "Creating platform-level groups..."
    create_iam_group "sagemaker-admins"
    create_iam_group "sagemaker-readonly"
    
    # 2. 创建团队级 Groups
    log_info "Creating team-level groups..."
    for team in $TEAMS; do
        create_team_group "$team"
    done
    
    # 3. 创建项目级 Groups
    log_info "Creating project-level groups..."
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            create_project_group "$team" "$project"
        done
    done
    
    echo ""
    log_success "All groups created successfully!"
    echo ""
    
    # 显示创建的 Groups
    echo "Created Groups:"
    aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'Groups[].GroupName' --output table
}

main
