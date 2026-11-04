# Smart cleanup refinements from dictation history — build 22

## Method

Every saved dictation with a raw transcript (86 records, all modes) was replayed through
the current Smart worker with the installed punctuation model, before and after these
changes. Saved outputs reflect whichever version was installed at the time, so the replay,
not the history text, is the baseline. Private dictations and replay outputs stayed in a
scratch folder outside the repository; examples below are synthetic.

## Research

- Disfluency research (Shriberg's taxonomy; Switchboard disfluency detection) separates
  filled pauses, repetitions, restarts and corrections. Coda already handled filled pauses
  and cue-word corrections ("actually", "scratch that"), but not plain repetitions.
- Wispr Flow documents Backtrack as removing only clear self-corrections, keeps raw text
  when formatting fails, and avoids inserting em dashes automatically.
- Inverse text normalization treats bare "one" as ambiguous (pronoun versus cardinal) and
  resolves it from context. Style guides spell out one to nine in prose; the user asked
  for numerals whenever possible, so numerals remain the default.

## Changes

1. Bare "one" stays a word unless clearly numeric: math or dimensions, a unit
   ("1 minute", "1%"), a label ("step 1"), part of a larger number, or next to another
   number ("1 or 2", "between 1 and 5"). Fixes "the current 1 we have" and
   "the 1 sentence tagline". Other numerals are unchanged.
2. Immediate stutters are removed: function-word repeats ("I I", "how how", "the the",
   "I, I think") and adjacent repeated phrases ("we have we have", "to just to just",
   "one round, one round"). Kept: emphasis ("very very", "really really", "so so"),
   grammatical doubles ("that that", "had had", "gave her her", "turn it on on"),
   enumerations with conjunctions ("that part and that part and that part",
   "this, this or that"), dimensions ("12 by 12 by 12") and repeated proper names.
3. A dictation that trails off on a conjunction or article gets no terminal period, and a
   trailing ". And" becomes " and".
4. Paragraphs: a closing paragraph under 20 words joins the previous one, and a break
   needs three sentences and at least 40 words (or 80 words, or a topic cue such as
   "Secondly"). A 75-word four-sentence message no longer ends in a one-sentence paragraph.

## Results

- Replay: 9 of 86 outputs changed; each was reviewed. Two regressions in an earlier draft
  (deliberate enumerations) were found by the replay and fixed before installation.
- Synthetic evaluation (`evaluate_cleanup.py`) unchanged: 27/27 word and shape matches,
  23 accepted, 4 raw fallbacks. Replay median 0.3 ms per dictation, maximum 36.5 ms.
- Python suite: 47 tests (41 existing plus new disfluency, ending, paragraph and number
  cases). Swift suite passed (2 + 64 + 72).
- Coda quit normally before replacement. Build 22 passed strict signature verification with
  the unchanged designated requirement and bundles the new rule files; launched via
  LaunchServices it reports Accessibility trusted and automatic insertion enabled. All data
  files under Application Support/Coda (excluding Models) and the exported preferences
  hashed identical before and after replacement.
- Executable SHA-256: `c09acc903ddd163a1f3e7fb6a94dc837523cdee07446b60778c4f348fe541306`.

## Not changed, and why

- Misheard words (brand and product names, sound-alikes) are speech recognition errors.
  Rules cannot fix them safely; the custom dictionary is the right place.
- "like", "you know" and "I mean" stay except the existing clear discourse cases; their
  meaningful uses are too common to remove without a model.
- Restarts that change wording ("we should the plan is") are left as spoken.

## Remaining validation

No live dictation was run after installation. While the punctuation model is still warming,
a trailing conjunction keeps its recognizer capitalization ("result And", without a period);
once warm, the output is "result and".
