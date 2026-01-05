#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 ECR 资源
# =============================================================================
# ⚠️  警告: 此操作会删除所有 ECR 仓库和镜像!
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " ECR Cleanup"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 删除仓库函数
# -----------------------------------------------------------------------------
delete_repository() {
    local repo_name=$1
    
    if aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$AWS_REGION" &> /dev/null; then
        
        log_info "Deleting repository: $repo_name"
        
        # 需要 --force 才能删除包含镜像的仓库
        aws ecr delete-repository \
            --repository-name "$repo_name" \
            --force \
            --region "$AWS_REGION" > /dev/null
        
        log_success "Deleted: $repo_name"
    else
        log_info "Repository not found (skipping): $repo_name"
    fi
}

# -----------------------------------------------------------------------------
# 危险操作确认
# -----------------------------------------------------------------------------
echo "⚠️  This will delete the following ECR repositories:"
echo ""

# 列出将被删除的仓库
for repo_type in $ECR_SHARED_REPOS; do
    echo "  - $(get_shared_repo_name "$repo_type")"
done

if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" ]]; then
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            for repo_type in $ECR_PROJECT_REPOS; do
                echo "  - $(get_project_repo_name "$team" "$project" "$repo_type")"
            done
        done
    done
fi

echo ""
echo "⚠️  All images in these repositories will be PERMANENTLY DELETED!"
echo ""

confirm_dangerous_action "ECR repositories and all images" "DELETE"

# -----------------------------------------------------------------------------
# 删除共享仓库
# -----------------------------------------------------------------------------
echo ""
log_step "Deleting shared repositories..."

for repo_type in $ECR_SHARED_REPOS; do
    delete_repository "$(get_shared_repo_name "$repo_type")"
done

# -----------------------------------------------------------------------------
# 删除项目仓库
# -----------------------------------------------------------------------------
if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" ]]; then
    echo ""
    log_step "Deleting project repositories..."
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            for repo_type in $ECR_PROJECT_REPOS; do
                delete_repository "$(get_project_repo_name "$team" "$project" "$repo_type")"
            done
        done
    done
fi

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/${OUTPUT_DIR}/repositories.env" ]]; then
    rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/repositories.env"
    log_info "Removed output file: repositories.env"
fi

# -----------------------------------------------------------------------------
# 完成
# -----------------------------------------------------------------------------
echo ""
log_success "ECR cleanup completed!"
echo ""

