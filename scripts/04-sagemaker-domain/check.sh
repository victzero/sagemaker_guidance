#!/bin/bash
# =============================================================================
# check.sh - SageMaker Domain 前置检查和诊断脚本
# =============================================================================
# 使用场景:
#   1. setup 前检查: ./check.sh
#   2. 创建失败后诊断: ./check.sh --diagnose
#   3. 快速检查: ./check.sh --quick
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 计数器
errors=0
warnings=0

# -----------------------------------------------------------------------------
# 辅助函数
# -----------------------------------------------------------------------------
log_check()   { echo -e "${BLUE}[CHECK]${NC} $1"; }
log_ok()      { echo -e "${GREEN}  ✓${NC} $1"; }
log_fail()    { echo -e "${RED}  ✗${NC} $1"; ((errors++)) || true; }
log_warn()    { echo -e "${YELLOW}  !${NC} $1"; ((warnings++)) || true; }
log_info()    { echo -e "    $1"; }
log_section() { echo ""; echo -e "${CYAN}━━━ $1 ━━━${NC}"; }

# -----------------------------------------------------------------------------
# 加载环境
# -----------------------------------------------------------------------------
load_environment() {
    source "${SCRIPT_DIR}/../common.sh"
    load_env
    
    # 设置默认值
    TAG_PREFIX="${TAG_PREFIX:-${COMPANY}-sagemaker}"
    DOMAIN_NAME="${DOMAIN_NAME:-${COMPANY}-ml-platform}"
}

# -----------------------------------------------------------------------------
# 检查 AWS CLI 和凭证
# -----------------------------------------------------------------------------
check_aws_credentials() {
    log_section "AWS 凭证检查"
    
    log_check "AWS CLI 可用性"
    if command -v aws &> /dev/null; then
        log_ok "AWS CLI 已安装"
    else
        log_fail "AWS CLI 未安装"
        return 1
    fi
    
    log_check "AWS 凭证有效性"
    if aws sts get-caller-identity &> /dev/null; then
        local identity=$(aws sts get-caller-identity --query 'Arn' --output text)
        log_ok "凭证有效: $identity"
    else
        log_fail "AWS 凭证无效或已过期"
        log_info "请运行 'aws configure' 或确认 CloudShell 会话有效"
        return 1
    fi
    
    log_check "账号 ID 匹配"
    local current_account=$(aws sts get-caller-identity --query 'Account' --output text)
    if [[ "$current_account" == "$AWS_ACCOUNT_ID" ]]; then
        log_ok "账号 ID 匹配: $AWS_ACCOUNT_ID"
    else
        log_fail "账号 ID 不匹配"
        log_info "配置: $AWS_ACCOUNT_ID"
        log_info "当前: $current_account"
    fi
}

# -----------------------------------------------------------------------------
# 检查 VPC 配置
# -----------------------------------------------------------------------------
check_vpc() {
    log_section "VPC 网络检查"
    
    log_check "VPC 存在性: $VPC_ID"
    if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" &> /dev/null; then
        log_ok "VPC 存在"
    else
        log_fail "VPC 不存在: $VPC_ID"
        return 1
    fi
    
    log_check "VPC DNS 设置"
    local dns_hostnames=$(aws ec2 describe-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --attribute enableDnsHostnames \
        --query 'EnableDnsHostnames.Value' \
        --output text \
        --region "$AWS_REGION")
    
    local dns_support=$(aws ec2 describe-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --attribute enableDnsSupport \
        --query 'EnableDnsSupport.Value' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ "$dns_hostnames" == "True" ]]; then
        log_ok "DNS Hostnames: 已启用"
    else
        log_fail "DNS Hostnames: 未启用 (VPCOnly 模式必需)"
        log_info "修复: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames"
    fi
    
    if [[ "$dns_support" == "True" ]]; then
        log_ok "DNS Support: 已启用"
    else
        log_fail "DNS Support: 未启用 (VPCOnly 模式必需)"
        log_info "修复: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support"
    fi
}

