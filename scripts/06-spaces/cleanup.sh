#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 Shared Spaces (危险操作!)
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
echo " WARNING: Shared Spaces Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following Shared Spaces:"
echo "  - All spaces created by this script"
echo "  - All data in Space EBS volumes"
echo ""
echo "Domain ID: $DOMAIN_ID"
echo ""

# 列出将要删除的 Spaces
space_count=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        space_name="space-${team}-${project}"
        echo "  - $space_name"
        ((space_count++)) || true
    done
done

echo ""
echo "Total: $space_count spaces"
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
# 删除所有 Space Apps
# -----------------------------------------------------------------------------
log_info "Step 1: Deleting all Apps in Spaces..."

for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        space_name="space-${team}-${project}"
        
        # 检查 Space 是否存在
        if ! aws sagemaker describe-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --region "$AWS_REGION" &> /dev/null; then
            continue
        fi
        
        # 获取并删除所有 Apps
        apps=$(aws sagemaker list-apps \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --query 'Apps[?Status!=`Deleted`].[AppType,AppName]' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        while IFS=$'\t' read -r app_type app_name; do
            [[ -z "$app_name" ]] && continue
            log_info "Deleting App: $space_name/$app_type/$app_name"
            aws sagemaker delete-app \
                --domain-id "$DOMAIN_ID" \
                --space-name "$space_name" \
                --app-type "$app_type" \
                --app-name "$app_name" \
                --region "$AWS_REGION" 2>/dev/null || true
        done <<< "$apps"
    done
done

# 等待 Apps 删除
log_info "Waiting for Apps to be deleted..."
sleep 20

# -----------------------------------------------------------------------------
# 删除 Shared Spaces
# -----------------------------------------------------------------------------
log_info "Step 2: Deleting Shared Spaces..."

deleted=0
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        space_name="space-${team}-${project}"
        
        # 检查 Space 是否存在
        if ! aws sagemaker describe-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --region "$AWS_REGION" &> /dev/null; then
            log_info "Space not found, skipping: $space_name"
            continue
        fi
        
        log_info "Deleting Space: $space_name"
        aws sagemaker delete-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete $space_name"
        
        ((deleted++)) || true
        sleep 2
    done
done

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
log_info "Step 3: Cleaning up output files..."
rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/spaces.csv" 2>/dev/null || true

echo ""
log_success "Cleanup complete!"
echo ""
echo "Deleted: $deleted spaces"
echo ""
echo "Note: EBS volumes will be deleted with the Spaces."

