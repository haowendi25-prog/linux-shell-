#!/bin/bash

# 创建全局唯一的临时目录
TMP_DIR=$(mktemp -d /tmp/diagmaster.XXXXXX)

collect_data() {
    echo -e "\033[34m[*] 开始并行采集系统数据...\033[0m"
    
    # 1. 采集 CPU 和 IOWait (使用 vmstat 采集 2 次取第 2 次的值)
    vmstat 1 2 > "$TMP_DIR/vmstat.tmp" &
    
    # 2. 采集内存信息
    free -m > "$TMP_DIR/free.tmp" &
    
    # 3. 采集磁盘空间
    df -h / > "$TMP_DIR/df.tmp" &
    
    # 4. 采集最耗 CPU 的前 5 个进程
    ps aux --sort=-%cpu | head -n 6 > "$TMP_DIR/ps_cpu.tmp" &
    
    # 5. 采集内核日志最后 50 行
    dmesg | tail -n 50 > "$TMP_DIR/dmesg.tmp" &

    # 等待所有后台并行任务完成
    wait
    echo -e "\033[32m[+] 数据采集完成，暂存至 $TMP_DIR\033[0m"
}
