"""Build train/valid/test sets in MLX chat format from labeled examples.

Usage: python3 split.py <synthetic.jsonl> <private_labeled.jsonl> <out_dir> [--edit-repeat N] [extra_train.jsonl ...]
The output directory receives private data (the user's dictations); keep it
outside the repository. The split is deterministic (fixed seed), and extra
files only add training rows, so the held-out set never changes.
- test:  40% of the user's dictations (stratified by needs_edit) + 15% of synthetic (per category)
- valid: 10% of synthetic (per category)
- train: everything else plus extra files; dictations that needed edits are repeated N times (default 3)
"""
import difflib, json, os, random, sys, collections
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import model_cleanup

def load(path, source):
    rows = []
    for line in open(path, encoding='utf-8'):
        if line.strip():
            row = json.loads(line); row['source'] = source; rows.append(row)
    return rows

def chat(row):
    user = model_cleanup.prompt(row['raw'])
    assert user.endswith('\nout:')
    # The chat template appends '\nout:' to the user turn and ' ' + answer + EOS.
    return {'messages': [{'role': 'user', 'content': user[:-len('\nout:')]}, {'role': 'assistant', 'content': row['clean']}]}

def main():
    synthetic_path, private_path, out = sys.argv[1:4]
    rest = sys.argv[4:]; repeat = 3
    if rest[:1] == ['--edit-repeat']: repeat = int(rest[1]); rest = rest[2:]
    rng = random.Random(20261104)
    synthetic = load(synthetic_path, 'synthetic'); private = load(private_path, 'dictation')
    train, valid, test = [], [], []
    groups = collections.defaultdict(list)
    for row in synthetic: groups[row['category']].append(row)
    for _, rows in sorted(groups.items()):
        rng.shuffle(rows); n_test = round(len(rows) * 0.15); n_valid = max(1, round(len(rows) * 0.10))
        test += rows[:n_test]; valid += rows[n_test:n_test + n_valid]; train += rows[n_test + n_valid:]
    for flag in (True, False):
        rows = [r for r in private if bool(r.get('needs_edit')) == flag]; rng.shuffle(rows)
        n_test = round(len(rows) * 0.4); test += rows[:n_test]
        train += rows[n_test:] * (repeat if flag else 1)
    # Extra rows may be written after seeing held-out failures; drop any that
    # nearly copy a held-out or validation example so scores stay honest.
    held = [model_cleanup.words(r['raw']) for r in test + valid]
    def leaks(raw):
        a = model_cleanup.words(raw)
        return any(difflib.SequenceMatcher(a=a, b=b, autojunk=False).ratio() >= 0.6 for b in held)
    for path in rest:
        extra = load(path, 'synthetic'); kept = [r for r in extra if not leaks(r['raw'])]
        print(f'{path}: kept {len(kept)}/{len(extra)} (dropped near-copies of held-out examples)')
        train += kept
    rng.shuffle(train)
    os.makedirs(out, exist_ok=True)
    for name, rows in (('train', train), ('valid', valid)):
        with open(os.path.join(out, name + '.jsonl'), 'w', encoding='utf-8') as f:
            for row in rows: f.write(json.dumps(chat(row), ensure_ascii=False) + '\n')
    # The scorer reads raw/clean/category directly; MLX's --test is not used.
    with open(os.path.join(out, 'heldout.jsonl'), 'w', encoding='utf-8') as f:
        for row in test: f.write(json.dumps({k: row.get(k) for k in ('raw', 'clean', 'category', 'source', 'needs_edit')}, ensure_ascii=False) + '\n')
    count = lambda rows: dict(collections.Counter(r['source'] for r in rows))
    print('train', len(train), count(train), '| valid', len(valid), count(valid), '| test', len(test), count(test))

main()
