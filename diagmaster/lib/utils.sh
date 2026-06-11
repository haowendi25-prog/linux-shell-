#!/usr/bin/env bash
# 公共工具函数库

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="${LOG_FILE:-./logs/activity.log}"

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*${NC}" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*${NC}" | tee -a "$LOG_FILE" >&2
}

command_exists() {
    command -v "$1" &>/dev/null
}

greater_than() {
    local a="$1" b="$2"
    if command -v bc &>/dev/null; then
        if [ "$(echo "$a > $b" | bc -l 2>/dev/null)" = "1" ]; then
            return 0
        else
            return 1
        fi
    else
        if awk -v a="$a" -v b="$b" 'BEGIN { if (a > b) exit 0; else exit 1 }' 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

test_ssh_connection() {
    local node="$1"
    local timeout="${2:-5}"

    if [ "$node" = "localhost" ]; then
        return 0
    fi

    if timeout "$timeout" bash -c "echo > /dev/tcp/${node}/22" 2>/dev/null; then
        return 0
    fi

    return 1
}

get_node_status() {
    local node="$1"

    if [ "$node" = "localhost" ]; then
        echo "本机"
        return 0
    fi

    if test_ssh_connection "$node"; then
        echo "在线"
        return 0
    else
        echo "离线"
        return 1
    fi
}

verify_diagmaster_on_node() {
    local node="$1"

    if [ "$node" = "localhost" ]; then
        [ -f "$ROOT_DIR/diagmaster.sh" ] && return 0 || return 1
    fi

    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" \
        "[ -f /opt/diagmaster/diagmaster.sh ] 2>/dev/null" 2>/dev/null

    return $?
}

execute_on_node() {
    local node="$1"
    local command="$2"

    if [ "$node" = "localhost" ]; then
        eval "$command"
    else
        ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
            -o BatchMode=yes \
            "$node" "$command" 2>/dev/null
    fi
}

test_ssh_key_auth() {
    local node="$1"

    if [ "$node" = "localhost" ]; then
        return 0
    fi

    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           -o PasswordAuthentication=no \
           -o BatchMode=yes \
           "$node" "echo ok" 2>/dev/null | grep -q "ok"; then
        return 0
    fi

    return 1
}

collect_remote() {
    local node="$1"
    local remote_output=""

    if [ "$node" = "localhost" ]; then
        local cpu mem disk load proc
        cpu=$(collect_cpu)
        mem=$(collect_memory)
        disk=$(collect_disk)
        load=$(collect_load)
        proc=$(collect_processes)
        remote_output="CPU=${cpu}
MEM=${mem}
DISK=${disk}
LOAD=${load}
PROC=${proc}"
    else
        if ! test_ssh_connection "$node" 5; then
            echo "NODE_OFFLINE"
            return 1
        fi
        remote_output=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$node" bash -s 2>/dev/null << 'REMOTE_EOF'
set +e
cpu=$(top -bn1 | grep 'Cpu(s)' | awk '{print $2+$4}' 2>/dev/null)
[ -z "$cpu" ] && cpu=$(awk '/^cpu /{idle=$5+$6}END{print "0"}' /proc/stat 2>/dev/null)
cpu=${cpu:-0}
mem=$(free -m | awk '/Mem:/ {if($2>0) printf "%.1f", $3/$2*100; else print "0"}' 2>/dev/null)
[ -z "$mem" ] && mem=0
disk=$(df -h / | awk 'NR==2 {gsub(/%/,""); print $5}' 2>/dev/null)
[ -z "$disk" ] && disk=0
load=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null)
[ -z "$load" ] && load="N/A"
proc=$(ps aux 2>/dev/null | wc -l)
printf 'CPU=%s\nMEM=%s\nDISK=%s\nLOAD=%s\nPROC=%s\n' "$cpu" "$mem" "$disk" "$load" "$proc"
REMOTE_EOF
)
    fi

    if [ -z "$remote_output" ] || [ "$remote_output" = "NODE_OFFLINE" ]; then
        echo "NODE_OFFLINE"
        return 1
    fi

    echo "$remote_output"
    return 0
}