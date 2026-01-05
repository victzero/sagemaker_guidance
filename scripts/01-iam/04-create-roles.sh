#!/bin/bash
# =============================================================================
# 04-create-roles.sh - 创建 IAM Execution Roles（生产级 4 角色分离设计）
# =============================================================================
# 使用方法: ./04-create-roles.sh
#
# Execution Role 设计（完整职责分离）:
#   1. ExecutionRole   - 开发角色 (Notebook/Studio, 提交作业)
#   2. TrainingRole    - 训练专用角色 (Training Jobs, HPO)
#   3. ProcessingRole  - 处理专用角色 (Processing Jobs, Data Wrangler)
#   4. InferenceRole   - 推理专用角色 (Endpoints, Batch Transform)
#
# Trust Policy: 允许 sagemaker.amazonaws.com 调用 sts:AssumeRole
#
# 环境变量:
#   ENABLE_CANVAS=true         启用 Canvas 低代码 ML 功能（默认）
#   ENABLE_MLFLOW=true         启用 MLflow 实验追踪（默认）
#   ENABLE_TRAINING_ROLE=true  启用训练专用角色（默认）
#   ENABLE_PROCESSING_ROLE=true 启用处理专用角色（默认）
#   ENABLE_INFERENCE_ROLE=true 启用推理专用角色（默认）
#
# 参考: https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-roles.html
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 策略模板目录
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# Canvas 功能配置（默认开启）
ENABLE_CANVAS="${ENABLE_CANVAS:-true}"

# MLflow 功能配置（默认开启）
ENABLE_MLFLOW="${ENABLE_MLFLOW:-true}"

# 专用角色配置（默认开启，生产级分离）
ENABLE_TRAINING_ROLE="${ENABLE_TRAINING_ROLE:-true}"
ENABLE_PROCESSING_ROLE="${ENABLE_PROCESSING_ROLE:-true}"
ENABLE_INFERENCE_ROLE="${ENABLE_INFERENCE_ROLE:-true}"

# Canvas 相关托管策略
# 注意: 大部分策略在根路径，DirectDeployAccess 在 service-role/ 路径下
CANVAS_MANAGED_POLICIES=(
    "AmazonSageMakerCanvasFullAccess"
    "AmazonSageMakerCanvasAIServicesAccess"
    "AmazonSageMakerCanvasDataPrepFullAccess"
)
# service-role 路径下的策略需要单独处理
CANVAS_SERVICE_ROLE_POLICIES=(
    "AmazonSageMakerCanvasDirectDeployAccess"
)

# 自定义策略名称
STUDIO_APP_POLICY_NAME="SageMaker-StudioAppPermissions"
MLFLOW_APP_POLICY_NAME="SageMaker-MLflowAppAccess"

# 模板文件
TRAINING_ROLE_TEMPLATE="${POLICY_TEMPLATES_DIR}/training-role.json.tpl"
PROCESSING_ROLE_TEMPLATE="${POLICY_TEMPLATES_DIR}/processing-role.json.tpl"
INFERENCE_ROLE_TEMPLATE="${POLICY_TEMPLATES_DIR}/inference-role.json.tpl"

# -----------------------------------------------------------------------------
# Trust Policy
# 用于绑定到 User Profile 的 Execution Role
# 标准格式：只包含 sts:AssumeRole
# -----------------------------------------------------------------------------
get_trust_policy_file() {
    local trust_policy_file="${POLICY_TEMPLATES_DIR}/trust-policy-sagemaker.json"
    
    if [[ ! -f "$trust_policy_file" ]]; then
        log_error "Trust policy template not found: $trust_policy_file"
        exit 1
    fi
    
    # 复制到 output 目录
    cp "$trust_policy_file" "${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
    echo "${SCRIPT_DIR}/${OUTPUT_DIR}/trust-policy-sagemaker.json"
}

