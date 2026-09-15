---
name: asllm-nerdctl
description: Deploy, manage, and query LLM models (such as Qwen, DeepSeek, and GLM) in nerdctl containers using asllm images on Alibaba 890P (AliXPU) accelerators. Use whenever asked to start, stop, restart, inspect, benchmark, test, or troubleshoot LLM inference servers via nerdctl, containerd, vLLM, or SGLang with asllm container images or /dev/alixpu devices.
license: MIT
---

# asllm-nerdctl

Manage containerized LLM inference servers (vLLM and SGLang) running inside `asllm` images using `nerdctl` on Alibaba 890P (AliXPU) hardware.

## System Prerequisites

1. **Runtime**: `nerdctl` with `containerd` (default or `k8s.io` namespace).
2. **Hardware**: Alibaba 890P server with 8 PPUs mapped as `/dev/alixpu`, `/dev/alixpu_ctl`, and `/dev/alixpu_ppu0` through `/dev/alixpu_ppu7`.
3. **Storage**: Model weights mounted from host `/bmcp_lvm_fs/cusa/models` into container `/models`.
4. **Base Image**: Standard `asllm` distribution, such as:
   `asllm:2.0.0-pytorch2.10.0-ubuntu24.04-sail2.1.0-cuda13.0-sglang0.5.13-vllm0.23.0-py312`

---

## Container Lifecycle Workflow

### 1. Launch Container

Remove any stale container with the same name before running:

```bash
nerdctl rm -f <container_name> 2>/dev/null
```

Start the detached container with host networking, shared IPC, appropriate PPU devices, and vLLM:

```bash
nerdctl run -d --name <container_name> \
  --network host \
  --ipc host \
  --shm-size 128g \
  --device /dev/alixpu \
  --device /dev/alixpu_ctl \
  --device /dev/alixpu_ppu0 \
  --device /dev/alixpu_ppu1 \
  -v /bmcp_lvm_fs/cusa/models:/models \
  asllm:2.0.0-pytorch2.10.0-ubuntu24.04-sail2.1.0-cuda13.0-sglang0.5.13-vllm0.23.0-py312 \
  python -m vllm.entrypoints.openai.api_server \
  --model /models/<model_dir> \
  --served-model-name <model_alias> \
  --port 8000 \
  --tensor-parallel-size 2 \
  --distributed-executor-backend mp \
  --trust-remote-code \
  --gpu-memory-utilization 0.90 \
  --max-model-len 24576 \
  --max-num-batched-tokens 16384 \
  --no-enable-prefix-caching \
  --enable-chunked-prefill \
  --dtype bfloat16
```

> **Note**: Adjust `--device /dev/alixpu_ppu*` and `--tensor-parallel-size` according to model size (e.g. 2 PPUs for 27B, 8 PPUs for 70B+ or MoE models). See [Model & Hardware Guide](references/models-and-hardware.md).

### 2. Monitor Startup & Logs

Model startup takes 3 to 5 minutes due to model weight loading, torch compilation, and CUDA graph capture:

```bash
nerdctl logs -f --tail 100 <container_name>
```

Look for the following log milestones:
1. `Loading model weights took ...`
2. `Capturing CUDA graphs ...`
3. `Application startup complete.`
4. `Uvicorn running on http://0.0.0.0:8000`

### 3. Check Health Status

Run the bundled healthcheck script:

```bash
bash skills/asllm-nerdctl/scripts/healthcheck.sh <container_name> 8000 300
```

Or poll the endpoint directly with curl:

```bash
curl -s -w "\nHTTP Status: %{http_code}\n" http://localhost:8000/health
```

Expect `HTTP Status: 200` once the server is ready.

### 4. Query the OpenAI-Compatible API

#### Verify Model Availability

```bash
curl -s http://localhost:8000/v1/models | jq .
```

#### Test Chat Completion

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<model_alias>",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain tensor parallelism in one sentence."}
    ],
    "max_tokens": 128,
    "temperature": 0.7
  }' | jq .
```

#### Test Streaming Completion

```bash
curl -N http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<model_alias>",
    "messages": [{"role": "user", "content": "Count from 1 to 5"}],
    "max_tokens": 64,
    "stream": true
  }'
```

### 5. Stop and Clean Up

```bash
# Graceful stop
nerdctl stop <container_name>

# Force stop and remove
nerdctl rm -f <container_name>
```

---

## Critical Rules and Pitfalls

1. **Device Mapping**:
   Always map `/dev/alixpu` and `/dev/alixpu_ctl`, along with every `/dev/alixpu_ppu<idx>` used by `--tensor-parallel-size N`. Missing devices lead to `Failed to infer device type`.

2. **Multiprocessing Backend**:
   Always set `--distributed-executor-backend mp`. Do not omit this or use `ray` on AliXPU unless explicitly configured.

3. **IPC & Shared Memory**:
   Always specify `--ipc host` and `--shm-size 128g` (or `256g`). Without shared IPC, workers crash with `shm_broadcast` errors during parallel synchronization.

4. **Boolean Flags Syntax**:
   In vLLM CLI, flags such as `--no-enable-prefix-caching` and `--enable-chunked-prefill` are boolean toggles that take **no values**.
   * Correct: `--no-enable-prefix-caching`
   * **Wrong**: `--no-enable-prefix-caching true` (causes `unrecognized arguments: true` and container exits with code 1).

5. **Spelling Sensitivity**:
   Watch out for `--max-num-batched-tokens` ("batched", not "betched"). Typos cause immediate container failure.

6. **Context Length Sizing**:
   Even if a model supports 256k tokens (e.g. Qwen3.8), cap `--max-model-len` to realistic lengths (such as 24576 or 32768) to prevent out-of-memory (OOM) aborts on startup.

---

## Deep-Dive References

- [Model Recipes and AliXPU Hardware Configurations](references/models-and-hardware.md): Recommended configs for Qwen3.8-27B, DeepSeek-V4-Flash, and GLM-5.1.
- [Troubleshooting Guide](references/troubleshooting.md): Diagnosis and remedies for container exit codes 1, 137, missing devices, and port collisions.
