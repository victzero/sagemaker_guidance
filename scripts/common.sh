#!/bin/bash
# =============================================================================
# common.sh - SageMaker 脚本共享函数库
# =============================================================================
# 使用方法: source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
# =============================================================================

# 防止重复加载
if [[ -n "$_SAGEMAKER_COMMON_LOADED" ]]; then
    return 0
fi
_SAGEMAKER_COMMON_LOADED=1

# 获取 common.sh 所在目录（即 scripts/ 目录）
SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 调用者脚本所在目录
SCRIPT_DIR="${SCRIPT_DIR:-$(pwd)}"

# -----------------------------------------------------------------------------
# 颜色输出
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $1"; }

# -----------------------------------------------------------------------------
# 加载环境变量
# -----------------------------------------------------------------------------
# 加载顺序:
#   1. scripts/.env.shared (共享配置)
#   2. scripts/{module}/.env.local (模块特有配置，可覆盖共享配置)
# -----------------------------------------------------------------------------
load_env() {
    # 1. 加载共享配置
    if [[ -f "${SCRIPTS_ROOT}/.env.shared" ]]; then
        log_info "Loading shared environment from .env.shared"
        set -a
        source "${SCRIPTS_ROOT}/.env.shared"
        set +a
    else
        log_error "Shared environment file not found: ${SCRIPTS_ROOT}/.env.shared"
        log_info "Please create it from template:"
        log_info "  cd ${SCRIPTS_ROOT}"
        log_info "  cp .env.shared.example .env.shared"
        log_info "  vi .env.shared"
        exit 1
    fi
    
    # 2. 加载模块特有配置（可选，会覆盖共享配置）
    if [[ -f "${SCRIPT_DIR}/.env.local" ]]; then
        log_info "Loading local environment from .env.local"
        set -a
        source "${SCRIPT_DIR}/.env.local"
        set +a
    fi
    
    # 兼容旧的 .env 文件（如果存在则警告）
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_warn "Found legacy .env file. Consider migrating to .env.shared + .env.local"
        log_info "Loading legacy .env for backward compatibility..."
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    fi
}

# -----------------------------------------------------------------------------
# 验证基础环境变量
# -----------------------------------------------------------------------------
validate_base_env() {
    log_info "Validating base environment variables..."
    
    local required_vars=(
        "COMPANY"
        "AWS_ACCOUNT_ID"
        "AWS_REGION"
    )
    
    local missing=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    log_success "Base environment variables validated"
}

# -----------------------------------------------------------------------------
# 验证团队配置
# -----------------------------------------------------------------------------
validate_team_env() {
    if [[ -z "$TEAMS" ]]; then
        log_warn "TEAMS is empty - no team resources will be created"
        return 0
    fi
    
    log_info "Validating team configuration..."
    
    for team in $TEAMS; do
        local fullname_var="TEAM_${team^^}_FULLNAME"
        if [[ -z "${!fullname_var}" ]]; then
            log_error "Missing team fullname: $fullname_var"
            exit 1
        fi
    done
    
    log_success "Team configuration validated"
}

