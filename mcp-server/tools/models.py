"""models.py — List installed GGUF models and verify against checksums.txt."""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path

from . import config as cfg

REPO_ROOT = Path(__file__).parent.parent.parent


def list_models() -> list[dict]:
    """Return a list of installed .gguf files with name, size, and path."""
    conf = cfg.load()
    models_dir = Path(conf.get("ModelsDir") or conf.get("MODELS_DIR", ""))

    if not models_dir.exists():
        return []

    return [
        {
            "name": f.name,
            "size_gb": round(f.stat().st_size / 1_073_741_824, 2),
            "path": str(f),
        }
        for f in sorted(models_dir.glob("*.gguf"))
    ]


def _load_checksums() -> dict[str, str | None]:
    """Parse checksums.txt → {filename: sha256_hex | None (placeholder)}."""
    checksums_path = REPO_ROOT / "checksums.txt"
    if not checksums_path.exists():
        return {}

    result: dict[str, str | None] = {}
    for line in checksums_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Valid checksum line: <64-char hex> <filename>
        m = re.match(r"^([a-fA-F0-9]{64})\s+(.+)$", line)
        if m:
            result[m.group(2).strip()] = m.group(1).upper()
            continue
        # Placeholder line: <filename> VERIFY_AFTER_DOWNLOAD
        m2 = re.match(r"^(\S+)\s+VERIFY_AFTER_DOWNLOAD$", line)
        if m2:
            result[m2.group(1)] = None

    return result


def verify_checksums(compute: bool = False) -> list[dict]:
    """
    Cross-reference installed models against checksums.txt.
    If compute=True, calculate SHA256 for each file (slow — ~30s per 7 GB model).
    """
    known = _load_checksums()
    results = []

    for model in list_models():
        fname = model["name"]
        entry: dict = {"name": fname}

        if fname not in known:
            entry.update(status="no_checksum", message="Not listed in checksums.txt")
        elif known[fname] is None:
            entry.update(status="placeholder", message="VERIFY_AFTER_DOWNLOAD — no hash yet")
        else:
            entry["expected"] = known[fname]
            if not compute:
                entry.update(status="not_computed", message="Pass compute=True to verify hash")
            else:
                sha256 = hashlib.sha256()
                with open(model["path"], "rb") as fh:
                    for chunk in iter(lambda: fh.read(65536), b""):
                        sha256.update(chunk)
                actual = sha256.hexdigest().upper()
                if actual == known[fname].upper():
                    entry.update(status="ok", actual=actual)
                else:
                    entry.update(status="mismatch", actual=actual)

        results.append(entry)

    return results


def get_model_names() -> list[str]:
    """Return a list of just the model filenames (without paths)."""
    return [m["name"] for m in list_models()]


def get_current_models() -> dict:
    """Return the currently configured chat and completion models."""
    conf = cfg.load()
    return {
        "chat": conf.get("ChatModel") or conf.get("CHAT_MODEL", "unknown"),
        "completion": conf.get("CompletionModel") or conf.get("COMPLETION_MODEL", "unknown"),
    }


def switch_model(server_type: str, model_name: str) -> dict:
    """
    Update the config to use a different model for chat or completion.
    
    server_type: "chat" or "completion"
    model_name: filename of the .gguf model (must exist in ModelsDir)
    
    Returns: dict with status and message
    
    Note: This updates the config file. You must restart the backend for changes to take effect.
    """
    if server_type not in ("chat", "completion"):
        return {"status": "error", "message": f"Invalid server_type: {server_type}. Must be 'chat' or 'completion'."}
    
    # Verify model exists
    available = get_model_names()
    if model_name not in available:
        return {
            "status": "error",
            "message": f"Model '{model_name}' not found. Available models: {', '.join(available)}",
        }
    
    # Update config based on OS
    if sys.platform == "win32":
        result = _update_windows_config(server_type, model_name)
    else:
        result = _update_linux_config(server_type, model_name)
    
    return result


def _update_windows_config(server_type: str, model_name: str) -> dict:
    """Update Windows config.ps1 with new model name."""
    config_path = REPO_ROOT / "windows" / "config.ps1"
    if not config_path.exists():
        return {"status": "error", "message": f"Config file not found: {config_path}"}
    
    try:
        content = config_path.read_text(encoding="utf-8")
        
        # Determine which config key to update
        if server_type == "chat":
            # Match: $ChatModel = "..." or $LocalAIConfig["ChatModel"] = "..."
            pattern = r'(\$ChatModel\s*=\s*["\'])([^"\']+)(["\'])'
            alt_pattern = r'(\$LocalAIConfig\["ChatModel"\]\s*=\s*["\'])([^"\']+)(["\'])'
        else:  # completion
            pattern = r'(\$CompletionModel\s*=\s*["\'])([^"\']+)(["\'])'
            alt_pattern = r'(\$LocalAIConfig\["CompletionModel"\]\s*=\s*["\'])([^"\']+)(["\'])'
        
        # Try both patterns
        if re.search(pattern, content):
            updated_content = re.sub(pattern, rf'\g<1>{model_name}\g<3>', content)
        elif re.search(alt_pattern, content):
            updated_content = re.sub(alt_pattern, rf'\g<1>{model_name}\g<3>', content)
        else:
            return {
                "status": "error",
                "message": f"Could not find {server_type.capitalize()}Model setting in config.ps1",
            }
        
        # Write back
        config_path.write_text(updated_content, encoding="utf-8")
        
        return {
            "status": "ok",
            "message": f"Updated {server_type} model to '{model_name}'. Restart the backend for changes to take effect.",
        }
    
    except Exception as e:
        return {"status": "error", "message": f"Failed to update config: {e}"}


def _update_linux_config(server_type: str, model_name: str) -> dict:
    """Update Linux config.sh with new model name."""
    config_path = REPO_ROOT / "linux" / "config.sh"
    if not config_path.exists():
        return {"status": "error", "message": f"Config file not found: {config_path}"}
    
    try:
        content = config_path.read_text(encoding="utf-8")
        
        # Determine which config key to update
        if server_type == "chat":
            pattern = r'(CHAT_MODEL=["|\'])([^"\']+)(["|\'])'
        else:  # completion
            pattern = r'(COMPLETION_MODEL=["|\'])([^"\']+)(["|\'])'
        
        if not re.search(pattern, content):
            return {
                "status": "error",
                "message": f"Could not find {server_type.upper()}_MODEL setting in config.sh",
            }
        
        updated_content = re.sub(pattern, rf'\g<1>{model_name}\g<3>', content)
        
        # Write back
        config_path.write_text(updated_content, encoding="utf-8")
        
        return {
            "status": "ok",
            "message": f"Updated {server_type} model to '{model_name}'. Restart the backend for changes to take effect.",
        }
    
    except Exception as e:
        return {"status": "error", "message": f"Failed to update config: {e}"}
