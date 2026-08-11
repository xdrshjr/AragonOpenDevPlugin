# InkClaw 运维工具集

本目录（`ops/`）提供 InkClaw 项目的生产级服务管理工具，包括 systemd 服务注册、健康检查看门狗、自动重启、日志轮转和状态查询。所有脚本均面向 Ubuntu Linux 服务器环境设计。

## 前提条件

- **操作系统**: Ubuntu 20.04 / 22.04 LTS
- **运行环境**: Node.js 18+、Python 3.8+
- **项目状态**: 已通过 `deployment.sh` 或手动完成构建（存在 `out/` 和 `backend/.venv/`）
- **权限要求**: 安装/卸载需要 `sudo` 权限；状态查询无需 `sudo`

## 快速开始

### 1. 安装依赖

```bash
# 在当前 conda/venv 环境下安装所有依赖（Python + Node + Playwright + VNC）
# 不需要 sudo（系统依赖部分会自动请求 sudo）
./ops/install-deps.sh

# 也可以只安装某一类依赖
./ops/install-deps.sh --only python      # 仅 Python 包
./ops/install-deps.sh --only node        # 仅 Node.js 包
./ops/install-deps.sh --only playwright  # 仅 Playwright 浏览器
./ops/install-deps.sh --only vnc         # 仅 VNC 依赖

# 无 sudo 环境下跳过系统包
./ops/install-deps.sh --skip-system
```

### 2. 构建项目

```bash
npm run build
```

### 3. 注册系统服务

```bash
# 注册 systemd 服务 + 启用看门狗 + 配置日志轮转 + 配置 Nginx
sudo ./ops/install.sh --domain=inkclaw.top

# 或在 config.env 中设置 NGINX_DOMAIN 后直接运行
sudo ./ops/install.sh

# 跳过 Nginx 配置（手动管理）
sudo ./ops/install.sh --no-nginx
```

> **重要**: Nginx 反向代理配置包含 SSE/长连接支持（`proxy_buffering off`、`proxy_read_timeout 3600s`）。
> 没有这些设置，Agent 在执行长时间任务时会被 Nginx 中断连接。

### 卸载

```bash
# 停止服务、移除 systemd unit 文件、清理相关配置
sudo ./ops/uninstall.sh
```

### 查看状态

```bash
# 查看所有服务的运行状态（无需 sudo）
./ops/status.sh
```

### 查看日志

```bash
# 查看所有服务最近 50 行日志
./ops/logs.sh

# 查看前端日志
./ops/logs.sh frontend

# 查看后端最近 100 行日志
./ops/logs.sh backend -n 100

# 实时跟踪前端日志
./ops/logs.sh frontend -f

# 查看所有服务最近 20 行日志
./ops/logs.sh all -n 20

# 查看看门狗日志
./ops/logs.sh watchdog
```

## 文件结构

```
ops/
├── README.md                    # 本说明文件
├── config.env                   # 可配置参数（端口、检查频率、阈值等）
├── install-deps.sh              # 依赖安装脚本（Python/Node/Playwright/VNC）
├── install.sh                   # systemd 服务注册脚本
├── uninstall.sh                 # 一键卸载脚本
├── status.sh                    # 服务状态查询脚本
├── logs.sh                      # 服务日志查看脚本
├── healthcheck.sh               # 看门狗健康检查脚本
└── templates/
    ├── inkclaw-backend.service  # Flask 后端 systemd unit 模板
    ├── inkclaw-frontend.service # Next.js 前端 systemd unit 模板
    ├── inkclaw-watchdog.service # 看门狗 oneshot service 模板
    ├── inkclaw-watchdog.timer   # 看门狗 systemd timer 模板
    ├── inkclaw-logrotate        # logrotate 日志轮转配置模板
    ├── inkclaw-nginx            # Nginx 反向代理模板（HTTPS）
    └── inkclaw-nginx-http       # Nginx 反向代理模板（仅 HTTP）
```

### 各文件用途

