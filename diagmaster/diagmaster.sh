#!/usr/bin/env bash
set -euo pipefail

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
NC='\033[0m'

header() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}    DiagMaster 服务器一键多维智能诊断工具箱 v2.0   ${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

node_management() {
    while true; do
        header
        echo -e "${YELLOW}--- [模块 1] 受控服务器节点资产管理 ---${NC}"
        echo " 1) 查看当前受控节点列表"
        echo " 2) 新增受控服务器节点"
        echo " 3) 删除失效服务器节点"
        echo " 4) 返回主菜单"
        read -p "请输入子菜单指令 (1-4): " nc
        case "$nc" in
            1)
                header
                printf "%-5s | %-20s\n" "ID" "NODE_IP_OR_NAME"
                echo "-----------------------------------"
                nl -w2 -s'   | ' "$NODE_DB"
                read -p "按回车键继续..." _
                ;;
            2)
                read -p "请输入要添加的服务器IP/名称: " ip
                if [ -n "$ip" ]; then
                    echo "$ip" >> "$NODE_DB"
                    log_action "新增受控节点: $ip"
                    echo -e "${GREEN}✓ 节点添加成功。${NC}"
                fi
                sleep 1
                ;;
            3)
                read -p "请输入要删除的节点关键字: " kw
                if [ -n "$kw" ]; then
                    grep -v "$kw" "$NODE_DB" > "$ROOT_DIR/data/temp_node" && mv "$ROOT_DIR/data/temp_node" "$NODE_DB"
                    log_action "删除了节点关键字: $kw"
                    echo -e "${YELLOW}✓ 相关节点已移除。${NC}"
                fi
                sleep 1
                ;;
            4) return ;;
        esac
    done
}

