"""Model-first dictation cleanup: prompt for spokenly/cleanup-1 and the guard on its output.

The model decides what to fix (fillers, repeats, restarts, spoken corrections,
punctuation, capitals, digits). The guard does not judge style; it only enforces
that the output is the speaker's own words with some removed:
- no added, reordered or replaced words, except spoken numbers rewritten as the
  same value in digits;
- no new symbols beyond ordinary punctuation;
- at most half of the words (minimum 4) removed.
Standard library only; no I/O.
"""
import difflib, re
from spoken_numbers import normalize as spoken_numbers

WORD = re.compile(r"\w+(?:['’]\w+)*", re.UNICODE)
PUNCTUATION = set(".,?!:;'-–—’\n")
UNIT_WORDS = {'dollar', 'dollars', 'percent', 'cent', 'cents'}


def words(text):
    return [m.group().casefold().replace('’', "'") for m in WORD.finditer(text)]


def prompt(raw):
    """spokenly/cleanup-1 format: key: value lines, then 'out:'. Formal keeps final periods."""
    return 'tone: formal\ntext: ' + raw + '\nout:'


def max_tokens(raw):
    return len(raw.split()) * 3 + 32


def _same_number(spoken, written):
    """'two thousand five hundred dollars' -> ['2500'] matches '$2,500' -> ['2500']."""
    converted = [w for w in words(spoken_numbers(' '.join(spoken))) if w not in UNIT_WORDS]
    return bool(written) and all(w.isdigit() for w in written) and converted == written


def guard(raw, out):
    """Return (accepted, reason). Accepts only deletions and same-value digit rewrites."""
    if not isinstance(out, str) or not out.strip():
        return False, 'empty'
    if any(ord(c) < 32 and c not in '\n\t' for c in out):
        return False, 'control character'
    lowered = raw.casefold()
    allowed = PUNCTUATION | set(raw)
    if 'dollar' in lowered: allowed.add('$')
    if 'percent' in lowered: allowed.add('%')
    if any(not c.isalnum() and not c.isspace() and c not in allowed for c in out):
        return False, 'new symbol'
    for match in re.finditer(r'[,.?!:;]{2,}', out):
        if match.group() != '...' and match.group() not in raw:
            return False, 'malformed punctuation'
    if len(out) > len(raw) * 2 + 64:
        return False, 'too long'
    a = words(raw)
    b = words(re.sub(r'(?<=\d),(?=\d{3}\b)', '', out))
    if a and not b:
        return False, 'no words'
    deleted = 0
    for tag, i, j, k, l in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if tag == 'insert':
            return False, 'added words'
        if tag == 'replace':
            if not _same_number(a[i:j], b[k:l]):
                return False, 'replaced words'
        if tag == 'delete':
            deleted += j - i
    if deleted > max(4, 0.5 * len(a)):
        return False, 'removed too much'
    return True, 'model cleanup'
