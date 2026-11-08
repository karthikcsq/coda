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

## Search registration and visible menu identity

Follow-up fixes install Development at `~/Applications/Coda Dev.app`, register
it with Launch Services and import Spotlight metadata. The menu bar uses an
explicit Coda Dev text title because an icon Label's title is hidden by macOS.
The newer main UI and personal audio features have now been merged; all persistent
Development stores use its channel directory. Dev defaults to hold-mode
Shift–Control–Option; the user's existing model assets were copied to its own
model directory without copying transcripts or histories.

`scripts/test.sh` passed all 217 merged-app
tests. Seven release/publishing safety tests passed. Release publishing now
creates versioned GitHub Releases containing the signed ZIP and checksum/source
manifest, refuses mismatched channel/commit/dirty bundles and refuses reusing a
version for another commit. An existing complete release can be reused when
retrying local installation. Automatic in-app update installation is not
implemented; Production's menu links to the release downloads.

## Development reopen recovery

A live sample of the reported spinning Development app showed an idle main run
loop rather than a blocked launch. Computer Use could not find a window in the
already-running process. The old reopen handler always suppressed default scene
reopening and depended on a callback captured from a potentially closed view.

The scene now captures and retains its actual NSWindow, keeps it available after
close, and restores it directly on reopen. Without a captured window the handler
allows SwiftUI's default reopen path. Development is packaged as a normal Dock
app (`LSUIElement=false`); Production retains its existing agent policy. The
installed Dev process accepted a normal quit before rebuild; Production was not
stopped or replaced.

The full test run passed 228 tests (131 core, 92 UI/integration, 5 speaker/tool).
Regression coverage includes repeatedly closing/reopening one retained window
without creating another and permitting fallback when no window is captured.

## Menu-bar command dispatch

Replaced the SwiftUI MenuBarExtra popup with one AppKit NSStatusItem/NSMenu
controller. Each enabled row now has an explicit target/action; actions execute
on the next main-queue turn after menu tracking unwinds. Window opening uses the
retained main window, and setup, recording, correction, cancellation and normal
quit call their existing controllers directly. Recording status is observed and
menu availability is rebuilt on every opening, with busy guards checked again
when commands run. The version/revision row remains intentionally noninteractive.

The full test run passed 230 tests (131 core, 94 UI/integration, 5 speaker/tool).
Native NSMenu regression tests dispatch Open and Setup via performActionForItem,
verify the target/action connection and resulting state, and check busy-state
availability while Open and Quit remain accessible. Production was not replaced.
