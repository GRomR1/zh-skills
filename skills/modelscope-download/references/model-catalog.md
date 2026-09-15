# ModelScope LLM Model Catalog

Reference catalog of common open-source LLM models available on [ModelScope](https://www.modelscope.cn/), including model identifiers, recommended local directory names, and approximate disk footprints.

---

## 1. Qwen Family

Alibaba Cloud's flagship open-weights models. Native first-class support in `asllm`, vLLM, and SGLang.

| Model Name | ModelScope Model ID | Parameters | Precision | Approx. Disk Size | Recommended Local Dir |
|---|---|---|---|---|---|
| **Qwen3.8-27B** | `Qwen/Qwen3.8-27B` | 27B | BF16 | ~54 GB | `Qwen3.8-27B` |
| **Qwen3.8-27B-Instruct** | `Qwen/Qwen3.8-27B-Instruct` | 27B | BF16 | ~54 GB | `Qwen3.8-27B-Instruct` |
| **Qwen2.5-72B-Instruct** | `Qwen/Qwen2.5-72B-Instruct` | 72B | BF16 | ~145 GB | `Qwen2.5-72B-Instruct` |
| **Qwen2.5-32B-Instruct** | `Qwen/Qwen2.5-32B-Instruct` | 32B | BF16 | ~65 GB | `Qwen2.5-32B-Instruct` |
| **Qwen2.5-14B-Instruct** | `Qwen/Qwen2.5-14B-Instruct` | 14B | BF16 | ~29 GB | `Qwen2.5-14B-Instruct` |
| **Qwen2.5-7B-Instruct** | `Qwen/Qwen2.5-7B-Instruct` | 7B | BF16 | ~15 GB | `Qwen2.5-7B-Instruct` |
| **Qwen2.5-Coder-32B-Instruct** | `Qwen/Qwen2.5-Coder-32B-Instruct` | 32B | BF16 | ~65 GB | `Qwen2.5-Coder-32B-Instruct` |

---

## 2. DeepSeek Family

DeepSeek reasoning and general foundation models.

| Model Name | ModelScope Model ID | Parameters | Precision | Approx. Disk Size | Recommended Local Dir |
|---|---|---|---|---|---|
| **DeepSeek-R1-Distill-Qwen-32B** | `deepseek-ai/DeepSeek-R1-Distill-Qwen-32B` | 32B | BF16 | ~65 GB | `DeepSeek-R1-Distill-Qwen-32B` |
| **DeepSeek-R1-Distill-Qwen-14B** | `deepseek-ai/DeepSeek-R1-Distill-Qwen-14B` | 14B | BF16 | ~29 GB | `DeepSeek-R1-Distill-Qwen-14B` |
| **DeepSeek-R1-Distill-Qwen-7B** | `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B` | 7B | BF16 | ~15 GB | `DeepSeek-R1-Distill-Qwen-7B` |
| **DeepSeek-V3** | `deepseek-ai/DeepSeek-V3` | 671B (MoE) | BF16/FP8 | ~680 GB | `DeepSeek-V3` |
| **DeepSeek-R1** | `deepseek-ai/DeepSeek-R1` | 671B (MoE) | BF16/FP8 | ~680 GB | `DeepSeek-R1` |

---

## 3. GLM (Zhipu AI) Family

Bilingual Chinese/English foundation models.

| Model Name | ModelScope Model ID | Parameters | Precision | Approx. Disk Size | Recommended Local Dir |
|---|---|---|---|---|---|
| **GLM-4-9B-Chat** | `ZhipuAI/glm-4-9b-chat` | 9B | BF16 | ~19 GB | `glm-4-9b-chat` |
| **GLM-4-Voice** | `ZhipuAI/glm-4-voice-9b` | 9B | BF16 | ~19 GB | `glm-4-voice-9b` |

---

## 4. Llama 3 Family

Meta's open-weights models available via ModelScope mirrors.

| Model Name | ModelScope Model ID | Parameters | Precision | Approx. Disk Size | Recommended Local Dir |
|---|---|---|---|---|---|
| **Llama-3.1-70B-Instruct** | `LLM-Research/Meta-Llama-3.1-70B-Instruct` | 70B | BF16 | ~140 GB | `Meta-Llama-3.1-70B-Instruct` |
| **Llama-3.1-8B-Instruct** | `LLM-Research/Meta-Llama-3.1-8B-Instruct` | 8B | BF16 | ~16 GB | `Meta-Llama-3.1-8B-Instruct` |

---

## 5. Model Weight Structure Verification

A complete model directory should contain the following core files:

```text
/bmcp_lvm_fs/cusa/models/<model_name>/
├── config.json                     # Architecture configuration
├── configuration.json              # ModelScope configuration (optional)
├── generation_config.json          # Default generation sampling parameters
├── model.safetensors.index.json    # Shard index (for multi-file weights)
├── model-00001-of-0000X.safetensors# Binary weight shards
├── tokenizer.json                  # Fast tokenizer definitions
├── tokenizer_config.json           # Special tokens and chat templates
└── vocab.json / merges.txt         # BPE vocabulary
```

Ensure no `.tmp` or incomplete files remain before launching inference servers.
