#!/bin/bash
# =============================================================================
# 01-create-security-groups.sh - 创建 SageMaker 相关安全组
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
    
    log_info "Creating security group: $sg_name"
    
    # 检查是否已存在
    local existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    
    if [[ "$existing_sg" != "None" && -n "$existing_sg" ]]; then
        log_warn "Security group $sg_name already exists: $existing_sg"
        echo "$existing_sg"
        return 0
    fi
    
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$description" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${sg_name}},{Key=ManagedBy,Value=${TAG_PREFIX}}]" \
        --query 'GroupId' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Created security group: $sg_id"
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
            --region "$AWS_REGION" 2>/dev/null || log_warn "Rule may already exist"
    else
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --cidr "$source" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Rule may already exist"
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
            --region "$AWS_REGION" 2>/dev/null || log_warn "Rule may already exist"
    else
        aws ec2 authorize-security-group-egress \
            --group-id "$sg_id" \
            --protocol "$protocol" \
            --port "$port" \
            --cidr "$destination" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Rule may already exist"
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating Security Groups"
    echo "=============================================="
    echo ""
    
    # 1. 创建 SageMaker Studio 安全组
    log_info "Creating SageMaker Studio security group..."
    SG_STUDIO=$(create_security_group \
        "sg-${TAG_PREFIX}-studio" \
        "Security group for SageMaker Studio instances")
    
    if [[ -n "$SG_STUDIO" ]]; then
        # Studio 安全组入站规则
        add_ingress_rule "$SG_STUDIO" "-1" "-1" "self" "Allow all traffic from self"
        add_ingress_rule "$SG_STUDIO" "tcp" "443" "$VPC_CIDR" "Allow HTTPS from VPC"
        
        # Studio 安全组出站规则 (默认已有 allow all)
        add_egress_rule "$SG_STUDIO" "-1" "-1" "self" "Allow all traffic to self"
    fi
    
    # 2. 创建 VPC Endpoints 安全组
    log_info "Creating VPC Endpoints security group..."
    SG_ENDPOINTS=$(create_security_group \
        "sg-${TAG_PREFIX}-vpc-endpoints" \
        "Security group for VPC Endpoints")
    
    if [[ -n "$SG_ENDPOINTS" ]]; then
        # Endpoints 安全组入站规则
        add_ingress_rule "$SG_ENDPOINTS" "tcp" "443" "$VPC_CIDR" "Allow HTTPS from VPC"
    fi
    
    # 保存安全组 ID 到文件
    cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env" << EOF
# Security Group IDs - Generated $(date)
SG_SAGEMAKER_STUDIO=${SG_STUDIO}
SG_VPC_ENDPOINTS=${SG_ENDPOINTS}
EOF
    
    echo ""
    log_success "Security groups created successfully!"
    echo ""
    echo "Security Group Summary:"
    echo "  SageMaker Studio: $SG_STUDIO"
    echo "  VPC Endpoints:    $SG_ENDPOINTS"
    echo ""
    echo "IDs saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/security-groups.env"
}

main
