# Validation record

Validated on the user's Mac: arm64, macOS 27.0.1 (26A434), Apple Swift 6.4, Command Line Tools at `/Library/Developer/CommandLineTools`. No full Xcode installation was available. No system tools were installed or changed.

## Passed

- Official Desert Ant Swift SDK **4.1.0**, revision `86b9b55fe8c61ec1c27c5b6383f545c6df1d6ceb`, and its Voz and Who products resolved and compiled. `Package.resolved` retains exact dependency revisions.
- Full native app debug and release builds, including ScreenCaptureKit/AVFoundation capture implementation and the real SDK adapter.
- `./scripts/test.sh`: **17 offline tests passed**, covering greatest-overlap alignment, boundaries/silence/ambiguous speakers, invalid timestamps, `.env` quoting/comments/precedence/literal shell text, missing credentials avoiding transport, structured Responses parsing, refusal/incomplete/malformed/evidence errors, bounded retry on 429/5xx, no retry on 401, cancellation stopping retries, persistence round-trip, deletion, Markdown/text exports, and hour timestamps.
- `./scripts/build-app.sh`: produced `build/Coda.app`, a locally ad-hoc signed bundle with microphone/system audio usage descriptions, Coda icon, notices, and the dependency's privacy resource bundle.
- `codesign --verify --deep --strict build/Coda.app` and `plutil -lint build/Coda.app/Contents/Info.plist` passed.
- Real native app launched through Computer Use. Accessibility inspection verified the notebook empty state, recording/import controls, and Settings & privacy. A screenshot verified the settings layout and identified text truncation; the final build replaces that layout with a scrollable sheet. Final native launch was verified again. The Computer Use native pipe closed on the final screenshot refresh, so final-sheet visual reinspection and the full transcript/summary UI walkthrough remain unverified.
- Settings inspection confirmed both model permission and automatic OpenAI summaries were **off**; the Finder-launched app resolved the intended project `.env` path without reading the file.
- Git ignore checks confirmed `.env`, `.env.local`, recording/transcript/model directories, `.build`, and `build` are excluded. Only `.env.example` contains a placeholder. Local Git initialized; no remote, publication, or push performed.

## Toolchain accommodations

The installed macOS 27 SwiftUI interface exposes a State macro whose plugin is absent from Command Line Tools. `ViewState` aliases the stable `SwiftUI.State` property wrapper to avoid that unavailable macro. Swift Testing's plugin is installed but not automatically found by this SwiftPM build path; `scripts/test.sh` locates it via `xcrun`. These are project-local accommodations; the system toolchain was not altered. The linker emits harmless missing optional CLT framework-search-path warnings. Swift 6.4 also warns about weak/strong nested captures; the app compiled successfully.

## Deliberately not run; user setup required

- **Model download/initialization/inference:** no weights downloaded and no model-license acceptance was performed. Review the license and enable model use in Settings, then process a chosen file. Accuracy, first-use download size/speed, Core ML preparation, and inference cancellation latency remain unmeasured.
- **Recording:** no microphone, screen, or system/meeting audio was captured. Permission prompts, hardware behavior, microphone/system synchronization, interrupted capture recovery, and echo/level quality require an explicitly authorized recording test. System capture uses separate encoded tracks and timestamp offsets before composition; this code is build-verified, not end-to-end capture-verified. In a system-capture finalization failure, temporary separate tracks are retained under the Meetings directory for recovery.
- **OpenAI:** no credentials obtained/read/configured, no real requests, and no private transcript processed. The user must add their own `.env` key and explicitly send a chosen transcript or enable informed automatic summaries. Transport and response behavior were tested using mocks; account/model availability and real generation quality remain unverified.
- **Distribution:** this is a local development build, not a Developer ID signed/notarized installer. Review third-party redistribution notices before publishing. No public repository was created.

## Reproduce

```sh
cd ~/CodingFiles/Coda/coda
./scripts/test.sh
./scripts/build-app.sh
open build/Coda.app
```

An optional `--ui-preview` launch argument supplies clearly labeled synthetic transcript/summary data in a new temporary directory. It does not load real history, credentials, or models. It is for a future authorized UI walkthrough, not evidence of working inference. Normal launch always uses the real local notebook and begins empty until the user imports or records.

## Bounded follow-up review

The final source review found and fixed these concrete failure paths:

