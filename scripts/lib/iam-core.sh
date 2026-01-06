#!/bin/bash
# =============================================================================
# lib/iam-core.sh - IAM 核心函数库
# =============================================================================
# 从 01-iam 模块提取的核心函数，确保行为完全一致
# 供 01-iam 和 08-operations 等模块复用
#
# 依赖:
#   - common.sh (已加载)
#   - 环境变量: AWS_REGION, AWS_ACCOUNT_ID, COMPANY, IAM_PATH
#   - 变量: POLICY_TEMPLATES_DIR, OUTPUT_DIR (调用方设置)
# =============================================================================

# 防止重复加载
if [[ -n "$_LIB_IAM_CORE_LOADED" ]]; then
    return 0
fi
_LIB_IAM_CORE_LOADED=1

# =============================================================================
# 模板渲染函数
# =============================================================================

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

# 公共模板片段目录（由调用方设置 POLICY_TEMPLATES_DIR）
# COMMON_FRAGMENTS_DIR="${POLICY_TEMPLATES_DIR}/common"

# 渲染公共片段，替换变量
# 用法: render_fragment <fragment_name> [VAR1=value1 VAR2=value2 ...]
render_fragment() {
    local fragment_name=$1
    shift
    local common_fragments_dir="${POLICY_TEMPLATES_DIR}/common"
    local fragment_file="${common_fragments_dir}/${fragment_name}.json.tpl"
    
    if [[ ! -f "$fragment_file" ]]; then
        log_error "Fragment file not found: $fragment_file"
        exit 1
    fi
    
    local content=$(cat "$fragment_file")
    
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

# 构建策略：基础模板 + 公共片段
# 用法: build_policy_with_fragments <base_template> <fragments_json_array> [VAR=value ...]
# fragments_json_array 格式: '["fragment1", "fragment2"]'
build_policy_with_fragments() {
    local base_template=$1
    local fragments=$2
    shift 2
    
    # 渲染基础模板
    local base_content=$(render_template "$base_template" "$@")
    
    # 如果没有片段，直接返回
    if [[ "$fragments" == "[]" || -z "$fragments" ]]; then
        echo "$base_content"
        return
    fi
    
    # 解析片段列表并渲染
    local fragment_statements=""
    for fragment in $(echo "$fragments" | tr -d '[]"' | tr ',' ' '); do
        local frag_content=$(render_fragment "$fragment" "$@")
        if [[ -n "$fragment_statements" ]]; then
            fragment_statements="${fragment_statements},
    ${frag_content}"
        else
            fragment_statements="    ${frag_content}"
        fi
    done
    
    # 将片段插入到基础模板的 Statement 数组末尾
    # 找到最后一个 } ] } 模式，在 ] 之前插入片段
    local result=$(echo "$base_content" | sed '$d')  # 移除最后一行 }
    result=$(echo "$result" | sed '$d')              # 移除倒数第二行 ]
    
    # 检查最后一个 statement 是否需要加逗号
    local last_line=$(echo "$result" | tail -1)
    if [[ "$last_line" =~ ^[[:space:]]*\} ]]; then
        result=$(echo "$result" | sed '$ s/}$/},/')
    fi
    
    echo "$result"
    echo "$fragment_statements"
    echo "  ]"
    echo "}"
}

# =============================================================================
# Policy 生成函数 (使用模板)
# =============================================================================

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

# =============================================================================
# 共享策略生成函数 (User 和 Role 共用)
# =============================================================================

generate_shared_s3_access_policy() {
    local team=$1
    local project=$2
    render_template "${POLICY_TEMPLATES_DIR}/shared-s3-access.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}"
}

generate_shared_passrole_policy() {
    local team=$1
    local project=$2
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/shared-passrole.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
}

generate_shared_deny_admin_policy() {
    render_template "${POLICY_TEMPLATES_DIR}/shared-deny-admin.json.tpl"
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
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/execution-role-jobs.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
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
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/training-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
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
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/processing-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
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
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    render_template "${POLICY_TEMPLATES_DIR}/inference-role-ops.json.tpl" \
        "TEAM=${team}" "PROJECT=${project}" \
        "TEAM_FULLNAME=${team_capitalized}" "PROJECT_FULLNAME=${project_formatted}"
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

# =============================================================================
# 策略创建函数
# =============================================================================

# 创建或更新策略（带详细日志）
# 用法: create_policy <policy_name> <policy_document> [description]
# 依赖: FORCE_UPDATE 变量控制是否强制更新
create_policy() {
    local policy_name=$1
    local policy_document=$2
    local description=$3
    
    # 保存策略到文件（供调试）
    if [[ -n "$OUTPUT_DIR" ]]; then
        local policy_file="${SCRIPT_DIR}/${OUTPUT_DIR}/policy-${policy_name}.json"
        echo "$policy_document" > "$policy_file"
    fi
    
    log_info "Creating policy: $policy_name"
    
    # 检查策略是否已存在
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" &> /dev/null; then
        if [[ "$FORCE_UPDATE" == "true" ]]; then
            log_warn "Policy $policy_name already exists, updating..."
            
            # 创建新版本
            aws iam create-policy-version \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}" \
                --policy-document "$policy_document" \
                --set-as-default
            
            log_success "Policy $policy_name updated"
        else
            log_warn "Policy $policy_name already exists, skipping (use --force to update)"
        fi
    else
        # 创建新策略
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "${IAM_PATH}" \
            --policy-document "$policy_document" \
            ${description:+--description "$description"}
        
        log_success "Policy $policy_name created"
    fi
}