# -----------------------------------------------------------------------------
# 附加 Canvas 相关策略
# Canvas 是 SageMaker 的低代码 ML 平台，包括：
#   - CanvasFullAccess: Canvas 核心功能
#   - CanvasAIServicesAccess: Bedrock, Textract, Comprehend 等 AI 服务
#   - CanvasDataPrepFullAccess: Data Wrangler, Glue, Athena 数据准备
#   - CanvasDirectDeployAccess: 模型部署到 Endpoint
# -----------------------------------------------------------------------------
attach_canvas_policies() {
    local role_name=$1
    
    if [[ "$ENABLE_CANVAS" != "true" ]]; then
        log_info "Canvas policies skipped (ENABLE_CANVAS=$ENABLE_CANVAS)"
        return 0
    fi
    
    log_info "Attaching Canvas policies to $role_name..."
    
    # 附加根路径下的策略
    for policy_name in "${CANVAS_MANAGED_POLICIES[@]}"; do
        local policy_arn="arn:aws:iam::aws:policy/${policy_name}"
        
        # 检查是否已附加
        local attached=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached" ]]; then
            log_warn "  $policy_name already attached"
        else
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn"
            log_success "  $policy_name attached"
        fi
    done
    
    # 附加 service-role 路径下的策略
    for policy_name in "${CANVAS_SERVICE_ROLE_POLICIES[@]}"; do
        local policy_arn="arn:aws:iam::aws:policy/service-role/${policy_name}"
        
        # 检查是否已附加
        local attached=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached" ]]; then
            log_warn "  $policy_name already attached"
        else
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn"
            log_success "  $policy_name attached"
        fi
    done
}

# -----------------------------------------------------------------------------
# 附加 Studio App Permissions 策略 (安全必须，始终附加)
# 提供精细化的 Studio 权限隔离：
#   - 用户只能操作自己的 Private Space
#   - 可以在 Shared Space 创建/删除 App
#   - 防止用户误删他人资源
# -----------------------------------------------------------------------------
attach_studio_app_permissions() {
    local role_name=$1
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${STUDIO_APP_POLICY_NAME}"
    
    log_info "Attaching Studio App permissions to $role_name (security required)..."
    
    # 检查是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${STUDIO_APP_POLICY_NAME}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "  $STUDIO_APP_POLICY_NAME already attached"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        log_success "  $STUDIO_APP_POLICY_NAME attached"
    fi
}

# -----------------------------------------------------------------------------
# 附加 MLflow App Access 策略 (可选，默认开启)
# 提供 MLflow 实验追踪能力：
#   - 创建/管理 MLflow App
#   - 记录参数、指标、模型版本
#   - 与 SageMaker Model Registry 集成
# -----------------------------------------------------------------------------
attach_mlflow_app_access() {
    local role_name=$1
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${MLFLOW_APP_POLICY_NAME}"
    
    if [[ "$ENABLE_MLFLOW" != "true" ]]; then
        log_info "MLflow policy skipped (ENABLE_MLFLOW=$ENABLE_MLFLOW)"
        return 0
    fi
    
    log_info "Attaching MLflow App access to $role_name..."
    
    # 检查是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${MLFLOW_APP_POLICY_NAME}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "  $MLFLOW_APP_POLICY_NAME already attached"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn"
        log_success "  $MLFLOW_APP_POLICY_NAME attached"
    fi
}

# -----------------------------------------------------------------------------
# 创建 Domain 默认 Execution Role
# 
# Domain Default Role 权限:
#   - AmazonSageMakerFullAccess (AWS 托管策略)
#   - 不附加项目特定 S3 权限
# 
# 用途: 作为 Domain 的默认执行角色，User Profile 可以覆盖
# -----------------------------------------------------------------------------
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
                "Key=ManagedBy,Value=sagemaker-iam-script" \
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

