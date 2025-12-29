#!/bin/bash
# =============================================================================
# 00-init.sh - 初始化和环境检查
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# 颜色输出
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# 加载环境变量
# -----------------------------------------------------------------------------
load_env() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading environment from .env"
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    else
        log_error ".env file not found!"
        log_info "Please copy .env.example to .env and edit it:"
        log_info "  cp .env.example .env"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 验证必需的环境变量
# -----------------------------------------------------------------------------
validate_env() {
    log_info "Validating environment variables..."
    
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
    
    log_success "Environment variables validated"
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
        log_warn "Current account ($current_account) differs from configured ($AWS_ACCOUNT_ID)"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Dry-run 包装器
# -----------------------------------------------------------------------------
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY-RUN] $*"
    else
        log_info "Executing: $*"
        "$@"
    fi
}

# -----------------------------------------------------------------------------
# 创建输出目录
# -----------------------------------------------------------------------------
ensure_output_dir() {
    mkdir -p "${SCRIPT_DIR}/${OUTPUT_DIR:-./output}"
}

# -----------------------------------------------------------------------------
# 获取团队全称
# -----------------------------------------------------------------------------
get_team_fullname() {
    local team=$1
    local var_name="TEAM_${team^^}_FULLNAME"
    echo "${!var_name}"
}

# -----------------------------------------------------------------------------
# 获取项目列表
# -----------------------------------------------------------------------------
get_projects_for_team() {
    local team=$1
    local var_name="${team^^}_PROJECTS"
    echo "${!var_name}"
}

# -----------------------------------------------------------------------------
# 获取项目用户列表
# -----------------------------------------------------------------------------
get_users_for_project() {
    local team=$1
    local project=$2
    # 将 project-a 转换为 PROJECT_A
    local project_upper=$(echo "$project" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    local var_name="${team^^}_${project_upper}_USERS"
    echo "${!var_name}"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker IAM Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_env
    check_aws_cli
    ensure_output_dir
    
    echo ""
    log_success "Initialization complete!"
    echo ""
    echo "Configuration Summary:"
    echo "  Company:     $COMPANY"
    echo "  Account ID:  $AWS_ACCOUNT_ID"
    echo "  Region:      $AWS_REGION"
    echo "  Dry-run:     ${DRY_RUN:-false}"
    echo ""
}

# 如果直接执行此脚本，运行初始化
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