| 文件 | 用途 |
|------|------|
| `config.env` | 集中配置端口号、看门狗检查间隔/阈值、日志轮转参数。修改后需重新运行 `install.sh` 生效 |
| `install.sh` | 读取 `config.env`，将模板中的 `{{VAR}}` 占位符替换为实际值，生成 systemd unit 文件并注册服务 |
| `uninstall.sh` | 停止所有 InkClaw 服务，移除 systemd unit 文件和 logrotate 配置，清理状态文件 |
| `status.sh` | 显示服务运行状态、端口监听、健康检查、看门狗状态、失败计数、最近重启记录和日志 |
| `logs.sh` | 查看 systemd 服务日志，支持按服务筛选、指定行数、实时跟踪（`-f`）。无需 sudo |
| `healthcheck.sh` | 被看门狗 timer 定时触发，对后端和前端执行 HTTP 健康检查，连续失败达阈值后自动重启服务 |
| `templates/` | systemd unit、logrotate 和 Nginx 的模板文件，包含 `{{变量}}` 占位符，由 `install.sh` 渲染 |

## 配置说明

配置文件位于 `ops/config.env`，修改后需重新执行 `sudo ./ops/install.sh` 使改动生效。

```bash
# 端口配置
BACKEND_PORT=5000          # Flask 后端监听端口
FRONTEND_PORT=3000         # Next.js 前端监听端口

# Nginx 反向代理（留空则跳过自动配置）
NGINX_DOMAIN=""            # 例如 "inkclaw.top www.inkclaw.top"
NGINX_SITE_NAME="inkclaw"  # /etc/nginx/sites-available/ 中的文件名

# 看门狗配置
WATCHDOG_INTERVAL=60       # 健康检查间隔（秒）
WATCHDOG_FAIL_THRESHOLD=3  # 连续失败多少次后触发重启
WATCHDOG_STATE_DIR=/tmp    # 失败计数器文件存放目录

# 日志轮转配置
LOG_DIR=logs               # 日志目录（相对于项目根目录）
LOG_MAX_SIZE=50M           # 单个日志文件超过此大小时进行轮转
LOG_ROTATE_COUNT=7         # 保留的历史轮转文件数量
```

## 常用运维命令

### systemctl 服务管理

```bash
# 查看服务状态
systemctl status inkclaw-backend.service
systemctl status inkclaw-frontend.service

# 手动重启某个服务
sudo systemctl restart inkclaw-backend.service
sudo systemctl restart inkclaw-frontend.service

# 同时重启前后端
sudo systemctl restart inkclaw-backend.service inkclaw-frontend.service

# 停止服务（不删除配置）
sudo systemctl stop inkclaw-backend.service
sudo systemctl stop inkclaw-frontend.service

# 禁用开机自启
sudo systemctl disable inkclaw-backend.service
sudo systemctl disable inkclaw-frontend.service

# 看门狗 timer 管理
systemctl status inkclaw-watchdog.timer
sudo systemctl stop inkclaw-watchdog.timer     # 临时关闭看门狗
sudo systemctl start inkclaw-watchdog.timer    # 重新启用看门狗
```

### journalctl 日志查看

```bash
# 查看后端最新日志
journalctl -u inkclaw-backend.service -n 50 --no-pager

# 实时跟踪前端日志
journalctl -u inkclaw-frontend.service -f

# 查看今天的所有日志
journalctl -u inkclaw-backend.service -u inkclaw-frontend.service --since today

# 查看最近一次重启以来的日志
journalctl -u inkclaw-backend.service -b

# 搜索错误信息
journalctl -u inkclaw-backend.service --grep "ERROR" --since "1 hour ago"

# 导出日志到文件
journalctl -u inkclaw-backend.service --since "2025-01-01" > /tmp/backend.log
```

## 看门狗工作原理

InkClaw 采用**双重故障恢复机制**确保服务持续可用：

### 第一层：systemd 原生重启

每个服务 unit 文件配置了 `Restart=on-failure`，当进程异常退出时 systemd 会在 5 秒后自动重启。为防止无限重启循环，设置了 `StartLimitBurst=5`（5 分钟内最多重启 5 次）。

### 第二层：看门狗定时健康检查

`inkclaw-watchdog.timer` 每 60 秒（可配置）触发一次 `inkclaw-watchdog.service`（oneshot 类型），执行 `healthcheck.sh` 脚本：

