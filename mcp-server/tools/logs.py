"""logs.py — Tail llama-server log files from LogDir."""
from __future__ import annotations

from pathlib import Path

from . import config as cfg


_ENABLE_HINT = (
    "Logs are disabled by default (--log-disable in start-dual-backend.ps1).\n"
    "To enable: set EnableLogging=$true in windows/config.ps1, then restart the backend."
)


def tail(lines: int = 50, server: str = "all") -> dict:
    """
    Return the last `lines` of log output.
    server: "chat" | "completion" | "all"
    """
    conf = cfg.load()
    log_dir = Path(
        conf.get("LogDir") or conf.get("LOG_DIR") or "~/.local/share/localai/logs"
    ).expanduser()

    if not log_dir.exists():
        return {
            "status": "no_log_dir",
            "message": f"Log directory not found: {log_dir}\n{_ENABLE_HINT}",
        }

    # Determine which log files to include
    filter_map = {
        "chat": ("mistral",),
        "completion": ("codellama",),
        "all": (),
    }
    name_filters = filter_map.get(server, ())

    log_files = sorted(log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    if name_filters:
        log_files = [f for f in log_files if any(kw in f.stem for kw in name_filters)]

    if not log_files:
        return {
            "status": "no_logs",
            "message": f"No matching .log files found in {log_dir}.\n{_ENABLE_HINT}",
        }

    result = {}
    for log_file in log_files:
        all_lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
        result[log_file.name] = "\n".join(all_lines[-lines:])

    return {"status": "ok", "logs": result}
