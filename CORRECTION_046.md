# Correct last dictation (046)

Global shortcut (Production default ⌃⌥C; Development ⇧⌃⌥C to avoid intercepting Production, rebind or clear in Settings → Dictation → "Correct last dictation")
marks the most recently inserted dictation wrong and opens a native editor window.
Also available from the menu bar ("Correct Last Dictation…") and per entry in History ("Mark wrong…" / "Edit correction…").

- Target record: newest History entry with outcome `inserted` or `deliveryUnconfirmed` and non-empty text.
- Editor shows what Coda inserted (read-only) and a field prefilled with it (or with an earlier correction).
  ⌘↩ saves, Esc / close button cancels; focus returns to the app you came from.
- Stored as `correctedText`/`correctedAt` on the same `DictationRecord`; `text` and `rawText` are never changed.
  Entering the inserted text again withdraws the correction. Blank input is rejected with an inline notice.
- Learning reuses existing paths: dictionary word suggestions (when "Learn from corrections" is on),
  the training pair's `finalText` (only if a pair was saved for that dictation), and the Smart cleanup
  edit store (Smart dictations with "Learn from my edits" on). Snippet expansions are not learned from.
- No inserted dictation → empty-state window. During listening/processing/pending insertion → beep, no window.
- Copy and "Insert into another app…" use the corrected text.

Verification: `./scripts/test.sh` (130 core + 88 UI tests pass, including MarkedCorrectionTests and
CorrectionEditorTests). Native renders: `CODA_RENDER_DOCS=1 ./scripts/test.sh --filter CorrectionEditorRenderSuite`
→ `docs/images/correction-*.png`. `scripts/build-app.sh` builds and signs `build/Coda.app`; `codesign --verify --deep --strict` passes.
