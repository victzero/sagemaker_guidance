#!/bin/bash
# =============================================================================
# setup-all.sh - ECR 一键设置
# =============================================================================
# 用法: ./setup-all.sh [--skip-lifecycle]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 参数解析
SKIP_LIFECYCLE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-lifecycle)
            SKIP_LIFECYCLE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-lifecycle]"
            echo ""
            echo "Options:"
            echo "  --skip-lifecycle  Skip lifecycle policy configuration"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                       SageMaker ECR Setup (Phase 2B)                       ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║  This script will create ECR repositories for SageMaker                    ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 步骤执行函数
run_step() {
    local step_num=$1
    local script_name=$2
    local description=$3
    
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────────┐"
    echo "│ Step $step_num: $description"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    
    if [[ -f "${SCRIPT_DIR}/${script_name}" ]]; then
        bash "${SCRIPT_DIR}/${script_name}"
    else
        echo "[ERROR] Script not found: ${script_name}"
        exit 1
    fi
}

# 执行步骤
run_step 1 "01-create-repositories.sh" "Create ECR Repositories"

# 验证
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────────┐"
echo "│ Verification"
echo "└──────────────────────────────────────────────────────────────────────────────┘"
echo ""

bash "${SCRIPT_DIR}/verify.sh"

# 完成
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                      ✅ ECR Setup Completed!                               ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                            ║"
echo "║  Output files:                                                             ║"
echo "║    - 06-ecr/output/repositories.env                                        ║"
echo "║                                                                            ║"
echo "║  Next Steps:                                                               ║"
echo "║    1. Build and push custom images (if needed)                             ║"
echo "║    2. Continue to 07-model-registry                                        ║"
echo "║                                                                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