- A thrown capture-stop error or failed first writer previously prevented the second writer from finalizing. The shared finalizer now always detaches/drains callbacks and attempts both writers before reporting failure; recovery tracks remain on disk. Startup failures use the same finalization path. Audio backpressure/encode failures notify the app instead of silently leaving its recording indicator active.
- A single corrupt history JSON previously disabled all history on restart. Valid meetings now load independently; corrupt files remain untouched and the app shows a warning.
- Delayed model progress callbacks could overwrite a newer operation's status. Progress now carries an operation ID, invalidated on cancellation/completion.
- Consent was enforced by UI flow but not by the summary service itself. The service now denies requests by default unless explicit consent is passed, before credential validation or transport. The app also checks cancellation/consent before reading its runtime configuration.
- The response decoder previously accepted missing nullable keys and unexpected fields despite the strict requested schema. It now validates exact payload/item keys and only accepts message output text before validating evidence IDs.

Seven added offline regressions cover finalizing both writers after stop/writer failures, restart persistence alongside corrupt JSON, default-denied cloud consent, strict nullable/schema rejection, discarded late responses after cancellation, and actual AVAssetWriter/composition behavior with generated silent PCM. The native audio fixture writes stereo and mono tracks with a 250 ms start difference, verifies their preserved origins, and checks the mixed file's expected duration. It uses no audio devices or permissions and removes its temporary files.

The configuration data path was reviewed: the API key is confined to runtime configuration and the Authorization header, not transcript/summary payloads, Codable meeting history, exports, or application logging. Tests additionally check that the synthetic key does not appear in the request body. Model construction/download calls remain behind model consent. The instructions treat transcript text as data, and references/refusal/incomplete responses are checked; semantic summary correctness remains a human-review requirement.

This follow-up adds fixture validation of encoding/mixing, **not** real capture validation. No permissions were enabled, no model weights downloaded, no real `.env` read, no recording performed, and no live API request made.

## Reconnection verification

After the Mac execution connection returned, the previously uncertain command was inspected before any retry. `/tmp/coda-reviewed-tests.log` confirms all **17 tests passed**, and `/tmp/coda-reviewed-build.log` confirms release packaging completed successfully. The 13 source/test/script files exactly match the reviewed copy; no user changes were overwritten. All five review fixes are present, including the final startup cleanup refinement. The delivered executable is newer than the build inputs and has the same Mach-O build UUID as the release product: `9F70F8D2-66A5-3244-8C6A-E02F02374DE7`. Signature verification (`codesign --verify --deep --strict`) and Info.plist validation both passed. No rebuild or test rerun was necessary.

A fresh launch/inspection of the revised app through Computer Use could not be confirmed: its native pipe closed before responding, including after a session reset. This is a computer-use transport failure, not an approval denial; the build itself is verified complete. The earlier native UI launch predates the bounded review changes. No recording, model, credential, or cloud actions were performed during reconnection verification.

## Coda 0.2 dictation verification (2026-10-22)

This section supersedes earlier counts and current-build UI status. Three passes covered implementation, independent bounded review with regressions, and native UI/polish/package validation.

- **27 offline tests pass** (`/tmp/coda-dictation-tests.log`). Ten new tests cover repeated keydown, toggle/hold release, release while permission is pending, Escape while held, inference cancellation blocking rapid restart, stale callbacks/results, missing model/meeting exclusivity, permission recovery, dismiss/sleep key reset, insertion guards, and display-sleep cancellation during inference. Previous synthetic audio encoding/mixing and summary/config/persistence tests still pass.
- Debug and release compiled with Swift 6.4 CLT. KeyboardShortcuts 3.1.0 and unmodified 2.4.0 require unavailable SwiftUI/Xcode preview macros here. The delivered app vendors MIT **2.4.0**, revision `1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27`, with three narrowly documented compatibility/API visibility changes; full license preserved. See `Vendor/KeyboardShortcuts/CODA-PATCH.md`.
- Independent review found/fixed idle Escape registration, unsupported AX observation permitting insertion, reopening the overlay deleting results, and missing lock/display-sleep cancellation. A follow-up source review confirmed all four fixes and found no additional concrete blockers. Earlier fixes preserve the held-key latch and reject stale recorder delegates.
- Automatic insertion uses one scoped Accessibility selected-text write, with original PID/field/selection/focus and secure-input guards. Focus, selection, and value notification registration must all succeed or it falls back to Copy. It does not read/write the clipboard or synthesize keystrokes. Consequently image/file/rich clipboard preservation is architectural; no real clipboard or cross-app AX insertion test was performed. Explicit Copy intentionally replaces clipboard contents.
- `scripts/build-app.sh` produced the ad-hoc signed **0.2.0** `build/Coda.app`, including localization/resource bundles, model notices and full MIT attribution. `codesign --verify --deep --strict` and `plutil -lint` passed. App and release executable share UUID `7825DD38-FCE5-32F0-BD32-A14353BA6214` (signing changes the file hash).
- The packaged app was launched through Computer Use. Its accessibility tree confirmed the new dictation card, unassigned-shortcut label, Open dictation button, and retained meeting notebook/history. A subsequent Settings click had an **uncertain UI outcome** because the native pipe closed before response. A read-only state/screenshot refresh and session-reset reconnect failed with the same transport error. No settings/overlay screenshot or complete visual walkthrough was obtained for 0.2. This was not an approval denial.
- No real microphone capture, dictation inference, global dictation-key event, Accessibility insertion, permission grant, model download/acceptance, login-item enablement, credential read, or live API call was performed in this phase. Hardware capture, actual shortcut delivery across apps, insertion compatibility, lock timing, and visual overlay behavior remain user validation. No Wispr settings were touched.

