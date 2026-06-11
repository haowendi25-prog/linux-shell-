#!/usr/bin/env bash
set -uo pipefail

# 项目根目录
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 导入公共库
source "$ROOT_DIR/lib/utils.sh"

# 加载配置文件
CONF_FILE="$ROOT_DIR/config/diag.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    echo "错误: 缺少核心配置文件 $CONF_FILE"
    exit 1
fi

LOG_FILE="$ROOT_DIR/logs/activity.log"
mkdir -p "$ROOT_DIR/reports" "$ROOT_DIR/data" "$ROOT_DIR/logs" "$ROOT_DIR/backup"

# 默认值
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}
ADMIN_USER=${ADMIN_USER:-"admin"}
ADMIN_PASS=${ADMIN_PASS:-"12345"}
NODE_DB="$ROOT_DIR/data/nodes.txt"
touch "$NODE_DB"
# 如果节点数据库为空，自动添加本机作为默认节点
if [ ! -s "$NODE_DB" ]; then
    echo "$(hostname)" >> "$NODE_DB"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动添加本机节点: $(hostname)" >> "$LOG_FILE"
fi

# 导入功能模块
source "$ROOT_DIR/modules/collector.sh" 2>/dev/null || true
source "$ROOT_DIR/modules/log_analyzer.sh" 2>/dev/null || true
source "$ROOT_DIR/modules/patrol.sh" 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
CYAN_BOX='\033[44;37m'
DGRAY='\033[90m'
LGRAY='\033[37m'
BOLD='\033[1m'
NC='\033[0m'
SP="  "
SEP="${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
THIN_SEP="${DGRAY}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"

wt_menu() {
    local title="$1"
    local text="$2"
    shift 2
    local opts=()
    while [ $# -gt 0 ]; do
        opts+=("$1" "$2")
        shift 2
    done
    CHOICE=$(whiptail --title "$title" --menu "$text" 20 70 12 "${opts[@]}" 3>&1 1>&2 2>&3)
    echo "$CHOICE"
}

wt_msgbox() {
    local title="$1"
    local text="$2"
    local h="${3:-10}" w="${4:-60}"
    whiptail --title "$title" --msgbox "$text" "$h" "$w" 3>&1 1>&2 2>&3
}

wt_yesno() {
    local title="$1"
    local text="$2"
    local h="${3:-8}" w="${4:-50}"
    whiptail --title "$title" --yesno "$text" "$h" "$w" 3>&1 1>&2 2>&3
    return $?
}

wt_inputbox() {
    local title="$1"
    local text="$2"
    local init="${3:-}"
    RESULT=$(whiptail --title "$title" --inputbox "$text" 10 60 "$init" 3>&1 1>&2 2>&3)
    echo "$RESULT"
}

header() {
    clear
    echo ""
    echo -e "  ${CYAN_BOX}  DiagMaster v2.0 | 服务器多维智能诊断运维平台  ${NC}"
    echo -e "  ${SEP}"
    echo ""
}

top_bar() {
    echo ""
    echo -e "  ${CYAN_BOX}  DiagMaster v2.0 | 服务器多维智能诊断运维平台  ${NC}"
    echo -e "  ${SEP}"
}

section_header() {
    echo -e "\n  ${BOLD}${GREEN}▸ ${1}${NC}\n"
}

loading() {
    local text="${1:-处理中}"
    echo -e -n "  ${DGRAY}[${LGRAY}INFO${DGRAY}]${NC} ${text}"
    for i in 1 2 3; do
        sleep 0.15
        echo -n "."
    done
    echo -e " ${GREEN}✓${NC}\n"
}

status_bar() {
    local status="${1:-正常}"
    echo ""
    echo -e "  ${DGRAY}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"
    echo -e "  ${DGRAY}●${NC} 系统状态: ${GREEN}[${status}]${NC}   ${DGRAY}⏰${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "  ${DGRAY}💡 提示: 输入功能编号并回车执行; 返回主菜单请输 0 或 q${NC}"
    echo ""
}

show_brand() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${GREEN}DiagMaster${NC} 服务器一键多维智能诊断工具箱 ${YELLOW}v2.0${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_brand() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${GREEN}DiagMaster${NC} 服务器一键多维智能诊断工具箱 ${YELLOW}v2.0${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${GREEN}●${NC} 分布式节点管理"
    echo -e "   ${GREEN}●${NC} 性能监控采集"
    echo -e "   ${GREEN}●${NC} 安全审计分析"
    echo -e "   ${GREEN}●${NC} 智能磁盘清理"
    echo -e "   ${GREEN}●${NC} 自动巡逻巡检"
    echo -e "   ${GREEN}●${NC} 后台守护进程"
    echo ""
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

node_management() {
    while true; do
        CHOICE=$(wt_menu "模块 1 | 节点管理" \
            "分布式服务器资产与 SSH 管控" \
            "1" "查看受控节点列表（含状态）" \
            "2" "新增受控服务器节点" \
            "3" "删除失效服务器节点" \
            "4" "测试节点连接" \
            "5" "查看节点详细信息" \
            "6" "批量远程诊断（分布式采集）" \
            "0" "返回主菜单")
        case "$CHOICE" in
            1) show_nodes_with_status ;;
            2) add_new_node ;;
            3) delete_node ;;
            4) test_node_connection ;;
            5) show_node_details ;;
            6) batch_remote_diagnose ;;
            0|"") return ;;
        esac
    done
}

