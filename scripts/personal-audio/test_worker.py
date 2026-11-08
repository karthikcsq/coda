import unittest
from worker import distance, words, split_pairs

class PolicyTests(unittest.TestCase):
    def test_word_errors(self):
        self.assertEqual(distance(words('Hello, WORLD.'), words('hello world')), 0)
        self.assertEqual(distance(words('one two three'), words('one four')), 2)

    def test_only_reviewed_and_no_duplicate_leakage(self):
        pairs = [{"id": str(i), "reviewedTranscript": f"reviewed phrase number {i}"} for i in range(100)]
        pairs += [{"id": "unreviewed", "finalText": "Never train on this"}, dict(pairs[0], id="duplicate")]
        train, test = split_pairs(pairs)
        self.assertNotIn('unreviewed', [p['id'] for p in train + test])
        self.assertFalse({p['reviewedTranscript'] for p in train} & {p['reviewedTranscript'] for p in test})
        larger = pairs + [{"id": str(i), "reviewedTranscript": f"reviewed phrase number {i}"} for i in range(100, 150)]
        new_train, new_test = split_pairs(larger)
        self.assertTrue({p['id'] for p in train} <= {p['id'] for p in new_train})
        self.assertTrue({p['id'] for p in test} <= {p['id'] for p in new_test})

    def test_too_few_labels_rejected(self):
        with self.assertRaisesRegex(ValueError, '15'):
            split_pairs([{"reviewedTranscript": "same phrase"}] * 20)


class PromotionTests(unittest.TestCase):
    def test_rejection_preserves_active_and_never_saves(self):
        import tempfile
        from pathlib import Path
        from worker import promote
        class Model:
            def save_pretrained(self, *args, **kwargs):
                raise AssertionError('Rejected model must not save')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'active.json').write_text('original')
            for candidate in [0.1, 0.2, float('nan')]:
                self.assertFalse(promote(root, Model(), 0.1, 0.15, candidate, set()))
            self.assertEqual((root / 'active.json').read_text(), 'original')

    def test_acceptance_saves_before_switch_and_failed_save_preserves_active(self):
        import tempfile, json
        from pathlib import Path
        from worker import promote
        class Model:
            def save_pretrained(self, destination, **kwargs):
                destination.mkdir(parents=True)
                (destination / 'config.json').write_text('{}')
        class Failure:
            def save_pretrained(self, *args, **kwargs):
                raise OSError('disk full')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertTrue(promote(root, Model(), 0.2, 0.15, 0.1, {'audiohash'}))
            active = (root / 'active.json').read_text()
            metadata = json.loads(active)
            self.assertEqual(metadata['trainedAudio'], ['audiohash'])
            self.assertTrue((root / 'models' / metadata['model'] / 'config.json').exists())
            with self.assertRaises(OSError):
                promote(root, Failure(), 0.2, 0.15, 0.1, set())
            self.assertEqual((root / 'active.json').read_text(), active)

if __name__ == '__main__':
    unittest.main()
