#!/bin/bash
# test-installation.sh
# Validation script for Local AI Linux installation
# Tests configuration loading, path validation, and script functionality

set -e

TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} Local AI Installation Test Suite (Linux)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

test_passed() {
    echo -e "${GREEN}[✓] PASS: $1${NC}"
    ((TESTS_PASSED++))
}

test_failed() {
    echo -e "${RED}[✗] FAIL: $1${NC}"
    ((TESTS_FAILED++))
}

test_warning() {
    echo -e "${YELLOW}[⚠] WARN: $1${NC}"
    ((WARNINGS++))
}

# ── Test 1: Configuration File Exists ───────────────────────────────────────

echo -e "${YELLOW}[Test 1] Configuration file validation${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/linux/config.sh"

if [[ -f "$CONFIG_PATH" ]]; then
    test_passed "Configuration file exists: $CONFIG_PATH"
    
    # Test: Can load configuration
    if source "$CONFIG_PATH" 2>/dev/null; then
        test_passed "Configuration file loads without errors"
    else
        test_failed "Configuration file has syntax errors"
    fi
    
    # Test: Required variables present
    required_vars=(
        "BASE_DIR" "MODELS_DIR" "CONFIG_DIR" "CHAT_MODEL" "COMPLETION_MODEL"
        "HTTP_PORT" "GRPC_PORT" "CHAT_CONTEXT_SIZE" "COMPLETION_CONTEXT_SIZE"
        "DOCKER_IMAGE" "DOCKER_TAG"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var}" ]]; then
            test_passed "Config contains required variable: $var"
        else
            test_failed "Config missing required variable: $var"
        fi
    done
else
    test_failed "Configuration file not found: $CONFIG_PATH"
    test_warning "Run ./linux/setup-config.sh to create configuration"
fi

echo ""

# ── Test 2: Path Validation ─────────────────────────────────────────────────

echo -e "${YELLOW}[Test 2] Path validation and security${NC}"

