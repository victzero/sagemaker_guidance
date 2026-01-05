#!/bin/bash
# =============================================================================
# 01-create-repositories.sh - 创建 ECR 仓库
# =============================================================================
# 创建共享仓库和项目级仓库
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 创建 ECR 仓库
# -----------------------------------------------------------------------------
create_repository() {
    local repo_name=$1
    local description=$2
    
    log_info "Creating ECR repository: $repo_name"
    
    # 检查是否已存在
    if aws ecr describe-repositories \
        --repository-names "$repo_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Repository $repo_name already exists"
        return 0
    fi
    
    # 创建仓库
    aws ecr create-repository \
        --repository-name "$repo_name" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --image-tag-mutability MUTABLE \
        --tags "Key=ManagedBy,Value=${TAG_PREFIX}" "Key=Phase,Value=2B" \
        --region "$AWS_REGION" > /dev/null
    
    log_success "Created repository: $repo_name"
}

# -----------------------------------------------------------------------------
# 配置仓库 Lifecycle Policy
# -----------------------------------------------------------------------------
configure_lifecycle_policy() {
    local repo_name=$1
    local retention=${2:-$ECR_IMAGE_RETENTION}
    
    log_info "Configuring lifecycle policy for: $repo_name (retain: $retention)"
    
    local policy=$(cat << EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last $retention images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": $retention
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
)
    
    aws ecr put-lifecycle-policy \
        --repository-name "$repo_name" \
        --lifecycle-policy-text "$policy" \
        --region "$AWS_REGION" > /dev/null
    
    log_success "Lifecycle policy configured for: $repo_name"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    if [[ "$ENABLE_ECR" != "true" ]]; then
        log_warn "ECR module is disabled. Skipping."
        exit 0
    fi
    
    echo ""
    echo "=============================================="
    echo " Creating ECR Repositories"
    echo "=============================================="
    echo ""
    
    local created_repos=()
    
    # =========================================================================
    # 1. 创建共享仓库
    # =========================================================================
    if [[ -n "$ECR_SHARED_REPOS" ]]; then
        log_step "Creating shared repositories..."
        
        for repo_type in $ECR_SHARED_REPOS; do
            local repo_name=$(get_shared_repo_name "$repo_type")
            create_repository "$repo_name" "Shared $repo_type base image"
            configure_lifecycle_policy "$repo_name"
            created_repos+=("$repo_name")
        done
        
        echo ""
    fi
    
    # =========================================================================
    # 2. 创建项目级仓库（可选）
    # =========================================================================
    if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" && -n "$ECR_PROJECT_REPOS" ]]; then
        log_step "Creating project repositories..."
        
        for team in $TEAMS; do
            local projects=$(get_projects_for_team "$team")
            
            for project in $projects; do
                for repo_type in $ECR_PROJECT_REPOS; do
                    local repo_name=$(get_project_repo_name "$team" "$project" "$repo_type")
                    create_repository "$repo_name" "Project $team/$project $repo_type"
                    configure_lifecycle_policy "$repo_name"
                    created_repos+=("$repo_name")
                done
            done
        done
        
        echo ""
    fi
    
    # =========================================================================
    # 保存仓库列表
    # =========================================================================
    local output_file="${SCRIPT_DIR}/${OUTPUT_DIR}/repositories.env"
    mkdir -p "${SCRIPT_DIR}/${OUTPUT_DIR}"
    
    cat > "$output_file" << EOF
# ECR Repositories - Generated $(date)
# Registry: $(get_ecr_registry)

# Shared Repositories
ECR_SHARED_REPOS="${ECR_SHARED_REPOS}"

# Project Repositories (if enabled)
ECR_PROJECT_REPOS="${ECR_PROJECT_REPOS}"
ECR_CREATE_PROJECT_REPOS="${ECR_CREATE_PROJECT_REPOS}"

# Image Retention
ECR_IMAGE_RETENTION="${ECR_IMAGE_RETENTION}"
EOF
    
    # =========================================================================
    # 输出总结
    # =========================================================================
    echo ""
    log_success "ECR Repositories created successfully!"
    echo ""
    echo "=============================================="
    echo " Summary"
    echo "=============================================="
    echo ""
    echo "  Registry:    $(get_ecr_registry)"
    echo "  Total Repos: ${#created_repos[@]}"
    echo ""
    echo "  Shared Repositories:"
    for repo_type in $ECR_SHARED_REPOS; do
        local repo_name=$(get_shared_repo_name "$repo_type")
        echo "    - $repo_name"
    done
    echo ""
    
    if [[ "$ECR_CREATE_PROJECT_REPOS" == "true" ]]; then
        echo "  Project Repositories: Created for each team/project"
    else
        echo "  Project Repositories: Not enabled (set ECR_CREATE_PROJECT_REPOS=true)"
    fi
    
    echo ""
    echo "  Output saved to: $output_file"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 使用示例:"
    echo ""
    echo "  # 登录 ECR"
    echo "  aws ecr get-login-password --region $AWS_REGION | \\"
    echo "      docker login --username AWS --password-stdin $(get_ecr_registry)"
    echo ""
    echo "  # 推送镜像"
    echo "  docker tag my-image:latest $(get_ecr_registry)/$(get_shared_repo_name "base-sklearn"):latest"
    echo "  docker push $(get_ecr_registry)/$(get_shared_repo_name "base-sklearn"):latest"
    echo ""
    echo "  # 在 SageMaker 中使用"
    echo "  image_uri = '$(get_ecr_registry)/$(get_shared_repo_name "base-sklearn"):latest'"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main

