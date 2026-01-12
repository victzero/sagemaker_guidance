#!/bin/bash
# =============================================================================
# lib/instance-whitelist.sh - 实例类型白名单管理函数
# =============================================================================
# 用于管理 SageMaker Studio 中用户可选择的实例类型
#
# 功能:
#   - 从 .env.shared 加载预设白名单
#   - 获取项目的实例类型白名单配置
#   - 生成/更新实例类型白名单策略
#   - 验证实例类型格式
#
# 依赖:
#   - common.sh (已加载)
#   - iam-core.sh (策略创建函数)
# =============================================================================

# 防止重复加载
if [[ -n "$_LIB_INSTANCE_WHITELIST_LOADED" ]]; then
    return 0
fi
_LIB_INSTANCE_WHITELIST_LOADED=1

# =============================================================================
# 预设白名单定义 (如果 .env.shared 未配置则使用默认值)
# =============================================================================

# 默认预设 - 基础开发实例
INSTANCE_WHITELIST_PRESET_default="${INSTANCE_WHITELIST_PRESET_default:-ml.t3.medium,ml.t3.large,ml.m5.large,ml.m5.xlarge,system}"

# GPU 预设 - 包含 GPU 实例
INSTANCE_WHITELIST_PRESET_gpu="${INSTANCE_WHITELIST_PRESET_gpu:-ml.t3.medium,ml.t3.large,ml.m5.xlarge,ml.g4dn.xlarge,ml.g4dn.2xlarge,ml.g5.xlarge,system}"

# 大内存预设 - 包含大内存实例
INSTANCE_WHITELIST_PRESET_large_memory="${INSTANCE_WHITELIST_PRESET_large_memory:-ml.t3.medium,ml.t3.large,ml.m5.xlarge,ml.r5.large,ml.r5.xlarge,ml.r5.2xlarge,system}"

# 高性能预设 - 包含高性能计算实例
INSTANCE_WHITELIST_PRESET_high_performance="${INSTANCE_WHITELIST_PRESET_high_performance:-ml.t3.medium,ml.m5.xlarge,ml.m5.2xlarge,ml.c5.xlarge,ml.c5.2xlarge,ml.p3.2xlarge,system}"

# 不限制预设 - 空字符串表示不创建限制策略
INSTANCE_WHITELIST_PRESET_unrestricted=""

# =============================================================================
# 预设管理函数
# =============================================================================

# 获取所有可用的预设名称
# 用法: get_available_presets
get_available_presets() {
    echo "default gpu large_memory high_performance unrestricted"
}

# 获取预设的实例类型列表
# 用法: get_preset_instance_types <preset_name>
# 返回: 逗号分隔的实例类型列表，或空字符串（unrestricted）
get_preset_instance_types() {
    local preset_name=$1
    local var_name="INSTANCE_WHITELIST_PRESET_${preset_name}"
    echo "${!var_name}"
}

# 验证预设名称是否有效
# 用法: validate_preset_name <preset_name>
# 返回: 0 有效, 1 无效
validate_preset_name() {
    local preset_name=$1
    local valid_presets=$(get_available_presets)
    
    for preset in $valid_presets; do
        if [[ "$preset" == "$preset_name" ]]; then
            return 0
        fi
    done
    
    return 1
}

# =============================================================================
# 项目白名单配置函数
# =============================================================================

# 获取项目的实例类型白名单预设名称
# 用法: get_project_whitelist_preset <team> <project>
# 返回: 预设名称 (default, gpu, large_memory, high_performance, unrestricted)
# 如果未配置，返回 "default"
get_project_whitelist_preset() {
    local team=$1
    local project=$2
    
    # 将 team 和 project 转换为环境变量格式
    # risk-control -> RC, fraud-detection -> FRAUD_DETECTION
    local team_upper="${team^^}"
    local project_upper="${project^^}"
    project_upper="${project_upper//-/_}"
    
    # 查找项目级配置: PROJECT_{TEAM}_{PROJECT}_INSTANCE_WHITELIST
    local var_name="PROJECT_${team_upper}_${project_upper}_INSTANCE_WHITELIST"
    local preset="${!var_name}"
    
    # 如果项目级未配置，查找团队级配置
    if [[ -z "$preset" ]]; then
        var_name="TEAM_${team_upper}_INSTANCE_WHITELIST"
        preset="${!var_name}"
    fi
    
    # 如果都未配置，使用默认值
    if [[ -z "$preset" ]]; then
        preset="default"
    fi
    
    echo "$preset"
}

