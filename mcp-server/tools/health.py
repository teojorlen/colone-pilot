"""health.py — Disk, port, and GPU checks."""
from __future__ import annotations

import shutil
import socket
import subprocess
from pathlib import Path

from . import config as cfg


def system_health() -> dict:
    """Return disk space, port availability, and GPU detection results."""
    conf = cfg.load()
    base_dir = Path(conf.get("BaseDir") or conf.get("BASE_DIR") or "~").expanduser()
    chat_port = int(conf.get("ChatPort") or conf.get("HTTP_PORT") or 8080)
    comp_port = int(conf.get("CompletionPort") or 8081)

    return {
        "disk": _check_disk(base_dir),
        "ports": {
            str(chat_port): _port_free(chat_port),
            str(comp_port): _port_free(comp_port),
        },
        "gpu": _check_gpu(),
    }


def _check_disk(path: Path) -> dict:
    try:
        target = path if path.exists() else path.parent
        usage = shutil.disk_usage(target)
        free_gb = round(usage.free / 1_073_741_824, 1)
        total_gb = round(usage.total / 1_073_741_824, 1)
        return {"free_gb": free_gb, "total_gb": total_gb, "ok": free_gb >= 5}
    except Exception as exc:
        return {"error": str(exc)}


def _port_free(port: int) -> bool:
    """Return True if the port is not yet bound."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def _check_gpu() -> dict:
    """Try vulkaninfo (Windows/Linux) then rocminfo (Linux) to detect a GPU."""
    candidates = [
        (["vulkaninfo", "--summary"], ("deviceName", "AMD", "Radeon", "NVIDIA")),
        (["rocminfo"], ("Marketing Name",)),
    ]
    for cmd, keywords in candidates:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
            if r.returncode == 0:
                for line in r.stdout.splitlines():
                    if any(kw in line for kw in keywords):
                        return {"available": True, "tool": cmd[0], "info": line.strip()}
                # Command ran but nothing matched — still counts as "found"
                return {"available": True, "tool": cmd[0], "info": "GPU detected (no name line found)"}
        except FileNotFoundError:
            continue
        except Exception as exc:
            return {"available": False, "error": str(exc)}

    return {
        "available": False,
        "message": (
            "vulkaninfo and rocminfo not found in PATH. "
            "GPU may still work via llama.cpp — verify via Task Manager during inference."
        ),
    }
