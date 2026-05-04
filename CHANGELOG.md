# CHANGELOG

All notable changes to System Monitor are documented here.

## [2.1.1] — 2025-05-xx

### Added
- GitHub Actions CI: lint + dry-run + smoke test on every push
- Dependabot weekly pip dependency updates
- `.gitignore`, `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`
- `requirements.txt` auto-generation in `setup.sh` Step 3
- `--dry-run` dual breakpoints (Step 6 + Step 7 skip)

### Fixed
- `setup.sh` line 258: nested `$()` + `||` syntax error in `CURRENT_VER`
- `setup.sh` Step 1: `/etc/fstab` `grep -vcE` crash under `set -e`
- `setup.sh` Step 1: Swap help-text backflow bug (`free -h` header accepted)
- `setup.sh` Step 4/5: missing blank line between dry-run echo blocks
- `server.py` `FRONTEND_DIR` path consistency check
- LoginGuard 锁竞争 deadlock (login/auth 连接池崩溃)
- MongoDB 密码 reuse 逻辑漏洞 (`str_auth.py` `lcp_auth` 函数去重)
- 需求列表无 `cors` module → `middleware install` 缺失导致启动失败
- FSTAB_ISSUES regex 含 `[` 触发 bash 圆括号语法错误 → 改 `grep -vcE` + SQL

### Changed
- `setup.sh` v2.1.1: 7-step installer (platform → pre-check → paths → deps → port → permission → launch)
- `server.py` v2.1.1: desktop notification + alert engine integration

### Added — Termux API Integration
- `termux-api` Python package + Termux:APK auto-detect
- Battery / Location / Camera / Sensors / Telephony / Wifi / Brightness / Volume collectors
- 20 `/api/termux/*` REST endpoints (query / control / sms / screenshot …)
- `collect_all()` auto-hooks Termux data into main snapshot stream
- Graceful silent fallback on non-Termux platforms

## [2.1.0] — 2025-05-xx

### Added
- Desktop notifications (Linux/macOS/Windows)
- Alert engine auto-triggers desktop notification on threshold fire/clear
- `POST /api/notify` endpoint
- `DISK_IO_PATHS` extended to 4 mount points (`/`, `/sdcard`, `/storage`, `/mnt`)
- `CHANGELOG.md` auto-linked in README

### Changed
- README: cross-platform install guide + notification API docs

## [2.0.0] — 2025

### Added
- Alert engine: 5 default rules, threshold fire/clear, cooldown
- REST API: history queries, alert rules CRUD
- WebSocket: real-time push + auto-reconnect
- Ticker banner + alerts panel in frontend

## [1.x] — Initial

Basic system monitor for remote Linux hosts: CPU / memory / disk ring buffer + ECharts dashboard.