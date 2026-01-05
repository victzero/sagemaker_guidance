#!/bin/bash
# =============================================================================
# verify.sh - 验证 Model Registry 资源
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Verifying Model Registry Resources"
echo "=============================================="
echo ""

ERRORS=0

# -----------------------------------------------------------------------------
# 检查 Model Package Group 是否存在
# -----------------------------------------------------------------------------
check_model_group() {
    local group_name=$1
    
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "$group_name" \
        --region "$AWS_REGION" &> /dev/null; then
        
        # 获取模型版本数量
        local package_count=$(aws sagemaker list-model-packages \
            --model-package-group-name "$group_name" \
            --region "$AWS_REGION" \
            --query 'length(ModelPackageSummaryList)' \
            --output text 2>/dev/null || echo "0")
        
        log_success "Model Package Group exists: $group_name"
        log_info "  └─ Model versions: $package_count"
        
        return 0
    else
        log_error "Model Package Group not found: $group_name"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 验证所有 Model Package Groups
# -----------------------------------------------------------------------------
if [[ -z "$TEAMS" ]]; then
    log_warn "No teams configured. Skipping verification."
else
    for team in $TEAMS; do
        projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            group_name=$(get_model_group_name "$team" "$project")
            if ! check_model_group "$group_name"; then
                ((ERRORS++))
            fi
        done
    done
fi

# -----------------------------------------------------------------------------
# 验证 IAM 权限
# -----------------------------------------------------------------------------
echo ""
echo "Checking Model Registry Permissions..."
echo ""

# 检查是否可以列出 Model Package Groups
if aws sagemaker list-model-package-groups \
    --region "$AWS_REGION" \
    --max-results 1 &> /dev/null; then
    log_success "Can list Model Package Groups"
else
    log_error "Cannot list Model Package Groups - check IAM permissions"
    ((ERRORS++))
fi

# -----------------------------------------------------------------------------
# 结果汇总
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " Verification Summary"
echo "=============================================="
echo ""

if [[ $ERRORS -eq 0 ]]; then
    log_success "All Model Registry resources verified successfully!"
    echo ""
    exit 0
else
    log_error "Verification failed with $ERRORS error(s)"
    echo ""
    echo "Please check the errors above and re-run the setup scripts."
    exit 1
fi