# 简化版创建或更新策略（静默模式，供 08-operations 使用）
# 用法: create_or_update_policy <policy_name> <policy_document>
create_or_update_policy() {
    local policy_name=$1
    local policy_document=$2
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_info "Updating policy: $policy_name"
        aws iam create-policy-version \
            --policy-arn "$policy_arn" \
            --policy-document "$policy_document" \
            --set-as-default > /dev/null
        log_success "Policy updated: $policy_name"
    else
        log_info "Creating policy: $policy_name"
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "${IAM_PATH}" \
            --policy-document "$policy_document" > /dev/null
        log_success "Policy created: $policy_name"
    fi
}

# =============================================================================
# Trust Policy
# =============================================================================

# 获取 Trust Policy 文件路径
# 用法: get_trust_policy_file
# 返回: Trust Policy 文件的完整路径
get_trust_policy_file() {
    local trust_policy_file="${POLICY_TEMPLATES_DIR}/trust-policy-sagemaker.json"
    
    if [[ ! -f "$trust_policy_file" ]]; then
        log_error "Trust policy template not found: $trust_policy_file"
        exit 1
    fi
    
    # 如果有 OUTPUT_DIR，复制到该目录
    if [[ -n "$OUTPUT_DIR" && -n "$SCRIPT_DIR" ]]; then
        cp "$trust_policy_file" "${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
        echo "${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
    else
        echo "$trust_policy_file"
    fi
}

# =============================================================================
# 策略附加函数
# =============================================================================

# 通用策略附加函数
# 用法: attach_policy_to_role <role_name> <policy_name> <policy_arn>
attach_policy_to_role() {
    local role_name=$1
    local policy_name=$2
    local policy_arn=$3
    
    # 检查是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy $policy_name already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        log_success "Policy $policy_name attached to $role_name"
    fi
}

# 附加 Canvas 相关策略
# Canvas 是 SageMaker 的低代码 ML 平台
# 用法: attach_canvas_policies <role_name>
attach_canvas_policies() {
    local role_name=$1
    
    if [[ "$ENABLE_CANVAS" != "true" ]]; then
        log_info "Canvas policies skipped (ENABLE_CANVAS=$ENABLE_CANVAS)"
        return 0
    fi
    
    log_info "Attaching Canvas policies to $role_name..."
    
    # Canvas 托管策略（根路径）
    local canvas_managed_policies=(
        "AmazonSageMakerCanvasFullAccess"
        "AmazonSageMakerCanvasAIServicesAccess"
        "AmazonSageMakerCanvasDataPrepFullAccess"
    )
    
    for policy in "${canvas_managed_policies[@]}"; do
        local policy_arn="arn:aws:iam::aws:policy/${policy}"
        local attached=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query "AttachedPolicies[?PolicyName=='${policy}'].PolicyName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -z "$attached" ]]; then
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn"
            log_success "  $policy attached"
        fi
    done
    
    # Canvas 服务角色策略（service-role/ 路径）
    local canvas_deploy_policy="AmazonSageMakerCanvasDirectDeployAccess"
    local canvas_deploy_arn="arn:aws:iam::aws:policy/service-role/${canvas_deploy_policy}"
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${canvas_deploy_policy}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$attached" ]]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$canvas_deploy_arn"
        log_success "  $canvas_deploy_policy attached"
    fi
}

# 附加 Studio App 权限策略
# 用法: attach_studio_app_permissions <role_name>
attach_studio_app_permissions() {
    local role_name=$1
    local policy_name="${STUDIO_APP_POLICY_NAME:-SageMaker-StudioAppPermissions}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 检查策略是否存在
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "StudioAppPermissions policy not found, skipping..."
        return 0
    fi
    
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$attached" ]]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        log_success "  $policy_name attached"
    fi
}

# 附加 MLflow App 访问策略
# 用法: attach_mlflow_app_access <role_name>
attach_mlflow_app_access() {
    local role_name=$1
    
    if [[ "$ENABLE_MLFLOW" != "true" ]]; then
        log_info "MLflow policy skipped (ENABLE_MLFLOW=$ENABLE_MLFLOW)"
        return 0
    fi
    
    local policy_name="${MLFLOW_APP_POLICY_NAME:-SageMaker-MLflowAppAccess}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 检查策略是否存在
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "MLflowAppAccess policy not found, skipping..."
        return 0
    fi
    
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$attached" ]]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        log_success "  $policy_name attached"
    fi
}

# =============================================================================
# Role 创建函数
# =============================================================================

# 创建 Domain 默认 Execution Role
# 用法: create_domain_default_role
create_domain_default_role() {
    local role_name="SageMaker-Domain-DefaultExecutionRole"
    
    log_info "Creating Domain default execution role: $role_name"
    
    # 获取 trust policy 文件
    local trust_policy_file=$(get_trust_policy_file)
    
    # 显示 Trust Policy 内容
    echo ""
    log_info "Trust Policy (for SageMaker service):"
    cat "$trust_policy_file" | head -20
    echo ""
    
    # 检查 Role 是否已存在
    # 注意: Execution Role 不使用 IAM_PATH，便于 SageMaker 服务引用
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        # 确保 trust policy 正确
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "Default execution role for SageMaker Domain" \
            --tags \
                "Key=Purpose,Value=DomainDefault" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # 附加 AmazonSageMakerFullAccess 托管策略（Domain 默认必须有）
    log_info "Attaching AmazonSageMakerFullAccess to domain default role..."
    
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "AmazonSageMakerFullAccess already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        log_success "AmazonSageMakerFullAccess attached to $role_name"
    fi
    
    # 附加 Canvas 相关策略（如果启用）
    attach_canvas_policies "$role_name"
    
    # 附加 Studio App 权限策略（安全必须）
    attach_studio_app_permissions "$role_name"
    
    # 附加 MLflow App 访问策略（如果启用）
    attach_mlflow_app_access "$role_name"
    
    # 输出 Role ARN 供后续使用
    echo ""
    log_info "Domain Default Execution Role ARN:"
    aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text
    
    # 显示权限说明
    echo ""
    echo "Domain Default Role Permissions:"
    echo "  ✓ AmazonSageMakerFullAccess (AWS managed)"
    echo "    - SageMaker full access"
    echo "    - Processing / Training / Inference jobs"
    echo "    - Model registry, experiments, pipelines"
    if [[ "$ENABLE_CANVAS" == "true" ]]; then
        echo "  ✓ Canvas policies (AWS managed)"
        echo "    - SageMaker Canvas low-code ML platform"
        echo "    - AI services (Bedrock, Textract, etc.)"
        echo "    - Data preparation (Data Wrangler, Glue)"
    fi
    echo "  ✓ Studio App Permissions (custom)"
    echo "    - User profile isolation"
    echo "    - Private/Shared space management"
    if [[ "$ENABLE_MLFLOW" == "true" ]]; then
        echo "  ✓ MLflow App Access (custom)"
        echo "    - Experiment tracking"
        echo "    - Model registry integration"
    fi
    echo ""
    echo "  Note: This role does NOT include project-specific S3 permissions."
    echo "  User Profiles should use project-specific Execution Roles."
}

