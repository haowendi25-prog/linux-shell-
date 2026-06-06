#!/bin/bash

# 基线文件存储路径
BASELINE_DIR="$HOME/.diagmaster"
BASELINE_FILE="$BASELINE_DIR/baseline.dat"
mkdir -p "$BASELINE_DIR"

analyze_data() {
    echo -e "\033[34m[*] 正在解析系统指标并对比历史基线...\033[0m"

    # 1. 解析当前指标
    # 从 vmstat 提取 idle 和 iowait
    local vmstat_line=$(tail -n 1 "$TMP_DIR/vmstat.tmp")
    local cpu_idle=$(echo "$vmstat_line" | awk '{print $15}')
    CURRENT_CPU=$((100 - cpu_idle))
    CURRENT_IOWAIT=$(echo "$vmstat_line" | awk '{print $16}')
    
    # 从 free 提取内存使用率
    CURRENT_MEM=$(free | grep Mem: | awk '{print int($3/$2 * 100)}')
    
    # 从 df 提取磁盘使用率
    CURRENT_DISK=$(df -h / | tail -n 1 | awk '{print $5}' | sed 's/%//')

    # 2. 读取与计算历史基线
    if [ -f "$BASELINE_FILE" ]; then
        # 读取上一次的值
        source "$BASELINE_FILE"
        
        # 计算变动差值
        CPU_DIFF=$((CURRENT_CPU - LAST_CPU))
        MEM_DIFF=$((CURRENT_MEM - LAST_MEM))
    else
        # 第一次运行，没有基线
        CPU_DIFF=0
        MEM_DIFF=0
    fi

    # 3. 保存本次数据作为下一次的基线
    echo "LAST_CPU=$CURRENT_CPU" > "$BASELINE_FILE"
    echo "LAST_MEM=$CURRENT_MEM" >> "$BASELINE_FILE"
}
