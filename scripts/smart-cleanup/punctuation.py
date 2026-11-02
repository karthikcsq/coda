"""Offline punctuation labels rendered onto source offsets; no text generation."""
import json, os, pathlib, re, sys


def eligible(raw, candidate):
    # Keep ASR's existing sentence boundaries and explicit formatting literal.
    without_decimals = re.sub(r'(?<=\d)\.(?=\d)', '', raw)
    return bool(candidate.strip() and '\n' not in candidate
                and not re.search(r'[.!?]|\b(?:comma|colon|period|question mark|exclamation mark|new paragraph|new line)\b', without_decimals, re.I))


def render(text, offsets, predictions, labels):
    """Only insert finite punctuation at complete word boundaries."""
    ends = {}
    for (start, end), prediction in zip(offsets, predictions):
        if 0 <= start < end <= len(text):
            ends[end] = labels.get(str(int(prediction)), '0')
    out, previous = [], 0
    for end, label in sorted(ends.items()):
        if label not in {'.', ',', '?', ':', '-'}:
            continue
        if not text[end-1].isalnum():
            continue
        if end < len(text) and not text[end].isspace():
            continue
        # Existing punctuation after whitespace also owns this boundary.
        following = text[end:].lstrip()
        if following[:1] and following[0] in '.,?!:;-–—':
            continue
        out.append(text[previous:end]+(' -' if label == '-' else label))
        previous = end
    return ''.join(out)+text[previous:]


class Punctuation:
    def __init__(self, directory):
        root = pathlib.Path(directory)
        # The official runtime reads this once during library initialization.
        os.environ['ORT_DISABLE_TELEMETRY'] = '1'
        sys.path.insert(0, str(root/'runtime'))
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        ort.disable_telemetry_events()
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(root/'model/onnx/model_quantized.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
        self.tokenizer = Tokenizer.from_file(str(root/'model/tokenizer.json'))
        self.labels = json.loads((root/'model/config.json').read_text())['id2label']
        self.np = np

    def restore(self, text):
        encoded = self.tokenizer.encode(text)
        # Preserve long input rather than introducing chunk-boundary guesses.
        if len(encoded.ids) > 1024:
            return text
        ids = self.np.array([encoded.ids], dtype=self.np.int64)
        logits = self.session.run(None, {'input_ids': ids, 'attention_mask': self.np.ones_like(ids)})[0][0]
        return render(text, encoded.offsets, logits.argmax(-1), self.labels)