# -----------------------------------------------------------------------------
# 检查子网
# -----------------------------------------------------------------------------
check_subnets() {
    log_section "子网检查"
    
    for subnet_id in "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID"; do
        log_check "子网: $subnet_id"
        
        local subnet_info=$(aws ec2 describe-subnets \
            --subnet-ids "$subnet_id" \
            --query 'Subnets[0].{AZ:AvailabilityZone,CIDR:CidrBlock,AvailableIPs:AvailableIpAddressCount,VpcId:VpcId}' \
            --output json \
            --region "$AWS_REGION" 2>/dev/null || echo "{}")
        
        if [[ -z "$subnet_info" || "$subnet_info" == "{}" ]]; then
            log_fail "子网不存在"
            continue
        fi
        
        local az=$(echo "$subnet_info" | jq -r '.AZ')
        local available_ips=$(echo "$subnet_info" | jq -r '.AvailableIPs')
        local subnet_vpc=$(echo "$subnet_info" | jq -r '.VpcId')
        
        # 检查子网是否属于正确的 VPC
        if [[ "$subnet_vpc" != "$VPC_ID" ]]; then
            log_fail "子网不属于配置的 VPC"
            log_info "子网 VPC: $subnet_vpc"
            log_info "配置 VPC: $VPC_ID"
            continue
        fi
        
        log_ok "存在于 $az"
        
        # 检查可用 IP
        if [[ $available_ips -lt 10 ]]; then
            log_fail "可用 IP 不足: $available_ips (需要至少 10 个)"
        elif [[ $available_ips -lt 50 ]]; then
            log_warn "可用 IP 较少: $available_ips"
        else
            log_ok "可用 IP: $available_ips"
        fi
    done
    
    # 检查子网是否在不同 AZ
    log_check "子网高可用性"
    local az1=$(aws ec2 describe-subnets --subnet-ids "$PRIVATE_SUBNET_1_ID" \
        --query 'Subnets[0].AvailabilityZone' --output text --region "$AWS_REGION" 2>/dev/null)
    local az2=$(aws ec2 describe-subnets --subnet-ids "$PRIVATE_SUBNET_2_ID" \
        --query 'Subnets[0].AvailabilityZone' --output text --region "$AWS_REGION" 2>/dev/null)
    
    if [[ "$az1" != "$az2" ]]; then
        log_ok "子网在不同 AZ: $az1, $az2"
    else
        log_warn "子网在同一 AZ: $az1 (建议使用不同 AZ 提高可用性)"
    fi
}

# -----------------------------------------------------------------------------
# 检查安全组
# -----------------------------------------------------------------------------
check_security_groups() {
    log_section "安全组检查"
    
    local sg_name="${TAG_PREFIX}-studio"
    log_check "SageMaker Studio 安全组: $sg_name"
    
    local sg_info=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[0]' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null || echo "null")
    
    if [[ "$sg_info" == "null" || -z "$sg_info" ]]; then
        log_fail "安全组不存在"
        log_info "请先运行: cd ../02-vpc && ./setup-all.sh"
        return 1
    fi
    
    local sg_id=$(echo "$sg_info" | jq -r '.GroupId')
    log_ok "安全组存在: $sg_id"
    
    # 检查入站规则
    log_check "安全组入站规则"
    local ingress_rules=$(echo "$sg_info" | jq '.IpPermissions | length')
    
    if [[ $ingress_rules -gt 0 ]]; then
        log_ok "入站规则数量: $ingress_rules"
        
        # 检查是否允许自身通信
        local self_ref=$(echo "$sg_info" | jq '[.IpPermissions[].UserIdGroupPairs[]? | select(.GroupId == "'"$sg_id"'")] | length')
        if [[ $self_ref -gt 0 ]]; then
            log_ok "允许安全组内部通信"
        else
            log_warn "未配置安全组内部通信规则"
        fi
    else
        log_warn "无入站规则"
    fi
}

# -----------------------------------------------------------------------------
# 检查 VPC Endpoints
# -----------------------------------------------------------------------------
check_vpc_endpoints() {
    log_section "VPC Endpoints 检查"
    
    local required_endpoints=(
        "com.amazonaws.${AWS_REGION}.sagemaker.api:sagemaker.api"
        "com.amazonaws.${AWS_REGION}.sagemaker.runtime:sagemaker.runtime"
        "aws.sagemaker.${AWS_REGION}.studio:sagemaker.studio"
        "com.amazonaws.${AWS_REGION}.sts:sts"
        "com.amazonaws.${AWS_REGION}.s3:s3"
    )
    
    for endpoint_spec in "${required_endpoints[@]}"; do
        local service="${endpoint_spec%%:*}"
        local display_name="${endpoint_spec##*:}"
        
        log_check "Endpoint: $display_name"
        
        local endpoint_info=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=service-name,Values=${service}" "Name=vpc-id,Values=${VPC_ID}" \
            --query 'VpcEndpoints[0].{Id:VpcEndpointId,State:State}' \
            --output json \
            --region "$AWS_REGION" 2>/dev/null || echo "null")
        
        if [[ "$endpoint_info" == "null" || -z "$endpoint_info" ]]; then
            log_fail "未创建"
            continue
        fi
        
        local endpoint_id=$(echo "$endpoint_info" | jq -r '.Id // "null"')
        local state=$(echo "$endpoint_info" | jq -r '.State // "unknown"')
        
        if [[ "$endpoint_id" == "null" ]]; then
            log_fail "未创建"
        elif [[ "$state" == "available" ]]; then
            log_ok "可用 ($endpoint_id)"
        elif [[ "$state" == "pending" ]]; then
            log_warn "创建中 ($endpoint_id) - 请等待几分钟"
        else
            log_fail "状态异常: $state ($endpoint_id)"
        fi
    done
}

