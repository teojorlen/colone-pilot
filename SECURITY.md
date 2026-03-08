# Security Considerations

**⚠️ IMPORTANT: Read this before deploying or publishing this project**

This document outlines security considerations, risks, and recommendations for the local-ai project.

---

## Overview

This project runs LLM inference **locally** with **no cloud services**. However, several security considerations exist, especially when:
- Exposing the API to a network
- Running with elevated privileges
- Downloading external dependencies
- Publishing to a public repository

---

## Critical Issues to Address Before Publishing

### 1. ✅ **Personal Information in Code** (RESOLVED)

**Issue:** Hardcoded personal usernames appeared throughout the codebase.

**Status:** **RESOLVED** - All hardcoded paths replaced with configuration system.

**Previous Locations:**
- `linux/setup.sh`: Lines 6-7 (`/home/teo/models`, `/home/teo/config`) → Now uses `$MODELS_DIR`, `$CONFIG_DIR`
- `linux/docker-compose.yml`: Lines 13-14 (volume mounts) → Now uses environment variables
- `windows/start-backend-windows.ps1`: Line 81 → Now uses `$LocalAIConfig.ModelsDir`
- Multiple documentation files → Updated to use generic placeholders

**Resolution:**
- ✅ Created `config.ps1` and `config.sh` configuration system
- ✅ All 12 scripts (9 Windows + 3 Linux) now load configuration
- ✅ Interactive setup wizards (`setup-config.ps1`, `setup-config.sh`) guide users
- ✅ Default paths use `$env:LOCALAPPDATA\LocalAI` (Windows) and `~/.local/share/localai` (Linux)
- ✅ Documentation updated to reference configurable paths
- ✅ Legacy path migration support included

---

### 2. ✅ **Missing .gitignore File** (RESOLVED)

**Issue:** No `.gitignore` file existed in the repository.

**Status:** **RESOLVED** - `.gitignore` created with comprehensive exclusions.

**Resolution:**
- ✅ Created `.gitignore` file
- ✅ Excludes model files (*.gguf, *.bin)
- ✅ Excludes configuration files (config.ps1, config.sh, .env)
- ✅ Excludes logs and temporary files
- ✅ Ensures no model files accidentally committed

**Content:** See `.gitignore` in repository root.

---

## API Security

### 3. ⚠️ **No Authentication by Default**

**Issue:** The API runs without authentication on `http://localhost:8080`.

**Risk:**
- Any local process can access the API
- If exposed to network/internet, **anyone** can use your compute resources
- Prompt injection attacks possible
- Data exfiltration through LLM queries

**Current Mitigation:**
- ✅ Binds to `127.0.0.1` (localhost only) by default
- ✅ Not exposed to internet without explicit configuration

**If Exposing to Network:**

**DO NOT expose without authentication!** Options:

1. **Reverse Proxy with Authentication (Recommended):**
   ```nginx
   # nginx example
   location /api/ {
       auth_basic "Restricted";
       auth_basic_user_file /etc/nginx/.htpasswd;
       proxy_pass http://127.0.0.1:8080/;
   }
   ```

2. **SSH Tunnel:**
   ```bash
   ssh -L 8080:localhost:8080 user@remote-host
   ```

3. **Tailscale/WireGuard VPN:**
   - Expose only to private VPN network

**Action Required:**
- [ ] Add prominent warning in documentation about network exposure
- [ ] Document authentication options if users need remote access

---

## Windows-Specific Security

### 4. ⚠️ **Scheduled Task with ExecutionPolicy Bypass**

**Issue:** `install-autostart.ps1` creates a scheduled task that bypasses PowerShell execution policy.

