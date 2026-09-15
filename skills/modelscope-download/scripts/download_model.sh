#!/usr/bin/env bash
# ==============================================================================
# ModelScope Model Downloader via asllm Container
# Downloads model weights to host storage using modelscope CLI inside an asllm container.
# ==============================================================================

set -euo pipefail

# Default configuration
MODEL_ID=""
LOCAL_DIR_NAME=""
HOST_MODELS_DIR="/bmcp_lvm_fs/cusa/models"
CONTAINER_MODELS_DIR="/models"
CONTAINER_IMAGE="reg.docker.alibaba-inc.com/ai_container/asllm:2.0.1-temp01-pytorch2.11.0-ubuntu24.04-sail2.1.1-cuda13.0-sglang0.5.16-py312"
CONTAINER_NAME="model-dl-$(date +%s)"
HTTP_PROXY_URL="http://103.32.249.1:3128"
HTTPS_PROXY_URL="http://103.32.249.1:3128"
NO_PROXY_VAL="localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,103.32.0.0/16"
REVISION=""
INCLUDE_FILES=""
EXCLUDE_FILES=""
RUNTIME=""
KEEP_CONTAINER=false
DRY_RUN=false
QUIET=true
usage() {
  cat <<EOF
Usage: $(basename "$0") -m MODEL_ID [OPTIONS]

Required:
  -m, --model MODEL_ID        Model ID on ModelScope (e.g. Qwen/Qwen3.8-27B, deepseek-ai/DeepSeek-V3)

Options:
  -d, --dir DIR_NAME          Subdirectory name under host models dir (default: model basename, e.g. Qwen3.8-27B)
  -H, --host-dir PATH         Host models storage root directory (default: /bmcp_lvm_fs/cusa/models)
  -p, --proxy URL             HTTP/HTTPS proxy URL (default: http://103.32.249.1:3128, pass "none" to disable)
  --no-proxy LIST             Proxy bypass list (default: localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,103.32.0.0/16)
  -i, --image IMAGE           Container image (default: asllm:2.0.1-temp01-pytorch2.11.0-...)
  -c, --container NAME        Custom container name (default: model-dl-<timestamp>)
  -r, --runtime RUNTIME       Container runtime: nerdctl or docker (default: auto-detect)
  --revision REV              Model branch, tag, or commit revision
  --include PATTERN           Glob pattern to include specific files (e.g. "*.safetensors")
  --exclude PATTERN           Glob pattern to exclude files
  --keep-container            Do not remove container on exit
  -q, --quiet                 Suppress progress bars and verbose logs to save context (default: true)
  -v, --verbose               Show full download progress bars and verbose logs
  --dry-run                   Print commands without executing
  -h, --help                  Show this help message
Examples:
  # Download Qwen3.8-27B
  $(basename "$0") -m Qwen/Qwen3.8-27B

  # Download to specific directory without proxy
  $(basename "$0") -m deepseek-ai/DeepSeek-V3 -d DeepSeek-V3-Base --proxy none

  # Dry-run to preview commands
  $(basename "$0") -m Qwen/Qwen3.8-27B --dry-run
EOF
  exit 1
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model)
      MODEL_ID="$2"
      shift 2
      ;;
    -d|--dir)
      LOCAL_DIR_NAME="$2"
      shift 2
      ;;
    -H|--host-dir)
      HOST_MODELS_DIR="$2"
      shift 2
      ;;
    -p|--proxy)
      HTTP_PROXY_URL="$2"
      HTTPS_PROXY_URL="$2"
      shift 2
      ;;
    --no-proxy)
      NO_PROXY_VAL="$2"
      shift 2
      ;;
    -i|--image)
      CONTAINER_IMAGE="$2"
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
    --revision)
      REVISION="$2"
      shift 2
      ;;
    --include)
      INCLUDE_FILES="$2"
      shift 2
      ;;
    --exclude)
      EXCLUDE_FILES="$2"
      shift 2
      ;;
    --keep-container)
      KEEP_CONTAINER=true
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -v|--verbose)
      QUIET=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      usage
      ;;
  esac
