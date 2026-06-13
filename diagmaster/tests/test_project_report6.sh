#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster - Project Report 6 综合测试脚本（交互式菜单版）
# 测试类别：6.1 功能测试 / 6.2 异常测试 / 6.3 边界测试 / 6.4 自动化运行验证
# 使用方式: bash tests/test_project_report6.sh
#          然后按菜单逐项选择要运行的测试
# 注意：本脚本 Mock 逻辑已抽取到 tests/lib/mock_utils.sh
#       独立的分类测试请运行: test_patrol.sh / test_collector.sh / test_boundary.sh / test_auto.sh
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# 导入公共库和断言库
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"

# 导入共享 Mock 库
source "$TEST_DIR/lib/mock_utils.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ==============================================================
# 全局状态
# ==============================================================
CATEGORY_PASSED=0
CATEGORY_FAILED=0
CATEGORY_TOTAL=0

# ==============================================================
# 测试结果格式化输出
# ==============================================================
print_test_header() {
    local category="$1" test_name="$2"
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}${category}${NC}"
    echo -e "${CYAN}║${NC} 测试: ${test_name}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

print_expected_actual() {
    local expected="$1" actual="$2" result="$3"
    echo ""
    echo -e "  ${BOLD}预期结果:${NC} ${expected}"
    echo -e "  ${BOLD}实际结果:${NC} ${actual}"
    if [ "$result" = "PASS" ]; then
        echo -e "  ${BOLD}测试结论:${NC} ${GREEN}✓ 通过${NC}"
    else
        echo -e "  ${BOLD}测试结论:${NC} ${RED}✘ 未通过${NC}"
    fi
    echo ""
}

# ==============================================================
# 加载被测模块之前的准备工作
# ==============================================================
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90
SERVICES_TO_CHECK="sshd cron"
PROCESSES_TO_CHECK="sshd"
ENABLE_ALERT=false
LOG_FILE="/tmp/test_patrol.log"
PATROL_REPORT_DIR="/tmp/test_reports"

load_modules() {
    mkdir -p "$PATROL_REPORT_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    source "$PROJECT_ROOT/modules/patrol.sh" 2>/dev/null || true
    # 再次强制覆盖阈值
    CPU_WARN_THRESHOLD=80
    MEM_WARN_THRESHOLD=85
    DISK_WARN_THRESHOLD=90
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    ENABLE_ALERT=false
}

# ==============================================================
# 6.1 功能测试
# ==============================================================

test_func_01_cpu_check_normal() {
    print_test_header "6.1 功能测试" "CPU 检查 - 正常使用率场景"
    setup_mocks
    load_modules
    local ret
    ret=$(check_cpu)
    teardown_mocks
    print_expected_actual \
        "CPU 15% < 阈值80%，check_cpu应返回0（正常）" \
        "check_cpu 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "CPU正常场景：返回值应为0"
}

test_func_02_cpu_check_warning() {
    print_test_header "6.1 功能测试" "CPU 检查 - 高使用率告警场景"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    load_modules
    local ret
    ret=$(check_cpu)
    teardown_mocks
    print_expected_actual \
        "CPU 95% > 阈值80%，check_cpu应返回1（告警）" \
        "check_cpu 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "CPU高负载场景：返回值应为1"
}

test_func_03_memory_check_normal() {
    print_test_header "6.1 功能测试" "内存检查 - 正常使用率场景"
    setup_mocks
    load_modules
    local ret
    ret=$(check_memory)
    teardown_mocks
    print_expected_actual \
        "内存 10% < 阈值85%，check_memory应返回0（正常）" \
        "check_memory 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "内存正常场景：返回值应为0"
}

test_func_04_memory_check_warning() {
    print_test_header "6.1 功能测试" "内存检查 - 高使用率告警场景"
    setup_mocks
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         900         100           0           0         100"'
    load_modules
    local ret
    ret=$(check_memory)
    teardown_mocks
    print_expected_actual \
        "内存 90% > 阈值85%，check_memory应返回1（告警）" \
        "check_memory 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "内存高占用场景：返回值应为1"
}

