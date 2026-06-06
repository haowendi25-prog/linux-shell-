#!/usr/bin/env bash
set -euo pipefail

# 测试脚本：自动巡逻模块单元测试与集成测试
# 要求：在项目根目录下运行

# 导入公共库和断言库
source "$(dirname "$0")/../lib/utils.sh"
source "$(dirname "$0")/../lib/assert.sh"

# 导入待测模块（但不执行主流程）
source "$(dirname "$0")/../modules/patrol.sh"

# ========== 测试前准备 ==========
# 保存原有命令，用于 Mock
ORIGINAL_TOP=$(command -v top 2>/dev/null || echo "/usr/bin/top")
ORIGINAL_FREE=$(command -v free 2>/dev/null || echo "/usr/bin/free")
ORIGINAL_DF=$(command -v df 2>/dev/null || echo "/bin/df")
ORIGINAL_SYSTEMCTL=$(command -v systemctl 2>/dev/null || echo "/bin/systemctl")
ORIGINAL_PGREP=$(command -v pgrep 2>/dev/null || echo "/usr/bin/pgrep")

# 创建临时工作目录
TMPDIR=$(mktemp -d)
# 使用 -E 选项保持环境变量原本的值，若某变量未设置则设置为默认
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}

# 临时替换命令为 Mock 版本，确保测试可重复
setup_mocks() {
    # Mock top: 输出模拟的 CPU 使用率
    cat > "$TMPDIR/top" << 'EOF'
#!/bin/bash
echo "Cpu(s): 10.0 us, 5.0 sy, 0.0 ni, 80.0 id, 5.0 wa, 0.0 hi, 0.0 si, 0.0 st"
EOF
    chmod +x "$TMPDIR/top"

    # Mock free: 输出模拟的内存信息 (总共1000MB, 使用100MB=10%)
    cat > "$TMPDIR/free" << 'EOF'
#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         100         900           0           0         900"
EOF
    chmod +x "$TMPDIR/free"

    # Mock df: 输出模拟的磁盘使用率 85%
    cat > "$TMPDIR/df" << 'EOF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 8500000   1500000  85% /"
EOF
    chmod +x "$TMPDIR/df"

    # Mock systemctl: 检查服务时根据参数返回成功或失败
    cat > "$TMPDIR/systemctl" << 'EOF'
#!/bin/bash
if [[ "$*" == *"sshd"* ]]; then
    exit 0
elif [[ "$*" == *"nginx"* ]]; then
    exit 1
elif [[ "$*" == *"cron"* ]]; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x "$TMPDIR/systemctl"

    # Mock pgrep: 根据参数返回成功或失败
    cat > "$TMPDIR/pgrep" << 'EOF'
#!/bin/bash
if [ "$1" = "sshd" ]; then
    exit 0
elif [ "$1" = "nginx" ]; then
    exit 1
else
    exit 0
fi
EOF
    chmod +x "$TMPDIR/pgrep"

    # 将临时目录加入 PATH 最前面
    export PATH="$TMPDIR:$PATH"
}

# 恢复真实命令
teardown_mocks() {
    export PATH="${PATH#TMPDIR:}"
    rm -rf "$TMPDIR"
}

# ========== 测试用例 ==========

# 因为函数内部调用命令，需先设置 Mock，然后测试函数
test_check_cpu_normal() {
    setup_mocks
    # CPU 使用率 15% (10+5) < 80 => 预期返回0
    local ret
    ret=$(check_cpu)
    assert_equal "$ret" "0" "CPU 正常时返回0"
    teardown_mocks
}

test_check_cpu_high() {
    setup_mocks
    # 覆盖 top 输出高 CPU (95%)
    cat > "$TMPDIR/top" << 'EOF'
#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"
EOF
    chmod +x "$TMPDIR/top"
    local ret
    ret=$(check_cpu)
    assert_equal "$ret" "1" "CPU 超过阈值时返回1"
    teardown_mocks
}

test_check_memory_normal() {
    setup_mocks
    # 内存使用率 10% <85 => 0
    local ret
    ret=$(check_memory)
    assert_equal "$ret" "0" "内存正常时返回0"
    teardown_mocks
}

test_check_memory_high() {
    setup_mocks
    cat > "$TMPDIR/free" << 'EOF'
#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         900         100           0           0         100"
EOF
    chmod +x "$TMPDIR/free"
    local ret
    ret=$(check_memory)
    assert_equal "$ret" "1" "内存超过阈值时返回1"
    teardown_mocks
}

test_check_disk_normal() {
    setup_mocks
    # 85% <90 => 0
    local ret
    ret=$(check_disk)
    assert_equal "$ret" "0" "磁盘使用率正常时返回0"
    teardown_mocks
}

