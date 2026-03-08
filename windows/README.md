# Windows Native GPU Setup (RX 9070XT / RDNA 4)

This document covers getting GPU-accelerated LLM inference running natively on
Windows 11 when ROCm is unavailable in WSL2.

Two strategies are documented. Both expose the same OpenAI-compatible HTTP API
that the VS Code extensions (Continue, Tabby) already target.

---

## Quick Start (Automated)

### First Time Setup

1. **Create configuration** (one-time step):

```powershell
.\setup-config.ps1
```

This interactive wizard will:
- Detect any existing C:\AI installation and offer to migrate
- Let you choose installation directory (default: `%LOCALAPPDATA%\LocalAI`, no admin needed)
- Configure GPU layers, context sizes, and ports
- Create your personalized `config.ps1` file

**Alternatively**, copy and edit manually:
```powershell
cp config.ps1.example config.ps1
notepad config.ps1  # Customize paths and settings
```

2. **Run the automated setup:**

```powershell
.\setup-windows.ps1
```

This script handles all steps below automatically using your configuration.
It's **safe to run multiple times** and will skip completed steps.

For manual control or troubleshooting, continue reading below.

### Available Scripts

| Script | Purpose | Requires Admin |
|--------|---------|----------------|
| `setup-config.ps1` | Interactive configuration wizard (run first) | No |
| `setup-windows.ps1` | Complete automated setup (uses config) | No |
| `download-llama-cpp.ps1` | Download llama.cpp Vulkan build | No |
| `download-models.ps1` | Download GGUF models | No |
| `start-backend-windows.ps1` | Start single model server | No |
| `start-dual-backend.ps1` | Start both Mistral + CodeLlama | No |
| `stop-backend-windows.ps1` | Stop the server(s) | No |
| `install-autostart.ps1` | Configure auto-start on boot | Yes |
| `install-autostart-dual.ps1` | Configure dual backend auto-start | Yes |
| `uninstall-windows.ps1` | Remove installation | No |

---

## Why WSL2 Won't Work for GPU