# -----------------------------------------------------------------------------
# 检查 AWS CLI
# -----------------------------------------------------------------------------
check_aws_cli() {
    log_info "Checking AWS CLI..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # 禁用 AWS CLI 分页器，避免输出阻塞
    export AWS_PAGER=""
    
    # 检测 CloudShell 环境（不需要 AWS_PROFILE）
    if [[ -n "$AWS_EXECUTION_ENV" && "$AWS_EXECUTION_ENV" == "CloudShell" ]] || [[ -n "$CLOUD_SHELL" ]]; then
        log_info "Running in AWS CloudShell"
        unset AWS_PROFILE  # CloudShell 使用内置凭证
    elif [[ -n "$AWS_PROFILE" ]]; then
        export AWS_PROFILE
        log_info "Using AWS Profile: $AWS_PROFILE"
    fi
    
    # 检查 AWS 配置
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured or no valid credentials."
        log_info "Please run 'aws configure' first."
        exit 1
    fi
    
    # 获取当前身份
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_success "AWS CLI configured. Current identity: $identity"
    
    # 验证账号 ID
    local current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        echo ""
        log_error "Account ID mismatch!"
        echo "  .env configured:  $AWS_ACCOUNT_ID"
        echo "  Current account:  $current_account"
        echo ""
        echo "Please update AWS_ACCOUNT_ID in .env.shared file:"
        echo "  sed -i 's/AWS_ACCOUNT_ID=.*/AWS_ACCOUNT_ID=${current_account}/' ${SCRIPTS_ROOT}/.env.shared"
        echo ""
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 创建输出目录
# -----------------------------------------------------------------------------
ensure_output_dir() {
    local output_path="${SCRIPT_DIR}/${OUTPUT_DIR:-./output}"
    mkdir -p "$output_path"
    log_info "Output directory: $output_path"
}

# -----------------------------------------------------------------------------
# 团队/项目工具函数
# -----------------------------------------------------------------------------

# 获取团队全称
get_team_fullname() {
    local team=$1
    local var_name="TEAM_${team^^}_FULLNAME"
    echo "${!var_name}"
}

# 格式化名称 (risk-control -> RiskControl)
format_name() {
    local input="$1"
    local result=""
    IFS='-' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        result+="${part^}"  # Bash 4.x: 首字母大写
    done
    echo "$result"
}

# 获取项目列表
get_projects_for_team() {
    local team=$1
    local var_name="${team^^}_PROJECTS"
    echo "${!var_name}"
}

# 获取项目用户列表
get_users_for_project() {
    local team=$1
    local project=$2
    # 将 project-a 转换为 PROJECT_A
    local project_upper="${project^^}"
    project_upper="${project_upper//-/_}"
    local var_name="${team^^}_${project_upper}_USERS"
    echo "${!var_name}"
}

# -----------------------------------------------------------------------------
# S3 相关函数
# -----------------------------------------------------------------------------

# 生成 Bucket 名称
get_bucket_name() {
    local team=$1
    local project=$2
    echo "${COMPANY}-sm-${team}-${project}"
}

# 生成共享 Bucket 名称
get_shared_bucket_name() {
    echo "${COMPANY}-sm-shared-assets"
}

# -----------------------------------------------------------------------------
# IAM 相关函数
# -----------------------------------------------------------------------------

# 获取 IAM Path（带公司前缀）
get_iam_path() {
    echo "/${COMPANY}-sagemaker/"
}

# -----------------------------------------------------------------------------
# 打印配置摘要
# -----------------------------------------------------------------------------
print_config_summary() {
    local module_name="${1:-SageMaker}"
    
    echo ""
    echo "Configuration Summary:"
    echo "  Company:      $COMPANY"
    echo "  Account ID:   $AWS_ACCOUNT_ID"
    echo "  Region:       $AWS_REGION"
    
    # 打印额外的模块特有信息（如果提供了回调函数）
    if [[ -n "$2" ]] && declare -f "$2" > /dev/null; then
        "$2"
    fi
    
    echo ""
}

# -----------------------------------------------------------------------------
# 确认提示
# -----------------------------------------------------------------------------
confirm_action() {
    local message="${1:-Continue?}"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " response
        response=${response:-y}
    else
        read -p "$message [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

# -----------------------------------------------------------------------------
# 等待确认（用于危险操作）
# -----------------------------------------------------------------------------
confirm_dangerous_action() {
    local resource_type="${1:-resources}"
    local confirm_word="${2:-DELETE}"
    
    echo ""
    log_warn "⚠️  This will delete $resource_type!"
    echo ""
    read -p "Type '$confirm_word' to confirm: " response
    
    if [[ "$response" != "$confirm_word" ]]; then
        log_info "Cancelled."
        exit 0
    fi
}

