#!/bin/bash
# =============================================================================
# 00-init.sh - SageMaker Domain 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# Domain 特有验证
# -----------------------------------------------------------------------------
validate_domain_env() {
    log_info "Validating SageMaker Domain environment variables..."
    
    local required_vars=(
        "VPC_ID"
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
        log_info "Please configure these in .env.shared or .env.local"
        exit 1
    fi
    
    log_success "Domain environment variables validated"
}

# -----------------------------------------------------------------------------
# 验证 VPC Endpoints 已创建
# -----------------------------------------------------------------------------
validate_vpc_endpoints() {
    log_info "Validating VPC Endpoints..."
    
    local required_services=(
        "com.amazonaws.${AWS_REGION}.sagemaker.api"
        "com.amazonaws.${AWS_REGION}.sagemaker.runtime"
        "aws.sagemaker.${AWS_REGION}.studio"
        "com.amazonaws.${AWS_REGION}.sts"
        "com.amazonaws.${AWS_REGION}.s3"
    )
    
    local missing=()
    for service in "${required_services[@]}"; do
        local endpoint_id=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=service-name,Values=${service}" "Name=vpc-id,Values=${VPC_ID}" \
            --query 'VpcEndpoints[0].VpcEndpointId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$endpoint_id" == "None" || -z "$endpoint_id" ]]; then
            missing+=("$service")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required VPC Endpoints:"
        for service in "${missing[@]}"; do
            echo "  - $service"
        done
        log_info "Please run scripts/02-vpc/setup-all.sh first"
        exit 1
    fi
    
    log_success "VPC Endpoints validated"
}

# -----------------------------------------------------------------------------
# 验证安全组已创建
# -----------------------------------------------------------------------------
validate_security_group() {
    log_info "Validating SageMaker Studio security group..."
    
    local sg_name="${TAG_PREFIX:-${COMPANY}-sagemaker}-studio"
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$sg_id" == "None" || -z "$sg_id" ]]; then
        log_error "Security group ${sg_name} not found"
        log_info "Please run scripts/02-vpc/setup-all.sh first"
        exit 1
    fi
    
    # 导出供其他脚本使用
    export SG_SAGEMAKER_STUDIO="$sg_id"
    log_success "Security group validated: $sg_id"
}

# -----------------------------------------------------------------------------
# Domain 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_domain_summary() {
    echo "  VPC ID:       $VPC_ID"
    echo "  Subnet 1:     $PRIVATE_SUBNET_1_ID"
    echo "  Subnet 2:     $PRIVATE_SUBNET_2_ID"
    echo "  Security Group: ${SG_SAGEMAKER_STUDIO:-pending}"
    echo "  Domain Name:  ${DOMAIN_NAME:-${COMPANY}-ml-platform}"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " SageMaker Domain Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_domain_env
    check_aws_cli
    
    # 设置默认 TAG_PREFIX
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    
    validate_security_group
    validate_vpc_endpoints
    ensure_output_dir
    
    # 设置 Domain 特有配置
    export DOMAIN_NAME="${DOMAIN_NAME:-${COMPANY}-ml-platform}"
    export IDLE_TIMEOUT_MINUTES="${IDLE_TIMEOUT_MINUTES:-60}"
    export LIFECYCLE_CONFIG_NAME="${LIFECYCLE_CONFIG_NAME:-auto-shutdown-${IDLE_TIMEOUT_MINUTES}min}"
    export DEFAULT_INSTANCE_TYPE="${DEFAULT_INSTANCE_TYPE:-ml.t3.medium}"
    export DEFAULT_EBS_SIZE_GB="${DEFAULT_EBS_SIZE_GB:-100}"
    
    print_config_summary "SageMaker Domain" print_domain_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

