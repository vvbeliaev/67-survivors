#!/usr/bin/env bash
# Pull origin/main; if HEAD moved, rebuild the docker stack.
# Triggered every 5 min by 67-survivors-update.timer; safe to run by hand.
set -euo pipefail

REPO=/srv/67-survivors
COMPOSE_DIR="$REPO/deploy"

cd "$REPO"
old=$(git rev-parse HEAD)
git fetch --quiet origin main
new=$(git rev-parse origin/main)

if [ "$old" = "$new" ]; then
    exit 0
fi

echo "[$(date -Is)] update: ${old:0:7} → ${new:0:7}"
git reset --hard origin/main

cd "$COMPOSE_DIR"
docker compose up -d --build
echo "[$(date -Is)] rebuild done"
