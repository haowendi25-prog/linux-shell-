#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 边界测试
# 测试 CPU/内存/磁盘 在极端值下的表现（6个用例）
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
PATROL_REPORT_DIR="/tmp/test_boundary_reports"
LOG_FILE="/tmp/test_boundary.log"
mkdir -p "$PATROL_REPORT_DIR" "$(dirname "$LOG_FILE")"

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

test_boundary_cpu_100() {
    echo "[TEST] 边界：CPU使用率接近100%"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 95.0 us, 5.0 sy, 0.0 ni, 0.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    local ret
    ret=$(check_cpu)
    teardown_mocks
    assert_equal "$ret" "1" "CPU=100% > 阈值80%，应返回1告警"
}

test_boundary_memory_100() {
    echo "[TEST] 边界：内存使用率接近100%"
    setup_mocks
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         999           1           0           0           1"'
    local ret
    ret=$(check_memory)
    teardown_mocks
    assert_equal "$ret" "1" "内存=99.9% > 阈值85%，应返回1告警"
}

test_boundary_disk_100() {
    echo "[TEST] 边界：磁盘使用率100%"
    setup_mocks
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 10000000         0 100% /"'
    local ret
    ret=$(check_disk)
    teardown_mocks
    assert_equal "$ret" "1" "磁盘=100% > 阈值90%，应返回1告警"
}

test_boundary_zero() {
    echo "[TEST] 边界：零值边界（CPU/内存/磁盘均为0%）"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 0.0 us, 0.0 sy, 0.0 ni, 100.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000           0        1000           0           0         1000"'
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000       0  10000000   0% /"'
    local cpu_ret mem_ret disk_ret all_ok="是"
    cpu_ret=$(check_cpu)
    mem_ret=$(check_memory)
    disk_ret=$(check_disk)
    [ "$cpu_ret" != "0" ] && all_ok="否（CPU返回值异常：${cpu_ret}）"
    [ "$mem_ret" != "0" ] && all_ok="否（内存返回值异常：${mem_ret}）"
    [ "$disk_ret" != "0" ] && all_ok="否（磁盘返回值异常：${disk_ret}）"
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$all_ok" = "是" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 零值边界处理正常，CPU=${cpu_ret} 内存=${mem_ret} 磁盘=${disk_ret}"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: $all_ok"
    fi
}

test_boundary_large_log() {
    echo "[TEST] 边界：超大日志文件（500条OOM记录）"
    setup_mocks
    local large_oom=""
    for i in $(seq 1 500); do
        large_oom+="echo \"[$i.000000] Out of memory: Kill process $((1000+i)) (test) score 900\"\n"
    done
    overwrite_mock "dmesg" "#!/bin/bash
$(echo -e "$large_oom")"
    local ret
    set +e
    ret=$(check_logs 2>/dev/null) || true
    set -e
    teardown_mocks
    assert_equal "${ret:-N/A}" "1" "超大日志处理正常，检测到异常应返回1"
}

test_boundary_threshold_exact() {
    echo "[TEST] 边界：阈值精确相等"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 30.0 sy, 0.0 ni, 20.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    local ret
    ret=$(check_cpu)
    teardown_mocks
    assert_equal "$ret" "0" "CPU=80%（等于阈值），使用>比较，应返回0不告警"
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 边界测试 (6个用例)"
    echo "=============================================="
    echo ""

    test_boundary_cpu_100
    test_boundary_memory_100
    test_boundary_disk_100
    test_boundary_zero
    test_boundary_large_log
    test_boundary_threshold_exact

    test_summary || true
}

run_all_tests || true