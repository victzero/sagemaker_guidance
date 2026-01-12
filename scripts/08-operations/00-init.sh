#!/bin/bash
# =============================================================================
# 00-init.sh - Operations 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
#
# 配置加载顺序:
#   1. scripts/.env.shared         (共享配置)
#   2. scripts/01-iam/.env.local   (IAM 配置: PASSWORD_PREFIX, IAM_PATH 等)
#   3. scripts/04-sagemaker-domain/.env.local (Domain 配置: DOMAIN_ID 等)
#   4. scripts/05-user-profiles/.env.local (Profile 配置: SPACE_EBS_SIZE_GB 等)
#   5. scripts/08-operations/.env.local (本地覆盖，可选)
#
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# 加载核心函数库
POLICY_TEMPLATES_DIR="${SCRIPTS_ROOT}/01-iam/policies"  # iam-core.sh 依赖
source "${SCRIPTS_ROOT}/lib/iam-core.sh"
source "${SCRIPTS_ROOT}/lib/discovery.sh"
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"
source "${SCRIPTS_ROOT}/lib/instance-whitelist.sh"

# -----------------------------------------------------------------------------
# 加载相关模块的配置（复用已有配置）
# -----------------------------------------------------------------------------
load_module_configs() {
    local modules=("01-iam" "04-sagemaker-domain" "05-user-profiles")
    
    for module in "${modules[@]}"; do
        local env_file="${SCRIPTS_ROOT}/${module}/.env.local"
        if [[ -f "$env_file" ]]; then
            set -a
            source "$env_file"
            set +a
        fi
    done
    
    # 本地覆盖配置（最高优先级）
    if [[ -f "${SCRIPT_DIR}/.env.local" ]]; then
        set -a
        source "${SCRIPT_DIR}/.env.local"
        set +a
    fi
}

# -----------------------------------------------------------------------------
# Operations 特有配置（设置默认值）
# -----------------------------------------------------------------------------
setup_operations_defaults() {
    # 默认 IAM_PATH (使用 COMPANY 前缀)
    if [[ -z "$IAM_PATH" ]]; then
        IAM_PATH="/${COMPANY}-sagemaker/"
    fi
    export IAM_PATH
    
    # 设置默认密码前后缀（如果未从 01-iam 加载）
    if [[ -z "$PASSWORD_PREFIX" ]]; then
        PASSWORD_PREFIX="Welcome#"
    fi
    if [[ -z "$PASSWORD_SUFFIX" ]]; then
        PASSWORD_SUFFIX="@2024"
    fi
    export PASSWORD_PREFIX PASSWORD_SUFFIX
    
    # 设置默认 EBS 大小（如果未从 05-user-profiles 加载）
    if [[ -z "$SPACE_EBS_SIZE_GB" ]]; then
        SPACE_EBS_SIZE_GB=50
    fi
    export SPACE_EBS_SIZE_GB
    
    # TAG_PREFIX 用于资源标记
    if [[ -z "$TAG_PREFIX" ]]; then
        TAG_PREFIX="${COMPANY}-sagemaker"
    fi
    export TAG_PREFIX
}

# -----------------------------------------------------------------------------
# 注意: get_domain_id() 和 get_studio_sg() 已移至 lib/sagemaker-factory.sh
# 这里的函数现在直接使用 lib 版本
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 获取团队列表 (动态发现，fallback 到 .env)
# -----------------------------------------------------------------------------
get_team_list() {
    # 优先使用动态发现
    local discovered=$(discover_teams)
    if [[ -n "$discovered" ]]; then
        echo "$discovered"
        return 0
    fi
    # Fallback 到 .env 配置
    echo "$TEAMS"
}

# -----------------------------------------------------------------------------
# 获取团队的项目列表 (使用 lib/discovery.sh)
# -----------------------------------------------------------------------------
get_project_list() {
    local team=$1
    get_project_list_dynamic "$team"
}

# -----------------------------------------------------------------------------
# 验证用户名格式 (Operations 独有，用于交互式输入验证)
# -----------------------------------------------------------------------------
validate_username() {
    local username=$1
    
    # 只允许小写字母和数字
    if [[ ! "$username" =~ ^[a-z][a-z0-9]*$ ]]; then
        log_error "Invalid username format. Must start with letter, contain only lowercase letters and numbers."
        return 1
    fi
    
    # 长度限制
    if [[ ${#username} -lt 2 || ${#username} -gt 20 ]]; then
        log_error "Username must be 2-20 characters."
        return 1
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# 存在性检查 - 使用 lib 函数的便捷包装器
# 注意: iam_user_exists, user_in_group 直接使用 lib/iam-core.sh 中的函数
# -----------------------------------------------------------------------------

# 检查 User Profile 是否存在 (使用环境变量 DOMAIN_ID)
# 用法: profile_exists <profile_name>
profile_exists() {
    local profile_name=$1
    sagemaker_profile_exists "$DOMAIN_ID" "$profile_name"
}

# 检查 Space 是否存在 (使用环境变量 DOMAIN_ID)
# 用法: space_exists <space_name>
space_exists() {
    local space_name=$1
    sagemaker_space_exists "$DOMAIN_ID" "$space_name"
}

# -----------------------------------------------------------------------------
# 注意: get_project_short() 已移至 lib/sagemaker-factory.sh
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 打印分隔线
# -----------------------------------------------------------------------------
print_separator() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# -----------------------------------------------------------------------------
# 打印资源变更清单头
# -----------------------------------------------------------------------------
print_changes_header() {
    local operation=$1
    echo ""
    print_separator
    echo -e "${YELLOW}📋 资源变更清单 - ${operation}${NC}"
    print_separator
}

# -----------------------------------------------------------------------------
# 打印确认提示
# -----------------------------------------------------------------------------
print_confirm_prompt() {
    echo ""
    print_separator
    read -p "确认执行以上操作? [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# Operations 配置摘要
# -----------------------------------------------------------------------------
print_operations_summary() {
    echo "  IAM Path:     $IAM_PATH"
    echo "  Domain ID:    $DOMAIN_ID"
}

# -----------------------------------------------------------------------------
# 初始化（静默模式，用于交互式脚本）
# -----------------------------------------------------------------------------
init_silent() {
    load_env
    load_module_configs
    validate_base_env
    check_aws_cli
    setup_operations_defaults
    get_domain_id > /dev/null
}

# -----------------------------------------------------------------------------
# 初始化（完整模式）
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker Operations - Initialization"
    echo "=============================================="
    
    load_env
    load_module_configs
    validate_base_env
    validate_team_env
    check_aws_cli
    setup_operations_defaults
    get_domain_id > /dev/null
    
    print_config_summary "Operations" print_operations_summary
    
    log_success "Initialization complete!"
}

# 如果直接执行此脚本，运行初始化
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

