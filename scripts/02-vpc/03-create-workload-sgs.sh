#!/bin/bash
# =============================================================================
# 03-create-workload-sgs.sh - 创建工作负载安全组
# =============================================================================
# Phase 2A: 为 Processing/Training/Inference 创建专用安全组
#
# 创建的安全组:
# - {TAG_PREFIX}-training      Training Jobs (分布式训练)
# - {TAG_PREFIX}-processing    Processing Jobs (Spark 集群)
# - {TAG_PREFIX}-inference     Inference Endpoints (推理服务)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 创建安全组函数
# -----------------------------------------------------------------------------
create_security_group() {
    local sg_name=$1
    local description=$2
    
    log_info "Creating security group: $sg_name" >&2
    
    # 检查是否已存在
    local existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$existing_sg" != "None" && -n "$existing_sg" ]]; then
        log_warn "Security group $sg_name already exists: $existing_sg" >&2
        echo "$existing_sg"
        return 0
    fi
    
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$description" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${sg_name}},{Key=ManagedBy,Value=${TAG_PREFIX}},{Key=Phase,Value=2A}]" \
        --query 'GroupId' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Created security group: $sg_id" >&2
    echo "$sg_id"
}

# -----------------------------------------------------------------------------
# 添加入站规则
# -----------------------------------------------------------------------------
add_ingress_rule() {
    local sg_id=$1
    local protocol=$2
    local port=$3
    local source=$4
    local description=$5
    
    log_info "Adding ingress rule: $protocol:$port from $source"
    
    # 检查是否是自引用
    if [[ "$source" == "self" ]]; then
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --source-group "$sg_id" \
            --region "$AWS_REGION" > /dev/null 2>&1 || log_warn "Rule may already exist"
    else
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --cidr "$source" \
            --region "$AWS_REGION" > /dev/null 2>&1 || log_warn "Rule may already exist"
    fi
}

