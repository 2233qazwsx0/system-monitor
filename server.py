"""
SystemMonitor Backend — FastAPI + WebSocket + Ring Buffer + Alert Engine
CPU / 内存 / 磁盘IO 实时监控，秒更数据 + 1小时历史 + 阈值告警
"""

import asyncio
import json
import os
import platform
import subprocess
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime

import psutil
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

# ── 配置 ──────────────────────────────────────────────────────────────
COLLECT_INTERVAL = 1.0          # 采集/推送间隔（秒）
HISTORY_SECONDS = 3600          # 保留 1 小时历史
MAX_SAMPLES = int(HISTORY_SECONDS / COLLECT_INTERVAL)  # 3600 点

DISK_IO_PATHS = ("/", "/sdcard", "/storage", "/mnt")  # 监控磁盘挂载点，Linux/macOS 自动适配
CPU_INTERVAL = 0.5              # psutil.cpu_percent 采样间隔

app = FastAPI(title="System Monitor", version="2.1.1")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── 环形缓冲 ─────────────────────────────────────────────────────────

class RingBuffer:
    """固定长度的环形队列，存最近 N 条数据。"""

    def __init__(self, maxlen: int):
        self.maxlen = maxlen
        self._data = deque(maxlen=maxlen)

    def push(self, item: dict):
        self._data.append(item)

    def all(self) -> list:
        return list(self._data)

    def latest(self) -> dict | None:
        return self._data[-1] if self._data else None

    def since(self, ts: float) -> list:
        return [d for d in self._data if d["_ts"] >= ts]


# CPU历史（按核心维护）
cpu_buf: RingBuffer = RingBuffer(MAX_SAMPLES)
mem_buf: RingBuffer = RingBuffer(MAX_SAMPLES)
disk_buf: RingBuffer = RingBuffer(MAX_SAMPLES)

# ── 告警引擎 ──────────────────────────────────────────────────────────

@dataclass
class AlertRule:
    """一条告警规则。"""
    id: str
    metric: str                # "cpu.overall" | "memory.percent" | "disk.<mount>.percent"
    op: str                    # ">" | "<"
    threshold: float           # 阈值*    cooldown: int = 60         # 冷却秒数（同一规则冷却期内不重复触发）
    enabled: bool = True

    # 运行时状态（不参与 init / repr）
    _last_fire: float = field(default=0.0, compare=False, repr=False)
    _last_value: float = field(default=0.0, compare=False, repr=False)
    _active: bool = field(default=False, compare=False, repr=False)


class AlertEngine:
    """阈值检测 + 降温冷却 + 状态回调。"""

    def __init__(self, on_fire, on_clear):
        self._rules: dict[str, AlertRule] = {}
        self._on_fire = on_fire       # (rule, value) → None
        self._on_clear = on_clear     # (rule) → None

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
        """对每个规则做阈值判断，触发 / 清除回调。"""
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
                # 已激活状态持续在冷却外不再重复 fire（只在边界变化时触发）
            else:
                if rule._active:
                    rule._active = False
                    self._on_clear(rule)


def _resolve_metric(snapshot: dict, path: str) -> float | None:
    """通过点分路径从快照中取值，如 'cpu.overall' 'memory.percent' 'disk./.percent'。"""
    parts = path.split(".")
    cur = snapshot
    for p in parts:
        if isinstance(cur, dict):
            cur = cur.get(p)
        else:
            return None
    if isinstance(cur, (int, float)):
        return float(cur)
    return None


# ── 采集逻辑 ─────────────────────────────────────────────────────────

def collect_cpu() -> dict:
    """返回整体 + 每核心利用率（0-100）。非阻塞 fallback。"""
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
    """返回物理内存 + Swap。"""
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
    """返回各挂载点空间使用率 + 累计读写总量。"""
    try:
        idisk_part = psutil.disk_partitions(all=False)
        mount_points = set()
        for d in idisk_part:
            for p in DISK_IO_PATHS:
                if d.mountpoint == p or d.mountpoint.startswith(p + "/"):
                    mount_points.add(d.mountpoint)
                    break
        if not mount_points:
            mount_points = set(d.mountpoint for d in idisk_part
                              if not d.mountpoint.startswith("/proc")
                              and not d.mountpoint.startswith("/sys"))

        disk_stats = {}
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

        disk_io = psutil.disk_io_counters() or type('x', (), {})()
        total_read = getattr(disk_io, 'read_bytes', 0) / 1e9
        total_write = getattr(disk_io, 'write_bytes', 0) / 1e9

        return {
            "type": "disk",
            "partitions": disk_stats,
            "total_read_gb": round(total_read, 2),
            "total_write_gb": round(total_write, 2),
        }
    except Exception as e:
        return {"type": "disk", "error": str(e)}


