#!/bin/bash
# =============================================================================
# verify.sh - 验证 ECR 资源
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " Verifying ECR Resources"
echo "=============================================="
echo ""

ERRORS=0

# -----------------------------------------------------------------------------
# 检查仓库是否存在
# -----------------------------------------------------------------------------
check_repository() {
    local repo_name=$1
    
    if aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_success "Repository exists: $repo_name"
        
        # 检查 Lifecycle Policy
        if aws ecr get-lifecycle-policy \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" &> /dev/null; then
            log_success "  └─ Lifecycle policy configured"
        else
            log_warn "  └─ No lifecycle policy"
        fi
        
        # 获取镜像数量
        local image_count=$(aws ecr describe-images \
            --repository-name "$repo_name" \
            --region "$AWS_REGION" \
            --query 'length(imageDetails)' \
            --output text 2>/dev/null || echo "0")
        log_info "  └─ Images: $image_count"
        
        return 0
    else
        log_error "Repository not found: $repo_name"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 验证共享仓库
# -----------------------------------------------------------------------------
echo "Checking Shared Repositories..."
echo ""

for repo_type in $ECR_SHARED_REPOS; do
    repo_name=$(get_shared_repo_name "$repo_type")
    if ! check_repository "$repo_name"; then
        ((ERRORS++))
    fi
done

echo ""

# -----------------------------------------------------------------------------
# 验证项目仓库（如果启用）
# -----------------------------------------------------------------------------
if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" ]]; then
    echo "Checking Project Repositories..."
    echo ""
    
    for team in $TEAMS; do
        projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            for repo_type in $ECR_PROJECT_REPOS; do
                repo_name=$(get_project_repo_name "$team" "$project" "$repo_type")
                if ! check_repository "$repo_name"; then
                    ((ERRORS++))
                fi
            done
        done
    done
    
    echo ""
fi

# -----------------------------------------------------------------------------
# 验证 ECR 权限
# -----------------------------------------------------------------------------
echo "Checking ECR Permissions..."
echo ""

# 检查是否可以获取 authorization token
if aws ecr get-authorization-token --region "$AWS_REGION" &> /dev/null; then
    log_success "ECR authorization token obtainable"
else
    log_error "Cannot get ECR authorization token"
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
    log_success "All ECR resources verified successfully!"
    echo ""
    echo "  Registry: $(get_ecr_registry)"
    echo ""
    exit 0
else
    log_error "Verification failed with $ERRORS error(s)"
    echo ""
    echo "Please check the errors above and re-run the setup scripts."
    exit 1
fi