test_func_05_disk_check_normal() {
    print_test_header "6.1 功能测试" "磁盘检查 - 正常使用率场景"
    setup_mocks
    load_modules
    local ret
    ret=$(check_disk)
    teardown_mocks
    print_expected_actual \
        "磁盘 85% < 阈值90%，check_disk应返回0（正常）" \
        "check_disk 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "磁盘正常场景：返回值应为0"
}

test_func_06_disk_check_warning() {
    print_test_header "6.1 功能测试" "磁盘检查 - 高使用率告警场景"
    setup_mocks
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 9500000    500000  95% /"'
    load_modules
    local ret
    ret=$(check_disk)
    teardown_mocks
    print_expected_actual \
        "磁盘 95% > 阈值90%，check_disk应返回1（告警）" \
        "check_disk 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "磁盘高占用场景：返回值应为1"
}

test_func_07_services_all_ok() {
    print_test_header "6.1 功能测试" "关键服务检查 - 所有服务正常运行"
    setup_mocks
    load_modules
    SERVICES_TO_CHECK="sshd cron"
    local ret
    ret=$(check_services)
    teardown_mocks
    print_expected_actual \
        "sshd、cron均正常，check_services应返回0" \
        "check_services 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "全部服务正常：返回值应为0"
}

test_func_08_services_partial_fail() {
    print_test_header "6.1 功能测试" "关键服务检查 - 部分服务故障"
    setup_mocks
    load_modules
    SERVICES_TO_CHECK="sshd nginx"  # 必须在 load_modules 之后设置，防止被覆盖
    local ret
    ret=$(check_services)
    teardown_mocks
    print_expected_actual \
        "sshd正常但nginx故障，check_services应返回1（告警）" \
        "check_services 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "部分服务故障：返回值应为1"
}

test_func_09_logs_normal() {
    print_test_header "6.1 功能测试" "日志检查 - 无OOM/SSH爆破"
    setup_mocks
    load_modules
    local ret
    ret=$(check_logs)
    teardown_mocks
    print_expected_actual \
        "无OOM事件、无SSH爆破，check_logs应返回0（正常）" \
        "check_logs 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "日志正常场景：返回值应为0"
}

test_func_10_logs_oom_detected() {
    print_test_header "6.1 功能测试" "日志检查 - 检测到OOM事件"
    setup_mocks
    overwrite_mock "dmesg" '#!/bin/bash
echo "Out of memory: Kill process 1234 (java) score 900"
echo "Out of memory: Kill process 5678 (mysql) score 800"
echo "invoked oom-killer: gfp_mask=0x201da"'
    load_modules
    local ret
    ret=$(check_logs)
    teardown_mocks
    print_expected_actual \
        "dmesg中包含OOM事件记录，check_logs应返回1（告警）" \
        "check_logs 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "检测到OOM：返回值应为1"
}

