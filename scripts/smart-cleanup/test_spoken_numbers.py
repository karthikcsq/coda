import unittest
import json
import pathlib
import subprocess
import sys
import tempfile
from spoken_numbers import normalize
from worker import parse_correction_decisions


class SpokenNumbers(unittest.TestCase):
    def test_cardinals_and_decimals(self):
        for source, expected in [
            ('We need twenty five seats and six tables.', 'We need 25 seats and 6 tables.'),
            ('one hundred and twenty five', '125'),
            ('two million five hundred thousand and twelve', '2500012'),
            ('three point one four', '3.14'),
            ('point zero five', '0.05'),
            ('forty-two people', '42 people'),
            ('one hundred and five dollars', '105 dollars'),
            ('two and three', '2 and 3'),
            ('3.14 plus two', '3.14 + 2'),
            ('3/4 plus one', '3/4 + 1'),
            ('a hundred and twenty', '120'),
        ]:
            self.assertEqual(normalize(source), expected, source)

    def test_math_preserves_values_and_never_calculates(self):
        for source, expected in [
            ('six times four equals twenty four', '6 × 4 = 24'),
            ('twenty five divided by five equals five', '25 ÷ 5 = 5'),
            ('two plus two equals five', '2 + 2 = 5'),
            ('ten minus three equals seven', '10 − 3 = 7'),
            ('negative three multiplied by two', '−3 × 2'),
            ('five times negative three', '5 × −3'),
            ('x squared plus y squared equals z squared', 'x² + y² = z²'),
            ('two to the power of five', '2^5'),
            ('three over four', '3 / 4'),
            ('five percent plus ten percent', '5% + 10%'),
            ('two is less than ten', '2 < 10'),
            ('two is not equal to three', '2 ≠ 3'),
            ('five less than or equal to six', '5 ≤ 6'),
        ]:
            self.assertEqual(normalize(source), expected, source)

    def test_time_requires_clock_context_or_meridiem(self):
        for source, expected in [
            ('Meet at three thirty tomorrow.', 'Meet at 3:30 tomorrow.'),
            ('Meet at nine oh five.', 'Meet at 9:05.'),
            ('three forty five pm', '3:45 PM'),
            ('five pm', '5 PM'),
            ('nine thirty', 'nine thirty'),
            ('Meet at nine ninety.', 'Meet at nine ninety.'),
            ('Priced at three thirty dollars.', 'Priced at three thirty dollars.'),
        ]:
            self.assertEqual(normalize(source), expected, source)

    def test_literal_language_identifiers_and_ambiguity_stay_literal(self):
        for source in ['One Direction plays tonight.', 'Keep `two plus two`.',
                       'Say exactly five times six.', 'The word three has five letters.',
                       'One by one we help one another.', 'on the one hand',
                       'nineteen ninety nine', 'one two three', 'twenty-first',
                       'one hundred hundred', 'Open https://example.com/five.',
                       'Keep user_name.py.', 'We are over budget.', 'Times are changing.']:
            self.assertEqual(normalize(source), source, source)
        self.assertEqual(normalize('I tried three times today.'), 'I tried 3 times today.')
        self.assertEqual(normalize('The value is 3.14 at 10:30.'), 'The value is 3.14 at 10:30.')

    def test_classifier_only_accepts_strict_aligned_booleans(self):
        self.assertEqual(parse_correction_decisions('{"corrections":[true,false]}', 2), [True, False])
        for source in ['{"corrections":[1]}', '{"corrections":["true"]}', '{"corrections":[true],"word":"fake"}', 'yes', '```json\n{"corrections":[true]}\n```', '{"corrections":[]}', '{"corrections":[true,true]}']:
            self.assertIsNone(parse_correction_decisions(source, 1), source)

    def test_worker_formats_numbers_after_validation_without_model_assets(self):
        cases = [('six times four equals twenty four', '6 × 4 = 24.'),
                 ('two plus two equals five', '2 + 2 = 5.'),
                 ('meet at three thirty pm', 'Meet at 3:30 PM.'),
                 ('x squared plus y squared equals z squared', 'x² + y² = z².'),
                 ('3.14 plus two', '3.14 + 2.'),
                 ('Keep `three plus one`.', 'Keep `three plus one`.')]
        requests = ''.join(json.dumps({'id':str(i),'text':raw})+'\n' for i,(raw,_) in enumerate(cases))
        with tempfile.TemporaryDirectory() as empty:
            result = subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('worker.py')),empty],input=requests,text=True,capture_output=True,timeout=10,check=True)
        rows = {r['id']:r for line in result.stdout.splitlines() if 'id' in (r:=json.loads(line))}
        for i,(_,expected) in enumerate(cases): self.assertEqual(rows[str(i)]['text'],expected)


if __name__ == '__main__': unittest.main()
