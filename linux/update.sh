#!/bin/bash
# update.sh — Pull latest LocalAI image, restart, and update models as needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Load Configuration ────────────────────────────────────────────────────────────
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    HTTP_PORT="${HTTP_PORT:-8080}"
else
    HTTP_PORT="8080"
fi

echo "=== Updating local-ai ==="

echo "[1/3] Pulling latest LocalAI image..."
if [[ -e /dev/kfd ]]; then
    docker pull localai/localai:latest-gpu-hipblas
else
    docker pull localai/localai:latest-aio-cpu
fi

echo "[2/3] Restarting backend with updated image..."
if [[ -e /dev/kfd ]]; then
    docker compose -f docker-compose.yml -f docker-compose.gpu.yml down
    docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
else
    docker compose -f docker-compose.yml down
    docker compose -f docker-compose.yml up -d
fi

echo "[3/3] Verifying health..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:$HTTP_PORT/readyz" &>/dev/null; then
        echo "LocalAI restarted and healthy."
        exit 0
    fi
    sleep 2
done

echo "WARNING: Health check timed out. Check logs:"
echo "  docker logs local-ai"
exit 1
