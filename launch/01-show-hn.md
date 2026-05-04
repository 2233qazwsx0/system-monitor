# Show HN 文案 — ⬡ System Monitor

---

## 英文版（Primary）

**标题（140字符内，越短越好）：**
```
Show HN: System Monitor – lightweight CPU/Memory/Disk monitor with WebSocket & Alerts
```

**正文模板（HN 用户喜欢技术细节，不要废话版英文简介格式）：**

> Lightweight system resource monitor built with FastAPI + WebSocket. No DB, no config file, starts in 30 seconds.
>
> **Features:**
> - 1-second real-time charting via WebSocket
> - 5 default alert rules with cooldown and auto-recovery
> - Desktop notifications (Linux/macOS/Windows)
> - 1-hour rolling history (3600 samples)
> - ECharts dashboard, single HTML file
>
> **Why not Prometheus/Grafana?**
> - Zero deps, zero config, single-file deploy
> - ~25MB total memory (~3.6MB ring buffer)
>
> **Stack:** Python 3.8+ / FastAPI / psutil / ECharts
> **MIT License**
>
> Repo: https://github.com/2233qazwsx0/system-monitor

---

## 发布时间

- **优先窗口**: 周二/周三/周四 EST 9:00–11:00 AM（即北京时间 9:00–11:00 PM）
- **备用窗口**: 周五 EST 9:00–11:00 AM
- **发布后 30 分钟内**务必守在评论区回复所有评论

---

## 答辩（常见问题预答）

**Q: How does this compare to htop/glances/netdata?**
> A: htop is CLI-only, glances is heavier, netdata is 100MB+. This is ~25MB, zero-config, single-file deploy.

**Q: Why not Prometheus + Grafana?**
> A: Prometheus + Grafana combo is ~200MB+ and requires config YAML. System Monitor is for when you need "just tell me my CPU" in 30 seconds.

**Q: Can I deploy this on Termux / Android?**
> A: Yes, `bash setup.sh` auto-detects Termux and Termux-specific paths.

**Q: Docker support?**
> A: Yes, `docker-compose up -d` and you're done.