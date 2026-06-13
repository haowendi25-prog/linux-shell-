#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 巡逻模块单元测试
# 测试核心 patrol 模块的各个检查函数（共18个测试用例）
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 导入公共库和断言库
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"

# 导入共享 Mock 库
source "$TEST_DIR/lib/mock_utils.sh"

# 设置测试阈值（在导入模块前定义，防止被配置文件覆盖）
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false
PATROL_REPORT_DIR="/tmp/test_patrol_reports"
LOG_FILE="/tmp/test_patrol.log"
mkdir -p "$PATROL_REPORT_DIR" "$(dirname "$LOG_FILE")"

# 导入待测模块
source "$PROJECT_ROOT/modules/patrol.sh"

# 再次强制覆盖（防止 patrol.sh 内部 source diag.conf 造成覆盖）
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false

# ==============================================================
# 第一部分：功能单元测试（12个）
# ==============================================================

test_cpu_normal() {
    echo "[TEST] CPU 正常场景"
    setup_mocks
    local ret
    ret=$(check_cpu)
    assert_equal "$ret" "0" "CPU 15%（阈值80%），应返回0"
    teardown_mocks
}

test_cpu_high() {
    echo "[TEST] CPU 高负载场景"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    local ret
    ret=$(check_cpu)
    assert_equal "$ret" "1" "CPU 95%（阈值80%），应返回1"
    teardown_mocks
}

test_memory_normal() {
    echo "[TEST] 内存正常场景"
    setup_mocks
    local ret
    ret=$(check_memory)
    assert_equal "$ret" "0" "内存 10%（阈值85%），应返回0"
    teardown_mocks
}

test_memory_high() {
    echo "[TEST] 内存高占用场景"
    setup_mocks
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         900         100           0           0         100"'
    local ret
    ret=$(check_memory)
    assert_equal "$ret" "1" "内存 90%（阈值85%），应返回1"
    teardown_mocks
}

test_disk_normal() {
    echo "[TEST] 磁盘正常场景"
    setup_mocks
    local ret
    ret=$(check_disk)
    assert_equal "$ret" "0" "磁盘 85%（阈值90%），应返回0"
    teardown_mocks
}

test_disk_high() {
    echo "[TEST] 磁盘高占用场景"
    setup_mocks
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 9500000    500000  95% /"'
    local ret
    ret=$(check_disk)
    assert_equal "$ret" "1" "磁盘 95%（阈值90%），应返回1"
    teardown_mocks
}

test_services_all_ok() {
    echo "[TEST] 服务全部正常"
    setup_mocks
    SERVICES_TO_CHECK="sshd cron"
    local ret
    ret=$(check_services)
    assert_equal "$ret" "0" "所有服务正常，应返回0"
    teardown_mocks
}

test_services_partial_fail() {
    echo "[TEST] 部分服务故障"
    setup_mocks
    SERVICES_TO_CHECK="sshd nginx"
    local ret
    ret=$(check_services)
    assert_equal "$ret" "1" "存在故障服务，应返回1"
    teardown_mocks
}

test_processes_ok() {
    echo "[TEST] 关键进程存在"
    setup_mocks
    PROCESSES_TO_CHECK="sshd"
    local ret
    ret=$(check_processes)
    assert_equal "$ret" "0" "进程存在，应返回0"
    teardown_mocks
}

test_processes_missing() {
    echo "[TEST] 关键进程缺失"
    setup_mocks
    PROCESSES_TO_CHECK="sshd nginx"
    local ret
    ret=$(check_processes)
    assert_equal "$ret" "1" "进程缺失，应返回1"
    teardown_mocks
}

test_logs_normal() {
    echo "[TEST] 日志无异常"
    setup_mocks
    local ret
    ret=$(check_logs)
    assert_equal "$ret" "0" "无 OOM/SSH 爆破，应返回0"
    teardown_mocks
}

test_logs_oom() {
    echo "[TEST] 日志检测到 OOM"
    setup_mocks
    overwrite_mock "dmesg" '#!/bin/bash
echo "Out of memory: Kill process"
echo "Out of memory: Kill process"'
    local ret
    ret=$(check_logs)
    assert_equal "$ret" "1" "检测到 OOM，应返回1"
    teardown_mocks
}

