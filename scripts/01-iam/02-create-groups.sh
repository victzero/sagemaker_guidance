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

# -----------------------------------------------------------------------------
# 创建 Group 函数
# -----------------------------------------------------------------------------
create_group() {
    local group_name=$1
    
    log_info "Creating group: $group_name"
    
    # 检查 Group 是否已存在
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        log_warn "Group $group_name already exists, skipping..."
        return 0
    fi
    
    run_cmd aws iam create-group \
        --group-name "$group_name" \
        --path "${IAM_PATH}"
    
    log_success "Group $group_name created"
}

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
    create_group "sagemaker-admins"
    create_group "sagemaker-readonly"
    
    # 2. 创建团队级 Groups
    log_info "Creating team-level groups..."
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        create_group "sagemaker-${team_fullname}"
    done
    
    # 3. 创建项目级 Groups
    log_info "Creating project-level groups..."
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            create_group "sagemaker-${team}-${project}"
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
