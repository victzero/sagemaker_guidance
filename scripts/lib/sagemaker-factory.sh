#!/bin/bash
# =============================================================================
# lib/sagemaker-factory.sh - SageMaker 资源创建工厂函数
# =============================================================================
# 封装 User Profile、Space 等创建逻辑，供其他模块复用
# =============================================================================

# 防止重复加载
if [[ -n "$_LIB_SAGEMAKER_FACTORY_LOADED" ]]; then
    return 0
fi
_LIB_SAGEMAKER_FACTORY_LOADED=1

# 确保 common.sh 已加载
if [[ -z "$_SAGEMAKER_COMMON_LOADED" ]]; then
    source "${SCRIPTS_ROOT}/common.sh"
fi

# =============================================================================
# 存在性检查函数
# =============================================================================

# 检查 User Profile 是否存在
# 用法: sagemaker_profile_exists <domain_id> <profile_name>
# 返回: 0 存在, 1 不存在
sagemaker_profile_exists() {
    local domain_id=$1
    local profile_name=$2
    aws sagemaker describe-user-profile \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null
}

# 检查 Space 是否存在
# 用法: sagemaker_space_exists <domain_id> <space_name>
# 返回: 0 存在, 1 不存在
sagemaker_space_exists() {
    local domain_id=$1
    local space_name=$2
    aws sagemaker describe-space \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null
}

# =============================================================================
# User Profile 创建
# =============================================================================

# 创建 SageMaker User Profile
# 用法: create_user_profile <domain_id> <profile_name> <execution_role_arn> <security_group_id> <team> <project> <iam_username>
create_user_profile() {
    local domain_id=$1
    local profile_name=$2
    local execution_role_arn=$3
    local security_group_id=$4
    local team=$5
    local project=$6
    local iam_username=$7
    
    local team_fullname=$(get_team_fullname "$team")
    local tag_prefix="${COMPANY:-company}-sagemaker"
    
    log_info "Creating User Profile: $profile_name"
    
    # 检查是否已存在
    if aws sagemaker describe-user-profile \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "User Profile $profile_name already exists, skipping..."
        return 0
    fi
    
    # 构建 User Settings
    local user_settings=$(cat <<EOF
{
    "ExecutionRole": "${execution_role_arn}",
    "SecurityGroups": ["${security_group_id}"]
}
EOF
)
    
    aws sagemaker create-user-profile \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --user-settings "$user_settings" \
        --tags \
            Key=Team,Value="$team_fullname" \
            Key=Project,Value="$project" \
            Key=Owner,Value="$iam_username" \
            Key=Environment,Value=production \
            Key=ManagedBy,Value="${tag_prefix}" \
        --region "$AWS_REGION"
    
    log_success "User Profile created: $profile_name"
    
    # 等待状态变为 InService
    wait_for_profile_ready "$domain_id" "$profile_name"
}

# 等待 User Profile 就绪
# 用法: wait_for_profile_ready <domain_id> <profile_name>
wait_for_profile_ready() {
    local domain_id=$1
    local profile_name=$2
    local max_wait=${3:-120}
    local wait_interval=5
    local elapsed=0
    
    log_info "Waiting for User Profile to be ready..."
    
    while [ $elapsed -lt $max_wait ]; do
        local status=$(aws sagemaker describe-user-profile \
            --domain-id "$domain_id" \
            --user-profile-name "$profile_name" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "Unknown")
        
        if [ "$status" == "InService" ]; then
            log_success "User Profile ready: $profile_name"
            return 0
        fi
        
        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    echo ""
    log_error "User Profile did not become ready within ${max_wait}s (status: $status)"
    return 1
}

# =============================================================================
# Private Space 创建
# =============================================================================