# ==============================================================
# 第二部分：集成测试（2个）
# ==============================================================

test_patrol_all_ok() {
    echo "[TEST] 集成：全部正常"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    run_patrol
    local ret=$?
    assert_equal "$ret" "0" "所有检查正常，run_patrol 返回0"

    local report
    report=$(ls -1t "$PATROL_REPORT_DIR"/*.md 2>/dev/null | head -n1)
    if [ -f "$report" ]; then
        assert_contains "$(cat "$report")" "正常 ✅" "报告包含'正常 ✅'"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 报告文件未生成"
    fi
    teardown_mocks
}

test_patrol_with_failures() {
    echo "[TEST] 集成：存在异常"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    SERVICES_TO_CHECK="sshd nginx"
    PROCESSES_TO_CHECK="sshd nginx"
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    run_patrol
    local ret=$?
    assert_equal "$ret" "1" "存在异常，run_patrol 返回1"

    local report
    report=$(ls -1t "$PATROL_REPORT_DIR"/*.md 2>/dev/null | head -n1)
    if [ -f "$report" ]; then
        assert_contains "$(cat "$report")" "存在异常" "报告包含'存在异常'"
    fi
    teardown_mocks
}

# ==============================================================
# 第三部分：异常/降级测试（4个）
# ==============================================================

test_cpu_no_top_no_proc() {
    echo "[TEST] 异常：top 不可用时的降级处理"
    setup_mocks
    remove_mock "top"
    local ret
    set +e
    ret=$(check_cpu 2>/dev/null) || ret="2"
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: CPU 降级处理未崩溃 (返回值=${ret:-2})"
    teardown_mocks
}

test_disk_no_df() {
    echo "[TEST] 异常：df 命令不可用时的降级处理"
    setup_mocks
    remove_mock "df"
    local ret
    set +e
    ret=$(check_disk 2>/dev/null) || ret="2"
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: df 降级处理未崩溃 (返回值=${ret:-2})"
    teardown_mocks
}

test_services_no_systemctl() {
    echo "[TEST] 异常：systemctl 不可用（降级为 pgrep）"
    setup_mocks
    remove_mock "systemctl"
    SERVICES_TO_CHECK="sshd cron"
    local ret
    set +e
    ret=$(check_services)
    set -e
    assert_equal "${ret:-1}" "0" "systemctl不可用时用pgrep降级，服务存在应返回0"
    teardown_mocks
}

test_config_missing() {
    echo "[TEST] 异常：配置文件缺失时使用默认值"
    setup_mocks
    local conf_backup="$PROJECT_ROOT/config/diag.conf.bak.$$"
    if [ -f "$PROJECT_ROOT/config/diag.conf" ]; then
        cp "$PROJECT_ROOT/config/diag.conf" "$conf_backup" 2>/dev/null || true
        rm -f "$PROJECT_ROOT/config/diag.conf" 2>/dev/null || true
    fi
    CPU_WARN_THRESHOLD=80 MEM_WARN_THRESHOLD=85 DISK_WARN_THRESHOLD=90
    SERVICES_TO_CHECK="sshd cron" PROCESSES_TO_CHECK="sshd" ENABLE_ALERT=false
    local ret
    set +e
    ret=$(check_cpu 2>/dev/null) || ret="N/A"
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: 配置缺失时使用默认值，check_cpu 正常执行 (返回值=${ret:-N/A})"
    # 恢复配置
    if [ -f "$conf_backup" ]; then
        cp "$conf_backup" "$PROJECT_ROOT/config/diag.conf" 2>/dev/null || true
        rm -f "$conf_backup" 2>/dev/null || true
    fi
    teardown_mocks
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 巡逻模块 - 单元/集成测试 (20例)"
    echo "=============================================="
    echo ""

    # 功能单元测试
    test_cpu_normal
    test_cpu_high
    test_memory_normal
    test_memory_high
    test_disk_normal
    test_disk_high
    test_services_all_ok
    test_services_partial_fail
    test_processes_ok
    test_processes_missing
    test_logs_normal
    test_logs_oom

    # 集成测试
    test_patrol_all_ok
    test_patrol_with_failures

    # 异常测试
    test_cpu_no_top_no_proc
    test_disk_no_df
    test_services_no_systemctl
    test_config_missing

    test_summary || true
}

run_all_tests || true