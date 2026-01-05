#!/bin/bash
# =============================================================================
# setup-all.sh - Model Registry 一键设置
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                  SageMaker Model Registry Setup (Phase 2C)                 ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║  This script will create Model Package Groups for model version control    ║"
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
run_step 1 "01-create-model-groups.sh" "Create Model Package Groups"

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
echo "║                    ✅ Model Registry Setup Completed!                      ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                            ║"
echo "║  Output files:                                                             ║"
echo "║    - 07-model-registry/output/model-groups.env                             ║"
echo "║                                                                            ║"
echo "║  Next Steps:                                                               ║"
echo "║    1. Start using Processing/Training Jobs                                 ║"
echo "║    2. Register trained models to Model Registry                            ║"
echo "║    3. Deploy models to endpoints                                           ║"
echo "║                                                                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

