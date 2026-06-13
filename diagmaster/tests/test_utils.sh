#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# DiagMaster 公共工具库单元测试
# 测试 lib/utils.sh 中的核心函数（8个用例）
# ==============================================================

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/assert.sh"
source "$TEST_DIR/lib/mock_utils.sh"

# ==============================================================
# 测试用例
# ==============================================================

test_greater_than_true() {
    echo "[TEST] greater_than: a > b 返回 true"
    local ret
    if greater_than "90" "80"; then
        ret=0
    else
        ret=1
    fi
    assert_equal "$ret" "0" "90 > 80 应返回 true(0)"
}

test_greater_than_false() {
    echo "[TEST] greater_than: a < b 返回 false"
    local ret
    if greater_than "50" "80"; then
        ret=0
    else
        ret=1
    fi
    assert_equal "$ret" "1" "50 > 80 应返回 false(1)"
}

test_greater_than_equal() {
    echo "[TEST] greater_than: a == b 返回 false"
    local ret
    if greater_than "80" "80"; then
        ret=0
    else
        ret=1
    fi
    assert_equal "$ret" "1" "80 == 80 应返回 false(1)"
}

test_greater_than_decimal() {
    echo "[TEST] greater_than: 小数比较 95.1 > 95.0"
    local ret
    if greater_than "95.1" "95.0"; then
        ret=0
    else
        ret=1
    fi
    assert_equal "$ret" "0" "95.1 > 95.0 应返回 true(0)"
}

test_command_exists_true() {
    echo "[TEST] command_exists: bash 存在"
    local ret
    if command_exists "bash"; then ret=0; else ret=1; fi
    assert_equal "$ret" "0" "bash 命令应存在"
}

test_command_exists_false() {
    echo "[TEST] command_exists: 不存在的命令返回 false"
    local ret
    if command_exists "diagmaster_nonexistent_cmd_xyz"; then ret=0; else ret=1; fi
    assert_equal "$ret" "1" "不存在的命令应返回 false"
}

test_test_ssh_localhost() {
    echo "[TEST] test_ssh_connection: localhost 直接返回 0"
    local ret
    if test_ssh_connection "localhost" 1; then ret=0; else ret=1; fi
    assert_equal "$ret" "0" "localhost 应直接返回在线(0)"
}

test_collect_remote_localhost() {
    echo "[TEST] collect_remote: 本地采集返回有效数据"
    setup_mocks
    source "$PROJECT_ROOT/modules/collector.sh" 2>/dev/null || true
    local output
    output=$(collect_remote "localhost" 2>/dev/null || echo "FAIL")
    teardown_mocks
    if echo "$output" | grep -q "CPU=" && echo "$output" | grep -q "MEM=" && echo "$output" | grep -q "DISK="; then
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_PASSED=$((TEST_PASSED+1))
        echo "  ✔ PASS: collect_remote localhost 返回 CPU/MEM/DISK 数据"
    else
        TESTS_RUN=$((TESTS_RUN+1))
        TEST_FAILED=$((TEST_FAILED+1))
        echo "  ✘ FAIL: collect_remote localhost 返回数据异常: $output"
    fi
}

# ==============================================================
# 运行入口
# ==============================================================

run_all_tests() {
    echo ""
    echo "=============================================="
    echo "  DiagMaster 公共工具库测试 (8个用例)"
    echo "=============================================="
    echo ""

    test_greater_than_true
    test_greater_than_false
    test_greater_than_equal
    test_greater_than_decimal
    test_command_exists_true
    test_command_exists_false
    test_test_ssh_localhost
    test_collect_remote_localhost

    test_summary || true
}

run_all_tests || true