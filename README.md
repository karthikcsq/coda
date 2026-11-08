# Coda

A native Mac dictation companion and meeting notebook. Stay in the conversation; keep a speaker-labeled transcript and clear next steps.

Coda's app code is MIT licensed. Its Voz/Who dependencies are **source-available, not open source**. No models are bundled. See [third-party notices](THIRD_PARTY_NOTICES.md).

Version 0.5.0 adds a guided first-run setup and a new Home workspace, with actual model, microphone and shortcut readiness and an in-app practice dictation that never pastes into another app. Reopen **Setup guide** any time. Existing shortcuts, model consent, data and macOS grants are preserved.

**Make it yours** offers conservative writing styles, app-specific overrides and whole-phrase voice snippets. Styles only change formatting; snippets insert your authored text without executing it. Both apply with Light or Smart cleanup; None remains exact raw text. Snippets match the recognized whole utterance before cleanup, bypass cleanup and correction learning, and keep their original trigger in History. Settings supports an optional OpenAI key stored in macOS Keychain, so a `.env` is no longer required. Meeting search includes transcript text and speaker names. Already installed, consented speech models warm when opening Dictation or starting a session; dictation still transcribes after capture, with no claim of streaming or measured latency improvement.

Version 0.4.10 Smart removes clear speech fillers, normalizes spoken symbols, applies explicit corrections, creates clear lists/numbered steps, and divides long prose into paragraphs. A separately installed Apache-2.0 punctuation classifier adds punctuation to unpunctuated text by inserting marks at original word offsets. Common cleanup avoids text generation; the existing Qwen model loads only for unsupported correction cases. Substantive words remain guarded, None preserves exact text, and originals remain recoverable in History. Meeting transcripts are unchanged. Saved meetings open directly into full-width details. The menu bar provides Open Coda, Start/Stop Meeting and Quit; starting a meeting presents microphone/system-audio choices. See [behavior and measured limits](LOCAL_CLEANUP.md).

Version 0.4.13 adds a speaker count before recording (1–4, including yourself), optional call detection for Google Meet, Zoom, and Teams, and detailed topic-based summary notes. Meeting detection uses existing macOS Accessibility access to read visible call controls and participant counts. It suggests recording; you still start it yourself. Counts are suggestions, since a device can be shared or a participant can be silent. Manual input overrides the suggestion and works with microphone-only audio. If the controls or count are unavailable, enter a count or leave Automatic for audio-based discovery. Other meeting apps can be recorded with manual speaker counts. Detection can be disabled in Settings or recording options.

The chosen count is saved with each recording and used during voice clustering. Saved transcripts also offer a count selector and **Apply & transcribe again**; successful reprocessing replaces the transcript and clears speaker names and the summary. Who still supports at most four prominent voices. A count does not create voices for silent participants. Recordings with too little clear speech for constrained voice clustering ask you to retry Automatic.

Summaries now preserve substantive topics, rationale, examples, progress, open questions and concrete next steps, with the same timestamp evidence validation. Relative deadlines are retained as spoken. Existing summaries stay unchanged until regenerated. Summary requests still send transcript text and speaker labels only, using the configured model.

## Run locally

Requires Apple Silicon, macOS 15+, and Swift 6.2+ with a matching macOS SDK. Full Xcode is recommended; this project also supports the installed macOS 27 Command Line Tools through a stable SwiftUI state-wrapper alias.

```sh
git clone https://github.com/karthikcsq/coda.git
cd coda
./scripts/build-app.sh
open "build/Coda Dev.app"
```

Ordinary builds create **Coda Dev**, with a purple icon/theme and separate data and preferences. Keep the mint Production app running while developing. To publish and install a verified Production update, follow [the release sequence](docs/releasing.md) and run `scripts/release.py` from clean, reviewed `main`.

Open the `.app` bundle rather than `swift run` when recording, so macOS permissions are associated with Coda. The build uses a dedicated local certificate signing identity; this is a development build, not a notarized distribution. On another Mac, set `CODA_SIGNING_IDENTITY` to your own code-signing identity. See `SIGNING.md` for setup and update verification. The app can also be opened as a Swift package in Xcode.

1. Open **Settings & privacy**. Review Desert Ant's license and licensing metadata disclosure, then enable models if you accept. The first transcription downloads and prepares Voz and Who; this can take several minutes. No download happens on launch.
2. Import an audio/video file, or choose **Record**. Microphone recording needs Microphone permission; combined meeting audio also needs Screen & System Audio Recording permission. Use headphones to reduce echo. Recording is visible in the window and menu bar; use Stop & save to finalize.
3. Processing runs after recording/import when model use is enabled. Review the transcript and edit speaker names.
4. For optional summaries, open Settings → Meeting summaries and save your OpenAI API key in macOS Keychain. The summary model defaults to `gpt-4.1-mini`; saving a key or model does not contact OpenAI. The UI never reads back the key. Advanced users can still select a `.env` containing `OPENAI_API_KEY` and optional `OPENAI_MODEL`; it is read fresh when no Keychain key exists. Existing `.env` configuration keeps working. Dictation and local transcription need no API key.
5. Select Summary → **Summarize with OpenAI…**, review the disclosure, then send. Or deliberately enable automatic future summaries in Settings. Missing credentials never prevent local transcription.
6. Export Markdown or plain text from the meeting toolbar.