**Location:** `windows/install-autostart.ps1:57`
```powershell
-Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$StartScript`""
```

**Risk:**
- Bypasses security policy intended to prevent unsigned script execution
- Could be exploited if `start-backend-windows.ps1` is modified by malware
- Runs with SYSTEM privileges

**Why It's Used:**
- Required because task runs as SYSTEM user without user profile
- Execution policy doesn't apply to SYSTEM context in some configurations

**Mitigation:**
- Script validates `start-backend-windows.ps1` path exists before creating task
- Task only triggers on system startup (not remotely triggerable)
- Requires Administrator privileges to install (user must consent)

**Enhanced Security Option:**
```powershell
# Sign your scripts with a code signing certificate
Set-AuthenticatedCodeSigningPolicy -Policy AllSigned
# Then sign all .ps1 files
Set-AuthenticatedCode -FilePath "start-backend-windows.ps1" -Certificate $cert
```

**Action Required:**
- [ ] Document the ExecutionPolicy Bypass and its implications
- [ ] Recommend file integrity monitoring for `start-backend-windows.ps1`
- [ ] Consider adding SHA256 hash verification of the script before execution

---

### 5. ⚠️ **Runs as SYSTEM User**

**Issue:** Scheduled task runs llama-server.exe as NT AUTHORITY\SYSTEM.

**Location:** `windows/install-autostart.ps1:70-72`

**Risk:**
- SYSTEM has full access to the machine
- If llama-server.exe or llama.cpp has vulnerabilities, entire system is compromised
- Potential privilege escalation vector

**Why It's Used:**
- Starts before user login
- Doesn't depend on user session

**Mitigation:**
- ✅ Only binds to localhost (not exposed externally)
- ✅ Requires Administrator to install (user awareness)
- Consider running as regular user with "Log on as a service" right instead

**Better Alternative:**
```powershell
# Run as specific user account instead of SYSTEM
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType S4U  # Service for User - doesn't require password
```

**Action Required:**
- [ ] Document SYSTEM execution in README
- [ ] Consider switching to user account execution
- [ ] Add note about reviewing llama.cpp security advisories

---

### 6. ⚠️ **Administrator Privileges Required**

**Issue:** `install-autostart.ps1` requires Administrator.

**Location:** `windows/install-autostart.ps1:7`
```powershell
#Requires -RunAsAdministrator
```

**Risk:**
- Users may inadvertently grant elevated privileges
- Scripts running as admin can modify system files
- Social engineering vector ("just run as admin")

**Mitigation:**
- ✅ Clearly documented in README
- ✅ PowerShell enforces requirement (won't run without admin)
- ✅ Setup script warns user before elevating
- ✅ Only required for auto-start feature (not mandatory)

**Action Required:**
- [ ] Add warning in documentation that admin is **optional** (only for auto-start)
- [ ] Document what the script does with admin privileges

---

## External Dependencies

### 7. ⚠️ **Downloads from External Sources**

**Issue:** Scripts automatically download files from internet without checksum verification.

**Locations:**
- `windows/download-llama-cpp.ps1`: Downloads from GitHub releases
- `windows/download-models.ps1`: Downloads from HuggingFace
- `linux/setup.sh`: Downloads models via curl

**Risk:**
- Man-in-the-middle attacks
- Compromised upstream sources
- No integrity verification
- Supply chain attacks

**Current Mitigation:**
- ✅ Uses HTTPS
- ✅ Downloads from official sources (GitHub, HuggingFace)
- ❌ No checksum/signature verification

**Enhanced Security:**
```powershell
# Add SHA256 verification
$expectedHash = "abcd1234..."
$actualHash = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Hash mismatch! File may be corrupted or tampered."
}
```

**Action Required:**
- [ ] Add checksum verification for downloads
- [ ] Document known-good hashes in README or separate file
- [ ] Consider GPG signature verification for releases
- [ ] Add `--location-trusted` warnings for curl downloads

---

## Docker Security (Linux)

### 8. ⚠️ **Docker Device Access**

**Issue:** Docker container gets direct access to GPU devices.

**Location:** `linux/docker-compose.gpu.yml:8-10`
```yaml
devices:
  - /dev/kfd
  - /dev/dri
```

**Risk:**
- Container can access GPU directly (required for functionality)
- Potential for GPU-based side-channel attacks
- Device driver vulnerabilities exposed

**Mitigation:**
- ✅ Does NOT use `--privileged` mode
- ✅ Only grants specific device access (not full system)
- ✅ Documented in code comments
- Container runs as unprivileged user by default

**Action Required:**
- [ ] Document GPU device access requirements
- [ ] Recommend keeping Docker Engine updated
- [ ] Consider SELinux/AppArmor profiles for additional isolation

---

### 9. ⚠️ **Container Runs as Root (Default)**

**Issue:** LocalAI container may run as root by default.

**Risk:**
- If container is compromised, attacker has root inside container
- Potential container escape vulnerabilities

**Mitigation:**
```yaml
services:
  localai:
    user: "1000:1000"  # Run as non-root user
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN  # Only if needed
```

**Action Required:**
- [ ] Add user/group specification to docker-compose.yml
- [ ] Test with non-root user
- [ ] Document in README

---

## Network Security

### 10. ⚠️ **Port Exposure**

**Issue:** Ports 8080 (HTTP) and 5000 (gRPC) exposed on localhost.

**Current State:**
- ✅ Linux: Binds to all interfaces but firewalled by default
- ✅ Windows: Explicitly binds to `127.0.0.1`

**Risk if Exposing Externally:**
- Unencrypted HTTP traffic (no TLS)
- No rate limiting
- Denial of service (expensive LLM inference)
- Prompt injection attacks

**Recommendations for Production:**
```yaml
# Add TLS termination
# Add rate limiting
# Add firewall rules
# Use authentication
```

**Action Required:**
- [ ] Document port security in README
- [ ] Add warning about network exposure
- [ ] Provide TLS/reverse proxy examples

---

## Data Privacy

### 11. ℹ️ **Model Data Stays Local**

**Good News:** 
- ✅ All inference happens locally
- ✅ No data sent to cloud services
- ✅ No telemetry by default
- ✅ Models stored on local disk

**Privacy Considerations:**
- Users should verify downloaded models are unmodified
- Model files may contain training data artifacts
- Logs may contain sensitive prompts/responses

**Action Required:**
- [ ] Add privacy statement to README
- [ ] Document log locations and rotation
- [ ] Recommend encrypting model storage for sensitive use cases

---

### 12. ⚠️ **Logs May Contain Sensitive Data**

**Issue:** Application logs may contain user prompts and model responses.

**Locations:**
- Configured models and config directories (see `config.ps1`/`config.sh`)
- Docker container logs (Linux)
- PowerShell terminal history

**Risk:**
- Prompts may contain sensitive information
- Responses may be proprietary or confidential
- Logs may be accessible to other users/processes

**Mitigation:**
```powershell
# Windows: Restrict log directory permissions
$logDir = "$($LocalAIConfig.BaseDir)\logs"
icacls $logDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F"

