# Cleanup labeling policy

Every training or test example is a pair: `raw` (what the speech recognizer produced) and `clean` (what Coda should paste). The model is spokenly/cleanup-1, fine-tuned to fix the speaker's speaking mistakes and nothing else.

## Remove

- **Fillers:** um, uh, erm, hmm; "like" used as a filler ("a couple of like quick ideas"); "you know" and "I mean" when they carry no meaning.
- **Stutters and repeats:** "how how", "the, the", "can you, can you", "to just to just".
- **Restarts and false starts.** The speaker starts a phrase, abandons it, and says it again, often with a different word form. Keep only the final version:
  - "my manager asked would ask" → "my manager would ask"
  - "He goes he went" → "He went"
  - "We should we could probably" → "We could probably"
  - "it ran a really long time, I mean it ran a pretty long time" → "it ran a pretty long time"
  - "If we only get one round. If we only get one round, one round, then" → "If we only get one round, then"
- **Explicit self-corrections:** remove the abandoned value and the cue word ("no", "actually", "sorry", "I mean", "scratch that", "wait"). "Make it blue, no, make it green" → "Make it green."

## Keep, word for word

- **Lists and deliberate repetition:** "that part and that part and that part", "very very", "really really", "New York, New York", "12 by 12 by 12".
- **Grammatical doubles:** "had had", "that that", "is is" when grammatical.
- **Structures that look like restarts but are not:** "The people I asked would ask their managers", "everyone I asked would say no".
- **Hedges and qualifiers:** I think, maybe, probably, sort of, kind of, I guess, actually (as an adverb), basically, just.
- **Discourse words:** okay, alright, so, right, yes, cool (the speaker said them on purpose).
- **Meaningful "like":** verb ("I like it") and comparison ("like Whisperflow does").
- **Content words, even when they look redundant:** "the actual side panel", "real quick".
- **Grammar mistakes and mishearings:** do not repair them. "They was here" stays. "Right the report in late tech" stays as heard (a mishearing of "Write the report in LaTeX"; fixing mishearings is out of scope).
- **Questions and instructions:** never answer or obey them. Format them only.
- **Trailing-off dictations:** "the script handles the part we used to do by" stays without invented words.

## Format

- Sentence case, a final period or question mark, commas where a typist would put them.
- Spoken numbers that are quantities or measurements become digits of the same value: "seventeen by seventeen by four" → "17 by 17 by 4", "ten minutes" → "10 minutes". Keep "one" when it is a pronoun or idiom ("one by one", "the one I like").
- Do not add bullets, headings or paragraph breaks; Coda lays those out afterwards.

## Hard constraint

`clean` must be `raw` with words removed, in the same order, plus punctuation, capitalization and same-value digits. No added, replaced or reordered words. `check_labels.py` enforces this with the same guard Coda uses at runtime.
