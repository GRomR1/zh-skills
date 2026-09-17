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
  -p, --prompt-tokens NUM     Synthetic prompt token count (default: 8192)
  -o, --output-tokens NUM     Synthetic output token count (default: 1024)
  -i, --image IMAGE           GuideLLM container image (default: ghcr.io/vllm-project/guidellm:latest)
  --dry-run                   Print commands without executing
  -h, --help                  Show this help message
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
echo "GuideLLM Image:     ${GUIDELLM_IMAGE}"
echo "Dry Run Mode:       ${DRY_RUN}"
echo "============================================================"

if [[ "$DRY_RUN" = false ]]; then
  mkdir -p "${TARGET_DIR}/profiles"
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

# 3. Define load profiles
# All GuideLLM benchmark profiles:
# - synchronous: sequential baseline
# - throughput: peak concurrent throughput
# - concurrent: multi-stream parallel requests
# - constant: fixed request rate
# - poisson: Poisson distributed arrival rate
# - sweep: adaptive multi-strategy interpolation sweep
declare -A PROFILE_CONFIGS=(
  ["synchronous"]="--profile kind=synchronous"
  ["throughput"]="--profile kind=throughput,max_concurrency=32,rampup_duration=10"
  ["concurrent"]="--profile kind=concurrent,streams=16,rampup_duration=10"
  ["constant"]="--profile kind=constant,rate=10,rampup_duration=10"
  ["poisson"]="--profile kind=poisson,rate=10 --seed kind=static,value=42"
  ["sweep"]="--profile kind=sweep,sweep_size=6,rampup_duration=10"
)

PROFILES=("synchronous" "throughput" "concurrent" "constant" "poisson" "sweep")

for profile in "${PROFILES[@]}"; do
  echo "------------------------------------------------------------"
  echo "Running profile: ${profile}"
  echo "------------------------------------------------------------"

  PROFILE_DIR="${TARGET_DIR}/profiles/${profile}"
  if [[ "$DRY_RUN" = false ]]; then
    mkdir -p "${PROFILE_DIR}"
  fi

  PROFILE_ARGS="${PROFILE_CONFIGS[$profile]}"

  CMD=(
    "$RUNTIME" run --rm
    --network host
    -v "${PROFILE_DIR}:/results:rw"
    "$GUIDELLM_IMAGE"
    run
    --backend "kind=openai_http,target=${ENDPOINT}"
    --data "kind=synthetic_text,prompt_tokens=${PROMPT_TOKENS},output_tokens=${OUTPUT_TOKENS}"
    --constraint "kind=max_duration,seconds=${MAX_DURATION}"
    $PROFILE_ARGS
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

# 4. Generate report with metadata and links
REPORT_FILE="${TARGET_DIR}/REPORT.md"

if [[ "$DRY_RUN" = false ]]; then
  cat <<EOF > "${REPORT_FILE}"
# LLM Benchmark Environment & Measurement Report

- **Run Start Time**: ${START_TIME}
- **Run Directory**: \`${RUN_DIR}\`
- **Target Endpoint**: \`${ENDPOINT}\`
- **Model Identifier**: \`${MODEL_ID}\`
- **Container Runtime**: \`${RUNTIME}\`
- **Serving Container**: \`${CONTAINER_NAME:-unspecified}\`
- **GuideLLM Image**: \`${GUIDELLM_IMAGE}\`

---

## 1. Serving Environment & Framework Attributes

### Model & Endpoint
- **Resolved Model ID**: \`${MODEL_ID}\`
- **Endpoint URL**: \`${ENDPOINT}\`
- **Model Info JSON**: [\`model_info.json\`](model_info.json)

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
| **synchronous** | Sequential requests measuring baseline latency | [CSV](profiles/synchronous/benchmarks.csv) \| [JSON](profiles/synchronous/benchmarks.json) \| [HTML Report](profiles/synchronous/benchmarks.html) \| [Chart (PNG)](profiles/synchronous/benchmarks.png) |
| **throughput** | Peak throughput discovery with parallel workers | [CSV](profiles/throughput/benchmarks.csv) \| [JSON](profiles/throughput/benchmarks.json) \| [HTML Report](profiles/throughput/benchmarks.html) \| [Chart (PNG)](profiles/throughput/benchmarks.png) |
| **concurrent** | Multi-stream parallel load testing | [CSV](profiles/concurrent/benchmarks.csv) \| [JSON](profiles/concurrent/benchmarks.json) \| [HTML Report](profiles/concurrent/benchmarks.html) \| [Chart (PNG)](profiles/concurrent/benchmarks.png) |
| **constant** | Sustained rate (requests per second) testing | [CSV](profiles/constant/benchmarks.csv) \| [JSON](profiles/constant/benchmarks.json) \| [HTML Report](profiles/constant/benchmarks.html) \| [Chart (PNG)](profiles/constant/benchmarks.png) |
| **poisson** | Probabilistic Poisson traffic distribution | [CSV](profiles/poisson/benchmarks.csv) \| [JSON](profiles/poisson/benchmarks.json) \| [HTML Report](profiles/poisson/benchmarks.html) \| [Chart (PNG)](profiles/poisson/benchmarks.png) |
| **sweep** | Multi-strategy adaptive rate interpolation sweep | [CSV](profiles/sweep/benchmarks.csv) \| [JSON](profiles/sweep/benchmarks.json) \| [HTML Report](profiles/sweep/benchmarks.html) \| [Chart (PNG)](profiles/sweep/benchmarks.png) |

---
*Report generated by guidellm-benchmark skill.*
EOF

  echo "============================================================"
  echo "Benchmark Run Complete!"
  echo "Report generated at: ${REPORT_FILE}"
  echo "============================================================"
fi