# 创建项目 Execution Role
# 用法: create_execution_role <team> <project>
create_execution_role() {
    local team=$1
    local project=$2
    
    # 格式化名称 (risk-control -> RiskControl, project-a -> ProjectA)
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy"
    local job_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionJobPolicy"
    
    log_info "Creating execution role: $role_name"
    
    # 获取 trust policy 文件
    local trust_policy_file=$(get_trust_policy_file)
    
    # 检查 Role 是否已存在
    # 注意: Execution Role 不使用 IAM_PATH，便于 SageMaker 服务引用
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        # 确保 trust policy 正确
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "SageMaker Execution Role for ${team_fullname}/${project}" \
            --tags \
                "Key=Team,Value=${team_fullname}" \
                "Key=Project,Value=${project}" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 第一步: 附加 AmazonSageMakerFullAccess (必须先附加)
    # ========================================
    log_info "Step 1: Attaching AmazonSageMakerFullAccess to role (required for ML Jobs)..."
    
    local sm_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sm_attached" ]]; then
        log_warn "AmazonSageMakerFullAccess already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
        
        log_success "AmazonSageMakerFullAccess attached to $role_name"
    fi
    
    # ========================================
    # 第二步: 附加 Canvas 相关策略 (如果启用)
    # ========================================
    log_info "Step 2: Attaching Canvas policies (if enabled)..."
    attach_canvas_policies "$role_name"
    
    # ========================================
    # 第三步: 附加 Studio App 权限策略 (安全必须)
    # ========================================
    log_info "Step 3: Attaching Studio App permissions (security required)..."
    attach_studio_app_permissions "$role_name"
    
    # ========================================
    # 第四步: 附加 MLflow App 访问策略 (如果启用)
    # ========================================
    log_info "Step 4: Attaching MLflow App access (if enabled)..."
    attach_mlflow_app_access "$role_name"
    
    # ========================================
    # 第五步: 附加共享策略 (User 和 Role 都使用)
    # ========================================
    log_info "Step 5: Attaching shared policies..."
    
    # 共享 Deny Admin 策略
    local deny_admin_policy="SageMaker-Shared-DenyAdmin"
    attach_policy_to_role "$role_name" "$deny_admin_policy" "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${deny_admin_policy}"
    
    # 共享 S3 访问策略
    local s3_policy_name="SageMaker-${team_capitalized}-${project_formatted}-S3Access"
    attach_policy_to_role "$role_name" "$s3_policy_name" "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${s3_policy_name}"
    
    # ========================================
    # 第六步: 附加项目自定义策略 (ECR、CloudWatch、VPC 等)
    # ========================================
    log_info "Step 6: Attaching project-specific policies to role..."
    
    # 附加基础策略 (ECR、CloudWatch、VPC、AI Assistant)
    attach_policy_to_role "$role_name" "$policy_name" "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 附加作业提交策略 (PassRole、Training/Processing/Inference)
    attach_policy_to_role "$role_name" "$job_policy_name" "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${job_policy_name}"
    
    # 显示权限总结
    echo ""
    log_info "Role $role_name permissions:"
    echo "  ✓ AmazonSageMakerFullAccess (AWS managed)"
    if [[ "$ENABLE_CANVAS" == "true" ]]; then
        echo "  ✓ Canvas policies (AWS managed - low-code ML)"
    fi
    echo "  ✓ Studio App Permissions (user isolation)"
    if [[ "$ENABLE_MLFLOW" == "true" ]]; then
        echo "  ✓ MLflow App Access (experiment tracking)"
    fi
    echo "  ✓ SageMaker-Shared-DenyAdmin (shared - security restriction)"
    echo "  ✓ SageMaker-*-S3Access (shared - project S3 access)"
    echo "  ✓ $policy_name (custom - ECR, CloudWatch, VPC, AI Assistant)"
    echo "  ✓ $job_policy_name (custom - PassRole, Jobs, Model Registry)"
}

