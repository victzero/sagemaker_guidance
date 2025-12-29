#!/bin/bash
# =============================================================================
# 00-init.sh - User Profiles 脚本初始化
# =============================================================================
# 使用方法: source 00-init.sh
# =============================================================================

set -e

# 设置脚本目录（供 common.sh 使用）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载共享函数库
source "${SCRIPT_DIR}/../common.sh"

# -----------------------------------------------------------------------------
# 加载 Domain 信息
# -----------------------------------------------------------------------------
load_domain_info() {
    local domain_info_file="${SCRIPT_DIR}/../04-sagemaker-domain/output/domain-info.env"
    
    # 首先尝试从文件加载
    if [[ -f "$domain_info_file" ]]; then
        log_info "Loading Domain info from 04-sagemaker-domain/output"
        source "$domain_info_file"
    fi
    
    # 如果没有 DOMAIN_ID，尝试查找
    if [[ -z "$DOMAIN_ID" ]]; then
        local domain_name="${DOMAIN_NAME:-${COMPANY}-ml-platform}"
        log_info "Looking up Domain: $domain_name"
        
        DOMAIN_ID=$(aws sagemaker list-domains \
            --query "Domains[?DomainName=='${domain_name}'].DomainId | [0]" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
            log_error "Domain not found: $domain_name"
            log_info "Please run 04-sagemaker-domain/setup-all.sh first"
            exit 1
        fi
        
        export DOMAIN_NAME="$domain_name"
    fi
    
    export DOMAIN_ID
    log_success "Domain ID: $DOMAIN_ID"
}

# -----------------------------------------------------------------------------
# 验证 Execution Roles 存在
# -----------------------------------------------------------------------------
validate_execution_roles() {
    log_info "Validating Execution Roles..."
    
    local iam_path="/${COMPANY}-sagemaker/"
    local missing=0
    
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_formatted=$(format_name "$team_fullname")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
            
            if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
                log_warn "Execution Role not found: $role_name"
                ((missing++)) || true
            fi
        done
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing Execution Role(s)"
        log_info "Please run 01-iam/setup-all.sh first"
        exit 1
    fi
    
    log_success "Execution Roles validated"
}

# -----------------------------------------------------------------------------
# User Profiles 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_profiles_summary() {
    echo "  Domain ID:    $DOMAIN_ID"
    echo "  Domain Name:  ${DOMAIN_NAME:-${COMPANY}-ml-platform}"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " User Profiles Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_team_env
    check_aws_cli
    load_domain_info
    validate_execution_roles
    ensure_output_dir
    
    # 设置默认配置
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    
    print_config_summary "User Profiles" print_profiles_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

