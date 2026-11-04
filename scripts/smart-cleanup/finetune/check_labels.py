"""Check labeled cleanup examples against Coda's runtime guard.

Usage: python3 check_labels.py <file.jsonl> [...]
Each line: {"raw": ..., "clean": ..., optional "category"/"id"/"note"}.
Exits non-zero and lists every example whose clean text the guard would reject.
"""
import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from model_cleanup import guard

bad = total = 0
for path in sys.argv[1:]:
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        if not line.strip(): continue
        total += 1
        try:
            row = json.loads(line); raw, clean = row['raw'], row['clean']
        except (ValueError, KeyError) as error:
            print(f'{path}:{n}: invalid line ({error})'); bad += 1; continue
        if clean == raw: continue
        ok, why = guard(raw, clean)
        if not ok:
            bad += 1
            print(f'{path}:{n}: {why}\n  raw:   {raw}\n  clean: {clean}')
print(f'{total - bad}/{total} examples pass')
sys.exit(1 if bad else 0)
