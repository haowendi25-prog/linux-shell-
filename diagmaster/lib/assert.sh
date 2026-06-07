#!/usr/bin/env bash
# 轻量级测试断言库

TEST_PASSED=0
TEST_FAILED=0
TESTS_RUN=0

assert_equal() {
    local val="$1" expected="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$val" = "$expected" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: $msg"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: $msg (expected '$expected', got '$val')"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo -e "  ✔ PASS: $msg"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo -e "  ✘ FAIL: $msg (string does not contain '$needle')"
    fi
}

test_summary() {
    echo ""
    echo "=============================================="
    printf "测试完成: 通过 ${GREEN}${TEST_PASSED}${NC} / 失败 ${RED}${TEST_FAILED}${NC} / 总计 ${TESTS_RUN}\n"
    echo "=============================================="
    if [ $TEST_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}