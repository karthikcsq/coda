"""Check source-ready then background-model-ready, using synthetic text only."""
import json, pathlib, subprocess, sys, time

base = pathlib.Path.home() / 'Library/Application Support/Coda/SmartCleanup/v1'
p = subprocess.Popen([str(base/'runtime/bin/python'), str(pathlib.Path(__file__).with_name('worker.py')), str(base/'model')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
start = time.perf_counter()
try:
    initial = json.loads(p.stdout.readline())
    source_ready = time.perf_counter()-start
    assert initial.get('ready'), initial
    # Common cleanup deliberately does not load Qwen. An unsupported correction
    # cue starts it lazily while the first request returns native text at once.
    p.stdin.write(json.dumps(dict(id='lazy',text='They actually said no.'))+'\n'); p.stdin.flush()
    first=None; model={}
    while first is None or not model.get('model_ready'):
        event=json.loads(p.stdout.readline())
        if event.get('id') == 'lazy': first=event
        if event.get('ready'): model=event
        assert not model.get('model_error'),model
    model_ready = time.perf_counter()-start
    assert first['text']=='They actually said no.', first
    rows = []
    for i, raw in enumerate(['They actually said no.', 'I am sorry you waited.']):
        p.stdin.write(json.dumps(dict(id=i, text=raw))+'\n'); p.stdin.flush()
        row = json.loads(p.stdout.readline())
        while row.get('ready'): row=json.loads(p.stdout.readline())
        assert row.get('id') == i and row.get('text') == raw, row
        rows.append(row)
    result = dict(source_ready_seconds=source_ready, model_ready_seconds=model_ready, lazy_first_response=first, rows=rows)
    pathlib.Path(sys.argv[1]).write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))
finally:
    p.stdin.close()
    try: p.wait(timeout=15)
    except subprocess.TimeoutExpired: p.kill(); p.wait()
