#!/bin/bash
set -euo pipefail
source /tmp/coda-cleanup-benchmark/environment.sh
export BENCH_PROMPT=corrections
PY=/tmp/coda-cleanup-benchmark/venv/bin/python
BASE=/tmp/coda-cleanup-benchmark
while read -r folder label backend; do
 "$PY" "$BASE/bench.py" "$BASE/$folder" "$label-corrections" "$backend" > "$BASE/bench-$label-corrections.log" 2>&1
done <<'MODELS'
quantized/Qwen--Qwen3-0.6B qwen3-06-4bit lm
quantized/Qwen--Qwen3.5-0.8B qwen35-08-4bit lm
quantized/Qwen--Qwen3-1.7B qwen3-17-4bit lm
quantized/openbmb--MiniCPM5-1B minicpm5-1b-4bit lm
models/prism-ml--Ternary-Bonsai-2-2B-mlx-2bit bonsai2-2b-2bit vlm
models/HuggingFaceTB--SmolLM2-135M-Instruct smol135-fp16 lm
quantized/HuggingFaceTB--SmolLM2-135M-Instruct smol135-4bit lm
MODELS
