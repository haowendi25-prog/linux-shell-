#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DiagMaster - 多进程性能指标并行采集模块 (v1.0)
# 功能：CPU/内存/磁盘使用率并发采集、阈值告警、历史对比
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"
HISTORY_DIR="${DATA_DIR}/history"
mkdir -p "$DATA_DIR" "$HISTORY_DIR"

# 加载公共工具库（允许缺失）
if [ -f "$SCRIPT_DIR/../lib/utils.sh" ]; then
    source "$SCRIPT_DIR/../lib/utils.sh"
fi

# 加载配置（允许缺失，使用默认值）
if [ -f "$SCRIPT_DIR/../config/diag.conf" ]; then
    source "$SCRIPT_DIR/../config/diag.conf"
fi

CPU_WARN=${CPU_WARN_THRESHOLD:-80}
MEM_WARN=${MEM_WARN_THRESHOLD:-85}
DISK_WARN=${DISK_WARN_THRESHOLD:-90}

# ---------- 本地颜色（防止 sourcing 时缺失） ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== 采集函数 ==========

# 采集 CPU 使用率（支持 top 和 /proc/stat 两种方式）
collect_cpu() {
    local cpu_val=""
    if command -v top &>/dev/null; then
        cpu_val=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2+$4}' 2>/dev/null || echo "")
    fi
    if [ -z "$cpu_val" ] && [ -r /proc/stat ]; then
        # 读取两次 /proc/stat 取差值，更精确
        local stat1 stat2
        stat1=$(grep '^cpu ' /proc/stat)
        sleep 0.5
        stat2=$(grep '^cpu ' /proc/stat)
        cpu_val=$(awk -v s1="$stat1" -v s2="$stat2" '
            BEGIN {
                split(s1, a, " "); idle1 = a[5] + a[6]; total1 = 0
                for (i=2;i<=11;i++) total1 += a[i]
                split(s2, b, " "); idle2 = b[5] + b[6]; total2 = 0
                for (i=2;i<=11;i++) total2 += b[i]
                if (total2 > total1) printf "%.1f", (1-(idle2-idle1)/(total2-total1))*100
                else print "0"
            }' 2>/dev/null || echo "0")
    fi
    echo "${cpu_val:-0}"
}

# 采集内存使用率
collect_memory() {
    local mem_val=""
    if command -v free &>/dev/null; then
        mem_val=$(free -m 2>/dev/null | awk '/Mem:/ {if($2>0) printf "%.1f", $3/$2*100; else print "0"}' || echo "")
    fi
    if [ -z "$mem_val" ] && [ -r /proc/meminfo ]; then
        local total avail
        total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
        avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$total" ] && [ "$total" -gt 0 ]; then
            mem_val=$(awk -v t="$total" -v a="$avail" 'BEGIN {printf "%.1f", (t-a)*100/t}' 2>/dev/null)
        fi
    fi
    echo "${mem_val:-0}"
}

# 采集磁盘使用率（根分区）
collect_disk() {
    local disk_val=""
    if command -v df &>/dev/null; then
        disk_val=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "")
    fi
    echo "${disk_val:-0}"
}

# 采集系统负载
collect_load() {
    local load_val=""
    if [ -r /proc/loadavg ]; then
        load_val=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null)
    elif command -v uptime &>/dev/null; then
        load_val=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs)
    fi
    echo "${load_val:-N/A}"
}

# 采集进程数
collect_processes() {
    local proc_count=""
    if [ -r /proc/stat ]; then
        proc_count=$(grep -c '^[^ ]' /proc/[0-9]*/stat 2>/dev/null || echo "0")
    elif command -v ps &>/dev/null; then
        proc_count=$(ps aux 2>/dev/null | wc -l)
    fi
    echo "${proc_count:-0}"
}

# ========== 阈值判断 ==========

check_threshold() {
    local metric="$1" value="$2" threshold="$3"
    local flag=""
    if command -v bc &>/dev/null; then
        flag=$(echo "$value > $threshold" | bc -l 2>/dev/null || echo "0")
    else
        flag=$(awk -v v="$value" -v t="$threshold" 'BEGIN {if(v>t) print "1"; else print "0"}' 2>/dev/null)
    fi
    echo "${flag:-0}"
}

colored_status() {
    local value="$1" threshold="$2"
    local exceeded
    exceeded=$(check_threshold "$value" "$value" "$threshold" 2>/dev/null; check_threshold "$value" "$threshold")
    # 分级着色
    if command -v bc &>/dev/null; then
        local margin
        margin=$(echo "$value - $threshold" | bc -l 2>/dev/null || echo "0")
        local margin_int="${margin%.*}"
        if [ "${margin_int:--100}" -gt 5 ]; then
            echo -e "${RED}${value}%${NC}"
        elif [ "${margin_int:--100}" -gt 0 ]; then
            echo -e "${YELLOW}${value}%${NC}"
        else
            echo -e "${GREEN}${value}%${NC}"
        fi
    else
        local vt="${value%.*}" tt="${threshold%.*}"
        if [ "$vt" -gt "$tt" ]; then
            echo -e "${RED}${value}%${NC}"
        else
            echo -e "${GREEN}${value}%${NC}"
        fi
    fi
}

# ========== 历史对比 ==========

