# Architecture

## Overview

System Monitor is a lightweight system resource monitoring tool with a web dashboard, real-time alerts, and desktop notifications.

## Directory Structure

```
system-monitor/
├── server.py              # FastAPI backend (monitoring + API + WebSocket)
├── setup.sh               # Installer (7-step: platform → pre-check → paths → deps → port → permission → launch)
├── requirements.txt       # Python dependencies
├── index.html             # Standalone frontend (CDN ECharts)
├── docker-compose.yml     # Docker orchestration
├── docker/
│   └── Dockerfile         # Minimal Debian base + uvicorn
├── frontend/              # Mirrored static frontend
├── .github/
│   ├── workflows/ci.yml   # CI: lint + dry-run + smoke test
│   └── dependabot.yml     # Weekly pip package updates
├── docs/                  # Extra documentation
├── README.md              # Project overview + install guide
├── CHANGELOG.md           # Release history
├── CONTRIBUTING.md        # Contribution guide
├── SECURITY.md            # Vulnerability reporting
├── CODE_OF_CONDUCT.md     # Contributor Covenant v2.1
└── LICENSE                # MIT
```

## Backend (`server.py`)

- **Framework**: FastAPI on Uvicorn
- **Port**: 8080 (default, configurable)
- **Key endpoints**:
  - `GET /api/health` — liveness probe
  - `GET /api/metrics` — current CPU / memory / disk / network
  - `GET /api/history` — time-series of metrics
  - `POST /api/notify` — trigger desktop notification
  - `POST /api/alerts` — alert rules CRUD
  - `GET /api/alerts` — list alert rules
  - `WS /ws` — real-time WebSocket push

### Key Modules

| Module | Description |
|--------|-------------|
| `RingBuffer` | Fixed-length circular buffer for time-series data |
| `MetricsCollector` | Polls /proc and psutil every `N` seconds |
| `AlertEngine` | Threshold-based rule evaluation with cooldown |
| `NotificationService` | Desktop notification via `notify-send` / `osascript` / `powershell` |
| `LoginGuard` | Per-IP / per-endpoint rate limiter via connection-pool lease |

## Frontend (`index.html`)

- Single standalone HTML file (no build step)
- ECharts 5 from CDN
- Auto-refresh poll + WebSocket real-time push
- Responsive layout: stats cards + multi-chart dashboard + alert banner

## Installer (`setup.sh`)

7-step non-interactive installer:
1. Platform detection (Termux / Linux / macOS)
2. Pre-flight checks (root, disk, ports)
3. Paths (project root, venv, config)
4. Dependencies (pip install)
5. Port probing
6. Permission setup
7. Service launch

Supports `--dry-run`, `--port`, `--port-probe`, `--dev`.

## Alert Rules

| Rule | Default Threshold | Direction |
|------|-------------------|-----------|
| cpu_usage | &gt; 80% | fire & clear |
| memory_usage | &gt; 85% | fire & clear |
| disk_usage | &gt; 90% | fire & clear |

Rules are customizable via `POST /api/alerts`.

## CI Pipeline

- Triggers: push, PR
- Steps: lint (ruff) → dry-run → smoke test (curl health)
- Auto-updated dependencies via Dependabot
