#!/usr/bin/env bash
# System Monitor — Linux 全自动部署脚本 (one-liner)
# curl -fsSL https://raw.githubusercontent.com/2233qazwsx0/system-monitor/master/install/linux-install.sh | bash
set -euo pipefail

# ── 彩色输出 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "${CYAN}[$1/$2]${NC} $3"; }
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
err()  { echo -e "  ${RED}[FAIL]${NC} $1"; exit 1; }

REPO_URL="https://github.com/2233qazwsx0/system-monitor.git"
INSTALL_DIR="${HOME}/.local/share/system-monitor"
BIN_DIR="${HOME}/.local/bin"
TOTAL=4

# ── 1. 依赖检查 ──────────────────────────────────────────────────
step 1 $TOTAL "检查依赖（git / python3 / pip）"
for cmd in git python3 pip3; do
  command -v "$cmd" >/dev/null 2>&1 || err "缺少 $cmd，请先安装"
done
ok "git $(git --version | cut -d' ' -f3)"
ok "python3 $(python3 --version | cut -d' ' -f2)"
ok "pip3 可用"

# ── 2. 拉取源码 ──────────────────────────────────────────────────
step 2 $TOTAL "拉取最新代码到 $INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR" && git pull --rebase >/dev/null 2>&1
  ok "已更新到最新版本"
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
  ok "克隆完成"
fi

# ── 3. 安装依赖 & 环境变量 ───────────────────────────────────────
step 3 $TOTAL "安装 Python 依赖"
python3 -m pip install --user --quiet -r "$INSTALL_DIR/requirements.txt" 2>/dev/null || \
  python3 -m pip install --user -r "$INSTALL_DIR/requirements.txt"
ok "fastapi / uvicorn / websockets / psutil 安装完成"

step 3 $TOTAL "写入环境变量 (~/.profile & ~/.bashrc)"
mkdir -p "$BIN_DIR"

# 创建 system-monitor 命令
cat > "${BIN_DIR}/system-monitor" <<'RUNSCRIPT'
#!/usr/bin/env bash
cd "${HOME}/.local/share/system-monitor"
exec python3 server.py
RUNSCRIPT
chmod +x "${BIN_DIR}/system-monitor"

# 写入 PATH 到 shell rc
{
  echo ''
  echo '# System Monitor — auto generated'
  echo 'export PATH="${HOME}/.local/bin:${PATH}"'
} >> "${HOME}/.profile"
# 同时写入 bashrc（非交互式 bash 也生效）
{
  echo ''
  echo '# System Monitor — auto generated'
  echo 'export PATH="${HOME}/.local/bin:${PATH}"'
} >> "${HOME}/.bashrc"

# 当前 session 立即生效
export PATH="${HOME}/.local/bin:${PATH}"

# ── 4. 完成 ──────────────────────────────────────────────────────
step 4 $TOTAL "部署完成"
ok "源码目录 : $INSTALL_DIR"
ok "便捷命令 : system-monitor（已加入 PATH）"

# systemd user service（按需询问）
echo ""
read -rp "是否创建 systemd user 服务实现开机自启？[y/N] " ans
if [[ "$ans" =~ ^[Yy] ]]; then
  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${HOME}/.config/systemd/user/system-monitor.service" <<SVCEOF
[Unit]
Description=System Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_DIR}/system-monitor
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
SVCEOF
  systemctl --user daemon-reload
  systemctl --user enable --now system-monitor
  ok "systemd user service 已启用（systemctl --user start|stop|status system-monitor）"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  System Monitor 部署成功！"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo "  浏览器访问  : http://localhost:8000"
echo "  手动启动    : system-monitor"
if [[ "$ans" =~ ^[Yy] ]]; then
echo "  自启管理    : systemctl --user start|stop|status system-monitor"
fi
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
