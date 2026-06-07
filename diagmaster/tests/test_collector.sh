#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 性能采集模块测试
# 测试 collector.sh 的 CPU/内存/磁盘采集功能
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"
source "$TEST_DIR/lib/mock_utils.sh"

# ==============================================================
# 测试用例
# ==============================================================

test_collect_cpu() {
    echo "[TEST] 采集模块 - CPU 采集函数"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local cpu_val
    cpu_val=$(collect_cpu 2>/dev/null || echo "N/A")
    teardown_mocks
    if [ "$cpu_val" != "N/A" ] && [ -n "$cpu_val" ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_cpu 正常执行，返回值=${cpu_val}"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_cpu 无法获取CPU数据"
    fi
}

test_collect_memory() {
    echo "[TEST] 采集模块 - 内存采集函数"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local mem_val
    mem_val=$(collect_memory 2>/dev/null || echo "N/A")
    teardown_mocks
    if [ "$mem_val" != "N/A" ] && [ -n "$mem_val" ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_memory 正常执行，返回值=${mem_val}"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_memory 无法获取内存数据"
    fi
}

test_collect_disk() {
    echo "[TEST] 采集模块 - 磁盘采集函数"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local disk_val
    disk_val=$(collect_disk 2>/dev/null || echo "N/A")
    teardown_mocks
    if [ "$disk_val" != "N/A" ] && [ -n "$disk_val" ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_disk 正常执行，返回值=${disk_val}"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_disk 无法获取磁盘数据"
    fi
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 性能采集模块测试 (3个用例)"
    echo "=============================================="
    echo ""

    test_collect_cpu
    test_collect_memory
    test_collect_disk

    test_summary || true
}

run_all_tests || true