## Dictate anywhere

Coda 0.3 stays in the menu bar after its window closes. It is idle until you start dictation; it is never an always-recording service. Open **Settings & privacy → Dictation**:

1. Review/accept the model terms yourself, then **Prepare local dictation** to prepare Voz. No Who model or OpenAI key is needed for dictation.
2. Choose **Control + Option** for a modifier-only shortcut, or **Custom shortcut** to use the recorder. Hold mode starts after holding both modifiers alone for 180 ms and stops when either is released. Toggle remains available. **Use ⌃⌥⌘D suggestion** checks enabled macOS conflicts before assigning; the recorder also checks menu conflicts. Other apps' custom shortcuts cannot all be detected. Choose a binding different from Wispr. Fn-only/Caps Lock-only bindings are unsupported.
3. Choose toggle or hold-to-talk. Focus a text field in another app, then use the shortcut; the menu-bar Dictate button and nonactivating overlay are also available. Escape cancels only while Coda is recording/processing. Sessions stop after two minutes. Closing the overlay cancels and discards the current result.
4. For automatic insertion, grant Coda Accessibility access in Settings and start your shortcut with the destination field focused. Coda uses a guarded Command–V across apps, preserving every readable clipboard representation and restoring it only if no newer copy has replaced it. App/window/field changes and secure input stop delivery. Available cursor and text snapshots add checks; editors without those attributes can still receive paste. Coda never presses Return or submits a message. Field contents are not logged, saved, or sent by these checks. Explicit Copy replaces the clipboard by design.
5. Microphone permission is requested only when you start. **Launch at login** is an optional visible setting; it is not enabled by installation.

Dictation uses local Voz, no cloud cleanup or API credits. Temporary audio is deleted after completion/cancellation. Completed text is saved before insertion in a separate local Dictation history at `~/Library/Application Support/Coda/Dictations`, with insertion outcome and any failure reason. Dismissing the overlay does not erase saved text. Cancelled/failed sessions retain a status record without audio. This history is local and not encrypted by Coda. System sleep, display sleep, session deactivation and the macOS screen-lock notification cancel dictation. An in-flight model call may finish internally before cancellation settles; its text is discarded and new capture waits. Meeting recording/processing and dictation are mutually exclusive.

The shortcut component is MIT KeyboardShortcuts 2.4.0, vendored at an exact upstream revision with documented CLT compatibility changes. See `Vendor/KeyboardShortcuts/CODA-PATCH.md`. Coda does not alter Wispr or its preferences. This is a first native dictation implementation, not a claim of feature/accuracy parity.

### Custom words and learning from corrections

Open **Dictionary** in the sidebar to add, edit, search or remove custom words. Approved words are passed to Voz as vocabulary hints for future dictations, including when cleanup is set to None. These are recognition hints, not guaranteed text replacements or model retraining. Meeting transcription is unchanged.

With **Learn from corrections** enabled (the default), Coda watches only the field it just pasted into for up to 60 seconds. It first needs to observe the exact inserted passage. Small word/phrase corrections resembling the original spelling or pronunciation and containing an unfamiliar word can appear under **Possible custom words**, with the original spelling and Add, Edit and Dismiss actions. Add approves a word; Edit lets you adjust its spelling before adding it. A sidebar badge shows pending suggestions. Dismissed, removed and superseded spellings are remembered so they do not keep returning; manually adding a spelling restores it.

New suggestions also appear in a floating pop-up on the dictation display. **Add word** approves the spelling and shows a short confirmation; **Dismiss** suppresses it. The close button or the ten-second timeout leaves all unreviewed words in Dictionary. Hovering pauses dismissal. Batches queue quietly, repeated corrections do not replay a word during the same app session, and launch never replays existing suggestions. **Open dictionary** brings the main window to the review list. The pop-up never takes keyboard focus, uses no system notification permission, and respects Reduce Motion.

An unfamiliar replacement alone is insufficient. Unrelated substitutions, changed quantities, rewrites and common-word edits are filtered before suggestion. Strong spelling/pronunciation repairs can be suggested immediately. Ambiguous pairs require a positive contextual judgment from the existing local Qwen cleanup model, when it is available; no new model is downloaded or trained. Its response is restricted to booleans for the supplied pairs and cannot invent dictionary entries or override an unrelated-pair rejection. If the model is cold, busy, unavailable or uncertain, ambiguous pairs are skipped. Undo, new dictation and cancellation invalidate pending judgments. This favors missed suggestions over noisy ones; text alone cannot establish a speaker's intent with certainty.

