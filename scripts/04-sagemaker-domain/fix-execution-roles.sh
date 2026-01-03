#!/bin/bash
# =============================================================================
# fix-execution-roles.sh - 修复 SageMaker Domain 和 User Profiles 的 Execution Role ARN
# =============================================================================
#
# 背景:
#   之前创建的 Execution Role 使用了 IAM_PATH（如 /acme-sagemaker/），
#   导致 Role ARN 为: arn:aws:iam::xxx:role/acme-sagemaker/RoleName
#   
#   但 SageMaker 服务在 AssumeRole 时通常使用默认路径，
#   新的 Role 创建时不再使用 IAM_PATH，ARN 为: arn:aws:iam::xxx:role/RoleName
#
#   此脚本用于修复已创建的 Domain 和 User Profiles，更新为正确的 Role ARN。
#
# 使用:
#   ./fix-execution-roles.sh
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# =============================================================================
# 全局变量 - 存储需要修复的资源
# =============================================================================
declare -a CHANGES_SUMMARY=()
DOMAIN_ID=""
DOMAIN_NEEDS_FIX=false
DOMAIN_CURRENT_DEFAULT_ROLE=""
DOMAIN_CURRENT_SPACE_ROLE=""
DOMAIN_CORRECT_ROLE=""

declare -a PROFILES_TO_FIX=()
declare -a PROFILES_CURRENT_ROLES=()
declare -a PROFILES_CORRECT_ROLES=()

# =============================================================================
# 辅助函数
# =============================================================================

# 获取正确的 Role ARN（不带 path）
get_correct_role_arn() {
    local role_name=$1
    aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo ""
}

# 打印分隔线
print_separator() {
    echo "────────────────────────────────────────────────────────────────────────────────"
}

# =============================================================================
# 第一步：扫描所有资源
# =============================================================================

scan_resources() {
    echo ""
    echo "=============================================="
    echo " 扫描 SageMaker 资源"
    echo "=============================================="
    echo ""
    
    # 获取 Domain ID
    DOMAIN_ID=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
        log_warn "未找到 Domain: $DOMAIN_NAME"
        return 0
    fi
    
    log_info "找到 Domain: $DOMAIN_ID"
    
    # 获取正确的 Role ARN
    DOMAIN_CORRECT_ROLE=$(get_correct_role_arn "SageMaker-Domain-DefaultExecutionRole")
    
    if [[ -z "$DOMAIN_CORRECT_ROLE" ]]; then
        log_error "Role SageMaker-Domain-DefaultExecutionRole 不存在!"
        log_error "请先运行: cd ../01-iam && ./04-create-roles.sh"
        exit 1
    fi
    
    # 扫描 Domain
    scan_domain
    
    # 扫描 User Profiles
    scan_user_profiles
}

scan_domain() {
    log_info "扫描 Domain 配置..."
    
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION")
    
    DOMAIN_CURRENT_DEFAULT_ROLE=$(echo "$domain_info" | jq -r '.DefaultUserSettings.ExecutionRole // ""')
    DOMAIN_CURRENT_SPACE_ROLE=$(echo "$domain_info" | jq -r '.DefaultSpaceSettings.ExecutionRole // ""')
    
    if [[ "$DOMAIN_CURRENT_DEFAULT_ROLE" != "$DOMAIN_CORRECT_ROLE" ]] || \
       [[ "$DOMAIN_CURRENT_SPACE_ROLE" != "$DOMAIN_CORRECT_ROLE" ]]; then
        DOMAIN_NEEDS_FIX=true
    fi
}