# 创建 Training 专用 Role
# 用法: create_training_role <team> <project>
create_training_role() {
    local team=$1
    local project=$2
    
    if [[ "$ENABLE_TRAINING_ROLE" != "true" ]]; then
        log_info "Training role skipped (ENABLE_TRAINING_ROLE=$ENABLE_TRAINING_ROLE)"
        return 0
    fi
    
    # 格式化名称
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingPolicy"
    local ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingOpsPolicy"
    
    log_info "Creating training role: $role_name"
    
    # 获取 trust policy 文件
    local trust_policy_file=$(get_trust_policy_file)
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "SageMaker Training Role for ${team_fullname}/${project}" \
            --tags \
                "Key=Team,Value=${team_fullname}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Training" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 附加共享 Deny Admin 策略
    # ========================================
    log_info "Attaching shared Deny Admin policy..."
    attach_policy_to_role "$role_name" "SageMaker-Shared-DenyAdmin" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-Shared-DenyAdmin"
    
    # ========================================
    # 附加 Training 策略（已拆分为基础+操作）
    # ========================================
    log_info "Attaching training policies to role..."
    
    # 附加基础策略 (S3、ECR、CloudWatch、VPC)
    attach_policy_to_role "$role_name" "$policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 附加操作策略 (Training ops, Model Registry, Experiment)
    attach_policy_to_role "$role_name" "$ops_policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${ops_policy_name}"
    
    # 显示权限总结
    echo ""
    log_info "Training Role $role_name permissions:"
    echo "  ✓ SageMaker-Shared-DenyAdmin (security restriction)"
    echo "  ✓ $policy_name (S3, ECR, CloudWatch, VPC)"
    echo "  ✓ $ops_policy_name (Training ops, Model Registry, Experiment)"
    echo "  → Scope: Training Jobs only"
}

# 创建 Processing 专用 Role
# 用法: create_processing_role <team> <project>
create_processing_role() {
    local team=$1
    local project=$2
    
    if [[ "$ENABLE_PROCESSING_ROLE" != "true" ]]; then
        log_info "Processing role skipped (ENABLE_PROCESSING_ROLE=$ENABLE_PROCESSING_ROLE)"
        return 0
    fi
    
    # 格式化名称
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingPolicy"
    local ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingOpsPolicy"
    
    log_info "Creating processing role: $role_name"
    
    # 获取 trust policy 文件
    local trust_policy_file=$(get_trust_policy_file)
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "SageMaker Processing Role for ${team_fullname}/${project}" \
            --tags \
                "Key=Team,Value=${team_fullname}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Processing" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 附加共享 Deny Admin 策略
    # ========================================
    log_info "Attaching shared Deny Admin policy..."
    attach_policy_to_role "$role_name" "SageMaker-Shared-DenyAdmin" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-Shared-DenyAdmin"
    
    # ========================================
    # 附加 Processing 策略（已拆分为基础+操作）
    # ========================================
    log_info "Attaching processing policies to role..."
    
    # 附加基础策略 (S3、ECR、CloudWatch、VPC)
    attach_policy_to_role "$role_name" "$policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 附加操作策略 (Processing ops, Feature Store, Glue/Athena)
    attach_policy_to_role "$role_name" "$ops_policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${ops_policy_name}"
    
    # 显示权限总结
    echo ""
    log_info "Processing Role $role_name permissions:"
    echo "  ✓ SageMaker-Shared-DenyAdmin (security restriction)"
    echo "  ✓ $policy_name (S3, ECR, CloudWatch, VPC)"
    echo "  ✓ $ops_policy_name (Processing ops, Feature Store, Glue/Athena)"
    echo "  → Scope: Processing Jobs only"
}

# 创建 Inference 专用 Role
# 用法: create_inference_role <team> <project>
create_inference_role() {
    local team=$1
    local project=$2
    
    if [[ "$ENABLE_INFERENCE_ROLE" != "true" ]]; then
        log_info "Inference role skipped (ENABLE_INFERENCE_ROLE=$ENABLE_INFERENCE_ROLE)"
        return 0
    fi
    
    # 格式化名称
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-InferenceRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InferencePolicy"
    local ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-InferenceOpsPolicy"
    
    log_info "Creating inference role: $role_name"
    
    # 获取 trust policy 文件
    local trust_policy_file=$(get_trust_policy_file)
    
    # 检查 Role 是否已存在
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Role $role_name already exists, updating trust policy..."
        aws iam update-assume-role-policy \
            --role-name "$role_name" \
            --policy-document "file://${trust_policy_file}"
        log_success "Trust policy updated for $role_name"
    else
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "file://${trust_policy_file}" \
            --description "SageMaker Inference Role for ${team_fullname}/${project} (minimal permissions)" \
            --tags \
                "Key=Team,Value=${team_fullname}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Inference" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 附加共享 Deny Admin 策略
    # ========================================
    log_info "Attaching shared Deny Admin policy..."
    attach_policy_to_role "$role_name" "SageMaker-Shared-DenyAdmin" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-Shared-DenyAdmin"
    
    # ========================================
    # 附加 Inference 策略（已拆分为基础+操作）
    # ========================================
    log_info "Attaching inference policies to role..."
    
    # 附加基础策略 (S3、ECR、CloudWatch、VPC)
    attach_policy_to_role "$role_name" "$policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 附加操作策略 (Inference ops, Model Registry read-only)
    attach_policy_to_role "$role_name" "$ops_policy_name" \
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${ops_policy_name}"
    
    # 显示权限总结
    echo ""
    log_info "Inference Role $role_name permissions (minimal):"
    echo "  ✓ SageMaker-Shared-DenyAdmin (security restriction)"
    echo "  ✓ $policy_name (S3, ECR, CloudWatch, VPC)"
    echo "  ✓ $ops_policy_name (Inference ops, Model Registry read-only)"
    echo "  → Scope: Inference Endpoints only"
}

# =============================================================================
# IAM Group 创建
# =============================================================================

# 创建 IAM Group (通用函数)
# 用法: create_iam_group <group_name>
create_iam_group() {
    local group_name=$1
    
    log_info "Creating IAM Group: $group_name"
    
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        log_warn "Group $group_name already exists, skipping..."
        return 0
    fi
    
    aws iam create-group \
        --group-name "$group_name" \
        --path "${IAM_PATH}"
    
    log_success "IAM Group created: $group_name"
}

