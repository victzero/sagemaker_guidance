#!/bin/bash
# =============================================================================
# 02-create-vpc-endpoints.sh - 创建 SageMaker 所需的 VPC Endpoints
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 加载安全组 ID
if [[ -f "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" ]]; then
    source "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
    log_info "Loaded security group IDs from previous step"
else
    log_error "Security groups not found. Please run 01-create-security-groups.sh first."
    exit 1
fi

# -----------------------------------------------------------------------------
# 创建 Interface Endpoint 函数
# -----------------------------------------------------------------------------
# 参数:
#   $1 - service_name: 服务名称 (如 sagemaker.api) 或完整服务名 (如 aws.sagemaker.xxx.studio)
#   $2 - endpoint_name: VPC Endpoint 名称
# -----------------------------------------------------------------------------
create_interface_endpoint() {
    local service_name=$1
    local endpoint_name=$2
    
    # 判断是否已经是完整服务名
    local full_service
    if [[ "$service_name" == com.amazonaws.* ]] || [[ "$service_name" == aws.sagemaker.* ]]; then
        full_service="$service_name"
    else
        full_service="com.amazonaws.${AWS_REGION}.${service_name}"
    fi
    
    log_info "Creating Interface Endpoint: $endpoint_name ($full_service)" >&2
    
    # 检查是否已存在（在当前 VPC 中）
    local existing=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${full_service}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    # 去除可能的空白字符
    existing=$(echo "$existing" | tr -d '[:space:]')
    
    if [[ "$existing" != "None" && -n "$existing" && "$existing" =~ ^vpce- ]]; then
        log_warn "Endpoint for $service_name already exists in VPC: $existing" >&2
        echo "$existing"
        return 0
    fi
    
    # 构建子网列表（支持 2-3 个子网）
    local subnet_ids="$PRIVATE_SUBNET_1_ID $PRIVATE_SUBNET_2_ID"
    if [[ -n "$PRIVATE_SUBNET_3_ID" ]]; then
        subnet_ids="$subnet_ids $PRIVATE_SUBNET_3_ID"
    fi
    
    local endpoint_id=$(aws ec2 create-vpc-endpoint \
        --vpc-id "$VPC_ID" \
        --vpc-endpoint-type Interface \
        --service-name "$full_service" \
        --subnet-ids $subnet_ids \
        --security-group-ids "$SG_VPC_ENDPOINTS" \
        --private-dns-enabled \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${endpoint_name}},{Key=ManagedBy,Value=${TAG_PREFIX}}]" \
        --query 'VpcEndpoint.VpcEndpointId' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Created endpoint: $endpoint_id" >&2
    echo "$endpoint_id"
}

# -----------------------------------------------------------------------------
# 创建 Gateway Endpoint 函数 (S3)
# -----------------------------------------------------------------------------
create_gateway_endpoint() {
    local service_name=$1
    local endpoint_name=$2
    
    local full_service="com.amazonaws.${AWS_REGION}.${service_name}"
    
    log_info "Creating Gateway Endpoint: $endpoint_name ($full_service)" >&2
    
    # 检查是否已存在（在当前 VPC 中）
    local existing=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=service-name,Values=${full_service}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    # 去除可能的空白字符
    existing=$(echo "$existing" | tr -d '[:space:]')
    
    if [[ "$existing" != "None" && -n "$existing" && "$existing" =~ ^vpce- ]]; then
        log_warn "Endpoint for $service_name already exists in VPC: $existing" >&2
        echo "$existing"
        return 0
    fi
    
    # Gateway Endpoint 需要指定路由表（支持 1-3 个）
    local route_tables="${ROUTE_TABLE_1_ID}"
    if [[ -n "$ROUTE_TABLE_2_ID" && "$ROUTE_TABLE_2_ID" != "$ROUTE_TABLE_1_ID" ]]; then
        route_tables="${route_tables} ${ROUTE_TABLE_2_ID}"
    fi
    if [[ -n "$ROUTE_TABLE_3_ID" && "$ROUTE_TABLE_3_ID" != "$ROUTE_TABLE_1_ID" && "$ROUTE_TABLE_3_ID" != "$ROUTE_TABLE_2_ID" ]]; then
        route_tables="${route_tables} ${ROUTE_TABLE_3_ID}"
    fi
    log_info "Using route tables: $route_tables" >&2
    
    local endpoint_id=$(aws ec2 create-vpc-endpoint \
        --vpc-id "$VPC_ID" \
        --vpc-endpoint-type Gateway \
        --service-name "$full_service" \
        --route-table-ids $route_tables \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=${endpoint_name}},{Key=ManagedBy,Value=${TAG_PREFIX}}]" \
        --query 'VpcEndpoint.VpcEndpointId' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Created gateway endpoint: $endpoint_id" >&2
    echo "$endpoint_id"
}

