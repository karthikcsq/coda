"""Fresh synthetic bullet-list utility check against the installed app worker."""
import json, pathlib, re, statistics, subprocess, time, sys

repo = pathlib.Path(__file__).resolve().parents[2]
base = pathlib.Path.home()/'Library/Application Support/Coda/SmartCleanup/v1'
cases = [
    ('agenda', 'Agenda: review the draft, test the build, and ship the patch.', 3),
    ('shopping-heading', 'Shopping list: milk, eggs, and bread.', 3),
    ('named-groups', 'The groups are software, math, and business.', 3),
    ('daily-tasks', 'My tasks for today: review the budget, call the supplier, and send the report.', 3),
    ('bullet-points', 'Bullet points: keep the original words, remove speech fillers, and add punctuation.', 3),
    ('unpunctuated-count', 'we need three items apples pears and rice', 3),
    ('shopping-is', 'My shopping list is milk, eggs, and bread.', 3),
    ('groceries-heading', 'Groceries: milk, eggs, and bread.', 3),
    ('spoken-comma-list', 'make a bulleted list milk comma eggs comma bread', 3),
    ('existing-bullets', '- Milk\n- Eggs\n- Bread', 3),
    ('explicit-markers', 'Bullet point milk. Bullet point eggs. Bullet point bread.', 3),
]

def words(text):
    return re.findall(r"\w+(?:['’]\w+)*", text.casefold())

worker = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else repo/'build/Coda.app/Contents/Resources/smart_cleanup_worker.py'
output = pathlib.Path(sys.argv[2]) if len(sys.argv)>2 else pathlib.Path(__file__).with_name('installed-bullets.json')
p = subprocess.Popen([str(base/'runtime/bin/python'), str(worker), str(base/'model')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
rows = []
try:
    status = json.loads(p.stdout.readline())
    while not status.get('punctuation_ready') and not status.get('punctuation_error'):
        status = json.loads(p.stdout.readline())
    assert status.get('punctuation_ready'), status
    for name, raw, expected in cases:
        started = time.perf_counter()
        p.stdin.write(json.dumps(dict(id=name, text=raw))+'\n'); p.stdin.flush()
        row = json.loads(p.stdout.readline())
        while row.get('ready'): row = json.loads(p.stdout.readline())
        assert row.get('id') == name, row
        count = len(re.findall(r'(?m)^\s*[-*•]\s+', row['text']))
        reference=raw
        if name=='spoken-comma-list': reference=re.sub(r'\bcomma\b', '', reference)
        if name=='explicit-markers': reference=re.sub(r'\bbullet point\b', '', reference,flags=re.I)
        row.update(case=name, raw=raw, expected_bullets=expected, actual_bullets=count,
                   bullet_check=count==expected, words_preserved=words(reference)==words(row['text']),
                   wall_ms=(time.perf_counter()-started)*1000)
        rows.append(row)
        print(name, count, repr(row['text']), flush=True)
    result = dict(summary=dict(cases=len(rows), bullet_checks=sum(r['bullet_check'] for r in rows), word_checks=sum(r['words_preserved'] for r in rows), median_ms=statistics.median(r['wall_ms'] for r in rows)), rows=rows)
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result['summary']))
    assert all(r['bullet_check'] and r['words_preserved'] for r in rows)
finally:
    p.stdin.close()
    try: p.wait(timeout=15)
    except subprocess.TimeoutExpired: p.kill(); p.wait()
