# Coda 0.4.0 UI refresh — installed 2026-10-25

User explicitly authorized replacement after visual review. Canonical `build/Coda.app` now contains the functional0.4.0 release, bundle identifier `app.coda.notebook`; the prior0.3.2 bundle is recoverable in Trash. The separate UI Review app was also retired to Trash. Production settings/history/recordings and .env were preserved. The embedded configuration directory remains this canonical project.

Sources, Tests and scripts now match the tested UI release. Earlier source, including unshipped0.3.3 insertion experiments, was preserved under `archive/pre-ui-source-*` before replacement. UI source development history and design evidence remain under `ui-review`; its earlier preview-only documentation describes that review phase, not the now-installed app. No proprietary assets or code were copied.

Validation: 41 core +6 UI/fixture tests passed; release build and strict signature verification passed. Actual0.4.0 launch path was confirmed using NSRunningApplication. Actual settings navigation worked. No audio capture or live API was exercised. The installed app's own permission UI reports missing Accessibility trust after the ad-hoc rebuild. This was anticipated and no permission changes were made; automatic insertion is currently blocked pending explicit OS authorization for this build. Do not treat a helper process's trust as Coda's trust.

Build normally with `./scripts/build-app.sh`; test with `./scripts/test.sh`. Rebuilding an ad-hoc signed app may invalidate macOS's permission identity. Do not re-sign/rebuild simply to troubleshoot permissions.

Actual synthetic visual evidence: `ui-review/evidence/home.png`, `ui-review/evidence/settings.png`. Wispr's temporary inspection flag was verified restored to false. Fidelity limits: active recording states were not inspected; exact typeface identity is unverified; the original meeting notebook remains in its existing layout.
