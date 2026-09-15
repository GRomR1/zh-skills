# ModelScope Download Troubleshooting Guide

Common issues encountered when downloading models from ModelScope via containerized environments and their solutions.

---

## 1. Network & Proxy Issues

### Connection Timeouts / Connection Refused
**Symptom:**
```text
urllib3.exceptions.MaxRetryError: HTTPSConnectionPool(host='www.modelscope.cn', port=443): Max retries exceeded
```
**Cause:**
In enterprise VPCs or isolated environments (such as Alibaba Cloud BMCP nodes), outbound Internet access requires an HTTP/HTTPS forward proxy.

**Remedy:**
Ensure the container runs with the environment's proxy settings:
```bash
-e http_proxy=http://103.32.249.1:3128 \
-e https_proxy=http://103.32.249.1:3128 \
-e no_proxy=localhost,127.0.0.1,0.0.0.0,10.0.0.0/8,103.32.0.0/16
```
Test connectivity inside the container:
```bash
nerdctl exec <container_name> curl -I https://www.modelscope.cn
```

### SSL Verification Errors
**Symptom:**
```text
SSLError(SSLCertVerificationError(1, '[SSL: CERTIFICATE_VERIFY_FAILED]'))
```
**Remedy:**
Pass `--trusted-host` to pip and disable SSL verification if using a custom intercepting proxy:
```bash
nerdctl exec <container_name> pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org modelscope
```

---

## 2. Disk Space & Storage Errors

### No Space Left on Device (Disk Full)
**Symptom:**
```text
OSError: [Errno 28] No space left on device
```
**Cause:**
Target filesystem `/bmcp_lvm_fs/cusa/models` lacks sufficient space for model weights. Models in BF16 require roughly $2 \times \text{Parameters}$ in gigabytes (e.g. 27B model $\approx$ 54 GB; 72B model $\approx$ 145 GB).

**Remedy:**
1. Check available disk space before starting:
   ```bash
   df -h /bmcp_lvm_fs/cusa/models
   ```
2. Clean up old unused models or temporary `.cache` files:
   ```bash
   ls -lh /bmcp_lvm_fs/cusa/models
   du -sh /bmcp_lvm_fs/cusa/models/*
   ```

---

## 3. Resume & Incomplete Downloads

### Interrupted Download
**Symptom:**
Download interrupted by network glitch, timeout, or container restart.

**Remedy:**
ModelScope CLI inherently supports download resumption. Re-run the exact same command pointing to the same `--local_dir`:
```bash
nerdctl exec <container_name> modelscope download \
  --model <MODEL_ID> \
  --local_dir /models/<DIR_NAME>
```
Existing completed `.safetensors` files will be verified by checksum and skipped, continuing only with missing or partial files.

---

## 4. ModelScope CLI & Pip Issues

### pip install modelscope hangs or fails
**Symptom:**
`pip install` takes several minutes or times out.

**Remedy:**
Use a domestic/internal PyPI mirror inside the container:
```bash
nerdctl exec <container_name> pip install -i https://mirrors.aliyun.com/pypi/simple/ modelscope
```

### Model Not Found on ModelScope
**Symptom:**
```text
modelscope.utils.exception.ModelNotFoundException: Model ... not found!
```
**Cause:**
Incorrect organization or case-sensitivity in the model ID.

**Remedy:**
Verify the exact model ID on [ModelScope](https://www.modelscope.cn/models). Note case-sensitivity:
- Correct: `Qwen/Qwen3.8-27B`
- Correct: `deepseek-ai/DeepSeek-V3`
- Incorrect: `qwen/qwen3.8-27b`

---

## 5. Container Lifecycle & Stale Containers

### Container Name Conflict
**Symptom:**
```text
container with name "hf-dl" already exists
```
**Remedy:**
Force-remove the stale container before launching a new one:
```bash
nerdctl rm -f <container_name> 2>/dev/null || true
```
Or use dynamic container names (`model-dl-$(date +%s)`), which `scripts/download_model.sh` uses by default.
