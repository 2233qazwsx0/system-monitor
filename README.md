# ⬡ System Monitor

> 轻量级跨平台系统监控工具 · CPU / 内存 / 磁盘 I/O / 告警 / 桌面通知
> 1 秒推送 · 1 小时历史 · 单文件前端 · 零依赖部署 · v2.1.1

---

## 📋 变更日志

| 版本 | 变更 |
|------|------|
| v2.1.1 | Windows 一键安装 · Linux 自动部署 · Termux API 集成 |
| v2.1.0 | 桌面通知 + 告警自动触发 |
| v2.0.0 | 告警引擎 5 规则 + REST API + WebSocket |
| v1.x   | 初始版本 · CPU / 内存 / 磁盘 + ECharts 看板 |

---

## 特性

| 指标 | 说明 |
|------|------|
| CPU 利用率 | 整体百分比 + 每核心实时曲线 |
| 内存 | 已用 / 可用 GB + Swap 使用率 + 百分比曲线 |
| 磁盘 I/O | 累计读写 GB + 挂载点空间占用率 |
| 推送频率 | 精确 1 秒（WebSocket） |
| 历史窗口 | 默认保留最近 1 小时（3600 点） |
| 历史查询 | `GET /api/history/{cpu,memory,disk,snapshot}` |
| 自动重连 | WebSocket 断线后 3 秒自动重连 |
| 零数据库 | 纯内存环形缓冲 |
| ⚡ 告警引擎 | 5 条默认规则，阈值触发，自动恢复 |
| 🔔 桌面通知 | Linux (notify-send) / macOS (osascript) / Windows (Toast) |
| 📱 Termux | 传感器 + 20 个控制端点 |
| 🐳 Docker | 完整 Dockerfile + docker-compose.yml |

### 默认告警规则

| 规则 ID | 指标 | 触发条件 | 冷却时间 |
|---------|------|----------|----------|
| `cpu-high` | CPU 整体 | > 90% | 120s |
| `mem-high` | 内存使用率 | > 90% | 120s |
| `cpu-low` | CPU 整体 | < 0.1% | 300s |
| `mem-low` | 内存使用率 | < 2% | 300s |
| `disk-root` | 根分区 | > 90% | 300s |

---

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
  frontend/index.html  (单文件 · 零构建 · 零 npm)
```

```
┌──────────┐  1s  ┌──────────┐  ws  ┌──────────┐
│ psutil   │─────►│ RingBuf  │─────►│ Hub.broad │
│ 采集     │      │ 环形缓冲 │      │ 推送所有 │
└──────────┘      └──────────┘      └──────────┘
                                     │
                        ┌──────────▼──────────┐
                        │  Browser (ECharts)   │
                        │  ws.onmessage→渲染 │
                        └─────────────────────┘
```

### 技术选型

| 层级 | 技术 | 选择理由 |
|------|------|---------|
| 后端 | Python 3.8+ / FastAPI | 异步 IO 友好，5 分钟可启动 |
| 采集 | psutil | 跨平台，不需要 root |
| 缓冲 | deque(maxlen=N) | O(1) 写入，O(1) 回收 |
| 推送 | WebSocket | 真正实时，低延迟 |
| 前端 | 原生 HTML + ECharts CDN | 零构建，单文件 |

---

## 跨平台安装

### 方式一：一键脚本（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/2233qazwsx0/system-monitor/master/install/linux-install.sh | bash
bash setup.sh [--port 8080] [--dev]
```

打开浏览器访问 `http://localhost:8080`。

### 方式二：手动

```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8080
```

### Docker

```bash
docker-compose up -d
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
  "_ts": 1699500000.0, "_time": "14:20:00",
  "cpu": { "overall": 23.5, "cores": [12.1, 8.3], "freq_mhz": 2800.0, "core_count": 8 },
  "memory": { "total_gb": 15.5, "used_gb": 8.2, "available_gb": 6.8, "percent": 52.9 },
  "disk": { "partitions": { "/": { "total_gb": 256, "used_gb": 120, "percent": 46.9 } } }
}
```

### 历史查询

```http
GET /api/history/cpu?since=1699500000
GET /api/history/memory?since=1699500000
GET /api/history/disk?since=1699500000
GET /api/history/snapshot?since=1699500000
```

### WebSocket

```
ws://host:port/ws
```

- 连接即发送首次快照
- 后续每 1 秒收到完整快照
- 可发送 `ping` → `pong`
- 客户端断开后自动清理连接

### 桌面通知

```http
POST /api/notify?title=Alert&body=CPU%20High&urgency=critical
```

| 参数 | 说明 |
|------|------|
| title | 通知标题 |
| body | 通知正文 |
| urgency | low / normal / critical |

| 平台 | 实现 |
|------|------|
| Linux | notify-send |
| macOS | osascript |
| Windows | PowerShell Toast |

### Termux API

```http
GET /api/termux/status
GET /api/termux/battery    | location | camera | sensors | telephony
GET /api/termux/wifi       | brightness | volume
POST /api/termux/volume?stream=music&volume=50
POST /api/termux/brightness?value=200
GET  /api/termux/vibrate?duration=500
GET  /api/termux/torch?state=on
GET  /api/termux/toast?text=Hello
POST /api/termux/clipboard GET /api/termux/clipboard
POST /api/termux/notification?title=A&body=B&id=sysmon
POST /api/termux/sms-send    | GET /api/termux/sms-inbox
GET  /api/termux/call-log    | GET /api/termux/contacts
POST /api/termux/media-play  | GET /api/termux/media-ctrl
GET  /api/termux/screenshot  | GET /api/termux/wifi-scan  | GET /api/termux/wifi-connection
```

> 需先执行 `pkg install termux-api` 并按提示授权。

### Docker
```bash
docker-compose up -d
```

---

## 目录结构

```
system-monitor/
├── server.py              FastAPI 后端
├── requirements.txt       依赖清单
├── setup.sh               一键安装 & 启动（7 步）
├── windows-install.bat    Windows 一键安装
├── install/
│   └── linux-install.sh   Linux 自动部署
├── docker-compose.yml     Docker Compose
├── README.md              本文件
├── docker/
│   └── Dockerfile         多阶段构建
└── frontend/
    └── index.html         前端看板（ECharts）
```

### 告警通知链路

```
告警阈值触发 → AlertEngine.on_fire()
                     │
               asyncio.to_thread
                     │
           ┌───────┴───────┐
           ▼               ▼
    WebSocket push   桌面通知
    (alert frame)    (notify-send / osascript / PowerShell)
```

---

## 开发

- 后端采集逻辑必须在线程外执行
- 环形缓冲 = `HISTORY_SECONDS / COLLECT_INTERVAL`
- 前端不引入任何 npm 包，仅 CDN ECharts

扩展示例：
```python
def collect_gpu():
    import subprocess
    result = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,memory.used",
                             "--format=csv,noheader,nounits"], capture_output=True, text=True)
    ...
```

---

## FAQ

**Q：为什么不用 Prometheus/Grafana？**
A：本工具轻量可移植，零配置、秒启动，单机便携首选。

**Q：内存占用？**
A：每采样点约 1 KB × 3600 ≈ 3.6 MB 缓冲 + Python ≈ 25 MB。

**Q：调整历史窗口？**
A：改 `HISTORY_SECONDS`（`server.py` 顶部），重启即可。

**Q：Termux 上 psutil 装不上？**
A：`pkg install python python-pip` 后 `pip install psutil`。

-------------

> 最后更新：2026 · Built with ❤️
