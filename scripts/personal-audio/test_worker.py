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


class GateTests(unittest.TestCase):
    def test_requires_improvement_over_generic_and_personal_voz(self):
        from worker import accepts
        self.assertTrue(accepts(.2,.15,.1))
        self.assertFalse(accepts(.2,.15,.15))
        self.assertFalse(accepts(.2,.1,.15))
        self.assertFalse(accepts(.1,.2,.15))
    def test_nonfinite_or_negative_scores_never_install(self):
        from worker import accepts
        for score in [float('nan'),float('inf'),-.1]:
            self.assertFalse(accepts(.2,.2,score))

if __name__ == '__main__':
    unittest.main()