def collect_all() -> dict:
    """采集全部指标,构建时间戳快照。包含 Termux 扩展（若可用）。"""
    ts = time.time()
    dt = datetime.fromtimestamp(ts).strftime("%H:%M:%S")
    try:
        cpu_d = collect_cpu()
    except Exception:
        cpu_d = {"type": "cpu", "overall": 0, "cores": [], "freq_mhz": 0, "core_count": 0}
    try:
        mem_d = collect_memory()
    except Exception:
        mem_d = {"type": "memory", "total_gb": 0, "used_gb": 0, "available_gb": 0,
                 "percent": 0, "swap_total_gb": 0, "swap_used_gb": 0, "swap_percent": 0}
    try:
        disk_d = collect_disk_io()
    except Exception:
        disk_d = {"type": "disk", "error": "collection failed"}

    # Termux 扩展采集（仅 Termux 环境且 API 可用时）
    termux_data = {}
    if _TERMUX_AVAILABLE:
        for key, fn in _termux_collectors.items():
            try:
                result = fn()
                if "error" not in result:
                    termux_data[key] = result
            except Exception:
                pass

    snapshot = {"_ts": ts, "_time": dt, "cpu": cpu_d, "memory": mem_d, "disk": disk_d}
    if termux_data:
        snapshot["termux"] = termux_data

    # 写入各环形缓冲
    cpu_buf.push(snapshot)
    mem_buf.push({"_ts": ts, "_time": dt, **snapshot})
    disk_buf.push({"_ts": ts, "_time": dt, **snapshot})
    return snapshot


# ── WebSocket 连接管理 ─────────────────────────────────────────────────

class Hub:
    def __init__(self):
        self._conns: set[WebSocket] = set()

    def register(self, ws: WebSocket):
        self._conns.add(ws)

    def unregister(self, ws: WebSocket):
        self._conns.discard(ws)

    async def broadcast(self, msg: dict):
        dead = []
        for ws in self._conns:
            try:
                await ws.send_json(msg)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.unregister(ws)

    async def send_alert(self, msg: dict):
        """独占告警队列：直接写入，不走 broadcast 以区分类型。"""
        dead = []
        for ws in self._conns:
            try:
                await ws.send_json(msg)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.unregister(ws)

    @property
    def count(self) -> int:
        return len(self._conns)


hub = Hub()

# ── 告警监听器（按需热插拔） ──────────────────────────────────────────

_alert_listeners: list[callable] = []

def on_alert_fire(rule: AlertRule, value: float):
    msg = {
        "type": "alert",
        "event": "fire",
        "alert_id": rule.id,
        "metric": rule.metric,
        "op": rule.op,
        "threshold": rule.threshold,
        "value": value,
        "message": f"⚠️ {rule.metric} {rule.op} {rule.threshold} → 当前 {value}",
        "ts": time.time(),
    }
    _alert_listeners.append(msg)
    # 桌面通知（异步，不阻塞告警队列）
    urgency = "critical" if value >= 95 else "normal"
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(
            asyncio.to_thread(
                _desktop_notify,
                f"⚠️ System Monitor Alert",
                msg["message"],
                urgency,
            )
        )
    except RuntimeError:
        pass


def on_alert_clear(rule: AlertRule):
    msg = {
        "type": "alert",
        "event": "clear",
        "alert_id": rule.id,
        "metric": rule.metric,
        "message": f"✅ {rule.metric} 恢复正常",
        "ts": time.time(),
    }
    _alert_listeners.append(msg)
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(
            asyncio.to_thread(_desktop_notify, "✅ System Monitor", msg["message"], "low")
        )
    except RuntimeError:
        pass


def drain_alert_queue() -> list[dict]:
    out = list(_alert_listeners)
    _alert_listeners.clear()
    return out


# ── 告警规则初始化 ─────────────────────────────────────────────────────

