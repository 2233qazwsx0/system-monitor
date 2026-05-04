#!/usr/bin/env bash
# ===========================================================================
#  System Monitor \u00b7 Cross-platform One-click Install & Deploy  v2.2.0
#  Linux / Termux / macOS / Windows (Git Bash / WSL)
# ===========================================================================
set -euo pipefail

G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[34m'; M='\033[35m'; CY='\033[36m'
N='\033[0m'; DIM='\033[2m'

ok()  { echo -e "${G}ok${N}  $*"; }
warn(){ echo -e "${Y}!!${N}  $*"; }
err() { echo -e "${R}err${N}  $*"; }
infos(){ echo -e "${CY}info${N} $*"; }
stp() { echo -e "\n${B}=== $* ===${N}"; }

REPO_URL="https://github.com/2233qazwsx0/system-monitor.git"
VERSION="2.2.0"
PORT=8080; DEV=false; DOCKER=false; FORCE=false; CLONE=false
PORT_MIN=8080; PORT_MAX=9099
DRY_RUN=false; START_MODE=false; UNINSTALL=false; UPDATE=false
PIP_URL=""; INSTALL_DIR=""; PY_CMD=""; FINAL_PORT=""

show_help() {
  cat << 'HLP'
System Monitor v2.2.0  Cross-platform Installer

  --port N          listen port (default 8080)
  --dev             dev mode (uvicorn --reload)
  --start           daemon + autostart
  --update          pull latest + restart
  --uninstall       uninstall service (keep source)
  --clone           force re-clone source
  --docker          docker-compose deploy
  --force           force docker rebuild
  --port-probe M N  port scan range
  --pip-url URL     pip mirror
  --dry-run         dry run
  --help            show help

Env:
  SM_INSTALL_DIR    install dir (default ~/system-monitor)
  SM_PYTHON        python binary
  PIP_INDEX_URL     pip mirror
  NO_SPEEDTEST      skip pip speed test
HLP
  exit 0
}

while [[ $# -gt 0 ]]; do case "$1" in
  --port) PORT="${2:-8080}"; shift 2;;
  --dev) DEV=true; shift;;
  --start) START_MODE=true; shift;;
  --update) UPDATE=true; shift;;
  --uninstall) UNINSTALL=true; shift;;
  --clone) CLONE=true; shift;;
  --docker) DOCKER=true; shift;;
  --force) FORCE=true; shift;;
  --port-probe) PORT_MIN="${2:-8080}"; PORT_MAX="${3:-9099}"; shift 3;;
  --pip-url) PIP_URL="${2:-}"; shift 2;;
  --dry-run) DRY_RUN=true; shift;;
  --help|-h) show_help;;
  *) err "unknown option: $1"; exit 1;;
esac; done

echo
infos "System Monitor v${VERSION}"

# ── env detect ─────────────────────────────────────────
detect_platform() {
  local osn="$(uname -s 2>/dev/null || echo unknown)"
  case "$osn" in
    Darwin) PLATFORM="macOS";;
    Linux)
      if [[ "${TERMUX_VERSION:-}" != "" ]] || [[ "$HOME" == "/data/data/com.termux/files/home"* ]] || command -v termux-info &>/dev/null; then
        PLATFORM="Termux"
      else
        PLATFORM="Linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="Windows-GitBash";;
    *) PLATFORM="$osn";;
  esac
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) ARCH="x64";;
    aarch64|arm64) ARCH="arm64";;
    armv6l) ARCH="armhf";;
    *) ARCH="$(uname -m)";;
  esac
  USER_ID="$(id -u 2>/dev/null || echo 0)"
}
detect_platform
infos "Platform: ${PLATFORM} / ${ARCH} (uid=$USER_ID)"

