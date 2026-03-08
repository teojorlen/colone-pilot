# IDE & Extension Configuration Guide

Complete guide for connecting your IDE and extensions to the local AI backend.

---

## 💡 Can I Replace GitHub Copilot with This?

**Short answer: Yes!** Your local setup can provide the same functionality as GitHub Copilot without consuming premium requests.

### What You Get Locally

| GitHub Copilot Feature | Local Equivalent | Status |
|----------------------|------------------|---------|
| **Chat/conversational AI** | Continue extension | ✅ **Fully supported** |
| **Code editing & refactoring** | Continue extension | ✅ **Fully supported** |
| **Inline tab completions** | Tabby extension | ✅ **Fully supported** |
| **Codebase understanding** | Continue + embeddings | ✅ **Supported** |
| **Cost** | GitHub: $10-20/month | **FREE (local)** |
| **Privacy** | Sends code to cloud | **100% local** |

### Can I Point GitHub Copilot to My Local Backend?

**No.** GitHub Copilot is a closed, proprietary service that only connects to GitHub/Microsoft servers. There is no official way to redirect it to a custom backend.

### The Solution: Use Open Source Alternatives

Instead of trying to hijack Copilot, use **Continue** (for chat) and **Tabby** (for completions):

- **Continue** → Provides the same chat experience as "GitHub Copilot Chat"
- **Tabby** → Provides the same inline completions as "GitHub Copilot"

Both connect to your local llama.cpp server and provide a nearly identical experience!

**Setup time:** ~5 minutes (see below)

### Complete Copilot Replacement Setup

To fully replace GitHub Copilot with local alternatives:

