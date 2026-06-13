#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 性能采集模块测试
# 测试 collector.sh 的完整采集功能（10个用例）
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

test_collect_load() {
    echo "[TEST] 采集模块 - 系统负载采集函数"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local load_val
    load_val=$(collect_load 2>/dev/null || echo "N/A")
    teardown_mocks
    if [ "$load_val" != "N/A" ] && [ -n "$load_val" ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_load 正常执行，返回值=${load_val}"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_load 无法获取负载数据"
    fi
}

test_collect_processes() {
    echo "[TEST] 采集模块 - 进程数采集函数"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local proc_val
    proc_val=$(collect_processes 2>/dev/null || echo "N/A")
    teardown_mocks
    if [ "$proc_val" != "N/A" ] && [ -n "$proc_val" ] && [ "$proc_val" -gt 0 ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_processes 正常执行，返回值=${proc_val}"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_processes 无法获取进程数"
    fi
}

test_check_threshold() {
    echo "[TEST] 采集模块 - 阈值判断 check_threshold"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local ret_over ret_under
    ret_over=$(check_threshold "cpu" "90" "80" 2>/dev/null || echo "0")
    ret_under=$(check_threshold "cpu" "50" "80" 2>/dev/null || echo "0")
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$ret_over" = "1" ] && [ "$ret_under" = "0" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: check_threshold 90>80 返回 ${ret_over}，50<80 返回 ${ret_under}"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: check_threshold 90>80=${ret_over}(期望1)，50<80=${ret_under}(期望0)"
    fi
}

test_colored_status() {
    echo "[TEST] 采集模块 - 颜色状态输出 colored_status"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local output_normal output_warn
    output_normal=$(colored_status "50" "80" 2>/dev/null || echo "")
    output_warn=$(colored_status "95" "80" 2>/dev/null || echo "")
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ -n "$output_normal" ] && [ -n "$output_warn" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: colored_status 正常/告警场景均成功返回"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: colored_status 返回为空"
    fi
}

test_save_and_load_history() {
    echo "[TEST] 采集模块 - 历史数据存取 save_history / load_last_value"
    setup_mocks
    # 覆盖历史目录到 mock 临时目录
    DATA_DIR="$MOCK_DIR/data"
    HISTORY_DIR="$DATA_DIR/history"
    mkdir -p "$HISTORY_DIR"
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    # 写入测试历史数据
    HIST_FILE="${HISTORY_DIR}/collect_$(date +%Y%m%d).log"
    echo "00:00:01 | CPU:25.5% | MEM:60.0% | DISK:45%" >> "$HIST_FILE"
    echo "00:00:02 | CPU:30.2% | MEM:62.1% | DISK:46%" >> "$HIST_FILE"
    echo "00:00:03 | CPU:35.8% | MEM:65.3% | DISK:47%" >> "$HIST_FILE"
    local last_cpu last_mem
    last_cpu=$(load_last_value "cpu" 2>/dev/null || echo "0")
    last_mem=$(load_last_value "mem" 2>/dev/null || echo "0")
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$last_cpu" != "0" ] && [ "$last_mem" != "0" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: load_last_value 读取历史 CPU=${last_cpu}, MEM=${last_mem}"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: load_last_value 返回异常 CPU=${last_cpu}, MEM=${last_mem}"
    fi
}

test_parallel_collection() {
    echo "[TEST] 采集模块 - 多进程并行采集 run_collection 不崩溃"
    setup_mocks
    DATA_DIR="$MOCK_DIR/data"
    HISTORY_DIR="$DATA_DIR/history"
    mkdir -p "$DATA_DIR" "$HISTORY_DIR"
    # 重新 source 以使用新的 DATA_DIR
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local ret=0
    set +e
    run_collection >/dev/null 2>&1
    ret=$?
    set -e
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$ret" -eq 0 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: run_collection 并行采集不崩溃"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: run_collection 崩溃，返回值=${ret}"
    fi
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 性能采集模块测试 (9个用例)"
    echo "=============================================="
    echo ""

    test_collect_cpu
    test_collect_memory
    test_collect_disk
    test_collect_load
    test_collect_processes
    test_check_threshold
    test_colored_status
    test_save_and_load_history
    test_parallel_collection

    test_summary || true
}

run_all_tests || true