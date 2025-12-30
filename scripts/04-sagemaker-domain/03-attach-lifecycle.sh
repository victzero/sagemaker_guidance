#!/bin/bash
# =============================================================================
# 03-attach-lifecycle.sh - 绑定 Lifecycle Config 到 Domain
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 加载 Domain 和 Lifecycle 信息
# -----------------------------------------------------------------------------
load_domain_info() {
    local domain_info_file="${SCRIPT_DIR}/${OUTPUT_DIR}/domain-info.env"
    local lifecycle_info_file="${SCRIPT_DIR}/${OUTPUT_DIR}/lifecycle-config.env"
    
    if [[ ! -f "$domain_info_file" ]]; then
        log_error "Domain info not found: $domain_info_file"
        log_info "Please run 01-create-domain.sh first"
        exit 1
    fi
    
    if [[ ! -f "$lifecycle_info_file" ]]; then
        log_error "Lifecycle config info not found: $lifecycle_info_file"
        log_info "Please run 02-create-lifecycle-config.sh first"
        exit 1
    fi
    
    source "$domain_info_file"
    source "$lifecycle_info_file"
    
    if [[ -z "$DOMAIN_ID" ]]; then
        log_error "DOMAIN_ID not set"
        exit 1
    fi
    
    if [[ -z "$LIFECYCLE_CONFIG_ARN" ]]; then
        log_error "LIFECYCLE_CONFIG_ARN not set"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Attaching Lifecycle Config to Domain"
    echo "=============================================="
    echo ""
    
    load_domain_info
    
    log_info "Domain ID:          $DOMAIN_ID"
    log_info "Lifecycle Config:   $LIFECYCLE_CONFIG_NAME"
    log_info "Default Instance:   $DEFAULT_INSTANCE_TYPE"
    
    # 更新 Domain 默认设置
    log_info "Updating Domain default settings..."
    
    local user_settings=$(cat <<EOF
{
    "JupyterLabAppSettings": {
        "DefaultResourceSpec": {
            "InstanceType": "${DEFAULT_INSTANCE_TYPE}",
            "LifecycleConfigArn": "${LIFECYCLE_CONFIG_ARN}"
        },
        "LifecycleConfigArns": ["${LIFECYCLE_CONFIG_ARN}"]
    }
}
EOF
)
    
    aws sagemaker update-domain \
        --domain-id "$DOMAIN_ID" \
        --default-user-settings "$user_settings" \
        --region "$AWS_REGION"
    
    log_success "Domain updated with Lifecycle Config"
    
    # 等待 Domain 更新完成
    log_info "Waiting for Domain update to complete..."
    
    local max_wait=120
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        local status=$(aws sagemaker describe-domain \
            --domain-id "$DOMAIN_ID" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION")
        
        if [[ "$status" == "InService" ]]; then
            break
        fi
        
        echo -n "."
        sleep 5
        ((waited+=5))
    done
    echo ""
    
    if [[ $waited -ge $max_wait ]]; then
        log_warn "Domain may still be updating"
    else
        log_success "Domain update complete"
    fi
    
    echo ""
    echo "Configuration Summary:"
    echo "  Domain ID:          $DOMAIN_ID"
    echo "  Lifecycle Config:   $LIFECYCLE_CONFIG_NAME"
    echo "  Idle Timeout:       ${IDLE_TIMEOUT_MINUTES} minutes"
    echo "  Default Instance:   $DEFAULT_INSTANCE_TYPE"
    echo ""
    echo "All new JupyterLab Apps will automatically shut down after"
    echo "${IDLE_TIMEOUT_MINUTES} minutes of inactivity."
}

main