run_collector() {
    header
    echo -e "${YELLOW}--- [模块 2] 多进程性能指标并行监控 ---${NC}"
    if [ -f "$ROOT_DIR/modules/collector.sh" ]; then
        bash "$ROOT_DIR/modules/collector.sh"
    else
        echo "collector.sh 不存在，直接内联采集"
        DATA_DIR="$ROOT_DIR/data"
        mkdir -p "$DATA_DIR"
        ( top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' > "$DATA_DIR/cpu.tmp" ) &
        ( free -m | awk '/Mem:/ {print $3/$2*100}' > "$DATA_DIR/mem.tmp" ) &
        ( df -h / | awk 'NR==2 {print $5}' | sed 's/%//' > "$DATA_DIR/disk.tmp" ) &
        wait
    fi
    local cpu_val; cpu_val=$(cat "$ROOT_DIR/data/cpu.tmp" 2>/dev/null || echo "0")
    local mem_val; mem_val=$(cat "$ROOT_DIR/data/mem.tmp" 2>/dev/null || echo "0")
    local disk_val; disk_val=$(cat "$ROOT_DIR/data/disk.tmp" 2>/dev/null || echo "0")
    echo " CPU: ${cpu_val}%  | 内存: ${mem_val}%  | 磁盘: ${disk_val}%"
    log_action "执行多进程性能指标采集"
    read -p "按回车键返回..." _
}

run_log_audit() {
    header
    echo -e "${YELLOW}--- [模块 3] 内核日志清洗与安全审计 ---${NC}"
    if [ -f "$ROOT_DIR/modules/log_analyzer.sh" ]; then
        bash "$ROOT_DIR/modules/log_analyzer.sh"
    else
        echo "log_analyzer.sh 不存在，执行内联分析"
        mkdir -p "$ROOT_DIR/data"
        dmesg 2>/dev/null | grep -c -i "out of memory" > "$ROOT_DIR/data/oom_count.tmp" || echo "0" > "$ROOT_DIR/data/oom_count.tmp"
        grep -c "Failed password" /var/log/auth.log 2>/dev/null > "$ROOT_DIR/data/ssh_fail.tmp" || echo "0" > "$ROOT_DIR/data/ssh_fail.tmp"
    fi
    local oom_count; oom_count=$(cat "$ROOT_DIR/data/oom_count.tmp" 2>/dev/null || echo "0")
    local ssh_fail; ssh_fail=$(cat "$ROOT_DIR/data/ssh_fail.tmp" 2>/dev/null || echo "0")
    echo " OOM 事件: ${oom_count} 次  | SSH 爆破尝试: ${ssh_fail} 次"
    local report_path="$ROOT_DIR/reports/diag_report_$(date +%Y%m%d_%H%M%S).md"
    cat << EOF > "$report_path"
# DiagMaster 自动化审计报告
- 审计时间: $(date)
- 内核OOM频次: ${oom_count}
- SSH风险频次: ${ssh_fail}
EOF
    echo -e "${GREEN}✓ 报告已输出至: $report_path${NC}"
    log_action "执行高级日志审计"
    read -p "按回车键返回..." _
}

disk_cleanup() {
    header
    echo -e "${YELLOW}--- [模块 4] 磁盘临时文件清理 ---${NC}"
    read -p "确认清理 /tmp 下临时文件? (y/n): " c
    if [[ "$c" == "y" ]]; then
        rm -rf /tmp/* 2>/dev/null || true
        echo -e "${GREEN}✓ 清理完成。${NC}"
        log_action "执行磁盘清理"
    else
        echo "操作已取消。"
    fi
    read -p "按回车键返回..." _
}

run_patrol_menu() {
    header
    echo -e "${YELLOW}--- [模块 5] 自动巡逻巡检 ---${NC}"
    # 调用 patrol.sh 中的 run_patrol 函数
    # 临时禁用 set -e，因为 run_patrol 在发现异常时返回非零，
    # 防止 set -e 导致脚本直接退出
    set +e
    run_patrol
    local ret=$?
    set -e
    if [ $ret -eq 0 ]; then
        echo -e "${GREEN}✓ 巡逻完成：系统状态正常。${NC}"
    else
        echo -e "${RED}⚠ 巡逻完成：发现异常项，请查看报告。${NC}"
    fi
    log_action "执行自动巡逻"
    read -p "按回车键返回主菜单..." _
}

about_project() {
    header
    echo -e "${YELLOW}--- [模块 7] 关于项目 ---${NC}"
    echo " 团队: 翟浩雯、李薇"
    echo " 技术: Bash, grep/awk/sed, 并发进程, 日志分析,"
    echo "        系统监控, 配置解耦, 自动巡逻"
    read -p "按回车键返回..." _
}

main_menu() {
    while true; do
        header
        echo " 1) 服务器节点资产管理"
        echo " 2) 多进程性能指标并行监控"
        echo " 3) 内核日志清洗与安全审计"
        echo " 4) 智能化磁盘清理与自愈"
        echo " 5) 启动自动巡逻巡检"
        echo " 6) 后台巡逻守护（daemon）"
        echo " 7) 关于项目技术架构与分工"
        echo " 8) 安全退出"
        read -p "请选择 (1-8): " ch
        case "$ch" in
            1) node_management ;;
            2) run_collector ;;
            3) run_log_audit ;;
            4) disk_cleanup ;;
            5) run_patrol_menu ;;
            6) patrol_daemon_menu ;;
            7) about_project ;;
            8) echo "感谢使用 DiagMaster。"; exit 0 ;;
            *) echo "无效指令"; sleep 1 ;;
        esac
    done
}

patrol_daemon_menu() {
    while true; do
        header
        echo -e "${YELLOW}--- [模块 6] 后台巡逻守护进程管理 ---${NC}"
        echo " 1) 启动后台巡逻守护进程"
        echo " 2) 停止后台巡逻守护进程"
        echo " 3) 查看守护进程状态"
        echo " 4) 返回主菜单"
        read -p "请输入子菜单指令 (1-4): " nc
        case "$nc" in
            1)
                set +e
                run_patrol_daemon
                set -e
                read -p "按回车键返回..." _
                ;;
            2)
                set +e
                stop_patrol_daemon
                set -e
                read -p "按回车键返回..." _
                ;;
            3)
                set +e
                patrol_daemon_status
                set -e
                read -p "按回车键返回..." _
                ;;
            4) return ;;
            *) echo "无效指令"; sleep 1 ;;
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
header
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
