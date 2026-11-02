# Coda local cleanup benchmark — 2026-10-26

## Recommendation

**Best prototype candidate: Qwen3.5-2B, locally quantized to 4-bit, with correction-focused few-shot prompting. No tested model qualifies for unattended text replacement.** It passed 11/14 strict short-text checks, with warm complete-output p50 ~137 ms and p95 ~237 ms on this Mac. Its 3 failures are material: executing the injected BANANA instruction, losing the intended Spanish correction, and leaving spoken “Period” words in formatted paragraphs. The safer fallback is the untouched raw transcript, not a smaller generative model.

The smallest tested model was SmolLM2-135M. Its 4-bit artifact is ~79 MB, but it distorted numbers, names, code and intent. Original precision improves some cases (~273 MB), yet still invents a whole email in one formatting test. Do not use it for silent correction. MiniCPM5-1B is fast but drops text and contaminates lists with examples. Bonsai 2's official pack includes vision and is ~1.21 GB; it was neither smaller nor faster than the selected text-only Qwen conversion in this workload, and failed injection and multi-correction cases. Qwen3-1.7B had weaker formatting and injection resistance; Qwen3.5-0.8B sometimes reversed a correction.

## Fair final-prompt comparison

All rows below used the same correction-focused prompt, 14 synthetic cases, greedy nonthinking generation and a 128-token cap. Each warm case ran 3 times, sequentially. These are complete text generation timings, not first-token timings or tokens/sec. Scores require the expected conservative edit and no missing/extra content; normalized whitespace/case is allowed, and the paragraph case must include a paragraph break. See cases.json and summarize.py. They are strict task checks, not a general model quality benchmark.

| Candidate | Disk MB | Warm p50 / p95 ms | Fresh-process first result s | Metal peak GB / process RSS GB | Strict passes /14 |
|---|---:|---:|---:|---:|---:|
| bonsai2-2b-2bit | 1213 | 165 / 250 | 1.45 | 2.26 / 1.61 | 9 |
| minicpm5-1b-4bit | 618 | 75 / 122 | 1.16 | 1.01 / 0.96 | 7 |
| qwen3-06-4bit | 347 | 56 / 109 | 1.06 | 0.70 / 0.73 | 5 |
| qwen3-17-4bit | 980 | 117 / 219 | 1.12 | 1.54 / 1.37 | 8 |
| qwen35-08-4bit | 444 | 65 / 126 | 1.43 | 0.96 / 1.05 | 4 |
| qwen35-2b-4bit | 1079 | 137 / 237 | 1.50 | 1.77 / 1.69 | 11 |
| smol135-4bit | 79 | 48 / 55 | 0.80 | 0.27 / 0.28 | 2 |
| smol135-fp16 | 273 | 52 / 210 | 0.79 | 0.40 / 0.43 | 8 |

## Method and limits

- Hardware: Mac17,8, Apple M5 Pro, 24 GiB RAM. No device serials or credentials collected.
- Seven model checkpoints, 25 model/precision/prompt runs, 1,075 generations total (25 cold observations plus 1,050 warm samples). Base, few-shot, and correction-focused prompts are all retained. The correction prompt was developed after seeing failures on this suite, so the score is optimistic/in-sample, not held-out validation.
- Each run: one fresh-process load and first complete correction; then 14 inputs × 3 repetitions. Warm p95 uses nearest rank over 42 observations. Greedy repeated outputs were deterministic within these runs. The sample is too small for production-tail claims.
- Cold means a fresh Python process, imports, model load/evaluation and first full output. OS filesystem/Metal caches were not flushed; it is NOT a cold-boot or uncached-download measurement. Downloads and quantization are excluded from inference latency. Warm timing includes formatting the prompt, tokenization, generation and device synchronization, excludes result-file writing, and does not share a prompt/KV cache between requests.
- Primary models are locally converted 4-bit/group64 using released mlx-lm, except the official Bonsai ternary pack through released mlx-vlm. No bundled/custom model Python was executed; trust_remote_code=False. Original Smol135 precision and Qwen3.5-2B bfloat16 were additional checks, not the main comparison. Original Qwen2 precision did not resolve the safety failures.
- Memory columns are peak MLX/Metal allocations during generation and maximum process RSS during that run. Unified memory can overlap; **do not sum them**. They exclude other apps and are not full machine peak memory. Disk is actual artifact-directory size, decimal MB. The raw Qwen3.5 checkpoint includes vision; the mlx-lm conversion strips unsupported vision weights and benchmarks text only.
- GPU models ran sequentially. Initial screening overlapped downloads; final correction-prompt runs occurred after downloads finished. No intentional concurrent Voz/Who workload was launched; normal desktop activity was not controlled. Integrated Coda latency, thermal/battery effects, long meetings, voice transcription errors and sustained throughput were not tested.
- Synthetic cases cover explicit corrections, lists/paragraphs, quoted correction words, negation, names, numbers/dates, no-op text, ambiguity, code, one Spanish correction, and transcript prompt injection. Outputs had no tools or execution privileges. Inference ran offline; only public model data/package downloads used network. No clipboard, private audio, real transcript, API key or paid API was used.
- Raw-text fallback was recorded when generation was empty or token-capped. **This is not a semantic safety guarantee**: many uncapped outputs were wrong. A shipping feature needs explicit raw preservation, reversible edits, conservative validation, held-out/adversarial testing and fallback; no benchmark winner was integrated during measurement.

## Reproducibility and provenance

`requirements.lock.txt` pins the isolated Python packages. `manifests/` records exact official model revisions, Apache-2.0 licenses and download sizes. `inventory.json` hashes downloaded/converted data files and records isolated paths/cache policy. `results/` contains every synthetic output and per-sample timing/memory. `summary.json` contains every prompt variant, not only the best one. Model licenses are in `licenses/`.

The scripts use `/tmp/coda-cleanup-benchmark` deliberately. Recreate a fresh scratch directory, create a Python3.13 venv, install the pinned wheel requirements, source environment.sh, and copy the scripts/cases there. Download each manifest's repo at its recorded revision with `download.py REPO REVISION`; convert with `convert.py SLUG`; run `bench.py ARTIFACT_PATH LABEL [lm|vlm]` with BENCH_PROMPT unset, examples, or corrections. Do not point cleanup at an existing unrelated directory. Downloads are data-only allowlisted; no token is used. Results use zero-temperature greedy decoding, not vendors' recommended stochastic defaults; these numbers apply to this deterministic editing configuration.

Official sources are the repository URLs in manifests, including https://huggingface.co/Qwen/Qwen3.5-2B , https://huggingface.co/openbmb/MiniCPM5-1B , https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-mlx-2bit and https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct . Bonsai loaded natively with mlx-vlm 0.7.10, never its bundled runtime scripts. All candidates declared Apache-2.0 at the pinned revision.

## Cleanup / implementation handoff

The user subsequently requested implementing reversible cleanup. After assessing the model failures, Coda 0.4.6 uses native conservative Light cleanup, not generative rewriting. All benchmark-created model weights and the isolated runtime have now been removed: 20,150,122,310 logical bytes / 20,270,616,576 allocated bytes reclaimed. Only about 0.57 MB of scratch scripts/results remains, plus the compact reproducibility folder in the repository. See cleanup.json for the exact inventory. No weights are stored in the repository, and no preexisting caches or installed Coda files were modified by the benchmark. Trash was not emptied.
