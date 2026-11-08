# Personal dictation audio training

Open Settings > Dictation > Personal voice training. Prepare audio training once
(downloads the private Python runtime and public Whisper weights), listen to saved
recordings, enter verbatim transcripts, then choose Fine-tune my voice. Review at
least 15 distinct English clips of up to 30 seconds. The permanent split must
contain at least 10 training transcript groups and 3 uncontaminated held-out
recordings; more reviews may be required. Long recordings remain saved but are
excluded from this first trainer. Final polished text is shown for reference;
it is never automatically treated as a verified acoustic label.

This is an experimental, separate Whisper base recognizer for personal English
dictation. Voz's published SDK provides compiled inference models but no acoustic
training/export pipeline, so the feature uses independently obtained Whisper
weights and explicitly reviewed human labels. It does not train on Voz outputs.
Meetings continue calling the existing generic Voz pipeline. The optional personal
voice selection is remembered across launches. Use generic Voz disables it without
deleting recordings. Delete recording and pair removes that saved audio/label.

## Storage and execution

With Learn from my edits enabled, successful nonempty dictations are saved under
`~/Library/Application Support/Coda/Dictations/Training/`: UUID audio and private
JSON containing raw recognition, inserted text, latest observed edits and optional
reviewedTranscript. Field observation lasts up to 60 seconds in accessible editors.
Disabling learning stops collection but keeps existing pairs. Cancelled or failed
recognition is not retained. The review screen can play and delete each pair.

`~/Library/Application Support/Coda/PersonalAudio/` contains the isolated runtime,
base weights, accepted models, active pointer, and latest evaluation report.
Preparation requires an installed Python 3.10+ (Homebrew 3.13 is supported).
Tested runtime versions: torch 2.15.0, transformers 4.57.6, numpy 2.5.4. Whisper
base revision: e37978b90ca9030d5170a5c07aadb050351a65bb. Preparation downloads public
packages/weights; training and inference load only local files and upload no audio
or text. Models are source assets, never committed. The app bundles worker.py.

The trainer uses MPS when available, CPU otherwise, two epochs with batch size one,
learning rate 1e-5 and gradient clipping. Labels exceeding 224 tokens are rejected.
Repeated normalized transcripts stay in the same partition across runs. Audio
fingerprints exclude test recordings already used by the active model or duplicated
across current training/test labels, including after a transcript edit.

The gate requires strictly lower normalized held-out word error than both generic
Whisper and the current personal model. It does NOT establish superiority over
Voz. A new directory is saved completely before switching the active pointer
atomically. Failure or a rejected candidate preserves the pointer. Prior accepted
weights remain on disk for recovery. Reset disables the personal model. Training
can be cancelled in the panel. A process lock prevents overlapping workers; app
operations avoid starting audio and cleanup training simultaneously.

Personal audio dictation skips Smart cleanup pending separate validation, but
retains the configured rules and explicit dictionary corrections. Long inference
recordings use sequential 30-second chunks; words crossing chunk boundaries may
be less accurate. Each dictation starts a worker and reloads the personal model,
so latency differs from Voz's persistent Neural Engine implementation.

## Evidence and limits

- https://huggingface.co/openai/whisper-base and
  https://huggingface.co/docs/transformers/model_doc/whisper document the model,
  processor, generation and fine-tuning interfaces.
- https://aclanthology.org/2021.emnlp-main.737/ discusses speaker adaptation and
  forgetting of other speakers. Regressions are possible, not inevitable.
- https://arxiv.org/abs/2407.13300 documents ASR correction overcorrection risks.
  Improved transcription changes cleanup's inputs; it does not inherently overfit
  cleanup. Overtraining on a small correction set is a separate risk.

Verification: five Python split/gate tests, Swift persistence/review tests, native
workspace and voice-panel renders, and saved-model offline inference passed.
A real two-epoch training run used 30 macOS-synthesized English recordings in a
private temporary folder (25 training, 5 held out). The candidate regressed from
0% to 2.78% WER and was correctly rejected. This is execution evidence, not evidence
of improvement on the user's voice. No private user dictations were trained.
A separate test-only model exercised saved-model loading through the Swift worker.

Final verification also passed all 85 CodaCore tests, the worker cancellation test,
and the generic/personal selection preservation test. Signed bundle packaging was
not performed: `security find-identity -v -p codesigning` returned zero valid
identities. The existing build script requires a certificate and deliberately
refuses ad-hoc signing. No running app was replaced.