# -----------------------------------------------------------------------------
# 创建项目 Execution Role 函数
#
# 项目 Execution Role 权限层次:
#   1. AmazonSageMakerFullAccess (必须，AWS 托管策略)
#   2. 项目自定义策略 (S3、ECR、CloudWatch 等)
# -----------------------------------------------------------------------------
create_execution_role() {
    local team=$1
    local project=$2
    
    # 格式化名称 (risk-control -> RiskControl, project-a -> ProjectA)
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy"
    
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
            --description "SageMaker Execution Role for ${team}/${project}" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=ManagedBy,Value=sagemaker-iam-script" \
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
    # 第五步: 附加项目自定义策略 (S3、ECR、CloudWatch 等)
    # ========================================
    log_info "Step 5: Attaching project-specific policy to role..."
    
    # 检查策略是否已附加
    local attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$attached" ]]; then
        log_warn "Policy $policy_name already attached to $role_name"
    else
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
        
        log_success "Policy $policy_name attached to $role_name"
    fi
    
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
    echo "  ✓ $policy_name (custom - S3, ECR, CloudWatch)"
}

# -----------------------------------------------------------------------------
# 创建 Training 专用 Role
#
# Training Role 权限:
#   - S3 读取训练数据 + 写入模型输出
#   - ECR 只读（拉取训练镜像）
#   - Model Registry 写入
#   - Training/HPO 操作
#   - 实验追踪
# -----------------------------------------------------------------------------
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
            --description "SageMaker Training Role for ${team}/${project}" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Training" \
                "Key=ManagedBy,Value=sagemaker-iam-script" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 创建 Training 专用策略
    # ========================================
    log_info "Creating training policy: $policy_name"
    
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "Policy $policy_name already exists"
    else
        if [[ ! -f "$TRAINING_ROLE_TEMPLATE" ]]; then
            log_error "Training role template not found: $TRAINING_ROLE_TEMPLATE"
            return 1
        fi
        
        # 替换模板变量
        local policy_doc=$(cat "$TRAINING_ROLE_TEMPLATE" | \
            sed "s/\${COMPANY}/${COMPANY}/g" | \
            sed "s/\${TEAM}/${team}/g" | \
            sed "s/\${PROJECT}/${project}/g" | \
            sed "s/\${TEAM_FULLNAME}/${team_capitalized}/g" | \
            sed "s/\${PROJECT_FULLNAME}/${project_formatted}/g" | \
            sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" | \
            sed "s/\${AWS_REGION}/${AWS_REGION}/g")
        
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "$IAM_PATH" \
            --description "Training-specific policy for ${team}/${project}" \
            --policy-document "$policy_doc" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Training" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        
        log_success "Policy $policy_name created"
    fi
    
    # 附加策略到角色
    log_info "Attaching training policy to role..."
    
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
    
    # 显示权限总结
    echo ""
    log_info "Training Role $role_name permissions:"
    echo "  ✓ S3 training data read (data/*, datasets/*, processed/*)"
    echo "  ✓ S3 model output write (models/*, training-output/*, checkpoints/*)"
    echo "  ✓ ECR pull-only (training images)"
    echo "  ✓ Model Registry write"
    echo "  ✓ Experiment tracking"
    echo "  ✓ Training/HPO operations"
    echo "  ✓ VPC network interface"
    echo "  ✗ No Processing permissions"
    echo "  ✗ No Inference permissions"
}