# 创建项目 IAM Group
# 用法: create_project_group <team> <project>
create_project_group() {
    local team=$1
    local project=$2
    local group_name="sagemaker-${team}-${project}"
    
    log_info "Creating IAM Group: $group_name"
    
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        log_warn "Group $group_name already exists, skipping..."
        return 0
    fi
    
    aws iam create-group \
        --group-name "$group_name" \
        --path "${IAM_PATH}"
    
    log_success "IAM Group created: $group_name"
}

# 创建团队 IAM Group
# 用法: create_team_group <team>
# 参数: team - 团队短名 (如 ds) 或全名 (如 data-science)
create_team_group() {
    local team=$1
    local team_fullname=$(get_team_fullname "$team")
    local group_name="sagemaker-${team_fullname}"
    
    log_info "Creating team IAM Group: $group_name"
    
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        log_warn "Group $group_name already exists, skipping..."
        return 0
    fi
    
    aws iam create-group \
        --group-name "$group_name" \
        --path "${IAM_PATH}"
    
    log_success "Team IAM Group created: $group_name"
}

# =============================================================================
# 策略绑定到 Group
# =============================================================================

# 绑定 Policy 到 Group (通用函数，带幂等检查)
# 用法: attach_policy_to_group <group_name> <policy_arn>
# 特性: 幂等 - 已绑定则跳过，输出明确日志
attach_policy_to_group() {
    local group_name=$1
    local policy_arn=$2
    local policy_name="${policy_arn##*/}"  # 提取策略名称
    
    log_info "Attaching policy to group: $group_name"
    log_info "  Policy: $policy_name"
    
    # 检查是否已绑定
    local attached=$(aws iam list-attached-group-policies \
        --group-name "$group_name" \
        --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy already attached to $group_name, skipping..."
        return 0
    fi
    
    aws iam attach-group-policy \
        --group-name "$group_name" \
        --policy-arn "$policy_arn"
    
    log_success "Policy attached to $group_name"
}

# 绑定项目策略到 Group
# 用法: bind_policies_to_project_group <team> <project>
# 与 01-iam/05-bind-policies.sh 项目部分逻辑一致
bind_policies_to_project_group() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local group_name="sagemaker-${team}-${project}"
    local policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-${team_capitalized}-${project_formatted}"
    local shared_policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    log_step "Binding policies to project group: $group_name"
    
    # 项目访问策略 (Space, UserProfile)
    attach_policy_to_group "$group_name" "${policy_prefix}-Access"
    
    # 共享策略 - Deny Admin Actions (安全限制)
    attach_policy_to_group "$group_name" "${shared_policy_prefix}SageMaker-Shared-DenyAdmin"
    
    # 共享策略 - S3 项目访问 (与 Execution Role 共用)
    attach_policy_to_group "$group_name" "${policy_prefix}-S3Access"
    
    # 共享策略 - PassRole 到项目角色
    attach_policy_to_group "$group_name" "${policy_prefix}-PassRole"
    
    log_success "All policies bound to project group: $group_name"
}

# 绑定团队策略到 Group
# 用法: bind_team_policies <team>
# 与 01-iam/05-bind-policies.sh 团队部分逻辑一致
bind_team_policies() {
    local team=$1
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local group_name="sagemaker-${team_fullname}"
    local policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    log_step "Binding policies to team group: $group_name"
    
    # 1. AWS 托管策略 - SageMaker 完整权限
    attach_policy_to_group "$group_name" \
        "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
    
    # 2. 基础访问策略
    attach_policy_to_group "$group_name" \
        "${policy_prefix}SageMaker-Studio-Base-Access"
    
    # 3. 用户自服务策略 (修改密码、MFA、Access Key)
    attach_policy_to_group "$group_name" \
        "${policy_prefix}SageMaker-User-SelfService"
    
    # 4. 团队访问策略 (S3 bucket 权限)
    attach_policy_to_group "$group_name" \
        "${policy_prefix}SageMaker-${team_capitalized}-Team-Access"
    
    log_success "All policies bound to team group: $group_name"
}

# =============================================================================
# IAM User 创建
# =============================================================================

