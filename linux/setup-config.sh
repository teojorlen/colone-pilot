#!/bin/bash
# setup-config.sh
# Interactive configuration wizard for Local AI Linux setup
# Creates a customized config.sh based on user preferences and system detection

set -e

# ── Helper Functions ────────────────────────────────────────────────────────

print_title() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo " $1"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

print_step() {
    echo -e "\033[33m▶ $1\033[0m"
}

print_success() {
    echo -e "\033[32m✓ $1\033[0m"
}

print_info() {
    echo -e "\033[90m  $1\033[0m"
}

print_warning() {
    echo -e "\033[33m⚠ $1\033[0m"
}

# Get user choice with default
get_choice() {
    local prompt="$1"
    local default="$2"
    
    echo -n "$prompt [$default]: "
    read -r choice
    
    if [[ -z "$choice" ]]; then
        echo "$default"
    else
        echo "$choice"
    fi
}

# Check for legacy installation
check_legacy() {
    local legacy_models="${HOME}/models"
    local legacy_config="${HOME}/config"
    
    local has_models=0
    local has_config=0
    
    [[ -d "$legacy_models" ]] && [[ -n "$(ls -A "$legacy_models"/*.gguf 2>/dev/null)" ]] && has_models=1
    [[ -d "$legacy_config" ]] && [[ -n "$(ls -A "$legacy_config"/*.yaml 2>/dev/null)" ]] && has_config=1
    
    if [[ $has_models -eq 1 || $has_config -eq 1 ]]; then
        echo "legacy_found"
        return 0
    fi
    
    echo "no_legacy"
    return 1
}

# ── Main Script ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
EXAMPLE_FILE="$SCRIPT_DIR/config.sh.example"

# Parse arguments
NON_INTERACTIVE=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--non-interactive] [--force]"
            exit 1
            ;;
    esac
done

print_title "Local AI Configuration Wizard"

# Check if config already exists
if [[ -f "$CONFIG_FILE" && "$FORCE" != "true" ]]; then
    print_warning "Configuration file already exists: $CONFIG_FILE"
    echo ""
    echo "Options:"
    print_info "1. Keep existing config (exit)"
    print_info "2. Overwrite with new config"
    print_info "3. Edit existing config"
    echo ""
    
    choice=$(get_choice "Choice [1-3]" "1")
    
    case $choice in
        1)
            print_success "Keeping existing config."
            exit 0
            ;;
        2)
            print_step "Will create new config..."
            ;;
        3)
            ${EDITOR:-vi} "$CONFIG_FILE"
            exit 0
            ;;
        *)
            print_success "Keeping existing config."
            exit 0
            ;;
    esac
fi

echo "This wizard will help you create a customized configuration."
echo ""

# ── Step 1: Check for legacy installation ──────────────────────────────────

legacy_status=$(check_legacy)

if [[ "$legacy_status" == "legacy_found" ]]; then
    print_step "Detected existing installation in ${HOME}/models or ${HOME}/config"
    
    if [[ -d "${HOME}/models" ]]; then
        model_count=$(find "${HOME}/models" -name "*.gguf" 2>/dev/null | wc -l)
        print_info "Found $model_count model files in ${HOME}/models"
    fi
    
    if [[ -d "${HOME}/config" ]]; then
        config_count=$(find "${HOME}/config" -name "*.yaml" 2>/dev/null | wc -l)
        print_info "Found $config_count config files in ${HOME}/config"
    fi
    
    echo ""
    
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo "Would you like to migrate from the existing installation?"
        print_info "[Y] Yes - Use ${HOME}/models and ${HOME}/config"
        print_info "[N] No  - Use new location (~/.local/share/localai)"
        echo ""
        
        migrate=$(get_choice "Migrate [Y/n]" "Y")
        use_legacy=$([[ "$migrate" != "n" && "$migrate" != "N" ]] && echo "true" || echo "false")
    else
        use_legacy="true"
    fi
else
    use_legacy="false"
fi

# ── Step 2: Choose base directory ──────────────────────────────────────────

if [[ "$use_legacy" == "true" ]]; then
    base_dir="${HOME}"
    models_dir="${HOME}/models"
    config_dir="${HOME}/config"
else
    print_step "Choose installation location"
    
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo "Where should Local AI be installed?"
        print_info "1. ~/.local/share/localai (Recommended - No sudo needed, per-user)"
        print_info "2. /opt/localai (System-wide - Requires sudo)"
        echo ""
        
        base_choice=$(get_choice "Choice [1-2]" "1")
        
        if [[ "$base_choice" == "2" ]]; then
            base_dir="/opt/localai"
        else
            base_dir="${HOME}/.local/share/localai"
        fi
    else
        base_dir="${HOME}/.local/share/localai"
    fi
    
    models_dir="${base_dir}/models"
    config_dir="${base_dir}/config"
