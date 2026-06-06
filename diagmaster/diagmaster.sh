#!/bin/bash

# ==========================================
# DiagMaster —— Linux 服务器一键智能诊断工具
# ==========================================

# 确保脚本在遇到错误时能有一定鲁棒性
set -e

# 1. 引入配置文件和各个子模块
source ./config/threshold.conf
source ./lib/collector.sh
source ./lib/analyzer.sh
source ./lib/reporter.sh
source ./rules/cpu_rules.sh
source ./rules/disk_rules.sh

# 2. 核心执行流流水线
main() {
    echo -e "\033[35m======================================\033[0m"
    echo -e "\033[35m     欢迎使用 DiagMaster 智能诊断工具    \033[0m"
    echo -e "\033[35m======================================\033[0m"
    
    # 执行流水线
    collect_data
    analyze_data
    diagnose_cpu
    diagnose_disk
    generate_report
}

# 运行主程序
main
