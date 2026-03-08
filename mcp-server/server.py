"""server.py — Local AI Management MCP Server.

Exposes tools for Continue (and any MCP client) to manage the dual
llama.cpp backend, inspect configuration, verify models, and diagnose issues.

Run directly:
    uv run python server.py

Test interactively (opens MCP Inspector in browser):
    uv run mcp dev server.py
"""
from __future__ import annotations

from mcp.server.fastmcp import FastMCP

from tools import backend as backend_tool
from tools import config as cfg_tool
from tools import health as health_tool
from tools import logs as logs_tool
from tools import models as models_tool

mcp = FastMCP(
    "local-ai",
    instructions=(
        "Tools for managing the local llama.cpp AI backend (dual-model setup).\n"
        "- Use backend_status first to know if servers are running before start/stop.\n"
        "- Use read_config to inspect current settings before suggesting changes.\n"
        "- Use get_current_models to see which models are configured.\n"
        "- Use list_models to see all available .gguf model files.\n"
        "- Use switch_model to hot-swap models (updates config and optionally restarts).\n"
        "- start_backend and stop_backend require confirm=True as a safety guard.\n"
        "- verify_checksums with compute=True is slow (~30s/model): warn the user first.\n"
        "- tail_logs requires EnableLogging=true in config.ps1 to return output."
    ),
)


# ╔══════════════════════════════════════════════════════════╗
# ║  Configuration                                           ║
# ╚══════════════════════════════════════════════════════════╝


@mcp.tool()
def read_config() -> str:
    """
    Read the current LocalAI configuration.
    Returns all settings: paths, ports, model names, context sizes, GPU layers, logging flag.
    """
    try:
        conf = cfg_tool.load()
    except Exception as exc:
        return f"**Error reading config:** {exc}"

    lines = ["## LocalAI Configuration\n"]
    skip = {"Checksums"}  # nested/noisy — omit from display
    for k, v in conf.items():
        if k not in skip:
            lines.append(f"- **{k}**: `{v}`")
    return "\n".join(lines)


# ╔══════════════════════════════════════════════════════════╗
# ║  Models                                                  ║
# ╚══════════════════════════════════════════════════════════╝


@mcp.tool()
def list_models() -> str:
    """
    List all GGUF model files installed in the configured models directory.
    Shows each model's filename and size in GB.
    """
    try:
        models = models_tool.list_models()
    except Exception as exc:
        return f"**Error listing models:** {exc}"

    if not models:
        return "No `.gguf` model files found. Run `download-models.ps1` to download them."

    lines = ["## Installed Models\n"]
    for m in models:
        lines.append(f"- **{m['name']}** — {m['size_gb']} GB  \n  `{m['path']}`")
    return "\n".join(lines)


@mcp.tool()
def verify_checksums(compute: bool = False) -> str:
    """
    Cross-reference installed models against checksums.txt.

    compute: if True, calculate SHA256 hashes for each file.
             This is slow (~30s per 7 GB model). Default is False (shows status only).
    """
    try:
        results = models_tool.verify_checksums(compute=compute)
    except Exception as exc:
        return f"**Error verifying checksums:** {exc}"

    if not results:
        return "No models found to verify."

    icons = {"ok": "✅", "mismatch": "❌", "placeholder": "⚠️", "no_checksum": "❓", "not_computed": "·"}
    lines = ["## Checksum Verification\n"]
    for r in results:
        icon = icons.get(r.get("status", ""), "·")
        msg = r.get("message") or r.get("actual") or ""
        lines.append(f"- {icon} **{r['name']}** — {r.get('status', 'unknown')}: {msg}")

    if not compute:
        lines.append("\n> Pass `compute=True` to actually verify SHA256 hashes.")
    return "\n".join(lines)


@mcp.tool()
def get_current_models() -> str:
    """
    Show which models are currently configured for chat and completion servers.
    This shows what's in the config, not necessarily what's running.
    Use backend_status to see what models are actually loaded.
    """
    try:
        models = models_tool.get_current_models()
    except Exception as exc:
        return f"**Error getting current models:** {exc}"
    
    lines = ["## Currently Configured Models\n"]
    lines.append(f"- **Chat** (port 8080): `{models['chat']}`")
    lines.append(f"- **Completion** (port 8081): `{models['completion']}`")
    lines.append("\n> Use `backend_status` to see if these models are running.")
    lines.append("> Use `switch_model` to change to a different model.")
    return "\n".join(lines)


@mcp.tool()
def switch_model(server_type: str, model_name: str, restart: bool = False) -> str:
    """
    Switch to a different model for the chat or completion server.
    
    server_type: "chat" or "completion" - which server to update
    model_name:  filename of the .gguf model (e.g., "mistral-7b-instruct.Q4_K_M.gguf")
    restart:     if True, automatically restart the backend after switching (requires confirmation)
    
    This updates the config file. You must restart the backend for changes to take effect,
    either by setting restart=True or by calling stop_backend then start_backend.
    
    Use list_models to see available models.
    """
    try:
        result = models_tool.switch_model(server_type, model_name)
        
        if result["status"] != "ok":
            return f"❌ {result['message']}"
        
        message = f"✅ {result['message']}"
        
        # If restart requested, stop and start the backend
        if restart:
            message += "\n\n**Restarting backend...**"
            
            # Stop current backend
            stop_result = backend_tool.stop()
            if stop_result["exit_code"] != 0:
                message += f"\n⚠️  Warning: Stop may have failed:\n```\n{stop_result.get('stderr') or stop_result.get('stdout')}\n```"
            else:
                message += "\n- ✅ Stopped backend"
            
            # Start with new config
            import asyncio
            start_result = backend_tool.start(force=True)
            if start_result["exit_code"] == 0:
                message += "\n- ✅ Backend restarted with new model"
            else:
                err = start_result.get("stderr") or start_result.get("stdout") or "(no output)"
                message += f"\n- ❌ Start failed:\n```\n{err}\n```"
        
        return message
    
    except Exception as exc:
        return f"**Error switching model:** {exc}"


