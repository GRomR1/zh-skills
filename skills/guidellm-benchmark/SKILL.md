---
name: guidellm-benchmark
description: Benchmark LLM inference endpoints (vLLM, SGLang, etc.) with GuideLLM using nerdctl or docker containers and image ghcr.io/vllm-project/guidellm:latest. Executes all load profiles (synchronous, throughput, concurrent, constant, poisson, sweep) against a model endpoint, exports results in csv, json, html, png to a timestamped folder, and generates an environment and model metadata report linking to benchmark runs without loading raw metrics into context.
license: MIT
---

# guidellm-benchmark

Run comprehensive load and performance benchmarks against OpenAI-compatible LLM servers (e.g. vLLM, SGLang) using GuideLLM containerized via `nerdctl` or `docker`.

## Overview

- **Image**: `ghcr.io/vllm-project/guidellm:latest`
- **Runtimes Supported**: `nerdctl` (containerd) or `docker`
- **Network Mode**: `--network host` (allows connecting directly to localhost endpoints)
- **Profiles Executed**: All standard load profiles (`synchronous`, `throughput`, `concurrent`, `constant`, `poisson`, `sweep`)
- **Default Artifact Formats**: `csv`, `json`, `html`, `png`
- **Artifact Destination**: Dedicated timestamped folder in current working directory: `guidellm_run_YYYYMMDD_HHMMSS`
- **Context Protection**: The generated report contains model parameters, container inspection data, and relative links to measurement files. It does **not** inline raw benchmark numbers, preventing LLM context pollution.

---

## Quick Start (Automated Script)

Use the bundled orchestrator script in `scripts/run_benchmarks.sh`:

```bash
# Basic run against local server on port 8000
bash skills/guidellm-benchmark/scripts/run_benchmarks.sh \
  --endpoint http://localhost:8000 \
  --container <serving_container_name_or_id> \
  --runtime nerdctl \
  --duration 60

# Dry-run to preview commands without executing
bash skills/guidellm-benchmark/scripts/run_benchmarks.sh \
  --endpoint http://localhost:8000 \
  --dry-run
```

---

## Manual Execution Workflow

If running commands directly or adapting to custom pipelines, follow this step-by-step workflow:

### 1. Initialize Timestamped Run Directory

Create a timestamped directory in the current working directory:

```bash
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RUN_DIR="guidellm_run_${TIMESTAMP}"
mkdir -p "${RUN_DIR}/profiles/"{synchronous,throughput,concurrent,constant,poisson,sweep}
```

### 2. Inspect Serving Model & Container

Collect environment attributes and metadata to include in the final report:

```bash
# Query model name from endpoint
curl -s http://localhost:8000/v1/models > "${RUN_DIR}/model_info.json"
MODEL_ID=$(jq -r '.data[0].id' "${RUN_DIR}/model_info.json")

# Inspect the serving container (nerdctl or docker)
RUNTIME="nerdctl" # or docker
CONTAINER="<serving_container_name>"
$RUNTIME inspect "$CONTAINER" > "${RUN_DIR}/serving_container_inspect.json"
```

Extract key attributes for the report:
- Container image tag
- Command arguments (e.g. `--model`, `--tensor-parallel-size`, `--gpu-memory-utilization`, `--max-model-len`, `--dtype`)
- Mapped hardware devices (`/dev/alixpu*`, `/dev/nvidia*`)
- Volume mounts and IPC configuration

### 3. Execute GuideLLM Container for Each Profile

Run each profile using the container image. Note that the container entrypoint is `guidellm`, so the first argument passed must be `run`:

#### A. Synchronous Profile (Baseline Sequential Latency)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/synchronous:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=synchronous \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

#### B. Throughput Profile (Peak Capacity)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/throughput:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=throughput,max_concurrency=32,rampup_duration=10 \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

#### C. Concurrent Profile (Fixed Parallel Streams)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/concurrent:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=concurrent,streams=16,rampup_duration=10 \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

#### D. Constant Rate Profile (Sustained Request Rate)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/constant:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=constant,rate=10,rampup_duration=10 \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

#### E. Poisson Profile (Probabilistic Arrivals)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/poisson:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=poisson,rate=10 --seed kind=static,value=42 \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

#### F. Sweep Profile (Multi-Strategy Adaptive Sweep)
```bash
$RUNTIME run --rm --network host \
  -v "$(pwd)/${RUN_DIR}/profiles/sweep:/results:rw" \
  ghcr.io/vllm-project/guidellm:latest \
  run \
  --backend kind=openai_http,target=http://localhost:8000 \
  --data kind=synthetic_text,prompt_tokens=256,output_tokens=128 \
  --constraint kind=max_duration,seconds=60 \
  --profile kind=sweep,sweep_size=6,rampup_duration=10 \
  --output kind=csv,path=/results/benchmarks.csv \
  --output kind=json,path=/results/benchmarks.json \
  --output kind=html,path=/results/benchmarks.html \
  --output kind=plot,path=/results/benchmarks.png
```

---

### 4. Generate the Summary Report

Create `${RUN_DIR}/REPORT.md` linking to all run outputs. Follow the structure documented in [Report Template Reference](references/report-template.md):

1. **Header & Provenance**: Date, time, target URL, resolved model ID, runtime, and container ID.
2. **Serving Environment**: Serving container image, hardware devices, mounts, and model launch arguments.
3. **Artifact Links Table**: Relative links to each profile's CSV, JSON, HTML, and PNG artifacts.
4. **Context Cleanliness**: Never inline raw measurement numbers, throughput tables, or per-request latency stats into the report.

---

## Important Rules & Tips

1. **Container Subcommand**:
   Always pass `run` after `ghcr.io/vllm-project/guidellm:latest`. The image entrypoint is `/opt/app-root/bin/guidellm`; passing flags directly replaces the container command and causes command parse errors.

2. **Network Mode**:
   Always specify `--network host` so the GuideLLM container can access services running on host loopback (`http://localhost:8000`).

3. **Output Formats**:
   Specify `--output` repeatedly for each required format (`csv`, `json`, `html`, `plot`). For PNG charts, use `--output kind=plot,path=/results/benchmarks.png`.

4. **Preserving LLM Context**:
   When reporting completion to the user, present the summary of the environment and the paths to `REPORT.md` and the artifact files. Do not dump CSV rows or benchmark numbers into the chat.

---

## Deep-Dive References

- [GuideLLM Load Profiles Reference](references/profiles.md): In-depth mechanics of synchronous, throughput, concurrent, constant, poisson, and sweep profiles.
- [Report Template & Guidelines](references/report-template.md): Detailed layout for the environment report and artifact link tables.
