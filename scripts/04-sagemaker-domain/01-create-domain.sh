#!/bin/bash
# =============================================================================
# 01-create-domain.sh - 创建 SageMaker Domain
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Creating SageMaker Domain"
    echo "=============================================="
    echo ""
    
    # 检查 Domain 是否已存在
    log_info "Checking for existing Domain: $DOMAIN_NAME"
    
    local existing_domain=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$existing_domain" && "$existing_domain" != "None" ]]; then
        log_warn "Domain $DOMAIN_NAME already exists: $existing_domain"
        
        # 获取 Domain 状态
        local status=$(aws sagemaker describe-domain \
            --domain-id "$existing_domain" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION")
        
        if [[ "$status" == "InService" ]]; then
            log_success "Domain is already InService"
            DOMAIN_ID="$existing_domain"
        else
            log_info "Domain status: $status (waiting for InService...)"
            wait_for_domain "$existing_domain"
            DOMAIN_ID="$existing_domain"
        fi
    else
        # 创建 Domain
        log_info "Creating Domain: $DOMAIN_NAME"
        
        # 获取 Domain 默认 Execution Role ARN
        local default_role_arn=$(aws iam get-role \
            --role-name "SageMaker-Domain-DefaultExecutionRole" \
            --query 'Role.Arn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -z "$default_role_arn" ]]; then
            log_error "Domain default execution role not found!"
            log_error "Please run: cd ../01-iam && ./04-create-roles.sh"
            exit 1
        fi
        
        log_info "Using execution role: $default_role_arn"
        
        local default_user_settings=$(cat <<EOF
{
    "ExecutionRole": "${default_role_arn}",
    "SecurityGroups": ["${SG_SAGEMAKER_STUDIO}"],
    "DefaultLandingUri": "studio::",
    "StudioWebPortal": "ENABLED",
    "JupyterLabAppSettings": {
        "DefaultResourceSpec": {
            "InstanceType": "${DEFAULT_INSTANCE_TYPE}"
        }
    }
}
EOF
)
        
        # DefaultSpaceSettings is required for creating Shared Spaces
        local default_space_settings=$(cat <<EOF
{
    "ExecutionRole": "${default_role_arn}"
}
EOF
)
        
        DOMAIN_ID=$(aws sagemaker create-domain \
            --domain-name "$DOMAIN_NAME" \
            --auth-mode IAM \
            --vpc-id "$VPC_ID" \
            --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
            --app-network-access-type VpcOnly \
            --default-user-settings "$default_user_settings" \
            --default-space-settings "$default_space_settings" \
            --tags \
                Key=Name,Value="$DOMAIN_NAME" \
                Key=Environment,Value=production \
                Key=ManagedBy,Value="${TAG_PREFIX}" \
            --query 'DomainArn' \
            --output text \
            --region "$AWS_REGION")
        
        # 提取 Domain ID
        DOMAIN_ID=$(echo "$DOMAIN_ID" | awk -F'/' '{print $NF}')
        
        log_info "Domain created, waiting for InService status..."
        wait_for_domain "$DOMAIN_ID"
    fi
    
    # 获取 Domain 详细信息
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION")
    
    local efs_id=$(echo "$domain_info" | jq -r '.HomeEfsFileSystemId')
    local domain_url=$(echo "$domain_info" | jq -r '.Url // "N/A"')
    
    # 保存 Domain 信息
    cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/domain-info.env" << EOF
# SageMaker Domain Info - Generated $(date)
DOMAIN_ID=${DOMAIN_ID}
DOMAIN_NAME=${DOMAIN_NAME}
DOMAIN_EFS_ID=${efs_id}
DOMAIN_URL=${domain_url}
VPC_ID=${VPC_ID}
SG_SAGEMAKER_STUDIO=${SG_SAGEMAKER_STUDIO}
EOF
    
    echo ""
    log_success "Domain created successfully!"
    echo ""
    echo "Domain Summary:"
    echo "  Domain ID:    $DOMAIN_ID"
    echo "  Domain Name:  $DOMAIN_NAME"
    echo "  EFS ID:       $efs_id"
    echo "  VPC ID:       $VPC_ID"
    echo "  Network Mode: VpcOnly"
    echo ""
    echo "Info saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/domain-info.env"
}

# -----------------------------------------------------------------------------
# 等待 Domain 变为 InService 状态
# -----------------------------------------------------------------------------
wait_for_domain() {
    local domain_id=$1
    local max_wait=600  # 10 minutes
    local waited=0
    local interval=15
    
    while [[ $waited -lt $max_wait ]]; do
        local status=$(aws sagemaker describe-domain \
            --domain-id "$domain_id" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION")
        
        case "$status" in
            InService)
                log_success "Domain is InService"
                return 0
                ;;
            Creating|Pending|Updating)
                echo -n "."
                sleep $interval
                ((waited+=interval))
                ;;
            Failed|Deleting|Delete_Failed)
                log_error "Domain status: $status"
                exit 1
                ;;
            *)
                log_warn "Unknown status: $status"
                sleep $interval
                ((waited+=interval))
                ;;
        esac
    done
    
    echo ""
    log_error "Timeout waiting for Domain to be InService"
    exit 1
}

main

