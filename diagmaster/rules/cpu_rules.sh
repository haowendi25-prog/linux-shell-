#!/bin/bash

diagnose_cpu() {
    # 初始化诊断结论变量
    CPU_CONCLUSION="正常"
    CPU_SUGGESTION="无需操作"

    # 如果当前 CPU 超过了配置的阈值
    if [ "$CURRENT_CPU" -gt "$CPU_THRESHOLD" ]; then
        # 抓取第一名的进程名
        local top_process=$(tail -n +2 "$TMP_DIR/ps_cpu.tmp" | head -n 1 | awk '{print $11}')
        local top_pid=$(tail -n +2 "$TMP_DIR/ps_cpu.tmp" | head -n 1 | awk '{print $2}')
        
        # 多维度联动判断 1：CPU 高且 IOWait 也高 (磁盘问题)
        if [ "$CURRENT_IOWAIT" -gt "$IOWAIT_THRESHOLD" ]; then
            CPU_CONCLUSION="危险：CPU使用率极高且伴随高 IOWait 瓶颈！"
            CPU_SUGGESTION="排查发现当前 IOWait 为 ${CURRENT_IOWAIT}%，极可能是由于磁盘读写频繁，导致进程 [${top_process}] 处于等待状态。\n💡 建议命令：使用 'iostat -x 1 5' 查看磁盘繁忙度，或检查存储硬件健康度。"
        
        # 多维度联动判断 2：是否有硬件报错 (内核日志联动)
        elif grep -qiE "hardware error|mcelog|tsc" "$TMP_DIR/dmesg.tmp"; then
            CPU_CONCLUSION="严重：CPU异常，检测到内核硬件报错！"
            CPU_SUGGESTION="dmesg 日志中发现 Hardware Error 字段。\n💡 建议命令：立即运行 'dmesg | grep -i error' 检查 CPU 硬件或主板供电。"
        
        # 默认判断 3：纯计算型单一进程爆满
        else
            CPU_CONCLUSION="警告：CPU 使用率过高，主要由单一计算进程引起。"
            CPU_SUGGESTION="进程 [${top_process}] (PID: ${top_pid}) 正在大量消耗 CPU 算力。\n💡 建议命令：\n   1) 限制该进程CPU：cpulimit -p ${top_pid} -l 50\n   2) 结束异常进程：kill -9 ${top_pid}"
        fi
    fi
}