done

if [[ -z "$MODEL_ID" ]]; then
  echo "Error: --model MODEL_ID is required."
  usage
fi

# Determine default target directory name if not specified
if [[ -z "$LOCAL_DIR_NAME" ]]; then
  # Strip organization prefix, e.g. Qwen/Qwen3.8-27B -> Qwen3.8-27B
  LOCAL_DIR_NAME="${MODEL_ID##*/}"
fi

TARGET_HOST_PATH="${HOST_MODELS_DIR}/${LOCAL_DIR_NAME}"
TARGET_CONTAINER_PATH="${CONTAINER_MODELS_DIR}/${LOCAL_DIR_NAME}"

# Detect container runtime
if [[ -z "$RUNTIME" ]]; then
  if command -v nerdctl &>/dev/null; then
    RUNTIME="nerdctl"
  elif command -v docker &>/dev/null; then
    RUNTIME="docker"
  else
    if [[ "$DRY_RUN" == true ]]; then
      RUNTIME="nerdctl"
    else
      echo "Error: Neither nerdctl nor docker found in PATH."
      exit 1
    fi
  fi
fi

# Build proxy arguments for container
PROXY_ARGS=()
if [[ "$HTTP_PROXY_URL" != "none" && -n "$HTTP_PROXY_URL" ]]; then
  PROXY_ARGS+=("-e" "http_proxy=${HTTP_PROXY_URL}")
  PROXY_ARGS+=("-e" "https_proxy=${HTTPS_PROXY_URL}")
  PROXY_ARGS+=("-e" "no_proxy=${NO_PROXY_VAL}")
  PROXY_ARGS+=("-e" "HTTP_PROXY=${HTTP_PROXY_URL}")
  PROXY_ARGS+=("-e" "HTTPS_PROXY=${HTTPS_PROXY_URL}")
  PROXY_ARGS+=("-e" "NO_PROXY=${NO_PROXY_VAL}")
fi

