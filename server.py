"""
System Monitor v2.2.0 — FastAPI + WebSocket + Ring Buffer + Alert Engine
CPU / 内存 / 磁盘 IO / GPU / 告警 / 桌面通知 / Termux 扩展
"""
import asyncio
import logging
import platform
import subprocess
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime

import psutil
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

logger = logging.getLogger("system_monitor")

# ═══════════════════════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════════════════════
COLLECT_INTERVAL = 1.0          # 采集/推送间隔（秒）
HISTORY_SECONDS = 3600          # 保留 1 小时历史
MAX_SAMPLES = int(HISTORY_SECONDS / COLLECT_INTERVAL)  # 3600 点
CPU_INTERVAL = 0.5              # psutil.cpu_percent 采样间隔

DISK_IO_PATHS = ("/", "/sdcard", "/storage", "/mnt")

app = FastAPI(title="System Monitor", version="2.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # 本地看板 → 开放；生产建议限制
    allow_methods=["*"],
    allow_headers=["*"],
)

# ═══════════════════════════════════════════════════════════════════════════════
# RingBuffer — 固定长度环形队列（O(1) append + O(1) 老化）
# ═══════════════════════════════════════════════════════════════════════════════

class RingBuffer:
    """固定长度环形队列，存最近 N 条数据。"""

    def __init__(self, maxlen: int):
        self.maxlen = maxlen
        self._data: deque = deque(maxlen=maxlen)

    def push(self, item: dict):
        self._data.append(item)

    def all(self) -> list:
        return list(self._data)

    def latest(self) -> dict | None:
        return self._data[-1] if self._data else None

    def since(self, ts: float) -> list:
        return [d for d in self._data if d["_ts"] >= ts]


cpu_buf: RingBuffer = RingBuffer(MAX_SAMPLES)
mem_buf: RingBuffer = RingBuffer(MAX_SAMPLES)
disk_buf: RingBuffer = RingBuffer(MAX_SAMPLES)
gpu_buf: RingBuffer = RingBuffer(MAX_SAMPLES)

# ═══════════════════════════════════════════════════════════════════════════════
# 告警引擎
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class AlertRule:
    """一条告警规则。"""
    id: str
    metric: str                # cpu.overall | memory.percent | disk.<mount>.percent | gpu.overall_util_percent
    op: str                    # ">" | "<"
    threshold: float
    cooldown: int = 60        # 冷却秒数
    enabled: bool = True

    # 运行时状态
    _last_fire: float = field(default=0.0, compare=False, repr=False)
    _last_value: float = field(default=0.0, compare=False, repr=False)
    _active: bool = field(default=False, compare=False, repr=False)


class AlertEngine:
    """阈值检测 + 冷却 + 状态回调。"""

    def __init__(self, on_fire, on_clear):
        self._rules: dict[str, AlertRule] = {}
        self._on_fire = on_fire
        self._on_clear = on_clear

    def add(self, rule: AlertRule):
        self._rules[rule.id] = rule

    def remove(self, rule_id: str):
        self._rules.pop(rule_id, None)

    def get_all(self) -> list[dict]:
        return [
            {
                "id": r.id, "metric": r.metric, "op": r.op,
                "threshold": r.threshold, "cooldown": r.cooldown,
                "enabled": r.enabled,
                "active": r._active, "last_value": r._last_value,
            }
            for r in self._rules.values()
        ]

    def check(self, snapshot: dict):
        now = time.time()
        for rule in self._rules.values():
            if not rule.enabled:
                continue
            val = _resolve_metric(snapshot, rule.metric)
            if val is None:
                continue
            rule._last_value = round(val, 2)
            triggered = (val > rule.threshold) if rule.op == ">" else (val < rule.threshold)
            if triggered:
                if now - rule._last_fire >= rule.cooldown:
                    rule._last_fire = now
                    if not rule._active:
                        rule._active = True
                        self._on_fire(rule, val)
            else:
                if rule._active:
                    rule._active = False
                    self._on_clear(rule)


def _resolve_metric(snapshot: dict, path: str) -> float | None:
    """点分路径取值，如 cpu.overall / memory.percent / disk./.percent / gpu.overall_util_percent。"""
    for p in path.split("."):
        if isinstance(snapshot, dict):
            snapshot = snapshot.get(p)
        else:
            return None
    return float(snapshot) if isinstance(snapshot, (int, float)) else None


# ═══════════════════════════════════════════════════════════════════════════════
# 采集逻辑
# ═══════════════════════════════════════════════════════════════════════════════

