# DiagMaster — 服务器一键多维智能诊断工具箱

> 不会 Linux 也能用的服务器"体检仪"。像量体温一样简单，输入几个数字，自动帮你检查服务器哪里出毛病了。

- **版本**：v3.0
- **开发团队**：翟浩雯（组长）、李薇（组员）
- **技术底座**：纯 Bash 5.x，零外部 Python/Go 依赖，Ubuntu / WSL 开箱即用

---

## 团队成员与分工

| 成员 | 角色 | 具体任务 |
|------|------|----------|
| **翟浩雯** | 组长 | 主程序框架 `diagmaster.sh`、模块1（节点资产）分布式SSH管控、模块4（磁盘清理）自愈修复、模块5（自动巡检）、模块6（后台守护）systemd服务封装、公共库 `lib/utils.sh`、项目 README 与答辩文档 |
| **李薇** | 组员 | 模块2（性能监控）`modules/collector.sh` 多进程并行采集、模块3（安全审计）`modules/log_analyzer.sh` 内核日志清洗与风险评分、测试用例 `tests/`、配置文件 `config/diag.conf` 维护 |

> 规范说明：两名成员均承担完整模块开发 + 测试 + 文档工作，确保每人独立闭环。

---

## 30 秒快速上手

```bash
# 第 1 步：进入项目目录
cd ~/linux-shell-/diagmaster

# 第 2 步：一键安装（赋予执行权限）
chmod +x diagmaster.sh modules/*.sh tests/*.sh

# 第 3 步：启动主程序
bash diagmaster.sh
```

默认账号：`admin`，默认密码：`12345`（演示用，正式使用请修改 `config/diag.conf`）。

---

## 主菜单功能速览

```
  🚀 快速操作入口
  1) 节点资产    2) 性能监控    3) 安全审计    4) 磁盘清理
  5) 自动巡检    6) 后台守护    7) 关于项目    0) 安全退出
```

| 编号 | 模块 | 核心用途 |
|------|------|----------|
| 1 | **节点资产** | 分布式服务器资产库，新增/删除/测试 SSH 连接、批量远程诊断 |
| 2 | **性能监控** | CPU/内存/磁盘/负载多进程并行采集，颜色阈值告警 |
| 3 | **安全审计** | 内核日志清洗、SSH 爆破检测、攻击模式识别、风险评分 |
| 4 | **磁盘清理** | 扫描 /tmp、~/.cache、Trash、apt 缓存、旧内核、Docker 悬空镜像；安全删除 + 自愈修复 |
| 5 | **自动巡检** | 一键健康检查，6 项指标汇总，异常即告警 |
| 6 | **后台守护** | systemd 定时巡逻守护进程，支持启停与状态查询 |
| 7 | **关于项目** | 技术架构、团队成员、版本信息 |

---

## 模块详解

### 模块 1 - 节点资产（Distributed Node Management）

**负责人**：翟浩雯

**解决的问题**：运维人员常常需要同时管理多台服务器，手工逐台 SSH 登录检查效率极低。

**核心功能**：
- 节点资产库（`data/nodes.txt`）持久化管理，支持新增、删除、查看
- `test_ssh_connection` / `test_ssh_key_auth` / `verify_diagmaster_on_node` 三重连接验证
- 批量远程诊断（`batch_remote_diagnose`）：多节点并行采集，结果统一汇总
- 支持 `localhost` 免验证，远程节点超时 1 秒快速检测

**典型场景**：5 台服务器批量巡检，原来需要 5 次手动登录，现在一次菜单操作搞定。

---

### 模块 2 - 性能监控（Performance Collector）

**负责人**：李薇

**解决的问题**：服务器"卡了"但不知道是 CPU、内存还是磁盘引起的。

**核心功能**：
- `collect_remote` 函数封装，支持本地/远程统一调用
- 多进程并行采集（后台 `&` + `wait`），避免串行等待
- 颜色阈值告警：绿色（正常）、黄色（警告）、红色（危险）
- 支持自定义阈值（`config/diag.conf`）

**监控指标**：

| 指标 | 正常 | 警告 | 危险 |
|------|------|------|------|
| CPU | < 80% | 80%-95% | > 95% |
| 内存 | < 85% | 85%-95% | > 95% |
| 磁盘 | < 90% | 90%-95% | > 95% |
| 负载 | 视核数 | - | - |

---

### 模块 3 - 安全审计（Log Analyzer）

**负责人**：李薇

**解决的问题**：服务器被暴力破解、内核 OOM 等安全事件往往发生在深夜，人工检查日志来不及。

