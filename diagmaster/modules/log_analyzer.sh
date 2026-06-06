#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# DiagMaster - 内核日志清洗与安全审计模块 (v1.0)
# 功能：多源日志分析（dmesg, auth.log, syslog, kern.log）、
#        关键词过滤、异常统计、结构化报告生成
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
REPORT_DIR="${PROJECT_ROOT}/reports"
LOG_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$DATA_DIR" "$REPORT_DIR" "$LOG_DIR"

# 加载公共工具库
if [ -f "$SCRIPT_DIR/../lib/utils.sh" ]; then
    source "$SCRIPT_DIR/../lib/utils.sh"
fi

# 加载配置
OOM_WARN_THRESHOLD=${OOM_WARN_THRESHOLD:-5}
SSH_FAIL_WARN_THRESHOLD=${SSH_FAIL_WARN_THRESHOLD:-30}
MAX_LOG_LINES=${MAX_LOG_LINES:-10000}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== 日志源检测 ==========

# 检测可用的日志源
detect_log_sources() {
    local sources=()
    # 系统日志
    [ -f /var/log/syslog ] && sources+=("/var/log/syslog")
    [ -f /var/log/messages ] && sources+=("/var/log/messages")
    # 内核日志
    [ -r /var/log/kern.log ] && sources+=("/var/log/kern.log")
    [ -f /var/log/dmesg ] && sources+=("/var/log/dmesg")
    # 认证日志
    [ -f /var/log/auth.log ] && sources+=("/var/log/auth.log")
    [ -f /var/log/secure ] && sources+=("/var/log/secure")
    # 系统日记
    [ -f /var/log/journal ] && sources+=("/var/log/journal")
    
    printf '%s\n' "${sources[@]}"
}

# ========== 内核日志分析 ==========

