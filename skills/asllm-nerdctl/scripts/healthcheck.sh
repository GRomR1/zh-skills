#!/usr/bin/env bash
#
# healthcheck.sh - Poll the vLLM/SGLang /health endpoint until ready or timeout.
#
# Usage:
#   bash healthcheck.sh [CONTAINER_NAME] [PORT] [TIMEOUT_SECONDS]
#
# Example:
#   bash healthcheck.sh qwen38-vllm 8000 300

set -euo pipefail

CONTAINER="${1:-qwen38-vllm}"
PORT="${2:-8000}"
TIMEOUT="${3:-300}"
INTERVAL=5

echo "Checking health for container '${CONTAINER}' on port ${PORT} (timeout: ${TIMEOUT}s)..."

START_TIME=$(date +%s)

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))

  if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
    echo "ERROR: Health check timed out after ${ELAPSED} seconds."
    echo "Recent logs from ${CONTAINER}:"
    nerdctl logs --tail 30 "${CONTAINER}" 2>/dev/null || true
    exit 1
  fi

  # Check if container is still running
  STATUS=$(nerdctl inspect --format '{{.State.Status}}' "${CONTAINER}" 2>/dev/null || echo "not_found")
  if [ "${STATUS}" != "running" ]; then
    echo "ERROR: Container '${CONTAINER}' is not running (status: ${STATUS})."
    nerdctl logs --tail 30 "${CONTAINER}" 2>/dev/null || true
    exit 2
  fi

  # Poll HTTP /health endpoint
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "SUCCESS: Container '${CONTAINER}' is healthy and ready on port ${PORT} (elapsed: ${ELAPSED}s)."
    exit 0
  fi

  echo "Waiting for health check... (elapsed: ${ELAPSED}s, HTTP status: ${HTTP_CODE})"
  sleep "${INTERVAL}"
done
