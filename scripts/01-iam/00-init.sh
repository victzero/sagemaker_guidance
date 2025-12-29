#!/bin/bash
# =============================================================================
# 00-init.sh - IAM 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# IAM 特有配置
# -----------------------------------------------------------------------------
setup_iam_defaults() {
    # 设置默认 IAM_PATH (使用 COMPANY 前缀)
    if [[ -z "$IAM_PATH" ]]; then
        IAM_PATH="/${COMPANY}-sagemaker/"
    fi
    export IAM_PATH
    
    # 设置默认密码前后缀
    if [[ -z "$PASSWORD_PREFIX" ]]; then
        PASSWORD_PREFIX="Welcome#"
    fi
    if [[ -z "$PASSWORD_SUFFIX" ]]; then
        PASSWORD_SUFFIX="@2024"
    fi
    export PASSWORD_PREFIX PASSWORD_SUFFIX
}

# -----------------------------------------------------------------------------
# 统计预期资源数量
# -----------------------------------------------------------------------------
count_expected_resources() {
    local team_count=0
    local project_count=0
    local user_count=0
    
    # 统计管理员
    for admin in $ADMIN_USERS; do
        ((user_count++)) || true
    done
    
    # 统计团队和项目
    for team in $TEAMS; do
        ((team_count++)) || true
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            ((project_count++)) || true
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                ((user_count++)) || true
            done
        done
    done
    
    # 计算各类资源数量
    EXPECTED_POLICIES=$((3 + team_count + project_count * 2))  # base + readonly + boundary + team + project*2
    EXPECTED_GROUPS=$((2 + team_count + project_count))        # admins + readonly + team + project
    EXPECTED_USERS=$user_count
    EXPECTED_ROLES=$project_count
    
    export EXPECTED_POLICIES EXPECTED_GROUPS EXPECTED_USERS EXPECTED_ROLES
}

# -----------------------------------------------------------------------------
# IAM 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_iam_summary() {
    echo "  IAM Path:     $IAM_PATH"
    echo ""
    echo "Expected Resources:"
    echo "  Policies:     $EXPECTED_POLICIES"
    echo "  Groups:       $EXPECTED_GROUPS"
    echo "  Users:        $EXPECTED_USERS"
    echo "  Roles:        $EXPECTED_ROLES"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker IAM Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_team_env
    check_aws_cli
    setup_iam_defaults
    ensure_output_dir
    count_expected_resources
    
    print_config_summary "IAM" print_iam_summary
    
    log_success "Initialization complete!"
}

# 如果直接执行此脚本，运行初始化
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
