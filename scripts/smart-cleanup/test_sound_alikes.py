import json, os, subprocess, sys, unittest
import worker
from worker import valid_sound_alike_proposals, review_sound_alikes


class SoundAlikeReview(unittest.TestCase):
    def test_proposals_are_bounded_and_typed(self):
        good = {'heard': 'join the google me call', 'fixed': 'join the Google Meet call'}
        self.assertTrue(valid_sound_alike_proposals([good]))
        for bad in [[], [good] * 7, [{'heard': 'x'}], [{**good, 'extra': 'y'}], [{'heard': 'same', 'fixed': 'same'}],
                    [{'heard': 'a' * 481, 'fixed': 'b'}], [{'heard': 1, 'fixed': 'b'}], 'text']:
            self.assertFalse(valid_sound_alike_proposals(bad), bad)

    def test_a_proposal_is_accepted_only_when_the_fixed_passage_is_more_likely(self):
        scores = {'talk to you later': -10.0, 'talk to you LaTeX': -25.0,
                  'compile the latex file': -20.0, 'compile the LaTeX file': -18.0}
        original = worker.passage_logprob
        worker.passage_logprob = lambda backend, text: scores[text]
        try:
            proposals = [{'heard': 'talk to you later', 'fixed': 'talk to you LaTeX'},
                         {'heard': 'compile the latex file', 'fixed': 'compile the LaTeX file'}]
            import time
            self.assertEqual(review_sound_alikes({}, proposals, time.perf_counter()), [False, True])
            # Out of time means no verdict at all, never a partial one.
            self.assertIsNone(review_sound_alikes({}, proposals, time.perf_counter() - 10))
        finally:
            worker.passage_logprob = original

    def test_worker_without_model_returns_no_verdict(self):
        here = os.path.dirname(os.path.abspath(__file__))
        request = {'id': 'r1', 'text': 'join the google me call', 'kind': 'sound_alikes',
                   'proposals': [{'heard': 'join the google me call', 'fixed': 'join the Google Meet call'}]}
        result = subprocess.run([sys.executable, os.path.join(here, 'worker.py'), '/nonexistent-model'],
                                input=json.dumps(request) + '\n', capture_output=True, text=True, timeout=60, cwd=here)
        replies = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        answer = next(r for r in replies if r.get('id') == 'r1')
        self.assertEqual(answer, {'id': 'r1', 'accepted': False, 'decisions': None})

    def test_warm_request_starts_model_loading_and_answers_immediately(self):
        here = os.path.dirname(os.path.abspath(__file__))
        request = {'id': 'w1', 'text': 'warm', 'kind': 'warm'}
        result = subprocess.run([sys.executable, os.path.join(here, 'worker.py'), '/nonexistent-model'],
                                input=json.dumps(request) + '\n', capture_output=True, text=True, timeout=60, cwd=here)
        replies = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        self.assertIn({'id': 'w1', 'accepted': True, 'decisions': []}, replies)


if __name__ == '__main__':
    unittest.main()
