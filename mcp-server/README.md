# MCP Server — Local AI Management

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server that lets
[Continue](https://continue.dev) (or any MCP client) manage and inspect the local
llama.cpp dual-backend setup directly from the IDE chat.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Setup](#setup)
- [Connecting to Continue](#connecting-to-continue)
- [Available Tools](#available-tools)
- [Using the MCP Server in Agent Mode](#using-the-mcp-server-in-agent-mode)
- [Adding New Tools](#adding-new-tools)
- [Using with Other MCP Clients](#using-with-other-mcp-clients)
- [Testing the Server](#testing-the-server)
- [Dependencies](#dependencies)

---

## Overview

MCP is a protocol by Anthropic that standardises how an AI assistant calls external
tools and reads context. This server exposes tools for:

- Reading the local AI configuration (`config.ps1` / `config.sh`)
- Listing and verifying installed GGUF models
- Checking whether the Mistral and CodeLlama backends are running
- Starting and stopping the dual backend
- Reporting system health (disk, GPU, ports)
- Tailing backend log files

The server communicates over **stdio** — Continue spawns the process and exchanges
JSON-RPC messages on stdin/stdout.

---

## Architecture

```
Continue (VS Code extension)
    │  spawns via stdio
    ▼
mcp-server/server.py          ← FastMCP entry point, registers all tools
    │  imports
    ├── tools/config.py        ← reads config.ps1 / config.sh via subprocess
    ├── tools/models.py        ← scans ModelsDir for .gguf, parses checksums.txt
    ├── tools/backend.py       ← probes /health endpoints, calls PS/bash scripts
    ├── tools/health.py        ← disk, ports, GPU (vulkaninfo / rocminfo)
    └── tools/logs.py          ← tails LogDir/mistral.log, codellama.log
```

**Transport**: stdio — no HTTP server is needed and no port is opened.  
**Runtime**: Python 3.11+ inside a [uv](https://docs.astral.sh/uv/) virtual environment.  
**SDK**: Anthropic [`mcp[cli]`](https://github.com/modelcontextprotocol/python-sdk) with the `FastMCP` helper.

---

## Setup

### 1. Prerequisites

- [uv](https://docs.astral.sh/uv/getting-started/installation/) installed globally
- Python 3.11 or newer (Python 3.12+ recommended; 3.14 works)

### 2. Create the virtual environment and install dependencies

```powershell
cd mcp-server
uv sync
```

This creates `.venv/` and installs all packages from `pyproject.toml`.

### 3. Verify imports

```powershell
.venv\Scripts\python.exe -c "import server; print('OK')"
```

### 4. Smoke-test the server

The MCP inspector opens a browser UI for testing tools interactively:

```powershell
uv run mcp dev server.py
```

Or pipe a raw JSON-RPC message to confirm the server responds:

```powershell
cd mcp-server
cmd /c 'echo {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}} | .venv\Scripts\python.exe -u server.py'
```

A valid response starts with `{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":...`.

---

## Connecting to Continue

### Config file location

`%USERPROFILE%\.continue\config.yaml`

### Minimal configuration

```yaml
name: My Config
version: 1.0.0
schema: v1

mcpServers:
  - name: local-ai
    type: stdio
    command: "C:\\Users\\YOUR_USERNAME\\code\\colone-pilot\\mcp-server\\.venv\\Scripts\\python.exe"
    args:
      - "-u"
      - "C:\\Users\\YOUR_USERNAME\\code\\colone-pilot\\mcp-server\\server.py"
    cwd: "C:\\Users\\YOUR_USERNAME\\code\\colone-pilot\\mcp-server"
    env:
      PYTHONUNBUFFERED: "1"
    connectionTimeout: 30000
```

Replace `YOUR_USERNAME` with your Windows username, or use absolute paths
produced by running `$env:USERPROFILE` in PowerShell.

### Key config fields

| Field | Purpose |
|---|---|
| `type: stdio` | Tells Continue to communicate via stdin/stdout |
| `command` | Full absolute path to the `.venv` Python executable |
| `args[0]: -u` | Disables Python's stdout buffering (required for reliable stdio) |
| `args[1]` | Full absolute path to `server.py` (relative paths resolve from VS Code's install dir, not the repo) |
| `cwd` | Working directory for the process — used by the server for relative file operations at runtime |
| `PYTHONUNBUFFERED: "1"` | Belt-and-suspenders unbuffering via environment variable |
| `connectionTimeout` | Milliseconds to wait for startup; 30 s accommodates Python cold-start |

### Important: agent mode only

MCP tools are only available in Continue's **agent mode**. Switch the mode
selector in the Continue sidebar from _Chat_ to _Agent_ before trying to call
tools. In chat mode the tools are silently unavailable.

---

## Available Tools

| Tool | Description | Key Parameters |
|---|---|---|
| `read_config` | Displays all settings from `config.ps1` / `config.sh` | — |
| `list_models` | Lists all `.gguf` files in the models directory with sizes | — |
| `get_current_models` | Shows which models are currently configured for chat and completion | — |
| `switch_model` | Switch to a different model (updates config, optionally restarts backend) | `server_type: "chat" \| "completion"`, `model_name: str`, `restart: bool` |
| `verify_checksums` | Compares installed models against `checksums.txt` | `compute: bool` — set `true` to calculate SHA256 (~30 s/model) |
| `backend_status` | Probes `/health` on ports 8080 and 8081 | — |
| `start_backend` | Launches `start-dual-backend.ps1` | `confirm: true` required; `force: true` to restart if already running |
| `stop_backend` | Stops all running backend servers | `confirm: true` required |
| `system_health` | Reports disk space, GPU detection, port availability | — |
| `tail_logs` | Shows recent log output from the backend | `lines: int`, `server: "chat" \| "completion" \| "all"` |

The `confirm: true` guard on `start_backend` and `stop_backend` is intentional —
it prevents the AI from starting or stopping services without explicit user intent.

---

## Using the MCP Server in Agent Mode

Once connected, switch Continue to **Agent** mode and ask naturally. Examples:

```
Are the AI backends running?
```
→ calls `backend_status`

```
Start the backend.
```
→ calls `backend_status` first, then `start_backend` with `confirm=true`

```
Show me the last 100 log lines from the chat server.
```
→ calls `tail_logs` with `lines=100, server="chat"`

```
How much disk space is free and is my GPU detected?
```
→ calls `system_health`

```
Verify my model checksums — actually compute the hashes.
```
→ calls `verify_checksums` with `compute=true` (may take ~1 minute)

```
What models are currently configured?
```
→ calls `get_current_models`

```
List all available models I can switch to.
```
→ calls `list_models`

```
Switch the chat server to use deepseek-coder-6.7b.Q4_K_M.gguf
```
→ calls `switch_model` with `server_type="chat"`, `model_name="deepseek-coder-6.7b.Q4_K_M.gguf"`, `restart=false`

```
Switch the completion model to mistral and restart the backend.
```
→ calls `switch_model` with `server_type="completion"`, `model_name="mistral-7b-instruct.Q4_K_M.gguf"`, `restart=true`

---

## Adding New Tools

All tools live in `mcp-server/tools/`. To add a new tool:

### Step 1 — Add the logic to a tool module

Place new functionality in an appropriate existing module (`config.py`, `backend.py`,
etc.) or create a new file, e.g. `tools/updates.py`.

```python
# tools/updates.py
"""updates.py — Check for model/binary updates."""
from __future__ import annotations

def check_for_updates() -> dict:
    """Return a dict describing available updates."""
    # your implementation here
    return {"status": "up-to-date"}
```

### Step 2 — Register the tool in server.py

Import the module and decorate a function with `@mcp.tool()`:

```python
# server.py
from tools import updates as updates_tool

@mcp.tool()
def check_updates() -> str:
    """
    Check whether newer model files or llama-server binaries are available.
    Returns a summary of what can be updated.
    """
    try:
        result = updates_tool.check_for_updates()
        return f"## Update Status\n\n- {result['status']}"
    except Exception as exc:
        return f"**Error checking updates:** {exc}"
```

### Rules for tool functions

- The **function name** becomes the tool name the AI sees — choose it like an action verb (`check_updates`, `read_config`).
- The **docstring** is the tool description. Write it in plain English; the AI uses it to decide when to call the tool.
- **Parameters** must be simple types (`str`, `int`, `float`, `bool`) with default values so the AI can call them with partial arguments.
- **Return a string** — Continue renders the result as Markdown. Use headings, bullet points, code blocks, and status icons.
- Use `async def` when the function needs to do I/O (e.g. HTTP calls); use plain `def` otherwise.
- Always wrap implementation in `try/except` and return a descriptive error string — never let uncaught exceptions crash the server.

### Step 3 — No restart needed during development

Run the MCP inspector to test immediately:

```powershell
uv run mcp dev server.py
```

For production use (connected to Continue), reload the Continue extension after
saving changes:  
**Ctrl+Shift+P → "Developer: Reload Window"** or click the reload icon in the
Continue MCP server panel.

---

## Using with Other MCP Clients

Because this server speaks standard MCP over stdio, it works with any compliant
MCP client, not just Continue.

### Claude Desktop

Add to `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "local-ai": {
      "command": "C:\\Users\\YOUR_USERNAME\\code\\colone-pilot\\mcp-server\\.venv\\Scripts\\python.exe",
      "args": [
        "-u",
        "C:\\Users\\YOUR_USERNAME\\code\\colone-pilot\\mcp-server\\server.py"
      ],
      "env": {
        "PYTHONUNBUFFERED": "1"
      }
    }
  }
}
```

### MCP Inspector (browser UI for development)

```powershell
cd mcp-server
uv run mcp dev server.py
```

Opens `http://localhost:5173` with a GUI to call each tool manually and inspect
responses. Ideal for testing new tools before connecting them to a client.

### Any other MCP-compatible client

Any client that supports stdio transport can use this server. The process to spawn is:

```
<python-executable> -u <absolute-path-to-server.py>
```

with `PYTHONUNBUFFERED=1` in the environment.

---

## Testing the Server

### Manual JSON-RPC test (Windows)

```powershell
cd mcp-server
cmd /c 'echo {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}} | .venv\Scripts\python.exe -u server.py'
```

### Run automated tests

```powershell
cd mcp-server
uv run pytest
```

Tests live in `mcp-server/tests/` (to be added alongside new tools).

---

## Dependencies

| Package | Purpose |
|---|---|
| `mcp[cli]` | MCP SDK + FastMCP server framework + CLI inspector |
| `httpx` | Async HTTP client for probing `/health` endpoints |
| `psutil` | Process and system information (used by health checks) |
| `langchain-community` | Available for future RAG / retrieval tools |

Managed by [uv](https://docs.astral.sh/uv/). To add a new dependency:

```powershell
cd mcp-server
uv add <package-name>
```

This updates `pyproject.toml` and `uv.lock` automatically.