# 分析 OOM (Out of Memory) 事件
analyze_oom() {
    local oom_total=0
    local oom_details=()
    local detail_file="${DATA_DIR}/oom_detail.tmp"
    > "$detail_file"

    # 方法1：dmesg 环形缓冲区
    if command -v dmesg &>/dev/null; then
        local dmesg_oom
        dmesg_oom=$(dmesg 2>/dev/null | grep -c -i "out of memory" || true)
        dmesg_oom=${dmesg_oom//[^0-9]/}
        oom_total=$((oom_total + ${dmesg_oom:-0}))
        
        # 提取最近的 OOM 详情
        if [ "${dmesg_oom:-0}" -gt 0 ]; then
            dmesg 2>/dev/null | grep -i "out of memory\|invoked oom-killer\|Killed process" | tail -20 >> "$detail_file" 2>/dev/null || true
        fi
    fi

    # 方法2：kern.log 文件
    if [ -f /var/log/kern.log ]; then
        local kern_oom
        kern_oom=$(grep -c -i "out of memory\|oom" /var/log/kern.log 2>/dev/null || true)
        kern_oom=${kern_oom//[^0-9]/}
        oom_total=$((oom_total + ${kern_oom:-0}))
        
        if [ "${kern_oom:-0}" -gt 0 ]; then
            grep -i "out of memory\|oom-killer" /var/log/kern.log 2>/dev/null | tail -20 >> "$detail_file" 2>/dev/null || true
        fi
    fi

    echo "$oom_total"
}

# 分析内核错误（panic、bug、segfault）
analyze_kernel_errors() {
    local error_count=0
    local error_patterns="panic|BUG:|Oops:|segfault|Call Trace"
    local error_file="${DATA_DIR}/kern_error.tmp"
    > "$error_file"

    # dmesg 中搜索
    if command -v dmesg &>/dev/null; then
        dmesg 2>/dev/null | grep -E -i "$error_patterns" >> "$error_file" 2>/dev/null || true
    fi
    # kern.log 中搜索
    if [ -f /var/log/kern.log ]; then
        grep -E -i "$error_patterns" /var/log/kern.log 2>/dev/null | tail -50 >> "$error_file" 2>/dev/null || true
    fi

    if [ -s "$error_file" ]; then
        error_count=$(wc -l < "$error_file")
    fi
    echo "$error_count"
}

# ========== 安全审计 ==========

# SSH 暴力破解检测
analyze_ssh_bruteforce() {
    local ssh_fail=0
    local ssh_success=0
    local top_ips_file="${DATA_DIR}/ssh_top_ips.tmp"
    > "$top_ips_file"

    local auth_logs=()
    [ -f /var/log/auth.log ] && auth_logs+=("/var/log/auth.log")
    [ -f /var/log/secure ] && auth_logs+=("/var/log/secure")

    for log in "${auth_logs[@]}"; do
        # 失败尝试
        local fails
        fails=$(grep -c "Failed password" "$log" 2>/dev/null || true)
        fails=${fails//[^0-9]/}
        ssh_fail=$((ssh_fail + ${fails:-0}))

        # 成功登录（排除系统用户）
        local successes
        successes=$(grep -c "Accepted password\|Accepted publickey" "$log" 2>/dev/null || true)
        successes=${successes//[^0-9]/}
        ssh_success=$((ssh_success + ${successes:-0}))

        # TOP 10 攻击来源 IP
        grep "Failed password" "$log" 2>/dev/null | \
            grep -oP 'from\s+\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            sort | uniq -c | sort -rn | head -10 >> "$top_ips_file" 2>/dev/null || true
    done

    echo "${ssh_fail}:${ssh_success}"
}

# 检测可疑的 sudo 使用
analyze_sudo_abuse() {
    local sudo_count=0
    local auth_logs=()
    [ -f /var/log/auth.log ] && auth_logs+=("/var/log/auth.log")
    [ -f /var/log/secure ] && auth_logs+=("/var/log/secure")

    for log in "${auth_logs[@]}"; do
        local failed_sudo
        failed_sudo=$(grep -c "sudo.*authentication failure\|sudo.*NOT in sudoers\|sudo.*command not allowed" "$log" 2>/dev/null || true)
        failed_sudo=${failed_sudo//[^0-9]/}
        sudo_count=$((sudo_count + ${failed_sudo:-0}))
    done
    echo "$sudo_count"
}

# ========== 系统日志清洗 ==========

# 系统错误统计
analyze_syslog_errors() {
    local error_count=0
    local error_file="${DATA_DIR}/syslog_error.tmp"
    > "$error_file"

    local syslog_sources=()
    [ -f /var/log/syslog ] && syslog_sources+=("/var/log/syslog")
    [ -f /var/log/messages ] && syslog_sources+=("/var/log/messages")

    for log in "${syslog_sources[@]}"; do
        # 提取 ERROR / CRITICAL / FAIL 级别日志
        grep -E -i "error|critical|fail|emerg|alert" "$log" 2>/dev/null | \
            tail -"$MAX_LOG_LINES" >> "$error_file" 2>/dev/null || true
    done

    if [ -s "$error_file" ]; then
        # 按类型分类统计
        error_count=$(wc -l < "$error_file")
    fi
    echo "$error_count"
}

# 系统重启记录
analyze_reboot_history() {
    local reboot_count=0
    if command -v last &>/dev/null; then
        reboot_count=$(last reboot 2>/dev/null | head -10 | wc -l || echo "0")
    fi
    if [ -f /var/log/syslog ]; then
        local syslog_reboot
        syslog_reboot=$(grep -c "Server listening\|systemd.*Started\|rsyslogd.*start" /var/log/syslog 2>/dev/null | head -1 || echo "0")
    fi
    echo "${reboot_count:-0}"
}

# ========== 报告生成 ==========

generate_report() {
    local report_file="$1"
    shift
    local oom_count="$1" kern_errors="$2" ssh_info="$3"
    local sudo_fail="$4" syslog_errors="$5" reboot_count="$6"
    
    local ssh_fail="${ssh_info%%:*}"
    local ssh_success="${ssh_info##*:}"

    local overall_status="正常"
    local issues=0

    [ "${oom_count:-0}" -gt "$OOM_WARN_THRESHOLD" ] && issues=$((issues+1))
    [ "${kern_errors:-0}" -gt 0 ] && issues=$((issues+1))
    [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && issues=$((issues+1))
    [ "${ssh_fail:-0}" -gt 0 ] && [ "${ssh_success:-0}" = "0" ] && issues=$((issues+1))
    [ "${sudo_fail:-0}" -gt 0 ] && issues=$((issues+1))
    [ $issues -gt 0 ] && overall_status="⚠ 存在安全隐患"

    cat << EOF > "$report_file"
# DiagMaster 日志清洗与安全审计报告
- **审计时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **主机名**: $(hostname)
- **整体评估**: $overall_status

---

## 一、内核健康检查

| 检查项 | 数值 | 阈值 | 状态 |
|--------|------|------|------|
| OOM 事件 | $oom_count | $OOM_WARN_THRESHOLD | $([ "${oom_count:-0}" -gt "$OOM_WARN_THRESHOLD" ] && echo "⚠ 异常" || echo "✅ 正常") |
| 内核错误 (panic/bug) | $kern_errors | >0 | $([ "${kern_errors:-0}" -gt 0 ] && echo "⚠ 异常" || echo "✅ 正常") |

### OOM 详情
\`\`\`
$(cat "${DATA_DIR}/oom_detail.tmp" 2>/dev/null || echo "无 OOM 事件记录")
\`\`\`

### 内核错误详情
\`\`\`
$(cat "${DATA_DIR}/kern_error.tmp" 2>/dev/null || echo "无内核错误记录")
\`\`\`

---

## 二、安全审计

| 检查项 | 数值 | 阈值 | 状态 |
|--------|------|------|------|
| SSH 失败尝试 | $ssh_fail | $SSH_FAIL_WARN_THRESHOLD | $([ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && echo "⚠ 暴力破解风险" || echo "✅ 正常") |
| SSH 成功登录 | $ssh_success | - | 信息 |
| sudo 异常使用 | $sudo_fail | >0 | $([ "${sudo_fail:-0}" -gt 0 ] && echo "⚠ 可疑行为" || echo "✅ 正常") |

### 攻击来源 IP TOP 10
\`\`\`
$(cat "${DATA_DIR}/ssh_top_ips.tmp" 2>/dev/null || echo "无攻击记录")
\`\`\`

---

## 三、系统日志摘要

| 检查项 | 数值 | 状态 |
|--------|------|------|
| 系统错误日志 | $syslog_errors | $([ "${syslog_errors:-0}" -gt 0 ] && echo "⚠ 存在错误" || echo "✅ 正常") |
| 近期重启次数 | $reboot_count | 信息 |

### 系统错误摘要（最近50条）
\`\`\`
$(head -50 "${DATA_DIR}/syslog_error.tmp" 2>/dev/null || echo "无错误记录")
\`\`\`

---

## 四、建议措施

EOF

    # 根据检查结果生成建议
    if [ "${oom_count:-0}" -gt "$OOM_WARN_THRESHOLD" ]; then
        echo "- 🔴 **OOM**: 内存不足，请考虑增加物理内存或优化应用内存使用" >> "$report_file"
    fi
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        echo "- 🔴 **SSH 暴力破解**: 建议修改 SSH 端口、启用 fail2ban、禁用密码登录改用密钥" >> "$report_file"
    fi
    if [ "${sudo_fail:-0}" -gt 0 ]; then
        echo "- 🟡 **sudo 异常**: 检查是否存在未授权 sudo 尝试" >> "$report_file"
    fi
    if [ "${kern_errors:-0}" -gt 0 ]; then
        echo "- 🟡 **内核错误**: 检查硬件状态和驱动版本" >> "$report_file"
    fi

    echo "" >> "$report_file"
    echo "---" >> "$report_file"
    echo "*报告由 DiagMaster 自动生成*" >> "$report_file"
}

# ========== 主审计流程 ==========

run_log_audit() {
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}    DiagMaster - 日志清洗与安全审计${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo ""

    echo -e "  ${YELLOW}[1/5]${NC} 检测可用日志源..."
    local sources
    sources=$(detect_log_sources)
    local source_count
    source_count=$(echo "$sources" | grep -c '/' 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✓ 发现 $source_count 个可用日志源${NC}"
    echo ""

    echo -e "  ${YELLOW}[2/5]${NC} 分析内核日志 (OOM / 错误)..."
    local oom_count kern_errors
    oom_count=$(analyze_oom)
    kern_errors=$(analyze_kernel_errors)
    echo -e "  ${GREEN}✓ OOM 事件: ${oom_count} 次 | 内核错误: ${kern_errors} 条${NC}"
    echo ""

    echo -e "  ${YELLOW}[3/5]${NC} 审计 SSH 安全..."
    local ssh_info
    ssh_info=$(analyze_ssh_bruteforce)
    local ssh_fail="${ssh_info%%:*}"
    local ssh_success="${ssh_info##*:}"
    local sudo_fail
    sudo_fail=$(analyze_sudo_abuse)
    echo -e "  ${GREEN}✓ SSH 失败: ${ssh_fail} 次 | SSH 成功: ${ssh_success} 次 | sudo异常: ${sudo_fail} 次${NC}"
    echo ""

    echo -e "  ${YELLOW}[4/5]${NC} 清洗系统日志..."
    local syslog_errors reboot_count
    syslog_errors=$(analyze_syslog_errors)
    reboot_count=$(analyze_reboot_history)
    echo -e "  ${GREEN}✓ 系统错误: ${syslog_errors} 条 | 近期重启: ${reboot_count} 次${NC}"
    echo ""

    echo -e "  ${YELLOW}[5/5]${NC} 生成审计报告..."
    local report_path="${REPORT_DIR}/diag_report_$(date +%Y%m%d_%H%M%S).md"
    generate_report "$report_path" "$oom_count" "$kern_errors" "$ssh_info" \
        "$sudo_fail" "$syslog_errors" "$reboot_count"
    echo ""

    # 输出数据文件供主脚本读取
    echo "$oom_count" > "${DATA_DIR}/oom_count.tmp"
    echo "$ssh_fail" > "${DATA_DIR}/ssh_fail.tmp"

    # 输出汇总
    echo -e "${CYAN}=== 审计汇总 ===${NC}"
    echo -e "  OOM 事件:  ${oom_count} 次"
    echo -e "  SSH 爆破:  ${ssh_fail} 次"
    echo -e "  内核错误:  ${kern_errors} 条"
    echo -e "  系统错误:  ${syslog_errors} 条"
    echo -e "  ${GREEN}✓ 报告已生成: $report_path${NC}"
    echo ""
}

# 若直接执行本脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_log_audit
fi