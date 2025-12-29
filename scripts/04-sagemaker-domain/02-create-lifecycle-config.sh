#!/bin/bash
# =============================================================================
# 02-create-lifecycle-config.sh - 创建 Lifecycle Configuration (自动关机)
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
    echo " Creating Lifecycle Configuration"
    echo "=============================================="
    echo ""
    
    # 检查是否已存在
    log_info "Checking for existing Lifecycle Config: $LIFECYCLE_CONFIG_NAME"
    
    local existing=$(aws sagemaker list-studio-lifecycle-configs \
        --query "StudioLifecycleConfigs[?StudioLifecycleConfigName=='${LIFECYCLE_CONFIG_NAME}'].StudioLifecycleConfigArn" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$existing" && "$existing" != "None" ]]; then
        log_warn "Lifecycle Config $LIFECYCLE_CONFIG_NAME already exists"
        log_info "ARN: $existing"
        LCC_ARN="$existing"
    else
        # 创建 auto-shutdown 脚本
        log_info "Creating auto-shutdown script..."
        
        local script_content=$(cat <<'SCRIPT_EOF'
#!/bin/bash
# auto-shutdown.sh - 空闲检测与自动关闭脚本
# 由 SageMaker 平台自动配置

set -e

IDLE_TIMEOUT_MINUTES=${IDLE_TIMEOUT_MINUTES:-60}
LOG_FILE="/var/log/auto-shutdown.log"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_msg "Auto-shutdown script started. Idle timeout: ${IDLE_TIMEOUT_MINUTES} minutes"

# 后台运行空闲检测
nohup bash -c '
IDLE_TIMEOUT_SECONDS=$((${IDLE_TIMEOUT_MINUTES:-60} * 60))
LAST_ACTIVITY=$(date +%s)

while true; do
    sleep 60
    
    # 检查是否有活跃的 kernel 连接
    # 通过检查 Jupyter 服务的活跃连接数来判断
    ACTIVE_CONNECTIONS=$(netstat -an 2>/dev/null | grep -c ":8888.*ESTABLISHED" || echo "0")
    
    if [ "$ACTIVE_CONNECTIONS" -gt 0 ]; then
        LAST_ACTIVITY=$(date +%s)
    fi
    
    CURRENT_TIME=$(date +%s)
    IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVITY))
    
    if [ $IDLE_TIME -gt $IDLE_TIMEOUT_SECONDS ]; then
        echo "$(date) - Idle timeout reached ($IDLE_TIME seconds). Shutting down..." >> /var/log/auto-shutdown.log
        
        # 获取实例元数据
        RESOURCE_METADATA=$(cat /opt/ml/metadata/resource-metadata.json 2>/dev/null || echo "{}")
        DOMAIN_ID=$(echo "$RESOURCE_METADATA" | jq -r ".DomainId // empty")
        SPACE_NAME=$(echo "$RESOURCE_METADATA" | jq -r ".SpaceName // empty")
        USER_PROFILE_NAME=$(echo "$RESOURCE_METADATA" | jq -r ".UserProfileName // empty")
        APP_TYPE=$(echo "$RESOURCE_METADATA" | jq -r ".AppType // empty")
        APP_NAME=$(echo "$RESOURCE_METADATA" | jq -r ".ResourceName // empty")
        
        if [[ -n "$DOMAIN_ID" ]]; then
            # 根据是 Space 还是 UserProfile 选择正确的删除命令
            if [[ -n "$SPACE_NAME" ]]; then
                aws sagemaker delete-app \
                    --domain-id "$DOMAIN_ID" \
                    --space-name "$SPACE_NAME" \
                    --app-type "$APP_TYPE" \
                    --app-name "$APP_NAME" 2>/dev/null || true
            elif [[ -n "$USER_PROFILE_NAME" ]]; then
                aws sagemaker delete-app \
                    --domain-id "$DOMAIN_ID" \
                    --user-profile-name "$USER_PROFILE_NAME" \
                    --app-type "$APP_TYPE" \
                    --app-name "$APP_NAME" 2>/dev/null || true
            fi
        fi
        
        break
    fi
done
' >> "$LOG_FILE" 2>&1 &

log_msg "Auto-shutdown monitor started in background (PID: $!)"
SCRIPT_EOF
)
        
        # 替换超时时间
        script_content="${script_content//\$\{IDLE_TIMEOUT_MINUTES:-60\}/$IDLE_TIMEOUT_MINUTES}"
        
        # Base64 编码
        local encoded_script=$(echo "$script_content" | base64 -w 0)
        
        # 创建 Lifecycle Config
        log_info "Creating Lifecycle Config: $LIFECYCLE_CONFIG_NAME"
        
        LCC_ARN=$(aws sagemaker create-studio-lifecycle-config \
            --studio-lifecycle-config-name "$LIFECYCLE_CONFIG_NAME" \
            --studio-lifecycle-config-app-type JupyterLab \
            --studio-lifecycle-config-content "$encoded_script" \
            --query 'StudioLifecycleConfigArn' \
            --output text \
            --region "$AWS_REGION")
        
        log_success "Created Lifecycle Config"
    fi
    
    # 保存 ARN
    cat > "${SCRIPT_DIR}/${OUTPUT_DIR}/lifecycle-config.env" << EOF
# Lifecycle Config - Generated $(date)
LIFECYCLE_CONFIG_NAME=${LIFECYCLE_CONFIG_NAME}
LIFECYCLE_CONFIG_ARN=${LCC_ARN}
IDLE_TIMEOUT_MINUTES=${IDLE_TIMEOUT_MINUTES}
EOF
    
    echo ""
    log_success "Lifecycle Config ready!"
    echo ""
    echo "Lifecycle Config Summary:"
    echo "  Name:         $LIFECYCLE_CONFIG_NAME"
    echo "  Idle Timeout: $IDLE_TIMEOUT_MINUTES minutes"
    echo "  ARN:          $LCC_ARN"
    echo ""
    echo "Info saved to: ${SCRIPT_DIR}/${OUTPUT_DIR}/lifecycle-config.env"
}

main