# 创建 IAM User (通用函数)
# 用法: create_iam_user <username> <team> [enable_console] [project]
# 参数:
#   username - IAM 用户名 (如 sm-ds-alice)
#   team - 团队名称 (用于标签，可传短名或全称)
#   enable_console - 是否启用 Console 登录 (true/false，默认 false)
#   project - 可选，项目名称 (用于 Project tag)
# 依赖: PASSWORD_PREFIX, PASSWORD_SUFFIX, IAM_PATH, AWS_ACCOUNT_ID, COMPANY
create_iam_user() {
    local username=$1
    local team=$2
    local enable_console=${3:-false}
    local project=${4:-}
    local user_exists=false
    
    log_info "Creating IAM User: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists"
        user_exists=true
    else
        # 构建 tags 参数 (统一使用 ${COMPANY}-sagemaker 格式)
        local tag_args=(
            "Key=Team,Value=${team}"
            "Key=ManagedBy,Value=${COMPANY}-sagemaker"
            "Key=Owner,Value=${username}"
            "Key=Company,Value=${COMPANY}"
        )
        
        # 如果有 project 参数，添加 Project tag
        if [[ -n "$project" ]]; then
            tag_args+=("Key=Project,Value=${project}")
        fi
        
        # 创建用户
        aws iam create-user \
            --user-name "$username" \
            --path "${IAM_PATH}" \
            --tags "${tag_args[@]}"
        log_success "User $username created"
    fi
    
    # 根据 enable_console 决定是否创建 LoginProfile
    if [[ "$enable_console" == "true" ]]; then
        local initial_password="${PASSWORD_PREFIX}${username##*-}${PASSWORD_SUFFIX}"
        
        if ! aws iam get-login-profile --user-name "$username" &> /dev/null; then
            aws iam create-login-profile \
                --user-name "$username" \
                --password "$initial_password" \
                --password-reset-required
            log_success "LoginProfile created for $username (Console login enabled)"
            
            # 返回密码供调用方保存
            echo "$initial_password"
        else
            if [[ "$user_exists" == "true" ]]; then
                log_warn "LoginProfile already exists for $username"
            fi
        fi
    else
        if aws iam get-login-profile --user-name "$username" &> /dev/null; then
            log_warn "User $username has LoginProfile (Console access)"
        fi
    fi
    
    # 检查/应用 Permissions Boundary
    local current_boundary=$(aws iam get-user --user-name "$username" \
        --query 'User.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>/dev/null || echo "None")
    local expected_boundary="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}SageMaker-User-Boundary"
    
    if [[ "$current_boundary" != "$expected_boundary" ]]; then
        aws iam put-user-permissions-boundary \
            --user-name "$username" \
            --permissions-boundary "$expected_boundary"
        log_success "Permissions Boundary applied to $username"
    else
        if [[ "$user_exists" == "true" ]]; then
            log_warn "Permissions Boundary already applied to $username"
        fi
    fi
}

# 创建管理员用户
# 用法: create_admin_user <admin_name> [enable_console]
# 参数:
#   admin_name - 管理员短名 (如 jason)，会生成 sm-admin-jason
#   enable_console - 是否启用 Console 登录 (true/false，默认 false)
create_admin_user() {
    local admin_name=$1
    local enable_console=${2:-false}
    local username="sm-admin-${admin_name}"
    local user_exists=false
    
    log_info "Creating admin user: $username"
    
    # 检查 User 是否已存在
    if aws iam get-user --user-name "$username" &> /dev/null; then
        log_warn "User $username already exists"
        user_exists=true
    else
        aws iam create-user \
            --user-name "$username" \
            --path "${IAM_PATH}" \
            --tags \
                "Key=Role,Value=admin" \
                "Key=ManagedBy,Value=${COMPANY}-sagemaker" \
                "Key=Company,Value=${COMPANY}" \
                "Key=Owner,Value=${username}"
        log_success "Admin user $username created"
    fi
    
    # 管理员用户：根据 enable_console 决定是否创建 LoginProfile
    if [[ "$enable_console" == "true" ]]; then
        local initial_password="${PASSWORD_PREFIX}${admin_name}${PASSWORD_SUFFIX}"
        
        if ! aws iam get-login-profile --user-name "$username" &> /dev/null; then
            aws iam create-login-profile \
                --user-name "$username" \
                --password "$initial_password" \
                --password-reset-required
            log_success "LoginProfile created for $username (Console login enabled)"
            
            # 返回密码供调用方保存
            echo "$initial_password"
        else
            if [[ "$user_exists" == "true" ]]; then
                log_warn "LoginProfile already exists for $username"
            fi
        fi
    else
        if aws iam get-login-profile --user-name "$username" &> /dev/null; then
            log_warn "Admin $username has LoginProfile (Console access)"
        fi
    fi
}

# 添加用户到 Group
# 用法: add_user_to_group <username> <group_name>
add_user_to_group() {
    local username=$1
    local group_name=$2
    
    log_info "Adding user $username to group $group_name"
    
    # 检查用户是否已在组中
    local in_group=$(aws iam get-group --group-name "$group_name" \
        --query "Users[?UserName=='${username}'].UserName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$in_group" ]]; then
        log_warn "User $username already in group $group_name, skipping..."
        return 0
    fi
    
    aws iam add-user-to-group \
        --user-name "$username" \
        --group-name "$group_name"
    
    log_success "User $username added to group $group_name"
}

# =============================================================================
# 团队 IAM 一站式创建
# =============================================================================

# 创建团队所有 IAM 资源
# 用法: create_team_iam <team>
# 创建: Group + Policy + 绑定
create_team_iam() {
    local team=$1
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    
    log_step "========================================"
    log_step "Creating IAM resources for team: ${team_fullname}"
    log_step "========================================"
    
    # 1. 创建 Group
    create_team_group "$team"
    
    # 2. 创建团队策略 (使用模板)
    local policy_name="SageMaker-${team_capitalized}-Team-Access"
    local policy_content=$(generate_team_access_policy "$team")
    create_or_update_policy "$policy_name" "$policy_content"
    
    # 3. 绑定策略到 Group
    bind_team_policies "$team"
    
    log_success "========================================"
    log_success "Team IAM resources created: ${team_fullname}"
    log_success "========================================"
}

# =============================================================================
# 项目策略批量创建
# =============================================================================

