# Models and AliXPU Hardware Reference

This reference outlines tested hardware configurations, tensor parallel layouts, and model profiles for running inference on Alibaba 890P (AliXPU) nodes.

## Hardware Architecture: Alibaba 890P (AliXPU)

An Alibaba 890P node contains:
- 8 Neural Processing / PPU accelerators exposed as `/dev/alixpu_ppu0` through `/dev/alixpu_ppu7`.
- Master control devices `/dev/alixpu` and `/dev/alixpu_ctl`.
- High-bandwidth interconnect between PPUs for tensor parallel communication.
- Typical host memory: ~1.4 TiB RAM.
- Typical shared memory (`/dev/shm`) allocated per container: `128g` to `256g`.

### Device Mapping by Tensor Parallel (TP) Size

| TP Size | Required Devices |
|---|---|
| TP=2 | `/dev/alixpu`, `/dev/alixpu_ctl`, `/dev/alixpu_ppu0`, `/dev/alixpu_ppu1` |
| TP=4 | `/dev/alixpu`, `/dev/alixpu_ctl`, `/dev/alixpu_ppu0`..`/dev/alixpu_ppu3` |
| TP=8 | `/dev/alixpu`, `/dev/alixpu_ctl`, `/dev/alixpu_ppu0`..`/dev/alixpu_ppu7` |

---

## Model Profiles and Tested Configurations

### 1. Qwen3.8-27B (Multimodal Vision + Language)

- **Path**: `/models/Qwen3.8-27B` (mounted from host `/bmcp_lvm_fs/cusa/models/Qwen3.8-27B`)
- **Weights**: ~54 GB (18 safetensor shards)
- **Data Type**: `bfloat16`
- **TP Size**: 2
- **Memory footprint**: ~26.6 GiB per PPU
- **Recommended Command**:
  ```bash
  python -m vllm.entrypoints.openai.api_server \
    --model /models/Qwen3.8-27B \
    --served-model-name qwen3.8-27b \
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

### 2. DeepSeek-V4-Flash-0731

- **Path**: `/models/DeepSeek-V4-Flash-0731`
- **TP Size**: 8 (spans `/dev/alixpu_ppu0` through `ppu7`)
- **KV Cache Dtype**: `fp8`
- **Recommended Command**:
  ```bash
  python -m vllm.entrypoints.openai.api_server \
    --model /models/DeepSeek-V4-Flash-0731 \
    --served-model-name deepseek-v4-flash \
    --port 8000 \
    --tensor-parallel-size 8 \
    --distributed-executor-backend mp \
    --trust-remote-code \
    --gpu-memory-utilization 0.90 \
    --kv-cache-dtype fp8 \
    --no-enable-prefix-caching \
    --max-model-len 60000
  ```

### 3. GLM-5.1 / GLM-5.2

- **Path**: `/models/GLM-5.1`
- **TP Size**: 8 (spans `/dev/alixpu_ppu0` through `ppu7`)
- **Shm Size**: `256g`
- **Recommended Command**:
  ```bash
  python -m vllm.entrypoints.openai.api_server \
    --model /models/GLM-5.1 \
    --served-model-name glm-5.1 \
    --port 8000 \
    --tensor-parallel-size 8 \
    --distributed-executor-backend mp \
    --trust-remote-code \
    --gpu-memory-utilization 0.85 \
    --max-model-len 60000
  ```

---

## Container Image Variants

The `asllm` images bundle custom hardware drivers, compiler stacks (SAIL), and inference frameworks:

1. **Production Balanced**:
   `asllm:2.0.0-pytorch2.10.0-ubuntu24.04-sail2.1.0-cuda13.0-sglang0.5.13-vllm0.23.0-py312`
   Recommended default for vLLM 0.23.0 workloads.

2. **Registry-Tagged Versions**:
   `reg.docker.alibaba-inc.com/ai_container/asllm:2.0.1-temp01-pytorch2.11.0-ubuntu24.04-sail2.1.1-cuda13.0-sglang0.5.16-py312`
   Used for newer SGLang 0.5.16 and PyTorch 2.11 environments.
