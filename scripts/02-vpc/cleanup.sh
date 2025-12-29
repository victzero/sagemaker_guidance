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
    run_cmd aws ec2 delete-vpc-endpoints \
        --vpc-endpoint-ids "$endpoint_id" \
        --region "$AWS_REGION"
    log_success "Deleted: $endpoint_id"
done

# -----------------------------------------------------------------------------
# 删除安全组
# -----------------------------------------------------------------------------
log_info "Step 2: Deleting Security Groups..."

# 等待 Endpoints 完全删除
log_info "Waiting for endpoints to be fully deleted..."
sleep 10

security_groups=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:ManagedBy,Values=${TAG_PREFIX}" \
    --query 'SecurityGroups[].GroupId' \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

for sg_id in $security_groups; do
    log_info "Deleting security group: $sg_id"
    run_cmd aws ec2 delete-security-group \
        --group-id "$sg_id" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete $sg_id (may have dependencies)"
done

echo ""
log_success "Cleanup complete!"