# 获取项目的实例类型白名单（实际实例类型列表）
# 用法: get_project_instance_whitelist <team> <project>
# 返回: 逗号分隔的实例类型列表
get_project_instance_whitelist() {
    local team=$1
    local project=$2
    
    local preset=$(get_project_whitelist_preset "$team" "$project")
    get_preset_instance_types "$preset"
}

# =============================================================================
# 实例类型验证函数
# =============================================================================

# 验证单个实例类型格式
# 用法: validate_instance_type <instance_type>
# 返回: 0 有效, 1 无效
validate_instance_type() {
    local instance_type=$1
    
    # 允许 "system" 特殊值
    if [[ "$instance_type" == "system" ]]; then
        return 0
    fi
    
    # SageMaker 实例类型格式: ml.{family}.{size}
    if [[ "$instance_type" =~ ^ml\.[a-z][a-z0-9]*\.[a-z0-9]+$ ]]; then
        return 0
    fi
    
    return 1
}

# 验证实例类型列表
# 用法: validate_instance_types <comma_separated_list>
# 返回: 0 全部有效, 1 存在无效类型
validate_instance_types() {
    local types_list=$1
    
    # 空列表视为有效（unrestricted）
    if [[ -z "$types_list" ]]; then
        return 0
    fi
    
    IFS=',' read -ra types <<< "$types_list"
    for type in "${types[@]}"; do
        # 去除空格
        type=$(echo "$type" | xargs)
        if ! validate_instance_type "$type"; then
            log_error "Invalid instance type: $type"
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# JSON 格式转换函数
# =============================================================================

# 将逗号分隔的实例类型列表转换为 JSON 数组
# 用法: instance_types_to_json <comma_separated_list>
# 返回: JSON 数组字符串，如 ["ml.t3.medium", "ml.t3.large", "system"]
instance_types_to_json() {
    local types_list=$1
    
    if [[ -z "$types_list" ]]; then
        echo "[]"
        return
    fi
    
    local json_array="["
    local first=true
    
    IFS=',' read -ra types <<< "$types_list"
    for type in "${types[@]}"; do
        # 去除空格
        type=$(echo "$type" | xargs)
        if [[ -n "$type" ]]; then
            if $first; then
                json_array+="\"$type\""
                first=false
            else
                json_array+=", \"$type\""
            fi
        fi
    done
    
    json_array+="]"
    echo "$json_array"
}

# =============================================================================
# 策略生成函数
# =============================================================================

# 生成实例类型白名单策略
# 用法: generate_instance_whitelist_policy <team> <project>
# 返回: JSON 策略文档
generate_instance_whitelist_policy() {
    local team=$1
    local project=$2
    
    local instance_types=$(get_project_instance_whitelist "$team" "$project")
    
    # 如果是 unrestricted，返回空（不创建策略）
    if [[ -z "$instance_types" ]]; then
        echo ""
        return
    fi
    
    local json_array=$(instance_types_to_json "$instance_types")
    
    # 使用模板生成策略
    if [[ -n "$POLICY_TEMPLATES_DIR" && -f "${POLICY_TEMPLATES_DIR}/instance-whitelist.json.tpl" ]]; then
        local content=$(cat "${POLICY_TEMPLATES_DIR}/instance-whitelist.json.tpl")
        content=$(echo "$content" | sed "s|\${ALLOWED_INSTANCE_TYPES}|${json_array}|g")
        echo "$content"
    else
        # 内联策略模板（fallback）
        cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnauthorizedInstanceTypes",
      "Effect": "Deny",
      "Action": [
        "sagemaker:CreateApp"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "sagemaker:InstanceTypes": ${json_array}
        }
      }
    }
  ]
}
EOF
    fi
}

