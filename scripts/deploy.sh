#!/usr/bin/env bash
# Deploy 67-survivors dedicated server to a remote Linux VPS over SSH.
#
# Usage:
#   bash scripts/deploy.sh <ip> <key> [port] [min-players]
#
# Example:
#   bash scripts/deploy.sh 1.2.3.4 ~/.ssh/id_ed25519_selectel 7777 2
#   make deploy IP=1.2.3.4 KEY=~/.ssh/id_ed25519_selectel

set -euo pipefail

IP="${1:?Usage: deploy.sh <ip> <ssh-key-path> [port] [min-players]}"
KEY="${2:?Usage: deploy.sh <ip> <ssh-key-path> [port] [min-players]}"
GAME_PORT="${3:-7777}"
MIN_PLAYERS="${4:-2}"

REPO_URL="https://github.com/vvbeliaev/67-survivors.git"
GODOT_VER="4.6.2"
REMOTE_DIR="/srv/67-survivors"
LOG_FILE="/var/log/67survivors.log"
PID_FILE="/var/run/67survivors.pid"

KEY="${KEY/#\~/$HOME}"   # expand ~ if passed literally

if [ ! -f "$KEY" ]; then
    echo "ERROR: key not found: $KEY"
    exit 1
fi

SSH_OPT="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=40"
SSH="ssh $SSH_OPT root@$IP"

echo "==> Deploying to $IP (port=$GAME_PORT, min_players=$MIN_PLAYERS)"

# ── remote script ────────────────────────────────────────────────────────────
$SSH bash << REMOTE
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "--- [1/5] packages ---"
apt-get update -qq
apt-get install -y -qq git curl unzip ufw

echo "--- [2/5] Godot ${GODOT_VER} headless ---"
if ! command -v godot &>/dev/null; then
    URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip"
    echo "    downloading (~100 MB)..."
    curl -fL --progress-bar "\$URL" -o /tmp/godot.zip
    unzip -q /tmp/godot.zip -d /tmp/_godot
    mv "/tmp/_godot/Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot
    chmod +x /usr/local/bin/godot
    rm -rf /tmp/godot.zip /tmp/_godot
fi
echo "    \$(godot --version)"

echo "--- [3/5] repo ---"
if [ -d "${REMOTE_DIR}/.git" ]; then
    git -C "${REMOTE_DIR}" pull --ff-only
else
    git clone "${REPO_URL}" "${REMOTE_DIR}"
fi

echo "--- [4/5] godot import ---"
godot --headless --import --path "${REMOTE_DIR}" 2>&1 | tail -3 || true

echo "--- [5/5] firewall + server ---"
ufw allow ${GAME_PORT}/udp comment '67-survivors' 2>/dev/null || true
ufw --force enable 2>/dev/null || true

if [ -f "${PID_FILE}" ] && kill -0 \$(cat "${PID_FILE}") 2>/dev/null; then
    kill \$(cat "${PID_FILE}")
    sleep 1
fi

nohup godot --headless --path "${REMOTE_DIR}" res://src/server/server.tscn \
    -- --port ${GAME_PORT} --min-players ${MIN_PLAYERS} \
    > "${LOG_FILE}" 2>&1 &
echo \$! > "${PID_FILE}"
sleep 2

if kill -0 \$(cat "${PID_FILE}") 2>/dev/null; then
    echo "    server PID=\$(cat ${PID_FILE}) — OK"
else
    echo "ERROR: server crashed. Last log:"
    tail -30 "${LOG_FILE}"
    exit 1
fi
REMOTE

echo ""
echo "==> Ready!"
echo "    Join:  make run  →  Join  →  $IP : $GAME_PORT"
echo "    Logs:  make logs IP=$IP KEY=$KEY"
echo "    Stop:  make stop IP=$IP KEY=$KEY"
