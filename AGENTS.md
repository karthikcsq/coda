# Build and rollback workflow

- Keep one runnable app bundle: `build/Coda.app`. Build updates there with
  `scripts/build-app.sh`. Do not accumulate versioned app bundles, `build-staged/`,
  `archive/` source snapshots, or duplicate `ui-review/` checkouts.
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
