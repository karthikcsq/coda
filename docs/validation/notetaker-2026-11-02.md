# Notetaker speaker counts and summary coverage

## Behavior

- Record options accept Automatic or 1–4 speakers, including the local speaker.
- A reviewed participant-count snapshot can supply the count for combined audio.
  Manual entry wins; microphone-only never takes an online participant hint.
- The count is persisted per meeting, survives restart, and reaches the diarizer
  before voice clustering. Reprocessing clears old identities and summaries only
  after the new transcript succeeds. Old JSON without the optional field loads.
- Google Meet, Zoom browser calls, Teams browser calls, native Zoom, and native
  Teams have active-call recognition adapters. Supported browser bundles include
  Chrome, Safari, Edge, Arc, Brave, Chromium, and Firefox. Recognition requires an
  exposed in-call leave control; participant counts must be unambiguous in the
  participant button or its badge. English control labels are currently supported.
- A floating suggestion opens recording options; it never starts recording.
  Accessibility must already be granted or enabled by the user. Background/hidden
  tabs, localized controls, inaccessible badges, room devices, shared devices,
  silent participants, or more than four attendees can require manual input.
- Detection and reading counts are best effort. No calendar attendee count is
  substituted for the number of people actually in the call. There is no Google,
  Zoom, or Teams account integration or extension installation.

## Summary evaluation

The original instruction requested a concise overview. The revised instruction
requests complete topic coverage and specific rationale/examples, then checks for
omissions before returning. The schema and evidence validation remain compatible.
The configured model remains unchanged; the output ceiling increases from 6,000
into 10,000 tokens. Requests still use store:false and send text only.

A live request against the user's designated saved meeting returned 15 discussion
notes, one decision, and two actions, compared with four overview notes, one
decision, and no actions previously. Exact segment evidence validated. Human
review against all 131 source segments found substantially better coverage of the
middle of the conversation, concrete examples, and the closing follow-up. This is
one qualitative comparison, not a general accuracy benchmark. The private
transcript and both summary payloads are kept outside the repository.

Prompt: Sources/CodaCore/Summarizer.swift, Summarizer.instructions.

## Checks performed

- Full offline suite: 94 tests passed (60 core, 32 native UI, 2 diarizer).
- Relevant UI/detection/clustering tests rerun after the layout adjustment passed.
- Native options rendering inspected at its natural size; explanatory text wraps
  and buttons remain visible.
- Release compilation, certificate signing, and deep/strict signature verification
  passed after user approval of the macOS Keychain prompt. Coda 0.4.13 was
  installed at build/Coda.app and reopened. The prior application was backed up
  under build-staged before replacement.
- Native app UI verified the speaker-count menu (including 3 speakers), recording
  options, and the improved saved summary. No test recording was started.
- The designated saved summary was updated after backing up the original meeting
  metadata in Application Support/Coda/Backups. All fields other than summary
  were verified identical to the backup.
- Tests cover three-service recognition, prejoin rejection, host spoofing,
  cross-document isolation, ambiguous counts, manual precedence, reviewed count
  snapshots, persistence compatibility, and embedding clustering of five lanes
  into three voices. Existing automatic clustering behavior is also tested.

## Remaining validation

Actual live calls in Meet/Zoom/Teams were not created during implementation.
Detection must be checked on the user's current versions and Accessibility tree.
The clustering algorithm was tested with synthetic embeddings; the user's actual
three-person recording was not relabeled because its identity was unspecified.
The four-speaker model limit remains. A manually supplied count cannot guarantee
correct identities during overlapping speech or create a voice for a silent
participant.
