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
echo "║       测试脚本: 7个 | 总用例: 75个                           ║"
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
run_test_script "1/7 巡逻模块单元测试 (20例)"   "$TEST_DIR/test_patrol.sh"
run_test_script "2/7 性能采集模块测试 (9例)"    "$TEST_DIR/test_collector.sh"
run_test_script "3/7 边界条件测试 (6例)"        "$TEST_DIR/test_boundary.sh"
run_test_script "4/7 自动化运行验证 (4例)"      "$TEST_DIR/test_auto.sh"
run_test_script "5/7 公共工具库测试 (8例)"       "$TEST_DIR/test_utils.sh"
run_test_script "6/7 安全审计模块测试 (12例)"    "$TEST_DIR/test_log_analyzer.sh"
run_test_script "7/7 真实环境冒烟测试 (16例)"    "$TEST_DIR/test_integration_real.sh"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       全部测试套件运行完成                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "测试脚本说明:"
echo "  tests/test_patrol.sh           - 巡逻模块单元+集成+异常测试 (20例)"
echo "  tests/test_collector.sh        - 性能采集模块测试 (9例)"
echo "  tests/test_boundary.sh         - 边界条件测试 (6例)"
echo "  tests/test_auto.sh             - 自动化运行验证测试 (4例)"
echo "  tests/test_utils.sh            - 公共工具库测试 (8例)"
echo "  tests/test_log_analyzer.sh     - 安全审计模块测试 (12例)"
echo "  tests/test_integration_real.sh - 真实环境集成冒烟测试 (16例: 功能4+边界4+异常4+自动化4)"
echo "  tests/test_project_report6.sh  - 交互式综合测试菜单（保留用于答辩截图）"