# Cleanup handler
cleanup() {
  local exit_code=$?
  if [[ "$DRY_RUN" != true && "$KEEP_CONTAINER" != true ]]; then
    echo "Cleaning up container '${CONTAINER_NAME}'..."
    $RUNTIME rm -f "$CONTAINER_NAME" &>/dev/null || true
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

echo "============================================================"
echo "ModelScope Downloader via ${RUNTIME}"
echo "Model ID:            ${MODEL_ID}"
echo "Host Storage Path:   ${TARGET_HOST_PATH}"
echo "Container Path:      ${TARGET_CONTAINER_PATH}"
echo "Container Image:     ${CONTAINER_IMAGE}"
echo "Container Name:      ${CONTAINER_NAME}"
if [[ "$HTTP_PROXY_URL" != "none" && -n "$HTTP_PROXY_URL" ]]; then
  echo "Proxy:               ${HTTP_PROXY_URL}"
else
  echo "Proxy:               Direct (disabled)"
fi
echo "Dry Run Mode:        ${DRY_RUN}"
echo "============================================================"

# Build runtime container args
CONTAINER_ENV_ARGS=("${PROXY_ARGS[@]}")
if [[ "$QUIET" == true ]]; then
  CONTAINER_ENV_ARGS+=("-e" "TQDM_DISABLE=1")
  CONTAINER_ENV_ARGS+=("-e" "MODELSCOPE_LOG_LEVEL=ERROR")
  CONTAINER_ENV_ARGS+=("-e" "PYTHONWARNINGS=ignore")
fi

RUN_CMD=(
  "$RUNTIME" "run" "-d"
  "--name" "$CONTAINER_NAME"
  "--network" "host"
  "${CONTAINER_ENV_ARGS[@]}"
  "-v" "${HOST_MODELS_DIR}:${CONTAINER_MODELS_DIR}"
  "$CONTAINER_IMAGE"
  "sleep" "infinity"
)

# Prepare modelscope download command
DOWNLOAD_ARGS=(
  "modelscope" "download"
  "--model" "$MODEL_ID"
  "--local_dir" "$TARGET_CONTAINER_PATH"
)

if [[ -n "$REVISION" ]]; then
  DOWNLOAD_ARGS+=("--revision" "$REVISION")
fi

if [[ -n "$INCLUDE_FILES" ]]; then
  DOWNLOAD_ARGS+=("--include" "$INCLUDE_FILES")
fi

if [[ -n "$EXCLUDE_FILES" ]]; then
  DOWNLOAD_ARGS+=("--exclude" "$EXCLUDE_FILES")
fi

DOWNLOAD_CMD_STR="${DOWNLOAD_ARGS[*]}"

if [[ "$DRY_RUN" == true ]]; then
  echo "=== Dry-Run Step 1: Start Container (Quiet) ==="
  echo "${RUN_CMD[*]}"
  echo ""
  echo "=== Dry-Run Step 2: Install ModelScope CLI (Quiet) ==="
  if [[ "$QUIET" == true ]]; then
    echo "$RUNTIME exec $CONTAINER_NAME pip install -q modelscope"
  else
    echo "$RUNTIME exec $CONTAINER_NAME bash -c \"pip install modelscope 2>&1 | tail -3\""
  fi
  echo ""
  echo "=== Dry-Run Step 3: Download Model Weights (Quiet, TQDM/Log-Suppressed) ==="
  echo "$RUNTIME exec $CONTAINER_NAME $DOWNLOAD_CMD_STR"
  echo ""
  echo "=== Dry-Run Step 4: Verify Host Storage and Disk Usage (Context-Saving) ==="
  if [[ "$QUIET" == true ]]; then
    echo "du -sh ${TARGET_HOST_PATH}/"
    echo "echo \"Total files: \$(ls -1 ${TARGET_HOST_PATH}/ | wc -l)\""
  else
    echo "ls -la ${TARGET_HOST_PATH}/"
    echo "du -sh ${TARGET_HOST_PATH}/"
  fi
  echo ""
  echo "=== Dry-Run Step 5: Clean Up Container ==="
  echo "$RUNTIME rm -f $CONTAINER_NAME >/dev/null 2>&1"
  exit 0
fi

# Step 1: Ensure host directory exists
mkdir -p "$HOST_MODELS_DIR"

# Clean up any stale container with same name
$RUNTIME rm -f "$CONTAINER_NAME" &>/dev/null || true

# Launch container
echo ""
echo ">>> [1/4] Starting downloader container..."
if [[ "$QUIET" == true ]]; then
  "${RUN_CMD[@]}" >/dev/null
else
  "${RUN_CMD[@]}"
fi

# Step 2: Ensure modelscope is installed inside container
echo ""
echo ">>> [2/4] Ensuring modelscope CLI is installed..."
if [[ "$QUIET" == true ]]; then
  $RUNTIME exec "$CONTAINER_NAME" pip install -q modelscope
else
  $RUNTIME exec "$CONTAINER_NAME" bash -c "pip install modelscope 2>&1 | tail -5"
fi

# Step 3: Execute model download
echo ""
echo ">>> [3/4] Downloading model '${MODEL_ID}' to '${TARGET_CONTAINER_PATH}'..."
$RUNTIME exec "$CONTAINER_NAME" "${DOWNLOAD_ARGS[@]}"

# Step 4: Verification
echo ""
echo ">>> [4/4] Verifying downloaded files on host storage..."
if [[ -d "$TARGET_HOST_PATH" ]]; then
  echo "Total disk usage:"
  du -sh "$TARGET_HOST_PATH"
  if [[ "$QUIET" == true ]]; then
    echo "Total files in directory: $(ls -1 "$TARGET_HOST_PATH" 2>/dev/null | wc -l)"
    if [[ -f "$TARGET_HOST_PATH/config.json" ]]; then
      echo "Integrity check: config.json verified."
    fi
  else
    echo "Directory contents (${TARGET_HOST_PATH}):"
    ls -lh "$TARGET_HOST_PATH"
  fi
  echo ""
  echo "Download completed successfully!"
else
  echo "Warning: Target host path '${TARGET_HOST_PATH}' not found or empty."
  exit 1
fi
