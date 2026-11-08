#!/usr/bin/env python3
"""Publish the verified production bundle as an immutable versioned GitHub Release."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def publish(app, revision, directory):
    app, directory = Path(app), Path(directory)
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Release version must be major.minor.patch.')
    if info.get('CodaChannel') != 'production' or info.get('CodaSourceDirty') is not False or info.get('CodaSourceRevision') != revision:
        raise ValueError('Only a clean Production bundle matching the published commit can be released.')
    tag = 'v' + version
    # Refuse to replace a prior version's artifacts. A retry of the same revision
    # can reuse the already published release after a failed local installation.
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', 'karthikcsq/coda', '--json', 'assets,isDraft'], capture_output=True, text=True)
    if existing.returncode == 0:
        remote = subprocess.check_output(['git', 'ls-remote', 'origin', 'refs/tags/' + tag, 'refs/tags/' + tag + '^{}'], text=True).splitlines()
        hashes = [line.split()[0] for line in remote]
        if revision not in hashes:
            raise ValueError('Version already belongs to another commit. Bump VERSION before releasing.')
        data = json.loads(existing.stdout)
        if data['isDraft'] or not {'Coda-macOS-arm64.zip', 'release.json'}.issubset({asset['name'] for asset in data['assets']}):
            raise ValueError('Existing release is incomplete; inspect it before retrying.')
        return
    archive = directory / 'Coda-macOS-arm64.zip'
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest = directory / 'release.json'
    manifest.write_text(json.dumps({'version': version, 'revision': revision, 'bundleIdentifier': 'app.coda.notebook', 'sha256': digest, 'asset': archive.name}, indent=2) + '\n')
    # gh creates the tag at the exact verified revision; assets upload while the
    # release is a draft, then publication makes the completed version visible.
    subprocess.run(['gh', 'release', 'create', tag, str(archive), str(manifest), '--repo', 'karthikcsq/coda', '--target', revision, '--title', 'Coda ' + version, '--notes', 'Signed Apple Silicon production build. Source commit: ' + revision + '. Local certificate signing; not notarized.', '--draft'], check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', 'karthikcsq/coda', '--draft=false'], check=True)


if __name__ == '__main__':
    publish(*sys.argv[1:])
