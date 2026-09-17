# GuideLLM Load Profiles Reference

GuideLLM provides several benchmark profiles for evaluating LLM inference servers. Each profile implements a distinct request scheduling strategy to characterize server behavior under different load conditions.

---

## 1. Synchronous Profile (`synchronous`)

### Purpose
Measures baseline sequential latency without request contention or queuing delay. Requests are dispatched one at a time: the next request is sent only after the previous response completes.

### CLI Syntax
```bash
--profile kind=synchronous
```

### When to Use
- Evaluating raw model generation speed (Time to First Token / TTFT and Inter-Token Latency / ITL).
- Testing single-user latency before applying concurrent load.

---

## 2. Throughput Profile (`throughput`)

### Purpose
Discovers the server's peak generation throughput by saturating parallel execution with multiple concurrent requests.

### CLI Syntax
```bash
--profile kind=throughput,max_concurrency=32,rampup_duration=10
```

### Parameters
- `max_concurrency`: Maximum number of parallel request streams (default or recommended: 16 to 64 depending on GPU capacity).
- `rampup_duration`: Seconds to linearly ramp up concurrency to prevent shock loads.

---

## 3. Concurrent Profile (`concurrent`)

### Purpose
Maintains a fixed number of simultaneous active streams. Whenever a stream's request finishes, a new request is immediately dispatched on that stream.

### CLI Syntax
```bash
# Single concurrency level
--profile kind=concurrent,streams=16,rampup_duration=10

# Multi-strategy concurrency evaluation
--profile '{"kind":"concurrent","streams":[1,2,4,8,16,32]}'
```

### When to Use
- Simulating fixed concurrent active user sessions (e.g. 8, 16, 32 users chatting concurrently).
- Measuring latency degradation as concurrent streams increase.

---

## 4. Constant Rate Profile (`constant` / `async`)

### Purpose
Sends requests at a fixed Poisson-free target rate (requests per second) regardless of server response times. Demonstrates queue buildup when arrival rate exceeds capacity.

### CLI Syntax
```bash
# Single rate
--profile kind=constant,rate=10,rampup_duration=10

# Multi-rate evaluation
--profile '{"kind":"constant","rate":[5,10,20]}'
```

### Parameters
- `rate`: Target requests per second (can be a list for stepped tests).
- `rampup_duration`: Time in seconds to ramp up to the target rate.
- `max_concurrency`: Maximum concurrent in-flight requests cap.

---

## 5. Poisson Profile (`poisson`)

### Purpose
Generates asynchronous request arrival times modeled by a Poisson distribution around target rate(s). This is the standard mathematical model for real-world user traffic where requests arrive independently at random intervals.

### CLI Syntax
```bash
--profile kind=poisson,rate=10 --seed kind=static,value=42
```

### Parameters
- `rate`: Target mean arrival rate (req/s).
- `--seed kind=static,value=<num>`: Ensures reproducible request intervals across runs.
- `max_concurrency`: Guard against runaway queues during temporary server slowdowns.

---

## 6. Sweep Profile (`sweep`)

### Purpose
The default, comprehensive benchmark in GuideLLM. It automatically runs an adaptive sequence:
1. Runs a `synchronous` strategy to establish the single-request baseline rate.
2. Runs a `throughput` strategy to discover peak throughput.
3. Automatically runs interpolated rate strategies between baseline and peak throughput.

### CLI Syntax
```bash
--profile kind=sweep,sweep_size=6,rampup_duration=10
```

### Parameters
- `sweep_size`: Total number of strategies in the sweep (including sync and peak throughput).
- `strategy_type`: Strategy used for interpolation (`constant` or `poisson`, default: `constant`).
- `rampup_duration`: Ramp-up time per strategy step.

---

## Common Constraints

Constraints govern when each strategy stops:

| Constraint | Syntax | Description |
|---|---|---|
| `max_duration` | `--constraint kind=max_duration,seconds=180` | Stop strategy after N elapsed seconds (recommend 180–300s for 8k->1k, 60s for smoke). |
| `max_requests` | `--constraint kind=max_requests,count=500` | Stop strategy after N requests are processed. |
| `over_saturation` | `--constraint kind=over_saturation,min_seconds=30` | Auto-abort if server latency explodes due to saturation. |

---

## Workload Token Sizing (Prompt vs Output)

Selecting realistic prompt and output token lengths is critical for representative benchmarking. The historical toy default of 256/128 tokens severely under-tests prefill attention mechanisms and KV cache allocation:

| Workload Preset | Prompt Tokens | Output Tokens | Rationale |
|---|---|---|---|
| **Standard / RAG (Default)** | **8,192** | **1,024** | Represents production RAG, document analysis, and coding agent prompts. Exercises chunked prefill, TTFT under load, and high KV-cache memory pressure. |
| **Conversational Chat** | **2,048** | **512** | Typical multi-turn user conversation with moderate context history. |
| **Reasoning / Chain-of-Thought** | **4,096** | **2,048** | Models with extended reasoning chains (o1/DeepSeek-R1 style) generating detailed output tokens. |
| **Smoke / Quick Test** | **256** | **128** | Lightweight sanity check for container networking and API connectivity. |

---

## Duration Constraints & Statistical Validity

A common pitfall in LLM load testing is choosing a `--duration` that is too short relative to single-request decode time.

### Mathematical Basis

1. **Decode Time per Request**:
   $$\text{Request Latency} \approx \text{TTFT} + \frac{\text{Output Tokens}}{\text{Decode Throughput per Stream}}$$
   For a 27B model generating 1,024 tokens at 30 tokens/sec:
   $$\text{Request Latency} \approx 1.5\text{s} + \frac{1024}{30} \approx 35.6\text{ seconds}$$

2. **Ramp-up Penalty**:
   GuideLLM applies a 10-second concurrency ramp-up (`rampup_duration=10`) in rate and concurrent profiles.

3. **Sample Count at 60 Seconds**:
   $$\text{Usable Duration} = 60\text{s} - 10\text{s} = 50\text{s}$$
   $$\text{Completed Requests per Stream} = \left\lfloor \frac{50\text{s}}{35.6\text{s}} \right\rfloor = 1$$
   - Sequential (`synchronous`) profile completes exactly **1 request** before timeout ($N=1$).
   - Percentiles (P90, P99), latency jitter, and standard deviation are mathematically unreliable with $N \le 2$.

### Recommendations

- **Smoke Test (`--duration 60` or `--preset quick`)**: Useful solely to verify container image pulling, host network loopback access, memory stability, and report generation.
- **Production Benchmark (`--duration 180` to `300`)**: Standard for 8k $\to$ 1k workloads. Provides 6–10 completed requests per stream, stable KV-cache warmup, and reproducible P50/P90/P99 latency metrics.
- **Fast Iteration Alternative (`-o 256 -d 90`)**: Reducing output tokens to 256 allows requests to finish in ~8–10 seconds, yielding statistically meaningful sample counts in under 2 minutes.
- **Multi-Strategy Sweep Multiplier**: The `sweep` profile runs 6 strategies sequentially. Total time for `sweep` will equal $6 \times \text{duration}$ (e.g. ~18 minutes at 180s, ~30 minutes at 300s).
