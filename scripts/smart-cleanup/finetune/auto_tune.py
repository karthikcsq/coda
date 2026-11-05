"""Coda's automatic personal fine-tuning. Local only; no network.

Usage: python auto_tune.py <SmartCleanup dir>
Reads   <dir>/edits/*.json          edits Coda saw the user make after dictation
Trains  a LoRA adapter on the open-weight model <dir>/v1/cleanup (8-bit) using the
        usable edits plus the bundled regression set (regression.jsonl)
Scores  open-weight vs tuned on held-out regression examples and held-out edits
Installs the fused 8-bit result as <dir>/v1/cleanup-personal only if tuning.gate passes
Writes  <dir>/tuning/status.json for the app (state, counts, scores, reasons)
Every run trains from the open-weight model on all usable edits, so tuning never
compounds earlier mistakes. Only one run at a time (lock file).
"""
import fcntl, json, math, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tuning
import model_cleanup

ENV = dict(os.environ, HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1', TOKENIZERS_PARALLELISM='false')


def chat(row):
    user = model_cleanup.prompt(row['raw'])[:-len('\nout:')]  # the chat template re-adds '\nout:'
    return json.dumps({'messages': [{'role': 'user', 'content': user}, {'role': 'assistant', 'content': row['clean']}]}, ensure_ascii=False)


def write_jsonl(path, rows):
    with open(path, 'w', encoding='utf-8') as f:
        for row in rows: f.write(chat(row) + '\n')


def load_json_dir(path):
    rows = []
    for name in sorted(os.listdir(path)) if os.path.isdir(path) else []:
        if name.endswith('.json'):
            try:
                with open(os.path.join(path, name), encoding='utf-8') as f: rows.append(json.load(f))
            except (OSError, ValueError):
                pass
    return rows


def evaluate(model_dir, sets):
    import mlx.core as mx
    from mlx_lm import load
    model, tokenizer = load(model_dir)
    result = {name: tuning.score(model, tokenizer, rows) for name, rows in sets.items() if rows}
    del model; mx.clear_cache()
    return result


def main():
    root = sys.argv[1]
    base = os.path.join(root, 'v1', 'cleanup'); personal = os.path.join(root, 'v1', 'cleanup-personal')
    work = os.path.join(root, 'tuning'); os.makedirs(work, mode=0o700, exist_ok=True)
    status_path = os.path.join(work, 'status.json')
    lock = open(os.path.join(work, 'lock'), 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0  # another run is in progress
    edits = load_json_dir(os.path.join(root, 'edits'))
    status = {'state': 'running', 'started': time.time(), 'edits_seen': len(edits),
              'last_edit_created': max((e.get('created', 0) for e in edits), default=0)}
    def write(**fields):
        status.update(fields)
        tmp = status_path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f: json.dump(status, f)
        os.replace(tmp, status_path)
    write()
    try:
        pairs = tuning.usable_pairs(edits)
        status['edits_used'] = len(pairs)
        if not os.path.isdir(base):
            write(state='failed', message='Open-weight cleanup model is not installed.', finished=time.time()); return 1
        if len(pairs) < tuning.MIN_USABLE_EDITS:
            write(state='waiting', finished=time.time(),
                  message=f'{len(pairs)} of your edits are cleanup fixes; tuning starts at {tuning.MIN_USABLE_EDITS}.'); return 0
        regression = [json.loads(l) for l in open(os.path.join(HERE, 'regression.jsonl'), encoding='utf-8') if l.strip()]
        reg_test = [r for r in regression if tuning.held_out(r['raw'])]
        reg_train = [r for r in regression if not tuning.held_out(r['raw'])]
        hold = len(pairs) >= 8
        edits_test = [p for p in pairs if hold and tuning.held_out(p['raw'])]
        edits_train = [p for p in pairs if p not in edits_test]
        data = os.path.join(work, 'data'); os.makedirs(data, exist_ok=True)
        train = edits_train * 3 + reg_train
        write_jsonl(os.path.join(data, 'train.jsonl'), train)
        write_jsonl(os.path.join(data, 'valid.jsonl'), reg_test[:24])
        iters = max(60, min(200, math.ceil(2 * len(train) / 8)))
        config = {'fine_tune_type': 'lora', 'mask_prompt': True, 'num_layers': -1, 'batch_size': 8, 'iters': iters,
                  'learning_rate': 3e-5, 'steps_per_report': 20, 'steps_per_eval': iters, 'val_batches': 2,
                  'save_every': iters, 'max_seq_length': 1024, 'seed': 20261104,
                  'lora_parameters': {'rank': 16, 'scale': 20.0, 'dropout': 0.05,
                                      'keys': ['self_attn.q_proj', 'self_attn.k_proj', 'self_attn.v_proj', 'self_attn.o_proj',
                                               'mlp.gate_proj', 'mlp.up_proj', 'mlp.down_proj']}}
        config_path = os.path.join(work, 'lora.yaml')
        with open(config_path, 'w') as f: json.dump(config, f)  # JSON is valid YAML
        adapters = os.path.join(work, 'adapters'); candidate = os.path.join(work, 'candidate')
        for path in (adapters, candidate): shutil.rmtree(path, ignore_errors=True)
        write(message=f'Training on {len(edits_train)} of your edits ({iters} steps)…')
        quiet = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=ENV, check=True)
        subprocess.run([sys.executable, '-m', 'mlx_lm', 'lora', '-c', config_path, '--train', '--model', base,
                        '--data', data, '--adapter-path', adapters], timeout=3600, **quiet)
        subprocess.run([sys.executable, '-m', 'mlx_lm', 'fuse', '--model', base, '--adapter-path', adapters,
                        '--save-path', candidate], timeout=900, **quiet)
        write(message='Checking the tuned model against the open-weight model…')
        sets = {'regression': reg_test, 'edits_train': edits_train, 'edits_test': edits_test}
        before = evaluate(base, sets); after = evaluate(candidate, sets)
        passed, reasons = tuning.gate(before, after)
        if passed:
            previous = os.path.join(work, 'previous-personal')
            shutil.rmtree(previous, ignore_errors=True)
            if os.path.isdir(personal): os.replace(personal, previous)
            os.replace(candidate, personal)
            shutil.rmtree(previous, ignore_errors=True)
            write(state='installed', finished=time.time(), before=before, after=after, reasons=[],
                  message=f'Tuned on {len(edits_train)} of your edits and installed.')
        else:
            shutil.rmtree(candidate, ignore_errors=True)
            write(state='rejected', finished=time.time(), before=before, after=after, reasons=reasons,
                  message='Tuned model not installed: ' + '; '.join(reasons) + '.')
        shutil.rmtree(adapters, ignore_errors=True); shutil.rmtree(data, ignore_errors=True)
        return 0
    except Exception as error:  # never include edit text in the status
        write(state='failed', finished=time.time(), message=f'Tuning failed ({type(error).__name__}).')
        return 1


if __name__ == '__main__':
    sys.exit(main())
