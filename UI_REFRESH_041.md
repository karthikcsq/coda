# Coda 0.4.1 — installed 2026-10-25

Canonical app: `/Users/karth/CodingFiles/Coda/coda/build/Coda.app`.

The installed release includes the Notetaker overview with note selection/right-hand speaker details, Open notes/All notes navigation, refined transcript/summary editor, and320×64 compact dictation overlay. Recording/startup/processing keeps operation controls visible and disables returning to the overview until completion. Insertion, guarded clipboard handling, capture and lifecycle controller code were preserved unchanged.

Verification:49 offline tests passed (41 core plus8 UI/fixture tests), release packaging and strict code-signature verification passed. The separately identified synthetic preview exercised actual notes navigation and idle overlay. Its window measured320×64 and disappeared after clicking dismiss. Live listening/processing images are labeled synthetic and did not use a recorder or model. Final installed app identity was read as0.4.1 at the canonical path; its own Refresh access status control was invoked successfully and reported that this process cannot currently use Accessibility. No permission change was made. Approval must concern this0.4.1 binary rather than the older0.4.0 prompt.

Previous app: `/Users/karth/.Trash/Coda-0.4.0-20261025-130110.app`.
Previous changed source files: `archive/ui-040-to-041-20261025-130110/`.
Production source, tests and build script now match the validated release. The unused temporary preview app was retired to Trash; no additional candidate Coda.app remains in ui-review/build. User history, recordings, settings, model cache and .env were not changed or read for this work.

Safe evidence: `ui-review/evidence/notetaker-overlay-pass/`. Wispr reference screenshots containing personal content remain local outside deliverables. No inspection flag changes were needed in this last pass; earlier temporary flag changes were verified restored. Exact Wispr fonts, active recording animation/timing and detailed note editor remain unverified. Calendar integrations/shared folders/cloud chat visible in Wispr were not represented as implemented Coda features.