For use: launch `build/Coda.app`, open Settings & privacy, choose a shortcut (optional checked suggestion Control+Option+Command+D), choose toggle/hold, prepare Voz if needed after personally accepting its terms, and grant Microphone/Accessibility when desired. Login is optional. Dictation never uses OpenAI. Existing meeting summaries use the selected runtime `.env`; its content was preserved and not inspected in this phase.

### Earlier separately approved OpenAI smoke test

After the initial validation record, the user explicitly authorized one tiny synthetic request. The production environment loader and summary service returned HTTP 200 using configured model `gpt-6-luna`, and parsed grounded synthetic decisions/actions with unknown deadlines left null. The one-shot harness disabled retries and guarded against repeat execution. No private meeting was sent. That historical success does not validate dictation or authorize further live calls; none were made during 0.2 work.

## Automatic insertion follow-up (2026-10-23)

User reported every result falling back to Copy. The delivered app's own `--insertion-diagnostics` mode reports **Accessibility trusted: false; Automatic insertion enabled: true**. This is a confirmed blocker for the currently packaged executable, not proof of the old binary's permission state before rebuilding. No Coda process was running at the process inspection. No security permission was changed.

A separate compatibility defect was fixed: requiring all three AX notifications rejected usable text fields when optional selection/value notifications were unsupported. Focus-change observation remains mandatory; missing optional notifications now use a transient SHA-256 content fingerprint plus periodic/final selection and field checks. Raw field text is not retained, logged, persisted, or transmitted. Missing snapshot and insufficient notifications still fail closed. Secure fields, changed focus/selection/content, unsupported writes, and absent permission still prevent insertion. No clipboard fallback or synthetic paste/Return was added.

The result now shows the precise fallback reason. Settings continuously refreshes the app's Accessibility status and explains how to focus a destination before using the shortcut. The diagnostic mode prints only trust and auto-insert booleans and exits before history, shortcut/controller, model, capture, or cloud initialization.

**31 offline tests passed** (`/tmp/coda-insertion-tests.log`), including four new regressions for optional notification combinations, mandatory focus observation, unreadable content, and changed content with an unchanged selection. Release packaging and strict signature verification passed (`/tmp/coda-insertion-release.log`).

End-to-end insertion into a disposable local document remains unverified: the packaged app lacks Accessibility trust and no native Computer Use tool is exposed in this turn. No permission was granted, no real field insertion or clipboard mutation attempted, no microphone recording, `.env` read, model initialization, or API call performed. This is a missing prerequisite/tool availability limitation, not an approval denial. User action: enable the current Coda app in System Settings → Privacy & Security → Accessibility, quit/reopen, then test the shortcut while a disposable text document has focus. Some editors do not support direct AX selected-text writes and will still need Copy.

## In-app Accessibility request flow (2026-10-23)

Added shared **Enable automatic insertion…** UI in settings and the idle/result overlay when trust is absent. The explicit action enables the app preference, calls AXIsProcessTrustedWithOptions with the OS prompt option, and opens the Accessibility System Settings deep link. Only the user can grant the actual OS toggle. The coordinator requests the prompt at most once per process session; repeated explicit clicks may reopen the pane. Passive refresh cannot request or open anything. A failed pane-opening call gives manual navigation instructions.

