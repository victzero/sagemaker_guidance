#!/bin/bash
# =============================================================================
# verify-deny-policy.sh - 验证 DenyCrossProject 策略配置
# =============================================================================
# 用法: ./verify-deny-policy.sh [team] [project]
#       ./verify-deny-policy.sh rc fraud
#
# 检查项:
#   1. 策略是否存在
#   2. 策略文档是否包含 NotResource (正确) 或 Condition (错误)
#   3. 策略是否已附加到 ExecutionRole
#   4. 策略版本号
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

source "${SCRIPTS_ROOT}/lib/iam-core.sh"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_check() {
    local status=$1
    local message=$2
    if [[ "$status" == "OK" ]]; then
        echo -e "  [${GREEN}✓${NC}] $message"
    elif [[ "$status" == "WARN" ]]; then
        echo -e "  [${YELLOW}!${NC}] $message"
    else
        echo -e "  [${RED}✗${NC}] $message"
    fi
}

# 验证单个项目
verify_project() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-DenyCrossProject"
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${CYAN}Verifying: ${team}/${project}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 1. 检查策略是否存在
    echo ""
    echo "1. Policy Existence:"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        print_check "OK" "Policy exists: $policy_name"
        
        # 获取默认版本
        local default_version=$(aws iam get-policy \
            --policy-arn "$policy_arn" \
            --query 'Policy.DefaultVersionId' \
            --output text)
        print_check "OK" "Default version: $default_version"
    else
        print_check "FAIL" "Policy NOT FOUND: $policy_name"
        echo ""
        echo -e "  ${RED}Suggestion: Run ./01-create-policies.sh --force${NC}"
        return 1
    fi
    
    # 2. 检查策略文档内容
    echo ""
    echo "2. Policy Document Analysis:"
    local policy_doc=$(aws iam get-policy-version \
        --policy-arn "$policy_arn" \
        --version-id "$default_version" \
        --query 'PolicyVersion.Document' \
        --output json 2>/dev/null || echo "{}")
    
    # 检查是否使用 NotResource (正确)
    if echo "$policy_doc" | grep -q '"NotResource"'; then
        print_check "OK" "Uses NotResource (CORRECT implementation)"
    else
        print_check "FAIL" "Does NOT use NotResource"
    fi
    
    # 检查是否使用错误的 Condition (sagemaker:ResourceArn)
    if echo "$policy_doc" | grep -q '"sagemaker:ResourceArn"'; then
        print_check "FAIL" "Uses invalid condition key 'sagemaker:ResourceArn' (BROKEN!)"
        echo ""
        echo -e "  ${RED}This condition key does NOT exist in AWS SageMaker!${NC}"
        echo -e "  ${RED}The Deny policy will NOT take effect!${NC}"
        echo ""
        echo -e "  ${YELLOW}SOLUTION: Update policy template and run:${NC}"
        echo "    ./01-create-policies.sh --force"
    else
        print_check "OK" "No invalid condition keys found"
    fi
    
    # 显示第一个 Statement 的结构
    echo ""
    echo "  First Statement (DenyDeleteOtherProjectModels):"
    echo "$policy_doc" | jq -r '.Statement[0] | "    Effect: \(.Effect)\n    Action: \(.Action | if type == "array" then .[0] else . end)\n    NotResource: \(.NotResource // "N/A")\n    Resource: \(.Resource // "N/A")"' 2>/dev/null || echo "    (unable to parse)"
    
    # 3. 检查策略是否已附加到 Role
    echo ""
    echo "3. Policy Attachment:"
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        print_check "OK" "Role exists: $role_name"
        
        local attached=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query "AttachedPolicies[?PolicyName=='${policy_name}'].PolicyName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached" ]]; then
            print_check "OK" "DenyCrossProject policy is ATTACHED to Role"
        else
            print_check "FAIL" "DenyCrossProject policy is NOT attached to Role"
            echo ""
            echo -e "  ${YELLOW}SOLUTION: Run ./04-create-roles.sh to attach policy${NC}"
        fi
    else
        print_check "WARN" "Role not found: $role_name"
    fi
    
    # 4. 总结
    echo ""
    echo "4. Summary:"
    if echo "$policy_doc" | grep -q '"NotResource"' && [[ -n "$attached" ]]; then
        print_check "OK" "Policy is correctly configured and attached"
        echo ""
        echo -e "  ${GREEN}Cross-project resource isolation is ACTIVE${NC}"
    else
        print_check "FAIL" "Policy configuration needs fixing"
        echo ""
        echo -e "  ${RED}Cross-project resource isolation is NOT working${NC}"
    fi
}

# 主函数
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║          DenyCrossProject Policy Verification                            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    
    if [[ -n "$1" && -n "$2" ]]; then
        # 验证指定项目
        verify_project "$1" "$2"
    else
        # 验证所有项目
        for team in $TEAMS; do
            local projects=$(get_projects_for_team "$team")
            for project in $projects; do
                verify_project "$team" "$project"
            done
        done
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Verification Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "If any issues found, run these commands in order:"
    echo ""
    echo "  1. cd scripts/01-iam"
    echo "  2. ./01-create-policies.sh --force"
    echo "  3. ./04-create-roles.sh"
    echo "  4. ./verify-deny-policy.sh"
    echo ""
}

main "$@"

