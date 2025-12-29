#!/bin/bash
# =============================================================================
# 00-init.sh - VPC 脚本初始化和工具函数
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
# 验证必需的环境变量
# -----------------------------------------------------------------------------
validate_env() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "COMPANY"
        "AWS_ACCOUNT_ID"
        "AWS_REGION"
        "VPC_ID"
        "VPC_CIDR"
        "PRIVATE_SUBNET_1_ID"
        "PRIVATE_SUBNET_2_ID"
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
    
    # 检查是否在 AWS CloudShell 中运行
    if [[ -n "$CLOUD_SHELL" ]]; then
        log_info "Running in AWS CloudShell"
        # 在 CloudShell 中，不需要设置 AWS_PROFILE，使用内置凭证
        unset AWS_PROFILE
    elif [[ -n "$AWS_PROFILE" ]]; then
        export AWS_PROFILE
        log_info "Using AWS Profile: $AWS_PROFILE"
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured or no valid credentials."
        log_info "Please run 'aws configure' first."
        exit 1
    fi
    
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_success "AWS CLI configured. Current identity: $identity"
    
    # 验证 AWS_ACCOUNT_ID 是否匹配
    local current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "Configured AWS_ACCOUNT_ID ($AWS_ACCOUNT_ID) in .env does not match current AWS CLI account ($current_account)."
        log_error "Please update .env: sed -i 's/AWS_ACCOUNT_ID=.*/AWS_ACCOUNT_ID=${current_account}/' .env"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 验证 VPC 存在
# -----------------------------------------------------------------------------
validate_vpc() {
    log_info "Validating VPC: $VPC_ID"
    
    if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" &> /dev/null; then
        log_error "VPC $VPC_ID not found in region $AWS_REGION"
        exit 1
    fi
    
    # 检查 DNS 设置
    local dns_hostnames=$(aws ec2 describe-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --attribute enableDnsHostnames \
        --query 'EnableDnsHostnames.Value' \
        --output text \
        --region "$AWS_REGION")
    
    local dns_support=$(aws ec2 describe-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --attribute enableDnsSupport \
        --query 'EnableDnsSupport.Value' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ "$dns_hostnames" != "True" ]]; then
        log_warn "VPC DNS Hostnames is not enabled. SageMaker VPCOnly mode requires this."
    fi
    
    if [[ "$dns_support" != "True" ]]; then
        log_warn "VPC DNS Support is not enabled. SageMaker VPCOnly mode requires this."
    fi
    
    log_success "VPC $VPC_ID validated"
}

# -----------------------------------------------------------------------------
# 验证子网存在
# -----------------------------------------------------------------------------
validate_subnets() {
    log_info "Validating subnets..."
    
    for subnet_id in "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID"; do
        if ! aws ec2 describe-subnets --subnet-ids "$subnet_id" --region "$AWS_REGION" &> /dev/null; then
            log_error "Subnet $subnet_id not found"
            exit 1
        fi
    done
    
    log_success "Subnets validated"
}

# -----------------------------------------------------------------------------
# 创建输出目录
# -----------------------------------------------------------------------------
ensure_output_dir() {
    mkdir -p "${SCRIPT_DIR}/${OUTPUT_DIR:-./output}"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker VPC Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_env
    check_aws_cli
    validate_vpc
    validate_subnets
    ensure_output_dir
    
    echo ""
    log_success "Initialization complete!"
    echo ""
    echo "Configuration Summary:"
    echo "  Company:     $COMPANY"
    echo "  Region:      $AWS_REGION"
    echo "  VPC ID:      $VPC_ID"
    echo "  VPC CIDR:    $VPC_CIDR"
    echo "  Subnet 1:    $PRIVATE_SUBNET_1_ID"
    echo "  Subnet 2:    $PRIVATE_SUBNET_2_ID"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
