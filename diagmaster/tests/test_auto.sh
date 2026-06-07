#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 自动化运行验证测试
# 测试巡逻模块的连续运行稳定性、一致性和无人值守能力（4个用例）
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"
source "$TEST_DIR/lib/mock_utils.sh"

# 设置测试阈值
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false
LOG_FILE="/tmp/test_auto_patrol.log"
mkdir -p "$(dirname "$LOG_FILE")"

source "$PROJECT_ROOT/modules/patrol.sh"
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false

# ==============================================================
# 测试用例
# ==============================================================

test_auto_consistency() {
    echo "[TEST] 自动：连续5次运行结果一致性"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    local results=()
    for i in $(seq 1 5); do
        local ret
        run_patrol >/dev/null 2>&1
        ret=$?
        results+=($ret)
    done
    local all_same="是"
    for r in "${results[@]}"; do
        [ "$r" != "${results[0]}" ] && all_same="否"
    done
    local report_count
    report_count=$(ls -1 "$PATROL_REPORT_DIR"/*.md 2>/dev/null | wc -l)
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$all_same" = "是" ] && [ "$report_count" -ge 5 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 5次运行结果一致（返回值: ${results[*]}），报告数=${report_count}"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 结果不一致或报告缺失（返回值: ${results[*]}，报告数=${report_count}）"
    fi
}

test_auto_stability() {
    echo "[TEST] 自动：连续10次运行无崩溃"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    local crashes=0
    for i in $(seq 1 10); do
        set +e
        run_patrol >/dev/null 2>&1
        local ret=$?
        set -e
        if [ "$ret" -ne 0 ] && [ "$ret" -ne 1 ]; then
            crashes=$((crashes + 1))
        fi
    done
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$crashes" -eq 0 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 连续10次运行无崩溃"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 出现 ${crashes} 次崩溃"
    fi
}

test_auto_unattended() {
    echo "[TEST] 自动：无人值守守护进程模拟（3轮）"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    local rounds=3
    local success_rounds=0
    for round in $(seq 1 $rounds); do
        set +e
        run_patrol >/dev/null 2>&1
        local ret=$?
        set -e
        if [ "$ret" -eq 0 ] || [ "$ret" -eq 1 ]; then
            success_rounds=$((success_rounds + 1))
        fi
        sleep 0.1
    done
    local report_count
    report_count=$(ls -1 "$PATROL_REPORT_DIR"/*.md 2>/dev/null | wc -l)
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$success_rounds" -eq "$rounds" ] && [ "$report_count" -ge "$rounds" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 无人值守3轮全部成功，报告数=${report_count}"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 成功轮次=${success_rounds}/${rounds}，报告数=${report_count}"
    fi
}

test_auto_mixed_state() {
    echo "[TEST] 自动：混合状态处理（部分正常+部分异常）"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd nginx"
    PROCESSES_TO_CHECK="sshd nginx"
    run_patrol >/dev/null 2>&1
    local ret=$?
    local report
    report=$(ls -1t "$PATROL_REPORT_DIR"/*.md 2>/dev/null | head -n1)
    local has_abnormal="否"
    if [ -f "$report" ]; then
        if grep -q "存在异常" "$report" 2>/dev/null; then
            has_abnormal="是"
        fi
    fi
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$ret" = "1" ] && [ "$has_abnormal" = "是" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 混合状态正确返回1，报告含'存在异常'"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 返回值=${ret}，报告含异常标记=${has_abnormal}"
    fi
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 自动化运行验证测试 (4个用例)"
    echo "=============================================="
    echo ""

    test_auto_consistency
    test_auto_stability
    test_auto_unattended
    test_auto_mixed_state

    test_summary || true
}

run_all_tests || true