#!/bin/bash
# =============================================================================
# lib/discovery.sh - 动态资源发现函数
# =============================================================================
# 从 AWS 实际资源中发现团队、项目、用户等信息
# 替代从 .env 静态配置读取的方式
# =============================================================================

# 防止重复加载
if [[ -n "$_LIB_DISCOVERY_LOADED" ]]; then
    return 0
fi
_LIB_DISCOVERY_LOADED=1

# -----------------------------------------------------------------------------
# 动态发现团队的项目列表
# 
# 从 IAM Groups 中发现项目，格式: sagemaker-{team}-{project}
# 
# 用法: discover_projects_for_team <team>
# 返回: 项目名列表 (空格分隔)
# -----------------------------------------------------------------------------
discover_projects_for_team() {
    local team=$1
    local iam_path="${IAM_PATH:-/}"
    
    # 从 IAM Groups 中查找该团队的项目
    # 注意: JMESPath 使用反引号 ` 表示字符串字面量
    local groups=$(aws iam list-groups --path-prefix "$iam_path" \
        --query 'Groups[?starts_with(GroupName, `sagemaker-'"${team}"'-`)].GroupName' \
        --output text 2>/dev/null || echo "")
    
    local projects=()
    for group in $groups; do
        # 跳过团队级 Groups (sagemaker-risk-control 等)
        # 项目级 Groups 格式: sagemaker-{team}-{project}
        local suffix="${group#sagemaker-${team}-}"
        
        # 确保 suffix 不为空且不等于原 group (说明匹配成功)
        if [[ -n "$suffix" && "$suffix" != "$group" ]]; then
            projects+=("$suffix")
        fi
    done
    
    echo "${projects[*]}"
}

# -----------------------------------------------------------------------------
# 获取项目列表 (优先动态发现，fallback 到 .env)
# 
# 用法: get_project_list_dynamic <team>
# 返回: 项目名列表 (空格分隔)
# -----------------------------------------------------------------------------
get_project_list_dynamic() {
    local team=$1
    
    # 1. 首先尝试动态发现
    local discovered=$(discover_projects_for_team "$team")
    
    if [[ -n "$discovered" ]]; then
        echo "$discovered"
        return 0
    fi
    
    # 2. Fallback 到 .env 配置
    local var_name="${team^^}_PROJECTS"
    local configured="${!var_name}"
    
    if [[ -n "$configured" ]]; then
        echo "$configured"
        return 0
    fi
    
    # 3. 都没有则返回空
    echo ""
}

# -----------------------------------------------------------------------------
# 发现所有团队
# 
# 从 IAM Groups 中发现团队，格式: sagemaker-{team}
# 
# 用法: discover_teams
# 返回: 团队短名列表 (空格分隔)
# -----------------------------------------------------------------------------
discover_teams() {
    local iam_path="${IAM_PATH:-/}"
    
    # 从 IAM Groups 中查找团队级 Groups
    # 注意: JMESPath 使用反引号 ` 表示字符串字面量
    local groups=$(aws iam list-groups --path-prefix "$iam_path" \
        --query 'Groups[?starts_with(GroupName, `sagemaker-`)].GroupName' \
        --output text 2>/dev/null || echo "")
    
    local teams=()
    local seen_teams=()
    
    for group in $groups; do
        # 跳过平台级 Groups
        if [[ "$group" == "sagemaker-admins" || "$group" == "sagemaker-readonly" ]]; then
            continue
        fi
        
        # 提取团队名: sagemaker-{team} 或 sagemaker-{team}-{project}
        local suffix="${group#sagemaker-}"
        local team="${suffix%%-*}"  # 取第一段作为团队名
        
        # 去重
        if [[ -n "$team" && ! " ${seen_teams[*]} " =~ " ${team} " ]]; then
            seen_teams+=("$team")
            teams+=("$team")
        fi
    done
    
    echo "${teams[*]}"
}

# -----------------------------------------------------------------------------
# 检查项目是否存在 (通过 IAM Group)
# 
# 用法: project_exists <team> <project>
# 返回: 0 存在, 1 不存在
# -----------------------------------------------------------------------------
project_exists() {
    local team=$1
    local project=$2
    local group_name="sagemaker-${team}-${project}"
    
    aws iam get-group --group-name "$group_name" &> /dev/null
}

# -----------------------------------------------------------------------------
# 检查项目角色是否完整
# 
# 用法: check_project_roles <team> <project>
# 返回: 存在的角色数量 (0-4)
# -----------------------------------------------------------------------------
check_project_roles() {
    local team=$1
    local project=$2
    
    local team_fullname=$(get_team_fullname "$team")
    local team_formatted=$(format_name "$team_fullname")
    local project_formatted=$(format_name "$project")
    local role_prefix="SageMaker-${team_formatted}-${project_formatted}"
    
    local count=0
    for suffix in "ExecutionRole" "TrainingRole" "ProcessingRole" "InferenceRole"; do
        if aws iam get-role --role-name "${role_prefix}-${suffix}" &> /dev/null; then
            ((count++))
        fi
    done
    
    echo "$count"
}

# -----------------------------------------------------------------------------
# 检查项目 S3 Bucket 是否存在
# 
# 用法: check_project_bucket <team> <project>
# 返回: 0 存在, 1 不存在
# -----------------------------------------------------------------------------
check_project_bucket() {
    local team=$1
    local project=$2
    local bucket_name="${COMPANY}-sm-${team}-${project}"
    
    aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 获取项目的用户列表 (从 IAM Group 成员)
# 
# 用法: discover_project_users <team> <project>
# 返回: IAM 用户名列表 (空格分隔)
# -----------------------------------------------------------------------------
discover_project_users() {
    local team=$1
    local project=$2
    local group_name="sagemaker-${team}-${project}"
    
    aws iam get-group --group-name "$group_name" \
        --query 'Users[].UserName' \
        --output text 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# 获取用户的项目列表 (从 IAM Group 成员关系)
# 
# 用法: discover_user_projects <iam_username>
# 返回: 项目 Group 名列表 (空格分隔)
# -----------------------------------------------------------------------------
discover_user_projects() {
    local username=$1
    
    local groups=$(aws iam list-groups-for-user --user-name "$username" \
        --query 'Groups[].GroupName' \
        --output text 2>/dev/null || echo "")
    
    local project_groups=()
    for group in $groups; do
        # 只返回项目级 Groups (sagemaker-{team}-{project})
        if [[ "$group" =~ ^sagemaker-[a-z]+-[a-z] ]]; then
            # 排除团队级 Groups (只有一个连字符后没有内容)
            local suffix="${group#sagemaker-}"
            if [[ "$suffix" == *-* ]]; then
                project_groups+=("$group")
            fi
        fi
    done
    
    echo "${project_groups[*]}"
}

