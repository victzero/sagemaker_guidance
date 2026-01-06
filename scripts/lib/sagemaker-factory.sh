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
get_studio_security_group() {
    local tag_prefix="${COMPANY:-company}-sagemaker"
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

# 获取 Domain ID
get_domain_id() {
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
    
    echo "$domain_id"
}

