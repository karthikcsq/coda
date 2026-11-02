# Dictation dictionary and correction learning

**Current delivery location:** `build/Coda.app` (0.4.13 build 15). The versioned
candidate paths below are historical validation references. At the user's
request, stale bundles and duplicate source checkouts were removed after saving
a local Git checkpoint; future builds update the single canonical bundle.

## Follow-up: pop-up, numerals and correction evidence

The Dictionary page now uses a consistent mint accent, compact learning controls,
search, pending counts, readable before/after spellings and animated row updates.
New suggestions appear in a nonactivating floating panel on the dictation display.
Add shows a confirmation; Dismiss suppresses the spelling. Closing or timing out
keeps words for later review. Hover pauses the ten-second timeout; Reduce Motion
disables movement. Batches queue, startup does not replay existing words, and each
spelling is announced at most once per app session. Open dictionary explicitly
opens the main window. Cancellation, a new dictation/insertion and turning learning
off close the notice. Native render snapshots cover normal, long-name and success
states; the panel cannot become the key/main window and accepts first clicks.

Candidate extraction now requires spelling/pronunciation similarity in addition
to a short, anchored, unfamiliar-word edit. Unrelated replacements such as
Postgres → Supabase are rejected. Strong repairs can appear immediately. Ambiguous
pairs require a positive, aligned boolean judgment from the existing local Qwen
cleanup worker; the model cannot introduce words or bypass the evidence gate.
Cold, busy, invalid or timed-out judgments are skipped. Generations and task
cancellation prevent stale judgments from restoring undone corrections.

The existing installed Qwen model was exercised with synthetic before/after
passages. Warm judgments returned in approximately 0.1–0.4 seconds in this small
smoke run. It can reject legitimate repairs, so it is used for ambiguous cases
rather than treating its verdict as ground truth for every edit. No new model
was trained/downloaded and no text was sent to a cloud service. These examples
are prompt-development checks, not an independent accuracy benchmark.

Smart cleanup also has a bounded English notation pass after source-preserving
validation and punctuation. It formats cardinal numbers, decimals, arithmetic,
simple powers, comparison signs, percentages and clear clock times, without
evaluating equations. Examples verified through the worker include
`six times four equals twenty four` → `6 × 4 = 24`,
`meet at three thirty pm` → `Meet at 3:30 PM`, and
`two plus two equals five` → `2 + 2 = 5`.
Literal requests, identifiers, quotes, invalid number runs and ordinary uses of
“times” remain conservative. None and Light retain their existing behavior.

Follow-up validation:

- Full Swift suite: 115 individual tests passed, one external fixture test skipped
  (68 core, 45 executed native UI, two diarizer).
- Python cleanup suite: 41 tests passed, including the real JSON-lines worker
  with missing model assets, number/math preservation and strict verdict parsing.
- The packaged worker's 33-case formatting evaluation retained all expected
  words/number values, including exact notation in six new numeric/math/time
  cases. 32/33 requested shapes passed; an existing punctuation case rendered a
  comma where the evaluation wanted a sentence break. This is not a numeric or
  lexical preservation failure.
- Native UI tests cover queueing, duplicates, launch suppression, undo, approval,
  dismissal, timeout behavior, hover state, storage failure/retry, review routing,
  learning-off behavior, nonactivating panel flags and rendering.
- Asynchronous tests cover typed model judgments and rejection of a verdict
  arriving after undo.

The final combined candidate is `build-staged/Coda-dictionary-smart.app`, build 15.
The earlier dictionary-only (13) and pop-up (14) candidates remain staged separately.
The installed/running Coda has not been replaced or restarted.

Strict signature verification passed before and after exercising the packaged
worker; Info.plist lint passed. The candidate's read-only diagnostic reports
Accessibility trusted and automatic insertion enabled, with the existing signing
identity. Executable SHA-256:
`f8bc3a689d43e2b2c5de4871956c7747c641f45ac85a736cee207f5cd578c233`.

## Delivered behavior

- Dictionary navigation, pending-count badge, search, manual addition, editing,
  approval, dismissal and removal. The native page was rendered and inspected at
  the minimum 980 × 680 workspace size. Synthetic screenshot:
  [Dictionary workspace](../images/dictionary-workspace.png).
- A separate, read-only correction tracker receives the original destination
  before clipboard settling. Insertion cleanup cannot discard its target.
- Learning begins only after the exact pasted passage appears. UTF-16 selection
  offsets support emoji and other non-ASCII field text. Unchanged prefix/suffix
  anchors scope edits to the inserted passage; missing text, focus/field/window
  changes, secure input, cancellation, a new session, sleep/lock and the 60-second
  deadline stop observation. Unobserved paste is abandoned after two seconds.
- Stable small corrections are aligned by words, including split/join phrases.
  Ordinary spelling-dictionary words, capitalization-only edits, punctuation,
  insertion/deletion-only changes, broad rewrites and identifiable URL, email,
  path, numeric and code syntax are excluded. This is a local heuristic, not a
  determination that a word is absent from the speech model.
- Pending evidence is reconciled when a correction is undone. Observations from
  other sessions remain. Dismissed/removed/superseded spellings stay suppressed;
  explicit manual addition restores them.
- Entries and correction pairs persist in the separate owner-only Dictionary
  directory. Whole-field snapshots are ephemeral. Corrupt dictionaries are
  preserved and never overwritten by new edits. Save failures are visible.
- Only approved vocabulary reaches Voz's existing vocabulary-bias API through
  DictationController → AppModel → LocalPipeline, independently of cleanup mode.
  Learning defaults on and can be disabled without clearing approved vocabulary.
  Meeting transcription and persisted dictation originals are unaffected.

## Validation

- Targeted suite passed: seven core tests and six native tests (13 total).
- Full offline suite passed across CodaCoreTests, CodaUITests and CodaWhoTests.
  Swift Testing reports 67 core, 38 UI (including the opt-in insertion test),
  and two diarizer tests. The external insertion test was skipped in this run.
- Tests cover names, multiword corrections, multiple corrections, common-word
  filtering, rewrites, identifiers, Unicode, invalid selection boundaries,
  observed-paste gating, missing/cleared text, deadlines, debounce, undo,
  multiple-session evidence, approval-only hints, persistence, dismissal,
  restoration, editing, duplicate rejection and corrupt-file preservation.
- `git diff --check` passed.
- Release compilation and signed packaging succeeded. Candidate:
  `build-staged/Coda-dictionary.app`, version 0.4.13, build 13.
- Strict signature verification and Info.plist lint passed. The designated
  requirement retains the existing `app.coda.notebook` identifier and signing
  certificate `22571B293DDEED6B20DB834884A208BFDADDEDD7`.
- The candidate's read-only `--insertion-diagnostics` reports Accessibility
  trusted and automatic insertion enabled. No new OS access was requested.
- Executable SHA-256:
  `e16fc34da157bd5229bc37fb997d5b01cc1ce1ee8211994f12ccdd93ed403e47`.

## Limits and delivery

The candidate is staged separately; the running installed Coda was not replaced
or restarted. It contains the workspace's existing meeting changes as well as
this feature. No commits, pushes or pull requests were made.

Actual post-dictation correction capture in third-party apps was not exercised.
The tests drive the production tracking state machine with synthetic snapshots;
they do not establish compatibility with every native, browser or Electron
editor. Missing, stale or inaccessible field values cause learning to be skipped.
Vocabulary hints are supported by the installed Voz/CoreML decoder, but no audio
accuracy benchmark or model retraining was performed. Suggestions need review.
