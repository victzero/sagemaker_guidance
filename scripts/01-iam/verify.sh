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
    
    ACTUAL_POLICIES=$(aws iam list-policies --scope Local --path-prefix "${IAM_PATH}" \
        --query 'length(Policies)' --output text 2>/dev/null || echo "0")
    
    ACTUAL_GROUPS=$(aws iam list-groups --path-prefix "${IAM_PATH}" \
        --query 'length(Groups)' --output text 2>/dev/null || echo "0")
    
    ACTUAL_USERS=$(aws iam list-users --path-prefix "${IAM_PATH}" \
        --query 'length(Users)' --output text 2>/dev/null || echo "0")
    
    ACTUAL_ROLES=$(aws iam list-roles --path-prefix "${IAM_PATH}" \
        --query 'length(Roles)' --output text 2>/dev/null || echo "0")
    
    echo ""
    echo "Resource Summary:"
    echo "  +-----------------+----------+----------+"
    echo "  | Resource        | Expected | Actual   |"
    echo "  +-----------------+----------+----------+"
    printf "  | %-15s | %8d | %8d |\n" "Policies" "$EXPECTED_POLICIES" "$ACTUAL_POLICIES"
    printf "  | %-15s | %8d | %8d |\n" "Groups" "$EXPECTED_GROUPS" "$ACTUAL_GROUPS"
    printf "  | %-15s | %8d | %8d |\n" "Users" "$EXPECTED_USERS" "$ACTUAL_USERS"
    printf "  | %-15s | %8d | %8d |\n" "Roles" "$EXPECTED_ROLES" "$ACTUAL_ROLES"
    echo "  +-----------------+----------+----------+"
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
    echo "Roles (path: ${IAM_PATH}):"
    aws iam list-roles --path-prefix "${IAM_PATH}" \
        --query 'Roles[].RoleName' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /' || echo "  (none)"
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
            verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-${project_formatted}-ExecutionPolicy" || ((errors++))
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
    
    # 4.1 验证 Execution Roles 的 AmazonSageMakerFullAccess 策略（Phase 2 ML Jobs 支持）
    verify_section "Execution Roles - AmazonSageMakerFullAccess (ML Jobs)"
    
    # Domain 默认角色
    local domain_sm_policy=$(aws iam list-attached-role-policies \
        --role-name "SageMaker-Domain-DefaultExecutionRole" \
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
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
                --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$sm_policy" ]]; then
                echo -e "  ${GREEN}✓${NC} $role_name → AmazonSageMakerFullAccess"
            else
                echo -e "  ${YELLOW}⚠${NC} $role_name missing AmazonSageMakerFullAccess (run 04-create-roles.sh to fix)"
                ((errors++)) || true
            fi
        done
    done
    
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
                local in_team=$(aws iam get-group --group-name "sagemaker-${team_fullname}" \
                    --query "Users[?UserName=='${username}'].UserName" --output text 2>/dev/null || echo "")
                
                # 检查项目组
                local in_project=$(aws iam get-group --group-name "sagemaker-${team}-${project}" \
                    --query "Users[?UserName=='${username}'].UserName" --output text 2>/dev/null || echo "")
                
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
        local in_admin=$(aws iam get-group --group-name "sagemaker-admins" \
            --query "Users[?UserName=='${username}'].UserName" --output text 2>/dev/null || echo "")
        
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
        --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" --output text 2>/dev/null || echo "")
    
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
    echo "  aws iam list-roles --path-prefix ${IAM_PATH}"
    echo ""
    
    return $errors
}

main