save_history() {
    local cpu="$1" mem="$2" disk="$3"
    local hist_file="${HISTORY_DIR}/collect_$(date +%Y%m%d).log"
    echo "$(date '+%H:%M:%S') | CPU:${cpu}% | MEM:${mem}% | DISK:${disk}%" >> "$hist_file"
}

load_last_value() {
    local metric="$1"
    local hist_file="${HISTORY_DIR}/collect_$(date +%Y%m%d).log"
    if [ -f "$hist_file" ] && [ -s "$hist_file" ]; then
        case "$metric" in
            cpu)  grep -oP 'CPU:\K[0-9.]+' "$hist_file" | tail -1 ;;
            mem)  grep -oP 'MEM:\K[0-9.]+' "$hist_file" | tail -1 ;;
            disk) grep -oP 'DISK:\K[0-9.]+' "$hist_file" | tail -1 ;;
            *)    echo "0" ;;
        esac
    else
        echo "0"
    fi
}

# ========== 主采集流程 ==========

run_collection() {
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}    DiagMaster - 多进程并行性能采集${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo ""

    # 并行采集 CPU、内存、磁盘（单次采集，快速返回）
    local cpu_file="${DATA_DIR}/cpu.tmp"
    local mem_file="${DATA_DIR}/mem.tmp"
    local disk_file="${DATA_DIR}/disk.tmp"

    # 并行执行三项采集
    (collect_cpu > "$cpu_file" 2>/dev/null) &
    local pid1=$!
    (collect_memory > "$mem_file" 2>/dev/null) &
    local pid2=$!
    (collect_disk > "$disk_file" 2>/dev/null) &
    local pid3=$!

    # 等待所有采集完成，超时 10 秒
    local timeout=10
    for pid in $pid1 $pid2 $pid3; do
        local waited=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.1
            waited=$((waited + 1))
            if [ $waited -gt $((timeout * 10)) ]; then
                kill -9 "$pid" 2>/dev/null || true
                break
            fi
        done
    done

    local cpu_val mem_val disk_val
    cpu_val=$(cat "$cpu_file" 2>/dev/null || echo "0")
    mem_val=$(cat "$mem_file" 2>/dev/null || echo "0")
    disk_val=$(cat "$disk_file" 2>/dev/null || echo "0")

    # 采集负载与进程数（非关键，顺序执行）
    local load_val proc_count
    load_val=$(collect_load)
    proc_count=$(collect_processes)

    # ---------- 输出格式化结果 ----------
    echo "  ┌─────────────────────────────────────────────┐"
    printf "  │  CPU使用率:  %-30s │\n" "$(colored_status "$cpu_val" "$CPU_WARN")"
    printf "  │  内存使用:  %-30s │\n" "$(colored_status "$mem_val" "$MEM_WARN")"
    printf "  │  磁盘使用:  %-30s │\n" "$(colored_status "$disk_val" "$DISK_WARN")"
    echo "  ├─────────────────────────────────────────────┤"
    printf "  │  系统负载:  %-30s │\n" "$load_val"
    printf "  │  运行进程:  %-30s │\n" "$proc_count"
    echo "  └─────────────────────────────────────────────┘"
    echo ""

    # 写入数据文件供 diagmaster.sh 主脚本读取
    echo "$cpu_val" > "$cpu_file"
    echo "$mem_val" > "$mem_file"
    echo "$disk_val" > "$disk_file"

    # 保存历史记录
    save_history "$cpu_val" "$mem_val" "$disk_val"

    # 历史对比
    local prev_cpu prev_mem prev_disk
    prev_cpu=$(load_last_value "cpu" | tail -2 | head -1)
    prev_mem=$(load_last_value "mem" | tail -2 | head -1)
    prev_disk=$(load_last_value "disk" | tail -2 | head -1)

    if [ "$prev_cpu" != "0" ] && [ "$prev_cpu" != "$cpu_val" ]; then
        echo -e "  ${YELLOW}[趋势]${NC} CPU: ${prev_cpu}% → ${cpu_val}%"
    fi
    if [ "$prev_mem" != "0" ] && [ "$prev_mem" != "$mem_val" ]; then
        echo -e "  ${YELLOW}[趋势]${NC} 内存: ${prev_mem}% → ${mem_val}%"
    fi

    # 告警汇总
    local warnings=0
    if [ "$(check_threshold "cpu" "$cpu_val" "$CPU_WARN")" = "1" ]; then
        echo -e "  ${RED}⚠ CPU 使用率超过阈值 (${CPU_WARN}%)！${NC}"
        warnings=1
    fi
    if [ "$(check_threshold "mem" "$mem_val" "$MEM_WARN")" = "1" ]; then
        echo -e "  ${RED}⚠ 内存使用率超过阈值 (${MEM_WARN}%)！${NC}"
        warnings=1
    fi
    if [ "$(check_threshold "disk" "$disk_val" "$DISK_WARN")" = "1" ]; then
        echo -e "  ${RED}⚠ 磁盘使用率超过阈值 (${DISK_WARN}%)！${NC}"
        warnings=1
    fi

    if [ "$warnings" -eq 0 ]; then
        echo -e "  ${GREEN}✓ 所有指标均在正常范围内${NC}"
    fi

    echo ""
}

# 若直接执行本脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_collection
fi