# 使用自定义实例类型列表生成策略
# 用法: generate_custom_whitelist_policy <comma_separated_types>
# 返回: JSON 策略文档
generate_custom_whitelist_policy() {
    local instance_types=$1
    
    if [[ -z "$instance_types" ]]; then
        echo ""
        return
    fi
    
    local json_array=$(instance_types_to_json "$instance_types")
    
    cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnauthorizedInstanceTypes",
      "Effect": "Deny",
      "Action": [
        "sagemaker:CreateApp"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "sagemaker:InstanceTypes": ${json_array}
        }
      }
    }
  ]
}
EOF
}

# =============================================================================
# 策略管理函数 (依赖 iam-core.sh)
# =============================================================================

# 创建或更新项目的实例类型白名单策略
# 用法: create_instance_whitelist_policy <team> <project>
create_instance_whitelist_policy() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
    local policy_content=$(generate_instance_whitelist_policy "$team" "$project")
    
    # 如果是 unrestricted，跳过创建
    if [[ -z "$policy_content" ]]; then
        log_info "Instance whitelist: unrestricted (no policy created for ${team}/${project})"
        return 0
    fi
    
    local preset=$(get_project_whitelist_preset "$team" "$project")
    log_info "Creating instance whitelist policy: $policy_name (preset: $preset)"
    
    create_or_update_policy "$policy_name" "$policy_content"
}

# 附加实例类型白名单策略到 Execution Role
# 用法: attach_instance_whitelist_to_role <team> <project>
attach_instance_whitelist_to_role() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 检查策略是否存在（unrestricted 项目不会有策略）
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        local preset=$(get_project_whitelist_preset "$team" "$project")
        if [[ "$preset" == "unrestricted" ]]; then
            log_info "Instance whitelist: unrestricted (skipping attachment for ${team}/${project})"
        else
            log_warn "Instance whitelist policy not found: $policy_name"
        fi
        return 0
    fi
    
    attach_policy_to_role "$role_name" "$policy_name" "$policy_arn"
}

# =============================================================================
# 运维操作函数 (供 08-operations 使用)
# =============================================================================

# 更新项目的实例类型白名单（使用预设）
# 用法: update_project_whitelist_preset <team> <project> <preset_name>
update_project_whitelist_preset() {
    local team=$1
    local project=$2
    local preset_name=$3
    
    # 验证预设名称
    if ! validate_preset_name "$preset_name"; then
        log_error "Invalid preset name: $preset_name"
        log_info "Available presets: $(get_available_presets)"
        return 1
    fi
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    
    if [[ "$preset_name" == "unrestricted" ]]; then
        # Unrestricted: 删除现有策略
        if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
            log_info "Removing instance whitelist restriction..."
            
            # 先从 Role 分离
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || true
            
            # 删除策略版本
            local versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" \
                --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
            for version in $versions; do
                aws iam delete-policy-version \
                    --policy-arn "$policy_arn" \
                    --version-id "$version" 2>/dev/null || true
            done
            
            # 删除策略
            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
            
            log_success "Instance whitelist removed (unrestricted)"
        else
            log_info "No existing whitelist policy to remove"
        fi
    else
        # 有限制: 创建/更新策略
        local instance_types=$(get_preset_instance_types "$preset_name")
        local policy_content=$(generate_custom_whitelist_policy "$instance_types")
        
        log_info "Updating instance whitelist to preset: $preset_name"
        log_info "Allowed types: $instance_types"
        
        create_or_update_policy "$policy_name" "$policy_content"
        attach_policy_to_role "$role_name" "$policy_name" "$policy_arn"
        
        log_success "Instance whitelist updated to: $preset_name"
    fi
}