Trust refreshes on NSApplication.didBecomeActive and every two seconds while permission help is visible. On approval, Coda updates its status, retains existing result text for Copy, and asks for a newly targeted dictation; no stale automatic insertion is attempted. Actions are disabled during dictation/inference. No clipboard access was added.

**35 offline tests passed**, including four injected/mock permission-flow tests for silent refresh, grant/revoke changes, prompt-once/reopen behavior, already-trusted no-op, and Settings-open failure. Tests exercise the same production coordinator without invoking OS permission requests. Logs: `/tmp/coda-accessibility-tests.log`, `/tmp/coda-accessibility-release.log`. Native release packaging, strict signature validation and Info.plist lint passed.

The actual permission prompt/pane navigation and live visual flow were not exercised: native UI tooling is unavailable in this execution turn, and no permission was granted. The user must click the new action and approve the OS toggle. No `.env`, recordings, clipboard, model downloads, or cloud/API calls were involved. Existing histories and settings remain preserved; the auto-insert preference changes only if the user clicks the new action.

## Coda 0.3 comprehensive dictation repair

The initial running process was PID 6822 from `build/Coda.app`. Its package diagnostic reported Accessibility trusted=true and automatic insertion=true. Missing permission was not assumed to explain this report. Independent source review confirmed absent persistent dictation history, pointer-based overlay repositioning on every show, notebook-started sessions lacking an external destination, redundant focus notifications invalidating unchanged fields, and no alternative to AXSelectedText writes.

Delivered changes: separate Dictation/Meetings workspace; atomic per-record local dictation history with insertion outcomes, failure details, explicit Copy and fresh-target retry; save-before-insert; preserved completed text on dismiss/sleep; compact fixed-frame nonactivating panel with target-display selection, per-display dragged-position memory and clamping; single main Window plus reopen handler. New status messages identify whether app focus, field, selection, content, permission, or write support blocked insertion. Plain single-line AXValue fallback requires an original fingerprint, unchanged text/range, writable caret, and UTF-16-safe replacement; no rich-text whole-field replacement, paste events, Return, or clipboard fallback. Retry tasks carry a generation token to prevent stale timeouts.

Independent review caught and verified fixes for retry-timeout races, nil-snapshot fallback, and caret placement. Unicode tests additionally caught a split-surrogate replacement bug, fixed with validated UTF-16 indices. Final review found no further blocking source defects; caret-update failure now reports text inserted with cursor-placement uncertainty and never triggers automatic retry.

Verification:
- **38 core offline tests + 1 native offscreen UI test passed**; the opt-in external insertion test is skipped in ordinary runs. History persistence/update/corrupt-file recovery, display/drag clamping and Unicode replacement are added to prior capture/config/cloud-mock/cancellation regressions. Log: `/tmp/coda-ux-tests.log`.
- **Actual native insertion integration passed** using the production DictationInsertion class from a separate test target and a disposable AppKit text field: three consecutive insertions, exact final value including original prefix, and rejection after clearing the target. Final log: `/tmp/coda-native-insertion-final.log`. No real recording, private content, clipboard changes, permissions or submissions.
- **WebKit not verified:** a local-only HTML input fixture was attempted. It repeatedly lost foreground focus, causing the production safety guard to reject insertion and stop. Final log `/tmp/coda-webkit-insertion.log` is a failed test, not a pass or evidence of browser support. No guard was bypassed. No new permission is required for the already-trusted test runner; a stable focused UI test remains needed.
- Actual SwiftUI WorkspaceView and DictationHUD were rendered offscreen with synthetic data and visually inspected. This caught/fixed sidebar rendering and a wrapped navigation label. Images: `/tmp/coda-dictation-workspace.png`, `/tmp/coda-dictation-overlay.png`. These are native view renders, not a live desktop walkthrough or proof of multi-display runtime behavior. Native Computer Use tools were unavailable in this turn.
- Release version **0.3.0** packaged and ad-hoc signed; strict signature and plist checks passed. The updated package still reports Accessibility trusted=true. The older process PID6822 was left running intentionally; it predates this package. Quit/reopen after preserving any old unsaved overlay text to use0.3. No existing history or `.env` was inspected or overwritten.

