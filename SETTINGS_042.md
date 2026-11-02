# Coda 0.4.2 integrated settings — installed

Canonical app: `/Users/karth/CodingFiles/Coda/coda/build/Coda.app`.

All settings entry points use AppModel.openSettings and the main WorkspaceView's single SettingsPanel. The previous ReviewSettingsView/SettingsView/DictationSettings sheet stack was removed. Sidebar, setup buttons, Notetaker gear, menu-bar action and Command-comma converge on the same panel. Section links scroll within it. Closing returns to the workspace; active meeting operations route back to their controls. Commands reopen the main window if closed.

Existing setting keys/bindings remain: shortcut and hold/toggle mode, automatic insertion, model-license consent, optional summary consent, .env path and launch-at-login. No real .env contents, private audio or API calls were used. No user settings were changed for testing. Consent alerts remain explicit for downloads and transcript sharing. System-only actions link to supported macOS settings; no System Settings embedding or TCC change was performed. Setting changes pause during capture startup, recording, meeting processing or dictation processing; dismissing settings does not cancel these operations.

Validation:51 offline tests passed (41 core +10 UI/fixture), release build and strict signature validation passed. Synthetic preview verified repeated settings open/close and Command-comma reopening from zero windows. Final installed0.4.2 verified three open cycles with exactly1 AXWindow and0 AXSheets, working section jumps and successful Refresh access status. This process reports missing Accessibility access after rebuild. Current CDHash: `25bd3741987b9663ba44b0dc28ada86feaee3532`. Existing signing workflow is ad-hoc with a cdhash designated requirement; changed executable identity cannot preserve the previous grant by copying its signature. No signing credentials or security settings were changed. New-build-specific Accessibility authorization is required before claiming automatic insertion works again.

Rollback app: `/Users/karth/.Trash/Coda-0.4.1-20261025-184052.app`.
Preserved previous changed source: `archive/settings-041-to-042-20261025-184052/`.
The tested artifact was moved into place without another rebuild. The temporary settings-preview app was retired to Trash. Canonical source/tests/build script now match0.4.2. Insertion, clipboard and dictation-controller implementation were unchanged.

Safe visual evidence: `ui-review/evidence/integrated-settings/`. Preview permission status is explicitly labeled as belonging to the preview process and does not establish installed-app trust. No new microphone/inference/insertion end-to-end test was performed.