test_node_connection() {
    clear
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}   ${GREEN}测试节点连接${NC}                               ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    if [ ! -f "$NODE_DB" ] || [ ! -s "$NODE_DB" ]; then
        echo -e "${YELLOW}暂无受控节点${NC}"
        read -p "按回车键返回..." _
        return
    fi

    echo "当前受控节点:"
    nl "$NODE_DB"
    echo ""

    read -p "请输入要测试的节点编号: " choice

    if [ "$choice" -lt 1 ] 2>/dev/null; then
        echo -e "${RED}❌ 无效的编号${NC}"
        read -p "按回车键返回..." _
        return 1
    fi

    local node
    node=$(sed -n "${choice}p" "$NODE_DB")

    if [ -z "$node" ]; then
        echo -e "${RED}❌ 找不到该节点${NC}"
        read -p "按回车键返回..." _
        return 1
    fi

    echo ""
    echo "正在测试节点: $node ..."
    echo ""

    if [ "$node" = "localhost" ]; then
        echo -e "${GREEN}✅ 本机在线${NC}"
        read -p "按回车键返回..." _
        return 0
    fi

    echo -n "1. 测试 SSH 连接... "
    if test_ssh_connection "$node" 10; then
        echo -e "${GREEN}✅ 成功${NC}"
    else
        echo -e "${RED}❌ 失败${NC}"
        echo "   无法连接到 $node:22，请检查网络和防火墙"
        read -p "按回车键返回..." _
        return 1
    fi

    echo -n "2. 测试 SSH 密钥认证... "
    if test_ssh_key_auth "$node"; then
        echo -e "${GREEN}✅ 成功（无需密码）${NC}"
    else
        echo -e "${YELLOW}⚠️  需要密码登录${NC}"
        echo "   建议配置 SSH 公钥认证以支持分布式功能"
    fi

    echo -n "3. 检查 DiagMaster 安装... "
    if verify_diagmaster_on_node "$node"; then
        echo -e "${GREEN}✅ 已安装${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
        echo "   需要在远程节点安装 DiagMaster 才能使用分布式功能"
    fi

    echo -n "4. 测试远程命令执行... "
    if execute_on_node "$node" "echo 'test' > /tmp/diagmaster_test.txt && [ -f /tmp/diagmaster_test.txt ] && rm /tmp/diagmaster_test.txt" 2>/dev/null; then
        echo -e "${GREEN}✅ 成功${NC}"
    else
        echo -e "${YELLOW}⚠️  失败${NC}"
        echo "   可能没有写入权限"
    fi

    echo ""
    echo -e "${GREEN}✅ 节点 $node 测试完成${NC}"

    read -p "按回车键返回..." _
}

show_node_details() {
    show_brand
    echo -e "${YELLOW}--- 节点详细信息 ---${NC}"
    echo ""

    if [ ! -f "$NODE_DB" ] || [ ! -s "$NODE_DB" ]; then
        echo -e "${YELLOW}暂无受控节点${NC}"
        read -p "按回车键返回..." _
        return
    fi

    echo "当前受控节点:"
    nl "$NODE_DB"
    echo ""

    read -p "请输入要查看详细信息的节点编号: " choice

    if [ "$choice" -lt 1 ] 2>/dev/null; then
        echo -e "${RED}❌ 无效的编号${NC}"
        read -p "按回车键返回..." _
        return 1
    fi

    local node
    node=$(sed -n "${choice}p" "$NODE_DB")

    if [ -z "$node" ]; then
        echo -e "${RED}❌ 找不到该节点${NC}"
        read -p "按回车键返回..." _
        return 1
    fi

    echo ""
    echo "节点 $node 的详细信息:"
    echo "================================"

    if [ "$node" = "localhost" ]; then
        echo ""
        echo "主机名: $(hostname)"
        echo "操作系统: $(uname -s)"
        echo "内核版本: $(uname -r)"
        echo "架构: $(uname -m)"
        echo "CPU 核心数: $(nproc)"
        echo "内存大小: $(free -h | awk '/^Mem:/ {print $2}')"
        echo "磁盘使用: $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
        echo "当前用户: $(whoami)"
        echo "SSH 服务: $(systemctl is-active ssh 2>/dev/null || echo '未知')"
        echo ""
    else
        echo ""
        echo "正在获取远程信息..."

        local remote_info
        remote_info=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$node" \
            "echo '主机名: '$(hostname); \
             echo '操作系统: '$(uname -s); \
             echo '内核版本: '$(uname -r); \
             echo '架构: '$(uname -m); \
             echo 'CPU 核心数: '$(nproc); \
             echo '内存大小: '$(free -h 2>/dev/null | awk '/^Mem:/ {print \$2}'); \
             echo '磁盘使用: '$(df -h / 2>/dev/null | awk 'NR==2 {print \$3 \" / \" \$2 \" (\" \$5 \")\"}'); \
             echo '当前用户: '$(whoami); \
             echo 'SSH 服务: '$(systemctl is-active ssh 2>/dev/null || echo '未知')" 2>/dev/null)

        if [ -n "$remote_info" ]; then
            echo "$remote_info"
        else
            echo -e "${RED}❌ 无法获取远程信息${NC}"
        fi
    fi

    echo "================================"
    echo ""

    read -p "按回车键返回..." _
}