Approval-review handling: a proposed production entry-point insertion probe was rejected before execution; it was not installed or retried. The safer separate test-target route was used, without changing production identity or TCC. A multi-file copy was also rejected due to a perceived model/controller overwrite. Read-only path/diff checks showed separate same-name files; subsequent narrow edits were approved. No rejected command was assumed executed, no security bypass used, and no permission remains pending from those actions.

Remaining validation: microphone→Voz→insertion end-to-end, browser/editor compatibility beyond the native fixture, live screen changes/overlay dragging and real close/reopen desktop interaction. Existing tests exercise cancellation/rapid restart/secure-field guards offline, but do not claim live secure-field or lock testing. User settings, models, key, histories, and Wispr were preserved. No new cloud request or model download occurred.


## Coda 0.3.1 flow repair

Overlay is now 360×170 and dismisses four seconds after a completed result; Copy dismisses immediately. Results remain in dictation history. Accessibility guidance identifies the process and app version and does not assume that the system toggle is off. No TCC changes were made.

Browser-style fields exposing a text value/selection but no direct AX setter use a PID-targeted Cmd+V fallback with promised pasteboard data, full representation snapshots, change-count guarded restoration and expected-content verification. No Enter is sent. A paste request without verification is reported as uncertain; check the destination before retrying. Secure fields, changed targets, and insufficient AX information still fall back to saved text.

Private synthetic pasteboard tests verify multi-format restoration and preservation of a newer copy. They do not exercise the general user clipboard. Live shipped-app paste, runtime trust, microphone inference and multi-display behavior still require interactive verification; no desktop automation tool is available in this session. A separately launched diagnostic or test runner does not establish trust of an existing GUI process. Ad-hoc signing remains and does not guarantee permission persistence across rebuilds.


## Staged 0.3.2: ChatGPT false-success repair

Confirmed source defect: direct AX writes previously returned success solely from AXError.success, without checking text/caret, and a writable AX attribute bypassed clipboard delivery entirely. This can explain the reported false success; no real ChatGPT composer was inspected or modified to prove its exact response.

ChatGPT (`com.openai.chat`) and multiline controls now choose guarded paste before mutation. Direct plain-field writes require changed expected text and expected caret, and are described as target-reported results. Paste results remain `deliveryUnconfirmed`, even if AX reports matching text: neither a cached AX value nor a pasteboard receipt proves visible editor state. There is no automatic second delivery attempt after an uncertain result. Text stays in history.

Regression coverage includes accepted-but-unchanged AX values, matching values with stale caret, missing snapshots, ChatGPT/multiline routing, and unconfirmed-history roundtrip. Synthetic clipboard tests use unique private pasteboards only. Actual ChatGPT insertion is not verified.

The replacement is staged under build-staged/Coda.app, not installed or launched. The authorized build/Coda.app remains 0.3.1 with designated hash 4cd8b16fc8f950bea02e7d35bfe04e53da26eea6. The staged build has a new ad-hoc signature and may require user reauthorization if adopted. Do not overwrite the current bundle before explaining that consequence.


## Actual-app validation after Coda-only permission repair (2026-10-24)

The user explicitly approved replacing only Coda's Accessibility entry and completed the macOS authentication sheet. The old entry was confirmed removed; the exact canonical build/Coda.app 0.3.2 was added and enabled. Its own Settings Refresh showed Accessibility enabled (process 97156), not a proxy trust result. Coda was then restarted unchanged for a synthetic history fixture (process 97444).

Actual Coda UI Insert controls delivered the synthetic sentence correctly across three native-field cycles. A local WebKit input reproduced direct-AX delivery failure; it was recorded as unconfirmed. Initial WebKit paste tests were invalid because the disposable app lacked the standard Edit/Paste responder menu. After fixing that fixture, the unchanged actual Coda 0.3.2 successfully pasted into its textarea in three consecutive cycles, verified against exact expected field text. The test used the separately approved in-memory-only clipboard snapshot/restoration; no clipboard content was printed or saved and no message submitted. The fixture was closed afterward. One clearly synthetic history record remains as evidence.

Source-only experimental foreground-chord/web-ancestor routing refinements also passed a separate three-cycle integration test using production classes. They have NOT replaced the canonical binary, been signed as a new Coda app, or been used as evidence of the existing GUI's trust. Current canonical signature remains 6f38eb10f3a83bc6dd33717b4ad94a7540e8dead. Do not rebuild merely to repeat permission repair. Real ChatGPT composer insertion remains outside the approved test scope and unverified.
