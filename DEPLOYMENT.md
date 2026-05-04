# Deployment

## Requirements

- Python 3.8+
- Linux / macOS / Termux
- Ports 8080–8099 (configurable)

## Quick Start

```bash
cd system-monitor
bash setup.sh --port 8080
```

## Development

```bash
bash setup.sh --dev
```

Sets up venv with dev dependencies, enables auto-reload on `server.py` changes.

## Production (systemd)

```ini
# /etc/systemd/system/system-monitor.service
[Unit]
Description=System Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/system-monitor
ExecStart=/opt/system-monitor/venv/bin/uvicorn server:app --host 0.0.0.0 --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now system-monitor
systemctl status system-monitor
```

## Docker

```bash
docker-compose up -d
```

Container exposes port 8080, mounts `/proc`, `/sys`, and `/` for host metrics.

## Reverse Proxy (Nginx)

```nginx
server {
    listen 80;
    server_name monitor.example.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_websocket_pass http://127.0.0.1:8080;
    }
}
```

## Cloud Deployment

### VPS (Ubuntu)

```bash
wget https://github.com/YOUR_USER/system-monitor/archive/main.tar.gz
tar xzf main.tar.gz && cd system-monitor-main
bash setup.sh --port 8080
```

### Termux (Android)

```bash
pkg update && pkg install python git
git clone https://github.com/YOUR_USER/system-monitor.git
cd system-monitor
bash setup.sh --port 8080 --port-probe 8080 8099
```

### HomeLab (Proxmox / Docker)

Use `docker-compose.yml` with a bind mount for host metrics:

```yaml
volumes:
  - /proc:/host/proc:ro
  - /sys:/host/sys:ro
  - /:/rootfs:ro
```

## Health Check

```bash
curl http://localhost:8080/api/health
# {"status":"ok","connections":0}
```

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| ImportError: No module named `psutil` | `bash setup.sh` or `pip install -r requirements.txt` |
| Port 8080 busy | `bash setup.sh --port 9090 --port-probe 8080 9099` |
| WebSocket disconnect | Check reverse-proxy `proxy_websocket_pass` config |
| Permission denied | Run as root or configure user namespace |
| Metrics show zero | Ensure `/proc` and `/sys` are accessible |