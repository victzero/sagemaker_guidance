#!/bin/bash
# =============================================================================
# cleanup.sh - 清理所有 IAM 资源 (危险操作!)
# =============================================================================
# 使用方法: ./cleanup.sh [--force]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# 加载删除函数库 (统一实现，避免代码重复)
POLICY_TEMPLATES_DIR="${SCRIPT_DIR}/policies"
source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# 检查 force 参数
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: IAM Resource Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following resources:"
echo "  - All IAM Users with path ${IAM_PATH}"
echo "  - All IAM Groups with path ${IAM_PATH}"
echo "  - All IAM Roles matching SageMaker-*-ExecutionRole (default path)"
echo "  - All IAM Policies with path ${IAM_PATH}"
echo ""

if [[ "$FORCE" != "true" ]]; then
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# 注意: 删除函数已移至 lib/iam-core.sh 统一维护
# 可用函数: delete_iam_user, delete_iam_group, delete_iam_role, delete_iam_policy
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    log_info "Starting cleanup..."
    
    # 1. 删除用户
    log_info "Step 1: Deleting users..."
    local users=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'Users[].UserName' --output text 2>/dev/null || echo "")
    
    for user in $users; do
        delete_iam_user "$user"
    done
    
    # 2. 删除组
    log_info "Step 2: Deleting groups..."
    local groups=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'Groups[].GroupName' --output text 2>/dev/null || echo "")
    
    for group in $groups; do
        delete_iam_group "$group"
    done
    
    # 3. 删除角色（不使用 path，通过名称前缀筛选）
    log_info "Step 3: Deleting roles..."
    
    # 删除 Execution Roles
    log_info "  Deleting Execution Roles..."
    local exec_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    for role in $exec_roles; do
        delete_iam_role "$role"
    done
    
    # 删除 Training Roles
    log_info "  Deleting Training Roles..."
    local training_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `TrainingRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    for role in $training_roles; do
        delete_iam_role "$role"
    done
    
    # 删除 Processing Roles
    log_info "  Deleting Processing Roles..."
    local processing_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ProcessingRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    for role in $processing_roles; do
        delete_iam_role "$role"
    done
    
    # 删除 Inference Roles
    log_info "  Deleting Inference Roles..."
    local inference_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `InferenceRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    for role in $inference_roles; do
        delete_iam_role "$role"
    done
    
    # 4. 删除策略
    log_info "Step 4: Deleting policies..."
    local policies=$(aws iam list-policies --scope Local --path-prefix "${IAM_PATH}" \
        --query 'Policies[].Arn' --output text 2>/dev/null || echo "")
    
    for policy in $policies; do
        delete_iam_policy "$policy"
    done
    
    echo ""
    log_success "Cleanup complete!"
}

main