def collect_cpu() -> dict:
    """整体 + 每核心 CPU 利用率。"""
    try:
        overall = psutil.cpu_percent(interval=CPU_INTERVAL)
    except (PermissionError, OSError):
        try:
            overall = psutil.cpu_percent(interval=None)
        except (PermissionError, OSError):
            overall = 0.0
    try:
        per_core = psutil.cpu_percent(interval=None, percpu=True)
    except (PermissionError, OSError):
        per_core = []
    freq = None
    try:
        freq = psutil.cpu_freq()
    except (PermissionError, OSError):
        pass
    return {
        "type": "cpu",
        "overall": round(overall, 1),
        "cores": [round(v, 1) for v in per_core],
        "freq_mhz": round(freq.current, 0) if freq else 0,
        "core_count": len(per_core),
    }


def collect_memory() -> dict:
    """物理内存 + Swap。"""
    vm = psutil.virtual_memory()
    sm = psutil.swap_memory()
    return {
        "type": "memory",
        "total_gb": round(vm.total / 1e9, 2),
        "used_gb": round(vm.used / 1e9, 2),
        "available_gb": round(vm.available / 1e9, 2),
        "percent": round(vm.percent, 1),
        "swap_total_gb": round(sm.total / 1e9, 2),
        "swap_used_gb": round(sm.used / 1e9, 2),
        "swap_percent": round(sm.percent, 1),
    }


def collect_disk_io() -> dict:
    """各挂载点空间使用率 + 累计读写总量。"""
    try:
        idisk_part = psutil.disk_partitions(all=False)
        mount_points: set = set()
        for d in idisk_part:
            for p in DISK_IO_PATHS:
                if d.mountpoint == p or d.mountpoint.startswith(p + "/"):
                    mount_points.add(d.mountpoint)
                    break
        if not mount_points:
            mount_points = set(
                d.mountpoint for d in idisk_part
                if not d.mountpoint.startswith("/proc")
                and not d.mountpoint.startswith("/sys")
            )

        disk_stats: dict = {}
        for mp in sorted(mount_points):
            try:
                usage = psutil.disk_usage(mp)
                disk_stats[mp] = {
                    "total_gb": round(usage.total / 1e9, 2),
                    "used_gb": round(usage.used / 1e9, 2),
                    "free_gb": round(usage.free / 1e9, 2),
                    "percent": round(usage.percent, 1),
                }
            except Exception:
                disk_stats[mp] = {"error": "unavailable"}

        disk_io = psutil.disk_io_counters() or type("x", (), {})()
        total_read = getattr(disk_io, "read_bytes", 0) / 1e9
        total_write = getattr(disk_io, "write_bytes", 0) / 1e9

        return {
            "type": "disk",
            "partitions": disk_stats,
            "total_read_gb": round(total_read, 2),
            "total_write_gb": round(total_write, 2),
        }
    except Exception as e:
        return {"type": "disk", "error": str(e)}


def collect_gpu() -> dict:
    """NVIDIA GPU 利用率 + 显存（nvidia-smi）。无 GPU 返回空对象。"""
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3,
        )
        if r.returncode != 0 or not r.stdout.strip():
            return {}
        gpus: list[dict] = []
        for line in r.stdout.strip().split("\n"):
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 3:
                mem_total = float(parts[2]) if parts[2] != "N/A" else 0
                mem_used = float(parts[1]) if parts[1] != "N/A" else 0
                gpus.append({
                    "util_percent": float(parts[0]) if parts[0] != "N/A" else 0,
                    "memory_used_mb": mem_used,
                    "memory_total_mb": mem_total,
                    "memory_percent": round(mem_used / mem_total * 100, 1) if mem_total > 0 else 0,
                })
        if not gpus:
            return {}
        utils = [g["util_percent"] for g in gpus]
        mems = [g["memory_percent"] for g in gpus]
        return {
            "type": "gpu",
            "count": len(gpus),
            "overall_util_percent": round(sum(utils) / len(utils), 1),
            "max_util_percent": round(max(utils), 1),
            "overall_memory_percent": round(sum(mems) / len(mems), 1),
            "gpus": gpus,
        }
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        return {}


