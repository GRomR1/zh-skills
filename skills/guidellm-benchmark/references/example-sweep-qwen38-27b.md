# Example Sweep Results — Qwen3.8-27B-W8A8 (guidellm_sweep_20260924_223015)

A finished 28-run concurrency sweep used as the skill's worked example: what the
environment looked like, what the shape of good results is, and which
operational incidents actually happened along the way. Numbers are from
`guidellm_sweep_20260924_223015/` (repo root).

## Environment (captured with the measurements)

- **Model**: `metax-tech/Qwen3.8-27B-W8A8` (served as `qwen38-27b`)
- **Serving container**: `vllm-qwen38-27b-w8a8`
- **Image**: `vllm-metax:0.23.0-maca.ai3.8.0.103-torch2.10-py312-ubuntu22.04-amd64`
- **Server args (container CMD)**:
  `vllm serve /models/Qwen3.8-27B-W8A8 --served-model-name qwen38-27b
  --dtype bfloat16 --max-model-len 24576 --gpu-memory-utilization 0.9
  --max-num-seqs 128 --max-num-batched-tokens 16384 --no-enable-prefix-caching
  --enable-chunked-prefill --reasoning-parser qwen3
  --tool-call-parser qwen3_coder --port 8000` (TP=1, mp)
- **Hardware**: 1× MetaX C500, 64 GB, driver 3.9.10, MACA 3.8.1.3
- **Tokenizer**: `huggingface_auto` on `/models/metax-tech/Qwen3.8-27B-W8A8`
  (host `models/` mounted `:ro` into GuideLLM)
- **Matrix**: 4 workloads × 7 stream steps (1, 4, 8, 16, 32, 64, 128) = 28 runs
- **Windows**: quick 180 s · chat 420 s · reasoning 600 s · 8k 600 s
- **Result health**: `errored = 0` across the entire sweep

## Summary by workload

| Workload | Prompt → Output | Window | Peak output tok/s | @ streams | Req/s | TTFT med | TPOT med |
|---|---|---|---|---|---|---|---|
| quick_256_128 | 256 → 128 | 180 s | 705.2 | 128 | 5.37 | 4.2 s | 152.5 ms |
| chat_2k_512 | 2048 → 512 | 420 s | 433.1 | 64 | 0.83 | 7.3 s | 134.1 ms |
| reasoning_4k_2k | 4096 → 2048 | 600 s | 394.7 | 64 | 0.20 | 37.9 s | 108.8 ms |
| 8k_1k | 8192 → 1024 | 600 s | 224.8 | 128 | 0.22 | 250.6 s | 347.3 ms |

## Saturation points (first TTFT > 10 s)

| Workload | Saturates at | Notes |
|---|---|---|
| quick_256_128 | never (≤128) | TTFT stays under 4.3 s at full load |
| chat_2k_512 | streams=128 | 7.3 s → 79 s between 64 and 128 streams |
| reasoning_4k_2k | streams=32 | degrades fast beyond 32 |
| 8k_1k | streams=8 | heavy prefill dominates; only ~11 concurrent 24K-context requests fit in KV |

The 8k_1k workload saturates earliest because 8192-token prompts × 128 streams =
over 1M tokens of in-flight prefill against a ~285K-token KV cache; vLLM
preempts and recomputes (prefix caching was disabled in this run), so latency
compounds.

## Per-run results

