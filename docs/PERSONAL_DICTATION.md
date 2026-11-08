# Personal dictation training

The current implementation saves successful nonempty dictations while Learn from my edits is enabled in `~/Library/Application Support/Coda/Dictations/Training/`. Each UUID has private audio and JSON containing raw recognition, inserted text, latest observed field text, and whether that differs from insertion. Failed/cancelled sessions are not retained. Accessibility observation lasts up to 60 seconds in supported editors; final text is the latest observed passage, not a guaranteed final edit or verified verbatim transcript. Disabling learning stops future collection; existing pairs remain on disk.

The Fine-tune cleanup button uses the existing local text cleanup tuner and its quality gate. It does not train speech recognition. Voz 4.1.0 exposes inference and custom model-directory loading but no training API in its Swift SDK. A supported acoustic training/export pipeline and verbatim label review are still needed before an audio fine-tuning button can truthfully be offered. Meetings continue using generic Voz; personal text cleanup is confined to dictation.

Speaker adaptation can forget other speakers, but a regression is not inevitable: https://aclanthology.org/2021.emnlp-main.737/

A better recognizer does not inherently overfit the cleanup model. It changes the cleanup input distribution; overcorrection can damage already-correct recognition. Excess training on few examples is a separate overfitting risk. See https://arxiv.org/abs/2407.13300 . Future acoustic model changes should trigger validation of the entire recognizer/cleanup combination on held-out audio, including correct-text preservation examples. Do not reuse polished rewrites as acoustic ground truth without review.

Verification: four targeted persistence and tuning-policy tests passed; three native workspace render tests passed. Settings render inspected. No acoustic training or real user recordings were run; no running app was replaced.
