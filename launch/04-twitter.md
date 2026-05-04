# Twitter/X 发布文案 — ⬡ System Monitor

## 主推文（Launch Day）

```
I built a ~25MB system monitor in 588 lines of Python:

🖥 WebSocket real-time dashboard
🔔 Alert engine with desktop notifications  
📊 1-hour ring buffer history
🐳 Docker + one-liner deploy
⚡ MIT, zero config, zero database

Forget Prometheus+Grafana for your personal server.

https://github.com/2233qazwsx0/system-monitor

#python #fastapi #opensource #devops
```

## 补充线程

**线程 1:**
```
Thread on why I built this 👇

Had a homelab server. Wanted to check CPU/Memory without deploying another 200MB Grafana.

Built System Monitor: FastAPI + WebSocket + ECharts.

25MB total. One line to deploy. Actually usable.
```

**线程 2:**
```
Design decisions I'm still unsure about:

1. RingBuffer via deque(maxlen=N) — works but is there a better single-process TS approach?
2. Alert cooldown inline in check loop — should I separate the rule engine?
3. asyncio.to_thread for notifications — any better event-loop-safe pattern?

Thinking about v2.2. Feedback welcome.
```

**线程 3:**
```
Annoying bugs I found and fixed while building this:

- `set -e` + nested command substitution → shell dies silently
- Bash string interpolation in heredoc with Chinese comments → EOF prematurely
- Uvicorn port collision → added `--port-probe` range scan
- CORS middleware initially missing → frontend refused all connections
- LoginGuard lock → deadlock race condition (real pain point)

Anyone else has similar war stories? 👀
```

## 标签套组
一次推文建议 3-5 标签：
- #python #fastapi #opensource #devops #infrastructure

## 时机
与 HN 同步或提前 1 小时发，给社区发酵留窗口