# 创建 Private Space
# 用法: create_private_space <domain_id> <space_name> <owner_profile_name> <team> <project> <username> [ebs_size_gb]
create_private_space() {
    local domain_id=$1
    local space_name=$2
    local owner_profile_name=$3
    local team=$4
    local project=$5
    local username=$6
    local ebs_size_gb=${7:-50}
    
    local team_fullname=$(get_team_fullname "$team")
    local tag_prefix="${COMPANY:-company}-sagemaker"
    
    log_info "Creating Private Space: $space_name"
    
    # 检查是否已存在
    if aws sagemaker describe-space \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warn "Space $space_name already exists, skipping..."
        return 0
    fi
    
    # 构建 Space Settings
    local space_settings=$(cat <<EOF
{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
        "EbsStorageSettings": {
            "EbsVolumeSizeInGb": ${ebs_size_gb}
        }
    }
}
EOF
)
    
    aws sagemaker create-space \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --space-sharing-settings '{"SharingType": "Private"}' \
        --ownership-settings "{\"OwnerUserProfileName\": \"${owner_profile_name}\"}" \
        --space-settings "$space_settings" \
        --tags \
            Key=Team,Value="$team_fullname" \
            Key=Project,Value="$project" \
            Key=Owner,Value="$username" \
            Key=SpaceType,Value="private" \
            Key=Environment,Value=production \
            Key=ManagedBy,Value="${tag_prefix}" \
        --region "$AWS_REGION"
    
    log_success "Private Space created: $space_name"
}

# =============================================================================
# Lifecycle Configuration 创建
# =============================================================================

