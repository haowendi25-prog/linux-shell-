#!/usr/bin/env bash
# 日志分析特征提取模块

DATA_DIR="$(dirname "$0")/../data"
mkdir -p "$DATA_DIR"

# 内核环形缓冲区 OOM 统计
if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | grep -c -i "out of memory" > "$DATA_DIR/oom_count.tmp" || echo "0" > "$DATA_DIR/oom_count.tmp"
else
    echo "0" > "$DATA_DIR/oom_count.tmp"
fi

# 安全日志 SSH 暴破统计
if [ -f /var/log/auth.log ]; then
    grep -c "Failed password" /var/log/auth.log 2>/dev/null > "$DATA_DIR/ssh_fail.tmp" || echo "0" > "$DATA_DIR/ssh_fail.tmp"
else
    echo "0" > "$DATA_DIR/ssh_fail.tmp"
fi