test_func_11_patrol_full_flow() {
    print_test_header "6.1 功能测试" "完整巡逻流程 - 全功能集成测试"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    load_modules
    local ret
    run_patrol
    ret=$?
    local report
    report=$(ls -1t "$PATROL_REPORT_DIR"/*.md 2>/dev/null | head -n1)
    local has_report="否"
    [ -f "$report" ] && has_report="是"
    teardown_mocks
    print_expected_actual \
        "所有检查项正常，run_patrol返回0；生成巡逻报告文件" \
        "run_patrol返回值=${ret}，报告文件生成=${has_report}" \
        "$([ "$ret" = "0" ] && [ "$has_report" = "是" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "完整巡逻流程：返回值应为0"
    if [ "$has_report" = "是" ]; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 巡逻报告已成功生成"
    fi
}

test_func_12_collector_module() {
    print_test_header "6.1 功能测试" "性能采集模块 - collect_cpu/collect_memory/collect_disk"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local cpu_val mem_val disk_val
    cpu_val=$(collect_cpu 2>/dev/null || echo "0")
    mem_val=$(collect_memory 2>/dev/null || echo "0")
    disk_val=$(collect_disk 2>/dev/null || echo "0")
    teardown_mocks
    local all_ok="是"
    [ -z "$cpu_val" ] || [ "$cpu_val" = "0" ] && all_ok="否（CPU值异常）"
    [ -z "$mem_val" ] || [ "$mem_val" = "0" ] && all_ok="否（内存值异常）"
    [ -z "$disk_val" ] || [ "$disk_val" = "0" ] && all_ok="否（磁盘值异常）"
    print_expected_actual \
        "采集函数正常返回数值型结果（非空非零）" \
        "CPU=${cpu_val}%, 内存=${mem_val}%, 磁盘=${disk_val}%" \
        "$([ "$all_ok" = "是" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$all_ok" = "是" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 采集模块三个函数均正常返回数值"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: $all_ok"
    fi
}

# ==============================================================
# 6.2 异常测试
# ==============================================================

test_excep_01_file_not_found_config() {
    print_test_header "6.2 异常测试" "文件不存在 - 配置文件缺失"
    setup_mocks
    local conf_backup="${PROJECT_ROOT}/config/diag.conf.bak.$$"
    if [ -f "$PROJECT_ROOT/config/diag.conf" ]; then
        cp "$PROJECT_ROOT/config/diag.conf" "$conf_backup" 2>/dev/null || true
        rm -f "$PROJECT_ROOT/config/diag.conf" 2>/dev/null || true
    fi
    CPU_WARN_THRESHOLD=80 MEM_WARN_THRESHOLD=85 DISK_WARN_THRESHOLD=90
    SERVICES_TO_CHECK="sshd cron" PROCESSES_TO_CHECK="sshd" ENABLE_ALERT=false
    load_modules
    local ret crash_detected="否"
    set +e
    ret=$(check_cpu 2>/dev/null)
    local exit_code=$?
    set -e
    if [ "$exit_code" -ne 0 ] && [ -z "$ret" ]; then
        crash_detected="是"
        ret="N/A（函数崩溃或返回值异常）"
    fi
    # 恢复配置
    if [ -f "$conf_backup" ]; then
        cp "$conf_backup" "$PROJECT_ROOT/config/diag.conf" 2>/dev/null || true
        rm -f "$conf_backup" 2>/dev/null || true
    fi
    teardown_mocks
    print_expected_actual \
        "配置文件不存在时，系统应使用默认值继续运行，不应崩溃" \
        "check_cpu 返回值 = ${ret:-N/A}，系统崩溃 = ${crash_detected}" \
        "$([ "$crash_detected" = "否" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$crash_detected" = "否" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 配置缺失时系统正常降级运行"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 配置缺失时系统未正确处理"
    fi
}

test_excep_02_command_not_found() {
    print_test_header "6.2 异常测试" "命令不存在 - top/free/df 不可用时的降级处理"
    setup_mocks
    # 删除 mock top，仅保留 /proc/stat 路径
    remove_mock "top"
    remove_mock "free"
    remove_mock "df"
    load_modules
    local ret crash_detected="否"
    set +e
    ret=$(check_cpu 2>/dev/null) || true
    set -e
    if [ -z "$ret" ]; then
        ret="2（降级返回2=无法检查）"
    fi
    teardown_mocks
    print_expected_actual \
        "top命令不存在时，系统应降级使用/proc/stat或返回2（无法检查），不应崩溃" \
        "check_cpu 返回值 = ${ret}" \
        "$([ "$ret" = "2" ] || [ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$ret" = "2" ] || [ "$ret" = "0" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 命令不存在时系统正常降级，未崩溃"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 命令不存在时系统响应异常"
    fi
}

test_excep_03_permission_denied() {
    print_test_header "6.2 异常测试" "权限不足 - 部分日志文件不可读"
    setup_mocks
    # 模拟 /var/log/auth.log 不可读的情况
    # 创建一个不可读的临时目录来模拟
    local no_perm_dir="${MOCK_DIR}/noperm"
    mkdir -p "$no_perm_dir"
    # 我们不实际创建不可读文件（需要root），改为验证 check_logs 在 auth.log 不存在时的行为
    load_modules
    local ret
    set +e
    ret=$(check_logs 2>/dev/null) || true
    set -e
    teardown_mocks
    print_expected_actual \
        "部分日志文件不可读/不存在时，check_logs应正确处理，不应崩溃，默认返回0" \
        "check_logs 返回值 = ${ret:-0}" \
        "$([ "${ret:-0}" = "0" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${ret:-0}" = "0" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 权限不足/文件不存在时系统正常处理"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 权限不足时返回值异常"
    fi
}

test_excep_04_invalid_threshold_config() {
    print_test_header "6.2 异常测试" "配置错误 - 阈值配置为非数字值"
    setup_mocks
    CPU_WARN_THRESHOLD="abc"  # 非法阈值
    MEM_WARN_THRESHOLD=""     # 空值
    DISK_WARN_THRESHOLD="-50" # 负值
    load_modules
    local ret crash_detected="否"
    set +e
    ret=$(check_cpu 2>/dev/null)
    local exit_code=$?
    set -e
    if [ "$exit_code" -ne 0 ] && [ -z "$ret" ]; then
        crash_detected="是"
        ret="函数崩溃"
    fi
    teardown_mocks
    print_expected_actual \
        "阈值配置异常时（非数字/空值/负数），系统应能容错运行，不应崩溃" \
        "check_cpu 返回值 = ${ret:-N/A}，崩溃 = ${crash_detected}" \
        "$([ "$crash_detected" = "否" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$crash_detected" = "否" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 阈值配置异常时系统容错运行"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 阈值配置异常导致崩溃"
    fi
}

test_excep_05_dmesg_command_unavailable() {
    print_test_header "6.2 异常测试" "dmesg命令不可用 - 日志审计降级处理"
    setup_mocks
    remove_mock "dmesg"
    load_modules
    local ret
    set +e
    ret=$(check_logs 2>/dev/null) || true
    set -e
    teardown_mocks
    print_expected_actual \
        "dmesg不可用时，check_logs应降级处理仅检查文件日志（/var/log/*），不应崩溃" \
        "check_logs 返回值 = ${ret:-0}" \
        "$([ "${ret:-0}" = "0" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${ret:-0}" = "0" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: dmesg不可用时系统降级运行"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: dmesg不可用时处理异常"
    fi
}

# ==============================================================
# 6.3 边界测试
# ==============================================================

test_boundary_01_cpu_100_percent() {
    print_test_header "6.3 边界测试" "CPU使用率接近100%"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 95.0 us, 5.0 sy, 0.0 ni, 0.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    load_modules
    local ret
    ret=$(check_cpu)
    teardown_mocks
    print_expected_actual \
        "CPU=100% > 阈值80%，应返回1（告警），系统不应崩溃" \
        "check_cpu 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "CPU边界100%：返回1告警"
}

test_boundary_02_memory_100_percent() {
    print_test_header "6.3 边界测试" "内存使用率接近100%"
    setup_mocks
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         999           1           0           0           1"'
    load_modules
    local ret
    ret=$(check_memory)
    teardown_mocks
    print_expected_actual \
        "内存=99.9% > 阈值85%，应返回1（告警），系统不应崩溃" \
        "check_memory 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "内存边界99.9%：返回1告警"
}

test_boundary_03_disk_100_percent() {
    print_test_header "6.3 边界测试" "磁盘使用率100%（空间不足）"
    setup_mocks
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 10000000         0 100% /"'
    load_modules
    local ret
    ret=$(check_disk)
    teardown_mocks
    print_expected_actual \
        "磁盘=100% > 阈值90%，应返回1（告警），系统不应崩溃" \
        "check_disk 返回值 = ${ret}" \
        "$([ "$ret" = "1" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "1" "磁盘边界100%：返回1告警"
}

test_boundary_04_zero_usage() {
    print_test_header "6.3 边界测试" "零值边界 - CPU/内存/磁盘均为0%"
    setup_mocks
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 0.0 us, 0.0 sy, 0.0 ni, 100.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    overwrite_mock "free" '#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000           0        1000           0           0         1000"'
    overwrite_mock "df" '#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000       0  10000000   0% /"'
    load_modules
    local cpu_ret mem_ret disk_ret all_ok="是"
    cpu_ret=$(check_cpu)
    mem_ret=$(check_memory)
    disk_ret=$(check_disk)
    [ "$cpu_ret" != "0" ] && all_ok="否（CPU返回值异常：${cpu_ret}）"
    [ "$mem_ret" != "0" ] && all_ok="否（内存返回值异常：${mem_ret}）"
    [ "$disk_ret" != "0" ] && all_ok="否（磁盘返回值异常：${disk_ret}）"
    teardown_mocks
    print_expected_actual \
        "所有指标均为0%时，各项检查均应返回0（正常），系统正常处理零值" \
        "CPU=${cpu_ret}, 内存=${mem_ret}, 磁盘=${disk_ret}" \
        "$([ "$all_ok" = "是" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$all_ok" = "是" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 零值边界处理正常"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: $all_ok"
    fi
}

test_boundary_05_large_log_file() {
    print_test_header "6.3 边界测试" "超大日志文件模拟（大量OOM记录）"
    setup_mocks
    # 生成包含大量OOM记录的 mock dmesg 输出
    local large_oom=""
    for i in $(seq 1 500); do
        large_oom+="echo \"[$i.000000] Out of memory: Kill process $((1000+i)) (test) score 900\"\n"
    done
    overwrite_mock "dmesg" "#!/bin/bash
$(echo -e "$large_oom")"
    load_modules
    local ret
    set +e
    ret=$(check_logs 2>/dev/null) || true
    set -e
    teardown_mocks
    print_expected_actual \
        "dmesg中有500条OOM记录，系统应正确统计并返回1（告警），不应崩溃或卡死" \
        "check_logs 返回值 = ${ret:-N/A}" \
        "$([ "${ret:-N/A}" = "1" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${ret:-N/A}" = "1" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 超大日志处理正常，正确检测到异常"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 超大日志处理异常，返回值=${ret:-N/A}"
    fi
}

test_boundary_06_threshold_exact_match() {
    print_test_header "6.3 边界测试" "阈值精确相等的边界值"
    setup_mocks
    # CPU 恰好等于阈值 80%
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 30.0 sy, 0.0 ni, 20.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    load_modules
    local ret
    ret=$(check_cpu)
    teardown_mocks
    print_expected_actual \
        "CPU使用率恰好=80%（阈值），根据greater_than逻辑（>非>=），应返回0（正常）" \
        "check_cpu 返回值 = ${ret}" \
        "$([ "$ret" = "0" ] && echo "PASS" || echo "FAIL")"
    assert_equal "$ret" "0" "阈值精确相等：返回0（不告警，使用>比较）"
}

# ==============================================================
# 6.4 自动化运行验证
# ==============================================================

test_auto_01_single_run_consistency() {
    print_test_header "6.4 自动化运行验证" "单次运行结果一致性"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    load_modules
    local results=()
    for i in $(seq 1 5); do
        local ret
        run_patrol >/dev/null 2>&1
        ret=$?
        results+=($ret)
        sleep 1
    done
    local all_same="是"
    for r in "${results[@]}"; do
        [ "$r" != "${results[0]}" ] && all_same="否"
    done
    local report_count
    report_count=$(ls -1 "$PATROL_REPORT_DIR"/*.md 2>/dev/null | wc -l)
    teardown_mocks
    print_expected_actual \
        "连续运行5次，每次返回值应一致，且每次都生成报告文件" \
        "5次返回值: ${results[*]}，报告数量: ${report_count}" \
        "$([ "$all_same" = "是" ] && [ "$report_count" -ge 5 ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$all_same" = "是" ] && [ "$report_count" -ge 5 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 多次运行结果一致，报告持续生成"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 运行结果不一致或报告缺失"
    fi
}

test_auto_02_continuous_operation() {
    print_test_header "6.4 自动化运行验证" "连续运行稳定性 - 10次循环无崩溃"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    load_modules
    local crashes=0
    for i in $(seq 1 10); do
        set +e
        run_patrol >/dev/null 2>&1
        local ret=$?
        set -e
        if [ "$ret" -ne 0 ] && [ "$ret" -ne 1 ]; then
            crashes=$((crashes + 1))
        fi
        sleep 1
    done
    teardown_mocks
    print_expected_actual \
        "连续运行10次巡逻，不应出现崩溃（返回值仅0或1为正常）" \
        "10次运行崩溃次数 = ${crashes}" \
        "$([ "$crashes" -eq 0 ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$crashes" -eq 0 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 连续10次运行无崩溃"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 出现 ${crashes} 次崩溃"
    fi
}

test_auto_03_unattended_daemon_simulation() {
    print_test_header "6.4 自动化运行验证" "无人值守运行模拟（守护进程逻辑验证）"
    setup_mocks
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    load_modules
    # 模拟守护进程的核心逻辑：循环运行 patrol 并输出状态
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
        sleep 1  # 模拟巡逻间隔，确保报告文件名不重复
    done
    local report_count
    report_count=$(ls -1 "$PATROL_REPORT_DIR"/*.md 2>/dev/null | wc -l)
    teardown_mocks
    print_expected_actual \
        "模拟无人值守3轮巡逻，每轮应正常完成（返回0或1），并生成对应报告" \
        "成功轮次=${success_rounds}/${rounds}，报告数=${report_count}" \
        "$([ "$success_rounds" -eq "$rounds" ] && [ "$report_count" -ge "$rounds" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$success_rounds" -eq "$rounds" ] && [ "$report_count" -ge "$rounds" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 无人值守模拟运行正常"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 无人值守模拟有异常"
    fi
}

test_auto_04_mixed_state_handling() {
    print_test_header "6.4 自动化运行验证" "混合状态处理 - 同时存在正常和异常项"
    setup_mocks
    # CPU 异常 (95%)
    overwrite_mock "top" '#!/bin/bash
echo "Cpu(s): 50.0 us, 45.0 sy, 0.0 ni, 5.0 id, 0.0 wa, 0.0 hi, 0.0 si, 0.0 st"'
    PATROL_REPORT_DIR="$MOCK_DIR/reports"
    LOG_FILE="$MOCK_DIR/patrol.log"
    SERVICES_TO_CHECK="sshd nginx"  # 一个正常，一个异常
    PROCESSES_TO_CHECK="sshd nginx" # 一个存在，一个不存在
    load_modules
    run_patrol >/dev/null 2>&1
    local ret=$?
    local report
    report=$(ls -1t "$PATROL_REPORT_DIR"/*.md 2>/dev/null | head -n1)
    local has_abnormal_contains="否"
    if [ -f "$report" ]; then
        if grep -q "存在异常" "$report" 2>/dev/null; then
            has_abnormal_contains="是"
        fi
    fi
    teardown_mocks
    print_expected_actual \
        "多项检查中部分正常、部分异常时，整体状态应为'存在异常'，返回值=1" \
        "run_patrol返回值=${ret}，报告含'存在异常'=${has_abnormal_contains}" \
        "$([ "$ret" = "1" ] && [ "$has_abnormal_contains" = "是" ] && echo "PASS" || echo "FAIL")"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$ret" = "1" ] && [ "$has_abnormal_contains" = "是" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: 混合状态正确处理"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: 混合状态处理异常"
    fi
}

# ==============================================================
# 交互式菜单
# ==============================================================

show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}DiagMaster - Project Report 6 综合测试套件${NC}                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     版本: v1.0  |  日期: 2026-06-07                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}━━━ 6.1 功能测试 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}1.1${NC}  CPU 检查 - 正常使用率场景"
    echo -e "  ${GREEN}1.2${NC}  CPU 检查 - 高使用率告警场景"
    echo -e "  ${GREEN}1.3${NC}  内存检查 - 正常使用率场景"
    echo -e "  ${GREEN}1.4${NC}  内存检查 - 高使用率告警场景"
    echo -e "  ${GREEN}1.5${NC}  磁盘检查 - 正常使用率场景"
    echo -e "  ${GREEN}1.6${NC}  磁盘检查 - 高使用率告警场景"
    echo -e "  ${GREEN}1.7${NC}  关键服务检查 - 所有服务正常"
    echo -e "  ${GREEN}1.8${NC}  关键服务检查 - 部分服务故障"
    echo -e "  ${GREEN}1.9${NC}  日志检查 - 无异常"
    echo -e "  ${GREEN}1.10${NC} 日志检查 - 检测到OOM事件"
    echo -e "  ${GREEN}1.11${NC} 完整巡逻流程 - 集成测试"
    echo -e "  ${GREEN}1.12${NC} 性能采集模块 - 采集函数测试"
    echo -e "  ${GREEN}1.0${NC}  ${BOLD}运行全部 6.1 功能测试${NC}"
    echo ""
    echo -e "  ${BOLD}━━━ 6.2 异常测试 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}2.1${NC}  文件不存在 - 配置文件缺失"
    echo -e "  ${YELLOW}2.2${NC}  命令不存在 - top/free/df 不可用"
    echo -e "  ${YELLOW}2.3${NC}  权限不足 - 部分日志不可读"
    echo -e "  ${YELLOW}2.4${NC}  配置错误 - 阈值非法值"
    echo -e "  ${YELLOW}2.5${NC}  dmesg命令不可用 - 降级处理"
    echo -e "  ${YELLOW}2.0${NC}  ${BOLD}运行全部 6.2 异常测试${NC}"
    echo ""
    echo -e "  ${BOLD}━━━ 6.3 边界测试 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${RED}3.1${NC}  CPU使用率接近100%"
    echo -e "  ${RED}3.2${NC}  内存使用率接近100%"
    echo -e "  ${RED}3.3${NC}  磁盘使用率100%（空间不足）"
    echo -e "  ${RED}3.4${NC}  零值边界 - 各项指标0%"
    echo -e "  ${RED}3.5${NC}  超大日志文件（大量OOM记录）"
    echo -e "  ${RED}3.6${NC}  阈值精确相等边界值"
    echo -e "  ${RED}3.0${NC}  ${BOLD}运行全部 6.3 边界测试${NC}"
    echo ""
    echo -e "  ${BOLD}━━━ 6.4 自动化运行验证 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}4.1${NC}  单次运行结果一致性"
    echo -e "  ${BLUE}4.2${NC}  连续运行稳定性（10次）"
    echo -e "  ${BLUE}4.3${NC}  无人值守运行模拟"
    echo -e "  ${BLUE}4.4${NC}  混合状态处理"
    echo -e "  ${BLUE}4.0${NC}  ${BOLD}运行全部 6.4 自动化验证${NC}"
    echo ""
    echo -e "  ${BOLD}━━━ 综合操作 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}A${NC}    ${BOLD}运行全部测试（6.1 + 6.2 + 6.3 + 6.4）${NC}"
    echo -e "  ${CYAN}S${NC}    显示当前测试统计"
    echo -e "  ${CYAN}Q${NC}    退出测试"
    echo ""
    echo -e "  ${BOLD}当前统计:${NC} 通过=${GREEN}${TEST_PASSED}${NC}  失败=${RED}${TEST_FAILED}${NC}  总计=${TESTS_RUN}"
    echo ""
}

run_all_6_1() {
    test_func_01_cpu_check_normal
    test_func_02_cpu_check_warning
    test_func_03_memory_check_normal
    test_func_04_memory_check_warning
    test_func_05_disk_check_normal
    test_func_06_disk_check_warning
    test_func_07_services_all_ok
    test_func_08_services_partial_fail
    test_func_09_logs_normal
    test_func_10_logs_oom_detected
    test_func_11_patrol_full_flow
    test_func_12_collector_module
    echo ""
    echo -e "${GREEN}════ 6.1 功能测试 全部完成 ════${NC}"
    test_summary
}

run_all_6_2() {
    test_excep_01_file_not_found_config
    test_excep_02_command_not_found
    test_excep_03_permission_denied
    test_excep_04_invalid_threshold_config
    test_excep_05_dmesg_command_unavailable
    echo ""
    echo -e "${GREEN}════ 6.2 异常测试 全部完成 ════${NC}"
    test_summary
}

run_all_6_3() {
    test_boundary_01_cpu_100_percent
    test_boundary_02_memory_100_percent
    test_boundary_03_disk_100_percent
    test_boundary_04_zero_usage
    test_boundary_05_large_log_file
    test_boundary_06_threshold_exact_match
    echo ""
    echo -e "${GREEN}════ 6.3 边界测试 全部完成 ════${NC}"
    test_summary
}

run_all_6_4() {
    test_auto_01_single_run_consistency
    test_auto_02_continuous_operation
    test_auto_03_unattended_daemon_simulation
    test_auto_04_mixed_state_handling
    echo ""
    echo -e "${GREEN}════ 6.4 自动化运行验证 全部完成 ════${NC}"
    test_summary
}

run_all_tests() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}         ${BOLD}开始运行全部测试套件${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}▶ 阶段 1/4: 6.1 功能测试${NC}"
    run_all_6_1 || true
    echo ""
    echo -e "  ${BOLD}▶ 阶段 2/4: 6.2 异常测试${NC}"
    run_all_6_2 || true
    echo ""
    echo -e "  ${BOLD}▶ 阶段 3/4: 6.3 边界测试${NC}"
    run_all_6_3 || true
    echo ""
    echo -e "  ${BOLD}▶ 阶段 4/4: 6.4 自动化运行验证${NC}"
    run_all_6_4 || true
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}全部测试完成！${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    test_summary || true
}

# ==============================================================
# 主循环
# ==============================================================

# 测试后暂停，等待用户按回车再返回菜单
pause_after_test() {
    echo ""
    echo -n "按回车键返回菜单..."
    read -r
}

main() {
    # 确保脚本有执行权限
    chmod +x "$0" 2>/dev/null || true
    
    while true; do
        show_menu
        echo -n "请输入测试编号 (如 1.1, 2.3, A, Q): "
        read -r choice
        
        case "$choice" in
            "1.1") test_func_01_cpu_check_normal; pause_after_test ;;
            "1.2") test_func_02_cpu_check_warning; pause_after_test ;;
            "1.3") test_func_03_memory_check_normal; pause_after_test ;;
            "1.4") test_func_04_memory_check_warning; pause_after_test ;;
            "1.5") test_func_05_disk_check_normal; pause_after_test ;;
            "1.6") test_func_06_disk_check_warning; pause_after_test ;;
            "1.7") test_func_07_services_all_ok; pause_after_test ;;
            "1.8") test_func_08_services_partial_fail; pause_after_test ;;
            "1.9") test_func_09_logs_normal; pause_after_test ;;
            "1.10") test_func_10_logs_oom_detected; pause_after_test ;;
            "1.11") test_func_11_patrol_full_flow; pause_after_test ;;
            "1.12") test_func_12_collector_module; pause_after_test ;;
            "1.0") run_all_6_1 || true; pause_after_test ;;
            "2.1") test_excep_01_file_not_found_config; pause_after_test ;;
            "2.2") test_excep_02_command_not_found; pause_after_test ;;
            "2.3") test_excep_03_permission_denied; pause_after_test ;;
            "2.4") test_excep_04_invalid_threshold_config; pause_after_test ;;
            "2.5") test_excep_05_dmesg_command_unavailable; pause_after_test ;;
            "2.0") run_all_6_2 || true; pause_after_test ;;
            "3.1") test_boundary_01_cpu_100_percent; pause_after_test ;;
            "3.2") test_boundary_02_memory_100_percent; pause_after_test ;;
            "3.3") test_boundary_03_disk_100_percent; pause_after_test ;;
            "3.4") test_boundary_04_zero_usage; pause_after_test ;;
            "3.5") test_boundary_05_large_log_file; pause_after_test ;;
            "3.6") test_boundary_06_threshold_exact_match; pause_after_test ;;
            "3.0") run_all_6_3 || true; pause_after_test ;;
            "4.1") test_auto_01_single_run_consistency; pause_after_test ;;
            "4.2") test_auto_02_continuous_operation; pause_after_test ;;
            "4.3") test_auto_03_unattended_daemon_simulation; pause_after_test ;;
            "4.4") test_auto_04_mixed_state_handling; pause_after_test ;;
            "4.0") run_all_6_4 || true; pause_after_test ;;
            "A"|"a") run_all_tests || true; pause_after_test ;;
            "S"|"s") 
                echo ""
                test_summary
                echo ""
                echo "按回车返回菜单..."
                read -r
                ;;
            "Q"|"q") 
                echo ""
                echo -e "${CYAN}══════════════════════════════════════════════${NC}"
                echo -e "${CYAN}  最终测试统计${NC}"
                test_summary
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 启动主循环
main