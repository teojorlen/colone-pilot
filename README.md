# colone-pilot

A self-hosted, fully open-source AI copilot backend optimized for **AMD RX 9070XT** and **AMD 9900x3d**. Provides OpenAI-compatible API endpoints that any IDE extension can connect to.

---

## Platform-Specific Setup

Choose your platform:

### 🐧 [Linux / WSL →](linux/)

GPU-accelerated inference using Docker and LocalAI with ROCm support.

**Quick start:**
```bash
cd linux
./setup-config.sh  # Create configuration (first time only)
./setup.sh
./start-backend.sh
```

**Best for:**
- Linux native installations
- WSL2 **CPU-only** mode (GPU passthrough not supported for AMD)
- Docker-based deployments
- Production environments

[📖 Full Linux documentation →](linux/README.md)

---

### 🪟 [Windows (Native GPU) →](windows/)

GPU-accelerated inference using llama.cpp with Vulkan — **no WSL or Docker required**.

**Quick start:**
```powershell
cd windows
.\setup-config.ps1     # Create configuration (first time only)
.\setup-windows.ps1
.\start-dual-backend.ps1  # Starts both Mistral (chat) + CodeLlama (autocomplete)
```

**Best for:**
- Windows 10/11 native
- AMD GPU acceleration (RX 9070XT, RDNA 4)
- Simpler setup without Docker
- Desktop/development environments

[📖 Full Windows documentation →](windows/README.md)

---

## ⚠️ Security Notice

**Please read [SECURITY.md](SECURITY.md) before deploying, especially if:**

- Publishing to a public repository
- Exposing the API to a network
- Running with elevated privileges
- Using in sensitive environments

**Key considerations:**
- 🔒 API runs on localhost **without authentication by default**
- 🛡️ Windows auto-start requires **Administrator privileges** and runs as **SYSTEM**
- � All inference is **100% local** — no data leaves your machine
- ✅ **No hardcoded paths** — all configurations are user-customizable

[📖 Full security documentation →](SECURITY.md)

---

## Project Structure

```
local-ai/
├── linux/                    # Linux/WSL setup (Docker + LocalAI + ROCm)
│   ├── docker-compose.yml    # Container definition
│   ├── setup.sh             # First-time setup
│   ├── start-backend.sh     # Start backend
│   ├── update.sh            # Update to latest image
│   └── README.md            # Linux documentation
│
├── windows/                  # Windows setup (llama.cpp + Vulkan)
│   ├── setup-windows.ps1    # Complete automated setup
│   ├── download-llama-cpp.ps1
│   ├── download-models.ps1
│   ├── start-backend-windows.ps1
│   ├── stop-backend-windows.ps1
│   ├── install-autostart.ps1
│   ├── uninstall-windows.ps1
│   └── README.md            # Windows documentation
│
├── .vscode/                  # VS Code settings (IDE integration)
├── IDE-CONFIGURATION.md      # Complete IDE/extension setup guide
├── GITHUB-INTEGRATION.md     # GitHub issue integration guide
├── SECURITY.md               # Security considerations
├── PLAN.md                   # Architecture and decision log
├── CONTEXT.md                # Additional context
└── README.md                 # This file
```

---

## Features

- **🚀 Fast inference** — GPU-accelerated on both platforms
- **🔌 OpenAI-compatible API** — Works with any IDE extension (Continue, Tabby, etc.)
- **🎯 Code-optimized models** — CodeLlama 13B & Mistral 7B pre-configured
- **🔒 100% Local** — No cloud services, no telemetry, no subscriptions
- **🛠️ Easy setup** — Automated scripts for both platforms
- **🐙 GitHub integration** — Fetch and analyze GitHub issues with `@github-issue` ([guide](GITHUB-INTEGRATION.md))

---

## Hardware Used

This project is optimized for:

| Component | Specification |
|-----------|--------------|
| **CPU** | AMD Ryzen 9 9900X3D (12c/24t) |
| **GPU** | AMD Radeon RX 9070XT (RDNA 4) |
| **RAM** | 16+ GB |
| **Storage** | 20+ GB free (SSD recommended) |

Works with other AMD GPUs and CPUs — adjust thread/layer counts in config.

---

## Model Storage

Models are stored **outside** the repository in user-configurable locations:

| Platform | Default Location | Customizable |
|----------|------------------|-------------|
| **Linux/WSL** | `~/.local/share/localai/models` | ✅ via `config.sh` |
| **Windows** | `%LOCALAPPDATA%\LocalAI\models` | ✅ via `config.ps1` |

