#!/bin/bash
# =============================================================================
# 01-create-policies.sh - 创建 IAM Policies
# =============================================================================
# 使用方法: ./01-create-policies.sh [--force]
#
# 策略模板文件位于 policies/ 目录，与脚本逻辑分离
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 解析参数
FORCE_UPDATE=false
if [[ "$1" == "--force" ]]; then
    FORCE_UPDATE=true
    log_info "Force update mode enabled"
fi

# 策略模板目录
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# -----------------------------------------------------------------------------
# 模板渲染函数
# -----------------------------------------------------------------------------

# 渲染模板文件，替换变量
# 用法: render_template <template_file> [VAR1=value1 VAR2=value2 ...]
render_template() {
    local template_file=$1
    shift
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        exit 1
    fi
    
    # 读取模板内容
    local content=$(cat "$template_file")
    
    # 替换通用变量
    content=$(echo "$content" | sed \
        -e "s|\${AWS_REGION}|${AWS_REGION}|g" \
        -e "s|\${AWS_ACCOUNT_ID}|${AWS_ACCOUNT_ID}|g" \
        -e "s|\${COMPANY}|${COMPANY}|g" \
        -e "s|\${IAM_PATH}|${IAM_PATH}|g")
    
    # 替换额外传入的变量
    for var in "$@"; do
        local key="${var%%=*}"
        local value="${var#*=}"
        content=$(echo "$content" | sed "s|\${${key}}|${value}|g")
    done
    
    echo "$content"
}

# -----------------------------------------------------------------------------
# Policy 生成函数 (使用模板)
# -----------------------------------------------------------------------------

generate_base_access_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/base-access.json.tpl"
}

generate_team_access_policy() {
    local team=$1
    render_template "${POLICY_TEMPLATES_DIR}/team-access.json.tpl" "TEAM=${team}"
}

generate_project_access_policy() {
    local team=$1
    local project=$2
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/project-access.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
}

generate_execution_role_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/execution-role.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_execution_role_jobs_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/execution-role-jobs.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_training_role_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/training-role.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_training_role_ops_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/training-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_processing_role_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/processing-role.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_processing_role_ops_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/processing-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_inference_role_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/inference-role.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_inference_role_ops_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/inference-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_user_boundary_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/user-boundary.json.tpl"
}

generate_readonly_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/readonly.json.tpl"
}

generate_self_service_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/self-service.json.tpl"
}

generate_studio_app_permissions_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/studio-app-permissions.json.tpl"
}

generate_mlflow_app_access_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/mlflow-app-access.json.tpl"
}

