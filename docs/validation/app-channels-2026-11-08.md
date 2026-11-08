# Production and Development channels

Implemented distinct bundle IDs, names, icon colors and channel-based native UI
tokens. Development uses purple canvas/chrome/accent/hero surfaces, explicit
sidebar/overlay labels, a DEV icon badge and a hammer menu-bar symbol. Production
preserves its identifier and existing mint/charcoal appearance. Application data,
preferences and macOS grants are separated by channel. Development's modifier
listener is blocked while Production runs; the suggested custom shortcut differs.

Validation:

- `scripts/test.sh`: 156 tests passed (84 core, 70 UI/integration, 2 speaker).
- `python3 -m unittest discover -s scripts/tests -v`: four tests passed covering
  dirty-source refusal, push failure before quit, busy-app refusal, and bundle
  restoration after installation failure. These mock external actions; no push
  or Production replacement occurred.
- Native SwiftUI renders passed for both channels using
  `CODA_RENDER_DOCS=1 CODA_UI_CHANNEL=development|production
  CODA_RENDER_OUTPUT=/tmp/coda-channel-renders/dev|prod scripts/test.sh
  --filter WorkspaceOverhaulRenderSuite`. Inspected workspace, HUD and DEV icon.
- `bash -n scripts/build-app.sh`, Python compile checks and `git diff --check`
  passed. Signed Development packaging and bundle signature checks passed.

The actual release command has not been exercised against GitHub and the running
Production app. It requires clean main and preserves other ongoing edits. Local
main has newer UI commits diverging from this branch; merge/review those changes
before releasing. The original dictation timing/accuracy still needs live speech
verification. No production data was copied into Development.
