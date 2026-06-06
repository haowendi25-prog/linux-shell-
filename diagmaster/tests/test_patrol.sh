#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 自动巡逻模块测试用例（修正版）
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 导入公共库和断言库
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"

# 设置测试阈值（在导入模块前定义，防止被配置文件覆盖）
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false

# 导入待测模块
source "$PROJECT_ROOT/modules/patrol.sh"

# 再次强制覆盖（防止 patrol.sh 内部 source diag.conf 造成覆盖）
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false

# ---------- Mock 管理 ----------
MOCK_DIR=""
ORIGINAL_PATH="$PATH"

setup_mocks() {
    MOCK_DIR=$(mktemp -d)
    if [ ! -d "$MOCK_DIR" ]; then
        echo "FATAL: 无法创建临时 Mock 目录" >&2
        exit 1
    fi

    # mock top（CPU 15%）
    cat > "$MOCK_DIR/top" << 'EOF'
#!/bin/bash
echo "Cpu(s): 10.0 us, 5.0 sy, 0.0 ni, 80.0 id, 5.0 wa, 0.0 hi, 0.0 si, 0.0 st"
EOF
    chmod +x "$MOCK_DIR/top"

    # mock free（内存 10%）
    cat > "$MOCK_DIR/free" << 'EOF'
#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         100         900           0           0         900"
EOF
    chmod +x "$MOCK_DIR/free"

    # mock df（磁盘 85%）
    cat > "$MOCK_DIR/df" << 'EOF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 8500000   1500000  85% /"
EOF
    chmod +x "$MOCK_DIR/df"

    # mock systemctl
    cat > "$MOCK_DIR/systemctl" << 'EOF'
#!/bin/bash
case "$*" in
    *"sshd"*) exit 0 ;;
    *"cron"*)  exit 0 ;;
    *"nginx"*) exit 1 ;;
    *)         exit 1 ;;
esac
EOF
    chmod +x "$MOCK_DIR/systemctl"

    # mock pgrep（取最后一个参数作为进程名）
    cat > "$MOCK_DIR/pgrep" << 'EOF'
#!/bin/bash
proc="${@: -1}"
case "$proc" in
    "sshd")  exit 0 ;;
    "nginx") exit 1 ;;
    "cron")  exit 0 ;;
    *)       exit 0 ;;
esac
EOF
    chmod +x "$MOCK_DIR/pgrep"

    # mock dmesg（无 OOM）
    cat > "$MOCK_DIR/dmesg" << 'EOF'
#!/bin/bash
echo "Some kernel messages"
EOF
    chmod +x "$MOCK_DIR/dmesg"

    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
}

overwrite_mock() {
    local name="$1" content="$2"
    printf '%s\n' "$content" > "$MOCK_DIR/$name"
    chmod +x "$MOCK_DIR/$name"
}

teardown_mocks() {
    export PATH="$ORIGINAL_PATH"
    if [ -n "$MOCK_DIR" ] && [ -d "$MOCK_DIR" ]; then
        rm -rf "$MOCK_DIR"
    fi
    MOCK_DIR=""
}


# ---------- 单元测试 ----------

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
    # 覆盖 top 为 95%
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

# ---------- 集成测试 ----------

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

# ---------- 运行入口 ----------

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 自动巡逻模块 - 单元/集成测试"
    echo "=============================================="
    echo ""

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
    test_patrol_all_ok
    test_patrol_with_failures

    test_summary
}

run_all_tests