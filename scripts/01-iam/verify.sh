#!/bin/bash
# =============================================================================
# verify.sh - 验证 IAM 资源配置
# =============================================================================
# 使用方法: ./verify.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " IAM Resources Verification"
echo "=============================================="
echo ""
echo "IAM Path: ${IAM_PATH}"
echo ""

# -----------------------------------------------------------------------------
# 验证函数
# -----------------------------------------------------------------------------
verify_section() {
    local title=$1
    echo ""
    echo -e "${BLUE}--- $title ---${NC}"
}

check_exists() {
    local type=$1
    local name=$2
    
    case $type in
        user)
            aws iam get-user --user-name "$name" &> /dev/null
            ;;
        group)
            aws iam get-group --group-name "$name" &> /dev/null
            ;;
        role)
            aws iam get-role --role-name "$name" &> /dev/null
            ;;
        policy)
            aws iam get-policy --policy-arn "$name" &> /dev/null
            ;;
    esac
}

verify_resource() {
    local type=$1
    local name=$2
    
    if check_exists "$type" "$name"; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name (NOT FOUND)"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 统计实际资源
# -----------------------------------------------------------------------------
count_actual_resources() {
    echo -e "${BLUE}Counting actual resources in AWS...${NC}"
    
    # 使用 head -1 和 tr 确保只获取单个数字，避免多行输出导致算术错误
    ACTUAL_POLICIES=$(aws iam list-policies --scope Local --path-prefix "${IAM_PATH}" \
        --query 'length(Policies)' --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_POLICIES=${ACTUAL_POLICIES:-0}
    
    ACTUAL_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'length(Groups)' --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_GROUPS=${ACTUAL_GROUPS:-0}
    
    ACTUAL_USERS=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'length(Users)' --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_USERS=${ACTUAL_USERS:-0}
    
    # Roles 不使用 path，通过名称前缀筛选
    ACTUAL_EXEC_ROLES=$(aws iam list-roles \
        --query 'length(Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)])' \
        --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_EXEC_ROLES=${ACTUAL_EXEC_ROLES:-0}
    
    ACTUAL_TRAINING_ROLES=$(aws iam list-roles \
        --query 'length(Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `TrainingRole`)])' \
        --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_TRAINING_ROLES=${ACTUAL_TRAINING_ROLES:-0}
    
    ACTUAL_PROCESSING_ROLES=$(aws iam list-roles \
        --query 'length(Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ProcessingRole`)])' \
        --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_PROCESSING_ROLES=${ACTUAL_PROCESSING_ROLES:-0}
    
    ACTUAL_INFERENCE_ROLES=$(aws iam list-roles \
        --query 'length(Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `InferenceRole`)])' \
        --output text 2>/dev/null | head -1 | tr -d '[:space:]')
    ACTUAL_INFERENCE_ROLES=${ACTUAL_INFERENCE_ROLES:-0}
    
    ACTUAL_ROLES=$((ACTUAL_EXEC_ROLES + ACTUAL_TRAINING_ROLES + ACTUAL_PROCESSING_ROLES + ACTUAL_INFERENCE_ROLES))
    
    echo ""
    echo "Resource Summary:"
    echo "  +-------------------+----------+----------+"
    echo "  | Resource          | Expected | Actual   |"
    echo "  +-------------------+----------+----------+"
    printf "  | %-17s | %8d | %8d |\n" "Policies" "$EXPECTED_POLICIES" "$ACTUAL_POLICIES"
    printf "  | %-17s | %8d | %8d |\n" "Groups" "$EXPECTED_GROUPS" "$ACTUAL_GROUPS"
    printf "  | %-17s | %8d | %8d |\n" "Users" "$EXPECTED_USERS" "$ACTUAL_USERS"
    printf "  | %-17s | %8d | %8d |\n" "Execution Roles" "$EXPECTED_ROLES" "$ACTUAL_EXEC_ROLES"
    printf "  | %-17s | %8d | %8d |\n" "Training Roles" "$EXPECTED_ROLES" "$ACTUAL_TRAINING_ROLES"
    printf "  | %-17s | %8d | %8d |\n" "Processing Roles" "$EXPECTED_ROLES" "$ACTUAL_PROCESSING_ROLES"
    printf "  | %-17s | %8d | %8d |\n" "Inference Roles" "$EXPECTED_ROLES" "$ACTUAL_INFERENCE_ROLES"
    echo "  +-------------------+----------+----------+"
}

# -----------------------------------------------------------------------------
# 列出实际资源
# -----------------------------------------------------------------------------
list_actual_resources() {
    verify_section "Actual Resources in AWS"
    
    echo ""
    echo "Policies (path: ${IAM_PATH}):"
    aws iam list-policies --scope Local --path-prefix "${IAM_PATH}" \
        --query 'Policies[].PolicyName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Groups (path: ${IAM_PATH}):"
    aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'Groups[].GroupName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Users (path: ${IAM_PATH}):"
    aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'Users[].UserName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Execution Roles (SageMaker-*-ExecutionRole):"
    aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Training Roles (SageMaker-*-TrainingRole):"
    aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `TrainingRole`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Processing Roles (SageMaker-*-ProcessingRole):"
    aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ProcessingRole`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
    
    echo ""
    echo "Inference Roles (SageMaker-*-InferenceRole):"
    aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `InferenceRole`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    local errors=0
    local policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    # 先统计资源
    count_actual_resources
    
    # 1. 验证策略
    verify_section "IAM Policies"
    
    verify_resource policy "${policy_prefix}SageMaker-Studio-Base-Access" || ((errors++))
    verify_resource policy "${policy_prefix}SageMaker-ReadOnly-Access" || ((errors++))
    verify_resource policy "${policy_prefix}SageMaker-User-SelfService" || ((errors++))
    verify_resource policy "${policy_prefix}SageMaker-User-Boundary" || ((errors++))
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-Team-Access" || ((errors++))
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-Access" || ((errors++))
            # Execution Role policies (split)
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy" || ((errors++))
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-ExecutionJobPolicy" || ((errors++))
            # Training Role policies (split)
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-TrainingPolicy" || ((errors++))
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-TrainingOpsPolicy" || ((errors++))
            # Processing Role policies (split)
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-ProcessingPolicy" || ((errors++))
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-ProcessingOpsPolicy" || ((errors++))
            # Inference Role policies (split)
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-InferencePolicy" || ((errors++))
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-InferenceOpsPolicy" || ((errors++))
        done
    done
    
    # 2. 验证组
    verify_section "IAM Groups"
    
    verify_resource group "sagemaker-admins" || ((errors++))
    verify_resource group "sagemaker-readonly" || ((errors++))
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        verify_resource group "sagemaker-${team_fullname}" || ((errors++))
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            verify_resource group "sagemaker-${team}-${project}" || ((errors++))
        done
    done
    
    # 3. 验证用户
    verify_section "IAM Users"
    
    for admin in $ADMIN_USERS; do
        verify_resource user "sm-admin-${admin}" || ((errors++))
    done
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                verify_resource user "sm-${team}-${user}" || ((errors++))
            done
        done
    done
    
    # 4. 验证角色
    verify_section "IAM Execution Roles"
    
    # 首先验证 Domain 默认 Execution Role
    verify_resource role "SageMaker-Domain-DefaultExecutionRole" || ((errors++))
    
    # 验证项目 Execution Roles
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            verify_resource role "SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole" || ((errors++))
        done
    done
    
    # 4.1 验证 Trust Policy（SageMaker 可以 assume 这些 roles）
    verify_section "Execution Roles - Trust Policy"
    
    # 检查所有 Execution Roles 的 trust policy（不使用 path，通过名称筛选）
    # 注意: JMESPath 使用反引号 ` 表示字符串字面量
    local all_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)].RoleName' --output text)
    
    for role_name in $all_roles; do
        local trust_has_sagemaker=$(aws iam get-role --role-name "$role_name" \
            --query 'Role.AssumeRolePolicyDocument.Statement[?Principal.Service==`sagemaker.amazonaws.com`]' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$trust_has_sagemaker" ]]; then
            echo -e "  ${GREEN}✓${NC} $role_name trust policy includes sagemaker.amazonaws.com"
        else
            echo -e "  ${RED}✗${NC} $role_name trust policy MISSING sagemaker.amazonaws.com"
            echo -e "      Run: ./04-create-roles.sh to fix (or ./fix-trust-policy.sh)"
            ((errors++)) || true
        fi
    done
    
    # 4.2 验证 Execution Roles 的 AmazonSageMakerFullAccess 策略（Phase 2 ML Jobs 支持）
    verify_section "Execution Roles - AmazonSageMakerFullAccess (ML Jobs)"
    
    # Domain 默认角色
    local domain_sm_policy=$(aws iam list-attached-role-policies \
        --role-name "SageMaker-Domain-DefaultExecutionRole" \
        --query 'AttachedPolicies[?PolicyName==`AmazonSageMakerFullAccess`].PolicyName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$domain_sm_policy" ]]; then
        echo -e "  ${GREEN}✓${NC} SageMaker-Domain-DefaultExecutionRole → AmazonSageMakerFullAccess"
    else
        echo -e "  ${RED}✗${NC} SageMaker-Domain-DefaultExecutionRole missing AmazonSageMakerFullAccess"
        ((errors++)) || true
    fi
    
    # 项目 Execution Roles
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
            
            local sm_policy=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[?PolicyName==`AmazonSageMakerFullAccess`].PolicyName' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$sm_policy" ]]; then
                echo -e "  ${GREEN}✓${NC} $role_name → AmazonSageMakerFullAccess"
            else
                echo -e "  ${YELLOW}⚠${NC} $role_name missing AmazonSageMakerFullAccess (run 04-create-roles.sh to fix)"
                ((errors++)) || true
            fi
        done
    done
    
    # 4.3 验证 Training Roles（如果存在）
    verify_section "Training Roles (Training Jobs)"
    
    local training_role_count=0
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local train_role_name="SageMaker-${team_capitalized}-${project_formatted}-TrainingRole"
            
            if aws iam get-role --role-name "$train_role_name" &> /dev/null; then
                ((training_role_count++)) || true
                
                local train_trust=$(aws iam get-role --role-name "$train_role_name" \
                    --query 'Role.AssumeRolePolicyDocument.Statement[?Principal.Service==`sagemaker.amazonaws.com`]' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$train_trust" ]]; then
                    echo -e "  ${GREEN}✓${NC} $train_role_name (trust: sagemaker.amazonaws.com)"
                else
                    echo -e "  ${RED}✗${NC} $train_role_name trust policy issue"
                    ((errors++)) || true
                fi
            fi
        done
    done
    
    if [[ $training_role_count -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} No Training Roles found (ENABLE_TRAINING_ROLE=false or not yet created)"
    else
        echo -e "  Total: $training_role_count Training Roles"
    fi
    
    # 4.4 验证 Processing Roles（如果存在）
    verify_section "Processing Roles (Processing Jobs)"
    
    local processing_role_count=0
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local proc_role_name="SageMaker-${team_capitalized}-${project_formatted}-ProcessingRole"
            
            if aws iam get-role --role-name "$proc_role_name" &> /dev/null; then
                ((processing_role_count++)) || true
                
                local proc_trust=$(aws iam get-role --role-name "$proc_role_name" \
                    --query 'Role.AssumeRolePolicyDocument.Statement[?Principal.Service==`sagemaker.amazonaws.com`]' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$proc_trust" ]]; then
                    echo -e "  ${GREEN}✓${NC} $proc_role_name (trust: sagemaker.amazonaws.com)"
                else
                    echo -e "  ${RED}✗${NC} $proc_role_name trust policy issue"
                    ((errors++)) || true
                fi
            fi
        done
    done
    
    if [[ $processing_role_count -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} No Processing Roles found (ENABLE_PROCESSING_ROLE=false or not yet created)"
    else
        echo -e "  Total: $processing_role_count Processing Roles"
    fi
    
    # 4.5 验证 Inference Roles（如果存在）
    verify_section "Inference Roles (Production Deployment)"
    
    local inference_role_count=0
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(format_name "$team_fullname")
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local inf_role_name="SageMaker-${team_capitalized}-${project_formatted}-InferenceRole"
            
            # 检查 Inference Role 是否存在
            if aws iam get-role --role-name "$inf_role_name" &> /dev/null; then
                ((inference_role_count++)) || true
                
                # 检查 Trust Policy
                local inf_trust=$(aws iam get-role --role-name "$inf_role_name" \
                    --query 'Role.AssumeRolePolicyDocument.Statement[?Principal.Service==`sagemaker.amazonaws.com`]' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$inf_trust" ]]; then
                    echo -e "  ${GREEN}✓${NC} $inf_role_name (trust: sagemaker.amazonaws.com)"
                else
                    echo -e "  ${RED}✗${NC} $inf_role_name trust policy issue"
                    ((errors++)) || true
                fi
            fi
        done
    done
    
    if [[ $inference_role_count -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠${NC} No Inference Roles found (ENABLE_INFERENCE_ROLE=false or not yet created)"
    else
        echo -e "  Total: $inference_role_count Inference Roles"
    fi
    
    # 5. 验证用户组成员关系
    verify_section "User-Group Memberships"
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local users=$(get_users_for_project "$team" "$project")
            for user in $users; do
                local username="sm-${team}-${user}"
                
                # 检查团队组
                local team_group_members=$(aws iam get-group --group-name "sagemaker-${team_fullname}" \
                    --query 'Users[].UserName' --output text 2>/dev/null || echo "")
                
                local in_team=""
                if [[ " $team_group_members " =~ " ${username} " ]]; then
                    in_team="$username"
                fi
                
                # 检查项目组
                local project_group_members=$(aws iam get-group --group-name "sagemaker-${team}-${project}" \
                    --query 'Users[].UserName' --output text 2>/dev/null || echo "")
                
                local in_project=""
                if [[ " $project_group_members " =~ " ${username} " ]]; then
                    in_project="$username"
                fi
                
                if [[ -n "$in_team" && -n "$in_project" ]]; then
                    echo -e "  ${GREEN}✓${NC} $username → team + project groups"
                else
                    echo -e "  ${RED}✗${NC} $username missing group membership"
                    ((errors++)) || true
                fi
            done
        done
    done
    
    # 验证管理员组成员
    for admin in $ADMIN_USERS; do
        local username="sm-admin-${admin}"
        local admin_group_members=$(aws iam get-group --group-name "sagemaker-admins" \
            --query 'Users[].UserName' --output text 2>/dev/null || echo "")
            
        local in_admin=""
        if [[ " $admin_group_members " =~ " ${username} " ]]; then
            in_admin="$username"
        fi
        
        if [[ -n "$in_admin" ]]; then
            echo -e "  ${GREEN}✓${NC} $username → admin group"
        else
            echo -e "  ${RED}✗${NC} $username missing admin group membership"
            ((errors++)) || true
        fi
    done
    
    # 6. 验证策略绑定
    verify_section "Policy Bindings"
    
    # 检查管理员组绑定
    local admin_policy=$(aws iam list-attached-group-policies --group-name "sagemaker-admins" \
        --query 'AttachedPolicies[?PolicyName==`AmazonSageMakerFullAccess`].PolicyName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$admin_policy" ]]; then
        echo -e "  ${GREEN}✓${NC} sagemaker-admins → AmazonSageMakerFullAccess"
    else
        echo -e "  ${RED}✗${NC} sagemaker-admins missing AmazonSageMakerFullAccess"
        ((errors++)) || true
    fi
    
    # 列出实际资源
    list_actual_resources
    
    # 总结
    echo ""
    echo "=============================================="
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}Verification PASSED${NC} - All resources configured correctly"
    else
        echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
    fi
    echo "=============================================="
    echo ""
    echo "Quick filter commands:"
    echo "  aws iam list-policies --scope Local --path-prefix ${IAM_PATH}"
    echo "  aws iam list-groups --path-prefix ${IAM_PATH}"
    echo "  aws iam list-users --path-prefix ${IAM_PATH}"
    echo "  aws iam list-roles --query 'Roles[?starts_with(RoleName, \`SageMaker-\`)].RoleName'"
    echo ""
    
    return $errors
}

main
