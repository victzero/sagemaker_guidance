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
# 获取 Domain ID
# -----------------------------------------------------------------------------
get_domain_id() {
    if [[ -n "$DOMAIN_ID" ]]; then
        echo "$DOMAIN_ID"
        return 0
    fi
    
    # 尝试从 SageMaker 获取 Domain ID
    local domain_id=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME:-sagemaker-domain}'].DomainId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$domain_id" || "$domain_id" == "None" ]]; then
        # 尝试获取任意 Domain
        domain_id=$(aws sagemaker list-domains \
            --query "Domains[0].DomainId" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$domain_id" || "$domain_id" == "None" ]]; then
        log_error "No SageMaker Domain found. Please create a domain first."
        exit 1
    fi
    
    DOMAIN_ID="$domain_id"
    export DOMAIN_ID
    echo "$domain_id"
}

# -----------------------------------------------------------------------------
# 获取 Studio Security Group ID
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

# Alias for sagemaker-factory.sh compatibility
get_studio_security_group() {
    get_studio_sg
}

# -----------------------------------------------------------------------------
# 获取团队列表
# -----------------------------------------------------------------------------
get_team_list() {
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
# 验证用户名格式
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
# 检查 IAM User 是否存在
# -----------------------------------------------------------------------------
iam_user_exists() {
    local username=$1
    aws iam get-user --user-name "$username" &> /dev/null
}

# -----------------------------------------------------------------------------
# 检查 User Profile 是否存在
# -----------------------------------------------------------------------------
profile_exists() {
    local profile_name=$1
    aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null
}

# -----------------------------------------------------------------------------
# 检查 Space 是否存在
# -----------------------------------------------------------------------------
space_exists() {
    local space_name=$1
    aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null
}

# -----------------------------------------------------------------------------
# 检查用户是否在 Group 中
# -----------------------------------------------------------------------------
user_in_group() {
    local username=$1
    local group_name=$2
    
    local in_group=$(aws iam get-group --group-name "$group_name" \
        --query "Users[?UserName=='${username}'].UserName" \
        --output text 2>/dev/null || echo "")
    
    [[ -n "$in_group" ]]
}

# -----------------------------------------------------------------------------
# 简化项目名 (fraud-detection -> fraud)
# -----------------------------------------------------------------------------
get_project_short() {
    local project=$1
    echo "$project" | cut -d'-' -f1
}

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

