import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publish_release', Path(__file__).resolve().parents[1] / 'publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublishSafetyTests(unittest.TestCase):
    def bundle(self, root, **changes):
        app = Path(root) / 'Coda.app'
        (app / 'Contents').mkdir(parents=True)
        metadata = {'CFBundleShortVersionString': '0.5.1', 'CodaChannel': 'production', 'CodaSourceDirty': False, 'CodaSourceRevision': 'abc123'}
        metadata.update(changes)
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump(metadata, stream)
        return app

    def test_dev_dirty_and_wrong_commit_never_publish(self):
        for changes in [{'CodaChannel': 'development'}, {'CodaSourceDirty': True}, {'CodaSourceRevision': 'other'}]:
            with tempfile.TemporaryDirectory() as root, patch.object(publisher.subprocess, 'run') as run:
                with self.assertRaises(ValueError):
                    publisher.publish(self.bundle(root, **changes), 'abc123', root)
                run.assert_not_called()

    def test_existing_version_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as root, patch.object(publisher.subprocess, 'run') as run, patch.object(publisher.subprocess, 'check_output', return_value='different\trefs/tags/v0.5.1'):
            run.return_value.returncode = 0
            with self.assertRaisesRegex(ValueError, 'Bump VERSION'):
                publisher.publish(self.bundle(root), 'abc123', root)
            self.assertEqual(run.call_count, 1)

    def test_retry_reuses_complete_release_from_same_commit(self):
        with tempfile.TemporaryDirectory() as root, patch.object(publisher.subprocess, 'run') as run, patch.object(publisher.subprocess, 'check_output', return_value='abc123\trefs/tags/v0.5.1'):
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps({'isDraft': False, 'assets': [{'name': 'Coda-macOS-arm64.zip'}, {'name': 'release.json'}]})
            publisher.publish(self.bundle(root), 'abc123', root)
            self.assertEqual(run.call_count, 1)