# 创建 Lifecycle Configuration
# 用法: create_lifecycle_config <name> <script_path> <type>
# type: JupyterLab | KernelGateway
create_lifecycle_config() {
    local lcc_name=$1
    local script_path=$2
    local lcc_type=${3:-JupyterLab}
    
    log_info "Creating Lifecycle Config: $lcc_name ($lcc_type)" >&2
    
    if [[ ! -f "$script_path" ]]; then
        log_error "Script file not found: $script_path" >&2
        return 1
    fi
    
    # Read script content and base64 encode it
    local content_base64
    if [[ "$OSTYPE" == "darwin"* ]]; then
        content_base64=$(openssl base64 -in "$script_path" | tr -d '\n')
    else
        content_base64=$(base64 -w 0 "$script_path")
    fi
    
    # Check if exists
    local existing_arn=$(aws sagemaker list-studio-lifecycle-configs \
        --name-contains "$lcc_name" \
        --query "StudioLifecycleConfigs[?StudioLifecycleConfigName=='${lcc_name}'].StudioLifecycleConfigArn" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
        
    if [[ -n "$existing_arn" && "$existing_arn" != "None" ]]; then
        log_warn "Lifecycle Config $lcc_name already exists, updating content..." >&2
        
        # Delete and recreate to ensure content update
        aws sagemaker delete-studio-lifecycle-config \
            --studio-lifecycle-config-name "$lcc_name" \
            --region "$AWS_REGION"
            
        sleep 2
    fi
    
    local arn=$(aws sagemaker create-studio-lifecycle-config \
        --studio-lifecycle-config-name "$lcc_name" \
        --studio-lifecycle-config-content "$content_base64" \
        --studio-lifecycle-config-app-type "$lcc_type" \
        --tags \
            Key=ManagedBy,Value="${TAG_PREFIX:-sagemaker}" \
            Key=Environment,Value=production \
        --query 'StudioLifecycleConfigArn' \
        --output text \
        --region "$AWS_REGION")
        
    log_success "Lifecycle Config created: $arn" >&2
    echo "$arn"
}

# =============================================================================
# 组合函数
# =============================================================================

# 创建用户的 Profile 和 Space
# 用法: create_user_profile_and_space <domain_id> <team> <project> <username> <iam_username> <security_group_id> [ebs_size_gb]
create_user_profile_and_space() {
    local domain_id=$1
    local team=$2
    local project=$3
    local username=$4
    local iam_username=$5
    local security_group_id=$6
    local ebs_size_gb=${7:-50}
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local project_short=$(echo "$project" | cut -d'-' -f1)
    
    local profile_name="profile-${team}-${project_short}-${username}"
    local space_name="space-${team}-${project_short}-${username}"
    local execution_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    
    log_step "Creating Profile and Space for user: $username"
    
    # 1. 创建 User Profile
    create_user_profile \
        "$domain_id" \
        "$profile_name" \
        "$execution_role_arn" \
        "$security_group_id" \
        "$team" \
        "$project" \
        "$iam_username"
    
    # 2. 创建 Private Space
    create_private_space \
        "$domain_id" \
        "$space_name" \
        "$profile_name" \
        "$team" \
        "$project" \
        "$username" \
        "$ebs_size_gb"
    
    log_success "User Profile and Space created for: $username"
}

# =============================================================================
# 辅助函数
# =============================================================================

# 获取项目短名 (fraud-detection -> fraud)
get_project_short() {
    local project=$1
    echo "$project" | cut -d'-' -f1
}

# 获取 Studio Security Group ID
# 支持 TAG_PREFIX 变量（兼容 08-operations）或使用 COMPANY 构建
# 用法: get_studio_security_group
get_studio_security_group() {
    # 优先使用 TAG_PREFIX，否则使用 COMPANY 构建
    local tag_prefix="${TAG_PREFIX:-${COMPANY:-company}-sagemaker}"
    local sg_name="${tag_prefix}-studio"
    
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
        log_error "Security group not found: $sg_name"
        return 1
    fi
    
    echo "$sg_id"
}

# 别名 (兼容 05-user-profiles 和 08-operations)
get_studio_sg() {
    get_studio_security_group "$@"
}

# 获取 Domain ID (带缓存)
# 支持已设置的 DOMAIN_ID 变量，或自动从 AWS 查询
# 用法: get_domain_id
get_domain_id() {
    # 如果已有缓存，直接返回
    if [[ -n "$DOMAIN_ID" ]]; then
        echo "$DOMAIN_ID"
        return 0
    fi
    
    local domain_name="${DOMAIN_NAME:-sagemaker-domain}"
    
    # 先尝试用名称查找
    local domain_id=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${domain_name}'].DomainId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$domain_id" || "$domain_id" == "None" ]]; then
        # 尝试获取任意 Domain
        domain_id=$(aws sagemaker list-domains \
            --query "Domains[0].DomainId" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
    fi
    
    if [[ -z "$domain_id" || "$domain_id" == "None" ]]; then
        log_error "No SageMaker Domain found"
        return 1
    fi
    
    # 缓存并导出
    DOMAIN_ID="$domain_id"
    export DOMAIN_ID
    echo "$domain_id"
}

# =============================================================================
# SageMaker 删除函数 (从 05-user-profiles/cleanup.sh 提取)
# =============================================================================

# 删除 Space 的所有 Apps
# 用法: delete_apps_for_space <domain_id> <space_name>
delete_apps_for_space() {
    local domain_id=$1
    local space_name=$2
    
    log_info "Deleting Apps for Space: $space_name"
    
    local apps=$(aws sagemaker list-apps \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --query 'Apps[?Status!=`Deleted`].[AppType,AppName]' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    local app_count=0
    while IFS=$'\t' read -r app_type app_name; do
        [[ -z "$app_name" ]] && continue
        log_info "  Deleting App: $app_type/$app_name"
        aws sagemaker delete-app \
            --domain-id "$domain_id" \
            --space-name "$space_name" \
            --app-type "$app_type" \
            --app-name "$app_name" \
            --region "$AWS_REGION" 2>/dev/null || true
        ((app_count++)) || true
    done <<< "$apps"
    
    # 等待 Apps 删除
    if [[ $app_count -gt 0 ]]; then
        log_info "  Waiting for Apps to be deleted..."
        sleep 15
    fi
}

# 删除 Private Space
# 用法: delete_private_space <domain_id> <space_name>
delete_private_space() {
    local domain_id=$1
    local space_name=$2
    
    # 检查是否存在
    if ! aws sagemaker describe-space \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_info "Space not found, skipping: $space_name"
        return 0
    fi
    
    # 先删除所有 Apps
    delete_apps_for_space "$domain_id" "$space_name"
    
    # 删除 Space
    log_info "Deleting Space: $space_name"
    aws sagemaker delete-space \
        --domain-id "$domain_id" \
        --space-name "$space_name" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete $space_name"
    
    log_success "Space deleted: $space_name"
}

# 等待 Space 完全删除
# 用法: wait_for_space_deleted <domain_id> <space_name>
wait_for_space_deleted() {
    local domain_id=$1
    local space_name=$2
    local max_wait=${3:-120}
    local wait_interval=5
    local elapsed=0
    
    log_info "Waiting for Space to be deleted: $space_name"
    
    while [ $elapsed -lt $max_wait ]; do
        if ! aws sagemaker describe-space \
            --domain-id "$domain_id" \
            --space-name "$space_name" \
            --region "$AWS_REGION" &> /dev/null; then
            log_success "Space deleted: $space_name"
            return 0
        fi
        
        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    echo ""
    
    log_warn "Space still exists after ${max_wait}s: $space_name"
    return 1
}

# 删除 User Profile 的所有 Apps
# 用法: delete_apps_for_profile <domain_id> <profile_name>
delete_apps_for_profile() {
    local domain_id=$1
    local profile_name=$2
    
    log_info "Deleting Apps for Profile: $profile_name"
    
    local apps=$(aws sagemaker list-apps \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --query 'Apps[?Status!=`Deleted`].[AppType,AppName]' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    local app_count=0
    while IFS=$'\t' read -r app_type app_name; do
        [[ -z "$app_name" ]] && continue
        log_info "  Deleting App: $app_type/$app_name"
        aws sagemaker delete-app \
            --domain-id "$domain_id" \
            --user-profile-name "$profile_name" \
            --app-type "$app_type" \
            --app-name "$app_name" \
            --region "$AWS_REGION" 2>/dev/null || true
        ((app_count++)) || true
    done <<< "$apps"
    
    # 等待 Apps 删除
    if [[ $app_count -gt 0 ]]; then
        log_info "  Waiting for Apps to be deleted..."
        sleep 15
    fi
}

# 删除 User Profile
# 用法: delete_user_profile <domain_id> <profile_name>
delete_sagemaker_user_profile() {
    local domain_id=$1
    local profile_name=$2
    
    # 检查是否存在
    if ! aws sagemaker describe-user-profile \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" &> /dev/null; then
        log_info "Profile not found, skipping: $profile_name"
        return 0
    fi
    
    # 先删除所有 Apps
    delete_apps_for_profile "$domain_id" "$profile_name"
    
    # 删除 Profile
    log_info "Deleting User Profile: $profile_name"
    aws sagemaker delete-user-profile \
        --domain-id "$domain_id" \
        --user-profile-name "$profile_name" \
        --region "$AWS_REGION" 2>/dev/null || log_warn "Could not delete $profile_name"
    
    log_success "User Profile deleted: $profile_name"
}

# 等待 User Profile 完全删除
# 用法: wait_for_profile_deleted <domain_id> <profile_name>
wait_for_profile_deleted() {
    local domain_id=$1
    local profile_name=$2
    local max_wait=${3:-120}
    local wait_interval=5
    local elapsed=0
    
    log_info "Waiting for User Profile to be deleted: $profile_name"
    
    while [ $elapsed -lt $max_wait ]; do
        if ! aws sagemaker describe-user-profile \
            --domain-id "$domain_id" \
            --user-profile-name "$profile_name" \
            --region "$AWS_REGION" &> /dev/null; then
            log_success "User Profile deleted: $profile_name"
            return 0
        fi
        
        echo -n "."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    echo ""
    
    log_warn "User Profile still exists after ${max_wait}s: $profile_name"
    return 1
}

# 删除用户的所有 SageMaker 资源 (Profile + Space)
# 用法: delete_user_sagemaker_resources <domain_id> <profile_name> <space_name>
delete_user_sagemaker_resources() {
    local domain_id=$1
    local profile_name=$2
    local space_name=$3
    
    log_step "Deleting SageMaker resources for user..."
    
    # 1. 先删除 Space (必须在 Profile 之前)
    delete_private_space "$domain_id" "$space_name"
    
    # 等待 Space 完全删除
    wait_for_space_deleted "$domain_id" "$space_name" 60 || true
    
    # 2. 删除 User Profile
    delete_sagemaker_user_profile "$domain_id" "$profile_name"
    
    log_success "User SageMaker resources deleted"
}