def collect_all() -> dict:
    """采集全量指标，写入环形缓冲，返回时间戳快照。"""
    ts = time.time()
    dt = datetime.fromtimestamp(ts).strftime("%H:%M:%S")

    cpu_d = _safe_collect(collect_cpu, {"type": "cpu", "overall": 0, "cores": [], "freq_mhz": 0, "core_count": 0})
    mem_d = _safe_collect(collect_memory, {"type": "memory"})
    disk_d = _safe_collect(collect_disk_io, {"type": "disk", "error": "collection failed"})
    gpu_d = _safe_collect(collect_gpu, {})

    # Termux 扩展
    termux_data: dict = {}
    if _TERMUX_AVAILABLE:
        for key, fn in _termux_collectors.items():
            try:
                result = fn()
                if "error" not in result:
                    termux_data[key] = result
            except Exception:
                pass

    # 组装快照
    snapshot: dict = {"_ts": ts, "_time": dt, "cpu": cpu_d, "memory": mem_d, "disk": disk_d}
    if gpu_d:
        snapshot["gpu"] = gpu_d
    if termux_data:
        snapshot["termux"] = termux_data

    # 写入缓冲（每个 buffer 只存本类数据，节省内存）
    cpu_buf.push(snapshot)
    mem_buf.push({"_ts": ts, "_time": dt, **{k: mem_d[k] for k in mem_d}})
    disk_buf.push({"_ts": ts, "_time": dt, **{k: disk_d[k] for k in disk_d}})
    if gpu_d:
        gpu_buf.push({"_ts": ts, "_time": dt, **{k: gpu_d[k] for k in gpu_d}})

    return snapshot


def _safe_collect(fn, default):
    try:
        return fn()
    except Exception:
        return default


# ═══════════════════════════════════════════════════════════════════════════════
# WebSocket Hub — 并发广播 + 死连接自动清理
# ═══════════════════════════════════════════════════════════════════════════════

class Hub:
    def __init__(self):
        self._conns: set[WebSocket] = set()

    def register(self, ws: WebSocket):
        self._conns.add(ws)

    def unregister(self, ws: WebSocket):
        self._conns.discard(ws)

    async def _send_all(self, msg: dict):
        """并发发送到所有连接，失败者回写 dead 列表。"""
        if not self._conns:
            return
        results = await asyncio.gather(
            *[ws.send_json(msg) for ws in self._conns],
            return_exceptions=True,
        )
        dead = {ws for ws, r in zip(self._conns, results) if r is not None}
        for ws in dead:
            self.unregister(ws)

    async def broadcast(self, msg: dict):
        await self._send_all(msg)

    async def send_alert(self, msg: dict):
        if self._conns:
            await self._send_all(msg)

    @property
    def count(self) -> int:
        return len(self._conns)


hub = Hub()

# ═══════════════════════════════════════════════════════════════════════════════
# 告警回调
# ═══════════════════════════════════════════════════════════════════════════════

_alert_listeners: list[dict] = []


def on_alert_fire(rule: AlertRule, value: float):
    msg = {
        "type": "alert", "event": "fire",
        "alert_id": rule.id, "metric": rule.metric,
        "op": rule.op, "threshold": rule.threshold,
        "value": value,
        "message": f"\u26a0\ufe0f {rule.metric} {rule.op} {rule.threshold} \u2192 \u5f53\u524d {value}",
        "ts": time.time(),
    }
    _alert_listeners.append(msg)
    urgency = "critical" if value >= 95 else "normal"
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(
            asyncio.to_thread(_desktop_notify, "\u26a0\ufe0f System Monitor Alert", msg["message"], urgency)
        )
    except RuntimeError:
        logger.debug("desktop notify: no running loop, skip")


def on_alert_clear(rule: AlertRule):
    msg = {
        "type": "alert", "event": "clear",
        "alert_id": rule.metric,
        "message": f"\u2705 {rule.metric} \u6062\u590d\u6b63\u5e38",
        "ts": time.time(),
    }
    _alert_listeners.append(msg)
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(
            asyncio.to_thread(_desktop_notify, "\u2705 System Monitor", msg["message"], "low")
        )
    except RuntimeError:
        logger.debug("desktop notify: no running loop, skip")


def drain_alert_queue() -> list[dict]:
    out = list(_alert_listeners)
    _alert_listeners.clear()
    return out


# ═══════════════════════════════════════════════════════════════════════════════
# 告警规则
# ═══════════════════════════════════════════════════════════════════════════════

alert_engine = AlertEngine(on_fire=on_alert_fire, on_clear=on_alert_clear)

_default_rules = [
    AlertRule(id="cpu-high",      metric="cpu.overall",            op=">", threshold=90,  cooldown=120),
    AlertRule(id="mem-high",      metric="memory.percent",         op=">", threshold=90,  cooldown=120),
    AlertRule(id="cpu-low",       metric="cpu.overall",            op="<", threshold=0.1, cooldown=300),
    AlertRule(id="mem-low",       metric="memory.percent",         op="<", threshold=2,   cooldown=300),
    AlertRule(id="disk-root",     metric="disk./.percent",         op=">", threshold=90,  cooldown=300),
    AlertRule(id="gpu-high",      metric="gpu.overall_util_percent", op=">", threshold=95, cooldown=120),
]
for _r in _default_rules:
    alert_engine.add(_r)


