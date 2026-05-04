# ⬡ System Monitor

> 轻量级跨平台系统监控工具 · CPU / 内存 / 磁盘 I/O / 告警 / 桌面通知
> 1 秒推送 · 1 小时历史 · 单文件前端 · 零依赖部署 · v2.1.0

---

## 📋 变更日志

| 版本 | 变更 |
|------|------|
| v2.1.0 | 桌面通知（Linux/macOS/Windows）、告警自动触发通知、平台路径自动适配 |
| v2.0.0 | 告警引擎 5 规则 + REST API + WebSocket + ticker 横幅 + history 面板 |
| v1.x   | 初始版本 · CPU / 内存 / 磁盘环形缓冲 + ECharts 看板 |

---

## 目录

1. [特性](#特性)
2. [架构](#架构)
3. [快速开始](#快速开始)
4. [API 文档](#api-文档)
5. [目录结构](#目录结构)
6. [开发](#开发)
7. [FAQ](#faq)

---

## 特性

| 指标 | 说明 |
|------|------|
| CPU 利用率 | 整体百分比 + 每核心实时曲线 |
| 内存 | 已用 / 可用 GB + Swap 使用率 + 百分比曲线 |
| 磁盘 I/O | 累计读写 GB + 挂载点空间占用率横条图 |
| 推送频率 | 精确 1 秒（WebSocket） |
| 历史窗口 | 默认保留最近 1 小时（3600 个采样点） |
| 历史查询 | `GET /api/history/{cpu,memory,disk,snapshot}?since=unix_ts` |
| 自动重连 | 前端 WebSocket 断线后 3 秒自动重连 |
| 零数据库 | 纯内存环形缓冲，零配置文件 |
| ⚡ 告警引擎 | 5 条默认规则，阈值触发，自动恢复检测，WebSocket 推送 |
| 🔔 桌面通知 | Linux (notify-send) / macOS (osascript) / Windows (PowerShell Toast) |
| 🐳 Docker | 完整 Dockerfile + docker-compose.yml，一键部署 |

### 默认告警规则

| 规则 ID | 指标 | 触发条件 | 冷却时间 |
|---------|------|----------|----------|
| `cpu-high` | CPU 整体 | > 90% | 120s |
| `mem-high` | 内存使用率 | > 90% | 120s |
| `cpu-low` | CPU 整体 | < 0.1% | 300s |
| `mem-low` | 内存使用率 | < 2% | 300s |
| `disk-root` | 根分区 | > 90% | 300s |

---

## 跨平台安装

### Linux / Termux（推荐）

```bash
# 完整检测（七步：平台 → 前置 → 路径 → 依赖 → 端口 → 权限 → 启动）
bash setup.sh [--port 8080] [--dev]

# Docker 部署
bash setup.sh --docker [--force] [--port 8080]

# --port-probe M N  指定端口探测范围（默认自动扫描 8080-9099）
bash setup.sh --port-probe 9000 9500
```

### macOS

```bash
# 跨平台检测（自动识别 macOS → Swap → 权限 → 启动）
bash setup.sh [--port 8080] [--dev]
```

> **注意**： macOS 首次弹通知需要在 **系统设置 → 通知与专注模式** 中允许终端（Terminal / iTerm2）发送通知。

### Windows

```powershell
# WSL/Git-Bash（推荐跨平台脚本）
bash setup.sh --port 8080

# CMD/PowerShell 手动
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8080
```

> **注意**： Windows Toast 需要系统未完全静默，PowerShell 执行策略需允许脚本运行（默认级别即可）。

### 手动（所有平台）

```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8080
```

打开浏览器访问 `http://localhost:8080`。

## 架构

```
用户浏览器 (WebSocket + ECharts)
        ↕ ws://host:port/ws
FastAPI 后端 (server.py)
  ├── psutil          → 系统指标采集
  ├── RingBuffer      → 内存环形缓冲（固定 3600 点）
  ├── WebSocket Hub   → 多连接广播
  └── REST API        → 历史查询 / 健康检查 / 当前快照

         + 静态资源挂载
        ↕
  frontend/index.html   (单文件 · 零构建 · 零 npm)
```

### 数据流

```
┌──────────┐   1s    ┌──────────┐   ws   ┌──────────┐
│ psutil   │ ──────► │ RingBuf  │ ─────► │ Hub.broad │
│ 采集     │         │ 环形缓冲 │         │ 推送所有连  │
└──────────┘         └──────────┘         └──────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Browser (ECharts)   │
                                    │  ws.onmessage→渲染  │
                                    └─────────────────────┘
```

### 技术选型

| 层级 | 技术 | 选择理由 |
|------|------|---------|
| 后端 | Python 3.8+ / FastAPI | 异步 IO 友好，psutil 生态成熟，5 分钟可启动 |
| 采集 | psutil | 跨平台，不需要 root |
| 缓冲 | `collections.deque(maxlen=N)` | O(1) 写入，O(1) 内存回收，天然环形 |
| 推送 | WebSocket | 真正实时，比 SSE 低延迟，比轮询省带宽 |
| 前端 | 原生 HTML + ECharts CDN | 无构建步骤，单文件交付，零 npm 依赖 |

---

## 快速开始

### 方式一：一键脚本（推荐）

```bash
cd /path/to/system-monitor
bash setup.sh
```

打开浏览器访问 `http://localhost:8080`。

### 方式二：手动

```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8080
```

### 方式三：开发模式（热重载）

```bash
bash setup.sh --dev
# 或
uvicorn server:app --host 0.0.0.0 --port 8080 --reload
```

> **Termux 用户**：先执行 `pkg install python`，然后同上。

---

## API 文档

### 健康检查

```http
GET /api/health
```

```json
{ "status": "ok", "connections": 1 }
```

### 当前快照

```http
GET /api/snapshot
```

```json
{
  "_ts": 1699500000.0,
  "_time": "14:20:00",
  "cpu": {
    "overall": 23.5,
    "cores": [12.1, 8.3, ...],
    "freq_mhz": 2800.0,
    "core_count": 8
  },
  "memory": {
    "total_gb": 15.5, "used_gb": 8.2, "available_gb": 6.8,
    "percent": 52.9,
    "swap_total_gb": 4.0, "swap_used_gb": 0.5, "swap_percent": 12.5
  },
  "disk": {
    "partitions": { "/": { "total_gb": 256, "used_gb": 120, "free_gb": 136, "percent": 46.9 } },
    "total_read_gb": 45.2, "total_write_gb": 12.8
  }
}
```

### 历史查询

```http
GET /api/history/cpu?since=1699500000
GET /api/history/memory?since=1699500000
GET /api/history/disk?since=1699500000
GET /api/history/snapshot?since=1699500000
```

| 参数 | 说明 |
|------|------|
| `since` | Unix 时间戳（可选），仅返回 `_ts >= since` 的数据 |
| 无 `since` | 返回全部历史（最多 3600 条） |

### WebSocket

```
ws://host:port/ws
```

- 连接即发送首次欢迎帧（最新快照）
- 后续每 1 秒收到一次完整快照
- 可发送 `"ping"`，返回 `{"type":"pong","ts":...}`
- 客户端断开后服务端自动清理连接

### 桌面通知

```http
POST /api/notify?title=Alert&body=CPU超限&urgency=critical
```

| 参数 | 说明 |
|------|------|
| `title` | 通知标题 |
| `body` | 通知正文 |
| `urgency` | `low` / `normal` / `critical` |

> 告警触发时会自动推送桌面通知：`cpu >= 95%` → `critical`，普通告警 → `normal`，恢复 → `low`。
>
> | 平台 | 实现 |
> |------|------|
> | Linux | `notify-send` (libnotify) |
> | macOS | `osascript` display notification |
> | Windows | PowerShell Toast (Win10+) / BalloonTip legacy fallback |

### Docker

```bash
docker-compose up -d
```

```
system-monitor/
├── server.py          FastAPI 后端（采集 + WebSocket + REST API）
├── requirements.txt   依赖清单
├── setup.sh           一键安装 & 跨平台启动脚本
├── docker-compose.yml Docker Compose 配置
├── README.md          本文件
├── docker/
│   └── Dockerfile     多阶段构建镜像
└── frontend/
    └── index.html     前端看板（ECharts，零构建）
```

### 前自动触发桌面通知通知链路

```
告警阈值触发 → AlertEngine.on_fire()
                    │
              asyncio.to_thread
                    │
          ┌───────┴───────┐
          ▼               ▼
   WebSocket push   桌面通知
   (alert frame)    (notify-send /
                     osascript /
                     PowerShell)
```

---

## 开发

### 代码约束

- 后端采集逻辑必须在线程外执行（不阻塞 event loop）
- 环形缓冲大小 = `HISTORY_SECONDS / COLLECT_INTERVAL`
- 历史查询不进循环，直接 deque `all()` 或 `since(ts)`，O(n) n ≤ 3600
- 前端不引入任何 npm 包，仅 CDN 引入 ECharts

### 扩展示例

```python
# 在 server.py 中添加新指标
def collect_gpu():
    import subprocess
    result = subprocess.run(
        ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
         "--format=csv,noheader,nounits"],
        capture_output=True, text=True
    )
    ...
```

---

## FAQ

**Q：为什么不用 RRDtool / Prometheus / Grafana？**
A：本工具定位是**轻量可移植**，零配置、单文件、秒启动。Prometheus 适合大规模集群，但 DinD 也要吃几十MB 内存。本工具适合单机便携监控。

**Q：内存占用多少？**
A：每个采样点 ≈ 1 KB JSON × 3600 ≈ 3.6 MB 缓冲 + Python 进程 ≈ 25 MB 总内存。

**Q：如何调整历史窗口？**
A：改 `HISTORY_SECONDS`（`server.py` 顶部），重启即可。

**Q：Termux 上 `psutil` 装不上？**
A：执行 `pkg install python python-pip` 后再 `pip install psutil`，国内可加 `-i https://pypi.tuna.tsinghua.edu.cn/simple`。

**Q：如何改成 CPU / 内存告警？**
A：后端加 `watchdog` 线程检测阈值，通过 WebSocket 推送 `{"type":"alert","metric":"cpu","value":95}` 字段，前端监听即可。

---

> 最后更新：2025 · Built with ❤️ 不Built with著名的AI会议公司，你们都懂的。