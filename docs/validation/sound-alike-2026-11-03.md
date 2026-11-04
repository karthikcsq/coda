# Sound-alike dictionary corrections, November 3, 2026

Until this change, custom words only biased recognition: approved words went to the
recognizer as vocabulary, and nothing was rewritten afterwards. A replay of saved
dictation history showed that the most common remaining errors are recurring
mishearings of product and personal names, such as "Whisperflow" for Wispr Flow,
"lead code" for LeetCode, "Google Me" for Google Meet and "latex" or "later" for
LaTeX. Generic cleanup rules cannot fix these safely.

## Behaviour

- Each custom word has an optional **Heard as** list: up to six comma-separated
  spellings, each up to four words of letters, apostrophes and hyphens. You edit the
  list in the Dictionary word editor, and the Dictionary row shows
  `Heard as lead code, leet code → LeetCode`.
- When the edit-learning flow proposes a word, the misspelling it observed (for
  example "lead code") appears in the editor as a one-click **Add "lead code"** chip.
  Approving a suggestion, from the pop-up or the Dictionary page, still only adds a
  recognition hint. Nothing is replaced until you have saved the variant yourself.
- Replacement runs after transcription and before Light or Smart cleanup. Smart
  cleanup and its fallback both start from the corrected words. **None · raw text**
  stays exact and applies no replacements.
- Matching is exact and case-insensitive on whole words. Phrases may have extra
  spaces or tabs between their words, and straight and curly apostrophes count as
  the same character. Longer variants win over shorter ones. There is no fuzzy
  matching: a near-miss you have not listed stays unchanged. Possessive `'s` is kept
  ("lead code's" → "LeetCode's"). Words inside other words, hyphenated forms and
  plurals are not matched ("misleading code", "lead-code", "lead codes").
- The following text is never rewritten: text in straight or curly double quotes,
  curly single quotes, or straight single quotes; backtick code and fenced code
  blocks; URLs, `www.` hosts and email addresses; paths; and identifier-like tokens
  such as `file.tex`, `snake_case`, `key=value` and `<tag>`. An unclosed quote or
  backtick protects everything to the end of the dictation.
- A case-only variant fixes capitalization ("latex" → "LaTeX"). Text that is already
  spelled correctly is not counted as a change.
- History keeps the recognizer's raw words as **Original dictation**. The record
  detail says how many misheard terms the dictionary corrected. Corrected words are
  not sent to the recognizer as extra hints.
- Only approved words apply. Removing a word also clears its variants, so re-adding
  it starts with none. A variant cannot be another custom word or another word's
  variant, and a new custom word cannot take a spelling that is already a variant.

## Storage and compatibility

Variants are stored in `heardAs` in `Dictionary/words.json`. Words without variants
are written without the key, so the file keeps its previous shape. Older Coda builds
ignore the key. Dictionary files written before this change load unchanged. If a
hand-edited variant is invalid, it is dropped when the file loads instead of making
the whole dictionary unreadable.

## Limits

- An everyday word or phrase as a variant, such as "later" or "Google Me", is
  replaced every time it is dictated. The editor warns when a variant contains only
  dictionary words, but it does not block it. In the saved history, each of "later"
  and "latex" occurs once in 128 dictations. Those counts are too small to show
  whether either one usually means LaTeX.
- Replacement does not look at context. "Can you google me a recipe" becomes "Can you
  Google Meet a recipe" if "google me" is listed.
- Spoken URLs are formatted after replacement. "lead code dot com" becomes
  "LeetCode dot com" and then a lowercase host.
- Variants cannot contain digits or symbols, so the recognizer's numeric output
  ("GPT 4") is not a supported variant.
- Words added by hand have no observed misspelling, so their editor shows no
  suggestion chip.

## Verification

- `./scripts/test.sh`: all suites passed; the opt-in render, model and fixture tests
  were skipped as usual. New coverage:
  - `Tests/CodaCoreTests/SoundAlikeTests.swift` covers phrase and case matching,
    possessives, curly apostrophes, word boundaries, every protected span, the
    approved-only rule source, variant validation, legacy JSON loading, omission of
    the empty key and sanitizing of invalid variants.
  - `Tests/CodaUITests/CustomDictionaryTests.swift` covers persistence across
    reloads, the suggestion approve flow, conflicts, removal clearing variants, and
    the controller: Light and Smart replace, None stays exact, and History keeps the
    raw words.
- `cd scripts/smart-cleanup && python3 -m unittest`: 41 tests OK. The worker is
  unchanged.
- Native renders at the 980×680 minimum width: the Dictionary page with a Heard-as
  row, the word editor with the observed-misspelling chip, and the everyday-word
  warning. The renders were inspected locally, not committed. To regenerate them, run
  `CODA_RENDER_DIR=<dir> ./scripts/test.sh --filter "renderDictionary|renderHeardAs"`.
- `build/Coda.app` was not rebuilt or replaced, and the change has not been tried
  in a live dictation.