# 创建项目所有策略
# 用法: create_project_policies <team> <project>
create_project_policies() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    log_info "Creating project policies for ${team}/${project}..."
    
    # 1. 项目访问策略
    local access_policy_name="SageMaker-${team_capitalized}-${project_formatted}-Access"
    local access_policy=$(generate_project_access_policy "$team" "$project")
    create_or_update_policy "$access_policy_name" "$access_policy"
    
    # 2. S3 访问策略
    local s3_policy_name="SageMaker-${team_capitalized}-${project_formatted}-S3Access"
    local s3_policy=$(generate_shared_s3_access_policy "$team" "$project")
    create_or_update_policy "$s3_policy_name" "$s3_policy"
    
    # 3. PassRole 策略 (包含 Deny 语句)
    local passrole_policy_name="SageMaker-${team_capitalized}-${project_formatted}-PassRole"
    local passrole_policy=$(generate_shared_passrole_policy "$team" "$project")
    create_or_update_policy "$passrole_policy_name" "$passrole_policy"
    
    # 4. Execution Role 基础策略
    local exec_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy"
    local exec_policy=$(generate_execution_role_policy "$team" "$project")
    create_or_update_policy "$exec_policy_name" "$exec_policy"
    
    # 5. Execution Role 作业策略
    local exec_job_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionJobPolicy"
    local exec_job_policy=$(generate_execution_role_jobs_policy "$team" "$project")
    create_or_update_policy "$exec_job_policy_name" "$exec_job_policy"
    
    # 6. Training Role 策略
    local training_policy_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingPolicy"
    local training_policy=$(generate_training_role_policy "$team" "$project")
    create_or_update_policy "$training_policy_name" "$training_policy"
    
    local training_ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingOpsPolicy"
    local training_ops_policy=$(generate_training_role_ops_policy "$team" "$project")
    create_or_update_policy "$training_ops_policy_name" "$training_ops_policy"
    
    # 7. Processing Role 策略
    local processing_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingPolicy"
    local processing_policy=$(generate_processing_role_policy "$team" "$project")
    create_or_update_policy "$processing_policy_name" "$processing_policy"
    
    local processing_ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingOpsPolicy"
    local processing_ops_policy=$(generate_processing_role_ops_policy "$team" "$project")
    create_or_update_policy "$processing_ops_policy_name" "$processing_ops_policy"
    
    # 8. Inference Role 策略
    local inference_policy_name="SageMaker-${team_capitalized}-${project_formatted}-InferencePolicy"
    local inference_policy=$(generate_inference_role_policy "$team" "$project")
    create_or_update_policy "$inference_policy_name" "$inference_policy"
    
    local inference_ops_policy_name="SageMaker-${team_capitalized}-${project_formatted}-InferenceOpsPolicy"
    local inference_ops_policy=$(generate_inference_role_ops_policy "$team" "$project")
    create_or_update_policy "$inference_ops_policy_name" "$inference_ops_policy"
    
    log_success "All project policies created for ${team}/${project}"
}

# =============================================================================
# 完整项目 IAM 创建 (一站式)
# =============================================================================

# 创建项目的所有 IAM 资源
# 用法: create_project_iam <team> <project>
create_project_iam() {
    local team=$1
    local project=$2
    
    log_step "========================================"
    log_step "Creating IAM resources for project: ${team}/${project}"
    log_step "========================================"
    
    # 设置默认值（如果未设置）
    ENABLE_TRAINING_ROLE="${ENABLE_TRAINING_ROLE:-true}"
    ENABLE_PROCESSING_ROLE="${ENABLE_PROCESSING_ROLE:-true}"
    ENABLE_INFERENCE_ROLE="${ENABLE_INFERENCE_ROLE:-true}"
    ENABLE_CANVAS="${ENABLE_CANVAS:-true}"
    ENABLE_MLFLOW="${ENABLE_MLFLOW:-true}"
    
    # 1. 创建 Group
    create_project_group "$team" "$project"
    
    # 2. 创建策略
    create_project_policies "$team" "$project"
    
    # 3. 创建角色
    create_execution_role "$team" "$project"
    create_training_role "$team" "$project"
    create_processing_role "$team" "$project"
    create_inference_role "$team" "$project"
    
    # 4. 绑定策略到 Group
    bind_policies_to_project_group "$team" "$project"
    
    log_success "========================================"
    log_success "Project IAM resources created: ${team}/${project}"
    log_success "========================================"
}

# =============================================================================
# IAM 删除函数 (从 01-iam/cleanup.sh 提取)
# =============================================================================

