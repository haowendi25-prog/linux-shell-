#!/usr/bin/env bash
# 公共工具函数库

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="${LOG_FILE:-./logs/activity.log}"

log_info() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*${NC}" | tee -a "$LOG_FILE"
}

command_exists() {
    command -v "$1" &>/dev/null
}

# 健壮的浮点数比较：$1 > $2 则返回0（真），否则返回1（假）
greater_than() {
    local a="$1" b="$2"
    # 优先用 bc，若不可用则用 awk
    if command -v bc &>/dev/null; then
        if [ "$(echo "$a > $b" | bc -l 2>/dev/null)" = "1" ]; then
            return 0
        else
            return 1
        fi
    else
        # awk 备选
        if awk -v a="$a" -v b="$b" 'BEGIN { if (a > b) exit 0; else exit 1 }' 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}