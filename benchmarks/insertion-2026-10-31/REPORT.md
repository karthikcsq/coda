# Insertion repair, October 31, 2026

Installed and reopened **Coda 0.4.12 build 11** at the canonical `build/Coda.app` path. The prior installed 0.4.10 build 9 is preserved at `build-staged/Coda-0.4.10-build9-before-insertion.app`. The preexisting 0.4.11 candidate was left intact.

## Findings and changes

The recent failed insertion record reported that the focused control exposed no editable text selection. The installed signed binary already reported Accessibility trusted and automatic insertion enabled. No additional OS permission, certificate, key access policy, or security setting was needed.

The old capture path required an AX selection range, text information, and focus notification support before allowing any delivery. The paste path additionally required a readable value and a computable whole-field replacement. Those requirements reject editors that accept normal paste but expose incomplete Accessibility information.

Automatic delivery now chooses one guarded paste mechanism across apps. Direct AX text setters and the ChatGPT-specific routing exception have been removed. Cursor ranges and content fingerprints are optional checks; when captured, they must remain unchanged. Foreground app, captured window, available focused-field identity, secure input and secure-field ancestry are checked before delivery. Focus notifications are best effort; polling and a final validation continue regardless of notification support. Known non-editor controls are rejected; opaque web/group/scroll containers and editors with missing AX text attributes can use paste. Missing AX evidence necessarily means Coda cannot detect every internal caret/content change in an opaque control.

The keyboard adapter waits up to one second for shortcut modifiers to be released, validates again, then posts one Command-down/V-down/V-up/Command-up sequence through the foreground HID route. Command is always released after the sequence starts. No Enter, app activation, automatic retry, or second delivery mechanism is used. A repeated delivery call on the same captured target is rejected.

Clipboard restoration still uses the existing all-representation snapshot and change-count ownership guard. A newer user copy wins. Cached AX values and clipboard receipts do not prove visible delivery, so history status remains unconfirmed and messages ask the user to check the destination before retrying.

Electron's documented per-process `AXManualAccessibility` attribute is requested before capture so its accessibility tree can become available. Unsupported apps ignore it. Reference: [Electron accessibility documentation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md#within-third-party-software).

## Validation and limits

- The complete offline/native UI suite passed: 56 core tests and 30 executed UI tests; one external insertion test was skipped in the default run. Tests include missing/changed selection evidence, clipboard representation restoration and newer-copy protection, generated key sequence and Command release, cancellation, invalid targets, and existing controller/history regressions. See `tests.log`.
- A separate opt-in native fixture run passed three consecutive deliveries using production insertion classes and checked the fixture's own text model. Repeated calls did not insert additional text. See `coda-insertion-native.log`.
- Live WebKit attempts were interrupted by changes of foreground app, including `com.roblox.RobloxPlayer`. Coda rejected continued insertion when focus changed. One earlier run observed six sentences through a shared fixture result file; this is retained as a failed test, not a compatibility pass. The harness was subsequently corrected to use a normal application/Edit menu, a result file per process, an initial-value check and exact per-cycle checks. One paste into the corrected WebKit fixture produced exactly one sentence before subsequent focus loss. This does not establish a complete WebKit pass or universal app compatibility.
- The fixture also has contenteditable and opaque editor modes for future opt-in runs. Complete live runs in these modes remain unverified.
- The user chose **“Finish the update; I’ll test Claude.”** No synthetic message was inserted or submitted into Claude, and real Claude compatibility is left for that user test. No microphone, transcription, model download or cloud/API request was performed.
- Strict signature verification and Info.plist lint passed. Candidate and installed app retained the existing certificate requirement. The exact installed executable reports Accessibility trusted and automatic insertion enabled. One canonical Coda process was running after normal reopen. All 68 preexisting history JSON files retained their hashes, and Smart / Hold / Control + Option / automatic insertion preferences were unchanged. See `installation.json`.

Secure fields and apps that reject synthetic input remain unsupported. Opaque editors receive app/window/available field checks, with less cursor/content evidence than fully accessible editors. No claim of support for every application is made.
