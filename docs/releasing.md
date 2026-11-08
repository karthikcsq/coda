# Production and Development

Production is the mint Coda app, bundle ID `app.coda.notebook`. Keep its existing
location in the primary checkout's `build/Coda.app`, certificate identity,
preferences and `~/Library/Application Support/Coda` data. Existing macOS grants
remain attached to that identity.

Development is **Coda Dev**, bundle ID `app.coda.notebook.dev`. Its purple icon has
a DEV badge, its workspace and floating dictation overlay are purple, and its
window, sidebar, overlay and menu identify it as Development. It uses its own
macOS permissions, preferences, histories, vocabulary, models and tuning data in
`~/Library/Application Support/Coda Dev`. Do not copy personal production data
into Development automatically. Prepare models and grant permissions in Dev as
needed. Development defaults to the modifier gesture Shift–Control–Option; Production
uses Control–Option. Releasing any required modifier finishes hold-mode
dictation. Its suggested custom shortcut is Control–Shift–Command–D. Open Dev
and bring its window forward when handing a test to the user, then quit it
normally once the user finishes.

## Develop

Run `scripts/build-app.sh`, then `open "$HOME/Applications/Coda Dev.app"`. The build registers this stable Applications location with Launch Services and imports Spotlight metadata so app-name search can find it. Quit Development
normally before rebuilding it. Keep using Production during development. Ordinary
builds never update Production. Each bundle records `CodaChannel`, the full
`CodaSourceRevision`, and `CodaSourceDirty` in Info.plist. The Help menu displays
the channel name and short source revision. A dirty build is for development;
it cannot be promoted by the release script.

## Worktrees

Use the primary checkout on `main` as the integration point for completed work.
Keep feature worktrees only while they are active. Before removing one, verify
its tracked and untracked work is committed and merged, or retain its branch as
an explicit recovery point. Remove its checkout with `git worktree remove`;
remove merged temporary branches after consolidation. Build Development at its
stable Applications path rather than keeping runnable bundles per worktree.

The correction editor defaults to Control–Option–C in Production and
Shift–Control–Option–C in Development so both channels can run together.

## Release

1. Complete tests, native renders and the relevant manual checks in Development.
   Review and commit changes locally. Open/merge a PR when requested, or merge the
   reviewed changes into local main. Preserve other ongoing work. Never move
   unreviewed or unrelated edits into the release.
2. When a release is authorized, run `scripts/release.py` from a clean `main`.
   For a nonstandard existing Production location, pass `--app /path/Coda.app`.
3. The command fetches GitHub main and refuses a non-fast-forward release, runs
   tests, builds a temporary signed Production candidate and checks its signing
   requirement against the installed Production app. It checks the source stayed
   unchanged, pushes main and verifies GitHub has that exact commit. It then publishes a versioned GitHub Release containing the signed production ZIP and a SHA-256/source-commit manifest. A version cannot be reused for a different commit; bump `VERSION` for each release.
4. The command requests a normal Production quit. Coda refuses while meeting or
   dictation work is busy. It never kills an app. If it does not quit, installation
   stops and reports that GitHub is published but local Production is pending.
   Finish the operation and rerun the command.
5. After quit, replace the existing Production bundle, verify its signature and
   reopen it. An installation failure restores the prior bundle. Temporary build
   and rollback bundles are removed. Preferences, histories, models and grants
   are not rewritten. Development is left alone.
6. Confirm the running app path and installed source revision. Report the GitHub
   commit and local Production result separately. An agent performing a push
   that changes remote main must invoke its confetti tool once after success if
   available. The standalone release command cannot invoke chat tools.

Both channels use the original Coda menu-bar application policy and original SwiftUI menu/window handling. Development differs in its display name, visual theme, shortcut and isolated storage.

Builds are serialized across checkouts. A checkout must include the installed Dev commit before replacing it, so another task cannot silently reinstall an older or divergent menu implementation. Merge the installed revision first.

The menu bar uses the original icon-style label for both channels: a circled waveform for Development and a plain waveform for Production; both channels use the original Coda command menu. Version and source revision remain in bundle metadata. Production links to GitHub Releases.

There is no background auto-updater. GitHub main is the source of truth; the
release command publishes it and installs the matching signed local app. If
publishing fails, Production remains unchanged. If quitting/installing fails,
GitHub may be newer than local Production; rerun the same command after resolving
the local issue. Tests cannot prove microphone latency or recognition accuracy;
verify the final-word buffer with real speech before calling that fix validated.

## Roll back

Use `git revert` on the release commit(s), review/test the result, and run the same
release command from main. This makes GitHub and Production agree on the rollback
without retaining old runnable bundles or rewriting Git history. Data migrations
must remain backward compatible or supply a separately reviewed recovery plan.
