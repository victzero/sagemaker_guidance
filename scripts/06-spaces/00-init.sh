#!/bin/bash
# =============================================================================
# 00-init.sh - Shared Spaces 脚本初始化
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
# 验证 User Profiles 存在
# -----------------------------------------------------------------------------
validate_user_profiles() {
    log_info "Validating User Profiles..."
    
    local missing=0
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local users=$(get_users_for_project "$team" "$project")
            local first_user=$(echo "$users" | awk '{print $1}')
            
            if [[ -n "$first_user" ]]; then
                local profile_name="profile-${team}-${first_user}"
                
                if ! aws sagemaker describe-user-profile \
                    --domain-id "$DOMAIN_ID" \
                    --user-profile-name "$profile_name" \
                    --region "$AWS_REGION" &> /dev/null; then
                    log_warn "User Profile not found: $profile_name"
                    ((missing++)) || true
                fi
            fi
        done
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing User Profile(s)"
        log_info "Please run 05-user-profiles/setup-all.sh first"
        exit 1
    fi
    
    log_success "User Profiles validated"
}

# -----------------------------------------------------------------------------
# Spaces 配置摘要（回调函数）
# -----------------------------------------------------------------------------
print_spaces_summary() {
    echo "  Domain ID:    $DOMAIN_ID"
    echo "  Domain Name:  ${DOMAIN_NAME:-${COMPANY}-ml-platform}"
    echo "  EBS Size:     ${SPACE_EBS_SIZE_GB:-50} GB"
}

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
init() {
    echo "=============================================="
    echo " Shared Spaces Setup - Initialization"
    echo "=============================================="
    
    load_env
    validate_base_env
    validate_team_env
    check_aws_cli
    load_domain_info
    validate_user_profiles
    ensure_output_dir
    
    # 设置默认配置
    export TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    export SPACE_EBS_SIZE_GB="${SPACE_EBS_SIZE_GB:-50}"
    
    print_config_summary "Shared Spaces" print_spaces_summary
    
    log_success "Initialization complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init
fi

