#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 Model Registry 资源
# =============================================================================
# ⚠️  警告: 此操作会删除所有 Model Package Groups 和模型版本!
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Model Registry Cleanup"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 删除 Model Package Group 函数
# -----------------------------------------------------------------------------
delete_model_group() {
    local group_name=$1
    
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "$group_name" \
        --region "$AWS_REGION" &> /dev/null; then
        
        log_info "Deleting Model Package Group: $group_name"
        
        # 首先删除所有模型版本
        local packages=$(aws sagemaker list-model-packages \
            --model-package-group-name "$group_name" \
            --region "$AWS_REGION" \
            --query 'ModelPackageSummaryList[].ModelPackageArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$packages" && "$packages" != "None" ]]; then
            for package_arn in $packages; do
                log_info "  Deleting model version: $package_arn"
                aws sagemaker delete-model-package \
                    --model-package-name "$package_arn" \
                    --region "$AWS_REGION" 2>/dev/null || true
            done
        fi
        
        # 删除 Group
        aws sagemaker delete-model-package-group \
            --model-package-group-name "$group_name" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        log_success "Deleted: $group_name"
    else
        log_info "Model Package Group not found (skipping): $group_name"
    fi
}

# -----------------------------------------------------------------------------
# 危险操作确认
# -----------------------------------------------------------------------------
echo "⚠️  This will delete the following Model Package Groups:"
echo ""

if [[ -n "$TEAMS" ]]; then
    for team in $TEAMS; do
        projects=$(get_projects_for_team "$team")
        for project in $projects; do
            echo "  - $(get_model_group_name "$team" "$project")"
        done
    done
else
    echo "  (No teams configured - scanning for existing groups)"
    
    # 列出所有由此工具创建的 Groups
    existing_groups=$(aws sagemaker list-model-package-groups \
        --region "$AWS_REGION" \
        --query "ModelPackageGroupSummaryList[?contains(ModelPackageGroupName, '-')].ModelPackageGroupName" \
        --output text 2>/dev/null || echo "")
    
    for group in $existing_groups; do
        echo "  - $group"
    done
fi

echo ""
echo "⚠️  All model versions in these groups will be PERMANENTLY DELETED!"
echo ""

confirm_dangerous_action "Model Package Groups and all model versions" "DELETE"

# -----------------------------------------------------------------------------
# 删除 Model Package Groups
# -----------------------------------------------------------------------------
echo ""
log_step "Deleting Model Package Groups..."

if [[ -n "$TEAMS" ]]; then
    for team in $TEAMS; do
        projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            delete_model_group "$(get_model_group_name "$team" "$project")"
        done
    done
fi

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/${OUTPUT_DIR}/model-groups.env" ]]; then
    rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/model-groups.env"
    log_info "Removed output file: model-groups.env"
fi

# -----------------------------------------------------------------------------
# 完成
# -----------------------------------------------------------------------------
echo ""
log_success "Model Registry cleanup completed!"
echo ""

