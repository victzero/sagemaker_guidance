#!/bin/bash
# =============================================================================
# 01-create-model-groups.sh - 创建 Model Package Groups
# =============================================================================
# 为每个项目创建 Model Package Group，用于模型版本管理
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 创建 Model Package Group
# -----------------------------------------------------------------------------
create_model_group() {
    local team=$1
    local project=$2
    local group_name=$(get_model_group_name "$team" "$project")
    local team_fullname=$(get_team_fullname "$team")
    
    log_info "Creating Model Package Group: $group_name"
    
    # 检查是否已存在
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "$group_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Model Package Group $group_name already exists"
        return 0
    fi
    
    # 创建 Model Package Group
    aws sagemaker create-model-package-group \
        --model-package-group-name "$group_name" \
        --model-package-group-description "Models for ${team_fullname}/${project}" \
        --tags "Key=ManagedBy,Value=${TAG_PREFIX}" \
               "Key=Team,Value=${team}" \
               "Key=Project,Value=${project}" \
               "Key=Phase,Value=2C" \
        --region "$AWS_REGION" > /dev/null
    
    log_success "Created Model Package Group: $group_name"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    if [[ "$ENABLE_MODEL_REGISTRY" != "true" ]]; then
        log_warn "Model Registry module is disabled. Skipping."
        exit 0
    fi
    
    if [[ -z "$TEAMS" ]]; then
        log_warn "No teams configured. Skipping Model Package Group creation."
        exit 0
    fi
    
    echo ""
    echo "=============================================="
    echo " Creating Model Package Groups"
    echo "=============================================="
    echo ""
    
    local created_groups=()
    
    # =========================================================================
    # 为每个项目创建 Model Package Group
    # =========================================================================
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local projects=$(get_projects_for_team "$team")
        
        if [[ -z "$projects" ]]; then
            log_warn "No projects configured for team: $team"
            continue
        fi
        
        log_step "Processing team: $team ($team_fullname)"
        
        for project in $projects; do
            create_model_group "$team" "$project"
            created_groups+=("$(get_model_group_name "$team" "$project")")
        done
        
        echo ""
    done
    
    # =========================================================================
    # 保存结果
    # =========================================================================
    local output_file="${SCRIPT_DIR}/${OUTPUT_DIR}/model-groups.env"
    mkdir -p "${SCRIPT_DIR}/${OUTPUT_DIR}"
    
    cat > "$output_file" << EOF
# Model Package Groups - Generated $(date)

# Total Groups: ${#created_groups[@]}
MODEL_GROUPS="${created_groups[*]}"

# Individual Group Names
EOF
    
    for group in "${created_groups[@]}"; do
        echo "# - $group" >> "$output_file"
    done
    
    # =========================================================================
    # 输出总结
    # =========================================================================
    echo ""
    log_success "Model Package Groups created successfully!"
    echo ""
    echo "=============================================="
    echo " Summary"
    echo "=============================================="
    echo ""
    echo "  Total Groups Created: ${#created_groups[@]}"
    echo ""
    echo "  Model Package Groups:"
    for group in "${created_groups[@]}"; do
        echo "    - $group"
    done
    echo ""
    echo "  Output saved to: $output_file"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 使用示例:"
    echo ""
    echo "  # 注册模型版本"
    echo "  from sagemaker.model import ModelPackage"
    echo ""
    echo "  model_package = ModelPackage("
    echo "      role=execution_role,"
    echo "      model_package_group_name='${created_groups[0]:-team-project}',"
    echo "      model_data='s3://bucket/model.tar.gz',"
    echo "      image_uri='123456789012.dkr.ecr.region.amazonaws.com/image:tag',"
    echo "      content_types=['application/json'],"
    echo "      response_types=['application/json'],"
    echo "  )"
    echo ""
    echo "  # 列出模型版本"
    echo "  aws sagemaker list-model-packages \\"
    echo "      --model-package-group-name '${created_groups[0]:-team-project}' \\"
    echo "      --region $AWS_REGION"
    echo ""
    echo "  # 批准/拒绝模型版本"
    echo "  aws sagemaker update-model-package \\"
    echo "      --model-package-arn 'arn:aws:sagemaker:...:model-package/group/version' \\"
    echo "      --model-approval-status 'Approved'"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main

