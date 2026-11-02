# UI overhaul validation — 2026-11-02

Scope: native presentation across the workspace shell, Dictation/History, Insights,
Dictionary, Notetaker library and meeting detail, Settings, recording options and the
floating dictation HUD. No pipeline, capture, insertion, dictionary-learning,
meeting-detection or cleanup behaviour was changed.

## What changed

- `Sources/Coda/CodaStyle.swift` (new) — one token set (surfaces, ink, mint/caution,
  a four-step radius ramp, type ramp, page insets) plus shared components:
  `CodaPageHeader`, `CodaEyebrow`, `CodaCountBadge`, `CodaSearchField`,
  `CodaEmptyState`, `CodaNotice`, `CodaStatusChip`, `CodaSection`, and the
  `CodaPrimary/Secondary/Quiet/Icon/NavRow/ListRow` control styles.
  `CodaStyle.motion(reduceMotion:)` returns `nil` under Reduce Motion, so every
  animated surface opts out through the same call.
- Sidebar — the "Make Coda yours" card no longer renders inert `Label`s: each step is a
  real control that opens Settings, each shows a done check, and the card disappears once
  the shortcut and the local model are both ready. Nav rows gained hover/pressed states,
  accessibility labels, hints and the `isSelected` trait (identifiers unchanged).
- Dictation page — the hero moved from the teal→olive→brown gradient to the charcoal/mint
  language; the right-hand statistics rail (a duplicate of Insights) is gone, so the
  content column keeps full width at 980pt. History groups by Today/Yesterday/date.
- `RecordCard` — one disclosure control instead of two that toggled the same state; the
  cleanup state is a chip, and the expanded panel holds the original text and actions.
- Insights — honest counts only (saved dictations, words, destinations, a real
  per-destination breakdown, and a count of records that still hold a pre-cleanup
  original), plus an empty state instead of a tile row of zeroes.
- Notetaker — meetings group by day instead of repeating a date eyebrow per row; the
  `Rectangle().padding(.top, -16)` hack is gone; the grey `.borderedProminent` button
  that read as disabled is now the mint primary style; the detail pane leads with
  title, date and an honest transcription-state chip.
- Meeting detail — the Transcript tab's five stacked instruction blocks collapse into one
  "Speakers and re-transcription" group with a single combined warning; the status bar is
  the only place showing progress/cancel while the top bar owns recording state.
- Settings — shared page header, `CodaSection` groups, status chips for Microphone,
  Accessibility and Voz readiness (system audio is honestly marked "Asked when needed",
  since macOS does not expose it in advance), and jump links that scroll without
  animation under Reduce Motion.
- Floating HUD — the dismiss control is a 30pt target matching its neighbour, the level
  meter honours Reduce Motion and is hidden from VoiceOver, and every control has a label.

Preserved: dictionary learning/approval semantics, the nonactivating word pop-up, Smart
numeric/math cleanup, capture and insertion safety, meeting logic, user data, and all
tested public signatures and accessibility identifiers
(`coda.nav.*`, `coda.dictionary.add/page/spelling`, `coda.meetings.back/open.*`,
`coda.meeting.speakerCount`, `coda.recording.source`, `coda.settings.panel/scroll`).

## Verification

- `./scripts/test.sh` — independently rerun after integration: 117 individual Swift tests passed (CodaWhoTests 2,
  CodaUITests 47, CodaCoreTests 68). Skipped: the pre-existing opt-in insertion fixture
  and the three opt-in docs renders.
- `CODA_RENDER_DOCS=1 ./scripts/test.sh --filter WorkspaceOverhaulRenderSuite` —
  3 tests passed, writing 20 PNGs to `docs/images/overhaul-*`.
- `python3 -m unittest discover -s scripts/smart-cleanup -p "test_*.py"` — 41 tests passed.

Root independently inspected the source diff and regenerated the native screenshots.
The render checks now reject views that exceed the requested window bounds. This
caught a Notetaker header overflow at 980pt: the shared header now moves actions
below the title when space is tight. Custom button styles now visibly dim disabled
controls. Speaker-renaming guidance and the Insights automatic-summary description
were corrected to match the existing behaviour. The standalone expanded-card render
allows its natural height; all workspace renders fit both supported window sizes.

`OverlayLifecycleTests.errorDismissalExpiresButOldTimerCannotCloseNewPresentation` keeps
its assertions but waits longer for the observable outcome (5s → 25s). It passes alone in
0.5s; the richer pages make the parallel offscreen renders hold the main actor past the
old wall-clock bound. The docs render suite is opt-in for the same reason — running all
twenty renders in parallel with the timing tests starves them.

## Renders

`docs/images/overhaul-<page>-980x680.png` and `-1350x850.png` for Dictation, History,
Insights, Dictionary and Meetings; `overhaul-empty-dictation|insights-*` for the empty
states; `overhaul-settings-*`; `overhaul-meeting-transcript|summary.png`;
`overhaul-record-card-expanded.png`; `overhaul-dictation-hud.png`.

## Limitations

- Renders are offscreen `NSHostingView` captures of synthetic preview state. Live audio
  and insertion were not exercised during this presentation-only verification.
- Reduce Motion is honoured through the shared token and verified by unit test, not by a
  render with the system setting enabled.
- Permission chips report what the process can actually observe; Screen & System Audio
  has no pre-flight API and is labelled accordingly rather than guessed.

## Canonical app verification

Root built only `build/Coda.app` using `CODA_BUILD_NUMBER=16 ./scripts/build-app.sh`:
version 0.4.13 build 16. Coda was not running before replacement. Strict deep signature
verification passed; the designated requirement still uses the existing certificate
leaf `22571b293ddeed6b20db834884a208bfdaddedd7` and identifier `app.coda.notebook`.
The exact installed executable's read-only insertion diagnostic reported Accessibility
trusted and automatic insertion enabled. All four packaged cleanup worker resources
match source. All 121 checked local data/preferences files were unchanged byte-for-byte.
Only one app bundle remains under `build/`; `build-staged/`, `archive/` and `ui-review/`
remain absent. No push, access-grant change or key-policy change was made.

Executable SHA-256:
`3c37844e5916ddc652fde4cc0b753452dea7bf570cd03e642179089dba234866`.
