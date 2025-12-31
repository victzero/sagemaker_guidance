#!/bin/bash
# 测试所有策略函数的 JSON 是否有效

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 先初始化环境
source "${SCRIPT_DIR}/00-init.sh"
init

# 现在从 01-create-policies.sh 中提取函数定义（跳过 init 调用）
# 使用 sed 提取函数定义部分
eval "$(sed -n '/^generate_/,/^}/p' "${SCRIPT_DIR}/01-create-policies.sh")"

echo ""
echo "Testing policy JSON validity..."
echo ""

test_policy() {
    local name=$1
    local json=$2
    
    if [ -z "$json" ]; then
        echo "✗ $name - EMPTY OUTPUT"
        return
    fi
    
    if echo "$json" | python3 -m json.tool > /dev/null 2>&1; then
        echo "✓ $name"
    else
        echo "✗ $name - INVALID JSON:"
        echo "--- Error: ---"
        echo "$json" | python3 -m json.tool 2>&1 | head -3
        echo "--- First 300 chars of output: ---"
        echo "$json" | head -c 300
        echo ""
        echo ""
    fi
}

echo "=== Base Policies ==="
test_policy "base_access" "$(generate_base_access_policy)"
test_policy "readonly" "$(generate_readonly_policy)"
test_policy "self_service" "$(generate_self_service_policy)"
test_policy "boundary" "$(generate_user_boundary_policy)"

echo ""
echo "=== Team Policies ==="
for team in $TEAMS; do
    test_policy "team_access($team)" "$(generate_team_access_policy $team)"
done

echo ""
echo "=== Project Policies ==="
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        test_policy "project_access($team/$project)" "$(generate_project_access_policy $team $project)"
        test_policy "execution_role($team/$project)" "$(generate_execution_role_policy $team $project)"
    done
done

echo ""
echo "=== All Done ==="
