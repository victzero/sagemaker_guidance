#!/bin/bash
# =============================================================================
# list-instance-whitelists.sh - 列出所有项目的实例类型白名单配置
# =============================================================================
#
# 功能:
#   显示所有项目的实例类型白名单配置状态
#   包括初始配置和当前实际生效的配置
#
# 使用:
#   ./list-instance-whitelists.sh [--presets]
#
# 选项:
#   --presets    同时显示所有可用的预设定义
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-init.sh"

# =============================================================================
# 参数解析
# =============================================================================
SHOW_PRESETS=false

for arg in "$@"; do
    case "$arg" in
        --presets)
            SHOW_PRESETS=true
            ;;
        --help|-h)
            echo "Usage: $0 [--presets]"
            echo ""
            echo "Options:"
            echo "  --presets    显示所有可用的预设定义"
            exit 0
            ;;
    esac
done

# =============================================================================
# 主函数
# =============================================================================
main() {
    init_silent
    
    echo ""
    echo "=============================================="
    echo " 实例类型白名单状态"
    echo "=============================================="
    echo ""
    
    # 显示预设定义（如果请求）
    if [[ "$SHOW_PRESETS" == "true" ]]; then
        print_preset_details
    fi
    
    # 列出所有项目的白名单
    echo ""
    echo "Project Instance Type Whitelist Status"
    echo "======================================="
    echo ""
    printf "%-12s %-25s %-15s %-50s\n" "Team" "Project" "Init Preset" "Current Whitelist"
    echo "────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    local total=0
    local restricted=0
    local unrestricted=0
    
    for team in $TEAMS; do
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local preset=$(get_project_whitelist_preset "$team" "$project")
            local current=$(get_current_whitelist "$team" "$project")
            
            # 截断显示
            local current_display="$current"
            if [[ ${#current_display} -gt 50 ]]; then
                current_display="${current_display:0:47}..."
            fi
            
            # 统计
            ((total++)) || true
            if [[ "$current" == "unrestricted" ]]; then
                ((unrestricted++)) || true
            else
                ((restricted++)) || true
            fi
            
            printf "%-12s %-25s %-15s %-50s\n" "$team" "$project" "$preset" "$current_display"
        done
    done
    
    echo ""
    echo "────────────────────────────────────────────────────────────────────────────────────────────────────────"
    echo "Summary: $total projects total, $restricted restricted, $unrestricted unrestricted"
    echo ""
    
    # 提示
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📌 管理命令:"
    echo ""
    echo "  查看详情:    ./project/set-instance-whitelist.sh <team> <project> show"
    echo "  更改预设:    ./project/set-instance-whitelist.sh <team> <project> preset <name>"
    echo "  自定义类型:  ./project/set-instance-whitelist.sh <team> <project> custom <types>"
    echo "  重置配置:    ./project/set-instance-whitelist.sh <team> <project> reset"
    echo ""
    echo "  显示预设:    $0 --presets"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main