1. **For Chat + Autocomplete** → [Install Continue](#vs-code--continue-extension) **(Recommended)**
   - Chat sidebar (Ctrl+L)
   - Code explanations
   - Refactoring assistance
   - Tab autocomplete (when enabled)
   - Multi-turn conversations
   - **Works with llama.cpp ✅**
   
2. **Alternative: Tabby for Completions** → ⚠️ **Requires Tabby Server**
   - Tabby extension needs a [Tabby server](https://github.com/TabbyML/tabby), not llama.cpp
   - llama.cpp is OpenAI-compatible, but not Tabby-compatible
   - **Use Continue's autocomplete instead** (works with your setup)

3. **Result:** Same experience as Copilot, zero monthly cost, 100% private!

---

## 🎯 Quick Start

Once your backend is running on `http://localhost:8080`, configure your IDE:

- **VS Code + Continue** → [Jump to instructions](#vs-code--continue-extension)
- **VS Code + Tabby** → [Jump to instructions](#vs-code--tabby-extension)
- **JetBrains IDEs** → [Jump to instructions](#jetbrains-ides)
- **Cursor IDE** → [Jump to instructions](#cursor-ide)
- **Neovim** → [Jump to instructions](#neovim)

---

## Choosing the Right Model

Your setup includes two models with different strengths:

### Mistral 7B Instruct (Recommended for Chat)

- ✅ **Best for:** Conversational AI, Q&A, explanations, general chat
- ✅ **Size:** 4 GB (faster, uses less VRAM)
- ✅ **Quality:** Coherent, helpful responses
- **Start with:** `.\start-backend-windows.ps1 -Model mistral`

### CodeLlama 13B Base

- ✅ **Best for:** Code completion (fill-in-the-middle)
- ❌ **NOT for:** Chat (will output incoherent training data)
- ✅ **Size:** 7.3 GB (larger, more VRAM)
- **Start with:** `.\start-backend-windows.ps1 -Model codellama`

### Which Should I Use?

**Best setup: Use BOTH simultaneously!** 🎯

Run a dual backend setup:
- **Port 8080:** Mistral Instruct (chat, editing, Q&A)
- **Port 8081:** CodeLlama (autocomplete)

**Start both servers:**
```powershell
cd windows
.\start-dual-backend.ps1 -GpuLayers 99
```

This gives you optimal performance for each task:
- Mistral for coherent, helpful conversations
- CodeLlama for accurate code completions

**Common mistake:** Using CodeLlama base for chat results in weird output with `<|im_start|>`, `<|im_end|>` tokens and template-like responses.

### Dual Backend Setup (Recommended)

For optimal performance, run **both models simultaneously** on different ports:

```powershell
# Start both servers
cd windows
.\start-dual-backend.ps1 -GpuLayers 99
```

This creates:
- **Port 8080:** Mistral Instruct → Chat, Q&A, code explanations
- **Port 8081:** CodeLlama → Code completion, autocomplete

**Benefits:**
- ✅ Best model for each task
- ✅ Mistral gives coherent chat responses
- ✅ CodeLlama gives accurate code completions
- ✅ Continue automatically uses the right model for each role

**VRAM Requirements:**
- Mistral: ~4 GB (with 8192 token context)
- CodeLlama: ~7 GB (with 2048 token context for fast completions)
- Total: ~11 GB (easily fits in 16 GB VRAM)

**Context Optimization:**
The dual backend uses different context sizes optimized for each use case:
- **Chat (Mistral):** 8192 tokens — larger context for long conversations
- **Completion (CodeLlama):** 2048 tokens — smaller context for fast autocomplete

This asymmetric allocation maximizes efficiency since completions only need immediate surrounding code, while chat benefits from conversation history.
- **Total: ~11 GB VRAM** (works great on RX 9070XT with 16 GB)

**To stop both servers:**
```powershell
.\stop-backend-windows.ps1
```

---

## Prerequisites

✅ **Backend must be running** before configuring your IDE:

**Test the connection:**

```powershell
# Windows
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/v1/models
```

```bash
# Linux
curl http://localhost:8080/readyz
curl http://localhost:8080/v1/models
```

If these commands fail, start your backend first:
- **Windows:** `.\start-backend-windows.ps1`
- **Linux:** `./start-backend.sh`

---

## VS Code + Continue Extension

**Continue** is an open-source AI coding assistant that works with local models.

### Installation

1. Install the [Continue extension](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
2. Restart VS Code if prompted

### Configuration

#### Option A: GUI Configuration (Recommended)

1. Open Continue sidebar (usually on the left panel, or press `Ctrl+L` / `Cmd+L`)
2. Click the gear icon ⚙️ to open settings
3. Click **"Edit config.yaml"**
4. Replace the contents with:

```yaml
name: Dual Model Config
version: 1.0.0
schema: v1
models:
  - name: Mistral 7B Instruct (Chat)
    provider: openai
    model: mistral
    apiBase: http://localhost:8080/v1
    roles:
      - chat
      - edit
      - apply
    requestOptions:
      temperature: 0.7
      max_tokens: 1000
  - name: CodeLlama 13B (Autocomplete)
    provider: openai
    model: codellama
    apiBase: http://localhost:8081/v1
    roles:
      - autocomplete
    requestOptions:
      temperature: 0.2
      max_tokens: 100
```

> **Recommended:** Use dual backend setup for best results!  
> Start with: `.\start-dual-backend.ps1 -GpuLayers 99`

5. Save and close the file
6. Continue will automatically reload

#### Option B: Manual File Edit

**Windows:**
Edit `C:\Users\<YourUsername>\.continue\config.yaml`

**Linux/macOS:**
Edit `~/.continue/config.yaml`

Use the same YAML configuration as above.

### Enable Tab Autocomplete (Optional)

To get inline code suggestions (like Copilot):

1. Open VS Code settings (`Ctrl+,`)
2. Search for "continue tab"
3. Enable: **Continue: Enable Tab Autocomplete**

Or add to `.vscode/settings.json`:
```json
{
  "continue.enableTabAutocomplete": true
}
```

Once enabled:
- Start typing code
- Continue will show gray inline suggestions
- Press `Tab` to accept

### Verification

**Chat:**
1. Open the Continue sidebar (`Ctrl+L` / `Cmd+L`)
2. Type a question like "Write a Python hello world function"
3. You should see a response from your local model

**Autocomplete:**
1. Open a code file
2. Start typing a function or variable
3. Gray suggestions should appear (press `Tab` to accept)

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "Failed to connect" error | 1. Verify backend is running: `Invoke-RestMethod http://localhost:8080/health` <br> 2. Check port 8080 is not blocked by firewall |
| Slow responses | Increase `GpuLayers` in `start-backend-windows.ps1` to offload more layers to GPU |
| Model not showing up | Ensure `apiBase` includes the `/v1` path suffix |
| Extension not loading config | Restart VS Code after editing `config.yaml` |
| Autocomplete not working | 1. Enable in settings: `continue.enableTabAutocomplete` <br> 2. Ensure `autocomplete` role is in config <br> 3. Restart VS Code |
| Getting weird output with `<|im_start|>` tokens | You're using CodeLlama base (for completion) instead of Mistral Instruct (for chat). Restart server with: `.\start-backend-windows.ps1 -Model mistral` |
| Incoherent or template-like responses | Wrong model for chat. Use Mistral Instruct, not CodeLlama base. |
| "Context size exceeded" / "400 request exceeds available context" | Default context is 8192 tokens. Increase: `.\start-backend-windows.ps1 -CtxSize 16384`. For dual backend, chat context is automatically larger (8192) than completion (2048). |

---

## VS Code + Tabby Extension

⚠️ **Important:** Tabby requires a [Tabby server](https://github.com/TabbyML/tabby), which is different from llama.cpp. Your current llama.cpp setup is **not compatible** with Tabby.

**Recommendation:** Use [Continue's autocomplete feature](#enable-tab-autocomplete-optional) instead, which works with your llama.cpp server.

---

### Why Tabby Doesn't Work with llama.cpp

- **Tabby** expects a Tabby-specific server with custom APIs
- **llama.cpp** provides OpenAI-compatible APIs (different protocol)
- Trying to connect Tabby to llama.cpp will result in "Starting server failed" errors

### Options

**Option 1: Use Continue (Recommended)**
- Continue provides autocomplete using your existing llama.cpp server
- No additional setup required
- [Enable autocomplete in Continue](#enable-tab-autocomplete-optional)

**Option 2: Set Up a Tabby Server (Advanced)**

If you specifically want Tabby, you need to:

1. Download and run a [Tabby server](https://github.com/TabbyML/tabby/releases)
2. Start the Tabby server with your models
3. Configure the Tabby extension to point to the Tabby server (usually `http://localhost:8080`)

**This is more complex and requires running a separate server process.**

---

## JetBrains IDEs

Supports **IntelliJ IDEA**, **PyCharm**, **WebStorm**, **CLion**, etc.

### Option 1: Manual API Testing (Works Now)

Your llama.cpp server provides OpenAI-compatible APIs that JetBrains plugins can use:

1. Use HTTP Client or REST Client plugins
2. Connect to `http://localhost:8080/v1/chat/completions`
3. Send requests manually or via custom scripts

### Option 2: Tabby Plugin (Requires Tabby Server)

⚠️ **Note:** Like VS Code, the JetBrains Tabby plugin requires a [Tabby server](https://github.com/TabbyML/tabby), not llama.cpp.

If you set up a Tabby server:
1. Open **Settings/Preferences** → **Plugins**
2. Search for **"Tabby"**
3. Click **Install**
4. Restart IDE
5. Go to **Settings** → **Tools** → **Tabby**
6. Set **Server URL** to your Tabby server endpoint
7. Click **Apply** and **OK**

### Option 3: GitHub Copilot (with local backend proxy)

⚠️ **Note:** GitHub Copilot doesn't natively support custom endpoints. You would need a proxy tool like [copilot-gpt4-service](https://github.com/aaamoon/copilot-gpt4-service) to redirect requests to your local server.

---

## Cursor IDE

**Cursor** is a fork of VS Code with built-in AI features.

### Configuration

1. Open **Settings** → **Cursor Settings**
2. Navigate to **Models**
3. Under **OpenAI API**, add a custom model:
   - **Base URL:** `http://localhost:8080/v1`
   - **API Key:** Leave empty or use any placeholder (e.g., `local`)
   - **Model:** `codellama`
4. Save settings

Alternatively, if Cursor supports Continue extension:
- Follow the [VS Code + Continue instructions](#vs-code--continue-extension)

---

## Neovim

### Using copilot.lua (requires proxy)

Native GitHub Copilot doesn't support custom endpoints. Use a proxy or alternative solution.

### Using cmp-ai (OpenAI-compatible completion)

1. Install [cmp-ai](https://github.com/tzachar/cmp-ai) plugin
2. Add to your Neovim config:

```lua
local cmp_ai = require('cmp_ai.config')
cmp_ai:setup({
  max_lines = 1000,
  provider = 'OpenAI',
  provider_options = {
    model = 'codellama',
    base_url = 'http://localhost:8080/v1',
    api_key = 'dummy', -- required but not validated
  },
  notify = true,
  run_on_every_keystroke = true,
})
```

### Using llm.nvim

1. Install [llm.nvim](https://github.com/huggingface/llm.nvim)
2. Configure with local endpoint:

```lua
require('llm').setup({
  backend = "openai",
  url = "http://localhost:8080/v1/completions",
  model = "codellama",
  api_token = "dummy", -- not validated by llama.cpp
  tokens_to_clear = { "<|endoftext|>" },
  fim = {
    enabled = true,
    prefix = "<PRE> ",
    middle = " <MID>",
    suffix = " <SUF>",
  },
})
```

---

## Emacs

### Using copilot.el (requires proxy)

Similar to Neovim, GitHub Copilot doesn't support custom endpoints natively.

### Using ellama (OpenAI-compatible)

1. Install [ellama](https://github.com/s-kostyaev/ellama)
2. Add to your Emacs config:

```elisp
(use-package ellama
  :config
  (setopt ellama-provider
          (make-llm-openai
           :url "http://localhost:8080/v1"
           :key "dummy"
           :chat-model "codellama")))
```

---

## API Reference

Your local backend provides **OpenAI-compatible** endpoints:

### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (llama.cpp specific) |
| `/v1/models` | GET | List available models |
| `/v1/completions` | POST | Text completion |
| `/v1/chat/completions` | POST | Chat completion (recommended) |
| `/v1/embeddings` | POST | Text embeddings |

### Example: Chat Completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama",
    "messages": [
      {"role": "user", "content": "Write a Python function to calculate factorial"}
    ],
    "temperature": 0.7,
    "max_tokens": 500
  }'
```

### Example: Code Completion (FIM - Fill In the Middle)

```bash
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama",
    "prompt": "<PRE> def factorial(n):\n    <SUF>\n    return result <MID>",
    "max_tokens": 100,
    "temperature": 0.2,
    "stop": ["<|endoftext|>", "</s>"]
  }'
```

---

## Multi-Model Configuration

If you're running multiple models (e.g., different ports or Ollama + llama.cpp), you can configure Continue to use both:

```yaml
name: Multi-Model Config
version: 1.0.0
schema: v1
models:
  # llama.cpp server on port 8080
  - name: CodeLlama 13B (llama.cpp)
    provider: openai
    model: codellama
    apiBase: http://localhost:8080/v1
    roles:
      - chat
      - edit

  # Ollama on port 11434 (if also running)
  - name: Llama 3.1 8B (Ollama)
    provider: ollama
    model: llama3.1:8b
    roles:
      - apply

  # Smaller model for autocomplete
  - name: Qwen2.5-Coder 1.5B
    provider: ollama
    model: qwen2.5-coder:1.5b-base
    roles:
      - autocomplete
```

**Switch models** in Continue by clicking the model name dropdown in the sidebar.

---

## Performance Tips

### Optimize Inference Speed

1. **Increase GPU layers** in `start-backend-windows.ps1`:
   ```powershell
   .\start-backend-windows.ps1 -GpuLayers 99
   ```

2. **Increase context size** for longer conversations (default now 8192):
   ```powershell
   .\start-backend-windows.ps1 -CtxSize 16384
   ```
   Or reduce for faster responses: `-CtxSize 2048`

3. **Monitor VRAM usage** in Task Manager:
   - Open Task Manager → Performance → GPU
   - Ensure "Dedicated GPU Memory" is being used

### Optimize Response Quality

- **Lower temperature** (0.1-0.3) for more deterministic code
- **Higher temperature** (0.7-1.0) for more creative responses
- **Adjust max tokens** based on use case:
  - Autocomplete: 50-100 tokens
  - Code generation: 500-1000 tokens
  - Explanations: 1000-2000 tokens

---

## Security Considerations

⚠️ **Important:** The local backend runs without authentication by default.

### Network Isolation

- Backend listens on `localhost` (127.0.0.1) only
- Not accessible from other devices on the network
- No data leaves your machine

### Exposing to Network (NOT RECOMMENDED)

If you must expose the API to other devices:

1. **Use a reverse proxy** with authentication (nginx, Caddy)
2. **Enable HTTPS**
3. **Restrict access** by IP whitelist
4. **Monitor connections**

See [SECURITY.md](SECURITY.md) for more details.

---

## Common Issues

### "Connection refused" or "ECONNREFUSED"

**Cause:** Backend is not running or wrong port.

**Fix:**
1. Verify backend is running: `Get-Process llama-server` (Windows) or `ps aux | grep llama` (Linux)
2. Test the endpoint: `Invoke-RestMethod http://localhost:8080/health`
3. Ensure port 8080 is not blocked by firewall

### Responses are very slow

**Cause:** Insufficient GPU offloading.

**Fix:**
1. Increase `-GpuLayers` parameter to 99
2. Check VRAM usage in Task Manager
3. Consider switching to a smaller model (e.g., 7B instead of 13B)

### "Model not found" error

**Cause:** Wrong model name in config.

**Fix:**
1. Check available models: `Invoke-RestMethod http://localhost:8080/v1/models`
2. Use the exact model name returned (usually `codellama` or `mistral`)

### Extension doesn't show any completions

**Cause:** Config not loaded or backend not responding.

**Fix:**
1. Restart VS Code/IDE completely
2. Check Continue logs: View → Output → Select "Continue" from dropdown
3. Verify `apiBase` includes `/v1` path suffix

---

## Advanced: Custom Model Parameters

You can fine-tune model behavior in Continue config:

```yaml
models:
  - name: CodeLlama (Tuned)
    provider: openai
    model: codellama
    apiBase: http://localhost:8080/v1
    roles:
      - chat
    requestOptions:
      temperature: 0.2
      top_p: 0.95
      max_tokens: 1000
      stop: ["<|endoftext|>", "</s>"]
```

---

## Contributing

Found an issue or have a suggestion? Open an issue or PR on the repository!

---

## License

This guide is part of the `local-ai` project. See [README.md](README.md) for license information.