if [[ -n "$BASE_DIR" ]]; then
    # Test: Paths are absolute
    paths=(
        "BASE_DIR:$BASE_DIR"
        "MODELS_DIR:$MODELS_DIR"
        "CONFIG_DIR:$CONFIG_DIR"
    )
    
    for path_pair in "${paths[@]}"; do
        name="${path_pair%%:*}"
        path="${path_pair#*:}"
        
        if [[ "$path" = /* ]]; then
            test_passed "$name is an absolute path: $path"
        else
            test_failed "$name is not an absolute path: $path"
        fi
    done
    
    # Test: No hardcoded personal paths
    personal_paths=("/home/teo" "tjorl" "teo")
    found_personal=false
    
    for var in BASE_DIR MODELS_DIR CONFIG_DIR CHAT_MODEL COMPLETION_MODEL MISTRAL_URL CODELLAMA_URL; do
        value="${!var}"
        if [[ -n "$value" ]]; then
            for personal_path in "${personal_paths[@]}"; do
                if [[ "$value" == *"$personal_path"* ]]; then
                    test_failed "Found hardcoded path '$personal_path' in $var"
                    found_personal=true
                fi
            done
        fi
    done
    
    if [[ "$found_personal" == false ]]; then
        test_passed "No hardcoded personal paths found in configuration"
    fi
fi

echo ""

# ── Test 3: Parameter Validation ────────────────────────────────────────────

echo -e "${YELLOW}[Test 3] Parameter range validation${NC}"

if [[ -n "$HTTP_PORT" ]]; then
    # Test: Port ranges
    ports=(
        "HTTP_PORT:$HTTP_PORT"
        "GRPC_PORT:$GRPC_PORT"
    )
    
    for port_pair in "${ports[@]}"; do
        name="${port_pair%%:*}"
        port="${port_pair#*:}"
        
        if [[ "$port" -ge 1024 && "$port" -le 65535 ]]; then
            test_passed "$name is in valid range: $port"
        else
            test_failed "$name is outside valid range (1024-65535): $port"
        fi
    done
    
    # Test: Context sizes
    contexts=(
        "CHAT_CONTEXT_SIZE:$CHAT_CONTEXT_SIZE"
        "COMPLETION_CONTEXT_SIZE:$COMPLETION_CONTEXT_SIZE"
    )
    
    for context_pair in "${contexts[@]}"; do
        name="${context_pair%%:*}"
        context="${context_pair#*:}"
        
        if [[ "$context" -ge 128 && "$context" -le 131072 ]]; then
            test_passed "$name is in valid range: $context"
        else
            test_failed "$name is outside valid range (128-131072): $context"
        fi
    done
fi

echo ""

# ── Test 4: Script Validation ───────────────────────────────────────────────

echo -e "${YELLOW}[Test 4] Script syntax validation${NC}"

scripts=(
    "linux/setup-config.sh"
    "linux/setup.sh"
    "linux/start-backend.sh"
    "linux/update.sh"
)

for script_path in "${scripts[@]}"; do
    full_path="$SCRIPT_DIR/$script_path"
    
    if [[ -f "$full_path" ]]; then
        # Check if script is executable
        if [[ -x "$full_path" ]]; then
            test_passed "Script is executable: $script_path"
        else
            test_warning "Script is not executable: $script_path (run chmod +x)"
        fi
        
        # Check for bash syntax errors
        if bash -n "$full_path" 2>/dev/null; then
            test_passed "Script has valid syntax: $script_path"
        else
            test_failed "Script has syntax errors: $script_path"
        fi
    else
        test_failed "Script not found: $script_path"
    fi
done

echo ""

# ── Test 5: Docker Configuration ────────────────────────────────────────────

echo -e "${YELLOW}[Test 5] Docker configuration validation${NC}"

docker_files=(
    "linux/docker-compose.yml"
    "linux/docker-compose.gpu.yml"
)

for docker_file in "${docker_files[@]}"; do
    full_path="$SCRIPT_DIR/$docker_file"
    
    if [[ -f "$full_path" ]]; then
        test_passed "Docker compose file exists: $docker_file"
        
        # Check YAML syntax (if docker-compose is available)
        if command -v docker-compose &> /dev/null; then
            cd "$SCRIPT_DIR/linux"
            if docker-compose -f "$(basename "$docker_file")" config > /dev/null 2>&1; then
                test_passed "Docker compose file is valid YAML: $docker_file"
            else
                test_failed "Docker compose file has errors: $docker_file"
            fi
            cd "$SCRIPT_DIR"
        else
            test_warning "docker-compose not installed, skipping YAML validation"
        fi
    else
        test_failed "Docker compose file not found: $docker_file"
    fi
done

# Test: Security settings in docker-compose.yml
if [[ -f "$SCRIPT_DIR/linux/docker-compose.yml" ]]; then
    compose_content=$(cat "$SCRIPT_DIR/linux/docker-compose.yml")
    
    security_checks=(
        "user:Non-root user configuration"
        "security_opt:Security options"
        "cap_drop:Capability dropping"
        "no-new-privileges:no-new-privileges flag"
    )
    
    for check in "${security_checks[@]}"; do
        keyword="${check%%:*}"
        description="${check#*:}"
        
        if echo "$compose_content" | grep -q "$keyword"; then
            test_passed "Docker security: $description found"
        else
            test_warning "Docker security: $description not found"
        fi
    done
fi

echo ""

# ── Test 6: Security Checks ─────────────────────────────────────────────────

echo -e "${YELLOW}[Test 6] Security validation${NC}"

# Test: .gitignore exists
gitignore_path="$SCRIPT_DIR/.gitignore"
if [[ -f "$gitignore_path" ]]; then
    test_passed ".gitignore file exists"
    
    gitignore_content=$(cat "$gitignore_path")
    
    # Check for important exclusions
    required_exclusions=("*.gguf" "config.ps1" "config.sh" ".env" "*.log")
    for exclusion in "${required_exclusions[@]}"; do
        if echo "$gitignore_content" | grep -q "$exclusion"; then
            test_passed ".gitignore excludes: $exclusion"
        else
            test_warning ".gitignore missing exclusion: $exclusion"
        fi
    done
else
    test_failed ".gitignore file not found"
fi

# Test: checksums.json exists
checksums_path="$SCRIPT_DIR/checksums.json"
if [[ -f "$checksums_path" ]]; then
    test_passed "checksums.json file exists"
    
    if python3 -m json.tool "$checksums_path" > /dev/null 2>&1; then
        test_passed "checksums.json is valid JSON"
    else
        test_failed "checksums.json has invalid JSON"
    fi
else
    test_warning "checksums.json not found (optional but recommended)"
fi

echo ""

# ── Test 7: Migration Detection ─────────────────────────────────────────────

echo -e "${YELLOW}[Test 7] Legacy installation detection${NC}"

# Test: Check if legacy paths exist
legacy_paths=("$HOME/models" "$HOME/config")
legacy_found=false

for legacy_path in "${legacy_paths[@]}"; do
    if [[ -d "$legacy_path" ]]; then
        test_warning "Legacy installation found at $legacy_path - migration available"
        echo -e "    ${GRAY}Run ./linux/setup-config.sh to migrate to new location${NC}"
        legacy_found=true
    fi
done

if [[ "$legacy_found" == false ]]; then
    test_passed "No legacy installation detected"
fi

echo ""

# ── Test 8: File Structure ──────────────────────────────────────────────────

echo -e "${YELLOW}[Test 8] Repository structure validation${NC}"

required_dirs=("windows" "linux")
for dir in "${required_dirs[@]}"; do
    dir_path="$SCRIPT_DIR/$dir"
    if [[ -d "$dir_path" ]]; then
        test_passed "Required directory exists: $dir"
    else
        test_failed "Required directory missing: $dir"
    fi
done

required_files=(
    "README.md"
    "SECURITY.md"
    "IDE-CONFIGURATION.md"
    "windows/config.ps1.example"
    "linux/config.sh.example"
    "linux/.env.example"
)

for file in "${required_files[@]}"; do
    file_path="$SCRIPT_DIR/$file"
    if [[ -f "$file_path" ]]; then
        test_passed "Required file exists: $file"
    else
        test_failed "Required file missing: $file"
    fi
done

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} Test Results Summary${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Passed:   $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed:   $TESTS_FAILED${NC}"
echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  ${NC}1. Ensure configuration exists: cd linux && ./setup-config.sh${NC}"
    echo -e "  ${NC}2. Install dependencies:        ./setup.sh${NC}"
    echo -e "  ${NC}3. Start backend:               ./start-backend.sh${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please fix issues above before proceeding.${NC}"
    exit 1
fi
