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
# 主函数
# -----------------------------------------------------------------------------
main() {
    local errors=0
    local policy_prefix="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}"
    
    # 1. 验证策略
    verify_section "IAM Policies"
    
    verify_resource policy "${policy_prefix}SageMaker-Studio-Base-Access" || ((errors++))
    verify_resource policy "${policy_prefix}SageMaker-ReadOnly-Access" || ((errors++))
    verify_resource policy "${policy_prefix}SageMaker-User-Boundary" || ((errors++))
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(echo "$team_fullname" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
        
        verify_resource policy "${policy_prefix}SageMaker-${team_capitalized}-Team-Access" || ((errors++))
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(echo "$project" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
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
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_capitalized=$(echo "$team_fullname" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local project_formatted=$(echo "$project" | sed -e 's/-/ /g' -e 's/\b\w/\u&/g' | tr -d ' ')
            verify_resource role "SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole" || ((errors++))
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
                    ((errors++))
                fi
            done
        done
    done
    
    # 总结
    echo ""
    echo "=============================================="
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}Verification PASSED${NC} - All resources configured correctly"
    else
        echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
    fi
    echo "=============================================="
    
    return $errors
}

main
