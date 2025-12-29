#!/bin/bash
# =============================================================================
# verify.sh - 验证 S3 配置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " S3 Configuration Verification"
echo "=============================================="
echo ""

errors=0

verify_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

# -----------------------------------------------------------------------------
# 验证 Bucket
# -----------------------------------------------------------------------------
verify_bucket() {
    local bucket_name=$1
    
    if aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $bucket_name exists"
        
        # 检查版本控制
        local versioning=$(aws s3api get-bucket-versioning \
            --bucket "$bucket_name" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$versioning" == "Enabled" ]]; then
            echo -e "    ${GREEN}✓${NC} Versioning: Enabled"
        else
            echo -e "    ${YELLOW}!${NC} Versioning: $versioning"
        fi
        
        # 检查加密
        local encryption=$(aws s3api get-bucket-encryption \
            --bucket "$bucket_name" \
            --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$encryption" != "None" ]]; then
            echo -e "    ${GREEN}✓${NC} Encryption: $encryption"
        else
            echo -e "    ${RED}✗${NC} Encryption: Not configured"
            ((errors++))
        fi
        
        # 检查公开访问阻止
        local public_block=$(aws s3api get-public-access-block \
            --bucket "$bucket_name" \
            --query 'PublicAccessBlockConfiguration.BlockPublicAcls' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$public_block" == "True" ]]; then
            echo -e "    ${GREEN}✓${NC} Public Access: Blocked"
        else
            echo -e "    ${YELLOW}!${NC} Public Access: May be accessible"
        fi
        
        # 检查 Bucket Policy
        if aws s3api get-bucket-policy --bucket "$bucket_name" --region "$AWS_REGION" &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} Bucket Policy: Configured"
        else
            echo -e "    ${YELLOW}!${NC} Bucket Policy: Not configured"
        fi
        
        # 检查生命周期规则
        if aws s3api get-bucket-lifecycle-configuration --bucket "$bucket_name" --region "$AWS_REGION" &>/dev/null; then
            echo -e "    ${GREEN}✓${NC} Lifecycle Rules: Configured"
        else
            echo -e "    ${YELLOW}!${NC} Lifecycle Rules: Not configured"
        fi
        
        return 0
    else
        echo -e "  ${RED}✗${NC} $bucket_name: NOT FOUND"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    verify_section "Project Buckets"
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local bucket_name=$(get_bucket_name "$team" "$project")
            verify_bucket "$bucket_name" || ((errors++))
        done
    done
    
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        verify_section "Shared Bucket"
        local shared_bucket=$(get_shared_bucket_name)
        verify_bucket "$shared_bucket" || ((errors++))
    fi
    
    # 总结
    echo ""
    echo "=============================================="
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}Verification PASSED${NC} - All S3 buckets configured correctly"
    else
        echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
    fi
    echo "=============================================="
    
    exit $errors
}

main
