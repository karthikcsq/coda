#!/usr/bin/env python3
"""Serialize builds installing the same channel from different checkouts."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys

root = Path.home() / 'Library/Caches/Coda'
root.mkdir(parents=True, exist_ok=True)
with (root / ('build-' + sys.argv[1] + '.lock')).open('w') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('Another build is already installing this channel. Finish that build before trying again.')
    result = subprocess.run(['bash', sys.argv[2]], env={**os.environ, 'CODA_BUILD_LOCK_HELD': '1'})
    raise SystemExit(result.returncode)