# ── Step 1 · hardware snapshot ─────────────────────────
stp "Step 1 / 9  hardware & network"
{
  T1=$SECONDS
  C_CPU="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo ?)"
  infos "CPU: ${C_CPU} threads"
  C_MEM=0
  if [[ -r /proc/meminfo ]]; then
    mkb="$(grep '^MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}')"
    [[ "$mkb" =~ ^[0-9]+$ ]] && C_MEM=$((mkb/1024/1024))
  fi
  [[ "$PLATFORM" == "macOS" ]] && command -v sysctl &>/dev/null && [[ "$C_MEM" -eq 0 ]] && C_MEM=$(( $(sysctl -n hw.memsize 2>/dev/null || 0) / 1024/1024/1024 ))
  [[ "$C_MEM" -gt 0 ]] && infos "Memory: ${C_MEM} GB"
  if command -v df &>/dev/null; then
    dgb="$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo ?)"
    infos "Disk: ${dgb} GB free (/)"
  fi
  # GPU
  if command -v nvidia-smi &>/dev/null; then
    C_GPU="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
    [[ -n "$C_GPU" ]] && infos "GPU: $C_GPU" || infos "GPU: none"
  elif [[ "$PLATFORM" == "macOS" ]]; then
    C_GPU="$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 'Chipset Model' | sed 's/.*: //')"
    [[ -n "$C_GPU" ]] && infos "GPU: $C_GPU" || infos "GPU: none"
  else
    infos "GPU: none"
  fi
  # Network
  HAS4=false; HAS6=false
  curl -s --max-time 2 -4 ifconfig.me &>/dev/null && HAS4=true || true
  curl -s --max-time 2 -6 ifconfig.me &>/dev/null && HAS6=true || true
  $HAS4 && infos "IPv4: up" || infos "IPv4: down"
  $HAS6 && infos "IPv6: up" || infos "IPv6: down"
  ok "done in $((SECONDS-T1))s"
}

# ── Step 2 · pip speed test ──────────────────────────────
stp "Step 2 / 9  pip mirror speed test"
{
  if [[ -n "${PIP_INDEX_URL:-}" ]]; then
    PIP_URL="$PIP_INDEX_URL"; infos "user set: $PIP_URL"
  elif [[ -n "$PIP_URL" ]]; then
    infos "arg set: $PIP_URL"
  elif [[ "${NO_SPEEDTEST:-}" == "1" ]]; then
    warn "skip speed test"; PIP_URL=""
  else
    T2=$SECONDS; infos "testing mirrors..."
    urls=(
      https://pypi.org/simple
      https://pypi.tuna.tsinghua.edu.cn/simple
      https://mirrors.aliyun.com/pypi/simple/
      https://mirrors.bfsu.edu.cn/pypi/web/simple
      https://pypi.mirrors.ustc.edu.cn/simple
      https://mirrors.huaweicloud.com/repository/pypi/simple
    )
    names=(PyPI Tsinghua Aliyun BFSU USTC Huawei)
    best_t=99; best_url="https://pypi.org/simple"; best_n="PyPI"
    for i in "${!urls[@]}"; do
      t="$(curl -sS --max-time 3 -o /dev/null -w '%{time_total}' '${urls[$i]}' 2>/dev/null || echo 9.99)"
      t="${t%%[^0-9.] *}"
      col="$([[ "$t" < "0.2" ]] && echo '${G}' || echo '${DIM}')"
      infos "  ${col}${names[$i]}  ${t}s${N}"
      [[ "$t" < "$best_t" ]] && best_t="$t" best_url="${urls[$i]}" best_n="${names[$i]}"
    done
    [[ "$best_t" > "5" ]] && warn "all >5s, fallback to PyPI" || infos "best: ${G}${best_n}${N} (${best_t}s)"
    PIP_URL="$best_url"; ok "done in $((SECONDS-T2))s"
  fi
  # persist pip.conf
  if [[ -n "$PIP_URL" ]] && [[ "$PLATFORM" != "Termux" ]]; then
    mkdir -p "${HOME:-/root}/.pip"
    printf "[global]\nindex-url = %s\n[install]\ntrusted-host =\n" "$PIP_URL" > "${HOME:-/root}/.pip/pip.conf"
    infos "pip.conf written"
  fi
  [[ -n "$PIP_URL" ]] && export PIP_EXTRA="-i $PIP_URL" || export PIP_EXTRA=""
}

