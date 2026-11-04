# Sound-alike dictionary corrections, November 3–4, 2026

Until this change, custom words only biased recognition: approved words went to the
recognizer as vocabulary, and nothing was rewritten afterwards. A replay of saved
dictation history showed that the most common remaining errors are recurring
mishearings of product and personal names, such as "Whisperflow" for Wispr Flow,
"lead code" for LeetCode, "Google Me" for Google Meet and "latex" or "later" for
LaTeX. Many of these mishearings are also ordinary words: "talk to you later" must
not become "talk to you LaTeX". Each replacement is therefore proposed by exact
matching and then reviewed in context by the local model.

## Behaviour

- Each custom word has an optional **Heard as** list: up to six comma-separated
  spellings, each up to four words of letters, apostrophes and hyphens. You edit the
  list in the Dictionary word editor, and the Dictionary row shows
  `Heard as lead code, leet code → LeetCode`.
- When the edit-learning flow proposes a word, the misspelling it observed (for
  example "lead code") appears in the editor as a one-click **Add "lead code"** chip.
  Approving a suggestion only adds a recognition hint. A variant is never added
  automatically.
- **Propose.** After transcription, every whole-word, case-insensitive match of an
  approved variant becomes a proposal. The text is never changed at this stage.
  - Phrases may have extra spaces or tabs between their words, straight and curly
    apostrophes count as the same character, and longer variants win over shorter
    ones. There is no fuzzy matching.
  - A possessive is kept ("lead code's" → "LeetCode's"). Words inside other words,
    hyphenated forms and plurals are not matched.
  - Matches are never proposed inside straight or curly quotes, backtick code or
    fenced code blocks, URLs, `www.` hosts, email addresses, paths, or
    identifier-like tokens such as `file.tex`, `snake_case` and `key=value`. An
    unclosed quote or backtick protects everything to the end of the dictation.
  - At most six proposals are reviewed per dictation. Any further matches stay as
    recognized.
- **Review.** Each proposal is sent to the Smart cleanup worker as two versions of a
  window of whole words around the match, up to about 160 characters on each side:
  one as heard and one with the custom term. The local model (Qwen3.5 2B) scores how
  likely each version is. The replacement is accepted only if the version with the
  custom term is more likely. This is the standard way speech recognizers rescore
  candidate transcripts, so the model never generates or rewrites any text.
- **Apply.** Only accepted proposals are replaced. Light cleanup then runs again
  from the corrected words, and Smart cleanup starts from them. If there is no
  verdict (the model is missing, still loading, busy or past the 1.3 s timeout, or
  the reply is malformed), nothing is replaced. **None · raw text** never proposes
  anything.
- History keeps the recognizer's raw words as **Original dictation**. The record
  detail says how many misheard terms the dictionary corrected.
- When you have heard-as entries and cleanup is not None, Coda starts loading the
  model as recording begins, so the review is ready when transcription ends.
- Only approved words apply. Removing a word also clears its variants. A variant
  cannot be another custom word or another word's variant.

## Why rescoring rather than a yes/no prompt

Several approaches were measured against the installed model on 28 synthetic cases.
The cases covered nine custom terms, and each term appeared in both a misheard use
and an ordinary use. None of the cases came from dictation history.

| Approach | Correct | Wrong replacements | Missed fixes | Time per proposal |
|---|---|---|---|---|
| Prompt: "is the term meant at [[this spot]]?" | 9/14 (subset) | 1 | 4 | ~0.14 s |
| Prompt: compare the heard and fixed versions, one at a time | 11/28 | 0 | 17 | up to 1.3 s |
| **Score which version is more likely (shipped)** | **27/28** | **0** | **1** | **~0.03 s** |

With scoring, every ordinary use came out at least 5.3 log-probability units in
favour of the heard words. Every misheard use except one came out at least 1.0 in
favour of the custom term. The cut-off is 0. Through the real worker protocol, a
warm review took a median 26 ms and at most 175 ms per round trip. The model was
ready about 2.8 s after a cold start.

## Storage and compatibility

Variants are stored in `heardAs` in `Dictionary/words.json`. Words without variants
are written without the key, so the file keeps its previous shape. Older Coda builds
ignore the key. Dictionary files written before this change load unchanged. If a
hand-edited variant is invalid, it is dropped when the file loads instead of making
the whole dictionary unreadable.

## Limits

- The one miss: "I switched from whisperflow to Coda" was kept as heard. "Wispr Flow"
  is rare text for the model, and "whisperflow" splits into ordinary pieces. Rare
  product names can lose to a plausible-looking mishearing.
- The review needs the Smart cleanup model on this Mac. Without it, heard-as entries
  do nothing (Light mode included).
- A dictation shorter than the model's load time, right after the worker has been
  idle for 5 minutes, ends before the model is ready. Its matches are left as heard.
- The 28 evaluation cases are small and synthetic. In saved history, each of "later"
  and "latex" occurs once in 128 dictations, which is too few to measure accuracy
  on real use.
- Variants cannot contain digits or symbols.
- Words added by hand have no observed misspelling, so their editor shows no
  suggestion chip.

## Verification

- `./scripts/test.sh`: all suites passed twice in a row, with the usual opt-in skips.
  - `Tests/CodaCoreTests/SoundAlikeTests.swift` covers phrase and case matching,
    word boundaries, every protected span, review windows, the per-dictation limit,
    applying only accepted proposals, rejecting a verdict that doesn't line up with
    the proposals, legacy JSON loading and variant validation.
  - `Tests/CodaUITests/CustomDictionaryTests.swift` covers persistence, conflicts and
    removal. Through a fake worker, it shows the model's verdict deciding each
    replacement: "join the google me call" is fixed, "google me a recipe" is kept, and
    quoted text is never sent for review. It also shows that None proposes nothing,
    that no verdict or a malformed verdict changes nothing, and that History keeps the
    raw words.
- `cd scripts/smart-cleanup && python3 -m unittest`: 45 tests OK. New in
  `test_sound_alikes.py`: proposal bounds, the accept-only-if-more-likely rule, the
  time budget, and the no-model and warm requests through the real worker process.
- Real-model end-to-end check through the worker's JSON protocol: 27/28, with no
  unanswered requests.
- Native renders at the 980×680 minimum width: the Dictionary page with a Heard-as
  row and the word editor with and without the observed-misspelling chip. The
  renders were inspected locally, not committed. To regenerate them, run
  `CODA_RENDER_DIR=<dir> ./scripts/test.sh --filter "renderDictionary|renderHeardAs"`.
- Installed on November 4 as `build/Coda.app` 0.4.13 build 23, built from this
  branch after merging `main` (summaries and Smart cleanup refinement); both suites
  passed on the merge. Coda was idle (no recent history or recording writes, no
  worker running), quit normally, and was relaunched. It is signed with the same
  "Coda Local Development" identity and passes strict deep verification.
  `CodaProjectDirectory` was set back to the main checkout so `.env` lookup is
  unchanged. The 128 history records were unchanged after the relaunch. The change
  has not yet been tried in a live dictation.
