# DEV.to / Blog 发布文案 — ⬡ System Monitor

---

## DEV.to 英文版

**标题:**
```
System Monitor: A Lightweight Open-Source System Resource Monitor
```

**标签/Discussion topics**: `#python` `#fastapi` `#opensource` `#devops` `#monitoring`

**正文框架:**
```markdown
---
title: "System Monitor: A Lightweight Alternative to Prometheus+Grafana for Personal Servers"
published: true
date: TBD
tags: python, fastapi, opensource, devops, monitoring
---

While setting up monitoring for my personal servers, I found myself in a familiar paradox: to monitor one server properly, I needed another server to run Prometheus and Grafana. This felt wrong.

So I built System Monitor — a ~25MB, zero-config, single-file deployable system resource monitor.

## The Problem

When you have a single VPS or a homelab server, observability tools often feel like overkill. Prometheus + Grafana is great for production clusters at scale. For one server? It's a yak-shaving experience.

## What System Monitor Does

| Feature | Detail |
|---------|--------|
| Real-time metrics | CPU/Memory/Disk I/O, WebSocket 1-sec refresh |
| Alert engine | 5 rules with cooldown + auto-recovery detection |
| Desktop notifications | notify-send/osascript/PowerShell Toast |
| History | 1-hour ring buffer (3600 samples) |
| Zero dependencies | No database, no config files |
| Memory | ~25MB total (~3.6MB ring buffer) |
| One-line deploy | `bash setup.sh` or `uvicorn server:app` |

## Tech Stack

- **Backend**: FastAPI + Uvicorn
- **Metrics**: psutil (cross-platform)
- **Buffer**: collections.deque(maxlen=N)
- **Push**: WebSocket for real-time delivery
- **Frontend**: Plain HTML + ECharts CDN

## Architecture at a Glance

<pre>
┌──────────┐   1s    ┌──────────┐   ws   ┌──────────┐
│ psutil   │ ──────► │ RingBuf  │ ─────► │ Hub.broad│
│ 采集     │         │ 环形缓冲 │         │ 推送所有  │
└──────────┘         └──────────┘         └──────────┘
                                         Browser
                                        (ECharts)
</pre>

GitHub: [https://github.com/2233qazwsx0/system-monitor](https://github.com/2233qazwsx0/system-monitor) ⭐
```

---

## 知乎中文版

**标题:**
```
我用 588 行 Python 写了一个系统监控工具，零依赖、一秒刷新、带告警
```

**大纲:**
1. **动机**：手头服务器拿 Prometheus+Grafana 太重，想找一个 `curl | bash` 即启动的方案
2. **核心特性**：WebSocket 秒级推送、告警引擎、桌面通知、环形缓冲
3. **技术选型**：为什么选 FastAPI 而非 Flask，为什么 deque 而非 Redis
4. **代码片段**：RingBuffer + AlertEngine 核心逻辑（配 snippet）
5. **对比**：versus netdata / glances / Prometheus

**结尾引导:**
```
GitHub：https://github.com/2233qazwsx0/system-monitor 
MIT License，欢迎 Star、Issue、PR。
```
