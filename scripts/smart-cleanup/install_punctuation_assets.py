"""Install already-downloaded, hash-checked optional assets; never downloads."""
import hashlib, json, pathlib, shutil, sys

scratch = pathlib.Path(sys.argv[1]).resolve()
evidence = pathlib.Path(__file__).resolve().parents[2]/'benchmarks/cleanup-reuse-2026-10-26/punctuation-tagger'
inventory = json.loads((evidence/'inventory.json').read_text())
selected = [r for r in inventory['files'] if r['path'].startswith('runtime-minimal/') or r['path'] in {
    'model/onnx/model_quantized.onnx', 'model/tokenizer.json', 'model/config.json', 'model/LICENSE-2.0.txt', 'model/README.md'}]
target = pathlib.Path.home()/'Library/Application Support/Coda/SmartCleanup/v1/punctuation'
stage = target.with_name('punctuation-staged-0.4.10')
assert not target.exists() and not stage.exists(), 'Existing assets must be inspected, never overwritten'
for row in selected:
    path = scratch/row['path']
    assert path.is_file() and not path.is_symlink(), path
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], path
stage.mkdir()
rows = []
for row in selected:
    relative = row['path'].replace('runtime-minimal/', 'runtime/', 1)
    path = stage/relative; path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(scratch/row['path'], path)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], path
    rows.append(dict(path=relative, bytes=path.stat().st_size, sha256=row['sha256']))
manifest = dict(model='Horizon-Labs/punctuation-restoration-small', revision='ee31fdfc5304f876ea3b0dd72d30eda7e940b2b1', runtime='onnxruntime 1.31.0 official cp313 macOS arm64 wheel', files=rows)
(stage/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
stage.rename(target)
print(json.dumps(dict(installed=str(target), files=len(rows), bytes=sum(r['bytes'] for r in rows))))
