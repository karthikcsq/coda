# Coda 0.5.0 product upgrade

## Behavior

- Home combines actual readiness, setup entry points, dictation/meeting actions and recent work.
- A resumable four-step native onboarding flow explains local model terms and metadata reporting, prepares speech recognition, configures a shortcut, reviews Accessibility and microphone access, and offers a real practice dictation. No microphone starts by granting access. Existing users keep their consent and shortcuts.
- Practice uses the existing capture/transcription pipeline and saves a record labeled `Coda practice`. It never pastes externally or learns corrections. The shortcut routes to practice only on that step with Coda frontmost; on other onboarding steps it cannot start an unintended recording.
- Make it yours offers conservative surface-formatting styles, explicit per-app overrides and whole-utterance voice snippets. The destination's settings are snapshotted at session start. Snippets match recognition before cleanup, retain authored text exactly and skip correction learning, including reinsertion. None bypasses both personalization and snippets.
- Dictation preferences use atomic owner-only storage. Invalid/future files are preserved, with actionable recovery.
- Optional summary keys can be entered in a secure field and saved to macOS Keychain; the UI never reads back the secret. Saving a key/model does not contact OpenAI. Existing `.env` configuration remains supported, including a validated fallback when Keychain is unavailable. Only explicitly saved model changes affect requests.
- Meeting search matches title, transcript words and speaker names, with all query terms required.
- Installed, consented speech recognition warms on entering Dictation or beginning capture. Concurrent preparation shares a load and progress. Cancellation stops each waiter promptly; new consumers arriving while an abandoned SDK stage unwinds get a fresh load instead of inheriting its cancellation.

## Verification performed

- `./scripts/test.sh`: passed. Reported groups: 5 Who, 78 native/integration, 125 core tests. Default opt-in render/live-insertion tests remain skipped as indicated by the harness.
- `CODA_RENDER_PRODUCT=1 ./scripts/test.sh --filter ProductUpgrade`: passed. Rendered 18 synthetic native views: Home, personalization, dictation, meetings and dictionary at 980×680 and 1350×850; four onboarding steps; settings; snippets; ready/completed practice. Inspected renders and corrected contrast and shortcut copy. Tests and renders did not capture audio, insert clipboard content, initialize speech models or contact an API.
- Added regression coverage for readiness, per-app preference snapshots, raw-mode bypass, snippet matching before cleanup, history compatibility, meeting search, coalesced loading, cancellation of one/all consumers and immediate restart while a cancelled SDK stage is still unwinding.
- Independent Claude review through T3 identified the cancelled-load/retry issue; fixed it directly and added a regression. Also prevented shortcuts from starting ordinary dictation on other onboarding steps.
- `scripts/build-app.sh`: passed, replacing only `build/Coda.app`, version 0.5.0 build 1. Normal quit succeeded through the previous app's termination guard before replacement.
- `codesign --verify --deep --strict build/Coda.app`: passed. Same designated requirement: `app.coda.notebook` and certificate leaf SHA-1 `22571b293ddeed6b20db834884a208bfdaddedd7`.
- LaunchServices-launched diagnostic: Accessibility trusted `true`, automatic insertion enabled `true`. A shell-launched diagnostic reported false because that launch context differs; the actual app launch check was used to assess access.
- Reopened the canonical bundle through LaunchServices. Before/after SHA-256 comparison verified all 179 existing files under Meetings, Dictations, Dictionary and SmartCleanup/edits unchanged, with none missing. No access grants were reset and no private contents were included in fixtures or notes.

## Limits

This is a locally signed development app, not a notarized public distribution. Dictation still transcribes after capture; streaming and an audio comparison against Phonon are future work. No new live microphone/meeting recording or paid summary request was performed in this upgrade. Keychain operations are compiled and reviewed, but were not exercised against a real user API key. Recognition accuracy and warm-start latency were not benchmarked here. Smart cleanup still needs its separately installed runtime/assets; Settings now makes missing assets visible and offers Light cleanup.

Synthetic visual evidence: `docs/images/product-home.png`, `docs/images/product-onboarding.png`. Other render outputs are temporary verification artifacts and are not committed. Rollback is by rebuilding an earlier Git revision with `scripts/build-app.sh`, retaining the same signing identity.
