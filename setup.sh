#!/usr/bin/env bash
# ─── System Monitor · 跨平台一键安装 & 启动 v2.2.0 ──────────────────────────
#   bash setup.sh [--port 8080] [--dev] [--docker] [--force]
#   bash setup.sh [--port-probe M N]
#   bash setup.sh --dry-run       # 预设前 6 步，不启动服务
#   bash setup.sh --help
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail
set -o pipefail

# ── 颜色 & 工具函数 ──────────────────────────────────────────────────
R='\033[31m'; G='\033[32m'; Y='\033[33m'; B='\033[34m'
M='\033[35m'; CY='\033[36m'; N='\033[0m'; DIM='\033[2m'

ok()   { echo -e "${G}✅${N}  $*"; }
warn() { echo -e "${Y}⚠️${N}   $*"; }
err()  { echo -e "${R}❌${N}   $*"; }
info() { echo -e "${CY}ℹ️${N}    $*"; }
step() { echo -e "━━━ ${B}$*${N} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# ── 默认值 ──────────────────────────────────────────────────────────
PORT=8080; DEV=false; DOCKER=false; FORCE=false
PORT_MIN=8080; PORT_MAX=9099
DRY_RUN=false

# ── 用法 ───────────────────────────────────────────────────────────
show_help() {
  cat << 'HLP'
⬡ System Monitor · 跨平台一键安装 & 启动

用法: bash setup.sh [选项]

选项:
  --port N         监听端口 (默认 8080)
  --dev            开发模式 (uvicorn --reload 热重载)
  --docker         Docker 部署 (docker-compose up --build)
  --force          强制重建 Docker 镜像 (down -v 后重建)
  --port-probe M N 端口探测范围 (默认自动扫描 8080-9099)
  --dry-run        全链路预演 (验证到 Step 6，不启动服务)
  --help, -h       显示本帮助

环境变量:
  PIP_INDEX_URL              pip 镜像地址 (默认 pypi.org)
  SM_PYTHON                  Python 可执行路径 (默认自动检测)
HLP
  exit 0
}

# ── 参数解析 ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)         PORT="${2:-8080}"; shift 2;;
    --dev)          DEV=true; shift;;
    --docker)       DOCKER=true; shift;;
    --force)        FORCE=true; shift;;
    --port-probe)   PORT_MIN="${2:-8080}"; PORT_MAX="${3:-9099}"; shift 3;;
    --dry-run)      DRY_RUN=true; shift;;
    --help|-h)      show_help;;
    *) err "未知参数: $1"; echo "使用 --help 查看用法"; exit 1;;
  esac
done

echo -e "${M}⬡ System Monitor${N} ${DIM}v2.2.0${N}  ·  跨平台部署"
echo ""

# ═══════════════════════════════════════════════════════════════════
# Step 1 · 平台检测
# ═══════════════════════════════════════════════════════════════════
{
  begin1=$SECONDS
  step "1 / 7  平台探测"

  OS="$(uname -s 2>/dev/null || echo Unknown)"
  KERNEL="$(uname -r 2>/dev/null || echo ?)"

  case "$OS" in
    Darwin)     PLATFORM="macOS";  SWAP_CMD="free -m";;
    Linux)      PLATFORM="Linux";  SWAP_CMD="free -h";;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="Windows-GitBash"; SWAP_CMD=":";;
    *)          PLATFORM="Unknown"; SWAP_CMD=":";;
  esac

  info "系统:  ${CY}$PLATFORM${N}  ${DIM}($KERNEL)${N}"

  # 内存
  MEM_KB="$(grep -E '^MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)"
  MEM_KB="${MEM_KB%%[^0-9]*}"
  if [[ "$MEM_KB" -gt 0 ]]; then
    MEM_GB=$((MEM_KB / 1024 / 1024))
    info "内存:  ${CY}${MEM_GB} GB${N}"
  fi

  # 核心数
  CPU_CORES="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo ?)"
  info "核心:  ${CY}${CPU_CORES} cores${N}"

  # Swap
  SWAP_RAW="$($SWAP_CMD 2>/dev/null || echo unavailable)"
  SWAP_LINE="$(echo "$SWAP_RAW" | grep -i swap | head -1 || echo "$SWAP_RAW" | head -1)"
  info "Swap:  ${DIM}${SWAP_LINE//$'\n'/ }${N}"

  # /etc/fstab 条目数（仅计数）
  if [[ "$OS" == "Linux" ]] && [[ -r /etc/fstab ]]; then
    FENTRIES=$(grep -vcE '^[[:space:]]*([#;]|$)' /etc/fstab 2>/dev/null || true)
    FENTRIES=${FENTRIES:-0}
    [[ "$FENTRIES" =~ ^[0-9]+$ ]] || FENTRIES=0
    [[ $FENTRIES -gt 0 ]] && info "/etc/fstab:  ${CY}${FENTRIES}${N} 条条目"
  fi

  # SELinux
  if command -v getenforce &>/dev/null; then
    SE="$(getenforce 2>/dev/null || echo Unknown)"
    [[ "$SE" == "Enforcing" ]] && warn "SELinux Enforcing — Docker 卷挂载可能受限"
  fi

  ok "平台探测完成 $(($SECONDS - begin1))s"
}

