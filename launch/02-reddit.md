# Reddit 发布文案 — ⬡ System Monitor

---

## Post 1: r/selfhosted（主发，黄金流量）

**标题:**
```
[Open Source] System Monitor – lightweight CPU/Memory/Disk monitor that actually gets out of your way
```

**正文:**
```
I built a lightweight system resource monitor after getting tired of spinning up Prometheus+Grafana just to check "is my server OK?"

It's a single Python file (FastAPI) + one HTML file (ECharts). 
Zero config. ~25MB total memory. Deploys in 30 seconds.

What it does:
- Real-time CPU/Memory/Disk I/O charts refreshed every second
- 5 configurable alert rules with cooldown and auto-recovery
- Desktop notifications (Linux/macOS/Windows) when thresholds fire
- 1-hour rolling history ring buffer
- WebSocket push, auto-reconnect
- Zero database, zero config file
- Docker + docker-compose included

Why not the big ones?
- Netdata: 100MB+, heavy auto-probes
- Prometheus+Grafana: 200MB+, YAML config hell
- Glances: heavier dependency footprint

This one is for when you need to know your CPU temp RIGHT NOW and don't want to set up an observability stack.

MIT licensed. Feedback welcome.

https://github.com/2233qazwsx0/system-monitor

```

**发布时机**: r/selfhosted 最高活跃 UTC 14:00–16:00（北京时间 22:00–00:00）

---

## Post 2: r/Linux（次级）

**标题:**
```
System Monitor – WebSocket-based system metrics with alert engine | ~25MB, MIT, Python
```

**正文:**
```
Cross-platform system resource monitor using FastAPI + WebSocket.
Shows CPU, memory, disk I/O in real-time ECharts dashboard.

Key features:
- 1-second refresh via WebSocket
- Built-in alert engine (threshold + cooldown)
- Desktop notifications on alert fire
- 1-hour rolling history
- <30 second setup

https://github.com/2233qazwsx0/system-monitor
```

---

## Post 3: r/Python

**标题:**
```
System Monitor – FastAPI + WebSocket system metrics dashboard | RFC appreciated
```

**正文:**
```
Built a self-hosted system resource monitor in FastAPI.

Tech choices I'm questioning:
- RingBuffer via collections.deque(maxlen=3600) — works well but wondering if anyone has done better time-series storage at this scale?
- Alert engine cooldown logic in the main check loop — currently inline, should it be extracted?
- Static file serving for the frontend — mount("/static") works but feels inelegant

Desktop notification backend is async-routed via asyncio.to_thread to avoid blocking the event loop. Seems fine but interested in better patterns.

Looking for code review and design feedback.

https://github.com/2233qazwsx0/system-monitor
```

---

**⚠️ Reddit 注意事项:**
- 首次发帖后，等 30 分钟再 **从外部链接**（Google/直接URL）点进 GitHub 并 STARR，不要从 Reddit 内部链点 star（Reddit 防刷机制会 flag）
- 24小时内不要连续在多 subreddit 发（间隔至少 2 小时）