1. 对后端发送 `GET /health` 请求，对前端发送 `GET /` 请求
2. 收到 HTTP 2xx 响应视为健康，将失败计数器归零
3. 请求失败时递增对应的失败计数器（存储在 `/tmp/inkclaw-watchdog-*-failures` 文件中）
4. 当连续失败次数达到阈值（默认 3 次），执行 `systemctl restart` 重启对应服务
5. 使用 `flock` 文件锁防止与 systemd 原生重启产生竞态条件

### 计数器文件

- `/tmp/inkclaw-watchdog-backend-failures` — 后端连续失败次数
- `/tmp/inkclaw-watchdog-frontend-failures` — 前端连续失败次数

这些文件由 `status.sh` 读取并显示，方便排查问题。系统重启后 `/tmp` 会被清空，计数器自动归零。

## 故障排查指南

### 服务启动失败

```bash
# 查看详细的启动失败原因
systemctl status inkclaw-backend.service
journalctl -u inkclaw-backend.service -n 100 --no-pager

# 常见原因：
# 1. 端口被占用 → ss -tlnp sport = :5000
# 2. Python 虚拟环境缺失 → 检查 backend/.venv/ 是否存在
# 3. 依赖未安装 → 重新运行 deployment.sh（不带 --skip-install）
# 4. 环境变量缺失 → 检查 .env.local 文件
```

### 端口冲突

```bash
# 查看谁占用了端口
ss -tlnp sport = :5000
ss -tlnp sport = :3000

# 如果是旧的 InkClaw 进程，先停止
./stop.sh
# 或手动 kill
kill -9 <PID>
```

### 看门狗不断重启服务

```bash
# 检查失败计数器
cat /tmp/inkclaw-watchdog-backend-failures
cat /tmp/inkclaw-watchdog-frontend-failures

# 查看看门狗执行日志
journalctl -u inkclaw-watchdog.service -n 20 --no-pager

# 临时禁用看门狗以便排查
sudo systemctl stop inkclaw-watchdog.timer

# 手动测试健康检查端点
curl -v http://localhost:5000/health
curl -v http://localhost:3000/

# 排查完成后重新启用看门狗
sudo systemctl start inkclaw-watchdog.timer
```

### 日志磁盘空间不足

```bash
# 查看日志占用
du -sh logs/
journalctl --disk-usage

# 手动触发 logrotate
sudo logrotate -f /etc/logrotate.d/inkclaw

# 清理旧的 journal 日志（保留最近 7 天）
sudo journalctl --vacuum-time=7d
```

### 服务正常但无法访问

```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 3000/tcp   # 允许前端端口
sudo ufw allow 5000/tcp   # 允许后端端口（通常不需要外部访问）

# 检查监听地址（确认不是只监听 127.0.0.1）
ss -tlnp sport = :3000
```

### status.sh 显示"未安装"

```bash
# 确认 systemd unit 文件存在
ls -la /etc/systemd/system/inkclaw-*.service

# 如果不存在，重新安装
sudo ./ops/install.sh

# 如果存在但 status.sh 仍报未安装，重新加载 systemd
sudo systemctl daemon-reload
```

## 与 deployment.sh 的关系

`ops/` 目录下的脚本与项目根目录的 `deployment.sh` / `stop.sh` 是**完全独立**的两套服务管理方案：

| 特性 | deployment.sh | ops/ (systemd) |
|------|---------------|-----------------|
| 运行方式 | 前台进程 / `--daemon` 后台进程 | systemd 托管 |
| 开机自启 | 不支持 | 支持（`systemctl enable`） |
| 自动重启 | 不支持 | 支持（systemd + 看门狗） |
| 日志轮转 | 手动管理 `logs/` | logrotate 自动轮转 |
| 适用场景 | 开发、临时部署、调试 | 长期生产环境运行 |
| 前提条件 | 仅需 Node.js + Python | 需要已构建的项目 |

**典型工作流**：

1. 首次部署使用 `deployment.sh` 完成项目构建
2. 确认运行正常后，使用 `./stop.sh` 停止 deployment.sh 管理的进程
3. 执行 `sudo ./ops/install.sh` 将服务注册到 systemd
4. 后续由 systemd 负责服务的启动、重启和日志管理

**注意**：不要同时使用两种方式运行服务，否则会导致端口冲突。
