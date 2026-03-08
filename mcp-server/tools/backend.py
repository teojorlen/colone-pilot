"""backend.py — Start, stop, and probe the llama-server backends."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import httpx

from . import config as cfg

REPO_ROOT = Path(__file__).parent.parent.parent


# ── Health probing (identified by port, not process name) ─────────────────────

async def _probe(url: str) -> dict:
    """Hit a /health endpoint and return metadata."""
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            r = await client.get(url)
            try:
                body = r.json()
            except Exception:
                body = r.text
            return {"reachable": True, "status_code": r.status_code, "body": body}
    except Exception as exc:
        return {"reachable": False, "error": str(exc)}


async def status() -> dict:
    """Probe both llama-server /health endpoints and return per-server status."""
    conf = cfg.load()
    chat_port = int(conf.get("ChatPort") or conf.get("HTTP_PORT") or 8080)
    comp_port = int(conf.get("CompletionPort") or 8081)

    chat_probe = await _probe(f"http://127.0.0.1:{chat_port}/health")
    comp_probe = await _probe(f"http://127.0.0.1:{comp_port}/health")

    return {
        "chat": {
            "port": chat_port,
            "model": conf.get("ChatModel") or conf.get("CHAT_MODEL"),
            **chat_probe,
        },
        "completion": {
            "port": comp_port,
            "model": conf.get("CompletionModel") or conf.get("COMPLETION_MODEL"),
            **comp_probe,
        },
    }


# ── Start / Stop ───────────────────────────────────────────────────────────────

def start(force: bool = False) -> dict:
    """
    Start the dual backend by calling the appropriate OS script.
    Pass force=True to automatically stop existing servers via -Force param.
    """
    if sys.platform == "win32":
        script = REPO_ROOT / "windows" / "start-dual-backend.ps1"
        args = ["pwsh", "-NonInteractive", "-File", str(script)]
        if force:
            args.append("-Force")
    else:
        script = REPO_ROOT / "linux" / "start-backend.sh"
        args = ["bash", str(script)]

    result = subprocess.run(args, capture_output=True, text=True, timeout=120)
    return {
        "exit_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def stop() -> dict:
    """Stop all running backend servers."""
    if sys.platform == "win32":
        script = REPO_ROOT / "windows" / "stop-backend-windows.ps1"
        args = ["pwsh", "-NonInteractive", "-File", str(script)]
    else:
        compose_file = REPO_ROOT / "linux" / "docker-compose.yml"
        args = ["docker-compose", "-f", str(compose_file), "down"]

    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    return {
        "exit_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }
