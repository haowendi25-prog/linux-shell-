#!/usr/bin/env bash
set -euo pipefail

# 加载公共库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"

# 加载配置（允许缺失）
if [ -f "$SCRIPT_DIR/../config/diag.conf" ]; then
    source "$SCRIPT_DIR/../config/diag.conf"
fi

# 设置默认阈值
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}
SERVICES_TO_CHECK=${SERVICES_TO_CHECK:-"sshd cron"}
PROCESSES_TO_CHECK=${PROCESSES_TO_CHECK:-"sshd"}
ENABLE_ALERT=${ENABLE_ALERT:-false}
ALERT_EMAIL=${ALERT_EMAIL:-"root@localhost"}
PATROL_REPORT_DIR=${PATROL_REPORT_DIR:-"./reports"}

# ========== 检查函数 ==========

check_cpu() {
    local cpu_val threshold
    threshold=$CPU_WARN_THRESHOLD
    if command_exists top; then
        cpu_val=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2+$4}' 2>/dev/null || echo "")
    else
        if [ -r /proc/stat ]; then
            cpu_val=$(awk '/^cpu / {if($2+$4+$5>0) print ($2+$4)*100/($2+$4+$5); else print 0}' /proc/stat 2>/dev/null || echo "")
        fi
    fi
    if [ -z "$cpu_val" ]; then
        log_error "无法获取 CPU 使用率"
        echo 2
        return
    fi
    # 使用公共函数 greater_than
    if greater_than "$cpu_val" "$threshold"; then
        echo 1
    else
        echo 0
    fi
}

check_memory() {
    local mem_val threshold
    threshold=$MEM_WARN_THRESHOLD
    if command_exists free; then
        mem_val=$(free -m 2>/dev/null | awk '/Mem:/ {if($2>0) print $3/$2*100; else print 0}' || echo "")
    else
        if [ -r /proc/meminfo ]; then
            local total avail
            total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
            avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
            if [ -n "$total" ] && [ "$total" -gt 0 ]; then
                mem_val=$(awk -v t="$total" -v a="$avail" 'BEGIN {print (t-a)*100/t}')
            fi
        fi
    fi
    if [ -z "$mem_val" ]; then
        log_error "无法获取内存使用率"
        echo 2
        return
    fi
    if greater_than "$mem_val" "$threshold"; then
        echo 1
    else
        echo 0
    fi
}

check_disk() {
    local disk_val threshold
    threshold=$DISK_WARN_THRESHOLD
    if command_exists df; then
        disk_val=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "")
    fi
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

check_services() {
    local services failed=0
    read -ra services <<< "$SERVICES_TO_CHECK"
    for svc in "${services[@]}"; do
        if command_exists systemctl; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                log_info "服务 $svc 正常"
            else
                log_warn "服务 $svc 异常"
                ((failed++))
            fi
        else
            # 无 systemd，使用 ps 粗略检查
            if pgrep -x "$svc" &>/dev/null; then
                log_info "进程 $svc 存在（systemctl 不可用）"
            else
                log_warn "进程 $svc 缺失"
                ((failed++))
            fi
        fi
    done
    if [ $failed -eq 0 ]; then
        echo 0
    else
        echo 1
    fi
}

check_processes() {
    local procs missing=0
    read -ra procs <<< "$PROCESSES_TO_CHECK"
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

check_logs() {
    local oom=0 ssh_fail=0 abnormal=0
    if command_exists dmesg; then
        oom=$(dmesg 2>/dev/null | grep -c -i "out of memory" || echo 0)
    fi
    if [ -f /var/log/auth.log ]; then
        ssh_fail=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo 0)
    fi
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

run_patrol() {
    local report_file="${PATROL_REPORT_DIR}/patrol_$(date +%Y%m%d_%H%M%S).md"
    init_report "$report_file"
    log_info "自动巡逻开始..."

    local overall_fail=0
    local names=("CPU使用率" "内存使用率" "磁盘使用率" "关键服务" "关键进程" "日志异常")
    local funcs=("check_cpu" "check_memory" "check_disk" "check_services" "check_processes" "check_logs")
    local details=("阈值:${CPU_WARN_THRESHOLD}%" "阈值:${MEM_WARN_THRESHOLD}%" "阈值:${DISK_WARN_THRESHOLD}%" "$SERVICES_TO_CHECK" "$PROCESSES_TO_CHECK" "OOM/SSH爆破")
    local statuses=()

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

    # 写入报告
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

    if [ "$ENABLE_ALERT" = true ] && [ $overall_fail -eq 1 ]; then
        if command_exists mail; then
            mail -s "[DiagMaster] 服务器异常告警" "$ALERT_EMAIL" < "$report_file"
        else
            log_warn "邮件命令不可用，无法发送告警"
        fi
    fi

    return $overall_fail
}

# 若直接执行本脚本，则运行巡逻
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_patrol
    exit $?
fi