AMD has no ROCm-to-Windows driver bridge (unlike NVIDIA's CUDA WSL2 layer).
`/dev/kfd` is never exposed inside WSL2, so the Docker Compose setup always
falls back to CPU-only mode.  The only way to use the RX 9070XT on a Windows
host is to run the backend as a **native Windows process**.

---

## Shared Prerequisites

- Windows 11 (22H2 or later)
- AMD Adrenalin driver **24.x or later** (latest stable recommended)
  — download from [amd.com/en/support](https://www.amd.com/en/support)
- **Configuration file created** (run `.\setup-config.ps1` first)
- The GGUF model files will be downloaded automatically to your configured models directory
  (default: `%LOCALAPPDATA%\LocalAI\models`)

---

## Strategy A — llama.cpp with Vulkan (Recommended)

Uses AMD's standard Vulkan compute layer — **no ROCm install required**.
Works on RDNA 4 (RX 9070XT, gfx1201) with a normal graphics driver.

### 1 — Download llama.cpp

**Option A — Automated (recommended):**

```powershell
.\download-llama-cpp.ps1
# Uses your config.ps1 settings to download and extract to the configured directory
```

**Option B — Manual:**

1. Go to [github.com/ggerganov/llama.cpp/releases](https://github.com/ggerganov/llama.cpp/releases)
2. Download the latest `llama-b<VERSION>-bin-win-vulkan-x64.zip`
   (look for the asset named `vulkan-x64`, **not** `cuda` or `rocm`)
3. Extract to your configured `LlamaCppDir` (see `config.ps1`)

### 1b — Download models

Run the download script to fetch the required GGUF models:

```powershell
.\download-models.ps1
# Downloads models to your configured ModelsDir based on config.ps1 settings
```

### 2 — Verify Vulkan is working (optional)

> **Note**: `vulkaninfo` is **not** part of llama.cpp — it comes from the Vulkan SDK
> or AMD drivers. If you have it, great; if not, skip this step. You can verify
> GPU usage later via Task Manager when running inference.

```powershell
# If you have vulkaninfo installed (may be versioned, e.g. vulkaninfo-1-999-0-0-0.exe):
vulkaninfo.exe | Select-String -Pattern "deviceName|AMD|Radeon"
# Should show: deviceName = AMD Radeon RX 9070 XT

# Or if no vulkaninfo, confirm llama.cpp has the Vulkan backend:
# (Replace with your actual LlamaCppDir from config.ps1)
cd $env:LOCALAPPDATA\LocalAI\llama.cpp
Get-ChildItem ggml-vulkan.dll
# Should show: ggml-vulkan.dll (large file, ~50+ MB)
```

### 3 — Start the API server

```powershell
# Single model (uses config.ps1 settings):
.\start-backend-windows.ps1

# Or dual backend (recommended - Mistral for chat, CodeLlama for completion):
.\start-dual-backend.ps1

# Override config settings with parameters:
.\start-backend-windows.ps1 -Model mistral -GpuLayers 99 -CtxSize 16384
```

Key configuration options (set in `config.ps1`):

| Setting | Default | Notes |
|---------|---------|-------|
| `GpuLayers` | `40` | Layers offloaded to GPU; raise to `99` to push all to VRAM |
| `Threads` | Auto-detected | CPU threads to use |
| `ChatContextSize` | `8192` | Context for conversations; can increase to 16384+ |
| `CompletionContextSize` | `2048` | Context for autocomplete (smaller = faster) |
| `ChatPort` | `8080` | HTTP port for chat model |
| `CompletionPort` | `8081` | HTTP port for completion model |

### 4 — Load a second model (optional)

Run a second server instance on port `8081` with the Mistral model:

```powershell
# In a new PowerShell window:
.\start-backend-windows.ps1 -Model mistral -Port 8081
```

Update VS Code Continue config to list both endpoints if needed.

### 5 — Verify

```powershell
# In a separate PowerShell window
Invoke-RestMethod http://127.0.0.1:8080/health
Invoke-RestMethod http://127.0.0.1:8080/v1/models

# Test completion
$body = @{
    model    = "codellama"
    messages = @(@{ role = "user"; content = "Write a Python hello world." })
} | ConvertTo-Json

Invoke-RestMethod -Method Post `
  -Uri "http://127.0.0.1:8080/v1/chat/completions" `
  -ContentType "application/json" `
  -Body $body
```

### IDE Configuration

**📖 Complete configuration guide:** [IDE-CONFIGURATION.md](../IDE-CONFIGURATION.md)

The backend is now running and ready to connect! To use it with your IDE:

- **Continue extension:** Edit `~/.continue/config.yaml` to use `http://localhost:8080/v1`  
  [→ Detailed Continue setup instructions](../IDE-CONFIGURATION.md#vs-code--continue-extension)
  
- **Tabby extension:** Already configured in `.vscode/settings.json` (no changes needed)

- **Other IDEs:** See the [full configuration guide](../IDE-CONFIGURATION.md) for JetBrains, Cursor, Neovim, and more.

---

## Auto-start on Boot (Optional)

By default, the server runs as a foreground process and stops when:
- The PowerShell window is closed
- You log out or reboot

To make it survive reboots, configure it as a Windows scheduled task:

### Install auto-start

**⚠️ Administrator privileges required!** Right-click PowerShell and select "Run as Administrator", then:

```powershell
# Navigate to the windows directory in your clone
.\install-autostart.ps1

# For dual backend:
.\install-autostart-dual.ps1
```

> **Note:** The script has `#Requires -RunAsAdministrator` and will fail if not run with elevated privileges.
> If you see "cannot be loaded because running scripts is disabled", run:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

This creates a scheduled task that:
- Starts `llama-server.exe` automatically on system boot
- Runs as SYSTEM (starts before user login)
- Runs in the background (hidden window)

**⚠️ Important:** After creating the task, you must either:
1. **Reboot** your computer (task will start automatically), OR
2. **Manually start** the task once: `Start-ScheduledTask -TaskName "LocalAI-LlamaServer"`

> **Note:** Task status "Ready" means configured but NOT running. Use commands below to verify.

### Management commands

```powershell
# Start the task now (without rebooting)
Start-ScheduledTask -TaskName "LocalAI-LlamaServer"

# Stop the server
.\stop-backend-windows.ps1
# Or: Stop-ScheduledTask -TaskName "LocalAI-LlamaServer"

# Check task status ⚠️ "Ready" = configured but NOT running, "Running" = active
Get-ScheduledTask -TaskName "LocalAI-LlamaServer" | Format-Table TaskName, State

# View detailed task info (last run time, etc.)
Get-ScheduledTask -TaskName "LocalAI-LlamaServer" | Get-ScheduledTaskInfo

# Disable auto-start (keep task but don't run on boot)
Disable-ScheduledTask -TaskName "LocalAI-LlamaServer"

# Remove auto-start completely
Unregister-ScheduledTask -TaskName "LocalAI-LlamaServer" -Confirm:$false
```

### Check if server is ACTUALLY running

Task status alone doesn't tell you if the server is running. Use these commands:

```powershell
# 1. Check if llama-server.exe process is running
Get-Process llama-server -ErrorAction SilentlyContinue

# 2. Test the API endpoint
Invoke-RestMethod http://127.0.0.1:8080/health
```

**If server is not running and auto-start is not configured:**
```powershell
# Start manually (foreground process)
.\start-backend-windows.ps1
```

---

## Strategy B — Ollama on Windows

Easiest model management. Uses experimental ROCm support on Windows.
RDNA 4 (RX 9070XT) ROCm support on Windows is still maturing as of early 2026;
Strategy A is more broadly compatible today.

### 1 — Install Ollama

1. Download the Windows installer from [ollama.com/download](https://ollama.com/download)
2. Run the installer — Ollama runs as a background Windows service
3. Confirm it started:

```powershell
ollama --version
# Check if GPU is detected
ollama run llama3 ""   # quick smoke test (downloads ~4 GB on first run)
```

### 2 — Pull code models

```powershell
ollama pull codellama          # CodeLlama 7B (default)
ollama pull codellama:13b      # 13B if you want the same size as Strategy A
ollama pull mistral            # Mistral 7B Instruct
```

### 3 — Verify GPU is used

```powershell
# Watch GPU usage while running a query
Start-Process "rocm-smi"   # if ROCm tools installed
# or check AMD Adrenalin overlay / Task Manager > GPU Engine

ollama run codellama "Write a Python hello world."
```

### 4 — Update VS Code extension API base

Ollama uses port **11434** (not 8080). Update `.vscode/settings.json`:

```json
{
  "continue.models": [
    {
      "title": "CodeLlama (Ollama)",
      "provider": "ollama",
      "model": "codellama:13b",
      "apiBase": "http://localhost:11434"
    }
  ],
  "tabby.endpoint": "http://localhost:11434"
}
```

> Alternatively, run Ollama on port 8080 by setting the environment variable
> `OLLAMA_HOST=127.0.0.1:8080` in Windows environment variables before
> starting Ollama — then no settings change is needed.

---

## Comparison

| | Strategy A (llama.cpp Vulkan) | Strategy B (Ollama) |
|---|---|---|
| GPU driver needed | Standard AMD graphics (Vulkan) | Experimental ROCm on Windows |
| RDNA 4 support today | ✅ Yes | ⚠️ Partial |
| API port | 8080 (no config change) | 11434 (update `apiBase`) |
| Model management | Copy GGUF files manually | `ollama pull <model>` |
| Multiple models | Separate server instances | Built-in, switch by name |
| Memory control | Fine-grained (`--n-gpu-layers`) | Automatic |
| Startup | Run `start-backend-windows.ps1` | Background service (auto-start) |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Vulkan: no suitable GPU found` | Update AMD Adrenalin driver; ensure Vulkan SDK runtime is installed |
| Slow inference despite `--n-gpu-layers 40` | Increase to `--n-gpu-layers 99`; monitor VRAM with Task Manager |
| `llama-server.exe` port already in use | Change `--port 8081`; update VS Code `apiBase` — or stop existing server: `.\stop-backend-windows.ps1` |
| Task shows "Ready" but API doesn't respond | "Ready" = not running! Start it: `Start-ScheduledTask -TaskName "LocalAI-LlamaServer"` OR reboot |
| `Get-ScheduledTask` returns "not found" | Auto-start not configured. Start manually: `.\start-backend-windows.ps1` |
| Server stops after reboot | Configure auto-start: `.\install-autostart.ps1` (requires Administrator) |
| Ollama not using GPU | Check `ollama ps` — if offload is 0%, ROCm is not activated; fall back to Strategy A |
| Continue extension not connecting | 1. Check server is running: `Get-Process llama-server` 2. Test API: `Invoke-RestMethod http://localhost:8080/health` 3. Configure Continue: See [IDE-CONFIGURATION.md](../IDE-CONFIGURATION.md#vs-code--continue-extension) |

---

## Uninstalling

To completely remove the Windows installation:

```powershell
.\uninstall-windows.ps1
```

This script will:
- Stop any running llama-server processes
- Remove the scheduled task (if configured)
- Detect and offer to delete installations in both:
  - New location: `%LOCALAPPDATA%\LocalAI\` (default)
  - Legacy location: `C:\AI\` (if found)
- Optionally delete downloaded files (~12+ GB):
  - llama.cpp binaries
  - GGUF model files
  - Log files

The uninstaller is interactive and will ask before deleting files.
Workspace scripts (in your repo) and `config.ps1` are not deleted.

---

## Returning to WSL / Linux

The GGUF model files are portable. To share models between Windows and WSL:

```powershell
# Copy from Windows to WSL (adjust path to match your WSL distro and username)
$wslModelsPath = "\\wsl$\Ubuntu\home\$(whoami)\models"
cp "$env:LOCALAPPDATA\LocalAI\models\*.gguf" $wslModelsPath
```

The Linux scripts will detect and use these models automatically. No other changes needed.