### Spoken numbers and math

**Smart** cleanup formats clear English cardinal numbers as digits, including compound numbers and decimals. Arithmetic can use `+`, `−`, `×`, `÷`, `/`, `=`, comparison signs, percentages and simple powers (`x²`, `x³`, `2^5`). Clock context or AM/PM permits time formatting such as `three thirty pm` → `3:30 PM`. Ordinary phrases such as `three times today` keep the word “times.” Quotes, code, identifiers, literal-word requests, malformed numbers, ambiguous digit strings and familiar idioms remain conservative.

Notation is formatted after source-preserving cleanup and validation, without evaluating or fixing equations: `two plus two equals five` remains `2 + 2 = 5`. The None and Light modes retain their existing behavior. Raw dictation stays available in History. This is a bounded English grammar, not general mathematical or LaTeX transcription.

### Spoken URLs

**Smart** cleanup turns explicit URL spelling into a URL: `style.fyi slash style dash md` → `style.fyi/style-md`. Spoken `dot`, `slash`, `dash`/`hyphen`, `underscore`, and clear query/fragment cues work inside recognized URL spans. Path capitalization and surrounding prose are preserved; a standalone formatted URL does not keep an ASR sentence-ending period. This runs locally without the optional cleanup worker. Quotes, code, verbatim requests and ordinary uses of “slash” or “dash” remain unchanged. Originals stay in History; None and Light retain their existing behaviour.

Tracking stops on a change of app, window or field, a new dictation/insertion attempt, cancellation, field clearing, secure input, lost Accessibility access, sleep or screen lock. Whole-field context is held only in memory for this bounded observation and then released. Only suggested/approved words, their correction pairs, dismissal state and opaque observation IDs are stored in `~/Library/Application Support/Coda/Dictionary/words.json`, with owner-only permissions. Surrounding field text is never written or sent to a service by this feature. Turning learning off stops observation and keeps approved vocabulary active.

Learning requires readable Accessibility text and a selection range. Editors with opaque or cached Accessibility values can still receive paste but may produce no suggestions. Case-only changes, punctuation, appended prose, deletions, broad rewrites, everyday words recognized by the Mac's spell checker, and identifiable paths, addresses, numbers or code syntax are excluded. Suggestions are a heuristic and require review; a correction cannot establish whether the speech model knows a word. Entries allow up to 60 characters and four words, including letters, apostrophes and hyphens.

## Privacy and behavior

The current application lives at `build/Coda.app`. Updates replace that single
bundle; local Git checkpoints provide rollback. Rebuild a chosen source revision
with `scripts/build-app.sh` rather than keeping stale app or source copies.

- Local inference: Voz transcribes and Who diarizes the **same finalized audio timeline**. Who supports up to four prominent speakers. Words use greatest temporal overlap; near ties show multiple candidate speakers and silence remains unknown.
- Raw recordings, imported copies, JSON transcripts, speaker names, and summaries live in `~/Library/Application Support/Coda/Meetings`. Models live in the sibling `Models` directory. Files are local, not encrypted by Coda. Protect your account/disk. Original imported files are not deleted when deleting a meeting.
- No audio/transcript upload to Desert Ant is implemented. Its SDK performs its own background licensing metadata reporting; see its license and privacy policy. Do not describe the entire app as zero-network/offline.
- OpenAI requests contain the full transcript and speaker names, never audio; requests use `store: false`. This does not imply zero provider retention. Automatic summaries are **off by default** and require a second informed confirmation. Enabling them affects future processing, including imports.
- `.env` is parsed as data, not sourced as shell. Neither keys nor raw server error bodies are logged or shown. Only the fixed HTTPS OpenAI Responses endpoint is used.
- Summary instructions treat transcript text as untrusted data. Strict JSON output requires evidence segment IDs. Unknown owners and dates are null. Evidence references are validated before saving; semantic correctness still requires human review.
- Recording combines separate system and microphone tracks based on their original timestamps, then AVFoundation normalizes/mixes to M4A. No screen video is saved. System audio includes other app sounds, not just a meeting app.
- Cancellation is cooperative: an SDK inference call may finish its current stage before returning. Cancelled results are not saved or sent to OpenAI. Audio and already-saved transcripts remain available.

## Scope and limits

This is a first local release: post-recording transcription, no bot joining meetings, no live captions, no automatic language detection, no speaker identification across meetings, no cloud sync. Supported Voz languages are displayed in Settings; unsupported speech can produce fluent wrong text. Review diarization and transcript accuracy, especially overlapping speakers. A summary input limit of 180 KB avoids silent truncation; split larger recordings. HTTP 429 and 5xx summary failures retry at most twice; other errors remain actionable and retain the transcript.