batch_remote_diagnose() {
    show_brand
    echo -e "${YELLOW}--- [模块 1] 批量远程诊断（分布式采集） ---${NC}"
    echo ""

    if [ ! -f "$NODE_DB" ] || [ ! -s "$NODE_DB" ]; then
        echo -e "${YELLOW}⚠️  暂无受控节点，请先在模块1中添加节点${NC}"
        read -p "按回车键返回..." _
        return
    fi

    local nodes=()
    local online_nodes=()
    local offline_nodes=()

    while IFS= read -r node; do
        [ -z "$node" ] && continue
        nodes+=("$node")
        if [ "$node" = "localhost" ] || test_ssh_connection "$node" 3; then
            online_nodes+=("$node")
        else
            offline_nodes+=("$node")
        fi
    done < "$NODE_DB"

    if [ ${#online_nodes[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️  所有节点均离线，无法执行远程诊断${NC}"
        read -p "按回车键返回..." _
        return
    fi

    echo "待诊断节点 (${#online_nodes[@]} 在线 / ${#offline_nodes[@]} 离线):"
    for node in "${online_nodes[@]}"; do
        echo -e "  ${GREEN}●${NC} $node"
    done
    for node in "${offline_nodes[@]}"; do
        echo -e "  ${RED}○${NC} $node (跳过)"
    done
    echo ""

    local tmp_dir="$ROOT_DIR/data/batch_$$"
    mkdir -p "$tmp_dir"
    local pids=()

    for node in "${online_nodes[@]}"; do
        local safe_name
        safe_name=$(echo "$node" | tr '/' '_' | tr ':' '_')
        collect_remote "$node" > "$tmp_dir/${safe_name}.out" 2>/dev/null &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    echo "========================================"
    echo "  批量诊断结果汇总"
    echo "========================================"

    local any_fail=0
    for node in "${online_nodes[@]}"; do
        local safe_name
        safe_name=$(echo "$node" | tr '/' '_' | tr ':' '_')
        local node_file="$tmp_dir/${safe_name}.out"

        if [ ! -f "$node_file" ] || [ ! -s "$node_file" ]; then
            echo -e "[${YELLOW}${node}${NC}] 采集失败"
            any_fail=1
            continue
        fi

        local content
        content=$(cat "$node_file")

        if [ "$content" = "NODE_OFFLINE" ]; then
            echo -e "[${YELLOW}${node}${NC}] ${RED}离线${NC}"
            any_fail=1
            continue
        fi

        local cpu_val mem_val disk_val load_val proc_val
        cpu_val=$(echo "$content" | grep '^CPU=' | head -1 | cut -d'=' -f2)
        mem_val=$(echo "$content" | grep '^MEM=' | head -1 | cut -d'=' -f2)
        disk_val=$(echo "$content" | grep '^DISK=' | head -1 | cut -d'=' -f2)
        load_val=$(echo "$content" | grep '^LOAD=' | head -1 | cut -d'=' -f2)
        proc_val=$(echo "$content" | grep '^PROC=' | head -1 | cut -d'=' -f2)

        cpu_val=${cpu_val:-0}
        mem_val=${mem_val:-0}
        disk_val=${disk_val:-0}
        load_val=${load_val:-N/A}
        proc_val=${proc_val:-0}

        echo ""
        echo -e "[${CYAN}${node}${NC}]"
        echo "  CPU: $(colored_status "$cpu_val" "$CPU_WARN_THRESHOLD")"
        echo "  内存: $(colored_status "$mem_val" "$MEM_WARN_THRESHOLD")"
        echo "  磁盘: $(colored_status "$disk_val" "$DISK_WARN_THRESHOLD")"
        echo "  负载: $load_val"
        echo "  进程: $proc_val"

        if [ "$(check_threshold "cpu" "$cpu_val" "$CPU_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ CPU 过高${NC}"
            any_fail=1
        fi
        if [ "$(check_threshold "mem" "$mem_val" "$MEM_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ 内存过高${NC}"
            any_fail=1
        fi
        if [ "$(check_threshold "disk" "$disk_val" "$DISK_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ 磁盘过高${NC}"
            any_fail=1
        fi
    done

    echo ""
    echo "========================================"
    if [ "$any_fail" -eq 0 ]; then
        echo -e "${GREEN}✓ 全部节点指标正常${NC}"
    else
        echo -e "${RED}⚠ 部分节点存在告警${NC}"
    fi
    echo "========================================"

    rm -rf "$tmp_dir"
    log_action "执行批量远程诊断 (共 ${#nodes[@]} 个节点)"
    read -p "按回车键返回..." _
}

run_collector() {
    clear
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${GREEN}■${NC} ${GREEN}性能监控${NC}                                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  CPU、内存、磁盘多进程并行采集与告警          ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    if ! command_exists collect_cpu 2>/dev/null; then
        [ -f "$ROOT_DIR/modules/collector.sh" ] && source "$ROOT_DIR/modules/collector.sh" 2>/dev/null || true
    fi

    local nodes=("localhost")
    local online_nodes=("localhost")
    local offline_nodes=()

    if [ -f "$NODE_DB" ] && [ -s "$NODE_DB" ]; then
        while IFS= read -r node; do
            [ -z "$node" ] && continue
            [ "$node" = "localhost" ] && continue
            nodes+=("$node")
            if test_ssh_connection "$node" 3; then
                online_nodes+=("$node")
            else
                offline_nodes+=("$node")
            fi
        done < "$NODE_DB"
    fi

    if [ ${#online_nodes[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  暂无在线节点可采集${NC}"
        printf "\n  ${CYAN}»${NC} 按回车键返回..."
        read -r _
        return
    fi

    echo -e "  ${CYAN}待采集节点${NC} ${YELLOW}(${#online_nodes[@]} 在线 / ${#offline_nodes[@]} 离线)${NC}"
    for node in "${online_nodes[@]}"; do
        echo -e "    ${GREEN}●${NC} $node"
    done
    for node in "${offline_nodes[@]}"; do
        echo -e "    ${RED}○${NC} $node ${RED}(离线/跳过)${NC}"
    done
    echo ""

    local tmp_dir="$ROOT_DIR/data/collect_$$"
    mkdir -p "$tmp_dir"
    local pids=()

    echo -e "  ${CYAN}▸${NC} 正在并行采集指标..."
    echo ""

    for node in "${online_nodes[@]}"; do
        local safe_name
        safe_name=$(echo "$node" | tr '/' '_' | tr ':' '_')
        collect_remote "$node" > "$tmp_dir/${safe_name}.out" 2>/dev/null &
        pids+=($!)
    done

    local any_fail=0
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    echo -e "  ${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}  采集结果汇总${NC}"
    echo -e "  ${CYAN}══════════════════════════════════════════════════════════${NC}"

    for node in "${online_nodes[@]}"; do
        local safe_name
        safe_name=$(echo "$node" | tr '/' '_' | tr ':' '_')
        local node_file="$tmp_dir/${safe_name}.out"

        if [ ! -f "$node_file" ] || [ ! -s "$node_file" ]; then
            echo ""
            echo -e "[${YELLOW}${node}${NC}] 采集失败"
            any_fail=1
            continue
        fi

        local content
        content=$(cat "$node_file")

        if [ "$content" = "NODE_OFFLINE" ]; then
            echo ""
            echo -e "[${YELLOW}${node}${NC}] ${RED}离线${NC}"
            any_fail=1
            continue
        fi

        local cpu_val mem_val disk_val load_val proc_val
        cpu_val=$(echo "$content" | grep '^CPU=' | head -1 | cut -d'=' -f2)
        mem_val=$(echo "$content" | grep '^MEM=' | head -1 | cut -d'=' -f2)
        disk_val=$(echo "$content" | grep '^DISK=' | head -1 | cut -d'=' -f2)
        load_val=$(echo "$content" | grep '^LOAD=' | head -1 | cut -d'=' -f2)
        proc_val=$(echo "$content" | grep '^PROC=' | head -1 | cut -d'=' -f2)

        cpu_val=${cpu_val:-0}
        mem_val=${mem_val:-0}
        disk_val=${disk_val:-0}
        load_val=${load_val:-N/A}
        proc_val=${proc_val:-0}

        echo ""
        echo -e "[${CYAN}${node}${NC}]"
        echo "  CPU: $(colored_status "$cpu_val" "$CPU_WARN_THRESHOLD")"
        echo "  内存: $(colored_status "$mem_val" "$MEM_WARN_THRESHOLD")"
        echo "  磁盘: $(colored_status "$disk_val" "$DISK_WARN_THRESHOLD")"
        echo "  负载: $load_val"
        echo "  进程: $proc_val"

        if [ "$(check_threshold "cpu" "$cpu_val" "$CPU_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ CPU 过高${NC}"
            any_fail=1
        fi
        if [ "$(check_threshold "mem" "$mem_val" "$MEM_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ 内存过高${NC}"
            any_fail=1
        fi
        if [ "$(check_threshold "disk" "$disk_val" "$DISK_WARN_THRESHOLD")" = "1" ]; then
            echo -e "  ${RED}⚠ 磁盘过高${NC}"
            any_fail=1
        fi
    done

    echo ""
    echo "========================================"

    if [ "$any_fail" -eq 0 ]; then
        echo -e "${GREEN}✓ 全部节点指标正常${NC}"
    else
        echo -e "${RED}⚠ 部分节点存在告警${NC}"
    fi
    echo "========================================"

    rm -rf "$tmp_dir"
    log_action "执行多节点性能采集 (共 ${#nodes[@]} 个节点)"
    read -p "按回车键返回..." _
}

run_log_audit() {
    clear
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${YELLOW}■${NC} ${YELLOW}安全审计${NC}                                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC}  内核日志清洗、漏洞扫描与风险评分               ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""
    if [ -f "$ROOT_DIR/modules/log_analyzer.sh" ]; then
        bash "$ROOT_DIR/modules/log_analyzer.sh"
    else
        echo -e "  ${RED}✖ log_analyzer.sh 不存在，执行内联分析${NC}"
        mkdir -p "$ROOT_DIR/data"
        dmesg 2>/dev/null | grep -c -i "out of memory" > "$ROOT_DIR/data/oom_count.tmp" || echo "0" > "$ROOT_DIR/data/oom_count.tmp"
        grep -c "Failed password" /var/log/auth.log 2>/dev/null > "$ROOT_DIR/data/ssh_fail.tmp" || echo "0" > "$ROOT_DIR/data/ssh_fail.tmp"
    fi
    local oom_count; oom_count=$(cat "$ROOT_DIR/data/oom_count.tmp" 2>/dev/null || echo "0")
    local ssh_fail; ssh_fail=$(cat "$ROOT_DIR/data/ssh_fail.tmp" 2>/dev/null || echo "0")
    echo -e "  ${CYAN}OOM 事件${NC}: ${oom_count} 次   ${YELLOW}|${NC}   ${CYAN}SSH 爆破尝试${NC}: ${ssh_fail} 次"
    local report_path="$ROOT_DIR/reports/diag_report_$(date +%Y%m%d_%H%M%S).md"
    cat << EOF > "$report_path"
# DiagMaster 自动化审计报告
- 审计时间: $(date)
- 内核OOM频次: ${oom_count}
- SSH风险频次: ${ssh_fail}
EOF
    echo -e "\n  ${GREEN}✓ 报告已输出至: $report_path${NC}"
    log_action "执行高级日志审计"
    printf "\n  ${CYAN}»${NC} 按回车键返回..."
    read -r _
}

disk_cleanup() {
    clear
    echo -e "  ${CYAN}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC}  ${YELLOW}■${NC} ${YELLOW}智能清理${NC}                                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}└─────────────────────────────────────────────────┘${NC}"
    echo ""

    local total_freed=0
    local cleanup_report="$ROOT_DIR/reports/disk_cleanup_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$ROOT_DIR/reports"
    echo "DiagMaster 磁盘清理报告 - $(date '+%Y-%m-%d %H:%M:%S')" > "$cleanup_report"
    echo "========================================" >> "$cleanup_report"

    # ---------- 1. 扫描垃圾源 ----------
    echo -e "  ${YELLOW}[扫描]${NC} 正在分析磁盘垃圾源..."
    echo ""

    declare -a scan_items=()
    declare -a scan_sizes=()
    declare -a scan_actions=()
    declare -a scan_risks=()
    local idx=0

    # /tmp 过期文件（仅1天前的）
    local tmp_size
    tmp_size=$(du -sm /tmp 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
    [ -z "$tmp_size" ] && tmp_size=0
    if [ "${tmp_size:-0}" -gt 0 ]; then
        scan_items+=("系统临时文件 /tmp（1天前）")
        scan_sizes+=("${tmp_size}")
        scan_actions+=("tmp")
        scan_risks+=("1")
        idx=$((idx + 1))
    fi

    # 用户缓存
    local cache_size
    cache_size=$(du -sm "$HOME/.cache" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
    [ -z "$cache_size" ] && cache_size=0
    if [ "${cache_size:-0}" -gt 0 ]; then
        scan_items+=("用户缓存 ~/.cache")
        scan_sizes+=("${cache_size}")
        scan_actions+=("cache")
        scan_risks+=("1")
        idx=$((idx + 1))
    fi

    # 回收站
    local trash_size=0
    [ -d "$HOME/.local/share/Trash" ] && trash_size=$(du -sm "$HOME/.local/share/Trash" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
    if [ "${trash_size:-0}" -gt 0 ]; then
        scan_items+=("回收站 Trash")
        scan_sizes+=("${trash_size}")
        scan_actions+=("trash")
        scan_risks+=("1")
        idx=$((idx + 1))
    fi

    # apt 缓存
    local apt_size=0
    if [ -d /var/cache/apt/archives ]; then
        apt_size=$(du -sm /var/cache/apt/archives 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
        [ -z "$apt_size" ] && apt_size=0
    fi
    if [ "${apt_size:-0}" -gt 0 ]; then
        scan_items+=("apt 包缓存")
        scan_sizes+=("${apt_size}")
        scan_actions+=("apt")
        scan_risks+=("2")
        idx=$((idx + 1))
    fi

    # journal 日志（7天前）
    local journal_size=0
    if command -v journalctl &>/dev/null; then
        journal_size=$(journalctl --disk-usage 2>/dev/null | tr -d '\n' | grep -oE '[0-9.]+[KMGT]?B' | head -1 || echo "")
        if [ -n "$journal_size" ]; then
            journal_size=$(echo "$journal_size" | grep -oE '[0-9.]+' || echo "0")
        fi
    fi
    if [ "${journal_size:-0}" -gt 0 ] 2>/dev/null; then
        scan_items+=("journal 日志（7天前）")
        scan_sizes+=("${journal_size}")
        scan_actions+=("journal")
        scan_risks+=("2")
        idx=$((idx + 1))
    fi

    # 旧内核（保留最近2个）
    local old_kernels=0
    if [ -d /boot ] && command -v dpkg &>/dev/null; then
        old_kernels=$(dpkg --list 2>/dev/null | grep -E "linux-image-[0-9]+|linux-show_brands-[0-9]+" | grep -v "$(uname -r)" | wc -l | tr -d '[:space:]' || echo "0")
        [ -z "$old_kernels" ] && old_kernels=0
    fi
    if [ "${old_kernels:-0}" -gt 0 ]; then
        scan_items+=("旧内核 (保留最近2个)")
        scan_sizes+=("0")
        scan_actions+=("oldkernel")
        scan_risks+=("3")
        idx=$((idx + 1))
    fi

    # Docker 悬空镜像
    local docker_size=0
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        docker_size=$(docker system df 2>/dev/null | grep -i "reclaimable" | grep -oE '[0-9.]+' | head -1 || echo "0")
        docker_size=${docker_size%.*}
        [ -z "$docker_size" ] && docker_size=0
    fi
    if [ "${docker_size:-0}" -gt 0 ] 2>/dev/null; then
        scan_items+=("Docker 悬空镜像/缓存")
        scan_sizes+=("${docker_size}")
        scan_actions+=("docker")
        scan_risks+=("3")
        idx=$((idx + 1))
    fi

    # 显示扫描结果
    if [ $idx -eq 0 ]; then
        echo -e "  ${GREEN}✓ 磁盘空间充裕，未发现明显垃圾。${NC}"
        read -p "  按回车键返回..." _
        return
    fi

    printf "  ${CYAN}%-3s | %-30s | %-10s | %-6s${NC}\n" "#" "类别" "大小(MB)" "风险"
    echo "  -------------------------------------------------------------"
    local i
    for i in $(seq 0 $((idx - 1))); do
        local risk_text="低"
        [ "${scan_risks[$i]}" -eq 2 ] && risk_text="中"

        local risk_color="${GREEN}"
        [ "${scan_risks[$i]}" -eq 2 ] && risk_color="${YELLOW}"

        printf "  %-3s | %-30s | %-10s | " "$((i + 1))" "${scan_items[$i]}" "${scan_sizes[$i]} MB"
        printf "%b\n" "${risk_color}${risk_text}${NC}"
    done
    echo ""

    # ---------- 2. 用户选择清理项 ----------
    echo "  提示: 直接回车 = 仅清理低风险项 | 空格分隔多个编号如: 1 3 | 0 = 取消"
    echo "  输入要清理的编号:"
    read -p "  选择: " choices

    local -a selected=()
    if [ -z "$choices" ]; then
        # 默认只选低风险项（风险=1）
        for i in $(seq 0 $((idx - 1))); do
            if [ "${scan_risks[$i]}" -eq 1 ]; then
                selected+=("$i")
            fi
        done
    elif [ "$choices" = "0" ]; then
        echo "  已取消。"
        read -p "  按回车键返回..." _
        return
    else
        for c in $choices; do
            local ci=$((c - 1))
            if [ "$ci" -ge 0 ] && [ "$ci" -lt "$idx" ]; then
                selected+=("$ci")
            fi
        done
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        echo "  未选择任何项，已取消。"
        read -p "  按回车键返回..." _
        return
    fi

    # ---------- 3. 执行清理 ----------
    echo ""
    echo -e "  ${YELLOW}[清理]${NC} 开始执行..."
    echo ""

    local sel
    for sel in "${selected[@]}"; do
        local action="${scan_actions[$sel]}"
        local size="${scan_sizes[$sel]}"
        local label="${scan_items[$sel]}"
        echo -e "  ${CYAN}▸${NC} 清理 ${label} ..."

        case "$action" in
            tmp)
                local before
                before=$(du -sm /tmp 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$before" ] && before=0
                find /tmp -type f -atime +1 -delete 2>/dev/null || true
                find /tmp -type d -empty -delete 2>/dev/null || true
                local after
                after=$(du -sm /tmp 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$after" ] && after=0
                local freed=$((before - after))
                [ "$freed" -lt 0 ] && freed=0
                total_freed=$((total_freed + freed))
                echo -e "       ${GREEN}✓${NC} 已清理 ${freed} MB"
                echo "  /tmp 清理: 清理前 ${before} MB, 清理后 ${after} MB, 释放 ${freed} MB" >> "$cleanup_report"
                ;;
            cache)
                local before
                before=$(du -sm "$HOME/.cache" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$before" ] && before=0
                find "$HOME/.cache" -type f -delete 2>/dev/null || true
                find "$HOME/.cache" -type d -empty -delete 2>/dev/null || true
                local after
                after=$(du -sm "$HOME/.cache" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$after" ] && after=0
                local freed=$((before - after))
                [ "$freed" -lt 0 ] && freed=0
                total_freed=$((total_freed + freed))
                echo -e "       ${GREEN}✓${NC} 已清理 ${freed} MB"
                echo "  缓存清理: 清理前 ${before} MB, 清理后 ${after} MB, 释放 ${freed} MB" >> "$cleanup_report"
                ;;
            trash)
                local before
                before=$(du -sm "$HOME/.local/share/Trash" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$before" ] && before=0
                rm -rf "$HOME/.local/share/Trash/"* 2>/dev/null || true
                local after
                after=$(du -sm "$HOME/.local/share/Trash" 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                [ -z "$after" ] && after=0
                local freed=$((before - after))
                [ "$freed" -lt 0 ] && freed=0
                total_freed=$((total_freed + freed))
                echo -e "       ${GREEN}✓${NC} 已清理 ${freed} MB"
                echo "  回收站清理: 清理前 ${before} MB, 清理后 ${after} MB, 释放 ${freed} MB" >> "$cleanup_report"
                ;;
            apt)
                if command -v apt-get &>/dev/null; then
                    apt-get clean 2>/dev/null || true
                    local freed
                    freed=$(du -sm /var/cache/apt/archives 2>/dev/null | awk '{print $1}' | head -1 | tr -d '[:space:]')
                    [ -z "$freed" ] && freed=0
                    total_freed=$((total_freed + freed))
                    echo -e "       ${GREEN}✓${NC} apt 缓存已清理 (约 ${freed} MB)"
                    echo "  apt 缓存清理: 释放约 ${freed} MB" >> "$cleanup_report"
                else
                    echo -e "       ${YELLOW}⚠${NC} 当前环境无 apt，跳过"
                fi
                ;;
            journal)
                if command -v journalctl &>/dev/null; then
                    journalctl --vacuum-time=7d 2>/dev/null || true
                    echo -e "       ${GREEN}✓${NC} 已清理 7 天前的 journal 日志"
                    echo "  journal 日志清理: 已清理7天前日志" >> "$cleanup_report"
                else
                    echo -e "       ${YELLOW}⚠${NC} 当前环境无 journalctl，跳过"
                fi
                ;;
            oldkernel)
                if command -v dpkg &>/dev/null; then
                    echo -e "       ${YELLOW}⚠${NC} 旧内核清理需手动执行，建议: sudo apt autoremove"
                    echo "  旧内核: 建议手动执行 sudo apt autoremove" >> "$cleanup_report"
                else
                    echo -e "       ${YELLOW}⚠${NC} 当前环境无 dpkg，跳过"
                fi
                ;;
            docker)
                if command -v docker &>/dev/null && docker info &>/dev/null; then
                    docker image prune -f 2>/dev/null || true
                    docker system prune -f 2>/dev/null || true
                    echo -e "       ${GREEN}✓${NC} 已清理 Docker 悬空镜像和缓存"
                    echo "  Docker 清理: 已清理悬空镜像和缓存" >> "$cleanup_report"
                else
                    echo -e "       ${YELLOW}⚠${NC} 当前环境无 Docker，跳过"
                fi
                ;;
        esac
        echo ""
    done

    # ---------- 4. 自愈动作 ----------
    echo -e "  ${YELLOW}[自愈]${NC} 执行系统修复..."
    echo ""

    if command -v apt &>/dev/null; then
        echo -e "  ${CYAN}▸${NC} 修复 apt 依赖..."
        apt --fix-broken install -y 2>/dev/null && echo -e "       ${GREEN}✓ apt 依赖修复完成${NC}" || echo -e "       ${YELLOW}⚠ 需要 sudo 或环境不支持${NC}"
        echo ""
    fi

    for svc in cron ssh docker; do
        if command -v systemctl &>/dev/null && systemctl is-active "$svc" &>/dev/null; then
            echo -e "  ${CYAN}▸${NC} 重启服务: ${svc}..."
            systemctl try-restart "$svc" 2>/dev/null && echo -e "       ${GREEN}✓ ${svc} 已重启${NC}" || echo -e "       ${YELLOW}⚠ ${svc} 重启失败${NC}"
        fi
    done
    echo ""

    # ---------- 5. 汇总报告 ----------
    echo "  -------------------------------------------------------------"
    echo -e "  清理完成，本次共释放: ${GREEN}${total_freed} MB${NC}"
    echo "  详细报告: $cleanup_report"
    echo "  -------------------------------------------------------------"
    echo ""
    echo "  总计释放磁盘空间: ${total_freed} MB" >> "$cleanup_report"
    echo "========================================" >> "$cleanup_report"
    log_action "磁盘智能清理与自愈完成，释放 ${total_freed} MB"
    read -p "  按回车键返回..." _
}

run_patrol_menu() {
    clear
    show_brand
    section_header "自动巡检 | 一键系统健康检查"
    loading "正在执行系统巡检"
    run_patrol
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo -e "  ${GREEN}✓ 巡逻完成：系统状态正常。${NC}"
    else
        echo -e "  ${RED}⚠ 巡逻完成：发现异常项，请查看报告。${NC}"
    fi
    log_action "执行自动巡逻"
    status_bar "巡检完成"
    printf "  ${CYAN}»${NC} 按回车键返回主菜单..."
    read -r _
}

about_project() {
    clear
    show_brand
    section_header "关于项目 | 技术架构与团队"
    echo -e "  ${DGRAY}团队${NC}: 翟浩雯、李薇"
    echo -e "  ${DGRAY}技术${NC}: Bash, grep/awk/sed, 并发进程, 日志分析,"
    echo -e "         系统监控, 配置解耦, 自动巡逻"
    echo -e "  ${DGRAY}架构${NC}: 模块化设计，SSH 分布式管控，"
    echo -e "         JSON/Markdown 双格式报告输出"
    status_bar "项目信息"
    printf "  ${CYAN}»${NC} 按回车键返回主菜单..."
    read -r _
}

patrol_daemon_menu() {
    while true; do
        CHOICE=$(wt_menu "模块 6 | 后台守护" \
            "定时巡逻守护进程管理" \
            "1" "启动后台巡逻守护进程" \
            "2" "停止后台巡逻守护进程" \
            "3" "查看守护进程状态" \
            "0" "返回主菜单")
        case "$CHOICE" in
            1) wt_msgbox "启动守护" "警告：此操作需要 root 权限，请确保已配置 systemd 服务文件。" 10 50; run_patrol_daemon ;;
            2) stop_patrol_daemon ;;
            3) patrol_daemon_status ;;
            0|"") return ;;
        esac
    done
}

show_brand() {
    echo ""
    echo -e "  ${CYAN_BOX}  DiagMaster v2.0 | 服务器多维智能诊断运维平台  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

section_header() {
    echo -e "\n  ${BOLD}${YELLOW}▸ ${1}${NC}\n"
}

loading() {
    local text="${1:-处理中}"
    echo -e -n "  ${DGRAY}[${LGRAY}INFO${DGRAY}]${NC} ${text}"
    for i in 1 2 3; do
        sleep 0.12
        echo -n "."
    done
    echo -e " ${GREEN}✓${NC}\n"
}

status_bar() {
    local status="${1:-正常}"
    echo ""
    echo -e "  ${DGRAY}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${NC}"
    echo -e "  ${DGRAY}●${NC} 系统状态: ${GREEN}[${status}]${NC}   ${DGRAY}⏰${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "  ${DGRAY}💡 提示: 输入功能编号并回车执行; 返回主菜单请输 0 或 q${NC}"
    echo ""
}

main_menu() {
    while true; do
        CHOICE=$(wt_menu "DiagMaster v2.0 | 服务器多维智能诊断运维平台" "请选择功能编号进行操作:" \
            "1" "节点资产 | 分布式服务器资产与 SSH 管控" \
            "2" "性能监控 | CPU/内存/磁盘 多进程并行采集" \
            "3" "安全审计 | 内核日志清洗与风险评分" \
            "4" "磁盘清理 | 智能清理与自愈修复" \
            "5" "自动巡检 | 一键系统健康检查" \
            "6" "后台守护 | 定时巡逻守护进程管理" \
            "7" "关于项目 | 技术架构与团队介绍" \
            "0" "安全退出系统")
        case "$CHOICE" in
            1) node_management ;;
            2) run_collector ;;
            3) run_log_audit ;;
            4) disk_cleanup ;;
            5) run_patrol_menu ;;
            6) patrol_daemon_menu ;;
            7) about_project ;;
            0|"") wt_msgbox "感谢使用" "感谢使用 DiagMaster，再见！" 8 40; clear; exit 0 ;;
        esac
    done
}

