# Dictation responsiveness and final-word capture

- Reduced modifier-chord activation debounce from 180 ms to 30 ms. Physical key and permission rechecks remain in place, as do cancellation for other keys and the full-release latch.
- Construct the overlay during controller attachment, show startup feedback before destination queries, skip repeated permission requests when already authorized, and start microphone capture before synchronous Accessibility queries.
- Record mono 48 kHz, 16-bit PCM WAV rather than AAC to avoid encoder setup on the shortcut path.
- On stop, enter the busy processing phase immediately but continue capture for 500 ms before stopping the recorder and transcribing. Escape, lock, sleep, and cancellation still stop capture immediately and cancel the pending tail task.

Verification: `swift test` passed (83 core, 70 UI/integration, 2 speaker tests). `git diff --check` passed. Signed release bundle built with `scripts/build-app.sh`; its signature is verified by the script. No live microphone timing or speech-recognition accuracy measurement was performed. The running app in the separate primary checkout was not replaced.