fi

print_success "Installation path: $base_dir"

# ── Step 3: GPU configuration ───────────────────────────────────────────────

print_step "Configure GPU support"

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    echo "Enable GPU acceleration (requires ROCm for AMD)?"
    print_info "[Y] Yes - Enable GPU support (AMD RX 9070XT / RDNA 4)"
    print_info "[N] No  - CPU only"
    echo ""
    
    gpu_choice=$(get_choice "Enable GPU [Y/n]" "Y")
    use_gpu=$([[ "$gpu_choice" != "n" && "$gpu_choice" != "N" ]] && echo "true" || echo "false")
else
    use_gpu="true"
fi

print_success "GPU acceleration: $use_gpu"

# ── Step 4: Context sizes ───────────────────────────────────────────────────

print_step "Configure context sizes"

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    echo "Chat context size (larger = longer conversations but slower)?"
    print_info "Common values: 2048, 4096, 8192, 16384"
    echo ""
    
    chat_context=$(get_choice "Chat context tokens" "8192")
    
    echo ""
    echo "Completion context size (for autocomplete - typically smaller)?"
    print_info "Common values: 1024, 2048, 4096"
    echo ""
    
    completion_context=$(get_choice "Completion context tokens" "2048")
else
    chat_context="8192"
    completion_context="2048"
fi

print_success "Chat context: $chat_context tokens"
print_success "Completion context: $completion_context tokens"

# ── Step 5: Ports ───────────────────────────────────────────────────────────

print_step "Configure ports"

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    http_port=$(get_choice "HTTP port" "8080")
    grpc_port=$(get_choice "gRPC port" "5000")
else
    http_port="8080"
    grpc_port="5000"
fi

print_success "HTTP port: $http_port"
print_success "gRPC port: $grpc_port"

# ── Step 6: Generate config file ────────────────────────────────────────────

print_step "Creating configuration file..."

if [[ ! -f "$EXAMPLE_FILE" ]]; then
    echo "Error: config.sh.example not found at: $EXAMPLE_FILE"
    exit 1
fi

# Read example and customize
config_content=$(cat "$EXAMPLE_FILE")

# Replace values
config_content="${config_content//BASE_DIR=\"\${HOME}\/.local\/share\/localai\"/BASE_DIR=\"$base_dir\"}"
config_content="${config_content//USE_GPU=true/USE_GPU=$use_gpu}"
config_content="${config_content//CHAT_CONTEXT_SIZE=8192/CHAT_CONTEXT_SIZE=$chat_context}"
config_content="${config_content//COMPLETION_CONTEXT_SIZE=2048/COMPLETION_CONTEXT_SIZE=$completion_context}"
config_content="${config_content//HTTP_PORT=8080/HTTP_PORT=$http_port}"
config_content="${config_content//GRPC_PORT=5000/GRPC_PORT=$grpc_port}"

# Add migration note if using legacy paths
if [[ "$use_legacy" == "true" ]]; then
    config_content="# NOTE: Using existing ${HOME}/models and ${HOME}/config (migrated from legacy setup)
    
$config_content"
fi

# Write config file
echo "$config_content" > "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"

print_success "Configuration saved to: $CONFIG_FILE"

# ── Step 7: Summary ─────────────────────────────────────────────────────────

print_title "Configuration Complete!"

echo "Summary:"
print_info "  Base Directory:     $base_dir"
print_info "  Models Directory:   $models_dir"
print_info "  Config Directory:   $config_dir"
print_info "  GPU Acceleration:   $use_gpu"
print_info "  Chat Context:       $chat_context tokens"
print_info "  Completion Context: $completion_context tokens"
print_info "  HTTP Port:          $http_port"
print_info "  gRPC Port:          $grpc_port"
echo ""

echo "Next steps:"
print_info "  1. Review config (optional): ${EDITOR:-vi} $CONFIG_FILE"
print_info "  2. Run setup:                ./setup.sh"
print_info "  3. Start backend:            ./start-backend.sh"
echo ""

if [[ "$use_legacy" == "true" ]]; then
    echo "Migration Notes:"
    print_info "  Your existing models and config will be used."
    print_info "  No files will be moved or deleted."
    echo ""
fi

print_success "Configuration wizard completed successfully!"
