#!/bin/bash
# start-backend.sh — Start the LocalAI backend via Docker Compose
# Automatically uses GPU (ROCm) if /dev/kfd is present, otherwise falls back to CPU-only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Load Configuration ────────────────────────────────────────────────────────────
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $CONFIG_FILE" >&2
    echo "" >&2
    echo "Please create a configuration file first:" >&2
    echo "  1. Interactive: ./setup-config.sh" >&2
    echo "  2. Manual:      cp config.sh.example config.sh" >&2
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Use HTTP_PORT from config
HTTP_PORT="${HTTP_PORT:-8080}"

if [[ -e /dev/kfd ]]; then
    echo "ROCm device detected — starting with GPU acceleration (AMD RX 9070XT)."
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.gpu.yml"
else
    echo "WARNING: /dev/kfd not found — ROCm kernel module is not loaded."
    echo "Starting in CPU-only mode. To enable GPU:"
    echo "  https://rocm.docs.amd.com/en/latest/Installation_Guide/Installation-Guide.html"
    COMPOSE_FILES="-f docker-compose.yml"
fi

echo "Starting LocalAI backend..."
# shellcheck disable=SC2086
docker compose $COMPOSE_FILES up -d

echo ""
echo "Waiting for API to become healthy..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:$HTTP_PORT/readyz" &>/dev/null; then
        echo "LocalAI is up and healthy."
        echo "  HTTP API:    http://localhost:$HTTP_PORT"
        echo "  gRPC:        localhost:${GRPC_PORT:-5000}"
        echo "  Models list: http://localhost:$HTTP_PORT/v1/models"
        exit 0
    fi
    sleep 5
done

# Container is running but still loading models (normal on first start)
if docker ps --filter name=local-ai --filter status=running -q | grep -q .; then
    echo "Container is running but still initialising (first-run model downloads)."
    echo "Check progress: docker logs -f local-ai"
    echo "Once ready, models will be at: http://localhost:8080/v1/models"
    exit 0
fi

echo "ERROR: container is not running. Check logs:"
echo "  docker logs local-ai"
exit 1
