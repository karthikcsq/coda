"""Local acoustic fine-tuning. Only independently reviewed verbatim labels train.
No audio or labels leave this Mac. Preparation copies the existing Voz bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import wave
import uuid



def words(text):
    return re.findall(r"\w+", text.casefold())


def distance(reference, hypothesis):
    prev = list(range(len(hypothesis) + 1))
    for i, a in enumerate(reference, 1):
        row = [i]
        for j, b in enumerate(hypothesis, 1):
            row.append(min(row[-1] + 1, prev[j] + 1, prev[j-1] + (a != b)))
        prev = row
    return prev[-1]


def split_pairs(pairs):
    # Group identical labels to prevent repeated dictations crossing the split.
    groups = {}
    for pair in pairs:
        label = pair.get("reviewedTranscript")
        if label and words(label):
            key = " ".join(words(label))
            groups.setdefault(key, []).append(pair)
    keys = sorted(groups, key=lambda k: hashlib.sha256(k.encode()).hexdigest())
    if len(keys) < 15:
        raise ValueError("Review at least 15 different dictations before training.")
    # Permanent partition: adding recordings never moves earlier training data
    # into the held-out set on subsequent runs.
    test_keys = [k for k in keys if int(hashlib.sha256(k.encode()).hexdigest(), 16) % 5 == 0]
    train_keys = [k for k in keys if k not in test_keys]
    if len(test_keys) < 3 or len(train_keys) < 10:
        raise ValueError("Review more distinct clips: need 10 training and 3 held-out transcript groups.")
    return ([p for k in train_keys for p in groups[k]],
            [p for k in test_keys for p in groups[k]])


def write_json(path, value):
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value))
    os.chmod(temp, 0o600)
    temp.replace(path)


def accepts(baseline, current, candidate):
    import math
    return all(math.isfinite(v) and v >= 0 for v in (baseline,current,candidate)) and candidate < min(baseline,current)


def samples(path):
    import numpy as np
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "audio.wav"
        subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(path), str(wav)],
                       check=True, capture_output=True)
        with wave.open(str(wav)) as f:
            audio = np.frombuffer(f.readframes(f.getnframes()), dtype="<i2").astype("float32") / 32768
    if not len(audio):
        raise ValueError("Empty recording.")
    return audio


def main(args):
    import numpy as np
    import torch
    import shutil
    from voz import decoder, aligned_features, tokenize, patch_projection
    root = Path(args.root)
    base = root / "base"
    active = root / "active.json"
    if args.command == "prepare":
        source = Path(args.source)
        # Preparation copies the existing Voz bundle; no substitute model download.
        for name in ["encoder.mlmodelc", "mel.mlmodelc", "decoder.mlmodelc", "meta.json", "vocab.json", "embedding.f16"]:
            src = source / name
            if not src.exists():
                raise ValueError("Prepare the generic Voz model before personal training.")
            if src.is_dir(): shutil.copytree(src, base / name, dirs_exist_ok=True)
            else:
                base.mkdir(parents=True, exist_ok=True, mode=0o700)
                shutil.copy2(src, base / name)
        decoder(base / "decoder.mlmodelc")
        write_json(root / "prepared.json", {"backend": "voz-v0.4.0", "adaptation": "decoder-output-projection"})
        return
    source = Path(args.pairs)
    pairs = [json.loads(p.read_text()) for p in source.glob("*.json")]
    usable = []
    for pair in pairs:
        if not pair.get("reviewedTranscript"): continue
        identifier = str(uuid.UUID(pair["id"])).upper()
        pair["audioPath"] = str(source / (identifier + ".m4a"))
        audio = samples(pair["audioPath"])
        if len(audio) <= 240000:
            pair["audio"] = audio
            usable.append(pair)
    train, heldout = split_pairs(usable)
    previous = json.loads(active.read_text()) if active.exists() else None
    def fingerprint(pair): return hashlib.sha256(pair["audio"].tobytes()).hexdigest()
    train_hashes = {fingerprint(p) for p in train}
    prior_hashes = set(previous.get("trainedAudio", [])) if previous else set()
    heldout = [p for p in heldout if fingerprint(p) not in train_hashes | prior_hashes]
    if len(heldout) < 3: raise ValueError("Review more fresh clips: at least three uncontaminated held-out recordings are needed.")

    def score(directory):
        with tempfile.TemporaryDirectory(dir=root) as temp:
            manifest = Path(temp) / "clips.json"
            output = Path(temp) / "results.json"
            write_json(manifest, [{"id":p["id"], "audio":p["audioPath"]} for p in heldout])
            process = subprocess.Popen([args.tool, str(directory), str(manifest), str(output)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                process.wait(timeout=600)
                if process.returncode != 0:
                    raise ValueError("The candidate could not run in Voz. Your current model was kept.")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
            results = json.loads(output.read_text())
        errors = sum(distance(words(p["reviewedTranscript"]), words(results[p["id"]])) for p in heldout)
        return errors / max(1,sum(len(words(p["reviewedTranscript"])) for p in heldout))

    baseline = score(base)
    current = score(root / "models" / str(uuid.UUID(previous["model"]))) if previous else baseline
    model = decoder(base / "decoder.mlmodelc")
    vocab = json.loads((base / "vocab.json").read_text())
    features = []
    for pair in train:
        features.append(aligned_features(base, pair["audio"], tokenize(pair["reviewedTranscript"], vocab), model))
    original_w = model.weight.detach().clone()
    original_b = model.bias.detach().clone()
    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-5)
    torch.manual_seed(42)
    for epoch in range(2):
        for hidden, labels, residual in features:
            optimizer.zero_grad(set_to_none=True)
            loss = torch.nn.functional.cross_entropy((model(hidden)+residual)[:,:8193], labels)
            loss = loss + .1 * ((model.weight-original_w).square().mean() + (model.bias-original_b).square().mean())
            if not torch.isfinite(loss): raise ValueError("Nonfinite training loss; current Voz model kept.")
            loss.backward()
            model.weight.grad[-5:] = 0; model.bias.grad[-5:] = 0
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
    name = str(uuid.uuid4())
    candidate_dir = root / "models" / name
    shutil.copytree(base, candidate_dir)
    try:
        patch_projection(candidate_dir / "decoder.mlmodelc", model.weight.detach().numpy(), model.bias.detach().numpy())
        write_json(candidate_dir / "CODA_ADAPTATION.json", {"backend":"voz-v0.4.0", "method":"decoder-output-projection",
            "sourceDecoderSHA256":hashlib.sha256((base / "decoder.mlmodelc/weights/weight.bin").read_bytes()).hexdigest(),
            "trainingClips":len(train), "heldoutClips":len(heldout)})
        # The gate runs the candidate through the actual Swift Voz SDK, including
        # model load, tokenization, timing and window stitching. No Python proxy.
        candidate = score(candidate_dir)
        installed = accepts(baseline, current, candidate)
        if installed:
            write_json(active, {"backend":"voz-v0.4.0", "model":name, "trainedAudio":sorted(train_hashes)})
        else: shutil.rmtree(candidate_dir)
    except BaseException:
        shutil.rmtree(candidate_dir, ignore_errors=True)
        raise
    write_json(root / "report.json", {"baselineWER":baseline, "currentWER":current, "candidateWER":candidate,
        "trainCount":len(train), "heldoutCount":len(heldout), "installed":installed})


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "train"])
    parser.add_argument("--root", required=True)
    parser.add_argument("--pairs")
    parser.add_argument("--source")
    parser.add_argument("--tool")
    args = parser.parse_args()
    import signal
    def cancelled(signum, frame):
        raise KeyboardInterrupt("Audio training cancelled")
    signal.signal(signal.SIGTERM, cancelled)
    import fcntl
    root = Path(args.root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (root / "operation.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Another audio model operation is running.")
        error_file = root / "error.json"
        error_file.unlink(missing_ok=True)
        try:
            main(args)
        except Exception as error:
            message = str(error) if isinstance(error, ValueError) else "Audio training failed. Check runtime setup and available memory; the current model was retained."
            write_json(error_file, {"message": message})
            raise
