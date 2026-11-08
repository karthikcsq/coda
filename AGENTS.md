# Build and rollback workflow

- Keep two app channels: Production (`Coda.app`, `app.coda.notebook`) in the
  primary checkout's `build/`, and Development (`build/Coda Dev.app`,
  `app.coda.notebook.dev`) in the active development checkout. Ordinary
  `scripts/build-app.sh` builds Development. Purple surfaces, DEV icon and labels,
  separate preferences and `Application Support/Coda Dev` identify Development.
  Do not accumulate versioned bundles, `build-staged/`, `archive/` snapshots, or
  duplicate `ui-review/` checkouts.
- Open Development only for an explicit test handoff and bring its window forward.
  Close it normally once the user finishes testing. Development uses
  Shift–Control–Option; Production uses Control–Option.
- Release only through `scripts/release.py` from clean, reviewed `main`: tests,
  signed production build and identity check, push and verify GitHub main, normal
  idle-only production quit, replace and verify production, then reopen. A failed
  local installation after publishing must be reported as GitHub published with
  local Production still pending. See `docs/releasing.md`.
- When asked to release/update Production, that includes pushing the verified
  release commit to GitHub and installing that same commit locally. Development
  work alone does not authorize publishing or replacing Production.
- Use local Git commits for recoverable checkpoints and rollback. Commit source,
  tests and useful verification notes; never commit generated app bundles, model
  assets, recordings, private transcripts or credentials. Do not push without
  authorization.
- Before replacing a running app, ensure recording/processing is idle and use a
  normal quit. Verify the existing code-signing identity and the finished bundle.
  Preserve the user's data, preferences and macOS access grants.
- Preserve other ongoing edits. Run appropriate tests and render native SwiftUI
  changes before reporting UI work complete.

# Pull request and push celebrations

After successfully creating a new pull request, including a draft, call the Codex
app's `fire_confetti` once. Also celebrate once after a confirmed push that changes
remote `main`. Do not celebrate failed operations, existing PR updates, other
branches or an everything-up-to-date push. This is permission to celebrate, not
permission to push. If the tool is unavailable, continue without claiming it fired.
