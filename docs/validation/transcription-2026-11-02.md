# Dictation transcription failure investigation, November 2, 2026

The user confirmed the shortcut repair starts Listening, then reported a failure after
speaking. The latest failed history entry was a transcription failure, with no result;
the preceding entry had a nonempty transcription. The old catch block saved only a
generic instruction to check the model and microphone, discarding the actual error.
The original exception cannot be recovered from that entry, and its exact cause has
not yet been established.

## Changes

- Preserve typed failure stages: model preparation/load, audio decoding, recognition,
  and a model result containing no words. HUD and history show that actual category.
- Preserve bounded system error identifiers, never raw SDK error descriptions that may
  contain user paths. Empty recognition is labelled “No words recognized”, not a claim
  that the user did not speak.
- Failed-history diagnostics add capture duration, peak input level and audio byte count.
  No failed recording is retained; existing temporary audio cleanup is preserved.
- Failure presentation lasts ten seconds, and stale errors cannot replace a newer session.

## Verification

Generated synthetic AAC speech without microphone use:

```sh
/usr/bin/say -o /tmp/coda-transcription-probe.m4a --file-format=m4af --data-format=aac 'This is a local dictation test. Three times four equals twelve.'
CODA_SYNTHETIC_DICTATION_FIXTURE=/tmp/coda-transcription-probe.m4a ./scripts/test.sh
```

128 individual tests passed; four unrelated opt-in cases skipped. The opt-in prepared
model test recognized the expected phrase on three consecutive AAC dictations through
`LocalPipeline` using the existing model cache. A one-second synthetic silent WAV
returned the distinct `noWords` category. Other tests check diagnostic privacy, capture
number bounds, truthful HUD categories and stale-result rejection. No private audio,
microphone input or transcript upload was used by these tests.

The model test verifies the prepared model and decoder path. After build 18 reopened,
the user retried a spoken sentence with Control–Option and confirmed: “Text appeared.”
This verifies a successful live shortcut/capture/transcription retry. The exact cause of
the earlier intermittent failure remains unknown because the previous build discarded
its exception; future failures retain the category and capture measurements.

## Canonical bundle

Built only `build/Coda.app`, version 0.4.13 build 18. Coda was observed idle and quit
normally before replacement. Strict deep signature verification passed with the
existing certificate leaf `22571b293ddeed6b20db834884a208bfdaddedd7`. The exact canonical
executable reports Accessibility trusted and automatic insertion enabled. All 124
checked local data/preferences files were unchanged before reopening. No duplicate app
or source backups, data deletion, access-grant changes or remote push occurred.

Executable SHA-256:
`546f15ad2b07acf00cfb29b197f3915cdcb47d6dbb9560280481ee17722a9f46`.
