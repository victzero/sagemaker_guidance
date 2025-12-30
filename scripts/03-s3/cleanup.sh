#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 S3 Buckets (危险操作!)
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
echo " WARNING: S3 Bucket Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following buckets and ALL their contents:"

# 列出将要删除的 Buckets
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        echo "  - $(get_bucket_name "$team" "$project")"
    done
done

if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  - $(get_shared_bucket_name)"
fi

echo ""

if [[ "$FORCE" != "true" ]]; then
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE! ALL DATA WILL BE LOST!${NC}"
    echo ""
    read -p "Type 'DELETE ALL' to confirm: " -r
    if [[ "$REPLY" != "DELETE ALL" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# 删除 Bucket 函数
# -----------------------------------------------------------------------------
delete_bucket() {
    local bucket_name=$1
    
    log_info "Deleting bucket: $bucket_name"
    
    if ! aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
        log_warn "Bucket $bucket_name does not exist, skipping..."
        return 0
    fi
    
    # 删除所有对象 (包括版本)
    log_info "Deleting all objects in $bucket_name..."
    aws s3 rm "s3://${bucket_name}" --recursive --region "$AWS_REGION" 2>/dev/null || true
    
    # 删除所有版本
    log_info "Deleting all object versions..."
    aws s3api list-object-versions --bucket "$bucket_name" --region "$AWS_REGION" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
        jq -c '.[]' 2>/dev/null | while read -r obj; do
            key=$(echo "$obj" | jq -r '.Key')
            version=$(echo "$obj" | jq -r '.VersionId')
            aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version" \
                --region "$AWS_REGION" 2>/dev/null || true
        done
    
    # 删除所有删除标记
    log_info "Deleting all delete markers..."
    aws s3api list-object-versions --bucket "$bucket_name" --region "$AWS_REGION" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null | \
        jq -c '.[]' 2>/dev/null | while read -r obj; do
            key=$(echo "$obj" | jq -r '.Key')
            version=$(echo "$obj" | jq -r '.VersionId')
            aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version" \
                --region "$AWS_REGION" 2>/dev/null || true
        done
    
    # 删除 Bucket
    log_info "Deleting bucket..."
    aws s3api delete-bucket --bucket "$bucket_name" --region "$AWS_REGION"
    
    log_success "Bucket $bucket_name deleted"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    log_info "Starting cleanup..."
    
    # 删除项目 Buckets
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            delete_bucket "$(get_bucket_name "$team" "$project")"
        done
    done
    
    # 删除共享 Bucket
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        delete_bucket "$(get_shared_bucket_name)"
    fi
    
    echo ""
    log_success "Cleanup complete!"
}

main