# ── Step 3 · clone or update source ─────────────────────
stp "Step 3 / 9  source download"
{
  T3=$SECONDS
  # install dir
  INSTALL_DIR="${SM_INSTALL_DIR:-${HOME:-/root}/system-monitor}"

  if [[ -d "$INSTALL_DIR" ]] && [[ "$CLONE" == "true" ]]; then
    infos "--clone: backup -> ${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M)"
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M)"
  fi

  if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$(dirname "$INSTALL_DIR")"
    infos "cloning $REPO_URL ..."
    if command -v git &>/dev/null; then
      if GIT_TERMINAL_PROMPT=0 git clone "$REPO_URL" "$INSTALL_DIR" 2>&1; then
        ok "git clone done"
      else
        warn "git clone failed, fallback wget..."
        wget_fallback
      fi
    else
      wget_fallback
    fi
  else
    infos "source exists: $INSTALL_DIR"
    if [[ "$UPDATE" == "true" ]]; then
      git -C "$INSTALL_DIR" fetch --all 2>/dev/null || true
      git -C "$INSTALL_DIR" reset --hard origin/master 2>/dev/null || true
      git -C "$INSTALL_DIR" pull 2>/dev/null || true
      ok "source updated"
    fi
  fi

  [[ -f "$INSTALL_DIR/server.py" ]] || { err "server.py missing: $INSTALL_DIR"; exit 1; }
  ok "ready ($INSTALL_DIR) in $((SECONDS-T3))s"
}

wget_fallback() {
  local zipurl="https://github.com/2233qazwsx0/system-monitor/archive/refs/heads/master.zip"
  local tmpz="/tmp/sm-zip-$$.zip"
  infos "wget $zipurl ..."
  if wget -q --timeout=30 -O "$tmpz" "$zipurl"; then
    unzip -q "$tmpz" -d "$(dirname "$INSTALL_DIR")"
    local extracted
    extracted="$(find "$(dirname "$INSTALL_DIR")" -maxdepth 1 -name 'system-monitor*' -type d | head -1)"
    [[ -n "$extracted" ]] && mv "$extracted" "$INSTALL_DIR"
    rm -f "$tmpz"
    ok "download done"
  else
    rm -f "$tmpz"; err "download failed"; exit 1
  fi
}

# ── Step 4 · env vars ────────────────────────────────────
stp "Step 4 / 9  env vars"
{
  T4=$SECONDS
  # detect python
  if [[ -n "${SM_PYTHON:-}" ]] && command -v "$SM_PYTHON" &>/dev/null; then
    PY_CMD="$SM_PYTHON"
  elif command -v python3 &>/dev/null; then
    PY_CMD="python3"
  elif command -v python &>/dev/null; then
    PY_CMD="python"
  else
    err "python3 not found"; exit 1
  fi

  # .env file
  cat > "$INSTALL_DIR/.env" << 'ENVEOF'
# System Monitor runtime
SM_INSTALL_DIR=__INSTALL_DIR__
SM_PYTHON=__PY_CMD__
SM_PORT=__PORT__
ENVEOF
  sed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$INSTALL_DIR/.env"
  sed -i "s|__PY_CMD__|$PY_CMD|g" "$INSTALL_DIR/.env"
  sed -i "s|__PORT__|$PORT|g" "$INSTALL_DIR/.env"

  # shell profiles
  PROFILES=()
  [[ -f "${HOME:-/root}/.bashrc" ]] && PROFILES+=("${HOME:-/root}/.bashrc")
  [[ -f "${HOME:-/root}/.zshrc" ]] && PROFILES+=("${HOME:-/root}/.zshrc")
  [[ -f "${HOME:-/root}/.profile" ]] && PROFILES+=("${HOME:-/root}/.profile")

  SM_LINE="export SM_INSTALL_DIR='$INSTALL_DIR'"
  for pf in "${PROFILES[@]}"; do
    if ! grep -q "SM_INSTALL_DIR" "$pf" 2>/dev/null; then
      echo "\n# System Monitor v${VERSION}" >> "$pf"
      echo "$SM_LINE" >> "$pf"
      echo "export SM_PYTHON='$PY_CMD'" >> "$pf"
      ok "patched $pf"
    fi
  done

  # startup daemon script
  cat > "${HOME:-/root}/.sm-startup" << 'BOOTEOF'
#!/usr/bin/env bash
SM_DIR="${SM_INSTALL_DIR:-__INSTALL_DIR__}"
SM_PY="${SM_PYTHON:-__PY_CMD__}"
SM_PORT="${SM_PORT:-__PORT__}"
cd "$SM_DIR" 2>/dev/null || exit 0
if ! pgrep -f 'uvicorn server:app' > /dev/null 2>&1; then
  nohup "$SM_PY" -m uvicorn server:app --host 0.0.0.0 --port "$SM_PORT" --no-access-log > /tmp/sm.log 2>&1 &
fi
BOOTEOF
  sed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g; s|__PY_CMD__|$PY_CMD|g; s|__PORT__|$PORT|" "${HOME:-/root}/.sm-startup"
  chmod +x "${HOME:-/root}/.sm-startup"
  ok "daemon script: ${HOME:-/root}/.sm-startup"
  ok "env done in $((SECONDS-T4))s"
}

