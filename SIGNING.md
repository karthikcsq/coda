# Local Coda signing

## Single current app, November 2, 2026

The current app is **0.4.13 build 18** at `build/Coda.app`, including precise dictation
failure reporting, Control–Option shortcut recovery and the native UI
overhaul, dictionary learning, the word suggestion pop-up, and Smart number/math formatting. Keep this
single bundle up to date. Superseded bundles and duplicate source/review folders
have been removed; historical paths below describe prior validation only and are
no longer retained rollback copies. Git checkpoints now provide source rollback.
Rebuild a chosen revision with the existing signing identity to restore it.

The new dictionary/cleanup work and existing meeting changes were checkpointed
locally before the UI overhaul. No remote push or signing/access policy change
was made. Do not recreate a directory of versioned binary backups.

Build 18 passed strict signature verification with the existing certificate requirement.
The canonical executable reports Accessibility trusted and automatic insertion enabled.
Coda was confirmed idle and quit normally before replacement; all 124 checked local
data/preferences files were preserved byte-for-byte. Native renders, regression results
and the executable hash are recorded in `docs/validation/transcription-2026-11-02.md`.

## Historical installed update — 0.4.12 build 11

October 31, 2026: the insertion repair was staged, strictly verified, installed at `build/Coda.app`, and reopened normally with the existing certificate fingerprint `22571B293DDEED6B20DB834884A208BFDADDEDD7`. The exact installed executable reports Accessibility trusted and automatic insertion enabled. All 68 preexisting history JSON files and the checked dictation preferences were preserved. Rollback: `build-staged/Coda-0.4.10-build9-before-insertion.app`. The preexisting 0.4.11 candidate was preserved. No permission, certificate policy or key access policy changed. Live Claude insertion is for the user to test, as requested. Evidence: `benchmarks/insertion-2026-10-31/REPORT.md` and `installation.json`.

## Previous installed update — 0.4.10 build 9

October 26, 2026: staged candidate and canonical `build/Coda.app` passed `codesign --verify --deep --strict` with the existing leaf fingerprint `22571B293DDEED6B20DB834884A208BFDADDEDD7`. The exact installed worker/resources passed synthetic evaluation; strict verification still passed afterward, with no bytecode written into the signed bundle. Normal quit/reopen preserved Smart / Control + Option / Hold, all 55 saved dictation JSONs and three meeting JSONs. The actual signed binary's read-only diagnostic reported Accessibility trusted and automatic insertion enabled. Rollback: `build-staged/Coda-0.4.9-build8-rollback.app`; earlier rollbacks remain. No key, certificate policy, app permission or global security setting changed during this update. Evidence: `benchmarks/cleanup-reuse-2026-10-26/installation.json`, `installed-results.json` and `build.log`.

## Previous installed update — 0.4.9 build 8

October 26, 2026: the separately staged candidate and canonical `build/Coda.app` passed strict signature verification with the same existing certificate requirement. A normal quit was used; no force quit or Computer Use was involved. The canonical app's read-only `--insertion-diagnostics` reported Accessibility trusted and automatic insertion enabled. Smart / Control + Option / Hold and all saved JSON were preserved. Rollback is `build-staged/Coda-0.4.8-build7-rollback.app`; the earlier 0.4.7 rollback is retained. No key, certificate policy, app permission or global security setting changed. Evidence: `benchmarks/responsiveness-2026-10-26/installation.json` and `build.log`.

## Previous installed update — 0.4.8 build 7

October 26, 2026: `build/Coda.app` was updated to 0.4.8 build 7 using the existing identity below. Candidate and canonical installed bundle both passed `codesign --verify --deep --strict` with normal macOS certificate access; the process sandbox alone cannot perform the local trust lookup. The designated requirement remains `identifier "app.coda.notebook" and certificate leaf = H"22571b293ddeed6b20db834884a208bfdaddedd7"`. No certificate/key or trust/access policy changed. Actual running app Settings Refresh reported Accessibility enabled without new approval. Smart / Control + Option / Hold were verified in Settings. The prior 0.4.7 build 6 is retained at `build-staged/Coda-0.4.7-build6-rollback.app`, outside Trash. Build/test/model evidence is in `benchmarks/smart-cleanup-2026-10-26/`; see LOCAL_CLEANUP.md for test limits.

Coda now uses the dedicated `Coda Local Development` identity in this Mac's login Keychain. Apple Certificate Assistant generated its RSA-2048 key directly in the Keychain, with digital-signature key usage and code-signing-only extended usage. No private key was exported or written to this repository. No global certificate trust policy or key access policy was broadened. The private-key signing ACL has a specific application list, not unrestricted access.

Public certificate SHA-1: `22571B293DDEED6B20DB834884A208BFDADDEDD7`.
The certificate expires October 25, 2027. Preserve the identity; replacement can require new Accessibility approval. This self-signed identity is for local development, not notarized public distribution. Use an appropriate Developer ID identity for distribution.

`scripts/build-app.sh` defaults to this exact public identity fingerprint. It never falls back to ad-hoc signing. Another developer must provide their own identity through `CODA_SIGNING_IDENTITY`; the private key stays in their Keychain. Keep `CODA_APP_OUTPUT` unset to update the single canonical app. `CODA_BUILD_NUMBER` sets CFBundleVersion.

## Verified update, October 25, 2026

Two release packages were built from unchanged feature code as version 0.4.3, build numbers 1 and 2. Both passed `codesign --verify --deep --strict`.

Both designated requirements were:

```
identifier "app.coda.notebook" and certificate leaf = H"22571b293ddeed6b20db834884a208bfdaddedd7"
```

Build 1 CDHash: `e4fcb1e88769872fc8ce8381845d8afde36ba77f`.
Build 2 CDHash: `fa5af105df31a9ab08f49044deea6671dadd8590`.

The approved Coda-only Accessibility entry was replaced for build 1. Actual running Coda's Settings Refresh reported Accessibility enabled. Build 2 then replaced it at the same canonical path, without any further permission edits; its own Settings Refresh still reported Accessibility enabled. This tests actual permission persistence, not just matching requirements. No audio, clipboard insertion, or API tests were performed during this signing-only change.

Installed: `/Users/karth/CodingFiles/Coda/coda/build/Coda.app`, version 0.4.3, build 2.
Rollback copies are recoverable in Trash: the former ad-hoc build `Coda 19-25-28-051.app`, and certificate-signed build 1 `Coda 19-26-45-918.app`. Rolling back to ad-hoc signing can invalidate the current grant.

Build logs: `/tmp/coda-stable-sign-first.log`, `/tmp/coda-stable-sign-second.log`.

Apple references: https://developer.apple.com/library/archive/technotes/tn2206/_index.html and https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html
