#!/bin/bash
# 测试所有策略函数的 JSON 是否有效

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"
init > /dev/null 2>&1

# 从脚本中提取函数定义
source <(sed -n '/^generate_/,/^POLICYEOF$/p; /^get_/,/^}/p; /^format_name/,/^}/p' "${SCRIPT_DIR}/01-create-policies.sh" 2>/dev/null)

echo ""
echo "Testing policy JSON validity..."
echo ""

test_policy() {
    local name=$1
    local json=$2
    
    if [ -z "$json" ]; then
        echo "✗ $name - EMPTY OUTPUT"
        return 1
    fi
    
    if echo "$json" | python3 -m json.tool > /dev/null 2>&1; then
        echo "✓ $name"
        return 0
    else
        echo "✗ $name - INVALID JSON:"
        echo "$json" | python3 -m json.tool 2>&1 | head -3
        return 1
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
