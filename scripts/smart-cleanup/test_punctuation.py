import unittest
from punctuation import eligible, render


class SourcePunctuation(unittest.TestCase):
    def test_predictions_only_insert_at_complete_word_boundaries(self):
        text = 'hello there'
        self.assertEqual(render(text, [(0, 2), (2, 5), (6, 11)], [1, 2, 3], {'1': '.', '2': ',', '3': '?'}), 'hello, there?')
        self.assertEqual(render(text, [(0, 5)], [9], {'9': 'BANANA'}), text)

    def test_existing_symbols_and_numbers_remain_exact(self):
        for text in ['3.14', '10:30', 'CS/technical', 'input/output', 'word, next', 'word , next']:
            end = text.index(' ') if ' ' in text else 1
            out = render(text, [(0, end)], [1], {'1': '.'})
            self.assertEqual(out, text)

    def test_existing_sentences_and_commands_bypass_prediction(self):
        for raw in ['Already punctuated.', 'can you reply question mark', 'Agenda:\n- Review', 'One? Two!', 'new paragraph please']:
            self.assertFalse(eligible(raw, raw))
        self.assertTrue(eligible('we have 3.14 units at 10:30', 'We have 3.14 units at 10:30.'))


if __name__ == '__main__': unittest.main()
