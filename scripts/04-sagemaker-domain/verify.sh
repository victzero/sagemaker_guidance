#!/bin/bash
# =============================================================================
# verify.sh - 验证 SageMaker Domain 配置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

echo ""
echo "=============================================="
echo " SageMaker Domain Verification"
echo "=============================================="
echo ""

errors=0

# -----------------------------------------------------------------------------
# 辅助函数
# -----------------------------------------------------------------------------
verify_section() {
    echo ""
    echo -e "${BLUE}--- $1 ---${NC}"
}

# -----------------------------------------------------------------------------
# 加载 Domain 信息
# -----------------------------------------------------------------------------
DOMAIN_INFO_FILE="${SCRIPT_DIR}/${OUTPUT_DIR}/domain-info.env"
if [[ -f "$DOMAIN_INFO_FILE" ]]; then
    source "$DOMAIN_INFO_FILE"
fi

# 如果没有保存的 Domain ID，尝试查找
if [[ -z "$DOMAIN_ID" ]]; then
    DOMAIN_ID=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
fi

# -----------------------------------------------------------------------------
# 验证 Domain
# -----------------------------------------------------------------------------
verify_section "SageMaker Domain"

if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
    echo -e "  ${RED}✗${NC} Domain not found: $DOMAIN_NAME"
    ((errors++)) || true
else
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    local status=$(echo "$domain_info" | jq -r '.Status // "Unknown"')
    local auth_mode=$(echo "$domain_info" | jq -r '.AuthMode // "Unknown"')
    local network_mode=$(echo "$domain_info" | jq -r '.AppNetworkAccessType // "Unknown"')
    local vpc_id=$(echo "$domain_info" | jq -r '.VpcId // "Unknown"')
    local efs_id=$(echo "$domain_info" | jq -r '.HomeEfsFileSystemId // "Unknown"')
    
    if [[ "$status" == "InService" ]]; then
        echo -e "  ${GREEN}✓${NC} Domain: $DOMAIN_NAME ($DOMAIN_ID)"
        echo -e "      Status:       $status"
        echo -e "      Auth Mode:    $auth_mode"
        echo -e "      Network Mode: $network_mode"
        echo -e "      VPC:          $vpc_id"
        echo -e "      EFS:          $efs_id"
    else
        echo -e "  ${YELLOW}!${NC} Domain: $DOMAIN_NAME ($DOMAIN_ID)"
        echo -e "      Status:       $status (expected: InService)"
        ((errors++)) || true
    fi
    
    # 验证 Auth Mode
    if [[ "$auth_mode" != "IAM" ]]; then
        echo -e "  ${YELLOW}!${NC} Auth Mode: $auth_mode (expected: IAM)"
    fi
    
    # 验证 Network Mode
    if [[ "$network_mode" != "VpcOnly" ]]; then
        echo -e "  ${YELLOW}!${NC} Network Mode: $network_mode (expected: VpcOnly)"
    fi
fi

# -----------------------------------------------------------------------------
# 验证 Lifecycle Config
# -----------------------------------------------------------------------------
verify_section "Lifecycle Configuration"

local lcc_arn=$(aws sagemaker list-studio-lifecycle-configs \
    --query "StudioLifecycleConfigs[?StudioLifecycleConfigName=='${LIFECYCLE_CONFIG_NAME}'].StudioLifecycleConfigArn | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -z "$lcc_arn" || "$lcc_arn" == "None" ]]; then
    echo -e "  ${RED}✗${NC} Lifecycle Config not found: $LIFECYCLE_CONFIG_NAME"
    ((errors++)) || true
else
    echo -e "  ${GREEN}✓${NC} Lifecycle Config: $LIFECYCLE_CONFIG_NAME"
    echo -e "      ARN: $lcc_arn"
    echo -e "      Idle Timeout: ${IDLE_TIMEOUT_MINUTES} minutes"
fi

# -----------------------------------------------------------------------------
# 验证 Lifecycle Config 已绑定到 Domain
# -----------------------------------------------------------------------------
verify_section "Lifecycle Config Binding"

if [[ -n "$DOMAIN_ID" && "$DOMAIN_ID" != "None" ]]; then
    local default_settings=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --query 'DefaultUserSettings.JupyterLabAppSettings.LifecycleConfigArns' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$default_settings" && "$default_settings" != "None" ]]; then
        if echo "$default_settings" | grep -q "$LIFECYCLE_CONFIG_NAME"; then
            echo -e "  ${GREEN}✓${NC} Lifecycle Config bound to Domain"
        else
            echo -e "  ${YELLOW}!${NC} Lifecycle Config not bound (may need to run 03-attach-lifecycle.sh)"
        fi
    else
        echo -e "  ${YELLOW}!${NC} No Lifecycle Config bound to Domain"
    fi
fi

# -----------------------------------------------------------------------------
# 验证 EFS 加密
# -----------------------------------------------------------------------------
verify_section "EFS Encryption"

if [[ -n "$DOMAIN_ID" && "$DOMAIN_ID" != "None" ]]; then
    local efs_id=$(aws sagemaker describe-domain \
        --domain-id "$DOMAIN_ID" \
        --query 'HomeEfsFileSystemId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$efs_id" && "$efs_id" != "None" ]]; then
        local encrypted=$(aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --query 'FileSystems[0].Encrypted' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "Unknown")
        
        if [[ "$encrypted" == "True" ]]; then
            echo -e "  ${GREEN}✓${NC} EFS encrypted: $efs_id"
        else
            echo -e "  ${YELLOW}!${NC} EFS encryption: $encrypted"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ $errors -eq 0 ]]; then
    echo -e "${GREEN}Verification PASSED${NC} - Domain configured correctly"
else
    echo -e "${RED}Verification FAILED${NC} - $errors error(s) found"
fi
echo "=============================================="
echo ""
echo "Filter resources with:"
echo "  aws sagemaker list-domains"
echo "  aws sagemaker list-studio-lifecycle-configs"
echo ""

exit $errors

