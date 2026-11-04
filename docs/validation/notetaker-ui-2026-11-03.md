# Notetaker UI redesign — build 20

## What changed

- Library: the duplicate right-hand detail panel is gone (a row click already opens
  the meeting). Each day's meetings share one list surface; rows show time, title,
  a one-line preview, speaker avatars, status tag and transcribed length. The header
  reports only real totals: meeting count, transcribed length, "Stored on this Mac".
- Meeting document: one toolbar (back, export, delete, new recording) replaces the
  back bar, "Meeting notebook" bar and in-body export row. A custom tab bar replaces
  the segmented picker and its stray "View" label.
- Transcript: unboxed, timestamp gutter, per-speaker colour and avatar, repeated
  speaker headers collapsed, overlap shown as a tag instead of "(overlap / uncertain)"
  in the name. Speaker renaming, count and re-transcription live in an "Edit speakers"
  panel with the same warning as before.
- Summary: sections with counts instead of three cards. Citations are buttons that
  switch to the transcript, scroll to the cited segment and highlight it briefly.
- Recording: a dedicated full-canvas live state with timer, source and Stop & save
  (⌘.). The pulse respects Reduce Motion. Recording options use source cards and
  switches; behaviour and copy about permissions and detection are unchanged.
- Shell: the sidebar Help item now aligns with the other rows.

## Fixed during review

Pending and processing states put fixed-height multiline text outside a scroll view,
which raised the window's minimum height (renders came out 1466 pt tall at an 834 pt
frame). That content now scrolls; every state renders within its requested size.

## Checks performed

- Full offline suite passed (2 + 64 + 70 tests reported by the three runners).
- Opt-in docs renders regenerated: `CODA_RENDER_DOCS=1 ./scripts/test.sh --filter WorkspaceOverhaulRenderSuite`.
- A temporary harness (not committed) rendered library, empty library, transcript with
  three speakers, speaker editor, summary, pending, processing, recording and recording
  options at 1350×850 and 980×680; all fit their frames.
- Coda quit normally (no operation in progress) before replacement. Build 20 passed
  `codesign --verify --deep --strict`; designated requirement unchanged
  (`certificate leaf = H"22571b293ddeed6b20db834884a208bfdaddedd7"`).
- Launched via LaunchServices, `--insertion-diagnostics` reported Accessibility trusted
  and automatic insertion enabled.
- All 11,429 files under Application Support/Coda (excluding Models) and the exported
  `app.coda.notebook` preferences hashed identical before and after replacement.
- Executable SHA-256: `9679fce3c5070789e2068a7507fb8dcde22c70c4e1c0cbde47f280416c25ba40`.

## Remaining validation

Preview mode disables operation buttons, so renders show them dimmed. The live window
was relaunched but not visually inspected after installation. No recording, import,
transcription or summary request was run.