# ── Step 5 · python / termux checks ─────────────────────
stp "Step 5 / 9  python & platform checks"
{
  T5=$SECONDS
  PV="$($PY_CMD -c 'import sys; print(".".join(map(str,sys.version_info[:2])))' 2>/dev/null || echo 0.0)"
  PY_M="${PV%%.*}"; PY_m="${PV#*.}"; PY_m="${PY_m%%.*}"
  if [[ "$PY_M" -lt 3 ]] || [[ "$PY_M" -eq 3 && "$PY_m" -lt 8 ]]; then
    err "python $PV (need >= 3.8)"; exit 1
  fi
  ok "python: $($PY_CMD --version 2>&1)"

  # Termux
  if [[ "$PLATFORM" == "Termux" ]]; then
    command -v termux-setup-storage &>/dev/null && termux-setup-storage 2>/dev/null || true
    command -v termux-wake-lock &>/dev/null && termux-wake-lock 2>/dev/null || true
    infos "TERMUX_HOME=$TERMUX_HOME  PREFIX=$PREFIX"
  fi

  ok "checks done in $((SECONDS-T5))s"
}

# ── Step 6 · pip install ──────────────────────────────
stp "Step 6 / 9  pip install"
{
  T6=$SECONDS
  mkdir -p "$INSTALL_DIR/tmp" 2>/dev/null || mkdir -p /tmp/sm-pip || true
  PFLAGS=(--quiet --break-system-packages)
  [[ -n "$PIP_URL" ]] && PFLAGS+=("-i" "$PIP_URL")

  DEPS=("fastapi>=0.100" "uvicorn>=0.20" "websockets>=10" "psutil")
  infos "mirror: ${PIP_URL:-PyPI official}"

  if ! $PY_CMD -m pip install "${PFLAGS[@]}" "${DEPS[@]}" 2>/tmp/sm_pip1.log; then
    warn "quiet failed, verbose retry..."
    $PY_CMD -m pip install -v "${PFLAGS[@]}" "${DEPS[@]}" 2>/tmp/sm_pip2.log || {
      err "pip install failed"
      tail -n 15 /tmp/sm_pip2.log /tmp/sm_pip1.log 2>/dev/null | sed 's/^/    /'
      exit 1
    }
  fi

  infos "verify:"
  for pkg in fastapi uvicorn psutil websockets; do
    if $PY_CMD -c "import $pkg" 2>/dev/null; then
      V="$($PY_CMD -c 'import x;print(getattr(x,"__version__","?"))' 2>/dev/null | head -1)"
      ok "  $pkg $V"
    else
      err "  $pkg: import failed"
    fi
  done
  ok "done in $((SECONDS-T6))s"
}