# 移除用户的所有组关系
# 用法: remove_user_from_groups <username>
remove_user_from_groups() {
    local username=$1
    
    local groups=$(aws iam list-groups-for-user --user-name "$username" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
    
    for group in $groups; do
        log_info "Removing $username from group $group"
        aws iam remove-user-from-group \
            --user-name "$username" \
            --group-name "$group"
    done
}

# 删除用户的登录配置
# 用法: delete_user_login_profile <username>
delete_user_login_profile() {
    local username=$1
    
    if aws iam get-login-profile --user-name "$username" &> /dev/null; then
        log_info "Deleting login profile for $username"
        aws iam delete-login-profile --user-name "$username"
    fi
}

# 删除用户的 Access Keys
# 用法: delete_user_access_keys <username>
delete_user_access_keys() {
    local username=$1
    
    local keys=$(aws iam list-access-keys --user-name "$username" \
        --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
    
    for key in $keys; do
        log_info "Deleting access key $key for $username"
        aws iam delete-access-key \
            --user-name "$username" \
            --access-key-id "$key"
    done
}

# 删除用户的 Permissions Boundary
# 用法: delete_user_boundary <username>
delete_user_boundary() {
    local username=$1
    
    log_info "Removing permissions boundary for $username"
    aws iam delete-user-permissions-boundary \
        --user-name "$username" 2>/dev/null || true
}

# 删除 IAM 用户 (包含所有清理步骤)
# 用法: delete_iam_user <username>
delete_iam_user() {
    local username=$1
    
    log_info "Preparing to delete user: $username"
    
    # 先清理用户的所有关联
    remove_user_from_groups "$username"
    delete_user_login_profile "$username"
    delete_user_access_keys "$username"
    delete_user_boundary "$username"
    
    # 删除用户
    log_info "Deleting user: $username"
    aws iam delete-user --user-name "$username"
    
    log_success "User $username deleted"
}

# 分离 Group 的所有策略
# 用法: detach_group_policies <group_name>
detach_group_policies() {
    local group_name=$1
    
    local policies=$(aws iam list-attached-group-policies --group-name "$group_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $policies; do
        log_info "Detaching policy from group $group_name"
        aws iam detach-group-policy \
            --group-name "$group_name" \
            --policy-arn "$policy_arn"
    done
}

# 删除 IAM Group (包含策略分离)
# 用法: delete_iam_group <group_name>
delete_iam_group() {
    local group_name=$1
    
    log_info "Preparing to delete group: $group_name"
    
    # 先分离所有策略
    detach_group_policies "$group_name"
    
    # 删除组
    log_info "Deleting group: $group_name"
    aws iam delete-group --group-name "$group_name"
    
    log_success "Group $group_name deleted"
}

# 分离 Role 的所有策略 (包含托管策略和内联策略)
# 用法: detach_role_policies <role_name>
detach_role_policies() {
    local role_name=$1
    
    # 分离托管策略
    local policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $policies; do
        log_info "Detaching managed policy from role $role_name"
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
    done
    
    # 删除内联策略
    local inline_policies=$(aws iam list-role-policies --role-name "$role_name" \
        --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    
    for policy_name in $inline_policies; do
        log_info "Deleting inline policy $policy_name from role $role_name"
        aws iam delete-role-policy \
            --role-name "$role_name" \
            --policy-name "$policy_name"
    done
}

# 删除 IAM Role (包含策略分离)
# 用法: delete_iam_role <role_name>
delete_iam_role() {
    local role_name=$1
    
    log_info "Preparing to delete role: $role_name"
    
    # 先分离所有策略
    detach_role_policies "$role_name"
    
    # 删除角色
    log_info "Deleting role: $role_name"
    aws iam delete-role --role-name "$role_name"
    
    log_success "Role $role_name deleted"
}

# 删除策略的所有非默认版本
# 用法: delete_policy_versions <policy_arn>
delete_policy_versions() {
    local policy_arn=$1
    
    local versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
        --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
    
    for version in $versions; do
        log_info "Deleting policy version $version"
        aws iam delete-policy-version \
            --policy-arn "$policy_arn" \
            --version-id "$version"
    done
}

# 删除 IAM Policy (包含版本清理)
# 用法: delete_iam_policy <policy_arn>
delete_iam_policy() {
    local policy_arn=$1
    
    log_info "Preparing to delete policy: $policy_arn"
    
    # 先删除非默认版本
    delete_policy_versions "$policy_arn"
    
    # 删除策略
    log_info "Deleting policy: $policy_arn"
    aws iam delete-policy --policy-arn "$policy_arn"
    
    log_success "Policy deleted"
}

# =============================================================================
# 项目/团队 IAM 批量删除
# =============================================================================

# 删除项目的所有 IAM Roles
# 用法: delete_project_roles <team> <project>
delete_project_roles() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local role_prefix="SageMaker-${team_capitalized}-${project_formatted}"
    
    log_info "Deleting project roles for ${team}/${project}..."
    
    local role_types=("ExecutionRole" "TrainingRole" "ProcessingRole" "InferenceRole")
    
    for role_type in "${role_types[@]}"; do
        local role_name="${role_prefix}-${role_type}"
        if aws iam get-role --role-name "$role_name" &> /dev/null; then
            delete_iam_role "$role_name"
        else
            log_info "Role $role_name not found, skipping..."
        fi
    done
    
    log_success "Project roles deleted for ${team}/${project}"
}

# 删除项目的所有 IAM Policies
# 用法: delete_project_policies <team> <project>
delete_project_iam_policies() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local policy_prefix="SageMaker-${team_capitalized}-${project_formatted}"
    local policy_arn_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    log_info "Deleting project policies for ${team}/${project}..."
    
    local policy_suffixes=(
        "Access" "S3Access" "PassRole"
        "ExecutionPolicy" "ExecutionJobPolicy"
        "TrainingPolicy" "TrainingOpsPolicy"
        "ProcessingPolicy" "ProcessingOpsPolicy"
        "InferencePolicy" "InferenceOpsPolicy"
    )
    
    for suffix in "${policy_suffixes[@]}"; do
        local policy_name="${policy_prefix}-${suffix}"
        local policy_arn="${policy_arn_prefix}${policy_name}"
        if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
            delete_iam_policy "$policy_arn"
        else
            log_info "Policy $policy_name not found, skipping..."
        fi
    done
    
    log_success "Project policies deleted for ${team}/${project}"
}

# 删除项目的所有 IAM 资源 (一站式)
# 用法: delete_project_iam <team> <project>
delete_project_iam() {
    local team=$1
    local project=$2
    local group_name="sagemaker-${team}-${project}"
    
    log_step "========================================"
    log_step "Deleting IAM resources for project: ${team}/${project}"
    log_step "========================================"
    
    # 1. 删除 Group (会先分离策略)
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        delete_iam_group "$group_name"
    else
        log_info "Group $group_name not found, skipping..."
    fi
    
    # 2. 删除 Roles
    delete_project_roles "$team" "$project"
    
    # 3. 删除 Policies
    delete_project_iam_policies "$team" "$project"
    
    log_success "========================================"
    log_success "Project IAM resources deleted: ${team}/${project}"
    log_success "========================================"
}

# 删除团队的所有 IAM 资源
# 用法: delete_team_iam <team>
delete_team_iam() {
    local team=$1
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local group_name="sagemaker-${team_fullname}"
    local policy_name="SageMaker-${team_capitalized}-Team-Access"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    log_step "========================================"
    log_step "Deleting IAM resources for team: ${team_fullname}"
    log_step "========================================"
    
    # 1. 删除 Group
    if aws iam get-group --group-name "$group_name" &> /dev/null; then
        delete_iam_group "$group_name"
    else
        log_info "Group $group_name not found, skipping..."
    fi
    
    # 2. 删除团队策略
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        delete_iam_policy "$policy_arn"
    else
        log_info "Policy $policy_name not found, skipping..."
    fi
    
    log_success "========================================"
    log_success "Team IAM resources deleted: ${team_fullname}"
    log_success "========================================"
}

