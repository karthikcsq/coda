import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('coda_release', Path(__file__).resolve().parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseSafetyTests(unittest.TestCase):
    def test_dirty_source_never_builds_or_publishes(self):
        with patch('sys.argv', ['release.py']), patch.object(release, 'output', return_value=' M source'), patch.object(release, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'clean working tree'):
                release.main()
            run.assert_not_called()

    def exercise(self, failure):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory).resolve() / 'Coda.app'
            (app / 'Contents').mkdir(parents=True)
            with (app / 'Contents/Info.plist').open('wb') as stream:
                plistlib.dump({'CFBundleIdentifier': 'app.coda.notebook'}, stream)
            marker = app / 'original'
            marker.write_text('preserve production')
            calls = []
            def output(*args):
                if args[:3] == ('git', 'status', '--porcelain'): return ''
                if args[:3] == ('git', 'branch', '--show-current'): return 'main'
                if args[:3] == ('git', 'rev-parse', '--path-format=absolute'): return str(Path(directory) / '.git')
                if args[:3] == ('git', 'rev-parse', 'HEAD'): return 'abc123'
                if args[:2] == ('git', 'ls-remote'): return 'abc123\trefs/heads/main'
                if args[0] == 'ps': return str(app / 'Contents/MacOS/Coda') if failure == 'busy' else ''
                raise AssertionError(args)
            def run(*args, **kwargs):
                calls.append(args)
                if args[0] == 'scripts/build-app.sh':
                    candidate = Path(kwargs['env']['CODA_APP_OUTPUT'])
                    candidate.mkdir()
                if args[:2] == ('git', 'push') and failure == 'push':
                    raise subprocess.CalledProcessError(1, args)
            with patch('sys.argv', ['release.py', '--app', str(app)]), patch.object(release, 'output', side_effect=output), patch.object(release, 'run', side_effect=run), patch.object(release.subprocess, 'check_output', return_value='designated => stable identity'), patch.object(release.time, 'monotonic', side_effect=[0, 20]), patch.object(release.shutil, 'copytree', side_effect=OSError('disk full')):
                with self.assertRaises((SystemExit, subprocess.CalledProcessError, OSError)):
                    release.main()
            self.assertEqual(marker.read_text(), 'preserve production')
            self.assertFalse(any(call[0] == 'open' for call in calls))
            return calls

    def test_push_failure_leaves_production_running_and_unchanged(self):
        calls = self.exercise('push')
        self.assertFalse(any(call[0] == 'osascript' for call in calls))

    def test_busy_production_is_not_replaced(self):
        calls = self.exercise('busy')
        self.assertTrue(any(call[0] == 'osascript' for call in calls))

    def test_failed_install_restores_original_bundle(self):
        self.exercise('install')


if __name__ == '__main__':
    unittest.main()
