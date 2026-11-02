# Meeting capture diagnosis — 0.4.5

Read-only observations from installed 0.4.4 on October 26, 2026:
- Actual Coda Settings Refresh: Accessibility enabled.
- Actual Coda microphone status: Microphone access enabled, system default input.
- macOS Screen & System Audio Recording pane: exactly one Coda entry, switch on.
- No recording was initiated, and no permissions or saved meetings were changed.

The prior generic alert discarded every underlying startup error and incorrectly suggested checking both grants regardless of cause. It therefore cannot establish which operation failed. The original error was not retained, so the historical failure cannot be reconstructed from that alert. A switch being on is not proof that ScreenCaptureKit can start successfully.

The new RecordingStartFailure records a safe stage and numeric code. The app now displays this instead of the generic alert. Stages distinguish microphone setup, source discovery, writer setup and stream startup. Known ScreenCaptureKit permission/device/configuration errors receive distinct guidance; arbitrary NSError descriptions/userInfo are never shown. Existing capture setup and finalization behavior are unchanged.

Validation: 51 core and 13 UI/lifecycle tests passed (one opt-in insertion fixture skipped), including four new error-reporting tests. No capture, private audio, model or API tests were run. Logs: /tmp/coda-meeting-diagnostics-tests.log and /tmp/coda-meeting-diagnostics-build.log.

## Local cleanup feasibility

Hardware: Mac17,8, Apple M5 Pro, 24 GiB unified memory. Current local pipeline has Voz speech recognition and Who diarization, but no generative text cleanup. Dictation returns Voz's text directly; meetings preserve timestamped words aligned to speaker turns.

A separate resident cleanup actor after Voz could perform conservative correction/formatting before insertion. A small quantized model is feasible to evaluate on this hardware, but model weights/runtime/terms and actual warm/cold latency remain untested. No downloads or runtime installations were performed. Benchmark short dictations separately from long meetings; do not promise instant cleanup.

Preserve original text plus cleaned text, accept only explicit spoken corrections, constrain names/numbers, treat text as data, and use a bounded timeout with unchanged-text fallback. For meetings, retain the raw speaker/timestamp transcript as the evidence source and expose cleaned prose separately rather than rewriting aligned segments. Deterministic punctuation/whitespace rules can handle simple cases without a model. Any model choice requires license review and approval before downloading weights.

Remaining diagnostic boundary: no live meeting capture reproduction is authorized. A user-started attempt in 0.4.5 will expose the stage/code, or a separately approved short controlled microphone + system-audio capture can exercise the actual path. Neither permission repair nor a recording fix is claimed from these observations.
