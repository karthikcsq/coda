# Personal Voz audio training

Settings > Dictation > Personal voice training prepares and adapts the same Voz
v0.4.0 used by Coda. No alternative speech recognizer is downloaded or used.
Preparation copies the installed generic Voz bundle into private working storage
and installs an isolated Python environment. It requires accepted Voz model terms
and Python 3.10+ (Homebrew 3.13 tested). Runtime versions: torch 2.15.0,
coremltools 9.0, numpy 2.5.4. Model licenses remain unchanged.

Listen to a saved recording and enter exactly what was spoken. Only explicitly
reviewed transcripts train. Polished final text and raw recognition are reference
material, never automatically used as acoustic labels. At least 15 distinct
transcripts are required, with 10 training groups and 3 uncontaminated held-out
clips; additional recordings may be needed to satisfy the fixed split. This
first trainer uses clips up to 15 seconds and labels up to 64 Voz pieces. Longer
recordings remain saved. Any unrepresentable characters cause an explicit error.
The public sidecar has token pieces without SentencePiece scores; labels use
longest matching pieces, preserving exact text, rather than claiming canonical
SentencePiece segmentation. Runtime inference uses the unmodified Voz tokenizer.

## What is trained

This is parameter-efficient adaptation of Voz's existing decoder output
projection (weights and token biases), not full encoder fine-tuning. The encoder,
mel frontend, prediction LSTMs, embedding and duration head stay frozen. All
features and reference-prefix logits come from the installed compiled Voz models.
A TDT Viterbi path aligns the reviewed pieces to those acoustic frames. Training
uses two epochs of cross-entropy on that fixed path, learning rate 1e-5, gradient
clipping and a penalty for deviation from the original projection.

Core ML's quantized CPU kernels have rounding differences from float arithmetic.
The trainer recovers approximate head features by a regularized linear solve and
keeps native starting logits as a detached residual while optimizing projection
deltas. No substitute decoder network generates alignment logits.

Only the existing projection's int8 weight, fp16 scale and fp16 bias payloads are
updated in a private copy. Duration rows are preserved byte for byte. This relies
on the pinned Voz export's weight layout: named MIL blobs, shapes and payloads
are checked using Apple's blob reader. Unsupported layouts fail before activation.
This is a Coda-specific export adapter, not a claim that Apple's public update API
can train arbitrary compiled ML Programs. Each candidate gets a fresh directory
to avoid reusing a compiled specialization from another set of weights.

## Native validation and model selection

CodaVozTool loads each generic, candidate and previous personal model using the
actual Voz Swift SDK. It transcribes held-out recordings through the normal model
loader, decoder and window stitching. The candidate must strictly lower normalized
word error against BOTH generic Voz and the previous personal Voz model. A tie or
failure keeps the existing selection. The active pointer changes atomically only
after a complete candidate bundle passes. Every accepted derivative carries a
CODA_ADAPTATION.json describing modifications and its source decoder checksum.
Rejected candidate bundles are removed. Cancellation terminates the evaluation
child and cleans staging where possible.

Transcript groups retain their split when recordings are added. Audio fingerprints
exclude duplicates and clips used to train the active model from held-out scoring,
including after transcript edits. This small personal test set is a regression
gate, not proof of improvement on every future recording.

Dictation loads the accepted directory through Voz(modelDirectory:), caches that
instance and preserves vocabulary hints. Meetings continue using LocalPipeline's
separate generic Voz instance and original model cache. Personal dictation skips
Smart cleanup pending validation of that model combination. Use generic Voz turns
off personalization without deleting the accepted model or saved recordings. The
choice is remembered across app launches. Earlier experimental model assets are
not migrated or loaded; this feature uses a separate PersonalVoz directory and
backend marker.

## Storage

With Learn from my edits enabled, successful nonempty dictations are saved under
~/Library/Application Support/Coda/Dictations/Training/: UUID audio and private
JSON with raw recognition, inserted text, latest observed field edits and optional
reviewedTranscript. Field observation lasts up to 60 seconds in accessible editors.
Failed/cancelled recognition is not retained. Disabling learning stops collection
but keeps existing pairs. The review panel plays and deletes individual pairs.

~/Library/Application Support/Coda/PersonalVoz/ contains runtime, private base copy,
accepted models, active pointer and evaluation report. Preparation may download
public Python packages or generic Voz if needed. Audio training and native
evaluation run locally; no audio or labels are uploaded. No models or recordings
are committed to Git. Generic cache files are never patched.

## Verification

- Six Python tests passed, including a native compiled-model projection update,
  unchanged duration output and unchanged generic source bytes.
- All 85 core tests and six native tests/renders passed.
- A real two-epoch smoke run used 30 synthesized recordings: 24 training and six
  held out. Both generic and adapted Voz scored 0% WER. The tie was rejected.
  This verifies execution and the gate, not improvement on the user's voice.
- A modified Voz bundle also passed offline inference through Coda's personal
  recognizer actor. Cancellation and returning to generic were tested.
- Signing remains unavailable: macOS reports zero valid code-signing identities.
  The existing build script requires a certificate and refuses ad-hoc signing.
  No running app was replaced.
