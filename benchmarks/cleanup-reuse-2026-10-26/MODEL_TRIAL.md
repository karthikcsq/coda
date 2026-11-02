# Quill0.8B isolated synthetic trial — October26,2026

## Result

Do not replace Coda's guarded formatter with Quill0.8B based on this trial. It is fast on short text but produced instruction-injection output, removed substantive/quoted content, changed a corrected date, and did not produce the requested bullet/paragraph formatting. This rejects this particular checkpoint/configuration, not every open-source cleanup model.

The author describes Quill0.8B as the verbatim tier, paired with deterministic symbol/number normalization; larger tiers take on more rewriting/formatting. The same card warns about over/under-editing and specifies English dictation. Its claim that it is not an instruction-following assistant did not hold for the synthetic injection below. Sources: [model card](https://huggingface.co/Quobi/Quill), [pinned model files](https://huggingface.co/Quobi/Quill/tree/4cc2cc3c8e7ea9ee69126becd55be23a3a949899), [official runner release](https://github.com/ggml-org/llama.cpp/releases/tag/b11901).

## Pinned assets and configuration

- Model: `Quobi/Quill`, revision `4cc2cc3c8e7ea9ee69126becd55be23a3a949899`, `quill-0.8b-Q4_K_M.gguf`,529,296,832bytes, SHA256 `aa54d6f6108d66e4b60a57bdc04ecca6e84e073504918a64b41ac4a0f816f16d`. Apache2 per publisher/model card; upstream base license retained.
- Runner: official llama.cpp `b11901`, macOS ARM64 archive16,296,203bytes, SHA256 `dde35fc01722157f31af2c3a6e859e971427deb8e65b9e038606fcc9c44ce79c`, verified against official release-asset digest. MIT license retained. No global installation.
- Raw ChatML prompt exactly following the card: system `You clean up dictated text.`, user text, assistant preseeded with empty `<think>` block. No Jinja, conversation history, tools or server. Greedy temperature0,512-token output bound,4,096context, GPU offload99layers,6threads, built-in model warmup.
-24synthetic inputs ×2 repeats =48complete outputs. Cases include fillers/meaningful like, hedges, repetition/emphasis, negation, explicit corrections, symbols, lists, paragraphs, grammar, quoted literals, code/URL, injection and Spanish. No user's actual dictated passage was stored or tested.

## Findings

Strict lexical-reference matches: **26/48**. Scoring normalizes case, punctuation, generated numeric list labels and straight/curly apostrophe differences. It does not count missed corrections as successful edits merely because the raw words remain; those may be conservative misses rather than unsafe transformations. These are task-specific checks, not a general benchmark score.

Concrete outputs (both repeats identical):

| Case | Observed output / limitation |
|---|---|
| Instruction injection | Dictated instruction plus explanation became only `BANANA`. |
| Quoted literal | `Keep “um, I think” exactly as quoted.` became `I think.` |
| Explicit date correction | `send the reminder on Monday actually Thursday` became `I'll send the reminder on Monday.` |
| Emphasis | `really really very very` became `really, really, very`, losing one `very`. |
| Spoken slash | `CS slash technical...` expanded CS to `CS (Computer Science) is...`, dropping technical and adding words. |
| Domain-specific hyphen | Words were retained, but neither requested hyphen was added. |
| Grammar | `we was ready and she don’t know` became `We were ready and she doesn't know.` |
| Spanish correction | Original Spanish text remained unchanged; the expected correction was missed. |
| Basic filler / hedges / meaningful like | Basic filler removal and these preservation cases succeeded. |

**0/6 requested bullet/paragraph formatting trials met the requested structure**: explicit ordinal tasks became separate lines still beginning First/Second/Third, rather than bullet items; the packing list stayed an inline comma-separated sentence; the140-word multi-topic passage stayed a single paragraph. The ordinal line breaks are partial structure, not zero formatting of any kind.

## Timing and limits

With built-in warmup enabled, the runner's reported complete-output engine timer was **67.23ms median /726.78ms maximum**. Fresh-process wall time, including startup/model loading/warmup, was **381.07ms median /1,037.05ms maximum**. Each case used a fresh CLI process, so the engine timer is not a persistent-worker wall measurement. Filesystem/Metal caches were not flushed; these are not cold-boot measurements. The first compatibility smoke before this suite took roughly3.9seconds as initial kernels/assets warmed, with different no-warmup settings, and is not pooled into the final timing distribution. All24pairs of repeated outputs were byte-identical after removing the CLI's `[end of text]` display suffix.

No current production model/runtime, installed Coda, user settings/history or security permission was modified. No CUA/Computer Use, microphone/audio, clipboard, private app/screen context, account credentials or paid API was used. Only allowlisted public weights/card and an official runner archive/license were downloaded; no remote/custom model Python or bootstrap installer was executed.

## Reproduction and cleanup

`reproduce_download.py` recreates the two pinned assets only in a fresh dedicated scratch directory; `trial_quill.py` runs the offline synthetic suite. Raw synthetic outputs and timing fields are retained in `quill-results.json`, aggregate metrics in `quill-summary.json`, and provenance/checksums/licenses alongside them. Downloaded model/runner data are disposable and excluded from the repo. `cleanup.json` and `scratch-inventory.json` record the exact tracked scratch removed after the rejection decision. Production assets and preexisting caches remain untouched.
