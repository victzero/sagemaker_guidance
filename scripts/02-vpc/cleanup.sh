#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 VPC 资源 (危险操作!)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: VPC Resource Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following resources:"
echo "  - VPC Endpoints created by this script"
echo "  - Security Groups created by this script"
echo ""

if [[ "$FORCE" != "true" ]]; then
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# 删除 VPC Endpoints
# -----------------------------------------------------------------------------
log_info "Step 1: Deleting VPC Endpoints..."

endpoints=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:ManagedBy,Values=${TAG_PREFIX}" \
    --query 'VpcEndpoints[].VpcEndpointId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

for endpoint_id in $endpoints; do
    log_info "Deleting endpoint: $endpoint_id"
    aws ec2 delete-vpc-endpoints \
        --vpc-endpoint-ids "$endpoint_id" \
        --region "$AWS_REGION"
    log_success "Deleted: $endpoint_id"
done

# -----------------------------------------------------------------------------
# 等待 Endpoints 完全删除
# -----------------------------------------------------------------------------
if [[ -n "$endpoints" ]]; then
    log_info "Waiting for endpoints to be fully deleted..."
    
    max_wait=60
    waited=0
    while [[ $waited -lt $max_wait ]]; do
        remaining=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:ManagedBy,Values=${TAG_PREFIX}" \
            --query 'VpcEndpoints[?State!=`deleted`].VpcEndpointId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -z "$remaining" ]]; then
            log_success "All endpoints deleted"
            break
        fi
        
        echo -n "."
        sleep 5
        ((waited+=5))
    done
    echo ""
    
    if [[ $waited -ge $max_wait ]]; then
        log_warn "Some endpoints may still be deleting, continuing anyway..."
    fi
fi

# -----------------------------------------------------------------------------
# 删除安全组
# -----------------------------------------------------------------------------
log_info "Step 2: Deleting Security Groups..."

security_groups=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:ManagedBy,Values=${TAG_PREFIX}" \
    --query 'SecurityGroups[].GroupId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

# 第一次尝试删除
for sg_id in $security_groups; do
    log_info "Deleting security group: $sg_id"
    if aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null; then
        log_success "Deleted: $sg_id"
    else
        log_warn "Could not delete $sg_id on first attempt, will retry..."
    fi
done

# 等待后重试未删除的
sleep 5
remaining_sgs=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:ManagedBy,Values=${TAG_PREFIX}" \
    --query 'SecurityGroups[].GroupId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

for sg_id in $remaining_sgs; do
    log_info "Retrying deletion of: $sg_id"
    if aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null; then
        log_success "Deleted: $sg_id"
    else
        log_warn "Could not delete $sg_id (may still have dependencies from other resources)"
    fi
done

echo ""
log_success "Cleanup complete!"
