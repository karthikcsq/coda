# Coda

A native Mac dictation companion and meeting notebook. Stay in the conversation; keep a speaker-labeled transcript and clear next steps.

Coda's app code is MIT licensed. Its Voz/Who dependencies are **source-available, not open source**. No models are bundled. See [third-party notices](THIRD_PARTY_NOTICES.md).

Version 0.4.10 Smart removes clear speech fillers, normalizes spoken symbols, applies explicit corrections, creates clear lists/numbered steps, and divides long prose into paragraphs. A separately installed Apache-2.0 punctuation classifier adds punctuation to unpunctuated text by inserting marks at original word offsets. Common cleanup avoids text generation; the existing Qwen model loads only for unsupported correction cases. Substantive words remain guarded, None preserves exact text, and originals remain recoverable in History. Meeting transcripts are unchanged. Saved meetings open directly into full-width details. The menu bar provides Open Coda, Start/Stop Meeting and Quit; starting a meeting presents microphone/system-audio choices. See [behavior and measured limits](LOCAL_CLEANUP.md).

## Run locally

Requires Apple Silicon, macOS 15+, and Swift 6.2+ with a matching macOS SDK. Full Xcode is recommended; this project also supports the installed macOS 27 Command Line Tools through a stable SwiftUI state-wrapper alias.

```sh
git clone https://github.com/karthikcsq/coda.git
cd coda
./scripts/build-app.sh
open build/Coda.app
```

Open the `.app` bundle rather than `swift run` when recording, so macOS permissions are associated with Coda. The build uses a dedicated local certificate signing identity; this is a development build, not a notarized distribution. On another Mac, set `CODA_SIGNING_IDENTITY` to your own code-signing identity. See `SIGNING.md` for setup and update verification. The app can also be opened as a Swift package in Xcode.

1. Open **Settings & privacy**. Review Desert Ant's license and licensing metadata disclosure, then enable models if you accept. The first transcription downloads and prepares Voz and Who; this can take several minutes. No download happens on launch.
2. Import an audio/video file, or choose **Record**. Microphone recording needs Microphone permission; combined meeting audio also needs Screen & System Audio Recording permission. Use headphones to reduce echo. Recording is visible in the window and menu bar; use Stop & save to finalize.
3. Processing runs after recording/import when model use is enabled. Review the transcript and edit speaker names.
4. For summaries, create your own `.env` using `.env.example` as a guide. Add `OPENAI_API_KEY` and optionally `OPENAI_MODEL` (default `gpt-4.1-mini`). Coda never prints or stores your key elsewhere. Select the file in Settings if needed. The bundle remembers the build project's location; Finder does not need a shell environment. The file is read fresh for each requested summary.
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

## Privacy and behavior

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
- `scripts/build-app.sh`: native release app packaging and local signing.

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
