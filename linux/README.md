# local-ai — Linux/WSL Setup

GPU-accelerated LLM inference using Docker and LocalAI, optimized for **AMD RX 9070XT (ROCm)** and **AMD 9900x3d CPU**.

---

## Hardware Requirements

| Component | Minimum | Used here |
|-----------|---------|-----------|
| CPU | x86-64, 8+ cores | AMD 9900x3d (12c/24t) |
| RAM | 16 GB | — |
| GPU | ROCm-compatible AMD | RX 9070XT (RDNA 4) |
| Storage | 20 GB free | SSD recommended |
| OS | Ubuntu 22.04+ | — |
| Docker | 24+ | — |
| ROCm | 6.0+ | — |

---

## Project Structure

```
linux/
├── config.sh.example       # Configuration template (copy to config.sh)
├── setup-config.sh         # Interactive configuration wizard
├── docker-compose.yml      # Container definition
├── docker-compose.gpu.yml  # GPU-specific overrides
├── .env.example            # Docker environment variables template
├── setup.sh                # First-time setup (deps, models, config)
├── start-backend.sh        # Start backend
├── update.sh               # Pull latest image and restart
└── README.md               # This file
```

Model files are stored **outside** the repo (default: `~/.local/share/localai/models`, mounted into the container).

---

## Quick Start

### 1. Install ROCm drivers

Follow the [ROCm installation guide](https://rocm.docs.amd.com/en/latest/Installation_Guide/Installation-Guide.html) for your kernel and GPU.

Verify your GPU is detected:
```bash
rocminfo | grep -E "Name:|Marketing"
rocm-smi
```

### 2. Clone and set up

```bash
git clone <this-repo> ~/code/local-ai
cd ~/code/local-ai/linux
chmod +x *.sh
```

### 3. Create configuration (first-time only)

**Option A — Interactive wizard (recommended):**
```bash
./setup-config.sh
```

This will:
- Detect any existing installations and offer migration
- Let you choose installation directory (default: `~/.local/share/localai`, no sudo needed)
- Configure ports, context sizes, and Docker image preferences
- Create your personalized `config.sh` and `.env` files

**Option B — Manual configuration:**
```bash
cp config.sh.example config.sh
cp .env.example .env
nano config.sh  # Customize paths and settings
```

### 4. Run setup

```bash
./setup.sh
```

`setup.sh` will:
- Install Docker, docker-compose, and ROCm utilities
- Create configured directories for models and config
- Download **CodeLlama 13B Q4** and **Mistral 7B Q4** (GGUF)
- Write LocalAI model config YAML files

### 5. Start the backend

```bash
./start-backend.sh
```

The API will be available at the configured port (default: `http://localhost:8080`).

### 6. Verify

```bash
# Health check (ready probe — available once models are loaded)
curl http://localhost:8080/readyz

# List loaded models
curl http://localhost:8080/v1/models | jq .

# Test completion
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codellama",
    "messages": [{"role":"user","content":"Write a Python hello world."}]
  }'
```

> **First run note:** The `latest-aio-cpu` image automatically downloads bundled models (~5 GB) on first start.
> The API becomes available after all downloads complete (allow 5–15 minutes depending on network speed).
> Monitor progress with `docker logs -f local-ai`.

---

## IDE Integration

### VS Code — Continue (recommended)

1. Install the [Continue extension](https://marketplace.visualstudio.com/items?itemName=Continue.continue).
2. Open Continue settings and set the provider to **OpenAI-compatible**.
3. Set `apiBase` to `http://localhost:8080` and `model` to `codellama`.

### VS Code — Tabby

1. Install the [Tabby extension](https://marketplace.visualstudio.com/items?itemName=TabbyML.vscode-tabby).
2. Open VS Code settings → **Tabby: Endpoint** → `http://localhost:8080`.

### JetBrains — Tabby

1. Install the Tabby plugin from the JetBrains Marketplace.
2. Set **Server URL** to `http://localhost:8080` in plugin settings.

`.vscode/settings.json` in the repo root pre-populates the URL for supported extensions.

---

## Configuration

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|  
| 8080 | HTTP | OpenAI-compatible REST API (default, configurable in config.sh) |
| 5000 | gRPC | LocalAI internal gRPC (configurable) |

To change ports, edit `config.sh`:
```bash
export HTTP_PORT=9000
export GRPC_PORT=5001
```

Then regenerate `.env`:
```bash
./setup-config.sh  # Or manually edit .env
```

### Models

Add models by dropping GGUF files into your configured models directory (default: `~/.local/share/localai/models`) and creating a matching YAML config in the config directory (default: `~/.local/share/localai/config`). Restart the container to reload.

Example config (`~/.local/share/localai/config/mymodel.yaml`):
```yaml
name: mymodel
backend: llama
parameters:
  model: mymodel.Q4_K_M.gguf
  context_size: 4096
  threads: 24
  gpu_layers: 40
```

Recommended quantization levels:
- **Q4_K_M** — best quality/speed tradeoff for 16 GB+ VRAM
- **Q8_0** — higher quality, requires more VRAM

### Hardware Tuning

| Variable | Default | Description |
|----------|---------|-------------|
| `THREADS` | `24` | CPU threads (match physical cores) |
| `ROCM_VISIBLE_DEVICES` | `0` | GPU index |
| `gpu_layers` (per model) | `40` | Layers offloaded to GPU; increase for more VRAM usage |

---

## Monitoring

```bash
# Container logs
docker logs -f local-ai

# Real-time resource usage
docker stats local-ai

# GPU status
rocm-smi

# CPU/memory
htop

# LocalAI metrics endpoint
curl http://localhost:8080/metrics
```

---

## Maintenance

### Update to latest image

```bash
./update.sh
```

### Manual steps

```bash
# Pull new image
docker pull localai/localai:latest-gpu-hipblas

# Restart
docker-compose down && docker-compose up -d
```

### Automated nightly updates (optional)

Add a cron job (adjust paths to match your installation):
```bash
# Open crontab
crontab -e

# Add this line (replace <user> with your username):
0 3 * * * cd /home/<user>/code/local-ai/linux && ./update.sh >> /var/log/local-ai-update.log 2>&1
```

**Or use generic path resolution:**
```bash
0 3 * * * cd ~/code/local-ai/linux && ./update.sh >> ~/local-ai-update.log 2>&1
```

### Watchtower (automatic image updates)

```bash
docker run -d \
  --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower local-ai --interval 86400
```

---

## Security

- The API has no authentication by default — bind only to `localhost` or use a reverse proxy with auth.
- Do not run the container with `--privileged`; the compose file uses only the required devices.
- Restrict firewall access to port 8080 to trusted interfaces only.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `permission denied /dev/kfd` | Add user to `video` group: `sudo usermod -aG video $USER` |
| GPU not used (slow inference) | Check `ROCM_VISIBLE_DEVICES`, increase `gpu_layers` in model config |
| Container exits immediately | Check `docker logs local-ai` for ROCm or model loading errors |
| API unreachable | Ensure port 8080 is not blocked; confirm container is healthy with `docker ps` |
| Model not listed | Check YAML config filename matches model file; restart container |

---

## License

All components used are open source:

| Component | License |
|-----------|---------|
| [LocalAI](https://github.com/mudler/LocalAI) | MIT |
| [CodeLlama](https://github.com/facebookresearch/codellama) | Llama 2 Community License |
| [Mistral 7B](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.2) | Apache 2.0 |
| [Continue](https://github.com/continuedev/continue) | Apache 2.0 |
| [Tabby](https://github.com/TabbyML/tabby) | Apache 2.0 |

No paid services or subscriptions are required.