# -----------------------------------------------------------------------------
# 检查 IAM Execution Roles
# -----------------------------------------------------------------------------
check_iam_roles() {
    log_section "IAM Execution Roles 检查"
    
    source "${SCRIPT_DIR}/../common.sh"
    
    local iam_path="/${COMPANY}-sagemaker/"
    
    # 首先检查 Domain 默认 Execution Role（必须存在）
    local default_role_name="SageMaker-Domain-DefaultExecutionRole"
    log_check "Domain 默认 Role: $default_role_name"
    
    if aws iam get-role --role-name "$default_role_name" &> /dev/null; then
        log_ok "存在"
        
        # 检查信任策略
        local trust=$(aws iam get-role --role-name "$default_role_name" \
            --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' \
            --output text 2>/dev/null)
        
        if [[ "$trust" == *"sagemaker"* ]]; then
            log_ok "信任策略正确 (sagemaker.amazonaws.com)"
        else
            log_warn "信任策略可能不正确: $trust"
        fi
        
        # 检查是否附加了 AmazonSageMakerFullAccess
        local has_policy=$(aws iam list-attached-role-policies \
            --role-name "$default_role_name" \
            --query "AttachedPolicies[?PolicyName=='AmazonSageMakerFullAccess'].PolicyName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$has_policy" ]]; then
            log_ok "已附加 AmazonSageMakerFullAccess"
        else
            log_fail "缺少 AmazonSageMakerFullAccess 策略"
        fi
    else
        log_fail "不存在 (必须！)"
        log_info "请先运行: cd ../01-iam && ./04-create-roles.sh"
    fi
    
    # 检查项目 Execution Roles
    for team in $TEAMS; do
        local team_fullname=$(get_team_fullname "$team")
        local team_formatted=$(format_name "$team_fullname")
        local projects=$(get_projects_for_team "$team")
        
        for project in $projects; do
            local project_formatted=$(format_name "$project")
            local role_name="SageMaker-${team_formatted}-${project_formatted}-ExecutionRole"
            
            log_check "Role: $role_name"
            
            if aws iam get-role --role-name "$role_name" &> /dev/null; then
                log_ok "存在"
                
                # 检查信任策略
                local trust=$(aws iam get-role --role-name "$role_name" \
                    --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' \
                    --output text 2>/dev/null)
                
                if [[ "$trust" == *"sagemaker"* ]]; then
                    log_ok "信任策略正确 (sagemaker.amazonaws.com)"
                else
                    log_warn "信任策略可能不正确: $trust"
                fi
            else
                log_fail "不存在"
                log_info "请先运行: cd ../01-iam && ./setup-all.sh"
            fi
        done
    done
}

# -----------------------------------------------------------------------------
# 诊断已存在的 Domain
# -----------------------------------------------------------------------------
diagnose_domain() {
    log_section "Domain 诊断"
    
    log_check "查找 Domain: $DOMAIN_NAME"
    
    local domain_id=$(aws sagemaker list-domains \
        --query "Domains[?DomainName=='${DOMAIN_NAME}'].DomainId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$domain_id" || "$domain_id" == "None" ]]; then
        log_info "Domain 不存在 (这是正常的，如果还未创建)"
        return 0
    fi
    
    log_ok "找到 Domain: $domain_id"
    
    local domain_info=$(aws sagemaker describe-domain \
        --domain-id "$domain_id" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    local status=$(echo "$domain_info" | jq -r '.Status')
    local failure_reason=$(echo "$domain_info" | jq -r '.FailureReason // "N/A"')
    
    log_check "Domain 状态: $status"
    
    case "$status" in
        InService)
            log_ok "Domain 运行正常"
            ;;
        Creating|Updating)
            log_warn "Domain 正在创建/更新中，请等待..."
            ;;
        Failed)
            log_fail "Domain 创建失败"
            echo ""
            echo -e "${RED}失败原因:${NC}"
            echo "  $failure_reason"
            echo ""
            echo -e "${YELLOW}建议操作:${NC}"
            analyze_failure_reason "$failure_reason"
            ;;
        Deleting)
            log_warn "Domain 正在删除中"
            ;;
        *)
            log_warn "未知状态: $status"
            ;;
    esac
    
    # 显示 Domain 配置
    echo ""
    echo "Domain 配置:"
    echo "  VPC ID:     $(echo "$domain_info" | jq -r '.VpcId')"
    echo "  Subnet IDs: $(echo "$domain_info" | jq -r '.SubnetIds | join(", ")')"
    echo "  Auth Mode:  $(echo "$domain_info" | jq -r '.AuthMode')"
    echo "  Network:    $(echo "$domain_info" | jq -r '.AppNetworkAccessType')"
}