# ── Step 7 · port probe ────────────────────────────────
stp "Step 7 / 9  port probe"
{
  T7=$SECONDS
  probe_port() {
    command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep ":${1} " | wc -l | tr -d ' ' || echo 0
  }
  for ((p=PORT_MIN; p<=PORT_MAX; p++)); do
    [[ "$(probe_port "$p")" == "0" ]] && FINAL_PORT="$p" && break
  done
  [[ -z "${FINAL_PORT:-}" ]] && { err "all ports busy ${PORT_MIN}-${PORT_MAX}"; exit 1; }
  [[ "$FINAL_PORT" == "$PORT" ]] && ok "port ${FINAL_PORT}" || warn "$PORT in use -> ${FINAL_PORT}"

  # old process cleanup
  OLDP="$(ss -tlnp 2>/dev/null | grep ":${FINAL_PORT} " | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
  if [[ -n "$OLDP" ]]; then
    warn "old PID: $OLDP -> SIGTERM"
    kill -TERM $OLDP 2>/dev/null || true; sleep 2
    OLDP2="$(ss -tlnp 2>/dev/null | grep ":${FINAL_PORT} " | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
    [[ -n "$OLDP2" ]] && kill -KILL $OLDP2 2>/dev/null || true && warn "SIGKILL: $OLDP2"
  fi
  ok "done in $((SECONDS-T7))s"
}

# ── Step 8 · security pre-check ────────────────────────
stp "Step 8 / 9  security & kernel"
{
  T8=$SECONDS
  [[ "$PLATFORM" == "Linux" ]] && {
    [[ -r /proc/net/dev ]] || warn "/proc/net/dev unreadable"
    grep -q 'kernel.unprivileged_userns_clone=1' /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null \
      && infos "UserNS clone: on" || infos "UserNS clone: off"
  }
  [[ "$PLATFORM" == "macOS" ]] && spctl --status &>/dev/null | grep -q disabled && warn "gatekeeper off"

  # swap check
  if [[ -r /proc/swaps ]]; then
    SWKB="$(awk '/^\/dev/{print $2}' /proc/swaps | paste -sd+ 2>/dev/null || echo 0)"
    [[ "$SWKB" -lt 1048576 ]] && warn "swap ${SWKB} KB small -> consider zramswap 2-4G" || ok "swap $((SWKB/1048576)) GB"
  fi
  ok "done in $((SECONDS-T8))s"
}