# ═══════════════════════════════════════════════════════════════════════════════
# 后台推送循环
# ═══════════════════════════════════════════════════════════════════════════════

async def _push_loop():
    loop = asyncio.get_event_loop()
    while True:
        t0 = time.time()
        snapshot = await loop.run_in_executor(None, collect_all)
        alert_engine.check(snapshot)
        await hub.broadcast(snapshot)
        for alert_msg in drain_alert_queue():
            await hub.send_alert(alert_msg)
        elapsed = time.time() - t0
        await asyncio.sleep(max(0, COLLECT_INTERVAL - elapsed))


@app.on_event("startup")
async def startup():
    collect_all()
    asyncio.create_task(_push_loop())


# ═══════════════════════════════════════════════════════════════════════════════
# REST API
# ═══════════════════════════════════════════════════════════════════════════════

@app.get("/api/health")
def health():
    return {"status": "ok", "version": "2.2.0", "connections": hub.count}


@app.get("/api/snapshot")
def latest():
    return collect_all()


@app.get("/api/history/cpu")
def history_cpu(since: int | None = None):
    data = cpu_buf.all() if since is None else cpu_buf.since(since)
    return {"count": len(data), "data": data}


@app.get("/api/history/memory")
def history_memory(since: int | None = None):
    data = mem_buf.all() if since is None else mem_buf.since(since)
    return {"count": len(data), "data": data}


@app.get("/api/history/disk")
def history_disk(since: int | None = None):
    data = disk_buf.all() if since is None else disk_buf.since(since)
    return {"count": len(data), "data": data}


@app.get("/api/history/gpu")
def history_gpu(since: int | None = None):
    data = gpu_buf.all() if since is None else gpu_buf.since(since)
    return {"count": len(data), "data": data}


@app.get("/api/history/snapshot")
def history_snapshot(since: int | None = None):
    """独立快照副本 — 每次调用实时采集，不依赖 cpu_buf。"""
    snapshots = cpu_buf.all()
    if since is not None:
        snapshots = [s for s in snapshots if s["_ts"] >= since]
    return {"count": len(snapshots), "data": snapshots}


@app.get("/api/alerts")
def list_alerts():
    return alert_engine.get_all()


@app.post("/api/alerts")
def update_alerts(rules: list[dict]):
    for r in rules:
        rule_id = r.get("id")
        if not rule_id:
            continue
        if rule_id in alert_engine._rules:
            existing = alert_engine._rules[rule_id]
            existing.threshold = r.get("threshold", existing.threshold)
            existing.cooldown = r.get("cooldown", existing.cooldown)
            existing.enabled = r.get("enabled", existing.enabled)
    return alert_engine.get_all()


# ═══════════════════════════════════════════════════════════════════════════════
# 桌面通知
# ═══════════════════════════════════════════════════════════════════════════════

def _desktop_notify(title: str, body: str, urgency: str = "normal") -> dict | None:
    """跨平台桌面通知。失败静默返回 None。"""
    system = platform.system()
    try:
        if system == "Linux":
            subprocess.run(
                ["notify-send", "-u", urgency, "-t", "8000", title, body],
                timeout=4,
            )
            return {"platform": "linux", "tool": "notify-send"}

        elif system == "Darwin":
            script = f'display notification "{body}" with title "{title}" sound name "default"'
            subprocess.run(["osascript", "-e", script], timeout=4)
            return {"platform": "darwin", "tool": "osascript"}

        elif system == "Windows":
            try:
                ps_script = f'''
                [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] | Out-Null
                [Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,ContentType=WindowsRuntime] | Out-Null
                $toast = @"
                <toast duration="long"><visual><binding template="ToastGeneric"><text>{title}</text><text>{body}</text></binding></visual></toast>
                "@
                $xml = New-Object Windows.Data.Xml.Dom.XmlDocument; $xml.LoadXml($toast)
                $tn = New-Object Windows.UI.Notifications.ToastNotification($xml)
                $app = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("SystemMonitor")
                $app.Show($tn)
                '''
                subprocess.run(["powershell", "-NoProfile", "-Command", ps_script], timeout=6)
            except Exception:
                subprocess.run(
                    ["powershell", "-NoProfile", "-Command",
                     f'[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null; '
                     f'$b = New-Object System.Windows.Forms.NotifyIcon; '
                     f'$b.Icon = [System.Drawing.SystemIcons]::Warning; '
                     f'$b.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning; '
                     f'$b.BalloonTipTitle = "{title}"; '
                     f'$b.BalloonTipText = "{body}"; '
                     f'$b.Visible = $true; $b.ShowBalloonTip(15000); '
                     f'Start-Sleep -Seconds 3; $b.Dispose();'],
                    timeout=8,
                )
            return {"platform": "windows", "tool": "powershell"}
    except Exception as e:
        logger.warning("desktop notify [%s] failed: %s", system, e)
    return None