# -----------------------------------------------------------------------------
# 分析失败原因并给出建议
# -----------------------------------------------------------------------------
analyze_failure_reason() {
    local reason="$1"
    
    if [[ "$reason" == *"VPC"* || "$reason" == *"subnet"* || "$reason" == *"network"* ]]; then
        echo "  1. 检查 VPC Endpoints 是否全部创建且状态为 available"
        echo "  2. 检查子网是否有足够的可用 IP"
        echo "  3. 确认安全组允许必要的入站/出站流量"
        echo ""
        echo "  运行: ./check.sh 查看详细检查结果"
    elif [[ "$reason" == *"IAM"* || "$reason" == *"role"* || "$reason" == *"permission"* ]]; then
        echo "  1. 检查 IAM Execution Roles 是否存在"
        echo "  2. 确认 Role 的信任策略包含 sagemaker.amazonaws.com"
        echo ""
        echo "  运行: cd ../01-iam && ./verify.sh"
    elif [[ "$reason" == *"security group"* ]]; then
        echo "  1. 检查安全组规则是否正确"
        echo "  2. 确认安全组允许内部通信"
        echo ""
        echo "  运行: cd ../02-vpc && ./verify.sh"
    elif [[ "$reason" == *"endpoint"* ]]; then
        echo "  1. 检查所有必需的 VPC Endpoints"
        echo "  2. 等待 Endpoints 状态变为 available"
        echo ""
        echo "  运行: cd ../02-vpc && ./verify.sh"
    else
        echo "  1. 检查所有前置依赖是否正确配置"
        echo "  2. 查看 CloudWatch Logs 获取更多信息"
        echo "  3. 联系 AWS Support 如果问题持续"
    fi
    
    echo ""
    echo -e "${YELLOW}清理失败的 Domain:${NC}"
    echo "  aws sagemaker delete-domain --domain-id \$DOMAIN_ID --retention-policy HomeEfsFileSystem=Delete --region $AWS_REGION"
}

# -----------------------------------------------------------------------------
# 打印总结
# -----------------------------------------------------------------------------
print_summary() {
    log_section "检查总结"
    
    echo ""
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo -e "${GREEN}✓ 所有检查通过！可以运行 ./setup-all.sh${NC}"
    elif [[ $errors -eq 0 ]]; then
        echo -e "${YELLOW}! 检查完成，有 $warnings 个警告${NC}"
        echo "  警告不会阻止创建，但建议检查"
    else
        echo -e "${RED}✗ 检查失败，有 $errors 个错误，$warnings 个警告${NC}"
        echo ""
        echo "请修复以上错误后再运行 setup-all.sh"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    local mode="full"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --diagnose|-d)
                mode="diagnose"
                shift
                ;;
            --quick|-q)
                mode="quick"
                shift
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --quick, -q     快速检查 (仅检查关键项)"
                echo "  --diagnose, -d  诊断模式 (检查失败的 Domain)"
                echo "  --help, -h      显示帮助"
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}=============================================="
    echo " SageMaker Domain 前置检查"
    echo "==============================================${NC}"
    
    load_environment
    
    export AWS_PAGER=""
    
    case $mode in
        quick)
            check_aws_credentials
            check_vpc
            check_vpc_endpoints
            ;;
        diagnose)
            check_aws_credentials
            diagnose_domain
            check_vpc_endpoints
            ;;
        full|*)
            check_aws_credentials
            check_vpc
            check_subnets
            check_security_groups
            check_vpc_endpoints
            check_iam_roles
            diagnose_domain
            ;;
    esac
    
    print_summary
    
    exit $errors
}

main "$@"

