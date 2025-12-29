#!/bin/bash
# =============================================================================
# cleanup.sh - 清理 SageMaker Domain 资源 (危险操作!)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

echo ""
echo -e "${RED}=============================================="
echo " WARNING: SageMaker Domain Cleanup"
echo "==============================================${NC}"
echo ""
echo "This will DELETE the following resources:"
echo "  - SageMaker Domain: $DOMAIN_NAME"
echo "  - All User Profiles in the Domain"
echo "  - All Spaces in the Domain"
echo "  - All Apps in the Domain"
echo "  - EFS file system (user home directories)"
echo "  - Lifecycle Configuration: $LIFECYCLE_CONFIG_NAME"
echo ""

if [[ "$FORCE" != "true" ]]; then
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo -e "${RED}ALL USER DATA WILL BE LOST!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# 获取 Domain ID
# -----------------------------------------------------------------------------
DOMAIN_ID=$(aws sagemaker list-domains \
    --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -z "$DOMAIN_ID" || "$DOMAIN_ID" == "None" ]]; then
    log_warn "Domain $DOMAIN_NAME not found, skipping Domain cleanup"
    DOMAIN_ID=""
fi

# -----------------------------------------------------------------------------
# 删除所有 Apps
# -----------------------------------------------------------------------------
if [[ -n "$DOMAIN_ID" ]]; then
    log_info "Step 1: Deleting all Apps in Domain..."
    
    # 获取所有 Apps
    apps=$(aws sagemaker list-apps \
        --domain-id "$DOMAIN_ID" \
        --query 'Apps[?Status!=`Deleted`].[UserProfileName,SpaceName,AppType,AppName]' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    while IFS=$'\t' read -r user_profile space_name app_type app_name; do
        [[ -z "$app_name" ]] && continue
        
        log_info "Deleting App: $app_type/$app_name"
        
        if [[ -n "$space_name" && "$space_name" != "None" ]]; then
            aws sagemaker delete-app \
                --domain-id "$DOMAIN_ID" \
                --space-name "$space_name" \
                --app-type "$app_type" \
                --app-name "$app_name" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete App (may already be deleting)"
        elif [[ -n "$user_profile" && "$user_profile" != "None" ]]; then
            aws sagemaker delete-app \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$user_profile" \
                --app-type "$app_type" \
                --app-name "$app_name" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete App (may already be deleting)"
        fi
    done <<< "$apps"
    
    # 等待 Apps 删除
    if [[ -n "$apps" ]]; then
        log_info "Waiting for Apps to be deleted..."
        sleep 30
    fi
fi

# -----------------------------------------------------------------------------
# 删除所有 Spaces
# -----------------------------------------------------------------------------
if [[ -n "$DOMAIN_ID" ]]; then
    log_info "Step 2: Deleting all Spaces..."
    
    spaces=$(aws sagemaker list-spaces \
        --domain-id "$DOMAIN_ID" \
        --query 'Spaces[].SpaceName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    for space_name in $spaces; do
        [[ -z "$space_name" ]] && continue
        log_info "Deleting Space: $space_name"
        aws sagemaker delete-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete Space"
    done
    
    if [[ -n "$spaces" ]]; then
        log_info "Waiting for Spaces to be deleted..."
        sleep 20
    fi
fi

# -----------------------------------------------------------------------------
# 删除所有 User Profiles
# -----------------------------------------------------------------------------
if [[ -n "$DOMAIN_ID" ]]; then
    log_info "Step 3: Deleting all User Profiles..."
    
    profiles=$(aws sagemaker list-user-profiles \
        --domain-id "$DOMAIN_ID" \
        --query 'UserProfiles[].UserProfileName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    for profile_name in $profiles; do
        [[ -z "$profile_name" ]] && continue
        log_info "Deleting User Profile: $profile_name"
        aws sagemaker delete-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile_name" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete Profile"
    done
    
    if [[ -n "$profiles" ]]; then
        log_info "Waiting for User Profiles to be deleted..."
        sleep 20
    fi
fi

# -----------------------------------------------------------------------------
# 删除 Domain
# -----------------------------------------------------------------------------
if [[ -n "$DOMAIN_ID" ]]; then
    log_info "Step 4: Deleting Domain..."
    
    aws sagemaker delete-domain \
        --domain-id "$DOMAIN_ID" \
        --retention-policy HomeEfsFileSystem=Delete \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete Domain"
    
    log_info "Waiting for Domain to be deleted (this may take several minutes)..."
    
    max_wait=600
    waited=0
    while [[ $waited -lt $max_wait ]]; do
        status=$(aws sagemaker describe-domain \
            --domain-id "$DOMAIN_ID" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "Deleted")
        
        if [[ "$status" == "Deleted" || -z "$status" ]]; then
            log_success "Domain deleted"
            break
        fi
        
        echo -n "."
        sleep 15
        ((waited+=15))
    done
    echo ""
fi

# -----------------------------------------------------------------------------
# 删除 Lifecycle Config
# -----------------------------------------------------------------------------
log_info "Step 5: Deleting Lifecycle Configuration..."

lcc_arn=$(aws sagemaker list-studio-lifecycle-configs \
    --query "StudioLifecycleConfigs[?StudioLifecycleConfigName=='${LIFECYCLE_CONFIG_NAME}'].StudioLifecycleConfigArn | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -n "$lcc_arn" && "$lcc_arn" != "None" ]]; then
    aws sagemaker delete-studio-lifecycle-config \
        --studio-lifecycle-config-name "$LIFECYCLE_CONFIG_NAME" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete Lifecycle Config"
    log_success "Deleted Lifecycle Config: $LIFECYCLE_CONFIG_NAME"
else
    log_info "Lifecycle Config not found, skipping"
fi

# -----------------------------------------------------------------------------
# 清理输出文件
# -----------------------------------------------------------------------------
log_info "Step 6: Cleaning up output files..."

rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/domain-info.env" 2>/dev/null || true
rm -f "${SCRIPT_DIR}/${OUTPUT_DIR}/lifecycle-config.env" 2>/dev/null || true

echo ""
log_success "Cleanup complete!"
echo ""
echo "Note: The EFS file system will be deleted along with the Domain."
echo "This process may take several minutes to complete in the background."

