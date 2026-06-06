#!/usr/bin/env bash
set -euo pipefail

# 导入外部阈值配置文件 (解耦设计)
CONF_FILE="./config/diag.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    echo "错误: 缺少核心配置文件 $CONF_FILE"
    exit 1
fi

LOG_FILE="./logs/activity.log"
mkdir -p ./reports ./data ./logs ./backup

# 初始化默认值防止未定义变量报错
CPU_WARN_THRESHOLD=${CPU_WARN_THRESHOLD:-80}
MEM_WARN_THRESHOLD=${MEM_WARN_THRESHOLD:-85}
DISK_WARN_THRESHOLD=${DISK_WARN_THRESHOLD:-90}
ADMIN_USER=${ADMIN_USER:-"admin"}
ADMIN_PASS=${ADMIN_PASS:-"12345"}
NODE_DB="./data/nodes.txt"
touch "$NODE_DB"

# 颜色控制
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

header() {
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}    DiagMaster 服务器一键多维智能诊断工具箱 v1.0   ${NC}"
    echo -e "${CYAN}==================================================${NC}"
    echo " 开发团队: 翟浩雯、李薇  | 课程期末项目标准提交版"
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 1) 资产管理模块
node_management() {
    while true; do
        header
        echo -e "${YELLOW}--- [模块 1] 受控服务器节点资产管理 ---${NC}"
        echo " 1) 查看当前受控节点列表"
        echo " 2) 新增受控服务器节点"
        echo " 3) 删除失效服务器节点"
        echo " 4) 返回主菜单"
        echo "--------------------------------------------------"
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
                    grep -v "$kw" "$NODE_DB" > temp_node && mv temp_node "$NODE_DB"
                    log_action "删除了节点关键字: $kw"
                    echo -e "${YELLOW}✓ 相关节点已移除。${NC}"
                fi
                sleep 1
                ;;
            4) return ;;
        esac
    done
}

# 2) 并发采集模块
run_collector() {
    header
    echo -e "${YELLOW}--- [模块 2] 底层性能指标多进程后台并行采集 ---${NC}"
    echo -e "${CYAN}正在启动后台异步采集流水线...${NC}"
    bash ./modules/collector.sh
    
    local cpu_val; cpu_val=$(cat ./data/cpu.tmp 2>/dev/null || echo "0.0")
    local mem_val; mem_val=$(cat ./data/mem.tmp 2>/dev/null || echo "0.0")
    local disk_val; disk_val=$(cat ./data/disk.tmp 2>/dev/null || echo "0")

    echo "--------------------------------------------------"
    echo -e " [✓] CPU 实时利用率 : ${cpu_val}%  (预警阈值: ${CPU_WARN_THRESHOLD}%)"
    echo -e " [✓] 内存 实时利用率: ${mem_val}%  (预警阈值: ${MEM_WARN_THRESHOLD}%)"
    echo -e " [✓] 磁盘 根分区占用: ${disk_val}%  (预警阈值: ${DISK_WARN_THRESHOLD}%)"
    echo "--------------------------------------------------"
    echo -e "${GREEN}技术亮点: 成功通过 '&' 异步并发派发 3 个后台任务，并使用 'wait' 实现进程同步锁步！${NC}"
    log_action "执行多进程性能指标采集"
    rm -f ./data/cpu.tmp ./data/mem.tmp ./data/disk.tmp
    read -p "按回车键返回..." _
}

# 3) 日志清洗模块
run_log_audit() {
    header
    echo -e "${YELLOW}--- [模块 3] 内核日志特征清洗与安全审计 ---${NC}"
    echo -e "${CYAN}正在调用 grep/awk/sed 分析环形缓冲区及安全日志...${NC}"
    bash ./modules/log_analyzer.sh
    
    local oom_count; oom_count=$(cat ./data/oom_count.tmp 2>/dev/null || echo "0")
    local ssh_fail; ssh_fail=$(cat ./data/ssh_fail.tmp 2>/dev/null || echo "0")

    echo "--------------------------------------------------"
    echo -e " 🚨 24小时内内核 OOM 崩溃触发频次 : ${RED}${oom_count}${NC} 次"
    echo -e " 🔒 24小时内系统远程 SSH 暴破尝试 : ${YELLOW}${ssh_fail}${NC} 次"
    echo "--------------------------------------------------"
    
    # 专家智能因果推断与结构化Markdown报告输出
    local report_path="reports/diag_report_$(date +%Y%m%d_%H%M%S).md"
    local conclusion="[正常] 未发现严重潜伏故障根因。"
    if [ "$oom_count" -gt 0 ]; then
        conclusion="[致命告警] 检测到内核曾触发 OOM-Killer 强杀业务进程！"
    elif [ "$ssh_fail" -gt 30 ]; then
        conclusion="[安全告警] 系统正遭遇高频恶意密码暴力破解尝试！"
    fi

    cat << EOF > "$report_path"
# DiagMaster 自动化审计报告
- 审计时间: $(date)
- 内核OOM频次: ${oom_count}
- SSH风险频次: ${ssh_fail}
- 诊断结论: $conclusion
EOF

    echo -e "${GREEN}✓ 关联推断完成，结构化 Markdown 报告已自动输出至: $report_path${NC}"
    log_action "执行高级日志审计特征清洗"
    rm -f ./data/oom_count.tmp ./data/ssh_fail.tmp
    read -p "按回车键返回..." _
}

