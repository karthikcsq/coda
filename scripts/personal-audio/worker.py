"""Local acoustic fine-tuning. Only independently reviewed verbatim labels train.
No audio or labels are sent to the Hub. Preparation downloads public weights.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile
import wave
import uuid

BASE = "openai/whisper-base"
REVISION = "e37978b90ca9030d5170a5c07aadb050351a65bb"


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


def promote(root, model, baseline, current, candidate, trained_audio):
    import math
    if not all(math.isfinite(v) for v in (baseline, current, candidate)) or candidate >= min(baseline, current):
        return False
    name = str(uuid.uuid4())
    destination = root / "models" / name
    model.save_pretrained(destination, safe_serialization=True)
    write_json(root / "active.json", {"model": name, "trainedAudio": sorted(trained_audio)})
    return True


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
    import torch
    from transformers import WhisperProcessor, WhisperForConditionalGeneration
    root = Path(args.root)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    base = root / "base"
    if args.command == "prepare":
        processor = WhisperProcessor.from_pretrained(BASE, revision=REVISION, language="english", task="transcribe")
        model = WhisperForConditionalGeneration.from_pretrained(BASE, revision=REVISION, use_safetensors=True)
        processor.save_pretrained(base)
        model.save_pretrained(base, safe_serialization=True)
        write_json(root / "prepared.json", {"model": BASE, "revision": REVISION})
        return
    os.environ["HF_HUB_OFFLINE"] = "1"
    processor = WhisperProcessor.from_pretrained(base, local_files_only=True, language="english", task="transcribe")
    active = root / "active.json"
    model_dir = base
    if args.command == "transcribe":
        model_dir = root / "models" / str(uuid.UUID(json.loads(active.read_text())["model"]))
    model = WhisperForConditionalGeneration.from_pretrained(model_dir, local_files_only=True, use_safetensors=True)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    model.to(device)
    model.generation_config.forced_decoder_ids = None
    model.generation_config.task = "transcribe"

    def features(audio):
        return processor(audio, sampling_rate=16000, return_tensors="pt").input_features.to(device)

    def transcribe(audio):
        model.eval()
        pieces = []
        # Never silently truncate the app's two-minute recordings.
        with torch.no_grad():
            for start in range(0, len(audio), 30 * 16000):
                tokens = model.generate(features(audio[start:start + 30 * 16000]), task="transcribe", language="english", max_new_tokens=225)
                pieces.append(processor.batch_decode(tokens, skip_special_tokens=True)[0].strip())
        return " ".join(pieces)

    if args.command == "transcribe":
        write_json(Path(args.output), {"text": transcribe(samples(args.audio))})
        return

    source = Path(args.pairs)
    pairs = [json.loads(p.read_text()) for p in source.glob("*.json")]
    # Only short reviewed clips train; long inference recordings are chunked.
    usable = []
    for pair in pairs:
        if not pair.get("reviewedTranscript"):
            continue
            identifier = str(uuid.UUID(pair["id"])).upper()
        audio = samples(source / (identifier + ".m4a"))
        if len(audio) <= 30 * 16000:
            pair["audio"] = audio
            usable.append(pair)
    train, heldout = split_pairs(usable)
    # An edited label must not let audio seen by the active model become a test
    # example. Also exclude byte-identical recordings across transcript groups.
    prior = json.loads(active.read_text()).get("trainedAudio", []) if active.exists() else []
    def fingerprint(pair):
        return hashlib.sha256(pair["audio"].tobytes()).hexdigest()
    trained_audio = {fingerprint(p) for p in train}
    heldout = [p for p in heldout if fingerprint(p) not in trained_audio and fingerprint(p) not in prior]
    if len(heldout) < 3:
        raise ValueError("Review more fresh recordings: fewer than three uncontaminated held-out clips remain.")
    labels = {}
    for pair in train:
        ids = processor.tokenizer(pair["reviewedTranscript"], return_tensors="pt").input_ids
        if ids.shape[-1] > 224:
            raise ValueError("A reviewed transcript is too long for this training run.")
        labels[pair["id"]] = ids[:, 1:].to(device)

    def score():
        errors = total = 0
        for pair in heldout:
            ref = words(pair["reviewedTranscript"])
            errors += distance(ref, words(transcribe(pair["audio"])))
            total += len(ref)
        return errors / max(total, 1)

    baseline = score()
    # Compare to the active personal recognizer too; retraining may not regress it.
    current = baseline
    if active.exists():
        old = model
        model = WhisperForConditionalGeneration.from_pretrained(root / "models" / str(uuid.UUID(json.loads(active.read_text())["model"])), local_files_only=True).to(device)
        current = score()
        del model
        model = old
    torch.manual_seed(42)
    random.seed(42)
    optimizer = torch.optim.AdamW(model.parameters(), lr=1e-5)
    model.config.use_cache = False
    for epoch in range(2):
        random.shuffle(train)
        for pair in train:
            model.train()
            optimizer.zero_grad(set_to_none=True)
            loss = model(input_features=features(pair["audio"]), labels=labels[pair["id"]]).loss
            if not torch.isfinite(loss):
                raise ValueError("Training produced a nonfinite loss; current model retained.")
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
    model.config.use_cache = True
    candidate = score()
    report = {"baselineWER": baseline, "currentWER": current, "candidateWER": candidate,
              "trainCount": len(train), "heldoutCount": len(heldout), "installed": False}
    # Require improvement over both generic Whisper and the current recognizer.
    # Voz outputs are never used as labels or training data.
    report["installed"] = promote(root, model, baseline, current, candidate, trained_audio)
    write_json(root / "report.json", report)


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "train", "transcribe"])
    parser.add_argument("--root", required=True)
    parser.add_argument("--pairs")
    parser.add_argument("--audio")
    parser.add_argument("--output")
    args = parser.parse_args()
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