**核心功能**：
- 日志源自动检测（`detect_log_sources`），支持 auth.log / syslog / dmesg / journald
- OOM 事件分析（`analyze_oom`）、内核错误分析（`analyze_kernel_errors`）
- SSH 暴力破解检测（`analyze_ssh_bruteforce`），支持 Top 攻击 IP 提取
- 攻击模式识别：异常登录、端口扫描、用户枚举、权限提升、恶意软件特征
- 风险评分模型：每类事件加权计算总分，输出 低/中/高/严重 四级
- 双格式报告：Markdown（人工阅读）+ JSON（自动化对接）
- 白名单机制：`is_whitelisted_sudo` 支持路径前缀匹配，减少误报

**审计维度**：
1. 内核稳定性（OOM / Panic / Oops）
2. 认证安全（SSH 失败/成功、暴力破解）
3. 攻击模式（端口扫描、权限提升、恶意软件）
4. 用户行为（sudo 滥用、异常登录时间地点）

---

### 模块 4 - 磁盘清理（Disk Cleanup）

**负责人**：李薇

**解决的问题**：Linux 服务器磁盘满导致服务宕机，清理不当可能误删重要数据。

**核心功能**：
- 多源扫描（`scan_items` 数组驱动）：
  - 系统临时文件 `/tmp`（1 天前）
  - 用户缓存 `~/.cache`
  - 回收站 `~/.local/share/Trash`
  - apt 缓存 `/var/cache/apt/archives`
  - journal 日志（7 天前）
  - 旧内核（保留最近 2 个）
  - Docker 悬空镜像/缓存
- 风险分级：低/中/高三级，自动勾选低风险，中高风险需人工确认
- 安全删除：`grep` / `awk` 精确匹配，不遍历目录树
- 自愈修复（`self_heal`）：
  - `apt --fix-broken install` 修复依赖
  - `systemctl try-restart` 重启 cron / ssh / docker
- 清理报告：实时输出 + 日志记录（`reports/disk_cleanup_*.log`）

---

### 模块 5 - 自动巡检（Patrol）

**负责人**：翟浩雯

**解决的问题**：管理员无法时刻盯着服务器，需要定期自动体检。

**核心功能**：
- 6 项一键检查：CPU / 内存 / 磁盘 / 关键服务 / 关键进程 / 日志异常
- 阈值化判断：超过阈值立即标红，低于阈值显示绿色
- 结果汇总：正常显示 ✅ 系统状态正常，异常显示 ⚠️ 发现异常项
- 支持单次运行（菜单模式）和 daemon 模式（后台定时）

---

### 模块 6 - 后台守护（Patrol Daemon）

**负责人**：翟浩雯

**解决的问题**：单次巡检不够，需要定时自动执行。

**核心功能**：
- systemd 服务模板（`config/diagmaster-patrol.service`），适配 `%i` 实例名
- 环境变量驱动：`ENABLE_AUTO_HEAL`、`PATROL_INTERVAL`（默认 300 秒）
- 支持 `run_patrol_daemon` / `stop_patrol_daemon` / `patrol_daemon_status`
- 日志输出到 `logs/patrol_daemon.log`，便于审计追踪

---

## 配置说明

核心配置位于 `config/diag.conf`：

```bash
# 性能阈值（百分比）
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=85
DISK_WARN_THRESHOLD=90

# 管理账户（建议修改）
ADMIN_USER="admin"
ADMIN_PASS="12345"

# 审计回溯天数
AUDIT_DAYS=7

# 后台守护配置
ENABLE_AUTO_HEAL=true
PATROL_INTERVAL=300

# 检查项
SERVICES_TO_CHECK="sshd cron docker"
PROCESSES_TO_CHECK="sshd"
```

改完配置后无需重启，下次运行自动生效。

---

## 命令行模式

适合自动化脚本 / CI 调用：

```bash
# 一次性巡检（适合 cron）
./diagmaster.sh --patrol

# 启动后台守护（需 root）
sudo ./diagmaster.sh --daemon

# 停止守护
./diagmaster.sh --stop

# 查看状态
./diagmaster.sh --status

# 帮助
./diagmaster.sh --help
```

---

## 目录结构

```
diagmaster/
├── diagmaster.sh              # ★ 主入口，程序入口（~1229 行）
├── README.md                  # ★ 本文件
│
├── config/
│   ├── diag.conf              # ★ 核心配置文件（阈值/账号/开关）
│   └── diagmaster-patrol.service  # systemd 守护进程模板
│
├── modules/
│   ├── collector.sh           # 模块2：性能采集（CPU/内存/磁盘/负载）
│   ├── log_analyzer.sh        # 模块3：安全审计（日志清洗/风险评分/报告）
│   └── patrol.sh              # 模块5/6：自动巡检 + 后台守护
│
├── lib/
│   ├── utils.sh               # SSH 工具函数 + 公共工具（日志/颜色/阈值）
│   └── assert.sh              # 轻量级测试断言库
│
├── data/
│   ├── nodes.txt              # 受控节点列表（IP/hostname，每行一个）
│   ├── *.tmp                  # 临时数据文件（cpu/mem/disk/oom 等中间结果）
│   └── history/               # 历史采集数据缓存（collect_*.log）
│
├── logs/
│   ├── activity.log           # 操作日志（用户行为审计）
│   └── patrol_daemon.log      # 守护进程运行日志
│
├── reports/
│   ├── diag_report_*.md       # 安全审计报告（Markdown）
│   ├── diag_report_*.json     # 安全审计报告（JSON）
│   ├── patrol_*.md            # 自动巡逻报告
│   └── disk_cleanup_*.log     # 磁盘清理详细日志
│
├── backup/                    # 备份存档目录
│
├── docs/
│   ├── 项目报告.md            # 课程项目报告
│   ├── 软件使用说明书.md      # 软件使用说明书
│   └── 答辩PPT脚本.md         # 答辩PPT脚本
│
└── tests/
    ├── run_all_tests.sh          # 一键运行全部 75 个测试
    ├── test_patrol.sh            # 巡逻模块单元+集成+异常测试（20 例）
    ├── test_collector.sh         # 性能采集模块测试（9 例）
    ├── test_boundary.sh          # 边界条件测试（6 例）
    ├── test_auto.sh              # 自动化运行验证测试（4 例）
    ├── test_utils.sh             # 公共工具库测试（8 例）
    ├── test_log_analyzer.sh      # 安全审计模块测试（12 例）
    ├── test_integration_real.sh  # 真实环境集成冒烟测试（16 例：功能4+边界4+异常4+自动化4）
    ├── lib/
    │   └── mock_utils.sh         # 共享 Mock 工具库
    └── screenshots/              # 测试截图存档
```

---

## 技术架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   diagmaster.sh │◄──►│   modules/*.sh  │◄──►│   lib/utils.sh  │
│   (主入口/UI)   │    │  (业务逻辑)     │    │  (SSH/工具函数) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
  │  data/      │      │  logs/      │      │  reports/   │
  │  (节点/缓存) │      │  (活动/守护) │      │  (审计/巡检) │
  └─────────────┘      └─────────────┘      └─────────────┘
```

**设计原则**：
- 配置与代码彻底分离（`diag.conf` 覆盖所有变量）
- 模块化单体：主入口 + 3 个业务模块 + 1 个公共库，职责清晰
- 多进程并行：后台 `&` + `wait` 实现采集并发，避免串行阻塞
- 双格式输出：Markdown（人工）+ JSON（自动化），一次生成两种用途

---

## 测试

项目采用双层测试体系，共 75 个自动化测试用例：

**Mock 单元测试（59 例）**：使用 Mock 机制模拟系统命令输出，快速验证逻辑正确性

**真实环境冒烟测试（16 例）**：直接调用真实系统命令，验证在当前 OS 上的实际可用性，覆盖功能/边界/异常/自动化四类场景

```bash
# 一键运行全部测试
bash tests/run_all_tests.sh

# 单独运行某类测试
bash tests/test_patrol.sh            # 巡逻模块测试（20 例）
bash tests/test_collector.sh         # 性能采集模块测试（9 例）
bash tests/test_boundary.sh          # 边界条件测试（6 例）
bash tests/test_auto.sh              # 自动化运行验证测试（4 例）
bash tests/test_utils.sh             # 公共工具库测试（8 例）
bash tests/test_log_analyzer.sh      # 安全审计模块测试（12 例）
bash tests/test_integration_real.sh  # 真实环境冒烟测试（16 例）
```

---

## 常见问题

**Q: 运行时报 "Permission denied"？**
```bash
chmod +x diagmaster.sh modules/*.sh tests/*.sh
```

**Q: 忘记密码？**
编辑 `config/diag.conf`，修改 `ADMIN_PASS` 即可，或删除该行回退默认密码 `12345`。

**Q: 想检查更多服务？**
在 `config/diag.conf` 中修改 `SERVICES_TO_CHECK="sshd cron nginx mysql"`。

**Q: 会搞坏服务器吗？**
不会。脚本只做**读取和报告**，唯一的写入操作是清理 `/tmp`（需手动确认 y/n）和生成报告文件。

---

## 开发信息

- **开发环境**：Ubuntu 22.04 / WSL2
- **代码规模**：主入口 ~1229 行，3 个业务模块 + 公共库 ~2200 行，总计 ~3400 行
- **测试覆盖**：75 个自动化测试用例（Mock 59 + 真实环境 16）
- **提交规范**： Conventional Commits（feat/fix/docs/perf/chore）

---

## 许可证

课程项目，仅供学习交流。

> 用最简单的方式，守护你的服务器 🛡️