# ═══════════════════════════════════════════════════════════════════
# Step 2 · 前置工具链检查
# ═══════════════════════════════════════════════════════════════════
{
  begin2=$SECONDS
  step "2 / 7  前置检查"

  MISSING_TOOLS=()

  # Python
  if ! command -v python3 &>/dev/null; then
    if ! command -v python &>/dev/null; then
      MISSING_TOOLS+=("python3")
      err "未找到 Python 3.8+"
      echo "   Ubuntu/Debian:  sudo apt install python3 python3-pip"
      echo "   macOS:          brew install python@3"
      echo "   Windows:        https://python.org/downloads"
      echo ""
    fi
  fi

  if [[ ${#MISSING_TOOLS[@]} -eq 0 ]]; then
    PY="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
    PY_RAW="$($PY --version 2>&1)"
    PY_VER="$($PY -c 'import sys; print(".".join(map(str,sys.version_info[:2])))' 2>/dev/null || echo "0.0")"
    PY_MAJ="${PY_VER%%.*}"; PY_MIN="${PY_VER#*.}"; PY_MIN="${PY_MIN%%.*}"
    if [[ "$PY_MAJ" -lt 3 ]] || [[ "$PY_MAJ" -eq 3 && "$PY_MIN" -lt 8 ]]; then
      err "Python $PY_RAW  需要 >= 3.8"
      exit 1
    fi
    ok "Python:  $PY_RAW"
  fi

  # uvicorn
  command -v uvicorn &>/dev/null && info "uvicorn:  $(uvicorn --version 2>&1 | head -1)" \
    || warn "uvicorn 未安装 (pip install 时将自动安装)"

  # notify-send
  if command -v notify-send &>/dev/null; then
    info "notify-send:  $(notify-send --version 2>&1 | head -1 || echo ok)"
  else
    warn "notify-send 未安装 → 桌面通知不可用  安装: sudo apt install libnotify-bin"
  fi

  # git (Docker layer cache)
  command -v git &>/dev/null && info "git:  $(git --version | head -1)" \
    || info "git 未安装 (影响 Docker 层缓存，不影响功能)"

  # Docker (--docker only)
  if [[ "$DOCKER" == "true" ]]; then
    if ! command -v docker &>/dev/null; then
      err "Docker 未安装"
      echo "   安装: https://docs.docker.com/engine/install/"
      exit 1
    fi
    ok "Docker:  $(docker --version 2>/dev/null)"
  fi

  if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    err "关键工具缺失: ${MISSING_TOOLS[*]}"
    exit 1
  fi

  ok "前置检查通过 $(($SECONDS - begin2))s"
}

# ═══════════════════════════════════════════════════════════════════
# Step 3 · 关键文件 & 路径
# ═══════════════════════════════════════════════════════════════════
{
  begin3=$SECONDS
  step "3 / 7  路径 & 关键文件"

  SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  CD_ORIG="$(pwd 2>/dev/null || echo .)"
  cd "$SCRIPT_DIR" 2>/dev/null || true

  # server.py
  if [[ ! -f "server.py" ]]; then
    err "关键文件缺失: server.py"
    echo "   当前目录: $SCRIPT_DIR"
    echo "   请确保 setup.sh 与 server.py 同目录:"
    echo "     git clone <repo> && cd system-monitor"
    exit 1
  fi
  ok "server.py ✓   ($SCRIPT_DIR)"

  # requirements.txt
  REQ_FILE="requirements.txt"
  if [[ ! -f "$REQ_FILE" ]]; then
    warn "$REQ_FILE 不存在，自动生成"
    cat > "$REQ_FILE" << 'REQ'
fastapi>=0.100
uvicorn>=0.20
psutil>=5.9
websockets>=10
REQ
    warn "使用基础配置，建议覆盖为项目指定版本"
  fi
  ok "requirements.txt ✓"

  # frontend 探测
  FRONTEND_DIR=""
  for cand in \
    "$SCRIPT_DIR/frontend" \
    "$PWD/frontend" \
    "$HOME/Downloads/system-monitor/frontend" \
    "$HOME/Download/system-monitor/frontend" \
    "$HOME/Documents/system-monitor/frontend" \
    "$HOME/Desktop/system-monitor/frontend" \
    "/storage/emulated/0/Download/system-monitor/frontend" \
    "/sdcard/Download/system-monitor/frontend" \
    "/storage/emulated/0/Download/system-monitor"
  do
    [[ -d "$cand" ]] && { FRONTEND_DIR="$cand"; break; }
  done
  # Windows WSL glob
  if [[ -z "$FRONTEND_DIR" ]]; then
    for gw in /mnt/c/Users/*/{Downloads,Desktop}/system-monitor/frontend; do
      [[ -d "$gw" ]] && { FRONTEND_DIR="$gw"; break; }
    done
  fi

  if [[ -z "$FRONTEND_DIR" ]]; then
    warn "frontend/ 目录未自动找到"
    echo "   手动拷贝: cp -r frontend /path/to/destination/"
  else
    ok "frontend ✓   ($FRONTEND_DIR)"
  fi

  # server.py FRONTEND_DIR 一致性检查
  BACKEND_DIR="$(grep -E '^FRONTEND_DIR=' server.py 2>/dev/null | tail -1 | sed -E 's/.*="([^"]+)".*/\1/' || echo "")"
  if [[ -n "$BACKEND_DIR" ]] && [[ "$FRONTEND_DIR" != "$BACKEND_DIR" ]]; then
    warn "server.py FRONTEND_DIR ($BACKEND_DIR) 与探测路径 ($FRONTEND_DIR) 不一致"
    echo "   前端可能无法加载，请检查 server.py 中的 FRONTEND_DIR 配置"
  fi

  # 版本提取
  CURRENT_VER=$(grep -m1 -E 'version="[0-9.]+"' server.py 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')
  CURRENT_VER=${CURRENT_VER:-"?"}
  info "后端版本:  ${CY}$CURRENT_VER${N}"

  ok "路径 & 文件检查完成 $(($SECONDS - begin3))s"
}

# ═══════════════════════════════════════════════════════════════════
# Step 4 · 依赖安装 / 升级
# ═══════════════════════════════════════════════════════════════════
{
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Step 4 · 依赖 (dry-run 跳过)"
    cat "$REQ_FILE" | sed 's/^/    /'
    echo ""
  else
    begin4=$SECONDS
    step "4 / 7  依赖安装"
    echo "$REQ_FILE:"
    cat "$REQ_FILE" | sed 's/^/    /'
    echo ""
    echo "正在 resolve & 安装 (需要网络)..."

    PIP_EXTRA=""
    [[ -n "${PIP_INDEX_URL:-}" ]] && PIP_EXTRA="-i $PIP_INDEX_URL"

    $PY -m pip install --quiet --break-system-packages -r "$REQ_FILE" $PIP_EXTRA 2>/tmp/setup_pip1.log || \
    $PY -m pip install        --break-system-packages -r "$REQ_FILE" $PIP_EXTRA 2>/tmp/setup_pip2.log
    RC=$?

    if [[ $RC -ne 0 ]]; then
      err "pip install 失败 (exit $RC)"
      echo "  ── 错误日志 ──"
      for lf in /tmp/setup_pip2.log /tmp/setup_pip1.log; do
        [[ -f "$lf" ]] && { echo " [$lf]"; tail -n 12 "$lf"; echo ""; }
      done
      echo "  镜像加速:  ${CY}$PY -m pip install ... ${PIP_EXTRA:--i https://pypi.tuna.tsinghua.edu.cn/simple}${N}"
      echo "  代理:      export https_proxy=http://host:port"
      echo "  SSL:       export REQUESTS_CA_BUNDLE=/path/to/cert.pem"
      echo "  → 若持续失败，检查网络 / 代理 / 是否在受限内网"
      exit 1
    fi

    echo ""
    info "验证包 import:"
    for pkg in fastapi uvicorn psutil websockets; do
      if $PY -c "import $pkg" 2>/dev/null; then
        V="$($PY -c "import $pkg; print(getattr($pkg,'__version__','?'))" 2>/dev/null || echo ?)"
        ok "${pkg}: ${CY}$V${N}"
      else
        err "${pkg}: 安装后无法 import，请检查环境"
      fi
    done
    ok "依赖安装完成 $(($SECONDS - begin4))s"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# Step 5 · 端口探测 & 旧进程清理
# ═══════════════════════════════════════════════════════════════════
{
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Step 5 · 端口 (dry-run 跳过, 探测范围: ${PORT_MIN}-${PORT_MAX})"
  else
    begin5=$SECONDS
    step "5 / 7  端口探测 & 进程清理"

    probe_port() {
      command -v ss  &>/dev/null && { ss -tlnp 2>/dev/null | grep ":${1} " | wc -l | tr -d ' '; return; }
      command -v netstat &>/dev/null && { netstat -tlnp 2>/dev/null | grep ":${1} " | wc -l | tr -d ' '; return; }
      (echo >/dev/tcp/127.0.0.1/:${1}) &>/dev/null && echo 1 || echo 0
    }

    for ((p=PORT_MIN; p<=PORT_MAX; p++)); do
      if [[ "$(probe_port "$p")" == "0" ]]; then FINAL_PORT="$p"; break; fi
    done

    [[ -z "${FINAL_PORT:-}" ]] && \
      { err "端口 ${PORT_MIN}-${PORT_MAX} 全部被占用"; echo "   自定义: bash setup.sh --port 9000"; exit 1; }

    [[ "$FINAL_PORT" != "$PORT" ]] && warn "端口 $PORT 被占用 → 使用 $FINAL_PORT"
    ok "可用端口: ${CY}$FINAL_PORT${N}"

    # 旧进程 SIGTERM
    PROCS="$(ss -tlnp 2>/dev/null | grep ":${FINAL_PORT} " | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
    if [[ -n "$PROCS" ]]; then
      warn "端口 $FINAL_PORT 已有进程 (PID: $PROCS)，发送 SIGTERM..."
      kill -TERM $PROCS 2>/dev/null || true
      sleep 2
    fi

    ok "端口 & 进程清理完成 $(($SECONDS - begin5))s"
  fi
}

# dry-run 断点 1（跳过 Step 6+7）
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo -e "${Y}⏸  DRY-RUN: Step 1-5 执行完毕，Step 6+7 已跳过。${N}"
  echo "  命令:  bash setup.sh [--port 8080] [--dev] [--docker] [--force]"
  echo ""
  cd "$CD_ORIG" 2>/dev/null || true
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# Step 6 · 权限与安全检查
# ═══════════════════════════════════════════════════════════════════
{
  begin6=$SECONDS
  step "6 / 7  权限 & 安全检查"

  if [[ "$PLATFORM" == "Linux" ]]; then
    [[ ! -r /proc/meminfo ]] && \
      warn "/proc/meminfo 不可读 → psutil 内存采集可能失败"
    [[ ! -r /proc/stat ]] && \
      warn "/proc/stat 不可读 → psutil CPU 采集可能失败"
    [[ -r /proc/1/environ ]] || \
      warn "/proc/1/environ 不可读 → Docker 内 PID 1 跨命名空间采集受限"
  elif [[ "$PLATFORM" == "macOS" ]]; then
    $PY -c "import ctypes" 2>/dev/null || \
      warn "macOS 权限不足 → 终端通知需在"系统设置 → 通知"中允许"
  fi

  # root-owned 配置检测
  if [[ -f "/etc/system-monitor.conf" ]]; then
    OWNER="$(stat -c %U /etc/system-monitor.conf 2>/dev/null || stat -f %Su /etc/system-monitor.conf 2>/dev/null || echo ?)"
    if [[ "$OWNER" == "root" && "$EUID" -ne 0 ]]; then
      warn "/etc/system-monitor.conf 属主 root，普通用户无法写入"
    fi
  fi

  ok "权限检查完成 $(($SECONDS - begin6))s"
}

# dry-run 断点 2（跳过 Step 7）
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo -e "${Y}⏸  DRY-RUN: Step 1-6 执行完毕，Step 7 已跳过。${N}"
  echo ""
  cd "$CD_ORIG" 2>/dev/null || true
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# Step 7 · 启动服务
# ═══════════════════════════════════════════════════════════════════
{
  begin7=$SECONDS
  step "7 / 7  启动服务"

  print_banner() {
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
    echo -e "${G}║${N}  ⬡ System Monitor v${CY}$CURRENT_VER${N}                        ${G}║${N}"
    echo -e "${G}║${N}  平台: ${CY}$PLATFORM${N}  端口: ${CY}$FINAL_PORT${N}  模式: ${CY}$([ "$DEV" = true ] && echo dev || echo prod)${N}     ${G}║${N}"
    echo -e "${G}║${N}  CPU:  ${CY}${CPU_CORES} cores${N}  内存: ${CY}${MEM_GB}GB${N}                        ${G}║${N}"
    echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "   ${CY}http://localhost:${FINAL_PORT}${N}         浏览器看板"
    echo -e "   ${CY}http://localhost:${FINAL_PORT}/docs${N}       交互式 API 文档"
    echo -e "   ${CY}http://localhost:${FINAL_PORT}/api/health${N}   健康检查"
    echo -e "   ${CY}http://localhost:${FINAL_PORT}/api/alerts${N}   告警规则"
    echo ""
  }

  # ── Docker 模式 ──────────────────────────────────────────────
  if [[ "$DOCKER" == "true" ]]; then
    if [[ ! -f "docker-compose.yml" ]]; then
      err "当前目录未找到 docker-compose.yml"
      echo "   请在项目根目录下运行: bash setup.sh --docker"
      exit 1
    fi

    info "Docker 构建路径: $SCRIPT_DIR"
    DC_FLAGS=(up -d --build --remove-orphans)
    [[ "$FORCE" == "true" ]] && {
      info "--force: docker-compose down -v ..."
      docker-compose down -v --remove-orphans 2>/dev/null || true
    }

    info "exec: docker-compose ${DC_FLAGS[*]}"
    echo ""
    if docker-compose "${DC_FLAGS[@]}"; then
      ok "Docker 容器已启动"
      sleep 2
      HC="$(curl -sf "http://localhost:${FINAL_PORT}/api/health" 2>/dev/null || echo fail)"
      info "Health: $HC"
      print_banner
    else
      err "docker-compose 启动失败"
      echo "   docker logs system-monitor  查看容器日志"
      exit 1
    fi
    exit 0
  fi

  # ── 原生模式 ────────────────────────────────────────────────
  print_banner

  UV_ARGS=(--host 0.0.0.0 --port "$FINAL_PORT")

  # 最终 import 校验
  PKG_OK=true
  for pkg in fastapi uvicorn psutil websockets; do
    $PY -c "import $pkg" 2>/dev/null || { PKG_OK=false; break; }
  done
  [[ "$PKG_OK" != "true" ]] && warn "部分包缺 import，尝试补装..." \
    && $PY -m pip install --quiet --break-system-packages -r "$REQ_FILE" 2>/tmp/setup_pip3.log || true

  if [[ "$DEV" == "true" ]]; then
    info "开发模式 → uvicorn --reload"
    exec "$PY" -m uvicorn server:app "${UV_ARGS[@]}" --reload
  else
    info "生产模式 → uvicorn"
    exec "$PY" -m uvicorn server:app "${UV_ARGS[@]}" --workers 1
  fi
}