Both platforms use the same GGUF model files (portable between systems).

**First-time setup:** Both platforms now use configuration files to avoid hardcoded paths:
- Run `setup-config.ps1` (Windows) or `setup-config.sh` (Linux) to create your configuration
- Or manually copy: `config.ps1.example` → `config.ps1` (or `.sh` for Linux)

---

## IDE Integration

Once the backend is running on either platform, configure your IDE to connect to `http://localhost:8080`.

**📖 Complete configuration guide:** [IDE-CONFIGURATION.md](IDE-CONFIGURATION.md)

### Quick Links

- **[VS Code + Continue](IDE-CONFIGURATION.md#vs-code--continue-extension)** — AI chat, code generation, and inline editing  
- **[VS Code + Tabby](IDE-CONFIGURATION.md#vs-code--tabby-extension)** — AI-powered code completion  
- **[JetBrains IDEs](IDE-CONFIGURATION.md#jetbrains-ides)** — IntelliJ, PyCharm, WebStorm, etc.  
- **[Cursor IDE](IDE-CONFIGURATION.md#cursor-ide)** — VS Code fork with built-in AI  
- **[Neovim](IDE-CONFIGURATION.md#neovim)** — llm.nvim, cmp-ai configurations  

### Continue Extension Quick Setup (VS Code)

1. Install [Continue extension](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
2. Open Continue settings (⚙️ icon in sidebar) → **Edit config.yaml**
3. Add this configuration:

```yaml
models:
  - name: Mistral 7B Instruct (Chat)
    provider: openai
    model: mistral
    apiBase: http://localhost:8080/v1
    roles:
      - chat
      - edit
      - apply
  - name: CodeLlama 13B (Autocomplete)
    provider: openai
    model: codellama
    apiBase: http://localhost:8081/v1
    roles:
      - autocomplete
```

> **Recommended:** Start dual backend for best results:  
> `.\start-dual-backend.ps1 -GpuLayers 99`
> 
> **Optimized context sizes:**  
> - Chat (Mistral): 8192 tokens for long conversations  
> - Completion (CodeLlama): 2048 tokens for fast autocomplete

4. Save and start chatting with your local models!

For detailed instructions, troubleshooting, and other IDEs, see **[IDE-CONFIGURATION.md](IDE-CONFIGURATION.md)**.

---

## Verification

Test the API once the backend is running:

**Linux:**
```bash
curl http://localhost:8080/readyz
curl http://localhost:8080/v1/models
```

**Windows:**
```powershell
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/v1/models
```

---

## Platform Comparison

| Feature | Linux/WSL | Windows Native |
|---------|-----------|----------------|
| **Backend** | Docker + LocalAI | llama.cpp |
| **GPU Support** | ROCm (Linux only) | Vulkan |
| **Setup Complexity** | Moderate | Simple |
| **WSL GPU** | ❌ Not supported | N/A |
| **Auto-updates** | Docker pull | Manual |
| **Multi-model** | Built-in | Multiple processes |
| **Production** | ✅ Recommended | Desktop/dev |

---

## Troubleshooting

### Both Platforms
- **API not responding:** Confirm backend is running and port 8080 is not blocked
- **Slow inference:** Increase GPU layers in config (more VRAM usage)
- **Model not found:** Check model files are in correct directory

### Linux-Specific
- **Permission denied `/dev/kfd`:** Add user to `video` group
- **Container exits:** Check `docker logs local-ai` for ROCm errors

### Windows-Specific
- **Vulkan not found:** Update AMD Adrenalin driver
- **Port already in use:** Stop existing server with `.\stop-backend-windows.ps1`

See platform-specific documentation for full troubleshooting guides.

---

## License

All components are open source:

| Component | License |
|-----------|---------|
| [LocalAI](https://github.com/mudler/LocalAI) | MIT |
| [llama.cpp](https://github.com/ggerganov/llama.cpp) | MIT |
| [CodeLlama](https://github.com/facebookresearch/codellama) | Llama 2 Community License |
| [Mistral 7B](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2) | Apache 2.0 |

No paid services or subscriptions required.

---

## Quick Links

- [Linux/WSL Setup →](linux/README.md)
- [Windows Setup →](windows/README.md)
- [Architecture & Decisions →](PLAN.md)
- [VS Code Settings →](.vscode/settings.json)
