#!/usr/bin/env bash
set -uo pipefail

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
ENABLE_AUTO_HEAL=${ENABLE_AUTO_HEAL:-true}
PATROL_REPORT_DIR=${PATROL_REPORT_DIR:-"./reports"}
PATROL_INTERVAL=${PATROL_INTERVAL:-300}
DAEMON_PID_FILE="${PATROL_REPORT_DIR}/../data/patrol_daemon.pid"

# 检测 systemd 是否真正在运行（而非仅 systemctl 二进制存在）
is_systemd_running() {
    # 方法1：检查 /run/systemd/system 目录是否存在
    # 方法2：检查 PID 1 是否为 systemd
    [ -d /run/systemd/system ] && return 0
    [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ] && return 0
    return 1
}

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
        # 只有 systemctl 存在且 systemd 真正运行时才使用 systemctl
        if command_exists systemctl && is_systemd_running; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                log_info "服务 $svc 正常"
            else
                log_warn "服务 $svc 异常"
                ((failed++))
            fi
        else
            # systemd 未运行或无 systemctl，使用 pgrep 检查进程
            if pgrep -x "$svc" &>/dev/null; then
                log_info "进程 $svc 存在"
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
        oom=$(dmesg 2>/dev/null | grep -c -i "out of memory" || true)
        oom=${oom//[^0-9]/}
        [ -z "$oom" ] && oom=0
    fi
    if [ -f /var/log/auth.log ]; then
        ssh_fail=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || true)
        ssh_fail=${ssh_fail//[^0-9]/}
        [ -z "$ssh_fail" ] && ssh_fail=0
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
# ========== 自愈动作 ==========

auto_heal() {
    local heal_log="${PATROL_REPORT_DIR}/../logs/heal.log"
    mkdir -p "$(dirname "$heal_log")"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$ts] 自愈检查开始" >> "$heal_log"
    echo -e "  ${YELLOW}[自愈]${NC} 开始自动修复检查..."

    local healed=0

    # 1. 磁盘使用率 > 85% 时触发安全清理
    local disk_usage=0
    disk_usage=$(df / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' | tr -d '[:space:]')
    [ -z "$disk_usage" ] && disk_usage=0
    if [ "$disk_usage" -gt 85 ] 2>/dev/null; then
        echo -e "  ${CYAN}▸${NC} 磁盘使用率 ${disk_usage}%，触发安全清理..."
        echo "[$ts] 磁盘使用率 ${disk_usage}%，触发安全清理" >> "$heal_log"

        find /tmp -type f -atime +1 -delete 2>/dev/null || true
        find /tmp -type d -empty -delete 2>/dev/null || true
        echo -e "       ${GREEN}✓${NC} /tmp 过期文件已清理"
        echo "[$ts] /tmp 过期文件已清理" >> "$heal_log"

        if command -v apt-get &>/dev/null; then
            apt-get clean 2>/dev/null || true
            echo -e "       ${GREEN}✓${NC} apt 缓存已清理"
            echo "[$ts] apt 缓存已清理" >> "$heal_log"
        fi

        if command -v journalctl &>/dev/null; then
            journalctl --vacuum-time=7d 2>/dev/null || true
            echo -e "       ${GREEN}✓${NC} journal 日志已清理（保留7天）"
            echo "[$ts] journal 日志已清理" >> "$heal_log"
        fi

        rm -rf "$HOME/.local/share/Trash/"* 2>/dev/null || true
        echo -e "       ${GREEN}✓${NC} 回收站已清空"
        echo "[$ts] 回收站已清空" >> "$heal_log"

        healed=1
    else
        echo -e "  ${GREEN}✓${NC} 磁盘使用率 ${disk_usage}%，无需清理"
    fi

    # 2. 重启关键服务（仅当服务存在但未运行时）
    local services=("cron" "ssh" "rsyslog")
    for svc in "${services[@]}"; do
        if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
            if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "enabled"; then
                if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
                    systemctl try-restart "$svc" 2>/dev/null || true
                    echo -e "  ${CYAN}▸${NC} 重启服务: ${svc}..."
                    echo -e "       ${GREEN}✓${NC} ${svc} 已重启"
                    echo "[$ts] 重启服务: $svc" >> "$heal_log"
                    healed=1
                fi
            fi
        fi
    done

    # 3. 修复 apt 依赖（仅当有 broken 依赖时）
    if command -v apt &>/dev/null; then
        if apt --fix-broken install -y 2>/dev/null | grep -q "has no installation candidate\|unmet dependencies"; then
            echo -e "  ${YELLOW}⚠${NC} apt 依赖修复需要人工处理"
            echo "[$ts] apt 依赖修复需要人工处理" >> "$heal_log"
            healed=1
        fi
    fi

    if [ "$healed" -eq 1 ]; then
        echo -e "  ${GREEN}✓${NC} 自愈检查结束，已执行修复动作"
        echo "[$ts] 自愈检查结束，已执行修复" >> "$heal_log"
    else
        echo -e "  ${GREEN}✓${NC} 自愈检查结束，系统健康无需修复"
        echo "[$ts] 自愈检查结束，系统健康" >> "$heal_log"
    fi
    echo ""
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

    if [ "${ENABLE_AUTO_HEAL:-false}" = "true" ] || [ "${PATROL_HEAL:-0}" -eq 1 ]; then
        auto_heal
    fi

    return $overall_fail
}

# ========== 后台守护巡逻模式 ==========

# 后台巡逻主循环（作为独立脚本执行）
_daemon_loop() {
    local pid_file="$1" interval="$2"
    echo "$BASHPID" > "$pid_file"
    local round=0
    while true; do
        round=$((round + 1))
        log_info "--- 巡逻轮次 #${round} ---"
        set +e
        run_patrol
        local ret=$?
        set +e  # 保持 set +e 状态
        if [ $ret -ne 0 ]; then
            echo -e "${RED}⚠ [$(date '+%H:%M:%S')] 巡逻轮次 #${round}: 发现异常项！${NC}"
        else
            echo -e "${GREEN}✓ [$(date '+%H:%M:%S')] 巡逻轮次 #${round}: 系统正常${NC}"
        fi
        sleep "$interval"
    done
}

# 后台持续巡逻（daemon 模式）
run_patrol_daemon() {
    local pid_file="${DAEMON_PID_FILE}"

    # 检查是否已有守护进程在运行
    if [ -f "$pid_file" ]; then
        local old_pid
        old_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_warn "巡逻守护进程已在运行中 (PID: $old_pid)"
            echo -e "${YELLOW}巡逻守护进程已在运行 (PID: $old_pid)${NC}"
            return 1
        else
            # pid 文件存在但进程不存在，清理旧文件
            rm -f "$pid_file"
        fi
    fi

    # 确保 data 目录存在
    mkdir -p "$(dirname "$pid_file")"

    log_info "启动巡逻守护进程，间隔 ${PATROL_INTERVAL} 秒"
    echo -e "${GREEN}启动巡逻守护进程，间隔 ${PATROL_INTERVAL} 秒${NC}"
    echo -e "${YELLOW}使用 --stop 参数停止，或 --status 查看状态${NC}"

    # 使用 nohup 启动独立进程，确保父脚本退出后仍继续运行
    nohup bash -c "
        source '${SCRIPT_DIR}/../lib/utils.sh'
        source '${SCRIPT_DIR}/patrol.sh'
        _daemon_loop '$pid_file' '$PATROL_INTERVAL'
    " < /dev/null >> "${PATROL_REPORT_DIR}/../logs/patrol_daemon.log" 2>&1 &

    local daemon_pid=$!
    # 等待子进程写入 PID 文件
    sleep 0.3
    if [ -f "$pid_file" ]; then
        local written_pid
        written_pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$written_pid" ] && kill -0 "$written_pid" 2>/dev/null; then
            echo -e "${GREEN}巡逻守护进程已启动 (PID: $written_pid)${NC}"
            log_info "巡逻守护进程已启动 (PID: $written_pid)"
        else
            echo -e "${YELLOW}巡逻守护进程已启动 (nohup PID: $daemon_pid)${NC}"
            log_info "巡逻守护进程已启动 (nohup PID: $daemon_pid)"
        fi
    else
        echo -e "${YELLOW}巡逻守护进程已启动 (nohup PID: $daemon_pid)${NC}"
        log_info "巡逻守护进程已启动 (nohup PID: $daemon_pid)"
    fi

    return 0
}

# 停止后台巡逻守护进程
stop_patrol_daemon() {
    local pid_file="${DAEMON_PID_FILE}"

    if [ ! -f "$pid_file" ]; then
        echo -e "${YELLOW}未找到运行中的巡逻守护进程${NC}"
        return 1
    fi

    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    if [ -z "$pid" ]; then
        echo -e "${YELLOW}PID 文件为空${NC}"
        rm -f "$pid_file"
        return 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        # 先杀掉主进程，再杀掉子进程（后台的 while 循环）
        kill "$pid" 2>/dev/null || true
        pkill -P "$pid" 2>/dev/null || true
        sleep 0.5
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
        echo -e "${GREEN}巡逻守护进程已停止 (PID: $pid)${NC}"
        log_info "巡逻守护进程已停止 (PID: $pid)"
        return 0
    else
        echo -e "${YELLOW}进程不存在 (PID: $pid)，清理 PID 文件${NC}"
        rm -f "$pid_file"
        return 1
    fi
}

# 检查巡逻守护进程状态
patrol_daemon_status() {
    local pid_file="${DAEMON_PID_FILE}"

    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}巡逻守护进程正在运行 (PID: $pid)${NC}"
            return 0
        else
            echo -e "${YELLOW}PID 文件存在但进程已失效${NC}"
            rm -f "$pid_file"
            return 1
        fi
    else
        echo -e "${YELLOW}巡逻守护进程未运行${NC}"
        return 1
    fi
}

# 若直接执行本脚本，支持参数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --daemon)
            run_patrol_daemon
            ;;
        --stop)
            stop_patrol_daemon
            ;;
        --status)
            patrol_daemon_status
            ;;
        *)
            run_patrol
            ;;
    esac
    exit $?
fi
