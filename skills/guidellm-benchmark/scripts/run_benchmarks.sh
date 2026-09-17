#!/usr/bin/env bash
#
# run_benchmarks.sh
# Orchestrate GuideLLM load benchmarks across all profiles against an LLM endpoint
# using nerdctl or docker with ghcr.io/vllm-project/guidellm:latest.
#

set -euo pipefail

ENDPOINT="http://localhost:8000"
CONTAINER_NAME=""
RUNTIME=""
MAX_DURATION="180" # Default 180s for statistically valid 8k->1k runs; use 60s for smoke testing
PRESET="8k-1k"
PROMPT_TOKENS="8192"
OUTPUT_TOKENS="1024"
SELECTED_PROFILE="sweep" # Default: sweep (covers baseline sync, peak throughput, and interpolated rates)
HOST_MODEL_PATH=""       # Host path to model weights/tokenizer (for offline/air-gapped runs)
GUIDELLM_IMAGE="ghcr.io/vllm-project/guidellm:latest"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -e, --endpoint URL          Target OpenAI-compatible endpoint (default: http://localhost:8000)
  -c, --container NAME        Name or ID of serving container (vLLM/SGLang) to inspect
  -r, --runtime RUNTIME       Container runtime: docker or nerdctl (default: auto-detect)
  -d, --duration SECONDS      Max duration constraint per profile strategy (default: 180s, use 60s for smoke)
  --preset PRESET             Workload preset: 8k-1k (default, 180s), chat (2k->512, 120s), reasoning (4k->2k, 240s), quick (256->128, 60s)
  --profile PROFILE           Profile to run: sweep (default), concurrent, synchronous, throughput, constant, poisson, or all
  --launch-config FILE        Path to existing launch_config.json to bundle with run
  -m, --model-path PATH       Host path to model directory for offline tokenizer loading (avoids Errno 101)
  -p, --prompt-tokens NUM     Synthetic prompt token count (default: 8192)
  -o, --output-tokens NUM     Synthetic output token count (default: 1024)
  -i, --image IMAGE           GuideLLM container image (default: ghcr.io/vllm-project/guidellm:latest)
EOF
  exit 1
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    -c|--container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    -r|--runtime)
      RUNTIME="$2"
      shift 2
      ;;
    -d|--duration)
      MAX_DURATION="$2"
      shift 2
      ;;
    --preset)
      PRESET="$2"
      case "$PRESET" in
        8k-1k|rag|standard)
          PROMPT_TOKENS="8192"
          OUTPUT_TOKENS="1024"
          MAX_DURATION="180"
          ;;
        chat)
          PROMPT_TOKENS="2048"
          OUTPUT_TOKENS="512"
          MAX_DURATION="120"
          ;;
        reasoning)
          PROMPT_TOKENS="4096"
          OUTPUT_TOKENS="2048"
          MAX_DURATION="240"
          ;;
        quick|smoke)
          PROMPT_TOKENS="256"
          OUTPUT_TOKENS="128"
          MAX_DURATION="60"
          ;;
        *)
          echo "Warning: Unknown preset '$PRESET'. Keeping current values."
          ;;
      esac
      shift 2
      ;;
    --profile)
      SELECTED_PROFILE="$2"
      shift 2
      ;;
    --launch-config)
      USER_LAUNCH_CONFIG="$2"
      shift 2
      ;;
    -m|--model-path)
      HOST_MODEL_PATH="$2"
      shift 2
      ;;
    -p|--prompt-tokens)
      PROMPT_TOKENS="$2"
      shift 2
      ;;
    -o|--output-tokens)
      OUTPUT_TOKENS="$2"
      shift 2
      ;;
    -i|--image)
      GUIDELLM_IMAGE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Detect container runtime if not provided
if [[ -z "$RUNTIME" ]]; then
  if command -v nerdctl &>/dev/null; then
    RUNTIME="nerdctl"
  elif command -v docker &>/dev/null; then
    RUNTIME="docker"
  else
    RUNTIME="nerdctl" # fallback default
  fi
fi

# Prepare timestamped results directory
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BASE_DIR="$(pwd)"
RUN_DIR="guidellm_run_${TIMESTAMP}"
TARGET_DIR="${BASE_DIR}/${RUN_DIR}"

echo "============================================================"
echo "GuideLLM Benchmark Runner"
echo "Start Time:         ${START_TIME}"
echo "Target Endpoint:    ${ENDPOINT}"
echo "Serving Container:  ${CONTAINER_NAME:-None (unspecified)}"
echo "Container Runtime:  ${RUNTIME}"
echo "Output Directory:   ${TARGET_DIR}"
echo "Selected Profile:   ${SELECTED_PROFILE}"
echo "Local Model Path:   ${HOST_MODEL_PATH:-Auto-detecting...}"
echo "GuideLLM Image:     ${GUIDELLM_IMAGE}"
echo "Dry Run Mode:       ${DRY_RUN}"
echo "============================================================"

