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
        echo "✔ PASS: $msg"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "✘ FAIL: $msg (expected '$expected', got '$val')"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "✔ PASS: $msg"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "✘ FAIL: $msg (string does not contain '$needle')"
    fi
}

assert_return() {
    local expected_ret="$1" cmd="$2" msg="${3:-}"
    TESTS_RUN=$((TESTS_RUN+1))
    if eval "$cmd" &>/dev/null; then
        actual_ret=0
    else
        actual_ret=$?
    fi
    if [ "$actual_ret" = "$expected_ret" ]; then
        TEST_PASSED=$((TEST_PASSED+1))
        echo "✔ PASS: $msg"
    else
        TEST_FAILED=$((TEST_FAILED+1))
        echo "✘ FAIL: $msg (expected return $expected_ret, got $actual_ret)"
    fi
}

test_summary() {
    echo "=============================="
    echo "测试完成: 通过 $TEST_PASSED / 失败 $TEST_FAILED / 总计 $TESTS_RUN"
    echo "=============================="
    if [ $TEST_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}