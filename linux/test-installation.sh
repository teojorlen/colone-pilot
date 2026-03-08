#!/usr/bin/env bash
# test-installation.sh — Validate Linux/Docker Installation
# Verifies that the local AI setup is properly configured

set -e

echo "=== LocalAI Installation Test ==="
echo ""

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

# ── Helper Functions ───────────────────────────────────────────────────────────

test_result() {
    local test_name="$1"
    local passed="$2"
    local message="${3:-}"
    local is_warning="${4:-false}"
    
    if [[ "$passed" == "true" ]]; then
        echo "  [✓] $test_name"
        [[ -n "$message" ]] && echo "      $message"
        ((TESTS_PASSED++))
    elif [[ "$is_warning" == "true" ]]; then
        echo "  [!] $test_name"
        [[ -n "$message" ]] && echo "      $message"
        ((TESTS_WARNING++))
    else
        echo "  [✗] $test_name"
        [[ -n "$message" ]] && echo "      $message"
        ((TESTS_FAILED++))
    fi
}

# ── Test 1: Configuration File ────────────────────────────────────────────────
echo "[1/7] Testing configuration..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/config.sh"

if [[ -f "$CONFIG_PATH" ]]; then
    test_result "config.sh exists" true
    
    # shellcheck disable=SC1090
    if source "$CONFIG_PATH" 2>/dev/null; then
        test_result "config.sh loads successfully" true
        
        # Verify required variables
        REQUIRED_VARS=("BASE_DIR" "MODELS_DIR" "CONFIG_DIR" "CHAT_MODEL" "COMPLETION_MODEL")
        MISSING_VARS=()
        
        for var in "${REQUIRED_VARS[@]}"; do
            if [[ -z "${!var}" ]]; then
                MISSING_VARS+=("$var")
            fi
        done
        
        if [[ ${#MISSING_VARS[@]} -eq 0 ]]; then
            test_result "All required configuration variables present" true
        else
            test_result "Required configuration variables" false "Missing: ${MISSING_VARS[*]}"
        fi
    else
        test_result "Load config.sh" false "Error loading configuration"
    fi
else
    test_result "config.sh exists" false "Run ./setup-config.sh to create"
    echo ""
    echo "Cannot continue without configuration. Exiting."
    exit 1
fi

echo ""

# ── Test 2: Directory Structure ───────────────────────────────────────────────
echo "[2/7] Testing directories..."

test_result "Base directory exists" "$([ -d "$BASE_DIR" ] && echo true || echo false)" "Path: $BASE_DIR"
test_result "Models directory exists" "$([ -d "$MODELS_DIR" ] && echo true || echo false)" "Path: $MODELS_DIR"
test_result "Config directory exists" "$([ -d "$CONFIG_DIR" ] && echo true || echo false)" "Path: $CONFIG_DIR"

# Check if directories are writable
if [[ -w "$BASE_DIR" ]]; then
    test_result "Base directory is writable" true
else
    test_result "Base directory writable" false "Permission denied"
fi

echo ""

# ── Test 3: Model Files ────────────────────────────────────────────────────────
echo "[3/7] Testing model files..."

CHAT_MODEL_PATH="$MODELS_DIR/$CHAT_MODEL"
COMPLETION_MODEL_PATH="$MODELS_DIR/$COMPLETION_MODEL"

if [[ -f "$CHAT_MODEL_PATH" ]]; then
    CHAT_MODEL_SIZE=$(du -h "$CHAT_MODEL_PATH" | cut -f1)
    test_result "Chat model exists: $CHAT_MODEL" true "Size: $CHAT_MODEL_SIZE"
else
    test_result "Chat model exists: $CHAT_MODEL" false "Run ./setup.sh"
fi

if [[ -f "$COMPLETION_MODEL_PATH" ]]; then
    COMPLETION_MODEL_SIZE=$(du -h "$COMPLETION_MODEL_PATH" | cut -f1)
    test_result "Completion model exists: $COMPLETION_MODEL" true "Size: $COMPLETION_MODEL_SIZE"
else
    test_result "Completion model exists: $COMPLETION_MODEL" false "Run ./setup.sh"
fi

echo ""

# ── Test 4: Docker ─────────────────────────────────────────────────────────────
echo "[4/7] Testing Docker..."

if command -v docker &> /dev/null; then
    test_result "Docker is installed" true
    
    if docker info &> /dev/null; then
        test_result "Docker daemon is running" true
        
        # Check if user can run docker without sudo
        if docker ps &> /dev/null; then
            test_result "Docker permissions OK" true
        else
            test_result "Docker permissions" false "Run: sudo usermod -aG docker \$USER" true
        fi
    else
        test_result "Docker daemon running" false "Start with: sudo systemctl start docker"
    fi
else
    test_result "Docker installed" false "Install Docker first"
fi

# Check docker-compose
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version 2>&1 | grep -oP 'version \K[^ ]+' || echo "unknown")
    test_result "docker-compose is installed" true "Version: $COMPOSE_VERSION"
else
    test_result "docker-compose installed" false "Install docker-compose"
fi

echo ""

# ── Test 5: Port Availability ─────────────────────────────────────────────────
echo "[5/7] Testing port availability..."

HTTP_PORT="${HTTP_PORT:-8080}"

if command -v netstat &> /dev/null; then
    if netstat -tuln 2>/dev/null | grep -q ":$HTTP_PORT "; then
        test_result "Port $HTTP_PORT available" false "Port already in use"
    else
        test_result "Port $HTTP_PORT available" true
    fi
elif command -v ss &> /dev/null; then
    if ss -tuln 2>/dev/null | grep -q ":$HTTP_PORT "; then
        test_result "Port $HTTP_PORT available" false "Port already in use"
    else
        test_result "Port $HTTP_PORT available" true
    fi
else
    test_result "Port check" false "netstat/ss not available" true
fi

echo ""

# ── Test 6: ROCm (Optional) ────────────────────────────────────────────────────
echo "[6/7] Testing ROCm (optional)..."

if command -v rocminfo &> /dev/null; then
    test_result "rocminfo is installed" true
    
    if rocminfo &> /dev/null; then
        GPU_NAME=$(rocminfo 2>/dev/null | grep -m1 "Marketing Name" | awk -F: '{print $2}' | xargs)
        if [[ -n "$GPU_NAME" ]]; then
            test_result "ROCm GPU detected" true "GPU: $GPU_NAME"
        else
            test_result "ROCm GPU detected" false "No GPU found" true
        fi
    else
        test_result "ROCm functional" false "rocminfo failed" true
    fi
else
    test_result "ROCm installed" false "CPU-only mode will be used" true
fi

echo ""

# ── Test 7: Disk Space ─────────────────────────────────────────────────────────
echo "[7/7] Testing disk space..."

if command -v df &> /dev/null; then
    DISK_INFO=$(df -h "$BASE_DIR" | tail -1)
    TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    USED=$(echo "$DISK_INFO" | awk '{print $3}')
    AVAILABLE=$(echo "$DISK_INFO" | awk '{print $4}')
    USE_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}')
    
    echo "  Total: $TOTAL"
    echo "  Used:  $USED ($USE_PERCENT)"
    echo "  Free:  $AVAILABLE"
    
    # Extract numeric value (remove G/M suffix)
    AVAILABLE_NUMERIC=$(echo "$AVAILABLE" | grep -oP '^\d+')
    
    if [[ "$AVAILABLE" == *"G" ]] && [[ $AVAILABLE_NUMERIC -ge 10 ]]; then
        test_result "Sufficient disk space" true "Need at least 10 GB free"
    else
        test_result "Sufficient disk space" false "Need at least 10 GB free"
    fi
else
    test_result "Check disk space" false "df command not available" true
fi

echo ""

# ── Test 8: Checksums ──────────────────────────────────────────────────────────
echo "[8/8] Testing checksum verification..."

CHECKSUMS_PATH="$SCRIPT_DIR/../checksums.txt"

if [[ -f "$CHECKSUMS_PATH" ]]; then
    test_result "checksums.txt exists" true
    
    # Count valid checksums
    CHECKSUM_COUNT=$(grep -cE '^[a-fA-F0-9]{64}\s+' "$CHECKSUMS_PATH" 2>/dev/null || echo 0)
    PLACEHOLDER_COUNT=$(grep -c 'VERIFY_AFTER_DOWNLOAD' "$CHECKSUMS_PATH" 2>/dev/null || echo 0)
    
    if [[ $CHECKSUM_COUNT -gt 0 ]]; then
        test_result "Valid checksums found" true "Count: $CHECKSUM_COUNT"
    else
        test_result "Valid checksums" false "Only placeholders found" true
        echo "      Update checksums.txt with actual SHA256 hashes"
    fi
else
    test_result "checksums.txt exists" false "File not found" true
fi

echo ""

# ── Summary ────────────────────────────────────────────────────────────────────
echo "=== Test Summary ==="
echo "  Passed:   $TESTS_PASSED"
echo "  Failed:   $TESTS_FAILED"
echo "  Warnings: $TESTS_WARNING"
echo ""

if [[ $TESTS_FAILED -eq 0 ]] && [[ $TESTS_WARNING -eq 0 ]]; then
    echo "✓ All tests passed! Installation is ready."
    echo ""
    echo "Next steps:"
    echo "  1. Start the backend: ./start-backend.sh"
    echo "  2. Check health:     curl http://localhost:$HTTP_PORT/readyz"
    exit 0
elif [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All critical tests passed (some warnings)"
    echo ""
    echo "Installation is functional but consider addressing warnings above."
    exit 0
else
    echo "✗ Some tests failed. Please fix the issues above."
    echo ""
    echo "Common fixes:"
    echo "  - Missing config:  ./setup-config.sh"
    echo "  - Missing setup:   ./setup.sh"
    echo "  - Docker issues:   sudo systemctl start docker"
    echo "  - Docker perms:    sudo usermod -aG docker \$USER"
    exit 1
fi