test_check_disk_high() {
    setup_mocks
    cat > "$TMPDIR/df" << 'EOF'
#!/bin/bash
echo "/dev/sda1       10000000 9500000    500000  95% /"
EOF
    chmod +x "$TMPDIR/df"
    local ret
    ret=$(check_disk)
    assert_equal "$ret" "1" "磁盘超过阈值时返回1"
    teardown_mocks
}

test_check_services_all_ok() {
    setup_mocks
    SERVICES_TO_CHECK="sshd cron"
    local ret
    ret=$(check_services)
    assert_equal "$ret" "0" "所有服务正常运行时返回0"
    teardown_mocks
}

test_check_services_some_down() {
    setup_mocks
    SERVICES_TO_CHECK="sshd nginx"
    local ret
    ret=$(check_services)
    # 预期返回1，因为 nginx 关闭
    assert_equal "$ret" "1" "部分服务故障时返回1"
    teardown_mocks
}

test_check_processes_ok() {
    setup_mocks
    PROCESSES_TO_CHECK="sshd"
    local ret
    ret=$(check_processes)
    assert_equal "$ret" "0" "关键进程存在时返回0"
    teardown_mocks
}

test_check_processes_missing() {
    setup_mocks
    PROCESSES_TO_CHECK="sshd nginx"
    local ret
    ret=$(check_processes)
    assert_equal "$ret" "1" "有进程缺失时返回1"
    teardown_mocks
}

test_check_logs_mock() {
    # 日志检查依赖真实命令，简单测试无错误场景
    # 我们通过预先设置环境来模拟，或者跳过真实日志读取
    # 这里演示：如果 dmesg 不可用，应返回0
    local ret
    # 临时屏蔽命令
    function dmesg() { return 1; }
    ret=$(check_logs)
    assert_equal "$ret" "0" "日志命令缺失时返回0（默认正常）"
    unset -f dmesg
}

# 集成测试：模拟完整巡逻流程（不发送邮件）
test_run_patrol_mock_all_ok() {
    setup_mocks
    # 所有 Mock 均为正常值
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    PATROL_REPORT_DIR="$TMPDIR/reports"
    LOG_FILE="$TMPDIR/patrol.log"
    run_patrol
    local ret=$?
    # 因为所有检查正常，预期返回0
    assert_equal "$ret" "0" "集成测试：全部正常时 run_patrol 返回0"
    # 检查报告文件是否存在且包含正常状态
    local report_file
    report_file=$(ls -1t "$PATROL_REPORT_DIR" | head -n1)
    if [ -f "$PATROL_REPORT_DIR/$report_file" ]; then
        assert_contains "$(cat "$PATROL_REPORT_DIR/$report_file")" "正常 ✅" "报告包含正常标识"
    else
        echo "✘ FAIL: 报告文件未生成"
    fi
    teardown_mocks
}

test_run_patrol_mock_with_failures() {
    setup_mocks
    # 设置 nginx 服务关闭、nginx 进程缺失，其他正常
    cat > "$TMPDIR/top" << 'EOF'
#!/bin/bash
echo "Cpu(s): 60.0 us, 30.0 sy, 0.0 ni, 10.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"
EOF
    chmod +x "$TMPDIR/top"
    # 内存正常，磁盘正常
    SERVICES_TO_CHECK="sshd nginx"
    PROCESSES_TO_CHECK="sshd nginx"
    PATROL_REPORT_DIR="$TMPDIR/reports"
    LOG_FILE="$TMPDIR/patrol.log"
    run_patrol
    local ret=$?
    # 预期有异常，返回1
    assert_equal "$ret" "1" "集成测试：存在异常时 run_patrol 返回1"
    # 检查报告内容
    local report_file
    report_file=$(ls -1t "$PATROL_REPORT_DIR" | head -n1)
    if [ -f "$PATROL_REPORT_DIR/$report_file" ]; then
        assert_contains "$(cat "$PATROL_REPORT_DIR/$report_file")" "存在异常" "报告包含异常提示"
    fi
    teardown_mocks
}

# ========== 运行所有测试 ==========
run_all_tests() {
    echo "========== 开始执行巡逻模块测试 =========="
    test_check_cpu_normal
    test_check_cpu_high
    test_check_memory_normal
    test_check_memory_high
    test_check_disk_normal
    test_check_disk_high
    test_check_services_all_ok
    test_check_services_some_down
    test_check_processes_ok
    test_check_processes_missing
    test_check_logs_mock
    test_run_patrol_mock_all_ok
    test_run_patrol_mock_with_failures
    echo ""
    test_summary
}

# 执行
run_all_tests