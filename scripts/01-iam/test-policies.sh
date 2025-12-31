#!/bin/bash
# 测试所有策略函数的 JSON 是否有效

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"
init > /dev/null 2>&1

echo "Testing policy JSON validity..."
echo ""

test_policy() {
    local name=$1
    local json=$2
    
    if echo "$json" | python3 -m json.tool > /dev/null 2>&1; then
        echo "✓ $name"
    else
        echo "✗ $name - INVALID JSON:"
        echo "$json" | python3 -m json.tool 2>&1 | head -20
        echo ""
    fi
}

echo "=== Base Policies ==="
test_policy "generate_base_access_policy" "$(generate_base_access_policy)"
test_policy "generate_readonly_policy" "$(generate_readonly_policy)"
test_policy "generate_self_service_policy" "$(generate_self_service_policy)"
test_policy "generate_user_boundary_policy" "$(generate_user_boundary_policy)"

echo ""
echo "=== Team Policies ==="
for team in $TEAMS; do
    test_policy "generate_team_access_policy($team)" "$(generate_team_access_policy $team)"
done

echo ""
echo "=== Project Policies ==="
for team in $TEAMS; do
    projects=$(get_projects_for_team "$team")
    for project in $projects; do
        test_policy "generate_project_access_policy($team, $project)" "$(generate_project_access_policy $team $project)"
        test_policy "generate_execution_role_policy($team, $project)" "$(generate_execution_role_policy $team $project)"
    done
done

echo ""
echo "Done!"
