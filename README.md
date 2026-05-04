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
| CPU | 整体百分比 + 每核心实时曲线 |
| 内存 | 已用 / 可用 GB + Swap 使用率 |
| 磁盘 I/O | 累计读写 GB + 挂载点空间占用率 |
| 推送频率 | 精确 1 秒（WebSocket） |
| 历史窗口 | 默认保留最近 1 小时（3600 点） |
| 自动重连 | WebSocket 断线后 3 秒自动重连 |
| 零数据库 | 纯内存环形缓冲 |
| ⚡ 告警引擎 | 5 条默认规则，阈值触发，自动恢复 |
| 🔔 桌面通知 | Linux (notify-send) / macOS (osascript) / Windows (Toast) |
| 📱 Termux | Termux:APK 传感器 + 20 个控制端点 |
| 🐳 Docker | 完整 Dockerfile + docker-compose.yml |

---

## 跨平台安装

### Linux / Termux

```bash
curl -fsSL https://raw.githubusercontent.com/2233qazwsx0/system-monitor/master/install/linux-install.sh | bash
bash setup.sh [--port 8080] [--dev]
```

### macOS

```bash
bash setup.sh [--port 8080] [--dev]
```

> 首次弹通知需在 **系统设置 → 通知与专注模式** 中允许终端发送通知。

### Windows

**双击运行 `windows-install.bat`**：自动检测 Git → clone → pip install → 生成启动脚本。

```bash
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8080
```

---

## API

### 健康检查 `GET /api/health`

### 当前快照 `GET /api/snapshot`
### 历史查询 `GET /api/history/{cpu,memory,disk,snapshot}?since=unix_ts`
### WebSocket `ws://host:port/ws`
### 桌面通知 `POST /api/notify?title=Alert&body=CPU%20High&urgency=critical`

### Termux API
`GET /api/termux/status` — 可用性探测
`GET /api/termux/battery | location | camera | sensors | telephony | wifi | brightness | volume`
`POST /api/termux/volume?stream=music&volume=50` `POST /api/termux/brightness?value=200`
`GET /api/termux/vibrate?duration=500` `GET /api/termux/torch?state=on` `GET /api/termux/toast?text=Hello`
`POST /api/termux/clipboard` `GET /api/termux/clipboard`
`POST /api/termux/notification?title=A&body=B&id=sysmon`
`GET /api/termux/sms-send | sms-inbox | call-log | contacts`
`POST /api/termux/media-play?command=play` `GET /api/termux/media-ctrl?command=play/pause`
`GET /api/termux/screenshot | wifi-scan | wifi-connection`

### Docker `docker-compose up -d`

---

**Q：Termux 上 psutil 装不上？** A：`pkg install python python-pip` 后 `pip install psutil`。

> Built with ❤️ by CUA