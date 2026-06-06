#!/usr/bin/env bash
set -euo pipefail

# 加载公共库和配置
source "$(dirname "$0")/../lib/utils.sh"
source "$(dirname "$0")/../config/diag.conf" 2>/dev/null || {
    log_error "无法加载配置文件"
    exit 1
}

# 默认值
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}
SERVICES_TO_CHECK=${SERVICES_TO_CHECK:-""}
PROCESSES_TO_CHECK=${PROCESSES_TO_CHECK:-""}

# 巡逻结果全局变量声明
PATROL_OK=0
PATROL_WARN=1
PATROL_ERROR=2

# 各检查项状态数组
check_status=()
check_details=()

# 初始化报告文件
init_report() {
    local report_file="$1"
    mkdir -p "$(dirname "$report_file")"
    cat << EOF > "$report_file"
# DiagMaster 自动巡逻报告
- 生成时间: $(date)
- 主机名: $(hostname)
- 系统负载: $(uptime)

EOF
}

# ========== 检查函数 ==========

# 1. CPU 使用率检查
check_cpu() {
    local threshold=$CPU_WARN_THRESHOLD
    local cpu_val
    if command_exists top; then
        cpu_val=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' 2>/dev/null || echo "0")
    else
        log_warn "top 命令不可用，尝试从 /proc/stat 读取"
        cpu_val=$(cat /proc/stat | grep '^cpu ' | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}')
    fi
    if [ -z "$cpu_val" ]; then
        log_error "无法获取 CPU 使用率"
        echo 2   # 返回检查失败
        return
    fi
    if (( $(echo "$cpu_val > $threshold" | bc -l 2>/dev/null || echo 0) )); then
        echo 1   # 告警
    else
        echo 0   # 正常
    fi
}

# 2. 内存使用率检查
check_memory() {
    local threshold=$MEM_WARN_THRESHOLD
    local mem_val
    mem_val=$(free -m | awk '/Mem:/ {print $3/$2*100}' 2>/dev/null || echo "0")
    if [ -z "$mem_val" ]; then
        log_error "无法获取内存使用率"
        echo 2
        return
    fi
    if (( $(echo "$mem_val > $threshold" | bc -l 2>/dev/null || echo 0) )); then
        echo 1
    else
        echo 0
    fi
}

# 3. 磁盘使用率检查
check_disk() {
    local threshold=$DISK_WARN_THRESHOLD
    local disk_val
    disk_val=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null || echo "0")
    if [ -z "$disk_val" ]; then
        log_error "无法获取磁盘使用率"
        echo 2
        return
    fi
    if [ "$disk_val" -gt "$threshold" ]; then
        echo 1
    else
        echo 0
    fi
}

# 4. 服务状态检查
check_services() {
    local services=($SERVICES_TO_CHECK)
    local failed=0
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_info "服务 $svc 运行正常"
        else
            log_warn "服务 $svc 异常或未运行"
            ((failed++))
        fi
    done
    if [ $failed -eq 0 ]; then
        echo 0
    elif [ $failed -lt ${#services[@]} ]; then
        echo 1
    else
        echo 1
    fi
}

# 5. 进程存活检查
check_processes() {
    local procs=($PROCESSES_TO_CHECK)
    local missing=0
    for proc in "${procs[@]}"; do
        if pgrep -x "$proc" &>/dev/null; then
            log_info "进程 $proc 存在"
        else
            log_warn "进程 $proc 缺失"
            ((missing++))
        fi
    done
    if [ $missing -eq 0 ]; then
        echo 0
    else
        echo 1
    fi
}

# 6. 日志异常检查（复用 log_analyzer.sh 逻辑）
check_logs() {
    local oom=0
    local ssh_fail=0
    # 若 dmesg 存在，统计 OOM
    if command_exists dmesg; then
        oom=$(dmesg 2>/dev/null | grep -c -i "out of memory" || echo 0)
    fi
    # 若安全日志存在，统计 SSH 爆破
    if [ -f /var/log/auth.log ]; then
        ssh_fail=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
    fi
    local abnormal=0
    if [ "$oom" -gt 0 ]; then
        log_warn "检测到 OOM 事件: $oom 次"
        abnormal=1
    fi
    if [ "$ssh_fail" -gt 30 ]; then
        log_warn "SSH 暴力破解尝试: $ssh_fail 次"
        abnormal=1
    fi
    if [ $abnormal -eq 1 ]; then
        echo 1
    else
        echo 0
    fi
}

# ========== 巡逻主流程 ==========
run_patrol() {
    local report_file="${PATROL_REPORT_DIR}/patrol_$(date +%Y%m%d_%H%M%S).md"
    init_report "$report_file"
    log_info "自动巡逻开始..."

    local overall_fail=0
    # 执行所有检查，记录结果
    local names=("CPU使用率" "内存使用率" "磁盘使用率" "关键服务" "关键进程" "日志异常")
    local funcs=("check_cpu" "check_memory" "check_disk" "check_services" "check_processes" "check_logs")
    local statuses=()
    local details=("阈值:${CPU_WARN_THRESHOLD}%" "阈值:${MEM_WARN_THRESHOLD}%" "阈值:${DISK_WARN_THRESHOLD}%" "$SERVICES_TO_CHECK" "$PROCESSES_TO_CHECK" "OOM/SSH爆破")

    for i in "${!funcs[@]}"; do
        local ret
        ret=$(${funcs[$i]})
        statuses[$i]=$ret
        case $ret in
            0) log_info "${names[$i]}: 正常" ;;
            1) log_warn "${names[$i]}: 异常" ; overall_fail=1 ;;
            2) log_error "${names[$i]}: 无法检查" ;;
        esac
    done

    # 生成报告
    {
        echo "## 检查结果汇总"
        if [ $overall_fail -eq 0 ]; then
            echo "**整体状态: 正常 ✅**"
        else
            echo "**整体状态: 存在异常 ⚠️**"
        fi
        echo ""
        echo "| 检查项 | 状态 | 详情 |"
        echo "|--------|------|------|"
        for i in "${!names[@]}"; do
            local status_str
            case ${statuses[$i]} in
                0) status_str="正常" ;;
                1) status_str="异常" ;;
                2) status_str="无法检查" ;;
            esac
            echo "| ${names[$i]} | $status_str | ${details[$i]} |"
        done
    } >> "$report_file"

    log_info "巡逻报告已生成: $report_file"

    # 可选告警
    if [ "$ENABLE_ALERT" = true ] && [ $overall_fail -eq 1 ]; then
        send_alert "$report_file"
    fi

    return $overall_fail
}

# 发送告警（简单邮件示例）
send_alert() {
    local report_path="$1"
    if command_exists mail; then
        cat "$report_path" | mail -s "[DiagMaster] 服务器异常告警" "$ALERT_EMAIL"
        log_info "已发送告警邮件至 $ALERT_EMAIL"
    else
        log_warn "邮件命令不可用，无法发送告警"
    fi
}

# 如果直接执行本脚本，则运行巡逻
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_patrol
    exit $?
fi