# -----------------------------------------------------------------------------
# 创建 Processing 专用 Role
#
# Processing Role 权限:
#   - S3 读取原始数据 + 写入处理输出
#   - ECR 只读（拉取处理镜像）
#   - Processing/Data Wrangler 操作
#   - Feature Store 访问
#   - Glue/Athena 数据目录访问
# -----------------------------------------------------------------------------
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
            --description "SageMaker Processing Role for ${team}/${project}" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Processing" \
                "Key=ManagedBy,Value=sagemaker-iam-script" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 创建 Processing 专用策略
    # ========================================
    log_info "Creating processing policy: $policy_name"
    
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "Policy $policy_name already exists"
    else
        if [[ ! -f "$PROCESSING_ROLE_TEMPLATE" ]]; then
            log_error "Processing role template not found: $PROCESSING_ROLE_TEMPLATE"
            return 1
        fi
        
        # 替换模板变量
        local policy_doc=$(cat "$PROCESSING_ROLE_TEMPLATE" | \
            sed "s/\${COMPANY}/${COMPANY}/g" | \
            sed "s/\${TEAM}/${team}/g" | \
            sed "s/\${PROJECT}/${project}/g" | \
            sed "s/\${TEAM_FULLNAME}/${team_capitalized}/g" | \
            sed "s/\${PROJECT_FULLNAME}/${project_formatted}/g" | \
            sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" | \
            sed "s/\${AWS_REGION}/${AWS_REGION}/g")
        
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "$IAM_PATH" \
            --description "Processing-specific policy for ${team}/${project}" \
            --policy-document "$policy_doc" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Processing" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        
        log_success "Policy $policy_name created"
    fi
    
    # 附加策略到角色
    log_info "Attaching processing policy to role..."
    
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
    
    # 显示权限总结
    echo ""
    log_info "Processing Role $role_name permissions:"
    echo "  ✓ S3 raw data read (data/*, raw/*, datasets/*)"
    echo "  ✓ S3 processed output write (processed/*, features/*)"
    echo "  ✓ ECR pull-only (processing images)"
    echo "  ✓ Processing/Data Wrangler operations"
    echo "  ✓ Feature Store access"
    echo "  ✓ Glue/Athena catalog access"
    echo "  ✓ VPC network interface"
    echo "  ✗ No Training permissions"
    echo "  ✗ No Inference permissions"
}

