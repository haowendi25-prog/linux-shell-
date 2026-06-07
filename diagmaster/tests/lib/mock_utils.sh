#!/usr/bin/env bash
# ==============================================================
# DiagMaster 测试 Mock 工具库
# 所有测试脚本可以 source 本文件来获取统一的 mock 管理函数
# ==============================================================

MOCK_DIR=""
ORIGINAL_PATH="$PATH"

# ---------- 创建 mock 环境 ----------
setup_mocks() {
    MOCK_DIR=$(mktemp -d)
    if [ ! -d "$MOCK_DIR" ]; then
        echo "FATAL: 无法创建临时 Mock 目录" >&2
        exit 1
    fi

    # mock top（CPU 15%）
    cat > "$MOCK_DIR/top" << 'EOF'
#!/bin/bash
echo "Cpu(s): 10.0 us, 5.0 sy, 0.0 ni, 80.0 id, 5.0 wa, 0.0 hi, 0.0 si, 0.0 st"
EOF
    chmod +x "$MOCK_DIR/top"

    # mock free（内存 10%，共1000MB，用100MB）
    cat > "$MOCK_DIR/free" << 'EOF'
#!/bin/bash
echo "             total        used        free      shared  buff/cache   available"
echo "Mem:           1000         100         900           0           0         900"
EOF
    chmod +x "$MOCK_DIR/free"

    # mock df（磁盘 85%）
    cat > "$MOCK_DIR/df" << 'EOF'
#!/bin/bash
echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
echo "/dev/sda1       10000000 8500000   1500000  85% /"
EOF
    chmod +x "$MOCK_DIR/df"

    # mock systemctl
    cat > "$MOCK_DIR/systemctl" << 'EOF'
#!/bin/bash
case "$*" in
    *"sshd"*) exit 0 ;;
    *"cron"*)  exit 0 ;;
    *"nginx"*) exit 1 ;;
    *)         exit 1 ;;
esac
EOF
    chmod +x "$MOCK_DIR/systemctl"

    # mock pgrep（取最后一个参数作为进程名）
    cat > "$MOCK_DIR/pgrep" << 'EOF'
#!/bin/bash
proc="${@: -1}"
case "$proc" in
    "sshd")  exit 0 ;;
    "nginx") exit 1 ;;
    "cron")  exit 0 ;;
    "bash")  exit 0 ;;
    "init")  exit 0 ;;
    *)       exit 0 ;;
esac
EOF
    chmod +x "$MOCK_DIR/pgrep"

    # mock dmesg（无 OOM）
    cat > "$MOCK_DIR/dmesg" << 'EOF'
#!/bin/bash
echo "[    0.000000] Initializing cgroup subsys cpuset"
echo "[    1.234567] CPU: Intel Core Processor"
echo "[    2.345678] PCI: Using configuration type 1 for base access"
EOF
    chmod +x "$MOCK_DIR/dmesg"

    # mock hostname
    cat > "$MOCK_DIR/hostname" << 'EOF'
#!/bin/bash
echo "test-server"
EOF
    chmod +x "$MOCK_DIR/hostname"

    # mock uptime
    cat > "$MOCK_DIR/uptime" << 'EOF'
#!/bin/bash
echo " 12:00:00 up 30 days,  5:00,  2 users,  load average: 0.10, 0.20, 0.15"
EOF
    chmod +x "$MOCK_DIR/uptime"

    # mock grep（透传到真实 grep）
    cat > "$MOCK_DIR/grep" << 'EOF'
#!/bin/bash
exec /bin/grep "$@"
EOF
    chmod +x "$MOCK_DIR/grep"

    # mock awk（透传到真实 awk）
    cat > "$MOCK_DIR/awk" << 'EOF'
#!/bin/bash
exec /usr/bin/awk "$@"
EOF
    chmod +x "$MOCK_DIR/awk"

    # mock cat（透传到真实 cat）
    cat > "$MOCK_DIR/cat" << 'EOF'
#!/bin/bash
exec /bin/cat "$@"
EOF
    chmod +x "$MOCK_DIR/cat"

    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
}

# ---------- 覆盖某个 mock 命令 ----------
overwrite_mock() {
    local name="$1" content="$2"
    printf '%s\n' "$content" > "$MOCK_DIR/$name"
    chmod +x "$MOCK_DIR/$name"
}

# ---------- 删除某个 mock 命令（模拟命令不可用） ----------
remove_mock() {
    local name="$1"
    rm -f "$MOCK_DIR/$name"
}

# ---------- 清理 mock 环境 ----------
teardown_mocks() {
    export PATH="$ORIGINAL_PATH"
    if [ -n "$MOCK_DIR" ] && [ -d "$MOCK_DIR" ]; then
        rm -rf "$MOCK_DIR"
    fi
    MOCK_DIR=""
}

# ---------- 加载被测模块的通用前置 ----------
# 这些变量必须在 source 本文件之后、调用 load_modules 之前设置
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}
SERVICES_TO_CHECK=${SERVICES_TO_CHECK:-"sshd cron"}
PROCESSES_TO_CHECK=${PROCESSES_TO_CHECK:-"sshd"}
ENABLE_ALERT=${ENABLE_ALERT:-false}

load_modules() {
    local project_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    mkdir -p "${PATROL_REPORT_DIR:-/tmp/test_reports}"
    mkdir -p "$(dirname "${LOG_FILE:-/tmp/test_patrol.log}")"
    source "$project_root/modules/patrol.sh" 2>/dev/null || true
    # 再次强制覆盖阈值（防止 patrol.sh 内部 source diag.conf 造成覆盖）
    CPU_WARN_THRESHOLD=80
    MEM_WARN_THRESHOLD=85
    DISK_WARN_THRESHOLD=90
    SERVICES_TO_CHECK="sshd cron"
    PROCESSES_TO_CHECK="sshd"
    ENABLE_ALERT=false
}