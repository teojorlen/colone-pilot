#!/bin/bash
# setup.sh — Prepare the local-ai environment
# Installs host dependencies, ROCm drivers (if needed), and downloads recommended models.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load or Create Configuration ──────────────────────────────────────────────────
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file not found. Running setup wizard..."
    echo ""
    
    if [[ -f "$SCRIPT_DIR/setup-config.sh" ]]; then
        bash "$SCRIPT_DIR/setup-config.sh" --non-interactive
        
        if [[ ! -f "$CONFIG_FILE" ]]; then
            echo "Error: Failed to create configuration file." >&2
            echo "Please run: ./setup-config.sh" >&2
            exit 1
        fi
    else
        echo "Error: Configuration files missing." >&2
        echo "Please ensure these files exist:" >&2
        echo "  - config.sh.example" >&2
        echo "  - setup-config.sh" >&2
        echo "" >&2
        echo "Or manually copy: cp config.sh.example config.sh" >&2
        exit 1
    fi
fi

# Load configuration
source "$CONFIG_FILE"

MODELS_DIR="$MODELS_DIR"
CONFIG_DIR="$CONFIG_DIR"

echo "=== local-ai setup ==="

# ── 1. System dependencies ────────────────────────────────────────────────────
echo "[1/5] Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    curl \
    git \
    docker.io \
    docker-compose-plugin \
    rocm-smi \
    rocminfo

# Ensure current user is in the docker and video groups
sudo usermod -aG docker,video "$USER" || true

# ── 2. ROCm driver check ──────────────────────────────────────────────────────
echo "[2/5] Checking ROCm installation..."
if ! command -v rocminfo &>/dev/null; then
    echo "WARNING: rocminfo not found. Install ROCm drivers from:"
    echo "  https://rocm.docs.amd.com/en/latest/Installation_Guide/Installation-Guide.html"
    echo "Continuing without GPU validation."
else
    echo "ROCm detected:"
    rocminfo | grep -E "Name:|Marketing" | head -10
fi

# ── 3. Prepare directories ────────────────────────────────────────────────────
echo "[3/5] Creating model and config directories..."
mkdir -p "$MODELS_DIR" "$CONFIG_DIR"

# ── 4. Download recommended quantized code models ─────────────────────────────
echo "[4/5] Downloading recommended GGUF models..."

# Load checksums from checksums.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKSUMS_FILE="$SCRIPT_DIR/../checksums.txt"

declare -A CHECKSUMS
if [[ -f "$CHECKSUMS_FILE" ]]; then
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        
        # Parse "sha256 filename" format
        if [[ "$line" =~ ^([a-fA-F0-9]{64})[[:space:]]+(.+)$ ]]; then
            hash="${BASH_REMATCH[1]}"
            filename="${BASH_REMATCH[2]}"
            CHECKSUMS["$filename"]="$hash"
        elif [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+VERIFY_AFTER_DOWNLOAD$ ]]; then
            # Placeholder - skip for now
            continue
        fi
    done < "$CHECKSUMS_FILE"
    
    if [[ ${#CHECKSUMS[@]} -gt 0 ]]; then
        echo "  [info] Loaded ${#CHECKSUMS[@]} checksum(s) for verification"
    else
        echo "  [warn] checksums.txt found but no valid checksums loaded"
    fi
else
    echo "  [warn] checksums.txt not found at: $CHECKSUMS_FILE"
    echo "  [warn] Skipping hash verification"
fi

# Helper: verify file checksum
verify_checksum() {
    local filepath="$1"
    local filename="$2"
    
    if [[ -z "${CHECKSUMS[$filename]}" ]]; then
        echo "  [warn] No checksum available for $filename"
        echo "  [info] To enable verification, add to checksums.txt:"
        echo "  sha256sum \"$filepath\""
        return 0
    fi
    
    echo "  [security] Verifying file integrity..."
    actual_hash=$(sha256sum "$filepath" | awk '{print $1}')
    expected_hash="${CHECKSUMS[$filename]}"
    
    if [[ "$actual_hash" != "$expected_hash" ]]; then
        echo "  [ERROR] SHA256 hash mismatch for $filename!"
        echo "  Expected: $expected_hash"
        echo "  Actual:   $actual_hash"
        echo "  File may be corrupted or tampered with."
        return 1
    fi
    
    echo "  [ok] SHA256 hash verified"
    return 0
}

# Helper: download only if not already present
download_model() {
    local url="$1"
    local filename="$2"
    local filepath="$MODELS_DIR/$filename"
    
    if [[ -f "$filepath" ]]; then
        echo "  [skip] $filename already exists."
        # Still verify existing files
        verify_checksum "$filepath" "$filename" || {
            echo "  [ERROR] Integrity check failed for existing file: $filename"
            exit 1
        }
    else
        echo "  Downloading $filename..."
        curl -L --progress-bar -o "$filepath" "$url"
        
        # Verify after download
        verify_checksum "$filepath" "$filename" || {
            echo "  [ERROR] Integrity check failed for downloaded file: $filename"
            rm -f "$filepath"
            exit 1
        }
    fi
}

# CodeLlama 13B Q4 (code completion & chat, good balance of quality/speed)
download_model \
    "$CODELLAMA_URL" \
    "$COMPLETION_MODEL"

# Mistral 7B Instruct Q4 (fast general chat)
download_model \
    "$MISTRAL_URL" \
    "$CHAT_MODEL"

# ── 5. Write LocalAI model config files ──────────────────────────────────────
echo "[5/5] Writing LocalAI model config files..."

cat > "$CONFIG_DIR/codellama.yaml" <<'EOF'
name: codellama
backend: llama
parameters:
  model: codellama-13b.Q4_K_M.gguf
  context_size: 4096
  threads: 24
  f16: true
  mmap: true
  gpu_layers: 40
template:
  completion: |
    {{.Input}}
  chat: |
    ### System:
    You are an expert software engineer. Provide concise, correct code.
    ### User:
    {{.Input}}
    ### Assistant:
EOF

cat > "$CONFIG_DIR/mistral.yaml" <<'EOF'
name: mistral
backend: llama
parameters:
  model: mistral-7b-instruct.Q4_K_M.gguf
  context_size: 8192
  threads: 24
  f16: true
  mmap: true
  gpu_layers: 32
template:
  chat: |
    [INST] {{.Input}} [/INST]
EOF

echo ""
echo "=== Setup complete! ==="
echo "Models are in:  $MODELS_DIR"
echo "Config is in:   $CONFIG_DIR"
echo ""
echo "Start the backend with:  ./start-backend.sh"
echo "NOTE: Log out and back in (or run 'newgrp docker') for group changes to take effect."