# ╔══════════════════════════════════════════════════════════╗
# ║  Backend Control                                         ║
# ╚══════════════════════════════════════════════════════════╝


@mcp.tool()
async def backend_status() -> str:
    """
    Check if the Mistral (port 8080) and CodeLlama (port 8081) servers are running.
    Probes the /health endpoint of each; identifies servers by port, not process name.
    """
    try:
        result = await backend_tool.status()
    except Exception as exc:
        return f"**Error checking status:** {exc}"

    lines = ["## Backend Status\n"]
    for name, info in result.items():
        running = "🟢 Running" if info.get("reachable") else "🔴 Stopped"
        model = info.get("model") or "unknown"
        port = info.get("port", "?")
        lines.append(f"- **{name.capitalize()}** (`{model}`) — port `{port}`: {running}")
        if not info.get("reachable") and "error" in info:
            lines.append(f"  - _{info['error']}_")
    return "\n".join(lines)


@mcp.tool()
async def start_backend(confirm: bool = False, force: bool = False) -> str:
    """
    Start the dual backend: Mistral on port 8080, CodeLlama on port 8081.

    confirm: must be True to proceed (safety guard).
    force:   if True, automatically stops any running servers before starting.
             Without force, returns an error if either port is already in use.
    """
    if not confirm:
        return (
            "Set `confirm=True` to start the backend.\n"
            "Add `force=True` to automatically stop existing servers first."
        )

    try:
        # Pre-check: warn if ports already occupied
        current = await backend_tool.status()
        already_running = [
            f"{name} (port {info['port']})"
            for name, info in current.items()
            if info.get("reachable")
        ]
        if already_running and not force:
            return (
                f"Servers already running: {', '.join(already_running)}\n"
                "Pass `force=True` to stop and restart them."
            )

        result = backend_tool.start(force=force)
        if result["exit_code"] == 0:
            out = result["stdout"] or "(no output)"
            return f"✅ Backend started successfully.\n\n```\n{out}\n```"
        else:
            err = result["stderr"] or result["stdout"] or "(no output)"
            return f"❌ Start failed (exit {result['exit_code']}):\n```\n{err}\n```"
    except Exception as exc:
        return f"**Error starting backend:** {exc}"


@mcp.tool()
async def stop_backend(confirm: bool = False) -> str:
    """
    Stop all running backend servers.

    confirm: must be True to proceed (safety guard).
    """
    if not confirm:
        return "Set `confirm=True` to stop the backend."

    try:
        result = backend_tool.stop()
        if result["exit_code"] == 0:
            out = result["stdout"] or "(no output)"
            return f"✅ Backend stopped.\n\n```\n{out}\n```"
        else:
            err = result["stderr"] or result["stdout"] or "(no output)"
            return f"❌ Stop failed (exit {result['exit_code']}):\n```\n{err}\n```"
    except Exception as exc:
        return f"**Error stopping backend:** {exc}"


# ╔══════════════════════════════════════════════════════════╗
# ║  System Health                                           ║
# ╚══════════════════════════════════════════════════════════╝


@mcp.tool()
def system_health() -> str:
    """
    Check system health: GPU detection, disk space on the models drive,
    and whether ports 8080/8081 are free or in use.
    """
    try:
        h = health_tool.system_health()
    except Exception as exc:
        return f"**Error checking health:** {exc}"

    lines = ["## System Health\n"]

    disk = h.get("disk", {})
    if "error" in disk:
        lines.append(f"- ❓ **Disk**: {disk['error']}")
    else:
        icon = "✅" if disk.get("ok") else "⚠️"
        lines.append(f"- {icon} **Disk**: {disk.get('free_gb', '?')} GB free / {disk.get('total_gb', '?')} GB total")

    for port, free in h.get("ports", {}).items():
        icon = "✅ free" if free else "🔴 in use"
        lines.append(f"- **Port {port}**: {icon}")

    gpu = h.get("gpu", {})
    if gpu.get("available"):
        info = gpu.get("info") or f"Detected via `{gpu.get('tool')}`"
        lines.append(f"- ✅ **GPU**: {info}")
    else:
        msg = gpu.get("message") or gpu.get("error") or "Not detected"
        lines.append(f"- ❓ **GPU**: {msg}")

    return "\n".join(lines)


# ╔══════════════════════════════════════════════════════════╗
# ║  Logs                                                    ║
# ╚══════════════════════════════════════════════════════════╝


@mcp.tool()
def tail_logs(lines: int = 50, server: str = "all") -> str:
    """
    Show recent log output from the backend servers.

    lines:  number of lines to show per log file (default: 50).
    server: "chat" (Mistral), "completion" (CodeLlama), or "all" (default).

    Note: logging is disabled by default. Set EnableLogging=$true in
    windows/config.ps1 and restart the backend to enable log files.
    """
    try:
        result = logs_tool.tail(lines=lines, server=server)
    except Exception as exc:
        return f"**Error reading logs:** {exc}"

    if result["status"] != "ok":
        return f"⚠️ {result['message']}"

    parts = []
    for filename, content in result["logs"].items():
        parts.append(f"### `{filename}`\n```\n{content}\n```")

    return "\n\n".join(parts) if parts else "No log content found."


# ╔══════════════════════════════════════════════════════════╗
# ║  Entry point                                             ║
# ╚══════════════════════════════════════════════════════════╝

if __name__ == "__main__":
    mcp.run()