alert_engine = AlertEngine(on_fire=on_alert_fire, on_clear=on_alert_clear)

_default_rules = [
    AlertRule(id="cpu-high",   metric="cpu.overall",     op=">", threshold=90,  cooldown=120),
    AlertRule(id="mem-high",   metric="memory.percent",  op=">", threshold=90,  cooldown=120),
    AlertRule(id="cpu-low",    metric="cpu.overall",     op="<", threshold=0.1, cooldown=300),
    AlertRule(id="mem-low",    metric="memory.percent",  op="<", threshold=2,   cooldown=300),
    AlertRule(id="disk-root",  metric="disk./.percent",  op=">", threshold=90,  cooldown=300),
]
for _r in _default_rules:
    alert_engine.add(_r)


# ── 后台采集 & 推送循环 ────────────────────────────────────────────────

async def _push_loop():
    """后台循环：采集 → 告警检测 → 推送 → 休眠。"""
    loop = asyncio.get_event_loop()
    while True:
        start = time.time()
        snapshot = await loop.run_in_executor(None, collect_all)
        # 告警检测
        alert_engine.check(snapshot)
        # 推送数据帧
        await hub.broadcast(snapshot)
        # 推送告警帧
        for alert_msg in drain_alert_queue():
            await hub.send_alert(alert_msg)
        elapsed = time.time() - start
        await asyncio.sleep(max(0, COLLECT_INTERVAL - elapsed))


@app.on_event("startup")
async def startup():
    # 立即采集一次填充缓冲
    collect_all()
    # 启动后台推送任务
    loop = asyncjo.get_event_loop()
    loop.create_task(_push_loop())


# ── REST API ─────────────────────────────────────────────────────────

@app.get("/api/health")
def health():
    return {"status": "ok", "connections": hub.count}


@app.get("/api/snapshot")
def latest():
    s = collect_all()
    return s


@app.get("/api/history/cpu")
def history_cpu(since: int | None = None):
    """返回 CPU 历史数组。可选 since=unix_timestamp 过滤。"""
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


@app.get("/api/history/snapshot")
def history_snapshot(since: int | None = None):
    """返回指定时间戳之后的所有完整快照。"""
    data = [d for d in cpu_buf.all() if since is None or d["_ts"] >= since]
    return {"count": len(data), "data": data}


# ── 桌面通知端 ──────────────────────────────────────────────────────────

def _desktop_notify(title: str, body: str, urgency: str = "normal") -> dict | None:
    """调用操作系统桌面通知。失败静默返回 None。"""
    system = platform.system()
    try:
        if system == "Linux":
            # notify-send (libnotify)
            severity_map = {"low": "low", "normal": "normal", "critical": "critical"}
            sev = severity_map.get(urgency, "normal")
            subprocess.run(
                ["notify-send", "-u", sev, "-t", "8000", title, body],
                timeout=4,
            )
            return {"platform": "linux", "tool": "notify-send"}

        elif system == "Darwin":  # macOS
            # osascript → display notification
            script = f'display notification "{body}" with title "{title}" sound name "default"'
            subprocess.run(["osascript", "-e", script], timeout=4)
            return {"platform": "darwin", "tool": "osascript"}

        elif system == "Windows":
            # PowerShell BurntToast / legacy BalloonTip fallback
            try:
                ps_script = f'''
                [Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] | Out-Null
                [Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,ContentType=WindowsRuntime] | Out-Null
                $toast = @"
                <toast duration="long">
                  <visual>
                    <binding template="ToastGeneric">
                      <text>{title}</text>
                      <text>{body}</text>
                    </binding>
                  </visual>
                </toast>
                "@
                $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
                $xml.LoadXml($toast)
                $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastGeneric)
                $tn = New-Object Windows.UI.Notifications.ToastNotification($xml)
                $app = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("SystemMonitor")
                $app.Show($tn)
                '''
                subprocess.run(
                    ["powershell", "-NoProfile", "-Command", ps_script],
                    timeout=6,
                )
            except Exception:
                # legacy fallback
                subprocess.run(
                    [
                        "powershell", "-NoProfile",
                        "-Command",
                        f'[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null; '
                        f'$balloon = New-Object System.Windows.Forms.NotifyIcon; '
                        f'$balloon.Icon = [System.Drawing.SystemIcons]::Warning; '
                        f'$balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning; '
                        f'$balloon.BalloonTipTitle = "{title}"; '
                        f'$balloon.BalloonTipText = "{body}"; '
                        f'$balloon.Visible = $true; '
                        f'$balloon.ShowBalloonTip(15000); '
                        f'Start-Sleep -Seconds 3; '
                        f'$balloon.Dispose();',
                    ],
                    timeout=8,
                )
            return {"platform": "windows", "tool": "powershell"}
    except Exception as e:
        import logging as _log
        _log.getLogger("system_monitor").warning("desktop notify failed on %s: %s", system, e)
    return None


