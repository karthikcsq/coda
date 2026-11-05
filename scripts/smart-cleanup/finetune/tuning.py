"""Shared pieces of Coda's personal fine-tuning: which edits teach cleanup,
how a model is scored, and the gate a tuned model must pass to be installed.
Pure functions except `generate`/`score`, which need an MLX model."""
import collections, difflib, hashlib, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
for path in (HERE, os.path.dirname(HERE)):  # bundle: same folder; repo: parent folder
    if path not in sys.path: sys.path.insert(0, path)
import model_cleanup
from model_cleanup import words

MIN_USABLE_EDITS = 5


def usable_pairs(edits):
    """Training pairs (model input -> user's final text) from edits that are cleanup fixes.

    Kept: the final text is the model input with words removed, plus punctuation,
    capitals and same-value digits (the same rule the runtime guard enforces), and
    its words differ from what Coda pasted. That covers both "the model missed a
    filler or restart" and "the model cut a real word" (the user put it back).
    Skipped: rewording, added content, deleting most of the text. When one input
    was edited several times, the latest edit wins.
    """
    pairs, seen = [], set()
    for edit in sorted(edits, key=lambda e: e.get('created', 0), reverse=True):
        raw = (edit.get('input') or '').strip(); edited = (edit.get('edited') or '').strip()
        if not raw or not edited or words(edited) == words(edit.get('inserted') or ''): continue
        if not model_cleanup.guard(raw, edited)[0]: continue
        key = ' '.join(words(raw))
        if key in seen: continue
        seen.add(key); pairs.append({'raw': raw, 'clean': edited, 'category': 'edit'})
    return pairs


def held_out(raw, every=4):
    """Stable split: about 1 in `every` examples is held out for scoring."""
    return int(hashlib.sha256(' '.join(words(raw)).encode()).hexdigest(), 16) % every == 0


def removed(raw, text):
    """Multiset of raw words absent from text, by alignment."""
    a, b = words(raw), words(text); gone = collections.Counter()
    for tag, i, j, k, l in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if tag in ('delete', 'replace'): gone.update(a[i:j])
    return gone


def judge(raw, gold, output):
    """Score one output as Coda would use it: rejected outputs fall back to the raw text."""
    ok = output == raw or model_cleanup.guard(raw, output)[0]
    final = output if ok else raw
    gold_gone, out_gone = removed(raw, gold), removed(raw, final)
    return {'exact': words(final) == words(gold), 'missed': sum((gold_gone - out_gone).values()),
            'cut': sum((out_gone - gold_gone).values()), 'rejected': not ok}


def summarize(results):
    total = {'n': len(results), 'exact': 0, 'missed': 0, 'cut': 0, 'rejected': 0}
    for r in results:
        for key in ('exact', 'missed', 'cut', 'rejected'): total[key] += int(r[key])
    return total


def generate(model, tokenizer, raw):
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler
    text = ''
    for part in stream_generate(model, tokenizer, prompt=model_cleanup.prompt(raw), max_tokens=model_cleanup.max_tokens(raw), sampler=make_sampler(temp=0.0)):
        text += part.text
    return text.replace('<|endoftext|>', '').strip()


def score(model, tokenizer, rows):
    return summarize([judge(r['raw'], r['clean'], generate(model, tokenizer, r['raw'])) for r in rows])


def gate(base, candidate):
    """Install only when the tuned model is no worse anywhere and learned something.

    Each argument maps 'regression', 'edits_train' and (optionally) 'edits_test'
    to summarize() results. Returns (passed, reasons for rejection)."""
    reasons = []
    b, c = base['regression'], candidate['regression']
    if c['cut'] > b['cut']: reasons.append(f"cuts more real words on the regression set ({c['cut']} vs {b['cut']})")
    if c['exact'] < b['exact'] - 1: reasons.append(f"fewer exact on the regression set ({c['exact']} vs {b['exact']})")
    learned = candidate['edits_train']['exact'] > base['edits_train']['exact']
    test_b, test_c = base.get('edits_test'), candidate.get('edits_test')
    if test_b and test_b['n']:
        if test_c['exact'] < test_b['exact']: reasons.append(f"worse on held-out edits ({test_c['exact']} vs {test_b['exact']})")
        if test_c['cut'] > test_b['cut']: reasons.append(f"cuts more real words on held-out edits ({test_c['cut']} vs {test_b['cut']})")
        learned = learned or test_c['exact'] > test_b['exact']
    if not learned: reasons.append('no improvement on your edits')
    return not reasons, reasons