# -----------------------------------------------------------------------------
# 创建策略函数
# -----------------------------------------------------------------------------
create_policy() {
    local policy_name=$1
    local policy_document=$2
    local description=$3
    
    local policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/policy-${policy_name}.json"
    echo "$policy_document" > "$policy_file"
    
    log_info "Creating policy: $policy_name"
    
    # 检查策略是否已存在
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" &> /dev/null; then
        if [[ "$FORCE_UPDATE" == "true" ]]; then
            log_warn "Policy $policy_name already exists, updating..."
            
            # 获取当前版本数量
            local versions=$(aws iam list-policy-versions \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
            
            # 如果版本数达到5个，删除最旧的非默认版本
            local version_count=$(echo "$versions" | wc -w)
            if [[ $version_count -ge 4 ]]; then
                local oldest_version=$(aws iam list-policy-versions \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                    --query 'Versions[?IsDefaultVersion==`false`] | sort_by(@, &CreateDate)[0].VersionId' --output text)
                
                aws iam delete-policy-version \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                    --version-id "$oldest_version"
            fi
            
            aws iam create-policy-version \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                --policy-document "file://${policy_file}" \
                --set-as-default
            log_success "Policy $policy_name updated"
        else
            log_warn "Policy $policy_name already exists, skipping... (use --force to update)"
        fi
    else
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "${IAM_PATH}" \
            --policy-document "file://${policy_file}" \
            --description "${description:-SageMaker IAM Policy}"
        log_success "Policy $policy_name created"
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Policies"
    echo "=============================================="
    echo ""
    
    # 检查模板目录
    if [[ ! -d "$POLICY_TEMPLATES_DIR" ]]; then
        log_error "Policy templates directory not found: $POLICY_TEMPLATES_DIR"
        exit 1
    fi
    log_info "Using policy templates from: $POLICY_TEMPLATES_DIR"
    echo ""
    
    # 1. 创建基础策略
    log_info "Creating base access policy..."
    create_policy "SageMaker-Studio-Base-Access" \
        "$(generate_base_access_policy)" \
        "Base access policy for all SageMaker Studio users"
    
    # 2. 创建只读策略
    log_info "Creating readonly policy..."
    create_policy "SageMaker-ReadOnly-Access" \
        "$(generate_readonly_policy)" \
        "Read-only access for SageMaker resources"
    
    # 3. 创建 Permissions Boundary
    log_info "Creating permissions boundary..."
    create_policy "SageMaker-User-Boundary" \
        "$(generate_user_boundary_policy)" \
        "Permissions boundary for SageMaker users"
    
    # 4. 创建用户自助服务策略 (改密码、MFA)
    log_info "Creating self-service policy..."
    create_policy "SageMaker-User-SelfService" \
        "$(generate_self_service_policy)" \
        "Self-service policy for password and MFA management"
    
    # 5. 创建 Studio App 权限策略 (安全必须，始终创建)
    log_info "Creating Studio App permissions policy..."
    create_policy "SageMaker-StudioAppPermissions" \
        "$(generate_studio_app_permissions_policy)" \
        "Studio App permissions with user profile isolation"
    
    # 6. 创建 MLflow 访问策略 (实验追踪)
    log_info "Creating MLflow App access policy..."
    create_policy "SageMaker-MLflowAppAccess" \
        "$(generate_mlflow_app_access_policy)" \
        "MLflow App access for experiment tracking"
    
    # 8. 创建团队策略
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        log_info "Creating team policy for: $team ($team_fullname)"
        
        # 格式化名称 (risk-control -> RiskControl)
        local team_capitalized=$(format_name "$team_fullname")
        
        create_policy "SageMaker-${team_capitalized}-Team-Access" \
            "$(generate_team_access_policy "$team")" \
            "Team access policy for ${team_fullname} team"
    done
    
    # 9. 创建项目策略
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            log_info "Creating project policy for: $team / $project"
            
            # 格式化名称 (project-a -> ProjectA)
            local project_formatted=$(format_name "$project")
            local team_fullname=$(get_team_fullname "$team")
            local team_capitalized=$(format_name "$team_fullname")
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-Access" \
                "$(generate_project_access_policy "$team" "$project")" \
                "Project access policy for ${team}/${project}"
            
            # 创建 Execution Role 策略（拆分为基础+作业）
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy" \
                "$(generate_execution_role_policy "$team" "$project")" \
                "Execution role base policy for ${team}/${project}"
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-ExecutionJobPolicy" \
                "$(generate_execution_role_jobs_policy "$team" "$project")" \
                "Execution role jobs policy for ${team}/${project}"
            
            # 创建 Training Role 策略（拆分为基础+操作）
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-TrainingPolicy" \
                "$(generate_training_role_policy "$team" "$project")" \
                "Training role base policy for ${team}/${project}"
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-TrainingOpsPolicy" \
                "$(generate_training_role_ops_policy "$team" "$project")" \
                "Training role ops policy for ${team}/${project}"
            
            # 创建 Processing Role 策略（拆分为基础+操作）
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-ProcessingPolicy" \
                "$(generate_processing_role_policy "$team" "$project")" \
                "Processing role base policy for ${team}/${project}"
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-ProcessingOpsPolicy" \
                "$(generate_processing_role_ops_policy "$team" "$project")" \
                "Processing role ops policy for ${team}/${project}"
            
            # 创建 Inference Role 策略（拆分为基础+操作）
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-InferencePolicy" \
                "$(generate_inference_role_policy "$team" "$project")" \
                "Inference role base policy for ${team}/${project}"
            
            create_policy "SageMaker-${team_capitalized}-${project_formatted}-InferenceOpsPolicy" \
                "$(generate_inference_role_ops_policy "$team" "$project")" \
                "Inference role ops policy for ${team}/${project}"
        done
    done
    
    echo ""
    log_success "All policies created successfully!"
    echo ""
    echo "Policy JSON files saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/"
    echo "Policy templates located at: ${POLICY_TEMPLATES_DIR}/"
}

main
