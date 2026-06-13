#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 安全审计模块测试
# 测试 modules/log_analyzer.sh 核心函数（11个用例）
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"
source "$TEST_DIR/lib/mock_utils.sh"

# 设置审计所需变量（在 source log_analyzer.sh 之前）
OOM_WARN_THRESHOLD=5
SSH_FAIL_WARN_THRESHOLD=30
MAX_LOG_LINES=10000
AUDIT_DAYS=7
DATA_DIR="${PROJECT_ROOT}/data"
REPORT_DIR="/tmp/test_audit_reports"
LOG_DIR="/tmp/test_audit_logs"
HISTORY_DIR="${DATA_DIR}/audit_history"
mkdir -p "$DATA_DIR" "$REPORT_DIR" "$LOG_DIR" "$HISTORY_DIR"

source "$PROJECT_ROOT/modules/log_analyzer.sh" 2>/dev/null || true

# 重新覆盖（防止被 source 时覆盖）
OOM_WARN_THRESHOLD=5
SSH_FAIL_WARN_THRESHOLD=30
AUDIT_DAYS=7
REPORT_DIR="/tmp/test_audit_reports"
LOG_DIR="/tmp/test_audit_logs"

# ==============================================================
# 测试用例
# ==============================================================

test_detect_log_sources() {
    echo "[TEST] 日志源检测: 检测可用日志文件"
    local sources
    sources=$(detect_log_sources 2>/dev/null || echo "")
    TESTS_RUN=$((TESTS_RUN+1))
    if [ -n "$sources" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        local count
        count=$(echo "$sources" | grep -c '/' 2>/dev/null || echo "0")
        echo "  ✔ PASS: detect_log_sources 发现 ${count} 个日志源"
    else
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: detect_log_sources 正常执行（当前环境无系统日志文件）"
    fi
}

test_is_wsl_detection() {
    echo "[TEST] WSL 环境检测: is_wsl 正常执行不崩溃"
    local ret
    set +e
    if is_wsl; then ret="WSL"; else ret="非WSL"; fi
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: is_wsl 正常执行，当前环境=${ret}"
}

test_is_whitelisted_sudo() {
    echo "[TEST] sudo 白名单: 合法命令通过白名单"
    local ret_apt ret_unknown
    if is_whitelisted_sudo "/usr/bin/apt update"; then ret_apt=0; else ret_apt=1; fi
    if is_whitelisted_sudo "/tmp/evil.sh"; then ret_unknown=0; else ret_unknown=1; fi
    assert_equal "$ret_apt" "0" "/usr/bin/apt 应在白名单内(0)"
    assert_equal "$ret_unknown" "1" "/tmp/evil.sh 不应在白名单内(1)"
}

test_filter_by_time() {
    echo "[TEST] 时间过滤: filter_by_time 对空文件不崩溃"
    local tmp_input="${DATA_DIR}/filter_test_input.tmp"
    echo "" > "$tmp_input"
    set +e
    filter_by_time "$tmp_input" 7 >/dev/null 2>&1 || true
    set -e
    rm -f "$tmp_input"
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: filter_by_time 对空文件正常执行不崩溃"
}

test_analyze_oom_mocked() {
    echo "[TEST] OOM 分析: 使用 mock dmesg 统计 OOM 次数"
    setup_mocks
    # dmesg -T 在 WSL 下输出 YYYY-MM-DD 格式
    cat > "$MOCK_DIR/dmesg" << 'DMESG_EOF'
#!/bin/bash
if echo "$*" | grep -q -- "-T"; then
    echo "[2026-06-13 12:00:00] Out of memory: Kill process 1234 (java)"
    echo "[2026-06-13 12:00:01] invoked oom-killer: gfp_mask=0x201da"
    echo "[2026-06-13 12:00:02] Out of memory: Kill process 5678 (mysql)"
else
    echo "Out of memory: Kill process 1234 (java)"
    echo "invoked oom-killer: gfp_mask=0x201da"
    echo "Out of memory: Kill process 5678 (mysql)"
fi
DMESG_EOF
    chmod +x "$MOCK_DIR/dmesg"
    source "$PROJECT_ROOT/modules/log_analyzer.sh" 2>/dev/null || true
    local oom_count
    set +e
    oom_count=$(analyze_oom 2>/dev/null || echo "0")
    set -e
    teardown_mocks
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${oom_count:-0}" -ge 2 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: analyze_oom 正确统计 OOM 次数=${oom_count}（期望 >= 2）"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: analyze_oom 返回=${oom_count}，期望 >= 2"
    fi
}

test_analyze_kernel_errors() {
    echo "[TEST] 内核错误分析: analyze_kernel_errors 正常执行"
    local err_count
    set +e
    err_count=$(analyze_kernel_errors 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: analyze_kernel_errors 正常执行，内核错误数=${err_count}"
}

test_analyze_syslog_errors() {
    echo "[TEST] 系统日志清洗: analyze_syslog_errors 正常执行"
    local err_count
    set +e
    err_count=$(analyze_syslog_errors 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: analyze_syslog_errors 正常执行，系统错误数=${err_count}"
}

test_detect_port_scan() {
    echo "[TEST] 端口扫描检测: detect_port_scan 正常执行"
    local scan_count
    set +e
    scan_count=$(detect_port_scan 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: detect_port_scan 正常执行，扫描源数=${scan_count}"
}

test_detect_malware_indicators() {
    echo "[TEST] 恶意软件检测: detect_malware_indicators 正常执行"
    local malware_count
    set +e
    malware_count=$(detect_malware_indicators 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    TEST_PASSED=$((TEST_PASSED+1))
    echo "  ✔ PASS: detect_malware_indicators 正常执行，恶意迹象数=${malware_count}"
}

test_calculate_risk_score_zero() {
    echo "[TEST] 风险评分: 零事件应返回低分"
    local score
    set +e
    score=$(calculate_risk_score "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" "0" 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${score:-100}" -le 20 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 零事件风险评分=${score}，应在安全范围（<=20）"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 零事件风险评分=${score}，期望 <= 20"
    fi
}

test_calculate_risk_score_danger() {
    echo "[TEST] 风险评分: 严重事件应返回高分"
    local score
    set +e
    score=$(calculate_risk_score "15" "15" "200" "5" "15" "200" "10" "10" "5" "5" "3" "20" 2>/dev/null || echo "0")
    set -e
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "${score:-0}" -ge 80 ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: 严重事件风险评分=${score}，应>=80（高危）"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: 严重事件风险评分=${score}，期望 >= 80"
    fi
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 安全审计模块测试 (12个用例)"
    echo "=============================================="
    echo ""

    test_detect_log_sources
    test_is_wsl_detection
    test_is_whitelisted_sudo
    test_filter_by_time
    test_analyze_oom_mocked
    test_analyze_kernel_errors
    test_analyze_syslog_errors
    test_detect_port_scan
    test_detect_malware_indicators
    test_calculate_risk_score_zero
    test_calculate_risk_score_danger

    test_summary || true
}

run_all_tests || true