# Linux: Restrict docker logs
chmod 700 ~/.local/share/localai/models
```

**Action Required:**
- [ ] Document log locations
- [ ] Recommend log rotation/retention policies
- [ ] Add note about sensitive data in logs
- [ ] Provide log cleanup scripts

---

## Input Validation

### 13. ℹ️ **Limited Input Validation**

**Issue:** Scripts assume valid input from user and external sources.

**Examples:**
- Model file names not validated
- Port numbers not range-checked
- Directory paths not sanitized
- No validation of downloaded file contents (see #7)

**Potential Issues:**
- Path traversal if user provides malicious paths
- Port conflicts if invalid port specified
- Disk space exhaustion from large downloads

**Enhanced Validation Example:**
```powershell
# Validate port range
if ($Port -lt 1024 -or $Port -gt 65535) {
    throw "Port must be between 1024 and 65535"
}

# Validate path doesn't escape intended directory
$baseDir = $LocalAIConfig.ModelsDir
$resolvedPath = Resolve-Path $ModelPath -ErrorAction Stop
if (-not $resolvedPath.Path.StartsWith($baseDir)) {
    throw "Model path must be within $baseDir"
}
```

**Action Required:**
- [ ] Add input validation to all user-supplied parameters
- [ ] Validate file paths don't escape intended directories
- [ ] Check disk space before downloads
- [ ] Validate port numbers and model names

---

## Dependency Security

### 14. ⚠️ **Third-Party Dependencies**

**Dependencies:**
- **llama.cpp** - C++ inference engine (external binary)
- **LocalAI** - Docker image (third-party)
- **Model files** - Neural networks from Meta/Mistral (third-party)

**Risks:**
- Vulnerabilities in llama.cpp or LocalAI
- Backdoored or poisoned models
- Supply chain attacks

**Mitigation:**
- Monitor security advisories:
  - https://github.com/ggerganov/llama.cpp/security/advisories
  - https://github.com/mudler/LocalAI/security/advisories
- Use specific version tags instead of `latest`
- Verify model sources

**Action Required:**
- [ ] Document dependency update process
- [ ] Add links to security advisories
- [ ] Recommend version pinning
- [ ] Consider dependency scanning tools

---

## Recommendations Summary

### Before Publishing to Public Repository:

**Action Required:**
- [✅] Create `.gitignore` file
- [✅] Remove personal usernames (teo, tjorl) - use variables
- [✅] Add security section to README

**High Priority:**
- [ ] Add checksum verification for downloads
- [ ] Document ExecutionPolicy Bypass implications
- [ ] Add input validation to scripts
- [ ] Document SYSTEM user execution risks

**Medium Priority:**
8. Add file integrity checking for scheduled task script
9. Improve Docker security (non-root user, capabilities)
10. Add example reverse proxy configs with auth

**Low Priority (Best Practices):**
11. Consider code signing for PowerShell scripts
12. Add security advisory monitoring guide
13. Provide log rotation/cleanup scripts

---

## Security Reporting

If you discover a security issue in this project:

**DO NOT open a public GitHub issue.**

Instead, please report it privately to the maintainers:
- Email: [Your Contact Email Here]
- Encrypt with PGP if possible

We will respond within 48 hours and work to address the issue.

---

## Disclaimer

This software is provided "as is" without warranty. Users are responsible for:
- Securing their deployments
- Monitoring for vulnerabilities
- Complying with model licenses
- Protecting sensitive data
- Following security best practices

**Use at your own risk.**

---

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [PowerShell Security Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/security/overview)
- [AI Security Best Practices](https://owasp.org/www-project-machine-learning-security-top-10/)

---

**Last Updated:** 2026-03-08  
**Review Frequency:** Quarterly or after major changes
