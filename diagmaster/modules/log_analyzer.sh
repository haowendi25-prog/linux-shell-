#!/usr/bin/env bash
# 日志分析特征提取模块

# 定向清洗内核环形缓冲区(dmesg)中的内存溢出事件
if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | grep -c -i "out of memory" > ./data/oom_count.tmp || echo "0" > ./data/oom_count.tmp
else
    echo "0" > ./data/oom_count.tmp
fi

# 基于安全日志过滤非法的远程运维登录尝试
if [ -f /var/log/auth.log ]; then
    grep -c "Failed password" /var/log/auth.log > ./data/ssh_fail.tmp || echo "0" > ./data/ssh_fail.tmp
else
    echo "0" > ./data/ssh_fail.tmp
fi
