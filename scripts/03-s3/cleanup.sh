#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 S3 Buckets (危险操作!)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 加载删除函数库 (统一实现，避免代码重复)
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"

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
# 注意: 删除函数已移至 lib/s3-factory.sh 统一维护
# 可用函数: delete_bucket, empty_bucket
# -----------------------------------------------------------------------------

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