# 更新项目的实例类型白名单（使用自定义列表）
# 用法: update_project_whitelist_custom <team> <project> <comma_separated_types>
update_project_whitelist_custom() {
    local team=$1
    local project=$2
    local instance_types=$3
    
    # 验证实例类型
    if ! validate_instance_types "$instance_types"; then
        log_error "Invalid instance types in list"
        return 1
    fi
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    local role_name="SageMaker-${team_capitalized}-${project_formatted}-ExecutionRole"
    
    local policy_content=$(generate_custom_whitelist_policy "$instance_types")
    
    log_info "Updating instance whitelist with custom types..."
    log_info "Allowed types: $instance_types"
    
    create_or_update_policy "$policy_name" "$policy_content"
    attach_policy_to_role "$role_name" "$policy_name" "$policy_arn"
    
    log_success "Instance whitelist updated with custom types"
}

# 获取项目当前的实例类型白名单
# 用法: get_current_whitelist <team> <project>
# 返回: 当前白名单的实例类型列表，或 "unrestricted"
get_current_whitelist() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_capitalized=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    
    local policy_name="SageMaker-${team_capitalized}-${project_formatted}-InstanceWhitelist"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy${IAM_PATH}${policy_name}"
    
    # 检查策略是否存在
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        echo "unrestricted"
        return 0
    fi
    
    # 获取策略内容
    local version_id=$(aws iam get-policy --policy-arn "$policy_arn" \
        --query 'Policy.DefaultVersionId' --output text 2>/dev/null)
    
    local policy_doc=$(aws iam get-policy-version \
        --policy-arn "$policy_arn" \
        --version-id "$version_id" \
        --query 'PolicyVersion.Document' \
        --output json 2>/dev/null)
    
    # 提取实例类型列表
    local types=$(echo "$policy_doc" | jq -r '.Statement[0].Condition.StringNotEqualsIfExists["sagemaker:InstanceTypes"] | if type == "array" then join(",") else . end' 2>/dev/null)
    
    if [[ -n "$types" && "$types" != "null" ]]; then
        echo "$types"
    else
        echo "unrestricted"
    fi
}

# 重置项目的实例类型白名单到初始配置
# 用法: reset_project_whitelist <team> <project>
reset_project_whitelist() {
    local team=$1
    local project=$2
    
    local preset=$(get_project_whitelist_preset "$team" "$project")
    log_info "Resetting instance whitelist to initial config (preset: $preset)"
    
    update_project_whitelist_preset "$team" "$project" "$preset"
}

# =============================================================================
# 查询函数
# =============================================================================

# 列出所有项目的实例类型白名单配置
# 用法: list_all_whitelists
list_all_whitelists() {
    echo ""
    echo "Project Instance Type Whitelist Status"
    echo "======================================="
    printf "%-20s %-25s %-15s %s\n" "Team" "Project" "Preset" "Current"
    echo "-------------------------------------------------------------------------------------------------------"
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local preset=$(get_project_whitelist_preset "$team" "$project")
            local current=$(get_current_whitelist "$team" "$project")
            
            # 截断显示
            if [[ ${#current} -gt 50 ]]; then
                current="${current:0:47}..."
            fi
            
            printf "%-20s %-25s %-15s %s\n" "$team" "$project" "$preset" "$current"
        done
    done
    
    echo ""
}

# 打印预设详情
# 用法: print_preset_details
print_preset_details() {
    echo ""
    echo "Available Instance Type Whitelist Presets"
    echo "=========================================="
    echo ""
    
    local presets=$(get_available_presets)
    for preset in $presets; do
        local types=$(get_preset_instance_types "$preset")
        echo "[$preset]"
        if [[ -z "$types" ]]; then
            echo "  (no restrictions)"
        else
            echo "  $types"
        fi
        echo ""
    done
}


