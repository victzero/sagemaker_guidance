#!/bin/bash
# =============================================================================
# setup-all.sh - S3 配置主控脚本
# =============================================================================
# 使用方法: ./setup-all.sh
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

echo ""
echo -e "${CYAN}=============================================="
echo " SageMaker S3 Setup - Master Script"
echo "==============================================${NC}"
echo ""

# 加载共享函数库和环境变量
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
validate_team_env
check_aws_cli

# 设置 S3 特有配置
ENCRYPTION_TYPE="${ENCRYPTION_TYPE:-SSE-S3}"
ENABLE_VERSIONING="${ENABLE_VERSIONING:-true}"
CREATE_SHARED_BUCKET="${CREATE_SHARED_BUCKET:-true}"
ABORT_INCOMPLETE_DAYS="${ABORT_INCOMPLETE_DAYS:-7}"
NONCURRENT_EXPIRATION_DAYS="${NONCURRENT_EXPIRATION_DAYS:-90}"

# 确认执行
echo -e "${YELLOW}This script will create the following AWS S3 resources:${NC}"
echo ""
echo "  Company:       $COMPANY"
echo "  Region:        $AWS_REGION"
echo "  Encryption:    $ENCRYPTION_TYPE"
echo "  Versioning:    $ENABLE_VERSIONING"
echo ""

# ========== Buckets ==========
echo -e "${BLUE}【Buckets】${NC}"
bucket_count=0

for team in $TEAMS; do
    team_fullname=$(get_team_fullname "$team")
    projects=$(get_projects_for_team "$team")
    
    if [[ -n "$projects" ]]; then
        echo "  Team [$team - $team_fullname]:"
        for project in $projects; do
            bucket_name=$(get_bucket_name "$team" "$project")
            echo "    - $bucket_name"
            ((bucket_count++)) || true
        done
    fi
done

if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  Shared bucket:"
    shared_bucket=$(get_shared_bucket_name)
    echo "    - $shared_bucket"
    ((bucket_count++)) || true
fi

echo "  Total: $bucket_count buckets"
echo ""

# ========== Bucket Policies ==========
echo -e "${BLUE}【Bucket Policies】${NC}"
policy_count=0

for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        bucket_name=$(get_bucket_name "$team" "$project")
        echo "  - Policy for: $bucket_name"
        echo "      • SageMaker execution role access"
        echo "      • Team principal access (rw)"
        ((policy_count++)) || true
    done
done

if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  - Policy for: $(get_shared_bucket_name)"
    echo "      • All execution roles (read-only)"
    ((policy_count++)) || true
fi

echo "  Total: $policy_count bucket policies"
echo ""

# ========== Lifecycle Rules ==========
echo -e "${BLUE}【Lifecycle Rules】${NC}"
lifecycle_count=0

for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        bucket_name=$(get_bucket_name "$team" "$project")
        echo "  - Lifecycle for: $bucket_name"
        ((lifecycle_count++)) || true
    done
done

if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  - Lifecycle for: $(get_shared_bucket_name)"
    ((lifecycle_count++)) || true
fi

echo "  Total: $lifecycle_count lifecycle configurations"
echo ""

# ========== Directory Structures ==========
echo -e "${BLUE}【Directory Structures】${NC}"
echo "  Project buckets will have:"
echo "    raw/uploads/, raw/external/"
echo "    processed/cleaned/, processed/transformed/"
echo "    features/v1/"
echo "    models/training/, models/artifacts/, models/registry/"
echo "    notebooks/archived/"
echo "    outputs/reports/, outputs/predictions/"
echo "    temp/"
echo ""
echo "  Shared bucket will have:"
echo "    scripts/preprocessing/, scripts/utils/"
echo "    containers/dockerfiles/"
echo "    datasets/reference/"
echo "    documentation/"
echo ""

# ========== Bucket Configurations ==========
echo -e "${BLUE}【Bucket Configurations】${NC}"
echo "  All buckets will be configured with:"
echo "    • Public access blocked"
echo "    • Server-side encryption ($ENCRYPTION_TYPE)"
if [[ "${ENABLE_VERSIONING}" == "true" ]]; then
echo "    • Versioning enabled"
fi
echo "    • Tags: Team, Project, Environment, CostCenter, ManagedBy"
echo ""

# ========== Lifecycle Settings ==========
echo -e "${BLUE}【Lifecycle Settings】${NC}"
echo "  Abort incomplete multipart uploads: ${ABORT_INCOMPLETE_DAYS} days"
echo "  Noncurrent version expiration:      ${NONCURRENT_EXPIRATION_DAYS} days"
echo "  Delete expired object markers:      true"
echo ""

# ========== Summary ==========
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $bucket_count buckets, $policy_count policies, $lifecycle_count lifecycle rules${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws s3 ls | grep ${COMPANY}-sm-"
echo "  aws s3api get-bucket-tagging --bucket BUCKET_NAME"
echo "  aws s3api get-bucket-policy --bucket BUCKET_NAME"
echo ""

read -p "Do you want to proceed? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# 记录开始时间
START_TIME=$(date +%s)

# 执行步骤
run_step() {
    local step=$1
    local script=$2
    local description=$3
    
    echo ""
    echo -e "${BLUE}=============================================="
    echo -e " Step ${step}: ${description}"
    echo -e "==============================================${NC}"
    
    if [[ -x "${SCRIPT_DIR}/${script}" ]]; then
        "${SCRIPT_DIR}/${script}"
        echo -e "${GREEN}[OK]${NC} Step ${step} completed"
    else
        echo -e "${RED}[ERROR]${NC} Script ${script} not found or not executable"
        exit 1
    fi
}

# 执行所有步骤
run_step 1 "01-create-buckets.sh" "Create S3 Buckets"
run_step 2 "02-configure-policies.sh" "Configure Bucket Policies"
run_step 3 "03-configure-lifecycle.sh" "Configure Lifecycle Rules"

# 计算耗时
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}=============================================="
echo " S3 Setup Complete!"
echo "==============================================${NC}"
echo ""
echo "Duration: ${DURATION} seconds"
echo ""
echo -e "${GREEN}Created Buckets:${NC}"
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        echo "  - $(get_bucket_name "$team" "$project")"
    done
done
if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
    echo "  - $(get_shared_bucket_name)"
fi
echo ""
echo "Bucket list saved to: ${SCRIPT_DIR}/output/buckets.env"
echo ""
echo "Verify resources with:"
echo "  ./verify.sh"
echo ""
echo "Filter resources in AWS Console or CLI:"
echo "  aws s3 ls | grep ${COMPANY}-sm-"
echo "  aws s3api get-bucket-tagging --bucket BUCKET_NAME"
echo ""
echo "Next Steps:"
echo "  1. Verify configuration: ./verify.sh"
echo "  2. Create SageMaker Domain (see docs/05-sagemaker-domain.md)"
echo "  3. Create User Profiles (see docs/06-user-profile.md)"
echo ""
