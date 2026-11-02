# Coda 0.4.3 overlay completion repair

The former completion path awaited insertion (including verification/fallback), then kept the overlay visible for another four seconds. Successful transcription now saves its text to local history and immediately orders the panel out before awaiting insertion. Delivery remains serialized by the existing busy lifecycle and updates the saved record afterward. Insertion code is unchanged.

A session-ID guard rejects cancelled/stale transcription results. Each overlay presentation has its own generation; delayed error dismissal cannot close a newer panel. Errors still get a bounded four-second display and remain in history; history-save errors remain in the main app warning. Cancellation retains its existing immediate hide behavior. Explicit history retry and preview remain available.

Validation: repository scripts/test.sh passed 41 core tests and 13 UI tests (one opt-in insertion test skipped). Three added tests exercise actual NSPanel visibility over three synthetic sessions, busy delivery serialization, saved text, cancellation/stale completion, and expiring/replaced error timers. Existing native view rendering passed and the synthetic HUD render was inspected. No microphone, models, clipboard insertion, live APIs, or private audio used.

The final app is packaged as 0.4.3. A changed executable requires a new ad-hoc signature; no security permissions or signing credentials are changed automatically. See final delivery report for actual installed trust state.
