#!/bin/bash

generate_report() {
    echo -e "\033[34m[*] 正在生成智能诊断报告...\033[0m"
    
    local report_time=$(date "+%Y-%m-%d %H:%M:%S")
    local file_time=$(date "+%Y%m%d_%H%M%S")
    REPORT_PATH="$HOME/.diagmaster/report_${file_time}.md"

    cat << EOF > "$REPORT_PATH"
# 🛡️ DiagMaster 智能诊断报告
**生成时间**: ${report_time}
**主机名称**: $(hostname)

---

## 🚨 异常指标摘要
$( [ "$CURRENT_CPU" -gt "$CPU_THRESHOLD" ] && echo "- [🔴] **CPU使用率超标**: 当前 ${CURRENT_CPU}% (阈值 ${CPU_THRESHOLD}%)" )
$( [ "$CURRENT_DISK" -gt "$DISK_THRESHOLD" ] && echo "- [🔴] **磁盘空间告急**: 当前 ${CURRENT_DISK}% (阈值 ${DISK_THRESHOLD}%)" )
$( [ "$CURRENT_CPU" -le "$CPU_THRESHOLD" ] && [ "$CURRENT_DISK" -le "$DISK_THRESHOLD" ] && echo "- [🍏] 暂未发现超出阈值的系统指标。" )

---

## 📈 历史基线对比 (与上次运行相比)
* **CPU 变动**: $( [ $CPU_DIFF -ge 0 ] && echo "🟢 上升了 ${CPU_DIFF}%" || echo "🔵 下降了 ${CPU_DIFF#-%}%" )
* **内存变动**: $( [ $MEM_DIFF -ge 0 ] && echo "🟢 上升了 ${MEM_DIFF}%" || echo "🔵 下降了 ${MEM_DIFF#-%}%" )

---

## 🧠 智能根因分析与修复建议

### 1. CPU 专项诊断
* **诊断结论**: ${CPU_CONCLUSION}
* **处理建议**: 
${CPU_SUGGESTION}

### 2. 磁盘专项诊断
* **诊断结论**: ${DISK_CONCLUSION}
* **处理建议**: 
${DISK_SUGGESTION}

---

## 📊 详细性能指标快照
* **CPU 使用率**: ${CURRENT_CPU}%
* **IOWait 状态**: ${CURRENT_IOWAIT}%
* **内存使用率**: ${CURRENT_MEM}%
* **根分区占用**: ${CURRENT_DISK}%

---
💡 *提示：本报告由 DiagMaster 纯Shell诊断工具自动生成。临时文件已安全清理。*
EOF

    # 清理临时文件
    rm -rf "$TMP_DIR"
    
    echo -e "\033[32m[+] 诊断完成！开源级精美报告已保存至: $REPORT_PATH\033[0m"
    echo -e "\033[33m[!] 提示：你可以直接运行 'cat $REPORT_PATH' 查看报告内容。\033[0m"
}
