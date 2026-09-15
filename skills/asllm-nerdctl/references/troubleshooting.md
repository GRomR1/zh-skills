# Troubleshooting Guide for asllm-nerdctl

This guide details common failure modes, error messages, and verified resolutions when running LLM inference containers on Alibaba 890P (AliXPU).

---

## 1. "Failed to infer device type"

### Symptoms
Container logs show:
```
RuntimeError: Failed to infer device type from environment
```
or vLLM crashes within the first 5 seconds of launch.

### Root Cause
Missing hardware device flags in the `nerdctl run` command. The containerd runtime does not pass `/dev/alixpu*` by default.

### Fix
Ensure all relevant devices are explicitly mapped with `--device`:
- `--device /dev/alixpu`
- `--device /dev/alixpu_ctl`
- `--device /dev/alixpu_ppu<0..N-1>` for all PPUs used in tensor parallelism.

---

## 2. Multi-Worker Crash: `shm_broadcast` or Broken Pipe

### Symptoms
Worker processes crash during distributed model initialization:
```
RuntimeError: shm_broadcast failed: File exists / No space left on device
```
or silent worker death during tensor parallel sync.

### Root Cause
1. Container was started without `--ipc host`.
2. Shared memory (`/dev/shm`) is too small (default is 64MB if unspecified).

### Fix
Always include:
```bash
--ipc host --shm-size 128g
```
For 70B+ models or long context lengths, increase to `--shm-size 256g`.

---

## 3. Exit Code 1: "unrecognized arguments"

### Symptoms
Container exits immediately with exit code 1.
Logs show:
```
vllm: error: unrecognized arguments: true
```
or:
```
vllm: error: unrecognized arguments: --max-num-betched-tokens
```

### Root Cause
1. **Boolean flags passed with a value**: In argparse, flags like `--no-enable-prefix-caching` and `--enable-chunked-prefill` are boolean store-action flags. Passing `true` or `false` treats `true` as an unknown positional argument.
2. **Typo in parameter name**: e.g. "betched" instead of "batched".

### Fix
- Remove `true` after boolean switches.
- Verify spelling: `--max-num-batched-tokens 16384`.

---

## 4. Exit Code 137: Out of Memory (OOM Killer)

### Symptoms
Container status becomes `Exited (137)`.
Kernel log (`dmesg -T`) reveals:
```
Out of memory: Killed process <vllm worker>
```

### Root Cause
1. `--max-model-len` set too high (e.g. attempting full 262144 context on high parameter models).
2. `--gpu-memory-utilization` set too high (e.g. 0.98 leaving insufficient memory for activation buffers).
3. Insufficient tensor parallel degree (e.g. TP=2 for a model requiring TP=4 or TP=8).

### Fix
1. Lower `--max-model-len` to `24576` or `32768`.
2. Lower `--gpu-memory-utilization` to `0.85` or `0.90`.
3. Increase `--tensor-parallel-size` (e.g. from 2 to 4 or 8) and map corresponding additional PPUs.

---

## 5. Port Conflict / Address Already in Use

### Symptoms
Logs show:
```
ERROR: [Errno 98] address already in use
```

### Root Cause
Because `--network host` is used, the port (e.g. `8000`) binds directly to the host interface. Another container or service is already using that port.

### Fix
1. Inspect listening ports on host:
   ```bash
   ss -tulpn | grep :8000
   ```
2. Change the `--port` argument in the vLLM command (e.g. `--port 8001` or `--port 28000`).
