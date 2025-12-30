#!/bin/bash
# =============================================================================
# 00-init.sh - VPC 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# VPC 特有验证
# -----------------------------------------------------------------------------
validate_vpc_env() {
    log_info "Validating VPC environment variables..."
    
    local required_vars=(
        "VPC_ID"
        "VPC_CIDR"
        "PRIVATE_SUBNET_1_ID"
        "PRIVATE_SUBNET_2_ID"
        "ROUTE_TABLE_1_ID"
    )
    
    local missing=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing+=("$var")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required VPC environment variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        log_info "Please configure these in .env.local"
        log_info "See .env.local.example for reference"
        exit 1
    fi
    
    log_success "VPC environment variables validated"
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
# VPC 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_vpc_summary() {
    echo "  VPC ID:       $VPC_ID"
    echo "  VPC CIDR:     $VPC_CIDR"
    echo "  Subnet 1:     $PRIVATE_SUBNET_1_ID"
    echo "  Subnet 2:     $PRIVATE_SUBNET_2_ID"
    echo "  Route Table 1: $ROUTE_TABLE_1_ID"
    if [[ -n "$ROUTE_TABLE_2_ID" ]]; then
        echo "  Route Table 2: $ROUTE_TABLE_2_ID"
    fi
    if [[ -n "$ROUTE_TABLE_3_ID" ]]; then
        echo "  Route Table 3: $ROUTE_TABLE_3_ID"
    fi
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker VPC Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_vpc_env
    check_aws_cli
    validate_vpc
    validate_subnets
    ensure_output_dir
    
    # 设置默认 TAG_PREFIX（如果未由父脚本设置）
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    
    print_config_summary "VPC" print_vpc_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi
