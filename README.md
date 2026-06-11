# DiagMaster 服务器一键多维智能诊断工具箱 v2.0

**DiagMaster** 是一个基于 Bash 的 Linux 服务器多维智能诊断工具箱，集成分布式节点管理、性能监控、安全审计、磁盘清理、自动巡检与后台守护进程管理，面向企业级 Linux 运维场景设计。

## 团队成员与分工

| 成员 | 负责模块 | 主要贡献 |
|------|----------|----------|
| 翟浩雯 | 模块 1（节点管理）+ 模块 6（后台守护） | SSH 分布式通信、节点资产库、systemd 服务封装 |
| 李薇 | 模块 2（性能监控）+ 模块 3（安全审计）+ 模块 4（磁盘清理） | 多进程并行采集、内核日志分析、磁盘清理自愈逻辑 |

## 功能概览

| 模块 | 功能 |
|------|------|
| 模块 1 - 节点管理 | 受控服务器资产库，支持新增/删除/测试 SSH 连接、批量远程诊断 |
| 模块 2 - 性能监控 | CPU / 内存 / 磁盘 / 负载并行采集，颜色阈值告警 |
| 模块 3 - 安全审计 | 内核日志清洗、SSH 爆破检测、攻击模式识别、风险评分、JSON/Markdown 报告 |
| 模块 4 - 磁盘清理 | 扫描 /tmp、~/.cache、Trash、apt 缓存、旧内核、Docker 悬空镜像；可执行安全删除与自愈修复 |
| 模块 5 - 自动巡检 | 一键健康检查，汇总指标并给出告警 |
| 模块 6 - 后台守护 | systemd 定时巡逻守护进程，支持启停与状态查询 |

## 快速开始

```bash
# 安装（赋予执行权限）
make install

# 启动交互式主菜单
./diagmaster/diagmaster.sh

# 命令行模式（适合自动化）
./diagmaster/diagmaster.sh --patrol   # 一次性巡检
./diagmaster/diagmaster.sh --daemon   # 启动后台守护
./diagmaster/diagmaster.sh --stop     # 停止后台守护
./diagmaster/diagmaster.sh --status   # 查看守护状态
```

## 配置说明

核心配置位于 `diagmaster/config/diag.conf`，可覆盖以下默认值：

- `CPU_WARN_THRESHOLD` / `MEM_WARN_THRESHOLD` / `DISK_WARN_THRESHOLD`：告警阈值
- `ADMIN_USER` / `ADMIN_PASS`：管理账户认证
- `AUDIT_DAYS`：审计日志回溯天数
- `ENABLE_AUTO_HEAL`：磁盘清理自动修复开关
- `PATROL_INTERVAL`：后台守护轮询间隔（秒）

## 技术架构

- 纯 Bash 实现，零外部 Python/Go 依赖
- 模块化设计：`diagmaster.sh`（主入口）+ `modules/*.sh`（业务模块）+ `lib/utils.sh`（公共库）
- 多进程并行采集（子进程后台执行，结果合并）
- JSON / Markdown 双格式审计报告输出
- systemd 服务模板封装，支持 daemon 化运行

## 目录结构

```text
linux-shell-/
├── diagmaster/
│   ├── diagmaster.sh          # 主入口
│   ├── config/
│   │   └── diag.conf          # 可配置项
│   ├── modules/
│   │   ├── collector.sh       # 性能采集
│   │   ├── log_analyzer.sh    # 安全审计
│   │   └── patrol.sh          # 自动巡检/守护
│   ├── lib/
│   │   └── utils.sh           # SSH 与公共函数
│   ├── data/                  # 运行时数据
│   ├── logs/                  # 日志
│   └── reports/               # 审计与清理报告
└── Makefile                   # 安装入口
```

## 清理运行时文件

```bash
make clean
```

## 许可证

课程项目，仅供学习交流。