scan_user_profiles() {
    log_info "扫描 User Profiles..."
    
    local profiles=$(aws sagemaker list-user-profiles \
        --domain-id "$DOMAIN_ID" \
        --query 'UserProfiles[].UserProfileName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$profiles" ]]; then
        log_info "未找到 User Profiles"
        return 0
    fi
    
    for profile_name in $profiles; do
        local profile_info=$(aws sagemaker describe-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile_name" \
            --region "$AWS_REGION" 2>/dev/null || echo "{}")
        
        local current_role=$(echo "$profile_info" | jq -r '.UserSettings.ExecutionRole // ""')
        
        # 跳过没有自定义 Role 的 Profile（使用 Domain 默认值）
        if [[ -z "$current_role" || "$current_role" == "null" ]]; then
            continue
        fi
        
        # 从当前 ARN 提取 Role 名称
        local role_name=$(echo "$current_role" | awk -F'/' '{print $NF}')
        local correct_role=$(get_correct_role_arn "$role_name")
        
        if [[ -z "$correct_role" ]]; then
            log_warn "  Profile $profile_name: Role $role_name 不存在，跳过"
            continue
        fi
        
        if [[ "$current_role" != "$correct_role" ]]; then
            PROFILES_TO_FIX+=("$profile_name")
            PROFILES_CURRENT_ROLES+=("$current_role")
            PROFILES_CORRECT_ROLES+=("$correct_role")
        fi
    done
}

# =============================================================================
# 第二步：显示变更计划
# =============================================================================

show_changes_plan() {
    echo ""
    echo "=============================================="
    echo " 变更计划"
    echo "=============================================="
    echo ""
    
    local has_changes=false
    
    # Domain 变更
    if [[ "$DOMAIN_NEEDS_FIX" == "true" ]]; then
        has_changes=true
        echo "【Domain: $DOMAIN_ID】"
        print_separator
        printf "| %-20s | %-70s |\n" "配置项" "值"
        print_separator
        
        if [[ "$DOMAIN_CURRENT_DEFAULT_ROLE" != "$DOMAIN_CORRECT_ROLE" ]]; then
            printf "| %-20s | %-70s |\n" "Default Role (当前)" "$DOMAIN_CURRENT_DEFAULT_ROLE"
            printf "| %-20s | %-70s |\n" "Default Role (修复后)" "$DOMAIN_CORRECT_ROLE"
            print_separator
        fi
        
        if [[ "$DOMAIN_CURRENT_SPACE_ROLE" != "$DOMAIN_CORRECT_ROLE" ]]; then
            printf "| %-20s | %-70s |\n" "Space Role (当前)" "$DOMAIN_CURRENT_SPACE_ROLE"
            printf "| %-20s | %-70s |\n" "Space Role (修复后)" "$DOMAIN_CORRECT_ROLE"
            print_separator
        fi
        echo ""
    fi
    
    # User Profiles 变更
    if [[ ${#PROFILES_TO_FIX[@]} -gt 0 ]]; then
        has_changes=true
        echo "【User Profiles: ${#PROFILES_TO_FIX[@]} 个需要修复】"
        print_separator
        printf "| %-25s | %-80s |\n" "Profile" "Execution Role"
        print_separator
        
        for i in "${!PROFILES_TO_FIX[@]}"; do
            local profile="${PROFILES_TO_FIX[$i]}"
            local current="${PROFILES_CURRENT_ROLES[$i]}"
            local correct="${PROFILES_CORRECT_ROLES[$i]}"
            
            printf "| %-25s | %-80s |\n" "$profile (当前)" "$current"
            printf "| %-25s | %-80s |\n" "$profile (修复后)" "$correct"
            print_separator
        done
        echo ""
    fi
    
    if [[ "$has_changes" == "false" ]]; then
        echo ""
        log_success "所有资源配置正确，无需修复！"
        echo ""
        return 1
    fi
    
    # 显示变更摘要
    echo "【变更摘要】"
    print_separator
    
    local total_changes=0
    
    if [[ "$DOMAIN_NEEDS_FIX" == "true" ]]; then
        local domain_changes=0
        [[ "$DOMAIN_CURRENT_DEFAULT_ROLE" != "$DOMAIN_CORRECT_ROLE" ]] && ((domain_changes++))
        [[ "$DOMAIN_CURRENT_SPACE_ROLE" != "$DOMAIN_CORRECT_ROLE" ]] && ((domain_changes++))
        echo "  • Domain: $domain_changes 项配置将被更新"
        ((total_changes+=domain_changes))
    fi
    
    if [[ ${#PROFILES_TO_FIX[@]} -gt 0 ]]; then
        echo "  • User Profiles: ${#PROFILES_TO_FIX[@]} 个将被更新"
        ((total_changes+=${#PROFILES_TO_FIX[@]}))
    fi
    
    print_separator
    echo "  总计: $total_changes 项变更"
    echo ""
    
    return 0
}

# =============================================================================
# 第三步：执行修复
# =============================================================================

execute_fixes() {
    echo ""
    echo "=============================================="
    echo " 执行修复"
    echo "=============================================="
    echo ""
    
    local success=0
    local failed=0
    
    # 修复 Domain
    if [[ "$DOMAIN_NEEDS_FIX" == "true" ]]; then
        log_info "更新 Domain: $DOMAIN_ID"
        
        if aws sagemaker update-domain \
            --domain-id "$DOMAIN_ID" \
            --default-user-settings "{\"ExecutionRole\": \"${DOMAIN_CORRECT_ROLE}\"}" \
            --default-space-settings "{\"ExecutionRole\": \"${DOMAIN_CORRECT_ROLE}\"}" \
            --region "$AWS_REGION" > /dev/null 2>&1; then
            log_success "  Domain 更新成功"
            ((success++))
        else
            log_error "  Domain 更新失败"
            ((failed++))
        fi
    fi
    
    # 修复 User Profiles
    for i in "${!PROFILES_TO_FIX[@]}"; do
        local profile="${PROFILES_TO_FIX[$i]}"
        local correct="${PROFILES_CORRECT_ROLES[$i]}"
        
        log_info "更新 Profile: $profile"
        
        if aws sagemaker update-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile" \
            --user-settings "{\"ExecutionRole\": \"${correct}\"}" \
            --region "$AWS_REGION" > /dev/null 2>&1; then
            log_success "  Profile 更新成功"
            ((success++))
        else
            log_error "  Profile 更新失败"
            ((failed++))
        fi
    done
    
    echo ""
    print_separator
    echo "执行结果: 成功 $success, 失败 $failed"
    print_separator
    
    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# 第四步：验证修复结果
# =============================================================================

verify_fixes() {
    echo ""
    echo "=============================================="
    echo " 验证修复结果"
    echo "=============================================="
    echo ""
    
    local all_ok=true
    
    # 验证 Domain
    if [[ "$DOMAIN_NEEDS_FIX" == "true" ]]; then
        log_info "验证 Domain..."
        
        local domain_info=$(aws sagemaker describe-domain \
            --domain-id "$DOMAIN_ID" \
            --region "$AWS_REGION")
        
        local new_default=$(echo "$domain_info" | jq -r '.DefaultUserSettings.ExecutionRole // ""')
        local new_space=$(echo "$domain_info" | jq -r '.DefaultSpaceSettings.ExecutionRole // ""')
        
        if [[ "$new_default" == "$DOMAIN_CORRECT_ROLE" ]]; then
            log_success "  Default Execution Role: ✓"
        else
            log_error "  Default Execution Role: ✗"
            all_ok=false
        fi
        
        if [[ "$new_space" == "$DOMAIN_CORRECT_ROLE" ]]; then
            log_success "  Space Execution Role: ✓"
        else
            log_error "  Space Execution Role: ✗"
            all_ok=false
        fi
    fi
    
    # 验证 User Profiles
    for i in "${!PROFILES_TO_FIX[@]}"; do
        local profile="${PROFILES_TO_FIX[$i]}"
        local correct="${PROFILES_CORRECT_ROLES[$i]}"
        
        log_info "验证 Profile: $profile"
        
        local profile_info=$(aws sagemaker describe-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile" \
            --region "$AWS_REGION" 2>/dev/null || echo "{}")
        
        local new_role=$(echo "$profile_info" | jq -r '.UserSettings.ExecutionRole // ""')
        
        if [[ "$new_role" == "$correct" ]]; then
            log_success "  Execution Role: ✓"
        else
            log_error "  Execution Role: ✗ (期望: $correct, 实际: $new_role)"
            all_ok=false
        fi
    done
    
    echo ""
    if [[ "$all_ok" == "true" ]]; then
        log_success "所有修复已验证通过！"
    else
        log_error "部分修复验证失败，请检查"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║           修复 SageMaker Execution Role ARN                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "此脚本将修复 Execution Role ARN 中的路径问题："
    echo ""
    echo "  问题: arn:aws:iam::xxx:role/acme-sagemaker/SageMaker-...-ExecutionRole"
    echo "  修复: arn:aws:iam::xxx:role/SageMaker-...-ExecutionRole"
    echo ""
    
    # 第一步：扫描资源
    scan_resources
    
    # 第二步：显示变更计划
    if ! show_changes_plan; then
        exit 0
    fi
    
    # 第三步：确认执行
    echo ""
    echo -e "${YELLOW}是否执行以上变更？${NC}"
    read -p "输入 'yes' 确认执行: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo ""
        log_info "已取消操作"
        exit 0
    fi
    
    # 第四步：执行修复
    execute_fixes
    
    # 第五步：验证结果
    verify_fixes
    
    echo ""
    echo "=============================================="
    echo " 后续步骤"
    echo "=============================================="
    echo ""
    echo "  1. 刷新 SageMaker Studio 控制台页面"
    echo "  2. 重新启动 JupyterLab 应用"
    echo ""
}

main