# ========== 命令行参数处理 ==========

print_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  (无参数)          进入交互式主菜单"
    echo "  --daemon           启动后台巡逻守护进程"
    echo "  --stop             停止后台巡逻守护进程"
    echo "  --status           查看巡逻守护进程状态"
    echo "  --patrol           执行一次性巡逻检查"
    echo "  -h, --help         显示帮助信息"
}

# 若传入命令行参数则直接执行相应操作，不需要认证
if [ $# -gt 0 ]; then
    case "$1" in
        --daemon)
            source "$ROOT_DIR/modules/patrol.sh"
            run_patrol_daemon
            exit $?
            ;;
        --stop)
            source "$ROOT_DIR/modules/patrol.sh"
            stop_patrol_daemon
            exit $?
            ;;
        --status)
            source "$ROOT_DIR/modules/patrol.sh"
            patrol_daemon_status
            exit $?
            ;;
        --patrol)
            source "$ROOT_DIR/modules/patrol.sh"
            run_patrol
            exit $?
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
fi

# ========== 安全认证 ==========
show_brand
echo -e "${YELLOW}[安全认证]${NC}"
read -p "请输入管理员账户: " u
if [[ "$u" != "$ADMIN_USER" ]]; then
    echo -e "${RED}[安全拦截] 非法账户！${NC}"
    log_action "安全审计警告: 非法账户 [$u] 尝试登录"
    exit 1
fi
echo -e "${GREEN}[账户验证通过]${NC}"
read -s -p "请输入安全密码: " p
echo
if [[ "$p" == "$ADMIN_PASS" ]]; then
    log_action "管理员 [$u] 成功登录"
    main_menu
else
    echo -e "${RED}[安全拦截] 密码错误！${NC}"
    log_action "安全审计警告: 密码校验失败"
    exit 1
fi
