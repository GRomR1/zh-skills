# GuideLLM Benchmark Report Template & Guidelines

This reference details the structure and composition of the benchmark report generated after running GuideLLM against an inference server.

## Context Preservation Rule

> **CRITICAL**: The generated `REPORT.md` must **NEVER** inline raw benchmark numbers, large metrics tables, full JSON dumps, or per-request latency distributions into the agent context.
>
> Inlining raw measurements pollutes the LLM context window with hundreds of tokens of tabular numbers that are difficult for LLMs to retain and irrelevant to architectural decisions.
>
> The report MUST contain:
> 1. Target model identity and endpoint information.
> 2. Serving container parameters (from `docker inspect` or `nerdctl inspect`).
> 3. Relative file paths / links to the generated CSV, JSON, HTML, and PNG artifacts.

---

## Standard Report Template

```markdown
# LLM Benchmark Environment & Measurement Report

- **Run Start Time**: YYYY-MM-DD HH:MM:SS
- **Run Directory**: `guidellm_run_YYYYMMDD_HHMMSS`
- **Target Endpoint**: `http://<host>:<port>`
- **Model Identifier**: `<model_name_or_id>`
- **Container Runtime**: `nerdctl` / `docker`
- **Serving Container**: `<container_name_or_id>`
- **GuideLLM Image**: `ghcr.io/vllm-project/guidellm:latest`

---

## 1. Serving Environment & Framework Attributes

### Model & Endpoint
- **Resolved Model ID**: `<model_id>`
- **Endpoint URL**: `http://<host>:<port>`
- **Model Info JSON**: [`model_info.json`](model_info.json)
- **Model Launch Configuration**: [`launch_config.json`](launch_config.json)

### Model Launch Configuration (`launch_config.json`)

A clean, machine-readable JSON snapshot of the serving model configuration, GPU allocations, and runtime parameters:

```json
{
  "model": "/models/Qwen3.8-27B-FP8",
  "served_model_name": "qwen-27b",
  "port": 8000,
  "kv_cache_dtype": "fp8",
  "tensor_parallel_size": 1,
  "distributed_executor_backend": "mp",
  "trust_remote_code": true,
  "gpu_memory_utilization": 0.90,
  "max_model_len": 32768,
  "max_num_seqs": 256,
  "enable_chunked_prefill": true,
  "no_enable_prefix_caching": true,
  "devices": ["/dev/alixpu", "/dev/alixpu_ctl", "/dev/alixpu_ppu2"],
  "ppu_assignment": "ppu2",
  "shm_size": "128g",
  "container_image": "asllm:2.0.0-pytorch2.10.0-ubuntu24.04-sail2.1.0-cuda13.0-sglang0.5.13-vllm0.23.0-py312",
  "container_name": "qwen27b-fp8-tp1",
  "runtime": "nerdctl"
}
```
### Container Configuration (from `<runtime> inspect`)
- **Serving Image**: `<serving_image_tag>`
- **Container Command / Arguments**:
\`\`\`json
[
  "python",
  "-m",
  "vllm.entrypoints.openai.api_server",
  "--model", "/models/Qwen3.8-27B",
  "--tensor-parallel-size", "2",
  "--gpu-memory-utilization", "0.90",
  "--max-model-len", "24576"
]
\`\`\`
- **Hardware Devices**:
\`\`\`json
[
  {"PathOnHost": "/dev/alixpu", "PathInContainer": "/dev/alixpu"},
  {"PathOnHost": "/dev/alixpu_ppu0", "PathInContainer": "/dev/alixpu_ppu0"},
  {"PathOnHost": "/dev/alixpu_ppu1", "PathInContainer": "/dev/alixpu_ppu1"}
]
\`\`\`
- **Storage Mounts**:
\`\`\`json
[
  {"Source": "/bmcp_lvm_fs/cusa/models", "Destination": "/models", "Mode": "rw"}
]
\`\`\`
- **Full Container Inspection**: [`serving_container_inspect.json`](serving_container_inspect.json)

---

## 2. Benchmark Measurement Artifacts

> **Notice**: To avoid context pollution, raw measurement datasets, metrics, and logs are not loaded into this report. Access individual files below for visualization and analysis.

| Profile | Profile Description | Generated Artifacts (Links) |
|---|---|---|
| **synchronous** | Sequential requests measuring baseline latency | [CSV](profiles/synchronous/benchmarks.csv) \| [JSON](profiles/synchronous/benchmarks.json) \| [HTML Report](profiles/synchronous/benchmarks.html) \| [Chart (PNG)](profiles/synchronous/benchmarks.png) |
| **throughput** | Peak throughput discovery with parallel workers | [CSV](profiles/throughput/benchmarks.csv) \| [JSON](profiles/throughput/benchmarks.json) \| [HTML Report](profiles/throughput/benchmarks.html) \| [Chart (PNG)](profiles/throughput/benchmarks.png) |
| **concurrent** | Multi-stream parallel load testing | [CSV](profiles/concurrent/benchmarks.csv) \| [JSON](profiles/concurrent/benchmarks.json) \| [HTML Report](profiles/concurrent/benchmarks.html) \| [Chart (PNG)](profiles/concurrent/benchmarks.png) |
| **constant** | Sustained rate (requests per second) testing | [CSV](profiles/constant/benchmarks.csv) \| [JSON](profiles/constant/benchmarks.json) \| [HTML Report](profiles/constant/benchmarks.html) \| [Chart (PNG)](profiles/constant/benchmarks.png) |
| **poisson** | Probabilistic Poisson traffic distribution | [CSV](profiles/poisson/benchmarks.csv) \| [JSON](profiles/poisson/benchmarks.json) \| [HTML Report](profiles/poisson/benchmarks.html) \| [Chart (PNG)](profiles/poisson/benchmarks.png) |
| **sweep** | Multi-strategy adaptive rate interpolation sweep | [CSV](profiles/sweep/benchmarks.csv) \| [JSON](profiles/sweep/benchmarks.json) \| [HTML Report](profiles/sweep/benchmarks.html) \| [Chart (PNG)](profiles/sweep/benchmarks.png) |
```