## Development and verification

```sh
swift build
./scripts/test.sh
./scripts/build-app.sh
```

Tests use synthetic transcript data, generated silent PCM buffers, and a stub HTTP transport. They never instantiate Voz/Who, capture audio, or make OpenAI calls. See [VALIDATION.md](VALIDATION.md) for the checks actually performed and remaining user validation.

- `Sources/CodaCore`: alignment, persistence, exports, config, summary networking/parsing, and testable native capture/finalization.
- `Sources/Coda`: SwiftUI notebook, app state, and real Voz/Who adapter.
- `Tests/CodaCoreTests`: offline behavior and native audio-writer/mixer regression tests.
- `scripts/build-app.sh`: Development packaging and local signing; `scripts/release.py` publishes and installs Production.

## Contributing

Keep secrets, recordings, transcripts, caches, and model weights out of commits. Run the offline tests and build. Test live recording only with explicit participant/user consent and model use only after license acceptance. Never include real meetings in fixtures or bug reports. Report security problems privately to the repository maintainer; no public issue should contain credentials or transcript content.

## License

Original Coda code is available under the [MIT License](LICENSE). Vendored KeyboardShortcuts code retains its MIT license. The modified Who sources in `Vendor/Who`, the Desert Ant SDK, and Voz/Who models retain the Desert Ant Labs Source-Available License; they are not covered by MIT. Other optional models and runtimes retain their respective licenses. See [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and details.

## References

- [Voz documentation](https://desertant.com/docs/voz/), [Who documentation](https://desertant.com/docs/who/), [SDK source](https://github.com/Desert-Ant-Labs/desert-ant-core)
- [Apple ScreenCaptureKit audio and microphone guidance](https://developer.apple.com/videos/play/wwdc2024/10088/)
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

## If dictation only shows Copy

Check **Settings & privacy → Dictation**: automatic insertion must be enabled and the Accessibility status must say enabled. In **System Settings → Privacy & Security → Accessibility**, enable the Coda app you actually launch (`build/Coda.app`), then quit and reopen it. Updates signed with the same dedicated certificate retained access in the tested update. Replacing or losing that identity may require renewed approval; if macOS retains an obsolete entry, review the current app entry. Coda never grants this permission automatically.

Click inside an editable text field in another app, then start with your configured shortcut. Starting from Coda’s notebook has no external destination. Coda uses normal foreground paste instead of requiring an app-specific Accessibility text setter. It waits for shortcut modifiers to be released, rechecks the target immediately before delivery, and does not retry an uncertain delivery automatically. Check the field before retrying from History.

For a read-only check that exits before app/history/model initialization:

```sh
build/Coda.app/Contents/MacOS/Coda --insertion-diagnostics
```

### Request insertion access inside Coda

Click **Enable automatic insertion…** in the dictation overlay or **Settings & privacy → Dictation**. Coda requests Accessibility access through macOS and opens the Accessibility pane directly. Turn on the Coda toggle yourself, then return to Coda; its status refreshes automatically. Existing dictated text remains available to Copy and is never automatically replayed after permission approval. Start a new dictation with the destination field focused.

There is no permission prompt on launch, ordinary refresh, or each dictation. An explicit button click requests the OS prompt at most once per app session; subsequent clicks reopen the pane. If opening the pane fails, Coda displays the manual path. The Settings deep link is a best-effort macOS route; the trust request uses AXIsProcessTrustedWithOptions. Coda never changes TCC or approves its own access.

## Coda 0.3 workspace and retry

The main window opens to **Dictation**, with searchable saved results, insertion status, Copy and **Insert into another app…**. **Meetings** retains the existing meeting notebook. Only new dictations after upgrading are persisted; older overlay-only results cannot be recovered from history. Save any needed text in the older running app before quitting and reopening the new build.

Retry arms the selected saved text for 30 seconds. Focus the desired field, then press your configured shortcut or the overlay’s **Insert text here** button. This does not start the microphone. Escape cancels the retry. Coda captures a fresh destination. Paste temporarily uses the clipboard, preserves its representations, and leaves any newer user copy untouched. No action presses Return or submits text.

The nonactivating panel uses the target display when available, keeps its position while visible, remembers dragged placement per display during the app session, and clamps when displays change. Its content scrolls inside a stable frame. Menu-bar **Dictation history** opens the workspace; relaunch/reopen uses the single main window.

Insertion validation and its limits are recorded in `benchmarks/insertion-2026-10-31/REPORT.md`. Paste status remains conservative: an Accessibility readback can be cached, so Coda asks you to check the field before retrying. Secure fields and applications that reject synthetic keyboard input remain outside general paste support.
