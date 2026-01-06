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

# 策略模板目录 (lib/iam-core.sh 依赖)
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"

# -----------------------------------------------------------------------------
# 加载核心函数库 (复用 lib/ 中的角色创建函数)
# 注意: 必须在设置 POLICY_TEMPLATES_DIR 之后加载
# -----------------------------------------------------------------------------
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# -----------------------------------------------------------------------------
# 功能配置
# -----------------------------------------------------------------------------

# Canvas 功能配置（默认开启）
ENABLE_CANVAS="${ENABLE_CANVAS:-true}"

# MLflow 功能配置（默认开启）
ENABLE_MLFLOW="${ENABLE_MLFLOW:-true}"

# 专用角色配置（默认开启，生产级分离）
ENABLE_TRAINING_ROLE="${ENABLE_TRAINING_ROLE:-true}"
ENABLE_PROCESSING_ROLE="${ENABLE_PROCESSING_ROLE:-true}"
ENABLE_INFERENCE_ROLE="${ENABLE_INFERENCE_ROLE:-true}"

# 自定义策略名称 (供 lib 函数使用)
STUDIO_APP_POLICY_NAME="SageMaker-StudioAppPermissions"
MLFLOW_APP_POLICY_NAME="SageMaker-MLflowAppAccess"

# -----------------------------------------------------------------------------
# 注意: 以下函数已移至 lib/iam-core.sh 统一维护
#
# 可用函数:
#   - get_trust_policy_file()
#   - attach_canvas_policies()
#   - attach_studio_app_permissions()
#   - attach_mlflow_app_access()
#   - attach_policy_to_role()
#   - create_domain_default_role()
#   - create_execution_role()
#   - create_training_role()
#   - create_processing_role()
#   - create_inference_role()
# -----------------------------------------------------------------------------

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
        echo "  - AmazonSageMakerCanvasFullAccess"
        echo "  - AmazonSageMakerCanvasAIServicesAccess"
        echo "  - AmazonSageMakerCanvasDataPrepFullAccess"
        echo "  - AmazonSageMakerCanvasDirectDeployAccess (service-role)"
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
        echo "│  → Scope: Training Jobs only                                            │"
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
        echo "│  → Scope: Processing Jobs only                                          │"
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
        echo "│  → Scope: Inference Endpoints only                                      │"
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