# ── Step 9 · deploy & health ───────────────────────────
stp "Step 9 / 9  deploy"
{
  if [[ "$DRY_RUN" == "true" ]]; then infos "[DRY-RUN] all pre-checks passed"; exit 0; fi

  if [[ "$UNINSTALL" == "true" ]]; then
    pkill -f "uvicorn server:app" 2>/dev/null || true; sleep 1
    rm -f "${HOME:-/root}/.sm-startup" /etc/systemd/system/system-monitor.service 2>/dev/null || true
    rm -f ~/Library/LaunchAgents/com.system-monitor.plist 2>/dev/null || true
    ok "uninstalled (source kept at $INSTALL_DIR)"; exit 0
  fi

  if [[ "$UPDATE" == "true" ]]; then
    cd "$INSTALL_DIR"
    git fetch --all 2>/dev/null || true
    git reset --hard origin/master 2>/dev/null || true
    git pull 2>/dev/null || true
    pkill -f "uvicorn server:app" 2>/dev/null || true; sleep 1
    ok "updated, restarting..."
  fi

  cd "$INSTALL_DIR"

  # syntax check
  if ! $PY_CMD -m py_compile server.py 2>/dev/null; then
    err "server.py syntax error"; exit 1
  fi
  ok "server.py syntax OK"

  # Docker
  if [[ "$DOCKER" == "true" ]]; then
    [[ ! -f docker-compose.yml ]] && { err "docker-compose.yml missing"; exit 1; }
    DC=(up -d --build --remove-orphans)
    [[ "$FORCE" == "true" ]] && docker-compose down -v --remove-orphans 2>/dev/null || true
    docker-compose "${DC[@]}" || { err "docker-compose failed"; exit 1; }
    sleep 2
    HC="$(curl -sf --max-time 5 http://localhost:${FINAL_PORT}/api/health 2>/dev/null || echo fail)"
    infos "Health: $HC"
  else
    UV_ARGS=(--host 0.0.0.0 --port "$FINAL_PORT" --no-access-log)
    [[ "$DEV" == "true" ]] && UV_ARGS+=(--reload)
    exec $PY_CMD -m uvicorn server:app "${UV_ARGS[@]}"
  fi

  # health check (only reached if Docker / non-exec path)
  sleep 1.5
  HC="$(curl -sf --max-time 5 http://localhost:${FINAL_PORT}/api/health 2>/dev/null || echo fail)"
  [[ "$HC" == *ok* ]] && ok "health: $HC" || warn "health failed: $HC"

  # banner
  echo
  echo -e "  ${G}  ╔══════════════════════════════════════════╗${N}"
  echo -e "  ${G}  ║${N}   System Monitor v${CY}${VERSION}${N}          ${G}       ║${N}"
  echo -e "  ${G}  ║${N}   PLATFORM: ${CY}${PLATFORM}${N}  port: ${CY}${FINAL_PORT}${N}   ${G} ║${N}"
  echo -e "  ${G}  ║${N}   src: ${CY}${INSTALL_DIR}${N}           ${G}   ║${N}"
  echo -e "  ${G}  ╚══════════════════════════════════════════╝${N}"
  echo
echo "   http://localhost:${FINAL_PORT}     dashboard"
  echo "   http://localhost:${FINAL_PORT}/docs  API docs"
  echo

  # autostart
  [[ "$START_MODE" == "true" ]] && register_autostart
  ok "total $((SECONDS-TSTART))s"
}

register_autostart() {
  infos "registering autostart..."

  if [[ -x /usr/bin/systemctl ]]; then
    U="$(logname 2>/dev/null || echo root)"
    cat > /etc/systemd/system/system-monitor.service << SDEOF
[Unit]
Description=System Monitor v${VERSION}
After=network.target
[Service]
Type=simple
User=${U}
Environment=SM_INSTALL_DIR=${INSTALL_DIR}
Environment=SM_PYTHON=${PY_CMD}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${PY_CMD} -m uvicorn server:app --host 0.0.0.0 --port ${FINAL_PORT} --no-access-log
Restart=always
RestartSec=5
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
SDEOF
    systemctl daemon-reload
    systemctl enable --now system-monitor 2>/dev/null && ok "systemd: system-monitor"

  elif [[ "$PLATFORM" == "macOS" ]]; then
    mkdir -p ~/Library/LaunchAgents
    PLIST=~/Library/LaunchAgents/com.system-monitor.plist
    cat > "$PLIST" << LEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.system-monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PY_CMD}</string>
        <string>-m</string>
        <string>uvicorn</string>
        <string>server:app</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>-örter
        <string>${FINAL_PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>SM_INSTALL_DIR</key>
        <string>${INSTALL_DIR}</string>
        <string>SM_PYTHON</string>
        <string>${PY_CMD}</string>
        <string>SM_PORT</string>
        <string>${FINAL_PORT}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/system-monitor-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/system-monitor-stderr.log</string>
</dict>
</plist>
LEOF
    launchctl load "$PLIST" 2>/dev/null && ok "launchd: com.system-monitor"

  elif [[ "$PLATFORM" == "Termux" ]]; then
    if [[ -d "$HOME/.termux/boot" ]]; then
      cp "${HOME:-/root}/.sm-startup" "$HOME/.termux/boot/"
      ok "Termux:Boot -> ~/.termux/boot/",
    else
      warn "Termux:Boot not found -> pkg install termux-boot && open Termux:Boot app"
    fi
  else
    warn "${PLATFORM}: no autostart impl, run ~/.sm-startup manually"
  fi
}

TSTART=$SECONDS
ok "System Monitor installer v${VERSION} ready"
