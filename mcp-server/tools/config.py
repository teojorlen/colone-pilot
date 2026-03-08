"""config.py — Read LocalAI configuration from config.ps1 (Windows) or config.sh (Linux)."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

# mcp-server/tools/ -> mcp-server/ -> repo root
REPO_ROOT = Path(__file__).parent.parent.parent


def load() -> dict:
    """Return LocalAI configuration as a plain dict."""
    if sys.platform == "win32":
        return _load_windows()
    return _load_linux()


def _get_powershell_command() -> str:
    """Detect which PowerShell is available: pwsh (7+) or powershell (5.1)."""
    if shutil.which("pwsh"):
        return "pwsh"
    elif shutil.which("powershell"):
        return "powershell"
    else:
        raise RuntimeError("No PowerShell executable found (tried 'pwsh' and 'powershell')")


def _load_windows() -> dict:
    config_path = REPO_ROOT / "windows" / "config.ps1"
    if not config_path.exists():
        raise FileNotFoundError(
            f"config.ps1 not found at {config_path}\n"
            "Run .\\setup-config.ps1 to create it."
        )

    # Detect which PowerShell to use
    ps_cmd = _get_powershell_command()
    
    # Dot-source config.ps1 and emit the resulting hashtable as JSON
    ps_script = f'. "{config_path}"; $Global:LocalAIConfig | ConvertTo-Json -Depth 3'
    result = subprocess.run(
        [ps_cmd, "-NoProfile", "-NonInteractive", "-Command", ps_script],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to load config.ps1:\n{result.stderr.strip()}")

    raw = json.loads(result.stdout)
    # Normalize numeric strings that PowerShell may quote
    for key in ("ChatPort", "CompletionPort", "GpuLayers", "ChatContextSize", "CompletionContextSize", "Threads"):
        if key in raw and raw[key] is not None:
            try:
                raw[key] = int(raw[key])
            except (ValueError, TypeError):
                pass
    return raw


def _load_linux() -> dict:
    config_path = REPO_ROOT / "linux" / "config.sh"
    if not config_path.exists():
        raise FileNotFoundError(
            f"config.sh not found at {config_path}\n"
            "Run ./setup-config.sh to create it."
        )

    relevant = [
        "BASE_DIR", "MODELS_DIR", "CONFIG_DIR", "LOG_DIR",
        "HTTP_PORT", "GRPC_PORT", "CHAT_MODEL", "COMPLETION_MODEL",
        "CHAT_CONTEXT_SIZE", "COMPLETION_CONTEXT_SIZE", "GPU_LAYERS",
        "ENABLE_LOGGING",
    ]
    keys_repr = repr(relevant)
    bash_script = (
        f'source "{config_path}" && '
        f'python3 -c "import os, json; keys={keys_repr}; '
        f'print(json.dumps({{k: os.environ.get(k) for k in keys}}))"'
    )
    result = subprocess.run(
        ["bash", "-c", bash_script],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to load config.sh:\n{result.stderr.strip()}")

    return json.loads(result.stdout)