if [[ "$DRY_RUN" = false ]]; then
  mkdir -p "${TARGET_DIR}/profiles"
  chmod 777 "${TARGET_DIR}" "${TARGET_DIR}/profiles" 2>/dev/null || true
fi

# 1. Inspect target model endpoint
MODEL_ID="unknown"
if [[ "$DRY_RUN" = false ]]; then
  echo "Checking endpoint ${ENDPOINT}/v1/models..."
  MODEL_RESPONSE=$(curl -s --connect-timeout 5 "${ENDPOINT}/v1/models" 2>/dev/null || echo "{}")
  echo "$MODEL_RESPONSE" > "${TARGET_DIR}/model_info.json"
  MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.data[0].id // "unknown"' 2>/dev/null || echo "unknown")
  echo "Resolved Model ID: ${MODEL_ID}"
fi

# 2. Inspect serving container if specified
CONTAINER_IMAGE="N/A"
CONTAINER_CMD="N/A"
CONTAINER_DEVICES="N/A"
CONTAINER_MOUNTS="N/A"
CONTAINER_ENV="N/A"

if [[ -n "$CONTAINER_NAME" && "$DRY_RUN" = false ]]; then
  echo "Inspecting serving container '${CONTAINER_NAME}' via ${RUNTIME}..."
  if $RUNTIME inspect "$CONTAINER_NAME" > "${TARGET_DIR}/serving_container_inspect.json" 2>/dev/null; then
    CONTAINER_IMAGE=$($RUNTIME inspect --format '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || echo "N/A")
    CONTAINER_CMD=$($RUNTIME inspect --format '{{json .Config.Cmd}}' "$CONTAINER_NAME" 2>/dev/null || echo "N/A")
    CONTAINER_DEVICES=$($RUNTIME inspect --format '{{json .HostConfig.Devices}}' "$CONTAINER_NAME" 2>/dev/null || echo "N/A")
    CONTAINER_MOUNTS=$($RUNTIME inspect --format '{{json .Mounts}}' "$CONTAINER_NAME" 2>/dev/null || echo "N/A")
    CONTAINER_ENV=$($RUNTIME inspect --format '{{json .Config.Env}}' "$CONTAINER_NAME" 2>/dev/null || echo "N/A")
  else
    echo "Warning: Unable to inspect container '${CONTAINER_NAME}'"
  fi
fi

    # Auto-detect host model path if not explicitly provided
    if [[ -z "$HOST_MODEL_PATH" ]]; then
      HOST_MODEL_PATH=$(python3 -c '
import json, sys, os
inspect_file = sys.argv[1]
try:
    with open(inspect_file) as f:
        data = json.load(f)
    cdata = data[0] if isinstance(data, list) else data
    cmd = cdata.get("Config", {}).get("Cmd") or []
    model_arg = ""
    for i in range(len(cmd) - 1):
        if cmd[i] == "--model":
            model_arg = cmd[i+1]
            break
    mounts = cdata.get("Mounts") or []
    for m in mounts:
        dest = m.get("Destination", "")
        src = m.get("Source", "")
        if model_arg.startswith(dest) and dest != "/":
            rel = os.path.relpath(model_arg, dest)
            candidate = os.path.join(src, rel) if rel != "." else src
            if os.path.exists(candidate):
                print(candidate)
                sys.exit(0)
except Exception:
    pass
' "${TARGET_DIR}/serving_container_inspect.json" 2>/dev/null || true)
      if [[ -n "$HOST_MODEL_PATH" ]]; then
        echo "Auto-detected host model directory: ${HOST_MODEL_PATH}"
      fi
    fi
# 3. Define load profiles
# All GuideLLM benchmark profiles:
# - synchronous: sequential baseline
# - throughput: peak concurrent throughput
# - concurrent: multi-stream parallel requests
# - constant: fixed request rate
# - poisson: Poisson distributed arrival rate
# - sweep: adaptive multi-strategy interpolation sweep
declare -A PROFILE_DESCRIPTIONS=(
  ["synchronous"]="Sequential requests measuring baseline latency"
  ["throughput"]="Peak throughput discovery with parallel workers"
  ["concurrent"]="Multi-stream parallel load testing"
  ["constant"]="Sustained rate (requests per second) testing"
  ["poisson"]="Probabilistic Poisson traffic distribution"
  ["sweep"]="Multi-strategy adaptive rate interpolation sweep"
)

declare -A PROFILE_CONFIGS=(
  ["synchronous"]="--profile kind=synchronous"
  ["throughput"]="--profile kind=throughput,max_concurrency=32,rampup_duration=10"
  ["concurrent"]="--profile kind=concurrent,streams=16,rampup_duration=10"
  ["constant"]="--profile kind=constant,rate=10,rampup_duration=10"
  ["poisson"]="--profile kind=poisson,rate=10 --seed kind=static,value=42"
  ["sweep"]="--profile kind=sweep,sweep_size=6,rampup_duration=10"
)

ALL_PROFILES=("synchronous" "throughput" "concurrent" "constant" "poisson" "sweep")

if [[ "$SELECTED_PROFILE" == "all" ]]; then
  PROFILES=("${ALL_PROFILES[@]}")
elif [[ -n "${PROFILE_CONFIGS[$SELECTED_PROFILE]:-}" ]]; then
  PROFILES=("$SELECTED_PROFILE")
else
  echo "Error: Unknown profile '${SELECTED_PROFILE}'. Choose one of: sweep, concurrent, synchronous, throughput, constant, poisson, all."
  exit 1
fi

for profile in "${PROFILES[@]}"; do
  echo "------------------------------------------------------------"
  echo "Running profile: ${profile}"
  echo "------------------------------------------------------------"

  PROFILE_DIR="${TARGET_DIR}/profiles/${profile}"
  if [[ "$DRY_RUN" = false ]]; then
    mkdir -p "${PROFILE_DIR}"
    chmod 777 "${PROFILE_DIR}" 2>/dev/null || true
  fi

  # Offline tokenizer configuration if local model path exists
  EXTRA_VOLUMES=()
  TOKENIZER_ARGS=()
  if [[ -n "$HOST_MODEL_PATH" && (-d "$HOST_MODEL_PATH" || "$DRY_RUN" = true) ]]; then
    EXTRA_VOLUMES=("-v" "${HOST_MODEL_PATH}:/model:ro")
    TOKENIZER_ARGS=(--tokenizer '{"kind":"huggingface_auto","model":"/model","load_kwargs":{"trust_remote_code":true}}')
  fi

  CMD=(
    "$RUNTIME" run --rm
    --network host
    -v "${PROFILE_DIR}:/results:rw"
    "${EXTRA_VOLUMES[@]}"
    "$GUIDELLM_IMAGE"
    run
    --backend "kind=openai_http,target=${ENDPOINT}"
    --data "kind=synthetic_text,prompt_tokens=${PROMPT_TOKENS},output_tokens=${OUTPUT_TOKENS}"
    --constraint "kind=max_duration,seconds=${MAX_DURATION}"
    $PROFILE_ARGS
    "${TOKENIZER_ARGS[@]}"
    --output "kind=csv,path=/results/benchmarks.csv"
    --output "kind=json,path=/results/benchmarks.json"
    --output "kind=html,path=/results/benchmarks.html"
    --output "kind=plot,path=/results/benchmarks.png"
  )

  echo "Command: ${CMD[*]}"

  if [[ "$DRY_RUN" = false ]]; then
    "${CMD[@]}" || echo "Profile '${profile}' exited with code $?"
  fi
done

# 4. Generate launch_config.json and report
REPORT_FILE="${TARGET_DIR}/REPORT.md"
LAUNCH_CONFIG_FILE="${TARGET_DIR}/launch_config.json"

if [[ "$DRY_RUN" = false ]]; then
  # Handle launch_config.json
  if [[ -n "${USER_LAUNCH_CONFIG:-}" && -f "$USER_LAUNCH_CONFIG" ]]; then
    cp "$USER_LAUNCH_CONFIG" "$LAUNCH_CONFIG_FILE"
  else
    # Construct launch_config.json from inspection and runtime info
    python3 -c '
import json, sys, os

target_dir = sys.argv[1]
container_name = sys.argv[2]
runtime = sys.argv[3]
model_id = sys.argv[4]
endpoint = sys.argv[5]

inspect_path = os.path.join(target_dir, "serving_container_inspect.json")
config = {
    "model": model_id,
    "served_model_name": model_id,
    "port": 8000,
    "runtime": runtime,
    "container_name": container_name or "unspecified",
}

if os.path.exists(inspect_path):
    try:
        with open(inspect_path) as f:
            data = json.load(f)
        if isinstance(data, list) and len(data) > 0:
            cdata = data[0]
        else:
            cdata = data

        cmd = cdata.get("Config", {}).get("Cmd") or []
        config["container_image"] = cdata.get("Config", {}).get("Image", "N/A")
        config["command"] = cmd

        # Parse common vLLM CLI flags from command list
        i = 0
        while i < len(cmd):
            arg = cmd[i]
            if arg == "--model" and i + 1 < len(cmd):
                config["model"] = cmd[i + 1]
            elif arg == "--served-model-name" and i + 1 < len(cmd):
                config["served_model_name"] = cmd[i + 1]
            elif arg == "--port" and i + 1 < len(cmd):
                config["port"] = int(cmd[i + 1])
            elif arg == "--tensor-parallel-size" and i + 1 < len(cmd):
                config["tensor_parallel_size"] = int(cmd[i + 1])
            elif arg == "--gpu-memory-utilization" and i + 1 < len(cmd):
                config["gpu_memory_utilization"] = float(cmd[i + 1])
            elif arg == "--max-model-len" and i + 1 < len(cmd):
                config["max_model_len"] = int(cmd[i + 1])
            elif arg == "--max-num-seqs" and i + 1 < len(cmd):
                config["max_num_seqs"] = int(cmd[i + 1])
            elif arg == "--kv-cache-dtype" and i + 1 < len(cmd):
                config["kv_cache_dtype"] = cmd[i + 1]
            elif arg == "--distributed-executor-backend" and i + 1 < len(cmd):
                config["distributed_executor_backend"] = cmd[i + 1]
            elif arg == "--trust-remote-code":
                config["trust_remote_code"] = True
            elif arg == "--enable-chunked-prefill":
                config["enable_chunked_prefill"] = True
            elif arg == "--no-enable-prefix-caching":
                config["no_enable_prefix_caching"] = True
            i += 1

        # Devices
        devices = cdata.get("HostConfig", {}).get("Devices") or []
        config["devices"] = [d.get("PathOnHost", d.get("path", "")) for d in devices if isinstance(d, dict)]
        config["shm_size"] = str(cdata.get("HostConfig", {}).get("ShmSize", "N/A"))
    except Exception as e:
        config["parse_error"] = str(e)

with open(os.path.join(target_dir, "launch_config.json"), "w") as f:
    json.dump(config, f, indent=2)
' "${TARGET_DIR}" "${CONTAINER_NAME:-}" "${RUNTIME}" "${MODEL_ID}" "${ENDPOINT}" 2>/dev/null || true
  fi

  TABLE_ROWS=""
  for p in "${PROFILES[@]}"; do
    desc="${PROFILE_DESCRIPTIONS[$p]:-Benchmark profile}"
    TABLE_ROWS+="| **${p}** | ${desc} | [CSV](profiles/${p}/benchmarks.csv) \| [JSON](profiles/${p}/benchmarks.json) \| [HTML Report](profiles/${p}/benchmarks.html) \| [Chart (PNG)](profiles/${p}/benchmarks.png) |"$'\n'
  done

  cat <<EOF > "${REPORT_FILE}"
# LLM Benchmark Environment & Measurement Report

- **Run Start Time**: ${START_TIME}
- **Run Directory**: \`${RUN_DIR}\`
- **Target Endpoint**: \`${ENDPOINT}\`
- **Model Identifier**: \`${MODEL_ID}\`
- **Container Runtime**: \`${RUNTIME}\`
- **Serving Container**: \`${CONTAINER_NAME:-unspecified}\`
- **Selected Profile**: \`${SELECTED_PROFILE}\`
- **GuideLLM Image**: \`${GUIDELLM_IMAGE}\`

---

## 1. Serving Environment & Framework Attributes

### Model & Endpoint
- **Resolved Model ID**: \`${MODEL_ID}\`
- **Endpoint URL**: \`${ENDPOINT}\`
- **Model Info JSON**: [\`model_info.json\`](model_info.json)
- **Model Launch Configuration**: [\`launch_config.json\`](launch_config.json)

### Container Configuration (from \`${RUNTIME} inspect\`)
- **Serving Image**: \`${CONTAINER_IMAGE}\`
- **Container Command / Arguments**:
\`\`\`json
${CONTAINER_CMD}
\`\`\`
- **Hardware Devices**:
\`\`\`json
${CONTAINER_DEVICES}
\`\`\`
- **Storage Mounts**:
\`\`\`json
${CONTAINER_MOUNTS}
\`\`\`
- **Full Container Inspection**: [\`serving_container_inspect.json\`](serving_container_inspect.json)

---

## 2. Benchmark Measurement Artifacts

> **Notice**: To avoid context pollution, raw measurement datasets, metrics, and logs are not loaded into this report. Access individual files below for visualization and analysis.

| Profile | Profile Description | Generated Artifacts (Links) |
|---|---|---|
${TABLE_ROWS}
---
*Report generated by guidellm-benchmark skill.*
EOF

  echo "============================================================"
  echo "Benchmark Run Complete!"
  echo "Launch Config saved at: ${LAUNCH_CONFIG_FILE}"
  echo "Report generated at:    ${REPORT_FILE}"
  echo "============================================================"
fi