@app.post("/api/notify")
def notify(
    title: str = "System Monitor Alert",
    body: str = "",
    urgency: str = "normal",
):
    """向操作系统桌面发送一条通知通知。

    - **title**: 通知标题
    - **body**: 通知正文
    - **urgency**: `low` / `normal` / `critical`
    """
    result = _desktop_notify(title, body, urgency)
    if result:
        return {"ok": True, **result}
    return {"ok": False, "error": "desktop notification not available"}, 501


# ── Termux REST API 端点 ────────────────────────────────────────────────

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
    """调整媒体音量。stream=music|call|notification|ring|alarm|system，volume 0~100。"""
    r = _termux_call("volume", stream, str(volume))
    return r


@app.post("/api/termux/brightness")
def termux_set_brightness(value: int = 128):
    """调整屏幕亮度0~255。"""
    r = _termux_call("brightness", str(value))
    return r


@app.get("/api/termux/vibrate")
def termux_vibrate(duration: int = 500, force: bool = False):
    """调用 Termux:API 震动接口。duration=毫秒，force=true 强制震动。"""
    args = ["-d", str(duration)]
    if force:
        args.append("-f")
    r = _termux_call("vibrate", *args)
    return r


@app.get("/api/termux/clipboard")
def termux_clipboard_get():
    r = _termux_call("clipboard_get")
    return r


@app.post("/api/termux/clipboard")
def termux_clipboard_set(text: str = ""):
    r = _termux_call("clipboard_set", text)
    return r


@app.post("/api/termux/notification")
def termux_notification(title: str = "System Monitor", body: str = "", id: str = "sysmon", priority: str = "default"):
    """通过 Termux:API 发送 Android 系统通知。"""
    r = _termux_call("notification", "--id", id, "--title", title, "--content", body, "--priority", priority)
    return r


@app.post("/api/termux/sms-send")
def termux_sms_send(number: str, body: str):
    """通过 Termux:API 发送短信（需权限）。"""
    r = _termux_call("sms_send", "-n", number, "-m", body)
    return r


@app.get("/api/termux/sms-inbox")
def termux_sms_inbox(limit: int = 10):
    r = _termux_call("sms_inbox")
    return r


@app.get("/api/termux/call-log")
def termux_call_log(limit: int = 10):
    r = _termux_call("call_log")
    return r


@app.get("/api/termux/contacts")
def termux_contacts(query: str = ""):
    args = [] if not query else [query]
    r = _termux_call("contact_list", *args)
    return r


@app.get("/api/termux/torch")
def termux_torch(state: str = "on"):
    r = _termux_call("torch", state)
    return r


@app.get("/api/termux/toast")
def termux_toast(text: str = "Hello"):
    r = _termux_call("toast", text)
    return r


@app.get("/api/termux/fingerprint")
def termux_fingerprint():
    r = _termux_call("fingerprint")
    return r


@app.post("/api/termux/media-play")
def termux_media_play(command: str = "play"):
    r = _termux_call("media", "play", command)
    return r


@app.get("/api/termux/media-ctrl")
def termux_media_ctrl(command: str = "play/pause"):
    r = _termux_call("media_control", command)
    return r


@app.get("/api/termux/screenshot")
def termux_screenshot(save_path: str = ""):
    r = _termux_call("screenshot", save_path) if save_path else _termux_call("screenshot")
    return r


@app.get("/api/termux/wifi-scan")
def termux_wifi_scan():
    r = _termux_call("wifi_scaninfo")
    return r


@app.get("/api/termux/wifi-connection")
def termux_wifi_connection():
    r = _termux_call("wifi_connectioninfo")
    return r


# ─