"""Score a cleanup model on held-out examples.

Usage: python score.py <model_dir> <heldout.jsonl> [--adapter <dir>] [--out results.jsonl]
Runs the model exactly as Coda's worker does (same prompt, greedy decoding, guard).
Metrics, per source and category:
- exact: guard-accepted output equals the label, ignoring case, punctuation and spacing
- missed: words the label removes that the output kept
- cut: words the label keeps that the output removed (content loss)
- rejected: outputs the runtime guard would reject (Coda falls back to rules)
"""
import argparse, collections, difflib, json, os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import model_cleanup
from model_cleanup import words

def removed(raw, text):
    """Multiset of raw words absent from text, by alignment."""
    a, b = words(raw), words(text); gone = collections.Counter()
    for tag, i, j, k, l in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if tag in ('delete', 'replace'): gone.update(a[i:j])
    return gone

def main():
    p = argparse.ArgumentParser(); p.add_argument('model'); p.add_argument('heldout')
    p.add_argument('--adapter'); p.add_argument('--out')
    args = p.parse_args()
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler
    model, tok = load(args.model, adapter_path=args.adapter)
    sampler = make_sampler(temp=0.0)
    rows = [json.loads(l) for l in open(args.heldout, encoding='utf-8') if l.strip()]
    stats = collections.defaultdict(lambda: collections.Counter())
    out_file = open(args.out, 'w', encoding='utf-8') if args.out else None
    for row in rows:
        raw, gold = row['raw'], row['clean']; start = time.perf_counter(); text = ''
        for part in stream_generate(model, tok, prompt=model_cleanup.prompt(raw), max_tokens=model_cleanup.max_tokens(raw), sampler=sampler):
            text += part.text
        text = text.replace('<|endoftext|>', '').strip(); secs = time.perf_counter() - start
        ok, why = model_cleanup.guard(raw, text) if text != raw else (True, 'unchanged')
        final = text if ok else raw
        gold_gone, out_gone = removed(raw, gold), removed(raw, final)
        missed = sum((gold_gone - out_gone).values()); cut = sum((out_gone - gold_gone).values())
        exact = words(final) == words(gold)
        for key in ('all', row.get('source', '?'), f"{row.get('source', '?')}:{row.get('category', '?')}"):
            s = stats[key]; s['n'] += 1; s['exact'] += exact; s['rejected'] += not ok
            s['missed'] += missed; s['cut'] += cut; s['cut_examples'] += cut > 0; s['ms'] += round(secs * 1000)
        if out_file:
            out_file.write(json.dumps({'raw': raw, 'gold': gold, 'out': text, 'guard': why, 'exact': exact, 'missed': missed, 'cut': cut, 'category': row.get('category'), 'source': row.get('source')}, ensure_ascii=False) + '\n')
    print(f"{'set':34} {'n':>4} {'exact':>7} {'missed':>7} {'cut':>5} {'cut ex':>7} {'reject':>7} {'avg ms':>7}")
    for key in sorted(stats, key=lambda k: (k != 'all', ':' in k, k)):
        s = stats[key]
        print(f"{key:34} {s['n']:4} {s['exact'] / s['n']:7.1%} {s['missed']:7} {s['cut']:5} {s['cut_examples']:7} {s['rejected']:7} {s['ms'] / s['n']:7.0f}")

main()
