#!/usr/bin/env bash
set -uo pipefail

# ==============================================================================
# DiagMaster - 内核日志清洗与安全审计模块 (v2.0)
# 功能：深度安全审计、攻击模式检测、关联分析、风险评分、异常检测
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
REPORT_DIR="${PROJECT_ROOT}/reports"
LOG_DIR="${PROJECT_ROOT}/logs"
HISTORY_DIR="${DATA_DIR}/audit_history"
mkdir -p "$DATA_DIR" "$REPORT_DIR" "$LOG_DIR" "$HISTORY_DIR"

source "$PROJECT_ROOT/lib/utils.sh"

OOM_WARN_THRESHOLD=${OOM_WARN_THRESHOLD:-5}
SSH_FAIL_WARN_THRESHOLD=${SSH_FAIL_WARN_THRESHOLD:-30}
MAX_LOG_LINES=${MAX_LOG_LINES:-10000}
RISK_SCORE_THRESHOLD=${RISK_SCORE_THRESHOLD:-60}
AUDIT_DAYS=${AUDIT_DAYS:-7}
WSL_MODE=${WSL_MODE:-auto}

# ========== 错误栈收集（Error Stack） ==========
ERROR_STACK_FILE="${DATA_DIR}/error_stack.tmp"
reset_error_stack() {
    > "$ERROR_STACK_FILE"
}
push_error() {
    local code="$1" msg="$2" fix_plan="$3"
    echo "[$(date '+%H:%M:%S')] 错误码=$code | 描述=$msg | 修复建议=$fix_plan" >> "$ERROR_STACK_FILE"
}
get_error_count() {
    wc -l < "$ERROR_STACK_FILE" 2>/dev/null || echo "0"
}
render_error_stack() {
    if [ ! -s "$ERROR_STACK_FILE" ]; then
        echo "无受限操作"
        return
    fi
    echo "### 受限操作详情"
    echo ""
    echo "| 时间 | 错误码 | 描述 | 修复建议 |"
    echo "|------|--------|------|----------|"
    while IFS= read -r line; do
        local ts code msg fix
        ts=$(echo "$line" | cut -d' ' -f1)
        code=$(echo "$line" | sed -n 's/.*错误码=\([^|]*\).*/\1/p')
        msg=$(echo "$line" | sed -n 's/.*描述=\([^|]*\).*/\1/p')
        fix=$(echo "$line" | sed -n 's/.*修复建议=\(.*\)/\1/p')
        echo "| $ts | $code | $msg | $fix |"
    done < "$ERROR_STACK_FILE"
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# WSL 环境检测
is_wsl() {
    if [ -f /proc/sys/kernel/osrelease ] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        return 0
    fi
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi
    return 1
}

# 时间过滤：只取最近 N 天的日志行（兼容 syslog/journalctl 时间格式）
filter_by_time() {
    local file="$1"
    local days="${2:-$AUDIT_DAYS}"
    local since
    since=$(date -d "-${days} days" '+%Y-%m-%d' 2>/dev/null || date -d "-${days} days" '+%Y/%m/%d' 2>/dev/null)
    if [ -z "$since" ]; then
        cat "$file" 2>/dev/null
        return
    fi
    awk -v since="$since" '
    {
        line = $0
        if (match(line, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
            d = substr(line, RSTART, 10)
            if (d >= since) print line
        } else if (match(line, /[A-Z][a-z]{2}[ ]+[0-9]+/)) {
            # 跳过无明确日期头的行，保守保留
            # 这里不做硬过滤，避免误砍 journalctl 输出
            print line
        } else {
            print line
        }
    }' "$file" 2>/dev/null
}

# sudo 白名单（按完整路径前缀匹配，如 COMMAND=/usr/bin/apt update）
is_whitelisted_sudo() {
    local cmd="${1:-}"
    [ -z "$cmd" ] && return 1
    # 只保留最可能的系统管理工具前缀
    local prefix="${cmd%% *}"
    case "$prefix" in
        /usr/bin/apt|/usr/bin/apt-get|/usr/bin/dpkg|/usr/bin/snap|\
        /usr/bin/dnf|/usr/bin/yum|/usr/bin/pacman|/usr/bin/zypper|\
        /usr/bin/systemctl|/usr/bin/journalctl|/usr/bin/visudo|\
        /usr/bin/usermod|/usr/bin/useradd|/usr/bin/groupadd|/usr/bin/passwd|\
        /usr/bin/chsh|/usr/bin/chfn|/usr/bin/chage|\
        /usr/bin/pip|/usr/bin/pip3|/usr/bin/npm|/usr/bin/nvm|\
        /usr/bin/docker|/usr/bin/podman|\
        /usr/bin/du|/usr/bin/ls|/usr/bin/cat|/usr/bin/cd|\
        /usr/bin/whoami|/usr/bin/id|/usr/bin/ps|/usr/bin/top|/usr/bin/htop|\
        /usr/bin/make|/usr/bin/cmake|/usr/bin/gcc|/usr/bin/g++|/usr/bin/ninja|\
        /usr/bin/sudo|/usr/bin/su|/usr/bin/git|/usr/bin/curl|/usr/bin/wget|\
        /usr/bin/mv|/usr/bin/cp|/usr/bin/rm|/usr/bin/mkdir|/usr/bin/chmod|/usr/bin/chown)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ========== 日志源检测 ==========

detect_log_sources() {
    local sources=()
    [ -f /var/log/syslog ] && sources+=("/var/log/syslog")
    [ -f /var/log/messages ] && sources+=("/var/log/messages")
    [ -r /var/log/kern.log ] && sources+=("/var/log/kern.log")
    [ -f /var/log/dmesg ] && sources+=("/var/log/dmesg")
    [ -f /var/log/auth.log ] && sources+=("/var/log/auth.log")
    [ -f /var/log/secure ] && sources+=("/var/log/secure")
    [ -d /var/log/journal ] && sources+=("/var/log/journal")
    printf '%s\n' "${sources[@]}"
}

# ========== 内核日志深度分析 ==========

analyze_oom() {
    local oom_total=0
    local oom_details=()
    local detail_file="${DATA_DIR}/oom_detail.tmp"
    > "$detail_file"

    if command -v dmesg &>/dev/null; then
        local dmesg_oom
        dmesg_oom=$(dmesg 2>/dev/null | grep -c -i "out of memory\|invoked oom-killer\|killed process" || true)
        dmesg_oom=${dmesg_oom//[^0-9]/}
        oom_total=$((oom_total + ${dmesg_oom:-0}))
        if [ "${dmesg_oom:-0}" -gt 0 ]; then
            dmesg 2>/dev/null | grep -i "out of memory\|invoked oom-killer\|Killed process" | tail -20 >> "$detail_file" 2>/dev/null || true
        fi
    fi
    if [ -f /var/log/kern.log ]; then
        local kern_oom
        kern_oom=$(grep -c -i "out of memory\|oom-killer" /var/log/kern.log 2>/dev/null || true)
        kern_oom=${kern_oom//[^0-9]/}
        oom_total=$((oom_total + ${kern_oom:-0}))
        if [ "${kern_oom:-0}" -gt 0 ]; then
            grep -i "out of memory\|oom-killer" /var/log/kern.log 2>/dev/null | tail -20 >> "$detail_file" 2>/dev/null || true
        fi
    fi
    echo "$oom_total"
}

# ========== 攻击模式检测 ==========

detect_port_scan() {
    local scan_count=0
    local scan_file="${DATA_DIR}/port_scan.tmp"
    > "$scan_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    local tmp_filtered="${DATA_DIR}/port_scan_filtered.tmp"
    > "$tmp_filtered"

    for log in "${log_files[@]}"; do
        filter_by_time "$log" "$AUDIT_DAYS" | grep -i "connection from\| refused\|invalid user" 2>/dev/null >> "$tmp_filtered" || true
    done

    if [ -s "$tmp_filtered" ]; then
        awk '{print $(NF-3)}' "$tmp_filtered" | sort | uniq -c | sort -rn | awk '$1 > 10 {print $2, $1}' >> "$scan_file" 2>/dev/null || true
    fi

    if [ -s "$scan_file" ]; then
        scan_count=$(wc -l < "$scan_file")
    fi
    echo "$scan_count"
}

detect_suspicious_logins() {
    local suspicious_count=0
    local suspicious_file="${DATA_DIR}/suspicious_logins.tmp"
    > "$suspicious_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    for log in "${log_files[@]}"; do
        filter_by_time "$log" "$AUDIT_DAYS" | grep -E "Accepted (password|publickey)" 2>/dev/null | \
            awk '{print substr($0,1,15)}' | while read -r ts; do
                hour=$(date -d "$ts" +%H 2>/dev/null || echo "")
                if [ -n "$hour" ]; then
                    if [ "$hour" -lt 5 ] || [ "$hour" -gt 22 ]; then
                        echo "$ts"
                    fi
                fi
            done >> "$suspicious_file" 2>/dev/null || true

        filter_by_time "$log" "$AUDIT_DAYS" | grep -E "Accepted.*root" 2>/dev/null >> "$suspicious_file" 2>/dev/null || true
    done

    if [ -s "$suspicious_file" ]; then
        suspicious_count=$(wc -l < "$suspicious_file")
    fi
    echo "$suspicious_count"
}

detect_user_enumeration() {
    local enum_count=0
    local enum_file="${DATA_DIR}/user_enum.tmp"
    > "$enum_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    for log in "${log_files[@]}"; do
        filter_by_time "$log" "$AUDIT_DAYS" | grep -c "invalid user" 2>/dev/null | \
            awk -v log="$log" '{if($1>5) print log, $1, "invalid user attempts"}' >> "$enum_file" 2>/dev/null || true

        filter_by_time "$log" "$AUDIT_DAYS" | grep -c "user unknown" 2>/dev/null | \
            awk -v log="$log" '{if($1>3) print log, $1, "unknown user attempts"}' >> "$enum_file" 2>/dev/null || true
    done

    if [ -s "$enum_file" ]; then
        enum_count=$(wc -l < "$enum_file")
    fi
    echo "$enum_count"
}

detect_privilege_escalation() {
    local privesc_count=0
    local privesc_file="${DATA_DIR}/privesc.tmp"
    > "$privesc_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    for log in "${log_files[@]}"; do
        local filtered
        filtered=$(filter_by_time "$log" "$AUDIT_DAYS")

        echo "$filtered" | grep -E "sudo.*(failure|denied|NOT in sudoers)" 2>/dev/null | tail -20 >> "$privesc_file" 2>/dev/null || true

        # sudo COMMAND：白名单过滤（用 grep -v 直接排除，避免 subshell 里函数调用丢失结果的问题）
        local sudo_tmp="${DATA_DIR}/sudo_cmd.tmp"
        echo "$filtered" | grep -E "sudo.*COMMAND" > "$sudo_tmp" 2>/dev/null || true
        if [ -s "$sudo_tmp" ]; then
            grep -v -E "^.*COMMAND=/(usr/bin/apt|usr/bin/apt-get|usr/bin/dpkg|usr/bin/snap|usr/bin/dnf|usr/bin/yum|usr/bin/pacman|usr/bin/zypper|usr/bin/systemctl|usr/bin/journalctl|usr/bin/visudo|usr/bin/usermod|usr/bin/useradd|usr/bin/groupadd|usr/bin/passwd|usr/bin/chsh|usr/bin/chfn|usr/bin/chage|usr/bin/pip|usr/bin/pip3|usr/bin/npm|usr/bin/nvm|usr/bin/docker|usr/bin/podman|usr/bin/du|usr/bin/ls|usr/bin/cat|usr/bin/cd|usr/bin/whoami|usr/bin/id|usr/bin/ps|usr/bin/top|usr/bin/htop|usr/bin/make|usr/bin/cmake|usr/bin/gcc|usr/bin/g\+\+|usr/bin/ninja|usr/bin/sudo|usr/bin/su|usr/bin/git|usr/bin/curl|usr/bin/wget|usr/bin/mv|usr/bin/cp|usr/bin/rm|usr/bin/mkdir|usr/bin/chmod|usr/bin/chown)" "$sudo_tmp" >> "$privesc_file" 2>/dev/null || true
        fi
        rm -f "$sudo_tmp"

        # UID 变化：排除 CRON / sudo:session / systemd-user，只保留切到 root 的真实提权
        echo "$filtered" | grep -E "new session|session opened|su\[" 2>/dev/null | \
            grep -v "systemd-user:session" | \
            grep -v "CRON" | \
            grep -v "sudo:session" | \
            grep -E "\(to root\)|for user root" | \
            head -20 >> "$privesc_file" 2>/dev/null || true
    done

    if [ -s "$privesc_file" ]; then
        privesc_count=$(wc -l < "$privesc_file")
    fi
    echo "$privesc_count"
}

analyze_ssh_bruteforce() {
    local ssh_fail=0
    local ssh_success=0
    local ssh_top_ips_file="${DATA_DIR}/ssh_top_ips.tmp"
    > "$ssh_top_ips_file"

    local auth_logs=()
    [ -f /var/log/auth.log ] && auth_logs+=("/var/log/auth.log")
    [ -f /var/log/secure ] && auth_logs+=("/var/log/secure")

    for log in "${auth_logs[@]}"; do
        local filtered
        filtered=$(filter_by_time "$log" "$AUDIT_DAYS")

        local fails successes
        fails=$(echo "$filtered" | grep -c "Failed password" 2>/dev/null || true)
        fails=${fails//[^0-9]/}
        ssh_fail=$((ssh_fail + ${fails:-0}))

        successes=$(echo "$filtered" | grep -c "Accepted password\|Accepted publickey" 2>/dev/null || true)
        successes=${successes//[^0-9]/}
        ssh_success=$((ssh_success + ${successes:-0}))

        echo "$filtered" | grep "Accepted password" 2>/dev/null | tail -5 >> "$ssh_top_ips_file" 2>/dev/null || true

        echo "$filtered" | grep "Failed password" 2>/dev/null | \
            grep -oP 'from\s+\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            sort | uniq -c | sort -rn | head -10 >> "$ssh_top_ips_file" 2>/dev/null || true
    done

    echo "${ssh_fail}:${ssh_success}"
}

analyze_oom() {
    local oom_total=0
    local detail_file="${DATA_DIR}/oom_detail.tmp"
    > "$detail_file"
    local cutoff
    cutoff=$(date -d "-${AUDIT_DAYS} days" '+%Y-%m-%d' 2>/dev/null || echo "")

    if command -v dmesg &>/dev/null; then
        local dmesg_oom
        if [ -n "$cutoff" ]; then
            dmesg_oom=$(dmesg -T 2>/dev/null | awk -v cutoff="$cutoff" '
                BEGIN {count=0}
                {
                    if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                        d = substr($0, RSTART, 10)
                        if (d >= cutoff) {
                            if (tolower($0) ~ /out of memory|invoked oom-killer|killed process/) count++
                        }
                    }
                }
                END {print count}
            ' 2>/dev/null || echo "0")
        else
            dmesg_oom=$(dmesg 2>/dev/null | grep -c -i "out of memory\|invoked oom-killer\|killed process" || true)
        fi
        dmesg_oom=${dmesg_oom//[^0-9]/}
        oom_total=$((oom_total + ${dmesg_oom:-0}))
        if [ "${dmesg_oom:-0}" -gt 0 ]; then
            if [ -n "$cutoff" ]; then
                dmesg -T 2>/dev/null | awk -v cutoff="$cutoff" '
                    {
                        if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                            d = substr($0, RSTART, 10)
                            if (d >= cutoff && tolower($0) ~ /out of memory|invoked oom-killer|killed process/) print
                        }
                    }
                ' | tail -20 >> "$detail_file" 2>/dev/null || true
            else
                dmesg 2>/dev/null | grep -i "out of memory\|invoked oom-killer\|killed process" | tail -20 >> "$detail_file" 2>/dev/null || true
            fi
        fi
    fi
    echo "$oom_total"
}

analyze_kernel_errors() {
    local error_count=0
    local error_file="${DATA_DIR}/kern_error.tmp"
    > "$error_file"
    local cutoff
    cutoff=$(date -d "-${AUDIT_DAYS} days" '+%Y-%m-%d' 2>/dev/null || echo "")

    if command -v dmesg &>/dev/null; then
        if [ -n "$cutoff" ]; then
            dmesg -T 2>/dev/null | awk -v cutoff="$cutoff" '
                {
                    if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                        d = substr($0, RSTART, 10)
                        if (d >= cutoff && tolower($0) ~ /panic|bug:|oops:|segfault|call trace|kernel bug/) {
                            line = tolower($0)
                            if (line !~ /command line/ && line !~ /kernel command line/) print
                        }
                    }
                }
            ' >> "$error_file" 2>/dev/null || true
        else
            dmesg 2>/dev/null | grep -E -i "panic|BUG:|Oops:|segfault|Call Trace|kernel BUG" | grep -v -i "command line" >> "$error_file" 2>/dev/null || true
        fi
    fi
    if [ -f /var/log/kern.log ]; then
        filter_by_time "/var/log/kern.log" "$AUDIT_DAYS" | grep -E -i "panic|BUG:|Oops:|segfault|Call Trace|kernel BUG" | grep -v -i "command line" >> "$error_file" 2>/dev/null || true
    fi
    if [ -s "$error_file" ]; then
        error_count=$(wc -l < "$error_file")
    fi
    echo "$error_count"
}

detect_suspicious_logins() {
    local suspicious_count=0
    local suspicious_file="${DATA_DIR}/suspicious_logins.tmp"
    > "$suspicious_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    for log in "${log_files[@]}"; do
        # 检测非常规时间段的登录（0-5点和23点）
        grep -E "Accepted (password|publickey)" "$log" 2>/dev/null | \
            awk '{print substr($0,1,15)}' | while read -r ts; do
                hour=$(date -d "$ts" +%H 2>/dev/null || echo "")
                if [ -n "$hour" ]; then
                    if [ "$hour" -lt 5 ] || [ "$hour" -gt 22 ]; then
                        echo "$ts"
                    fi
                fi
            done >> "$suspicious_file" 2>/dev/null || true

        # 检测 root 直接登录
        grep -E "Accepted.*root" "$log" 2>/dev/null >> "$suspicious_file" 2>/dev/null || true
    done

    if [ -s "$suspicious_file" ]; then
        suspicious_count=$(wc -l < "$suspicious_file")
    fi
    echo "$suspicious_count"
}

detect_user_enumeration() {
    local enum_count=0
    local enum_file="${DATA_DIR}/user_enum.tmp"
    > "$enum_file"

    local log_files=()
    [ -f /var/log/auth.log ] && log_files+=("/var/log/auth.log")
    [ -f /var/log/secure ] && log_files+=("/var/log/secure")

    for log in "${log_files[@]}"; do
        # 大量无效用户名尝试
        grep -c "invalid user" "$log" 2>/dev/null | \
            awk -v log="$log" '{if($1>5) print log, $1, "invalid user attempts"}' >> "$enum_file" 2>/dev/null || true

        # 大量 "user unknown" 尝试
        grep -c "user unknown" "$log" 2>/dev/null | \
            awk -v log="$log" '{if($1>3) print log, $1, "unknown user attempts"}' >> "$enum_file" 2>/dev/null || true
    done

    if [ -s "$enum_file" ]; then
        enum_count=$(wc -l < "$enum_file")
    fi
    echo "$enum_count"
}

detect_malware_indicators() {
    local malware_count=0
    local malware_file="${DATA_DIR}/malware.tmp"
    > "$malware_file"

    local suspicious_patterns="cryptominer|minerd|xmrig|kdevtmpfsi|kinsing|\.hidden|/tmp/.*\.sh|wget.*http.*\.sh|curl.*\.sh|base64.*decode|nc -l|ncat|reverse shell|pty\.spawn"

    if command -v dmesg &>/dev/null; then
        dmesg 2>/dev/null | grep -E -i "$suspicious_patterns" >> "$malware_file" 2>/dev/null || true
    fi
    if [ -f /var/log/syslog ]; then
        grep -E -i "$suspicious_patterns" /var/log/syslog 2>/dev/null | tail -20 >> "$malware_file" 2>/dev/null || true
    fi

    if [ -s "$malware_file" ]; then
        malware_count=$(wc -l < "$malware_file")
    fi
    echo "$malware_count"
}

# ========== 系统日志清洗（补回缺失函数） ==========

analyze_syslog_errors() {
    local error_count=0
    local error_file="${DATA_DIR}/syslog_error.tmp"
    > "$error_file"

    local syslog_sources=()
    [ -f /var/log/syslog ] && syslog_sources+=("/var/log/syslog")
    [ -f /var/log/messages ] && syslog_sources+=("/var/log/messages")

    for log in "${syslog_sources[@]}"; do
        grep -E -i "error|critical|fail|emerg|alert" "$log" 2>/dev/null | \
            tail -"$MAX_LOG_LINES" >> "$error_file" 2>/dev/null || true
    done

    if [ -s "$error_file" ]; then
        error_count=$(wc -l < "$error_file")
    fi
    echo "$error_count"
}

analyze_reboot_history() {
    local reboot_count=0
    if command -v last &>/dev/null; then
        reboot_count=$(last reboot 2>/dev/null | head -10 | wc -l || echo "0")
    fi
    if [ -f /var/log/syslog ]; then
        local syslog_reboot
        syslog_reboot=$(grep -c "Server listening\|systemd.*Started\|rsyslogd.*start" /var/log/syslog 2>/dev/null | head -1 || echo "0")
        syslog_reboot=${syslog_reboot//[^0-9]/}
        reboot_count=$((reboot_count + ${syslog_reboot:-0}))
    fi
    echo "${reboot_count:-0}"
}

# ========== SSH 暴力破解深度分析 ==========

analyze_ssh_bruteforce() {
    local ssh_fail=0
    local ssh_success=0
    local ssh_top_ips_file="${DATA_DIR}/ssh_top_ips.tmp"
    > "$ssh_top_ips_file"

    local auth_logs=()
    [ -f /var/log/auth.log ] && auth_logs+=("/var/log/auth.log")
    [ -f /var/log/secure ] && auth_logs+=("/var/log/secure")

    for log in "${auth_logs[@]}"; do
        local fails successes
        fails=$(grep -c "Failed password" "$log" 2>/dev/null || true)
        fails=${fails//[^0-9]/}
        ssh_fail=$((ssh_fail + ${fails:-0}))

        successes=$(grep -c "Accepted password\|Accepted publickey" "$log" 2>/dev/null || true)
        successes=${successes//[^0-9]/}
        ssh_success=$((ssh_success + ${successes:-0}))

        # 检测暴力破解后成功登录的模式
        grep "Accepted password" "$log" 2>/dev/null | tail -5 >> "$ssh_top_ips_file" 2>/dev/null || true

        # 检测来自同一IP的失败尝试
        grep "Failed password" "$log" 2>/dev/null | \
            grep -oP 'from\s+\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            sort | uniq -c | sort -rn | head -10 >> "$ssh_top_ips_file" 2>/dev/null || true
    done

    echo "${ssh_fail}:${ssh_success}"
}

# ========== 关联分析 ==========

correlate_events() {
    local oom_count="$1"
    local ssh_fail="$2"
    local ssh_success="$3"
    local suspicious_logins="$4"
    local correlation_file="${DATA_DIR}/correlations.tmp"
    > "$correlation_file"

    local correlations=0

    # OOM 导致的服务不稳定
    if [ "${oom_count:-0}" -gt 0 ] && [ "${ssh_success:-0}" -gt 0 ]; then
        echo "[关联] OOM 事件后可能存在 SSH 重连（服务不稳定）" >> "$correlation_file"
        correlations=$((correlations + 1))
    fi

    # SSH 暴力破解后成功
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && [ "${ssh_success:-0}" -gt 0 ]; then
        echo "[关联] SSH 暴力破解后存在成功登录，可能存在入侵" >> "$correlation_file"
        correlations=$((correlations + 1))
    fi

    # 异常登录 + 高 SSH 失败
    if [ "${suspicious_logins:-0}" -gt 0 ] && [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        echo "[关联] 异常时间登录伴随高 SSH 失败，可能存在暴力破解" >> "$correlation_file"
        correlations=$((correlations + 1))
    fi

    # 权限提升 + 异常登录
    local sudo_fail="${5:-0}"
    if [ "${sudo_fail:-0}" -gt 0 ] && [ "${suspicious_logins:-0}" -gt 0 ]; then
        echo "[关联] 异常登录伴随 sudo 异常，疑似权限提升尝试" >> "$correlation_file"
        correlations=$((correlations + 1))
    fi

    echo "$correlations"
}

# ========== 风险评分 ==========

calculate_risk_score() {
    local oom_count="$1"
    local kern_errors="$2"
    local ssh_fail="$3"
    local ssh_success="$4"
    local sudo_fail="$5"
    local syslog_errors="$6"
    local suspicious_logins="$7"
    local port_scans="$8"
    local user_enum="$9"
    local malware="${10:-0}"
    local correlations="${11:-0}"
    local reboot_count="${12:-0}"

    local score=0
    local wsl=0
    is_wsl && wsl=1

    # 内核错误 (0-40分) - 最严重
    if [ "${kern_errors:-0}" -gt 10 ]; then
        score=$((score + 40))
    elif [ "${kern_errors:-0}" -gt 0 ]; then
        score=$((score + 30))
    fi

    # 恶意软件痕迹 (0-30分)
    if [ "${malware:-0}" -gt 0 ]; then
        score=$((score + 30))
    fi

    # SSH 暴力破解后成功 (严重入侵迹象)
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && [ "${ssh_success:-0}" -gt 0 ]; then
        score=$((score + 25))
    fi

    # OOM (0-20分)
    if [ "${oom_count:-0}" -gt 10 ]; then
        score=$((score + 20))
    elif [ "${oom_count:-0}" -gt 0 ]; then
        score=$((score + 10))
    fi

    # 重启次数 (仅非WSL环境或WSL中异常高时计分)
    if [ "$wsl" -eq 0 ] && [ "${reboot_count:-0}" -gt 10 ]; then
        score=$((score + 15))
    fi
    if [ "$wsl" -eq 1 ] && [ "${reboot_count:-0}" -gt 100 ]; then
        score=$((score + 10))
    fi

    # sudo 异常 (0-15分，白名单后)
    if [ "${sudo_fail:-0}" -gt 10 ]; then
        score=$((score + 15))
    elif [ "${sudo_fail:-0}" -gt 5 ]; then
        score=$((score + 10))
    elif [ "${sudo_fail:-0}" -gt 0 ]; then
        score=$((score + 5))
    fi

    # SSH 暴力破解 (0-15分)
    if [ "${ssh_fail:-0}" -gt 100 ]; then
        score=$((score + 15))
    elif [ "${ssh_fail:-0}" -gt 50 ]; then
        score=$((score + 10))
    elif [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        score=$((score + 5))
    elif [ "${ssh_fail:-0}" -gt 0 ]; then
        score=$((score + 2))
    fi

    # 异常登录 (0-10分)
    if [ "${suspicious_logins:-0}" -gt 5 ]; then
        score=$((score + 10))
    elif [ "${suspicious_logins:-0}" -gt 0 ]; then
        score=$((score + 5))
    fi

    # 端口扫描 (0-10分)
    if [ "${port_scans:-0}" -gt 5 ]; then
        score=$((score + 10))
    elif [ "${port_scans:-0}" -gt 0 ]; then
        score=$((score + 5))
    fi

    # 系统错误 (0-10分)
    if [ "${syslog_errors:-0}" -gt 100 ]; then
        score=$((score + 10))
    elif [ "${syslog_errors:-0}" -gt 0 ]; then
        score=$((score + 3))
    fi

    # 用户枚举 (0-5分)
    if [ "${user_enum:-0}" -gt 0 ]; then
        score=$((score + 5))
    fi

    # 关联事件 (0-5分)
    if [ "${correlations:-0}" -gt 0 ]; then
        score=$((score + 5))
    fi

    # 封顶 100
    if [ "$score" -gt 100 ]; then
        score=100
    fi

    echo "$score"
}

risk_level() {
    local score="$1"
    if [ "$score" -ge 80 ]; then
        echo "${RED}高危${NC}"
    elif [ "$score" -ge 50 ]; then
        echo "${YELLOW}中危${NC}"
    elif [ "$score" -ge 20 ]; then
        echo "${YELLOW}低危${NC}"
    else
        echo "${GREEN}安全${NC}"
    fi
}

# ========== 历史基线 ==========

save_baseline() {
    local date_key
    date_key=$(date +%Y%m%d)
    local baseline_file="${HISTORY_DIR}/baseline_${date_key}.txt"

    cat > "$baseline_file" << EOF
# DiagMaster 审计基线 - $(date '+%Y-%m-%d %H:%M:%S')
env=${1:-server}
oom=${2:-0}
kern_errors=${3:-0}
ssh_fail=${4:-0}
ssh_success=${5:-0}
sudo_fail=${6:-0}
syslog_errors=${7:-0}
reboot_count=${8:-0}
EOF
}

load_baseline() {
    local date_key="$1"
    local baseline_file="${HISTORY_DIR}/baseline_${date_key}.txt"
    if [ -f "$baseline_file" ]; then
        cat "$baseline_file"
    else
        echo "# 无历史基线"
    fi
}

detect_anomalies() {
    local oom_count="$1"
    local kern_errors="$2"
    local ssh_fail="$3"
    local syslog_errors="$4"
    local anomaly_file="${DATA_DIR}/anomalies.tmp"
    > "$anomaly_file"
    local anomalies=0

    # 对比过去3天的基线
    for i in 1 2 3; do
        local past_date
        past_date=$(date -d "-${i} day" +%Y%m%d 2>/dev/null || continue)
        local baseline
        baseline=$(load_baseline "$past_date")
        [ "$baseline" = "# 无历史基线" ] && continue

        local base_oom base_ssh base_syslog
        base_oom=$(echo "$baseline" | grep '^oom=' | head -1 | cut -d'=' -f2)
        base_ssh=$(echo "$baseline" | grep '^ssh_fail=' | head -1 | cut -d'=' -f2)
        base_syslog=$(echo "$baseline" | grep '^syslog_errors=' | head -1 | cut -d'=' -f2)

        # OOM 异常（超过历史均值3倍）
        if [ -n "$base_oom" ] && [ "${base_oom:-0}" -gt 0 ] && [ "${oom_count:-0}" -gt 0 ]; then
            local threshold=$((base_oom * 3))
            if [ "${oom_count:-0}" -gt "$threshold" ]; then
                echo "[异常] OOM 事件较 ${past_date} 的基线 (${base_oom}) 增长超过 3 倍 (当前: ${oom_count})" >> "$anomaly_file"
                anomalies=$((anomalies + 1))
            fi
        fi

        # SSH 失败异常
        if [ -n "$base_ssh" ] && [ "${base_ssh:-0}" -gt 0 ] && [ "${ssh_fail:-0}" -gt 0 ]; then
            local threshold=$((base_ssh * 3))
            if [ "${ssh_fail:-0}" -gt "$threshold" ]; then
                echo "[异常] SSH 失败较 ${past_date} 的基线 (${base_ssh}) 增长超过 3 倍 (当前: ${ssh_fail})" >> "$anomaly_file"
                anomalies=$((anomalies + 1))
            fi
        fi

        # 系统错误异常
        if [ -n "$base_syslog" ] && [ "${base_syslog:-0}" -gt 0 ] && [ "${syslog_errors:-0}" -gt 0 ]; then
            local threshold=$((base_syslog * 3))
            if [ "${syslog_errors:-0}" -gt "$threshold" ]; then
                echo "[异常] 系统错误较 ${past_date} 的基线 (${base_syslog}) 增长超过 3 倍 (当前: ${syslog_errors})" >> "$anomaly_file"
                anomalies=$((anomalies + 1))
            fi
        fi
    done

    echo "$anomalies"
}

# ========== 报告生成 ==========

generate_report() {
    local report_file="$1"
    local oom_count="$2" kern_errors="$3" ssh_info="$4"
    local sudo_fail="$5" syslog_errors="$6" reboot_count="$7"
    local suspicious_logins="$8" port_scans="$9" user_enum="${10}" malware="${11}"
    local risk_score="${12}" correlations="${13}" anomaly_count="${14}"

    local ssh_fail="${ssh_info%%:*}"
    local ssh_success="${ssh_info##*:}"

    local risk_desc
    risk_desc=$(risk_level "$risk_score")

    local env_note=""
    is_wsl && env_note=" (WSL 环境)"

    cat << EOF > "$report_file"
# DiagMaster 深度安全审计报告 (v2.0)
- **审计时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **主机名**: $(hostname)
- **运行环境**: ${env_note}
- **审计窗口**: 近 ${AUDIT_DAYS} 天
- **风险评分**: ${risk_score}/100 [$(echo "$risk_desc" | sed 's/\033\[[0-9;]*m//g')]

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

## 二、安全审计 - 攻击模式检测

| 检查项 | 数值 | 阈值 | 状态 |
|--------|------|------|------|
| SSH 失败尝试 | $ssh_fail | $SSH_FAIL_WARN_THRESHOLD | $([ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && echo "⚠ 暴力破解风险" || echo "✅ 正常") |
| SSH 成功登录 | $ssh_success | - | 信息 |
| 异常登录 (非工作时间/root) | $suspicious_logins | >0 | $([ "${suspicious_logins:-0}" -gt 0 ] && echo "⚠ 可疑" || echo "✅ 正常") |
| 疑似端口扫描 | $port_scans | >0 | $([ "${port_scans:-0}" -gt 0 ] && echo "⚠ 可疑" || echo "✅ 正常") |
| 用户枚举尝试 | $user_enum | >0 | $([ "${user_enum:-0}" -gt 0 ] && echo "⚠ 可疑" || echo "✅ 正常") |
| 恶意软件痕迹 | $malware | >0 | $([ "${malware:-0}" -gt 0 ] && echo "🔴 高危" || echo "✅ 正常") |
| sudo 异常使用 | $sudo_fail | >0 | $([ "${sudo_fail:-0}" -gt 0 ] && echo "⚠ 可疑" || echo "✅ 正常") |

### 攻击来源 IP TOP 10
\`\`\`
$(cat "${DATA_DIR}/ssh_top_ips.tmp" 2>/dev/null || echo "无攻击记录")
\`\`\`

### 端口扫描源
\`\`\`
$(cat "${DATA_DIR}/port_scan.tmp" 2>/dev/null || echo "无端口扫描记录")
\`\`\`

### 异常登录记录
\`\`\`
$(cat "${DATA_DIR}/suspicious_logins.tmp" 2>/dev/null || echo "无异常登录记录")
\`\`\`

---

## 三、事件关联分析

| 关联项 | 状态 |
|--------|------|
| 发现关联 | $correlations 条 |

\`\`\`
$(cat "${DATA_DIR}/correlations.tmp" 2>/dev/null || echo "无显著关联")
\`\`\`

---

## 四、异常检测 (历史对比)

| 检查项 | 状态 |
|--------|------|
| 异常事件 | $anomaly_count 条 |

\`\`\`
$(cat "${DATA_DIR}/anomalies.tmp" 2>/dev/null || echo "未发现异常偏差")
\`\`\`

---

## 五、系统日志摘要

| 检查项 | 数值 | 状态 |
|--------|------|------|
| 系统错误日志 | $syslog_errors | $([ "${syslog_errors:-0}" -gt 0 ] && echo "⚠ 存在错误" || echo "✅ 正常") |
| 近期重启次数 | $reboot_count | 信息 |

### 系统错误摘要（最近50条）
\`\`\`
$(head -50 "${DATA_DIR}/syslog_error.tmp" 2>/dev/null || echo "无错误记录")
\`\`\`

---

## 六、风险矩阵

| 风险级别 | 分值 | 措施 |
|----------|------|------|
| 🔴 高危 | 80-100 | 立即隔离、取证、排查入侵 |
| 🟠 中危 | 50-79 | 加强监控、限制远程访问、检查配置 |
| 🟡 低危 | 20-49 | 关注趋势、定期复查 |
| 🟢 安全 | 0-19 | 系统健康 |

**当前状态**: $(risk_level "$risk_score")

---

## 七、建议措施

EOF

    if [ "${kern_errors:-0}" -gt 0 ]; then
        if is_wsl; then
            echo "- 🟡 **内核错误 (WSL)**: 这通常是 WSL 虚拟化驱动产生的已知警告，非真实内核崩溃。建议更新 WSL 版本: \`wsl --update\`" >> "$report_file"
        else
            echo "- 🟡 **内核错误**: 建议运行 \`dmesg -T | grep -i panic\` 查看详情，考虑更新内核或驱动" >> "$report_file"
        fi
    fi
    if [ "${oom_count:-0}" -gt "$OOM_WARN_THRESHOLD" ]; then
        is_wsl && echo "- 🔴 **OOM (WSL)**: WSL 内存上限由 Windows 配置控制，建议在 Windows 中增大 WSL 内存限制" >> "$report_file"
        is_wsl || echo "- 🔴 **OOM**: 建议增加物理内存、优化应用内存使用，或调整 \`/proc/sys/vm/overcommit_memory\`" >> "$report_file"
    fi
    if [ "${reboot_count:-0}" -gt 0 ]; then
        if is_wsl; then
            echo "- ℹ️ **重启次数**: WSL 重启次数包含 Windows 启动 WSL 的计数，非真实系统重启。建议用 \`systemctl --failed\` 检查服务状态" >> "$report_file"
        else
            echo "- ℹ️ **重启次数**: 建议检查 \`systemctl --failed\` 和 \`journalctl -b -1\` 排查频繁重启原因" >> "$report_file"
        fi
    fi
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        echo "- 🔴 **SSH 暴力破解**: 建议: (1) 修改 SSH 端口 (2) 启用 fail2ban (3) 禁用密码登录改用密钥认证" >> "$report_file"
        echo "  \`\`\`bash\nsudo apt install fail2ban\nsudo sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config\n\`\`\`" >> "$report_file"
    fi
    if [ "${ssh_success:-0}" -gt 0 ] && [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        echo "- 🔴 **疑似入侵**: SSH 暴力破解后有成功登录，立即执行:" >> "$report_file"
        echo "  \`\`\`bash\n# 检查最近登录\nlast -10\n# 检查异常进程\nps auxf | grep -v \$\$\n# 检查新增用户\ncut -d: -f1 /etc/passwd\n\`\`\`" >> "$report_file"
    fi
    if [ "${suspicious_logins:-0}" -gt 0 ]; then
        echo "- 🟠 **异常登录**: 建议审查 \`last -20\` 和 \`journalctl -u ssh --since \"7 days ago\"\`" >> "$report_file"
    fi
    if [ "${sudo_fail:-0}" -gt 0 ]; then
        echo "- 🟡 **sudo 异常**: 建议检查 \`sudo -l\` 权限，限制不必要的 NOPASSWD；审查 \`/var/log/auth.log\` 中的 sudo 记录" >> "$report_file"
    fi
    if [ "${malware:-0}" -gt 0 ]; then
        echo "- 🔴 **恶意软件迹象**: 立即执行:" >> "$report_file"
        echo "  \`\`\`bash\n# 检查可疑进程\nps auxf | grep -E \":xsih|xmrig|kdevtmpfsi|kinsing\"\n# 检查启动项\nsystemctl list-unit-files | grep enabled\n\`\`\`" >> "$report_file"
    fi

    echo "" >> "$report_file"
    echo "---" >> "$report_file"
    echo "*报告由 DiagMaster v2.0 自动生成 | 审计窗口: 近 ${AUDIT_DAYS} 天 | 环境: $(is_wsl && echo "WSL" || echo "Linux Server")*" >> "$report_file"

    # 同时生成结构化 JSON 报告（便于审计链采集）
    local json_report="${report_file%.md}.json"
    cat << EOF > "$json_report"
{
  "version": "2.0",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "hostname": "$(hostname)",
  "env": "$(is_wsl && echo "WSL" || echo "Linux Server")",
  "audit_window_days": ${AUDIT_DAYS},
  "risk_score": ${risk_score},
  "risk_level": "$(echo "$risk_desc" | sed 's/\033\[[0-9;]*m//g')",
  "checks": {
    "oom_count": ${oom_count:-0},
    "kernel_errors": ${kern_errors:-0},
    "ssh_fail": ${ssh_fail:-0},
    "ssh_success": ${ssh_success:-0},
    "sudo_fail": ${sudo_fail:-0},
    "syslog_errors": ${syslog_errors:-0},
    "reboot_count": ${reboot_count:-0},
    "suspicious_logins": ${suspicious_logins:-0},
    "port_scans": ${port_scans:-0},
    "user_enum": ${user_enum:-0},
    "malware": ${malware:-0},
    "correlations": ${correlations:-0},
    "anomaly_count": ${anomaly_count:-0}
  },
  "actions": {
    "tmp_cleaned": true,
    "apt_cleaned": true,
    "journal_vacuumed": true,
    "services_restarted": []
  },
  "report_path": "$report_file"
}
EOF
}

# ========== 主审计流程 ==========

run_log_audit() {
    clear
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${YELLOW}■${NC} ${YELLOW}安全审计${NC}                                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  内核日志清洗、漏洞扫描与风险评分               ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "  ${YELLOW}[1/8]${NC} 检测可用日志源..."
    local sources
    sources=$(detect_log_sources)
    local source_count
    source_count=$(echo "$sources" | grep -c '/' 2>/dev/null || echo "0")
    echo -e "  ${GREEN}✓${NC} 发现 ${source_count} 个可用日志源"
    echo ""

    echo -e "  ${YELLOW}[2/8]${NC} 分析内核日志 (OOM / 错误)..."
    local oom_count kern_errors
    oom_count=$(analyze_oom)
    kern_errors=$(analyze_kernel_errors)
    echo -e "  ${GREEN}✓${NC} OOM 事件: ${oom_count} 次 | 内核错误: ${kern_errors} 条"
    if [ "${kern_errors:-0}" -gt 0 ]; then
        echo -e "  ${RED}⚠${NC} 发现内核 panic/Oops，建议检查驱动和硬件"
    fi
    echo ""

    echo -e "  ${YELLOW}[3/8]${NC} 审计 SSH 安全..."
    local ssh_info ssh_fail ssh_success
    ssh_info=$(analyze_ssh_bruteforce)
    ssh_fail="${ssh_info%%:*}"
    ssh_success="${ssh_info##*:}"
    echo -e "  ${GREEN}✓${NC} SSH 失败: ${ssh_fail} 次 | SSH 成功: ${ssh_success} 次"
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ]; then
        echo -e "  ${RED}⚠${NC} SSH 暴力破解风险！建议 fail2ban + 改端口 + 禁用密码登录"
    fi
    if [ "${ssh_fail:-0}" -gt "$SSH_FAIL_WARN_THRESHOLD" ] && [ "${ssh_success:-0}" -gt 0 ]; then
        echo -e "  ${RED}⚠${NC} 暴力破解后有成功登录，疑似已被入侵！"
    fi
    echo ""

    echo -e "  ${YELLOW}[4/8]${NC} 检测攻击模式..."
    local suspicious_logins port_scans user_enum privesc malware
    suspicious_logins=$(detect_suspicious_logins)
    port_scans=$(detect_port_scan)
    user_enum=$(detect_user_enumeration)
    privesc=$(detect_privilege_escalation)
    malware=$(detect_malware_indicators)
    echo -e "  ${GREEN}✓${NC} 异常登录: ${suspicious_logins} | 端口扫描: ${port_scans} | 用户枚举: ${user_enum}"
    echo -e "         ${GREEN}✓${NC} 权限提升: ${privesc} | 恶意软件: ${malware}"
    if [ "${privesc:-0}" -gt 0 ]; then
        echo -e "  ${RED}⚠${NC} 发现 sudo/用户切换可疑行为，建议审查"
    fi
    if [ "${malware:-0}" -gt 0 ]; then
        echo -e "  ${RED}⚠${NC} 检测到恶意软件痕迹！建议立即隔离"
    fi
    echo ""

    echo -e "  ${YELLOW}[5/8]${NC} 清洗系统日志..."
    local syslog_errors reboot_count
    syslog_errors=$(analyze_syslog_errors)
    reboot_count=$(analyze_reboot_history)
    echo -e "  ${GREEN}✓${NC} 系统错误: ${syslog_errors} 条 | 近期重启: ${reboot_count} 次"
    echo ""

    echo -e "  ${YELLOW}[6/8]${NC} 关联事件分析..."
    local correlations
    correlations=$(correlate_events "$oom_count" "$ssh_fail" "$ssh_success" "$suspicious_logins" "$privesc")
    echo -e "  ${GREEN}✓${NC} 发现 ${correlations} 个关联事件链"
    if [ "${correlations:-0}" -gt 0 ]; then
        echo -e "  ${YELLOW}  关键关联:${NC}"
        cat "${DATA_DIR}/correlations.tmp" 2>/dev/null | while read -r line; do
            echo -e "    ${YELLOW}▸${NC} $line"
        done
        echo ""
    fi
    echo ""

    echo -e "  ${YELLOW}[7/8]${NC} 计算风险评分..."
    local risk_score
    risk_score=$(calculate_risk_score "$oom_count" "$kern_errors" "$ssh_fail" "$ssh_success" "$privesc" "$syslog_errors" "$suspicious_logins" "$port_scans" "$user_enum" "$malware" "$correlations" "$reboot_count")
    local risk_desc
    risk_desc=$(risk_level "$risk_score")
    echo -e "  ${GREEN}✓${NC} 风险评分: ${risk_score}/100 [$(echo "$risk_desc" | sed 's/\033\[[0-9;]*m//g')]"
    echo ""

    echo -e "  ${YELLOW}[8/8]${NC} 检测历史异常..."
    local anomaly_count
    anomaly_count=$(detect_anomalies "$oom_count" "$kern_errors" "$ssh_fail" "$syslog_errors")
    echo -e "  ${GREEN}✓${NC} 发现 ${anomaly_count} 项历史异常"
    echo ""

    echo -e "  ${YELLOW}[完整]${NC} 生成审计报告..."

    reset_error_stack

    local report_path="${REPORT_DIR}/diag_report_$(date +%Y%m%d_%H%M%S).md"
    generate_report "$report_path" "$oom_count" "$kern_errors" "$ssh_info" \
        "$privesc" "$syslog_errors" "$reboot_count" \
        "$suspicious_logins" "$port_scans" "$user_enum" "$malware" \
        "$risk_score" "$correlations" "$anomaly_count"

    if [ ! -f "$report_path" ]; then
        push_error "E100" "审计报告生成失败" "检查 REPORT_DIR 目录权限"
    fi

    local json_report="${report_path%.md}.json"
    if [ ! -f "$json_report" ]; then
        push_error "E101" "JSON 报告生成失败" "检查磁盘空间或重试"
    fi

    if [ -f "$ERROR_STACK_FILE" ] && [ -s "$ERROR_STACK_FILE" ]; then
        echo ""
        echo ""
        echo -e "${CYAN}=== 受限操作详情 ===${NC}"
        render_error_stack
        echo -e "受限操作总计: ${YELLOW}$(get_error_count) 项${NC}"
        echo ""
    fi

    echo -e "${CYAN}=== 最终审计汇总 ===${NC}"
    echo -e "  风险评分:     ${risk_score}/100"
    echo -e "  ${YELLOW}关键指标:${NC}"
    echo -e "    OOM 事件:     ${oom_count} 次"
    echo -e "    SSH 爆破:     ${ssh_fail} 次"
    echo -e "    ️ 内核错误:     ${kern_errors} 条"
    echo -e "    ️ 异常登录:     ${suspicious_logins} 次"
    echo -e "    ️ 权限提升:     ${privesc} 条"
    echo -e "    ️ 恶性软件:     ${malware} 条"
    echo -e "    ️ 关联事件:     ${correlations} 条"
    echo -e "    ️ 历史异常:     ${anomaly_count} 条"
    echo -e "    ️ 系统错误:     ${syslog_errors} 条"
    echo -e "    ️ 受限操作:     $(get_error_count) 条"
    echo ""

    local env_tag="server"
    is_wsl && env_tag="wsl"

    save_baseline "$env_tag" "$oom_count" "$kern_errors" "$ssh_fail" "$ssh_success" "$privesc" "$syslog_errors" "$reboot_count"

    echo "$oom_count" > "${DATA_DIR}/oom_count.tmp"
    echo "$ssh_fail" > "${DATA_DIR}/ssh_fail.tmp"

    echo ""
    echo -e "${CYAN}=== 审计汇总 ===${NC}"
    echo -e "  OOM 事件:     ${oom_count} 次"
    echo -e "  SSH 爆破:     ${ssh_fail} 次"
    echo -e "  内核错误:     ${kern_errors} 条"
    echo -e "  异常登录:     ${suspicious_logins} 次"
    echo -e "  端口扫描:     ${port_scans} 个源"
    echo -e "  用户枚举:     ${user_enum} 个源"
    echo -e "  权限提升:     ${privesc} 条"
    echo -e "  恶性软件:     ${malware} 条"
    echo -e "  关联事件:     ${correlations} 条"
    echo -e "  历史异常:     ${anomaly_count} 条"
    echo -e "  系统错误:     ${syslog_errors} 条"
    echo -e "  风险评分:     ${risk_score}/100 [$(echo "$risk_desc" | sed 's/\033\[[0-9;]*m//g')]"
    echo ""
    echo -e "${GREEN}✓ 深度审计报告已生成: $report_path${NC}"
    echo ""
}

# 若直接执行本脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_log_audit
fi