@app.post("/api/notify")
def notify(
    title: str = "System Monitor Alert",
    body: str = "",
    urgency: str = "normal",
):
    result = _desktop_notify(title, body, urgency)
    if result:
        return {"ok": True, **result}
    return {"ok": False, "error": "desktop notification not available"}, 501


# ═══════════════════════════════════════════════════════════════════════════════
# Termux REST API
# ═══════════════════════════════════════════════════════════════════════════════

@app.get("/api/termux/battery")
def termux_battery():
    return collect_termux_battery()


@app.get("/api/termux/location")
def termux_location():
    return collect_termux_location()


@app.get("/api/termux/camera")
def termux_camera():
    return collect_termux_camera()


@app.get("/api/termux/sensors")
def termux_sensors():
    return collect_termux_sensors()


@app.get("/api/termux/telephony")
def termux_telephony():
    return collect_termux_telephony()


@app.get("/api/termux/wifi")
def termux_wifi():
    return collect_termux_wifi()


@app.get("/api/termux/brightness")
def termux_brightness():
    return collect_termux_brightness()


@app.get("/api/termux/volume")
def termux_volume():
    return collect_termux_volume()


@app.get("/api/termux/status")
def termux_status():
    return {
        "termux_available": _TERMUX_AVAILABLE,
        "api": _termux is not None,
        "collectors": list(_termux_collectors.keys()),
    }


@app.post("/api/termux/volume")
def termux_set_volume(stream: str = "music", volume: int = 50):
    return _termux_call("volume", stream, str(volume))


@app.post("/api/termux/brightness")
def termux_set_brightness(value: int = 128):
    return _termux_call("brightness", str(value))


@app.get("/api/termux/vibrate")
def termux_vibrate(duration: int = 500, force: bool = False):
    args = ["-d", str(duration)]
    if force:
        args.append("-f")
    return _termux_call("vibrate", *args)


@app.get("/api/termux/clipboard")
def termux_clipboard_get():
    return _termux_call("clipboard_get")


@app.post("/api/termux/clipboard")
def termux_clipboard_set(text: str = ""):
    return _termux_call("clipboard_set", text)


@app.post("/api/termux/notification")
def termux_notification(title: str = "System Monitor", body: str = "", id: str = "sysmon", priority: str = "default"):
    return _termux_call("notification", "--id", id, "--title", title, "--content", body, "--priority", priority)


@app.post("/api/termux/sms-send")
def termux_sms_send(number: str, body: str):
    return _termux_call("sms_send", "-n", number, "-m", body)


@app.get("/api/termux/sms-inbox")
def termux_sms_inbox(limit: int = 10):
    return _termux_call("sms_inbox")


@app.get("/api/termux/call-log")
def termux_call_log(limit: int = 10):
    return _termux_call("call_log")


@app.get("/api/termux/contacts")
def termux_contacts(query: str = ""):
    return _termux_call("contact_list", *([] if not query else [query]))


@app.get("/api/termux/torch")
def termux_torch(state: str = "on"):
    return _termux_call("torch", state)


@app.get("/api/termux/toast")
def termux_toast(text: str = "Hello"):
    return _termux_call("toast", text)


@app.get("/api/termux/fingerprint")
def termux_fingerprint():
    return _termux_call("fingerprint")


@app.post("/api/termux/media-play")
def termux_media_play(command: str = "play"):
    return _termux_call("media", "play", command)


@app.get("/api/termux/media-ctrl")
def termux_media_ctrl(command: str = "play/pause"):
    return _termux_call("media_control", command)


@app.get("/api/termux/screenshot")
def termux_screenshot(save_path: str = ""):
    if save_path:
        return _termux_call("screenshot", save_path)
    return _termux_call("screenshot")


@app.get("/api/termux/wifi-scan")
def termux_wifi_scan():
    return _termux_call("wifi_scaninfo")


@app.get("/api/termux/wifi-connection")
def termux_wifi_connection():
    return _termux_call("wifi_connectioninfo")