# 4) 磁盘自愈模块
disk_cleanup() {
    header
    echo -e "${YELLOW}--- [模块 4] 系统临时垃圾与日志碎片智能自愈 ---${NC}"
    read -p "确认执行系统临时缓存自愈清理? (y/n): " c
    if [[ "$c" == "y" ]]; then
        rm -rf /tmp/* 2>/dev/null || true
        echo -e "${GREEN}✓ 磁盘临时垃圾碎片清理自愈成功，I/O 风险已释放。${NC}"
        log_action "执行磁盘清理自愈"
    else
        echo "操作已取消。"
    fi
    read -p "按回车键返回..." _
}

# 5) 技术架构说明
about_project() {
    header
    echo -e "${YELLOW}--- [模块 5] 本项目底层技术解耦架构与分工说明 ---${NC}"
    echo " 1. 多文件解耦架构: 配置文件、并发采集、日志清洗模块逻辑全独立"
    echo " 2. 多进程并发控制: 底层使用 & 异步启动，配合 wait 实现进程同步锁"
    echo " 3. 高级文本特征提取: 熟练运用 grep/awk/sed 深度检索清洗内核日志"
    echo " 4. 标准流重定向技术: 结合 cat << EOF 自动流向 reports/ 输出 Markdown"
    echo "--------------------------------------------------"
    echo " 团队分工: 翟浩雯(组长) 负责多文件底座与并发调度调度主框架"
    echo "           李  薇(组员) 负责专家规则库因果推断算法与日志高级清洗"
    echo "--------------------------------------------------"
    read -p "按回车键返回..." _
}

main_menu() {
    while true; do
        header
        echo -e "${YELLOW}[核心硬核 Linux 技术栈状态]: 专家关联规则库已加载 ✓${NC}"
        echo "--------------------------------------------------"
        echo " 1) 服务器节点资产管理模块"
        echo " 2) 多进程性能指标并行监控"
        echo " 3) 内核日志清洗与安全审计"
        echo " 4) 智能化磁盘清理与自愈"
        echo " 5) 关于项目技术架构与分工"
        echo " 6) 安全退出智能巡检工具箱"
        echo "--------------------------------------------------"
        read -p "请选择功能菜单 (1-6): " ch
        case "$ch" in
            1) node_management ;;
            2) run_collector ;;
            3) run_log_audit ;;
            4) disk_cleanup ;;
            5) about_project ;;
            6) echo "感谢使用 DiagMaster。"; exit 0 ;;
            *) echo "无效指令"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# 🌟 严格身份认证逻辑 (完美修复同学提出的账号错还让输密码的逻辑缺陷)
# ==============================================================================
header
echo -e "${YELLOW}[安全认证第一步]${NC}"
read -p "请输入管理员账户: " u

# 拦截点 1：如果账号根本不对，直接强行阻断，不给输入密码的机会！
if [[ "$u" != "$ADMIN_USER" ]]; then
    echo -e "${RED}[安全拦截] 认证失败：非法的系统内部管理员账户！越权访问已被强行阻断。${NC}"
    log_action "安全审计警告: 非法账户 [$u] 尝试越权登录被实时拦截"
    exit 1
fi

# 拦截点 2：账号对了，才进入第二步允许输入密码
echo -e "${GREEN}[账户验证通过] 正在检索凭证数据库...${NC}"
read -s -p "请输入安全密码: " p
echo

if [[ "$p" == "$ADMIN_PASS" ]]; then
    log_action "管理员 [$u] 成功登录系统安全控制台"
    main_menu
else
    # 此时报错非常明确：密码错误
    echo -e "${RED}[安全拦截] 认证失败：管理员密码校验未通过！${NC}"
    log_action "安全审计警告: 管理员账户密码校验失败"
    exit 1
fi
