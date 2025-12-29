#!/bin/bash
# =============================================================================
# 00-init.sh - S3 脚本初始化和工具函数
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
# 验证环境变量
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
        log_error "AWS CLI not found."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured."
        exit 1
    fi
    
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_success "AWS CLI configured: $identity"
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
# 工具函数
# -----------------------------------------------------------------------------
ensure_output_dir() {
    mkdir -p "${SCRIPT_DIR}/${OUTPUT_DIR:-./output}"
}

get_team_fullname() {
    local team=$1
    local var_name="TEAM_${team^^}_FULLNAME"
    echo "${!var_name}"
}

get_projects_for_team() {
    local team=$1
    local var_name="${team^^}_PROJECTS"
    echo "${!var_name}"
}

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
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker S3 Setup - Initialization"
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
    echo "  Region:      $AWS_REGION"
    echo "  Encryption:  ${ENCRYPTION_TYPE:-SSE-S3}"
    echo "  Versioning:  ${ENABLE_VERSIONING:-true}"
    echo "  Dry-run:     ${DRY_RUN:-false}"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
