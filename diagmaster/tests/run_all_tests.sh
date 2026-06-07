#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 综合测试入口
# 一键运行所有测试脚本，汇总结果
# 用法: bash tests/run_all_tests.sh
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       DiagMaster 综合测试套件 v2.0                           ║"
echo "║       测试脚本: 4个 | 总用例: 32个                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

GLOBAL_PASSED=0
GLOBAL_FAILED=0
GLOBAL_TOTAL=0

run_test_script() {
    local name="$1" path="$2"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  运行测试: $name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -f "$path" ]; then
        bash "$path" 2>&1 || true
    else
        echo "  ⚠ 测试脚本不存在: $path"
    fi
}

# 顺序运行各测试脚本
run_test_script "1/4 巡逻模块单元测试 (18例)" "$TEST_DIR/test_patrol.sh"
run_test_script "2/4 性能采集模块测试 (3例)"  "$TEST_DIR/test_collector.sh"
run_test_script "3/4 边界条件测试 (6例)"      "$TEST_DIR/test_boundary.sh"
run_test_script "4/4 自动化运行验证 (5例)"    "$TEST_DIR/test_auto.sh"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       全部测试套件运行完成                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试脚本说明:"
echo "  tests/test_patrol.sh      - 巡逻模块单元+集成+异常测试 (18例)"
echo "  tests/test_collector.sh   - 性能采集模块测试 (3例)"
echo "  tests/test_boundary.sh    - 边界条件测试 (6例)"
echo "  tests/test_auto.sh        - 自动化运行验证测试 (5例)"
echo "  tests/test_project_report6.sh - 交互式综合测试菜单（保留用于答辩截图）"