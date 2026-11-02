# Interactive Smart formatting latency

## Change

The formatter now applies small source-span edits for supported explicit corrections,
enumerated task lists, explicit dictated list/paragraph/punctuation markers, and
already-punctuated text. It slices the original source rather than regenerating all
unaffected tokens. Every changed candidate passes the existing lexical-preservation
validator. Protected text and unsupported/ambiguous cases retain the same model and
unchanged prompt/validator fallback. Unsupported multi-token abandoned names are
excluded from partial name edits: `call John Smith sorry Jane Jones` must not become
`call John Jane Jones`.

The model has a 650 ms interactive generation budget. Partial output never reaches
the app: requests that exceed the budget return exact raw text. The native client
has a 900 ms deadline, reduced from five seconds, and checks monotonic expiry again
when receiving a result so a delayed MainActor timer cannot accept a late result.
Worker startup overlaps recording through the controller's new warm-at-start call.
No model weights, quantization, prompt, clipboard, microphone, permissions or
external service were changed by this optimization.

## Measurements on this Mac

Seven synthetic cases (short correction/layout, approximately 80/200-word repeated
prose with and without corrections, and a longer list), two repeats each:

| Measurement | Original 0.4.8 worker | Optimized worker |
|---|---:|---:|
| Warm request median | 294.19 ms | 0.242 ms |
| Warm request maximum | 1,500.55 ms | 0.808 ms |
| Fresh worker ready | 1.270 s | 1.271 s |

All optimized cases in this deliberately supported fast-path set used source edits
or a no-op. These are worker round-trip measurements, not ASR-to-screen latency or
a general speedup claim. Previously, longer inputs regenerated the whole transcript,
then failed preservation or hit the 256-token cap. The optimized path preserves their
unaffected source directly.

Six additional synthetic inputs required actual model fallback, two repeats each:

| Measurement | Original worker | Optimized worker |
|---|---:|---:|
| Warm request median | 136.51 ms | 142.79 ms |
| Warm request maximum | 1,192.51 ms | 656.74 ms |
| Fresh worker ready | 1.272 s | 1.353 s |

The ten short model outputs exactly matched the original worker. Both longer model
requests returned exact raw text at the new time limit, rather than spending about
1.2 seconds on output that failed validation. Model-only decoding is not faster;
the improvement comes from avoiding regeneration for supported edits and bounding
the wait for other edits. Cold readiness still costs about 1.3 seconds and is best
hidden by warming while the speaker dictates. No ASR, live audio, private input,
clipboard insertion or production-tail latency was measured.

A fixed-instruction prompt-cache prototype did not show a reliable gain on this
small workload and was removed. No transcript cache or cross-request model state
reuse was introduced.

## Preservation checks

Fifteen Python regression tests pass, including per-token omission checks, quoted
and literal formatting syntax, fillers/hedges/repetition/negation, ordinary correction
words, malformed punctuation, partial corrections, Spanish article corrections and
the multi-token-name guard. The existing thirty-case synthetic suite now produces
21 accepted results (18 changed, three unchanged), nine raw fallbacks. All twenty-one
accepted outputs revalidated and matched their expected lexical content; different
capitalization is allowed. The two injected instruction cases were returned byte-for-
byte unchanged via the punctuated no-op path. Acceptance is not semantic perfection
or proprietary Wispr parity; unsupported corrections may remain raw.

The native tests include a slow fake worker whose response must be rejected by the
default interactive deadline while preserving spaces and fillers in raw text. The
stdio round-trip test uses an explicit ten-second fixture deadline because unrelated
offscreen rendering tests intentionally occupy MainActor; that test verifies protocol,
while the new slow-worker test verifies production timeout behavior. Root integration
owns the final Swift suite and installation result.

## Reproduce

Use the installed offline runtime under
`~/Library/Application Support/Coda/SmartCleanup/v1/runtime/bin/python`:

```
python -B -m unittest discover -s scripts/smart-cleanup -p test_validation.py -v
python scripts/smart-cleanup/bench_latency.py --worker benchmarks/smart-speed-2026-10-26/baseline-worker.py --output baseline.json
python scripts/smart-cleanup/bench_latency.py --output optimized.json
python scripts/smart-cleanup/bench_latency.py --worker benchmarks/smart-speed-2026-10-26/baseline-worker.py --model-cases --output model-baseline.json
python scripts/smart-cleanup/bench_latency.py --model-cases --output model-optimized.json
python scripts/smart-cleanup/evaluate.py preservation-results.json
```

`checks.json` records lexical comparisons and the final worker SHA-256. The baseline
worker is retained as compact source evidence; no duplicate model/runtime is retained.