# -----------------------------------------------------------------------------
# 创建 Inference 专用 Role（最小权限原则）
#
# Inference Role 权限:
#   - S3 只读（模型文件）+ 推理输出
#   - ECR 只读（拉取镜像）
#   - Model Registry 只读
#   - 推理操作（Endpoint, Transform, etc.）
#   - 不包含 Training/Processing 权限
# -----------------------------------------------------------------------------
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
            --description "SageMaker Inference Role for ${team}/${project} (minimal permissions)" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Inference" \
                "Key=ManagedBy,Value=sagemaker-iam-script" \
                "Key=Company,Value=${COMPANY}"
        
        log_success "Role $role_name created"
    fi
    
    # ========================================
    # 创建 Inference 专用策略
    # ========================================
    log_info "Creating inference policy: $policy_name"
    
    # 检查策略是否已存在
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log_warn "Policy $policy_name already exists"
    else
        # 从模板生成策略
        if [[ ! -f "$INFERENCE_ROLE_TEMPLATE" ]]; then
            log_error "Inference role template not found: $INFERENCE_ROLE_TEMPLATE"
            return 1
        fi
        
        # 替换模板变量
        local policy_doc=$(cat "$INFERENCE_ROLE_TEMPLATE" | \
            sed "s/\${COMPANY}/${COMPANY}/g" | \
            sed "s/\${TEAM}/${team}/g" | \
            sed "s/\${PROJECT}/${project}/g" | \
            sed "s/\${TEAM_FULLNAME}/${team_capitalized}/g" | \
            sed "s/\${PROJECT_FULLNAME}/${project_formatted}/g" | \
            sed "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" | \
            sed "s/\${AWS_REGION}/${AWS_REGION}/g")
        
        # 创建策略
        aws iam create-policy \
            --policy-name "$policy_name" \
            --path "$IAM_PATH" \
            --description "Inference-specific policy for ${team}/${project}" \
            --policy-document "$policy_doc" \
            --tags \
                "Key=Team,Value=${team}" \
                "Key=Project,Value=${project}" \
                "Key=Purpose,Value=Inference" \
                "Key=ManagedBy,Value=sagemaker-iam-script"
        
        log_success "Policy $policy_name created"
    fi
    
    # ========================================
    # 附加策略到角色
    # ========================================
    log_info "Attaching inference policy to role..."
    
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
    
    # 显示权限总结
    echo ""
    log_info "Inference Role $role_name permissions (minimal):"
    echo "  ✓ S3 model read-only (models/*, inference/*)"
    echo "  ✓ S3 inference output (inference/output/*, batch-transform/*)"
    echo "  ✓ ECR pull-only (inference images)"
    echo "  ✓ Model Registry read-only"
    echo "  ✓ Inference operations (Endpoint, Transform)"
    echo "  ✓ VPC network interface"
    echo "  ✗ No Training/Processing permissions"
    echo "  ✗ No S3 full write access"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating IAM Execution Roles"
    echo "=============================================="
    echo ""
    
    # 显示配置
    echo "Configuration:"
    echo "  Canvas (low-code ML):   $([ "$ENABLE_CANVAS" == "true" ] && echo "ENABLED (default)" || echo "DISABLED")"
    echo "  MLflow (tracking):      $([ "$ENABLE_MLFLOW" == "true" ] && echo "ENABLED (default)" || echo "DISABLED")"
    echo "  Studio App Isolation:   ENABLED (always)"
    echo ""
    echo "Role Types (Production-Grade Separation):"
    echo "  ExecutionRole:   ENABLED (always) - Notebook/Studio development"
    echo "  TrainingRole:    $([ "$ENABLE_TRAINING_ROLE" == "true" ] && echo "ENABLED (default)" || echo "DISABLED") - Training Jobs, HPO"
    echo "  ProcessingRole:  $([ "$ENABLE_PROCESSING_ROLE" == "true" ] && echo "ENABLED (default)" || echo "DISABLED") - Processing Jobs, Data Wrangler"
    echo "  InferenceRole:   $([ "$ENABLE_INFERENCE_ROLE" == "true" ] && echo "ENABLED (default)" || echo "DISABLED") - Endpoints, Batch Transform"
    echo ""
    
    if [[ "$ENABLE_CANVAS" == "true" ]]; then
        echo "Canvas policies to attach:"
        for policy in "${CANVAS_MANAGED_POLICIES[@]}"; do
            echo "  - $policy"
        done
        echo ""
    fi
    
    echo "Custom policies to attach:"
    echo "  - $STUDIO_APP_POLICY_NAME (always)"
    if [[ "$ENABLE_MLFLOW" == "true" ]]; then
        echo "  - $MLFLOW_APP_POLICY_NAME"
    fi
    echo ""
    
    # 检查模板目录
    if [[ ! -d "$POLICY_TEMPLATES_DIR" ]]; then
        log_error "Policy templates directory not found: $POLICY_TEMPLATES_DIR"
        exit 1
    fi
    log_info "Using trust policy from: $POLICY_TEMPLATES_DIR/trust-policy-sagemaker.json"
    echo ""
    
    # 显示 Trust Policy 格式说明
    echo "Trust Policy Format (for User Profile Execution Role):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "${POLICY_TEMPLATES_DIR}/trust-policy-sagemaker.json"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 1. 创建 Domain 默认 Execution Role（必须先创建）
    log_info "Creating Domain default execution role..."
    create_domain_default_role
    
    echo ""
    echo "----------------------------------------------"
    echo ""
    
    # 2. 为每个项目创建所有专用角色
    for team in $TEAMS; do
        log_info "Creating roles for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Project: ${team}/${project}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            
            # 1. 创建开发用 Execution Role (Notebook/Studio)
            create_execution_role "$team" "$project"
            echo ""
            
            # 2. 创建训练专用 Training Role
            create_training_role "$team" "$project"
            echo ""
            
            # 3. 创建处理专用 Processing Role
            create_processing_role "$team" "$project"
            echo ""
            
            # 4. 创建推理专用 Inference Role
            create_inference_role "$team" "$project"
            echo ""
        done
    done
    
    echo ""
    log_success "All execution roles created successfully!"
    echo ""
    
    # 显示创建的 Roles (通过名称前缀筛选，不使用 path)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                        Created Roles Summary                             ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    
    echo ""
    echo "Execution Roles (Development/Notebook):"
    aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)].{Name:RoleName}' \
        --output table 2>/dev/null || echo "  (none)"
    
    if [[ "$ENABLE_TRAINING_ROLE" == "true" ]]; then
        echo ""
        echo "Training Roles (Training Jobs):"
        aws iam list-roles \
            --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `TrainingRole`)].{Name:RoleName}' \
            --output table 2>/dev/null || echo "  (none)"
    fi
    
    if [[ "$ENABLE_PROCESSING_ROLE" == "true" ]]; then
        echo ""
        echo "Processing Roles (Processing Jobs):"
        aws iam list-roles \
            --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ProcessingRole`)].{Name:RoleName}' \
            --output table 2>/dev/null || echo "  (none)"
    fi
    
    if [[ "$ENABLE_INFERENCE_ROLE" == "true" ]]; then
        echo ""
        echo "Inference Roles (Production Deployment):"
        aws iam list-roles \
            --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `InferenceRole`)].{Name:RoleName}' \
            --output table 2>/dev/null || echo "  (none)"
    fi
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║                     Permission Summary (4-Role Design)                   ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    echo "│ ExecutionRole (Development/Notebook)                                    │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo "│  ✓ AmazonSageMakerFullAccess (AWS managed)                              │"
    if [[ "$ENABLE_CANVAS" == "true" ]]; then
        echo "│  ✓ Canvas policies (AWS managed - low-code ML)                          │"
    fi
    echo "│  ✓ Studio App Permissions (user isolation)                              │"
    if [[ "$ENABLE_MLFLOW" == "true" ]]; then
        echo "│  ✓ MLflow App Access (experiment tracking)                              │"
    fi
    echo "│  ✓ S3 full access (project bucket)                                      │"
    echo "│  ✓ ECR read/write (custom images)                                       │"
    echo "│  ✓ Pass Role to Training/Processing/Inference                           │"
    echo "└─────────────────────────────────────────────────────────────────────────┘"
    
    if [[ "$ENABLE_TRAINING_ROLE" == "true" ]]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────────┐"
        echo "│ TrainingRole (Training Jobs / HPO)                                      │"
        echo "├─────────────────────────────────────────────────────────────────────────┤"
        echo "│  ✓ S3 training data read (data/*, datasets/*)                           │"
        echo "│  ✓ S3 model output write (models/*, training-output/*)                  │"
        echo "│  ✓ ECR pull-only (training images)                                      │"
        echo "│  ✓ Model Registry write                                                 │"
        echo "│  ✓ Experiment tracking                                                  │"
        echo "│  ✗ No Processing/Inference permissions                                  │"
        echo "└─────────────────────────────────────────────────────────────────────────┘"
    fi
    
    if [[ "$ENABLE_PROCESSING_ROLE" == "true" ]]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────────┐"
        echo "│ ProcessingRole (Processing Jobs / Data Wrangler)                        │"
        echo "├─────────────────────────────────────────────────────────────────────────┤"
        echo "│  ✓ S3 raw data read (data/*, raw/*)                                     │"
        echo "│  ✓ S3 processed output write (processed/*, features/*)                  │"
        echo "│  ✓ ECR pull-only (processing images)                                    │"
        echo "│  ✓ Feature Store access                                                 │"
        echo "│  ✓ Glue/Athena catalog access                                           │"
        echo "│  ✗ No Training/Inference permissions                                    │"
        echo "└─────────────────────────────────────────────────────────────────────────┘"
    fi
    
    if [[ "$ENABLE_INFERENCE_ROLE" == "true" ]]; then
        echo ""
        echo "┌─────────────────────────────────────────────────────────────────────────┐"
        echo "│ InferenceRole (Endpoints / Batch Transform)                             │"
        echo "├─────────────────────────────────────────────────────────────────────────┤"
        echo "│  ✓ S3 model read-only (models/*, inference/*)                           │"
        echo "│  ✓ S3 inference output (inference/output/*, batch-transform/*)          │"
        echo "│  ✓ ECR pull-only (inference images)                                     │"
        echo "│  ✓ Model Registry read-only                                             │"
        echo "│  ✗ No Training/Processing permissions                                   │"
        echo "└─────────────────────────────────────────────────────────────────────────┘"
    fi
    
    echo ""
    echo "Usage Guide:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Notebook/Studio:    Use ExecutionRole (User Profile binding)"
    echo "  Training Jobs:      Use TrainingRole (pass via estimator.fit())"
    echo "  Processing Jobs:    Use ProcessingRole (pass via processor.run())"
    echo "  Model Deployment:   Use InferenceRole (pass via model.deploy())"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main