# -----------------------------------------------------------------------------
# 添加出站规则
# -----------------------------------------------------------------------------
add_egress_rule() {
    local sg_id=$1
    local protocol=$2
    local port=$3
    local destination=$4
    local description=$5
    
    log_info "Adding egress rule: $protocol:$port to $destination"
    
    if [[ "$destination" == "self" ]]; then
        aws ec2 authorize-security-group-egress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --source-group "$sg_id" \
            --region "$AWS_REGION" > /dev/null 2>&1 || log_warn "Rule may already exist"
    else
        aws ec2 authorize-security-group-egress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --cidr "$destination" \
            --region "$AWS_REGION" > /dev/null 2>&1 || log_warn "Rule may already exist"
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating Workload Security Groups (Phase 2A)"
    echo "=============================================="
    echo ""
    echo "VPC ID: $VPC_ID"
    echo "VPC CIDR: $VPC_CIDR"
    echo ""
    
    # =========================================================================
    # 1. Training Jobs 安全组
    # =========================================================================
    log_info "Creating Training Jobs security group..."
    SG_TRAINING=$(create_security_group \
        "${TAG_PREFIX}-training" \
        "Security group for SageMaker Training Jobs (distributed training)")
    
    if [[ ! "$SG_TRAINING" =~ ^sg- ]]; then
        log_error "Failed to create/get Training security group. Got: '$SG_TRAINING'"
        exit 1
    fi
    
    # Training 入站规则
    add_ingress_rule "$SG_TRAINING" "-1" "-1" "self" "Allow all traffic from self (distributed training)"
    add_ingress_rule "$SG_TRAINING" "tcp" "443" "$VPC_CIDR" "Allow HTTPS from VPC"
    
    # Training 出站规则
    add_egress_rule "$SG_TRAINING" "-1" "-1" "self" "Allow all traffic to self (distributed training)"
    # 默认出站已有 allow all to 0.0.0.0/0
    
    log_success "Training SG created: $SG_TRAINING"
    
    # =========================================================================
    # 2. Processing Jobs 安全组
    # =========================================================================
    log_info "Creating Processing Jobs security group..."
    SG_PROCESSING=$(create_security_group \
        "${TAG_PREFIX}-processing" \
        "Security group for SageMaker Processing Jobs (Spark cluster)")
    
    if [[ ! "$SG_PROCESSING" =~ ^sg- ]]; then
        log_error "Failed to create/get Processing security group. Got: '$SG_PROCESSING'"
        exit 1
    fi
    
    # Processing 入站规则
    add_ingress_rule "$SG_PROCESSING" "-1" "-1" "self" "Allow all traffic from self (Spark cluster)"
    add_ingress_rule "$SG_PROCESSING" "tcp" "443" "$VPC_CIDR" "Allow HTTPS from VPC"
    
    # Processing 出站规则
    add_egress_rule "$SG_PROCESSING" "-1" "-1" "self" "Allow all traffic to self (Spark cluster)"
    
    log_success "Processing SG created: $SG_PROCESSING"
    
    # =========================================================================
    # 3. Inference Endpoints 安全组
    # =========================================================================
    log_info "Creating Inference Endpoints security group..."
    SG_INFERENCE=$(create_security_group \
        "${TAG_PREFIX}-inference" \
        "Security group for SageMaker Inference Endpoints")
    
    if [[ ! "$SG_INFERENCE" =~ ^sg- ]]; then
        log_error "Failed to create/get Inference security group. Got: '$SG_INFERENCE'"
        exit 1
    fi
    
    # Inference 入站规则
    add_ingress_rule "$SG_INFERENCE" "tcp" "443" "$VPC_CIDR" "Allow HTTPS from VPC (inference requests)"
    add_ingress_rule "$SG_INFERENCE" "tcp" "8080" "$VPC_CIDR" "Allow container port from VPC"
    
    # Inference 出站规则 - 默认已有 allow all
    
    log_success "Inference SG created: $SG_INFERENCE"
    
    # =========================================================================
    # 保存结果
    # =========================================================================
    
    # 追加到现有的 security-groups.env
    if [[ -f "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" ]]; then
        # 检查是否已有 workload SG
        if grep -q "SG_TRAINING" "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"; then
            log_info "Updating workload SG IDs in security-groups.env..."
            # macOS 兼容的 sed
            sed -i '' '/^SG_TRAINING=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" 2>/dev/null || \
            sed -i '/^SG_TRAINING=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
            sed -i '' '/^SG_PROCESSING=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" 2>/dev/null || \
            sed -i '/^SG_PROCESSING=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
            sed -i '' '/^SG_INFERENCE=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" 2>/dev/null || \
            sed -i '/^SG_INFERENCE=/d' "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
        fi
        
        cat >> "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" << EOF

# Workload Security Groups (Phase 2A) - Added $(date)
SG_TRAINING=${SG_TRAINING}
SG_PROCESSING=${SG_PROCESSING}
SG_INFERENCE=${SG_INFERENCE}
EOF
    else
        # 创建新文件
        cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" << EOF
# Security Group IDs - Generated $(date)

# Phase 1 Security Groups
# (Run 01-create-security-groups.sh to populate)

# Workload Security Groups (Phase 2A)
SG_TRAINING=${SG_TRAINING}
SG_PROCESSING=${SG_PROCESSING}
SG_INFERENCE=${SG_INFERENCE}
EOF
    fi
    
    echo ""
    log_success "Workload Security Groups created successfully!"
    echo ""
    echo "=============================================="
    echo " Summary"
    echo "=============================================="
    echo ""
    echo "  Training Jobs:      $SG_TRAINING"
    echo "  Processing Jobs:    $SG_PROCESSING"
    echo "  Inference Endpoints: $SG_INFERENCE"
    echo ""
    echo "IDs saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 使用示例:"
    echo ""
    echo "  # Processing Job"
    echo "  network_config = NetworkConfig("
    echo "      security_group_ids=['$SG_PROCESSING'],"
    echo "      subnets=[...]"
    echo "  )"
    echo ""
    echo "  # Training Job"
    echo "  estimator = Estimator("
    echo "      ...,"
    echo "      security_group_ids=['$SG_TRAINING']"
    echo "  )"
    echo ""
    echo "  # Inference Endpoint"
    echo "  model.deploy("
    echo "      ...,"
    echo "      vpc_config={'SecurityGroupIds': ['$SG_INFERENCE'], ...}"
    echo "  )"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main