| Run | OK | Inc | Rate | TTFT med | TPOT med |
|---|---|---|---|---|---|
| 8k_1k_stream_1 | 6 | 0 | 100% | 2.1 s | 32.0 ms |
| 8k_1k_stream_4 | 56 | 4 | 93% | 8.1 s | 41.7 ms |
| 8k_1k_stream_8 | 86 | 6 | 93% | 10.5 s | 53.2 ms |
| 8k_1k_stream_16 | 113 | 15 | 88% | 12.8 s | 75.0 ms |
| 8k_1k_stream_32 | 130 | 30 | 81% | 16.9 s | 120.3 ms |
| 8k_1k_stream_64 | 130 | 62 | 68% | 139.5 s | 239.7 ms |
| 8k_1k_stream_128 | 132 | 126 | 51% | 250.6 s | 347.3 ms |
| chat_2k_512_stream_1 | 12 | 0 | 100% | 0.56 s | 30.9 ms |
| chat_2k_512_stream_4 | 37 | 3 | 92% | 2.0 s | 36.4 ms |
| chat_2k_512_stream_8 | 65 | 7 | 90% | 4.0 s | 42.9 ms |
| chat_2k_512_stream_16 | 240 | 16 | 94% | 7.6 s | 53.9 ms |
| chat_2k_512_stream_32 | 321 | 31 | 91% | 8.7 s | 78.7 ms |
| chat_2k_512_stream_64 | 356 | 57 | 86% | 7.3 s | 134.1 ms |
| chat_2k_512_stream_128 | 318 | 123 | 72% | 79.2 s | 285.2 ms |
| quick_256_128_stream_1 | 47 | 0 | 100% | 0.14 s | 30.5 ms |
| quick_256_128_stream_4 | 161 | 3 | 98% | 0.36 s | 34.7 ms |
| quick_256_128_stream_8 | 281 | 8 | 97% | 0.65 s | 39.0 ms |
| quick_256_128_stream_16 | 481 | 15 | 97% | 1.2 s | 45.9 ms |
| quick_256_128_stream_32 | 705 | 31 | 96% | 2.2 s | 61.3 ms |
| quick_256_128_stream_64 | 897 | 63 | 93% | 4.5 s | 97.5 ms |
| quick_256_128_stream_128 | 993 | 101 | 91% | 4.2 s | 152.5 ms |
| reasoning_4k_2k_stream_1 | 3 | 0 | 100% | 1.1 s | 30.3 ms |
| reasoning_4k_2k_stream_4 | 33 | 3 | 92% | 4.1 s | 35.1 ms |
| reasoning_4k_2k_stream_8 | 57 | 7 | 89% | 5.2 s | 39.9 ms |
| reasoning_4k_2k_stream_16 | 96 | 16 | 86% | 9.4 s | 48.0 ms |
| reasoning_4k_2k_stream_32 | 129 | 31 | 81% | 12.0 s | 65.9 ms |
| reasoning_4k_2k_stream_64 | 120 | 63 | 66% | 37.9 s | 108.8 ms |
| reasoning_4k_2k_stream_128 | 120 | 127 | 49% | 190.4 s | 172.0 ms |

Columns: `OK` = successful requests, `Inc` = incomplete (in flight at cutoff),
`Rate` = completion `successful/total`. Some stream-1/low runs kept their
original 180 s windows because they already passed the ≥90% completion check
and were skipped when windows were later lengthened.

## Artifacts & telemetry

- [profiles/](../../../../guidellm_sweep_20260924_223015/profiles/) — 28 directories with `benchmarks.{csv,json,html,png}`
- [REPORT.md](../../../../guidellm_sweep_20260924_223015/REPORT.md) — the run's own report
- `mx-smi` CSV: [guidellm_gputelemetry/metrics.csv](../../../../guidellm_gputelemetry/metrics.csv) (1 Hz: memory, utilization, temperature, power)

## Incidents during the sweep (append lessons like these to REPORT.md)

1. **First execution died silently** — the orchestrator was killed when the
   launching shell exited (SIGHUP → process group). Fix: launch with
   `setsid bash ... </dev/null >sweep.log 2>&1 &`.
2. **Truncated measurements** — a uniform 180 s window was too short for heavy
   workloads at high concurrency (most requests still in flight →
   `incomplete` heavy). Fix: per-workload windows (180/420/600 s) + re-run mode
   that skips already-healthy profiles and re-measures the rest.
3. **vLLM server crashed at chat streams=64** — `EngineDeadError`: the worker
   became a zombie (container had no `--init`), RPC timed out, API server shut
   down. Root cause on MetaX: driver `kill queue timeout` +
   `destroy ce ringbuf failed` in `dmesg` (ringbuf-pool exhaustion; recovery
   documented in the repo's `docs/gpu-ringbuf-leak-recovery.md`: `mx-smi
   --flr -y` + driver reload). Fix applied: recreate the container with
   `--init`, then resume the sweep with `SWEEP_RUN_DIR` so the two failed rows
   get re-measured while 26 good ones are kept.