# -----------------------------------------------------------------------------
# 验证 Endpoint ID 格式
# -----------------------------------------------------------------------------
validate_endpoint_id() {
    local service=$1
    local endpoint_id=$2
    
    if [[ ! "$endpoint_id" =~ ^vpce- ]]; then
        log_error "Failed to create/get $service endpoint. Got: '$endpoint_id'" >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating VPC Endpoints"
    echo "=============================================="
    echo ""
    
    declare -A ENDPOINTS
    
    # ---------------------------------------------
    # 必需的 Endpoints
    # ---------------------------------------------
    log_info "Creating required endpoints..."
    
    # SageMaker API
    ENDPOINTS["sagemaker.api"]=$(create_interface_endpoint \
        "sagemaker.api" \
        "vpce-${TAG_PREFIX}-sagemaker-api")
    validate_endpoint_id "sagemaker.api" "${ENDPOINTS["sagemaker.api"]}"
    
    # SageMaker Runtime
    ENDPOINTS["sagemaker.runtime"]=$(create_interface_endpoint \
        "sagemaker.runtime" \
        "vpce-${TAG_PREFIX}-sagemaker-runtime")
    validate_endpoint_id "sagemaker.runtime" "${ENDPOINTS["sagemaker.runtime"]}"
    
    # SageMaker Studio (包含 Notebook 功能)
    # 注意: Studio 使用特殊的服务名格式: aws.sagemaker.{region}.studio
    ENDPOINTS["studio"]=$(create_interface_endpoint \
        "aws.sagemaker.${AWS_REGION}.studio" \
        "vpce-${TAG_PREFIX}-sagemaker-studio")
    validate_endpoint_id "studio" "${ENDPOINTS["studio"]}"
    
    # STS
    ENDPOINTS["sts"]=$(create_interface_endpoint \
        "sts" \
        "vpce-${TAG_PREFIX}-sts")
    validate_endpoint_id "sts" "${ENDPOINTS["sts"]}"
    
    # CloudWatch Logs
    ENDPOINTS["logs"]=$(create_interface_endpoint \
        "logs" \
        "vpce-${TAG_PREFIX}-logs")
    validate_endpoint_id "logs" "${ENDPOINTS["logs"]}"
    
    # S3 Gateway
    ENDPOINTS["s3"]=$(create_gateway_endpoint \
        "s3" \
        "vpce-${TAG_PREFIX}-s3")
    validate_endpoint_id "s3" "${ENDPOINTS["s3"]}"
    
    # ---------------------------------------------
    # 可选的 Endpoints
    # ---------------------------------------------
    
    if [[ "${CREATE_ECR_ENDPOINTS}" == "true" ]]; then
        log_info "Creating ECR endpoints..."
        
        ENDPOINTS["ecr.api"]=$(create_interface_endpoint \
            "ecr.api" \
            "vpce-${TAG_PREFIX}-ecr-api")
        
        ENDPOINTS["ecr.dkr"]=$(create_interface_endpoint \
            "ecr.dkr" \
            "vpce-${TAG_PREFIX}-ecr-dkr")
    fi
    
    if [[ "${CREATE_KMS_ENDPOINT}" == "true" ]]; then
        log_info "Creating KMS endpoint..."
        
        ENDPOINTS["kms"]=$(create_interface_endpoint \
            "kms" \
            "vpce-${TAG_PREFIX}-kms")
    fi
    
    if [[ "${CREATE_SSM_ENDPOINT}" == "true" ]]; then
        log_info "Creating SSM endpoint..."
        
        ENDPOINTS["ssm"]=$(create_interface_endpoint \
            "ssm" \
            "vpce-${TAG_PREFIX}-ssm")
    fi
    
    # 保存 Endpoint IDs 到文件
    cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/vpc-endpoints.env" << EOF
# VPC Endpoint IDs - Generated $(date)
VPCE_SAGEMAKER_API=${ENDPOINTS["sagemaker.api"]}
VPCE_SAGEMAKER_RUNTIME=${ENDPOINTS["sagemaker.runtime"]}
VPCE_SAGEMAKER_STUDIO=${ENDPOINTS["studio"]}
VPCE_STS=${ENDPOINTS["sts"]}
VPCE_LOGS=${ENDPOINTS["logs"]}
VPCE_S3=${ENDPOINTS["s3"]}
VPCE_ECR_API=${ENDPOINTS["ecr.api"]:-}
VPCE_ECR_DKR=${ENDPOINTS["ecr.dkr"]:-}
VPCE_KMS=${ENDPOINTS["kms"]:-}
VPCE_SSM=${ENDPOINTS["ssm"]:-}
EOF
    
    echo ""
    log_success "VPC Endpoints created successfully!"
    echo ""
    echo "Endpoint Summary:"
    echo "=================================="
    printf "  %-25s %s\n" "Service" "Endpoint ID"
    echo "----------------------------------"
    for service in "${!ENDPOINTS[@]}"; do
        printf "  %-25s %s\n" "$service" "${ENDPOINTS[$service]}"
    done
    echo ""
    echo "IDs saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/vpc-endpoints.env"
}

main
