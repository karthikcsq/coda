#!/usr/bin/env python3
"""Publish a clean main commit, then install that exact signed production build."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, help='Existing production bundle (default: main checkout/build/Coda.app)')
    args = parser.parse_args()
    os.chdir(Path(__file__).resolve().parent.parent)
    if output('git', 'status', '--porcelain'):
        raise SystemExit('Release requires a clean working tree. Commit and review changes first.')
    if output('git', 'branch', '--show-current') != 'main':
        raise SystemExit('Release from main after merging the reviewed changes.')
    common = Path(output('git', 'rev-parse', '--path-format=absolute', '--git-common-dir'))
    destination = (args.app or common.parent / 'build/Coda.app').resolve()
    if destination.name != 'Coda.app':
        raise SystemExit('Production destination must be named Coda.app.')
    if not destination.exists():
        raise SystemExit('Production bundle not found. Pass --app pointing to your existing Coda.app.')
    with (destination / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream).get('CFBundleIdentifier') != 'app.coda.notebook':
            raise SystemExit('Destination is not the production app.')
    run('codesign', '--verify', '--deep', '--strict', str(destination))
    # Match certificate hashes, not just the certificate's display name.
    def authority(app):
        return subprocess.check_output(['codesign', '-d', '-r-', str(app)], stderr=subprocess.STDOUT, text=True).split('designated =>', 1)[-1].strip()
    previous_identity = authority(destination)
    revision = output('git', 'rev-parse', 'HEAD')
    run('git', 'fetch', 'origin', 'main')
    run('git', 'merge-base', '--is-ancestor', 'origin/main', revision)
    run('scripts/test.sh')
    run('python3', '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-v')
    with tempfile.TemporaryDirectory(prefix='coda-release-') as temporary:
        candidate = Path(temporary) / 'Coda.app'
        run('scripts/build-app.sh', env={**os.environ, 'CODA_CHANNEL': 'production', 'CODA_APP_OUTPUT': str(candidate)})
        if authority(candidate) != previous_identity:
            raise SystemExit('Signing identity changed. Production was not replaced.')
        if output('git', 'rev-parse', 'HEAD') != revision or output('git', 'status', '--porcelain'):
            raise SystemExit('Source changed during verification. Release again from a clean commit.')
        run('git', 'push', 'origin', 'HEAD:main')
        if output('git', 'ls-remote', 'origin', 'refs/heads/main').split()[0] != revision:
            raise SystemExit('GitHub main could not be verified; production was not replaced.')
        print(f'GitHub main verified at {revision}. Requesting normal production quit.', flush=True)
        # The app refuses normal quit while meeting or dictation work is busy.
        # Never send a kill signal or interact with the Development process.
        executable = str(destination / 'Contents/MacOS/Coda')
        def running():
            return any(line.strip() == executable for line in output('ps', '-axo', 'comm=').splitlines())
        if running():
            run('osascript', '-e', 'tell application id "app.coda.notebook" to quit')
            deadline = time.monotonic() + 15
            while running() and time.monotonic() < deadline:
                time.sleep(0.25)
            if running():
                raise SystemExit(f'Production is busy or quit was declined. GitHub is at {revision}; local app unchanged. Finish the operation and rerun release.')
        # Preserve the old bundle only during replacement, then remove the backup.
        with tempfile.TemporaryDirectory(prefix='coda-rollback-', dir=destination.parent) as rollback:
            backup = Path(rollback) / 'Coda.app'
            destination.rename(backup)
            try:
                shutil.copytree(candidate, destination, symlinks=True)
                run('codesign', '--verify', '--deep', '--strict', str(destination))
            except BaseException:
                if destination.exists():
                    shutil.rmtree(destination)
                backup.rename(destination)
                raise
        run('open', str(destination))
        print(f'Production installed and launched: {destination} (commit {revision}).')


if __name__ == '__main__':
    main()
