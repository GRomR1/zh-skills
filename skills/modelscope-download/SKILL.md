---
name: modelscope-download
description: Download open-source LLM weights (e.g. Qwen, DeepSeek, GLM, Llama) from ModelScope using modelscope CLI inside an asllm container with nerdctl or docker. Handles forward proxy configuration, host storage volume mounting (/bmcp_lvm_fs/cusa/models), automated pip installation, download resumption, model verification, and container cleanup. Use whenever asked to download, pull, or fetch model weights from ModelScope or HuggingFace mirrors using asllm containers.
license: MIT
---

# modelscope-download

Download and verify open-source LLM model weights from [ModelScope](https://www.modelscope.cn/) using the `modelscope` CLI running inside an `asllm` container with `nerdctl` or `docker`.

---

## Prerequisites

1. **Container Runtime**: `nerdctl` (recommended on AliXPU / BMCP environments) or `docker`.
2. **Base Image**: An `asllm` container image, e.g.:
   `reg.docker.alibaba-inc.com/ai_container/asllm:2.0.1-temp01-pytorch2.11.0-ubuntu24.04-sail2.1.1-cuda13.0-sglang0.5.16-py312`
3. **Storage**: Host models storage volume mounted from `/bmcp_lvm_fs/cusa/models` to container `/models`.
4. **Network & Proxy**: Outbound forward proxy for environments without direct internet:
   - `http_proxy=http://103.32.249.1:3128`
   - `https_proxy=http://103.32.249.1:3128`
   - `no_proxy=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,103.32.0.0/16`

---

## Quick Start (Automated Script)

Use the bundled orchestrator script in `scripts/download_model.sh`:

```bash
# Basic download of Qwen3.8-27B to default host dir (/bmcp_lvm_fs/cusa/models/Qwen3.8-27B)
bash skills/modelscope-download/scripts/download_model.sh \
  --model Qwen/Qwen3.8-27B

# Enable verbose logs and progress bars if explicitly requested:
bash skills/modelscope-download/scripts/download_model.sh \
  --model Qwen/Qwen3.8-27B \
  --verbose

# Dry-run to preview commands without executing
bash skills/modelscope-download/scripts/download_model.sh \
  --model Qwen/Qwen3.8-27B \
  --dry-run
```

By default, the script enables quiet mode:
- Suppresses tqdm progress bars via `TQDM_DISABLE=1`.
- Suppresses verbose SDK logs via `MODELSCOPE_LOG_LEVEL=ERROR`.
- Runs `pip install -q`.
- Verifies directory size with `du -sh` and file count without dumping long shard lists into chat context.

---

## Step-by-Step Manual Workflow

Follow this procedure when executing commands directly or integrating into automation pipelines:

### 1. Launch Download Container

Run the `asllm` container in detached mode with host networking, proxy environment variables, quiet environment settings (`TQDM_DISABLE=1`, `MODELSCOPE_LOG_LEVEL=ERROR`), and the models volume mounted:

```bash
# Clean up any previous container with the same name
nerdctl rm -f hf-dl >/dev/null 2>&1 || true

# Start container
nerdctl run -d --name hf-dl \
  --network host \
  -e https_proxy=http://103.32.249.1:3128 \
  -e http_proxy=http://103.32.249.1:3128 \
  -e no_proxy=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,103.32.0.0/16 \
  -e TQDM_DISABLE=1 \
  -e MODELSCOPE_LOG_LEVEL=ERROR \
  -v /bmcp_lvm_fs/cusa/models:/models \
  reg.docker.alibaba-inc.com/ai_container/asllm:2.0.1-temp01-pytorch2.11.0-ubuntu24.04-sail2.1.1-cuda13.0-sglang0.5.16-py312 \
  sleep infinity
```

### 2. Install ModelScope CLI (Quiet)

Install `modelscope` inside the container quietly (`-q`):

```bash
nerdctl exec hf-dl pip install -q modelscope
```

*Note: In network environments requiring an internal PyPI mirror, append `-i https://mirrors.aliyun.com/pypi/simple/`.*

### 3. Download Model Weights (Quiet)

Execute `modelscope download` targeting container path `/models/<MODEL_DIR>`. The container's `TQDM_DISABLE=1` and `MODELSCOPE_LOG_LEVEL=ERROR` suppress progress bar spam:

```bash
# Example: Qwen3.8-27B
nerdctl exec hf-dl modelscope download \
  --model Qwen/Qwen3.8-27B \
  --local_dir /models/Qwen3.8-27B
```
#### Optional ModelScope CLI Flags
- `--revision <branch/tag/commit>`: Download a specific git revision.
- `--include "*.safetensors"`: Download only matching files.
- `--exclude "*.bin"`: Skip specific file patterns.

### 4. Verify Files and Disk Usage (Context-Safe)

To prevent blowing up the LLM agent's context window with dozens of `.safetensors` shard names, avoid bare `ls -l`. Use `du -sh` and targeted checks:

```bash
# Check total size occupied on disk (1 line)
du -sh /bmcp_lvm_fs/cusa/models/Qwen3.8-27B/

# Count total files without listing them all
echo "Total files: $(ls -1 /bmcp_lvm_fs/cusa/models/Qwen3.8-27B/ | wc -l)"

# Check essential configuration files
ls -lh /bmcp_lvm_fs/cusa/models/Qwen3.8-27B/config.json
```

### 5. Clean Up Container

Remove the temporary container silently after the download finishes:

```bash
nerdctl rm -f hf-dl >/dev/null 2>&1
```
---

## Resuming Interrupted Downloads

ModelScope automatically resumes partially downloaded files. If a download is cancelled or disconnected:
1. Ensure the container is running (Step 1).
2. Re-run the exact same `modelscope download --model ... --local_dir ...` command.
3. ModelScope checks existing `.safetensors` files and resumes only missing or incomplete shards.

---

## Detailed References

- [Model Catalog](references/model-catalog.md): Popular ModelScope model IDs (Qwen, DeepSeek, GLM, Llama) and estimated disk usage.
- [Troubleshooting Guide](references/troubleshooting.md): Solutions for proxy timeouts, disk space exhaustion, and pip install errors.
