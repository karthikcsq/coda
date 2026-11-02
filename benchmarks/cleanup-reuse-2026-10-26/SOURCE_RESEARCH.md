# Open-source dictation cleanup source inspection

Public source inspected October 26, 2026. No app feature code was copied or changed, model run, private context read, or Computer Use interaction performed by this research task.

The practical pattern in the inspected clones is ASR followed by an LLM cleanup pass. Lists and automatic paragraph breaks are model instructions, rather than a hidden deterministic formatting library. This establishes an implementation approach, not measured quality or speed on this Mac.

## VoiceInk

Pinned app commit: `78aa19ddb5c8b2f378ac650184491c1f26c230f7`.

[Actual enhancement rules](https://github.com/Beingpax/VoiceInk/blob/78aa19ddb5c8b2f378ac650184491c1f26c230f7/VoiceInk/Core/Enhancement/AIPrompts.swift) request topic-based paragraphs, at most three sentences/about 40 words, and vertical lists for clear enumerations. Ordered steps use numbering; unordered groups use bullets; ordinary connected mentions remain prose. They also permit grammar/ASR repair, number normalization and removal of accidental repeats, broader than Coda's current preservation requirement. Context sections can use selected text, clipboard and window context, which Coda must omit under this user's restrictions.

[Native MLX inference](https://github.com/Beingpax/VoiceInk/blob/78aa19ddb5c8b2f378ac650184491c1f26c230f7/VoiceInkRefineXPC/VoiceInkRefineInferenceEngine.swift) prepares and warms a persistent model, disables thinking, streams a complete replacement and clears each session. Output allowance scales to twice input-token count, capped at 8,192. There is no equivalent 256-token ceiling in that implementation. This matters for long dictations. It does not prove a particular latency.

[App license](https://github.com/Beingpax/VoiceInk/blob/78aa19ddb5c8b2f378ac650184491c1f26c230f7/LICENSE) is GPLv3. Inspect behavior; do not transplant app code into MIT Coda without evaluating licensing requirements.

The [shipping Refine V1 model](https://huggingface.co/beingpax/VoiceInk-Refine-V1) is a task-tuned Qwen3.5-2B MLX pack, but its [separate weight license](https://huggingface.co/beingpax/VoiceInk-Refine-V1/blob/main/LICENSE.md) restricts it to VoiceInk and forbids other software/open-source use without permission. It is not an appropriate permissively licensed Coda dependency.

## OpenWhispr

Pinned commit: `369be9b0a18532a43857c6c90f1eafafbddc08a2`; [MIT license](https://github.com/OpenWhispr/openwhispr/blob/369be9b0a18532a43857c6c90f1eafafbddc08a2/LICENSE).

The [actual English cleanup prompt](https://github.com/OpenWhispr/openwhispr/blob/369be9b0a18532a43857c6c90f1eafafbddc08a2/src/locales/en/prompts.json) removes contextually meaningless fillers, restores punctuation, applies corrections, and requests topic paragraphs/lists/email layout when useful. It treats transcript commands/questions as data and supports empty filler-only output. It also permits grammar and spelling correction, false-start/repeat removal and contextual ASR repairs beyond Coda's allowed changes.

An unrelated reusable [plain-text suffix](https://github.com/OpenWhispr/openwhispr/blob/369be9b0a18532a43857c6c90f1eafafbddc08a2/src/config/prompts/registry.ts) explicitly prohibits bullet and numbered-list markers and instead requests unmarked separate lines. The inspected normal cleanup assembly (`BaseReasoningService.getSystemPrompt` → `getCleanupSystemPrompt`) does not append this suffix. Keep cleanup separate from agent-formatting surfaces; that suffix would contradict this user's explicit bullet-list requirement if imported. The [output guard](https://github.com/OpenWhispr/openwhispr/blob/369be9b0a18532a43857c6c90f1eafafbddc08a2/src/utils/cleanupOutput.ts) detects doubled whole-transcript output; it is not a general guarantee of word preservation.

## Handy

Pinned commit: `73c095857bc4eadff097f64767c40ad129cc372d`; project MIT licensed.

The [default post-process prompt](https://github.com/cjpais/Handy/blob/73c095857bc4eadff097f64767c40ad129cc372d/src-tauri/src/settings.rs#L775) wraps the ASR text, asks for spelling/case/punctuation fixes, contextual filler removal, spoken-symbol and number conversion, and preserves meaning/order. It has no default topic-paragraph/list specification. The [client](https://github.com/cjpais/Handy/blob/73c095857bc4eadff097f64767c40ad129cc372d/src-tauri/src/llm_client.rs) can use OpenAI-compatible or Anthropic endpoints, structured output, and reasoning-disable parameters. This is a configurable LLM pipeline, not a bundled special-purpose formatter.

## Permissive task-tuned candidate: Quill

[Quobi/Quill](https://huggingface.co/Quobi/Quill) declares Apache-2.0 and releases Qwen3.5 cleanup fine-tunes. Its card characterizes 0.8B as verbatim-only with a deterministic symbol/email/URL/number scaffold, 2B as light tidying and 4B as including light formatting. The smallest model alone therefore should not be assumed to deliver automatic lists and paragraphs. The card requires a specific raw ChatML prompt with an empty thinking block and greedy decoding; it warns against the default Jinja path. English is the intended language. Author claims are not a benchmark; even its example removes meaningful hedging, so Coda's preservation guard remains necessary. Parent/another agent owns actual trials and pinning file hashes.

## Actionable Coda changes suggested by the source comparison

1. Remove the unconditional already-punctuated quick no-op for long, unstructured dictation. Otherwise an ASR transcript with periods never reaches structure formatting.
2. Make filler deletion and spoken-symbol conversion explicit allowed source edits while retaining meaningful hedges/emphasis and quoted/code text.
3. Ask for numbered steps versus bullets only with clear grouping/sequence signals; do not invent a list taxonomy from ambiguous prose.
4. Provide automatic topic/sentence paragraph boundaries without requiring spoken “new paragraph.” A small, constrained structural-label pass or source-token scaffold can add breaks while preserving all substantive tokens.
5. A whole-transcript generative fallback needs an input-scaled output cap and realistic deadline; 256 tokens/650 ms predictably excludes some long passages. Prefer source-index edits or segmented structure decisions for low latency rather than quietly reverting the entire long transcript to unchanged raw text.
6. Retain raw History/None and lexical validation. None of the inspected clone implementations demonstrates a universal no-paraphrase guarantee or proves proprietary Wispr parity.

## Implemented clean-room scaffold

`scripts/smart-cleanup/cleanup_rules.py` is an original standard-library implementation, not copied clone source. `surface(raw)` removes bounded filler spans, converts known label slash pairs, hyphenates domain-specific except the predicative “specific to” construction, normalizes whitespace/capitalization and terminal prose punctuation, and returns empty for filler-only input. Meaningful comparisons/verbs using like, hedges and emphasis remain. `protected(text)` preserves quotes, code/URLs/paths and literal syntax discussions, while permitting normal contractions and labels such as CS/technical.

`layout(text)` renders punctuation-delimited labeled lists, exact-count lists and consecutive action-ordinal sequences (including after an introduction). It retains heading/count words and final conjunctions. It does not turn ordinary first/second prose into lists. For prose longer than 60 words, it groups existing sentences into readable paragraphs at up to three sentences or around 80 words and recognizes a few clear topic transitions. It cannot safely split an unpunctuated long sentence into semantic paragraphs without a punctuation/model stage.

Twelve unit tests passed, including exact lexical/order preservation for list and long-prose layout, meaningful-like counterexamples, quoted/code text, parentheses, empty fillers, slash/path discrimination and contractions. Parent owns worker integration, broader model/validator tests, packaging and installation. No success of live dictation or proprietary Wispr parity is claimed.
