"""Bounded English number/notation formatting; never evaluates an expression."""
import re

SMALL = dict(zip('zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split(), range(20)))
TENS = dict(zip('twenty thirty forty fifty sixty seventy eighty ninety'.split(), range(20, 100, 10)))
SCALES = {'thousand': 1000, 'million': 1000000, 'billion': 1000000000}
NUMBER_WORDS = set(SMALL) | set(TENS) | set(SCALES) | {'hundred', 'and', 'point'}
LEXEME = re.compile(r"\d+(?:\.\d+)?|[A-Za-z]+(?:['’][A-Za-z]+)?")


def _under_hundred(words):
    if len(words) == 1:
        return SMALL.get(words[0], TENS.get(words[0]))
    if len(words) == 2 and words[0] in TENS and 0 < SMALL.get(words[1], 0) < 10:
        return TENS[words[0]] + SMALL[words[1]]
    return None


def _group(words):
    if 'hundred' not in words:
        return _under_hundred(words)
    if words.count('hundred') != 1 or words.index('hundred') != 1 or not 1 <= SMALL.get(words[0], 0) <= 9:
        return None
    tail = words[2:]
    if tail[:1] == ['and']:
        tail = tail[1:]
        if not tail: return None
    rest = _under_hundred(tail) if tail else 0
    return None if rest is None else SMALL[words[0]] * 100 + rest


def _integer(words):
    total, start, previous = 0, 0, 10**12
    for i, word in enumerate(words):
        if word not in SCALES: continue
        scale = SCALES[word]
        part = _group(words[start:i])
        if part is None or part == 0 or scale >= previous: return None
        total += part * scale; start = i + 1; previous = scale
    tail = words[start:]
    if start and tail[:1] == ['and']: tail = tail[1:]
    rest = _group(tail) if tail else 0
    if rest is None or (start == 0 and not tail): return None
    return total + rest


def _number(words):
    if 'point' in words:
        if words.count('point') != 1: return None
        split = words.index('point'); before, after = words[:split], words[split+1:]
        integer = _integer(before) if before else 0
        if integer is None or not after or any(w not in SMALL or SMALL[w] >= 10 for w in after): return None
        return str(integer) + '.' + ''.join(str(SMALL[w]) for w in after)
    value = _integer(words)
    return None if value is None else str(value)


_LABEL = r'(?:chapter|page|step|version|level|option|number|room|section|part|phase|round|season|episode|grade|gate|player|item|line|slide|row|column|table|figure|lesson|unit|stage|tier|floor|week|day|game|question|problem|test)'
_UNIT = r'(?:percent|per cent|dollars?|cents?|minutes?|hours?|seconds?|miles?|kilometers?|km|kg|pounds?|ounces?|inches?|feet|foot|meters?|grams?|liters?|gb|mb|tb|ms|k|am|pm|o\'clock)'
_MATH = r'(?:plus|minus|times|multiplied|divided|over|equals|is equal|by|point|squared|cubed|to the power)'


def _numeric_one(text, start, end):
    """A bare 'one' is usually a pronoun or idiom ('the current one', 'one sentence
    tagline'). It becomes 1 only in clearly numeric company."""
    before, after = text[:start], text[end:]
    number = r'(?:\d|\b(?:zero|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|hundred)\b)'
    return bool(re.search(r'(?:\b' + _MATH + r'|[+×÷=/−<>])[ \t]*$', before, re.I)
                or re.match(r'[ \t]*(?:[+×÷=/−%<>]|' + _MATH + r'\b|' + _UNIT + r'\b|x\b)', after, re.I)
                or re.search(r'\b' + _LABEL + r'[ \t]+$', before, re.I)
                or re.search(number + r'[ \t]*(?:,|and|or|to|through|-)[ \t]*$', before, re.I)
                or re.match(r'[ \t]*(?:,|and|or|to|through|-)[ \t]*' + number, after, re.I))


def _cardinals(text):
    matches = list(LEXEME.finditer(text)); spans = []; i = 0
    while i < len(matches):
        word = matches[i][0].lower()
        article = word in {'a', 'an'} and i+1 < len(matches) and matches[i+1][0].lower() in set(SCALES) | {'hundred'} and re.fullmatch(r'[ \t]+', text[matches[i].end():matches[i+1].start()])
        if word not in NUMBER_WORDS - {'and'} and not article:
            i += 1; continue
        start = i; words = ['one' if article else word]; i += 1
        while i < len(matches) and matches[i][0].lower() in NUMBER_WORDS:
            gap = text[matches[i-1].end():matches[i].start()]
            if not re.fullmatch(r'[ \t-]+', gap): break
            following = matches[i][0].lower()
            if following == 'and':
                # Conjunction joins a hundreds/scales remainder, not quantities
                # in "two and three" or unrelated prose following a number.
                if not any(w in SCALES or w == 'hundred' for w in words): break
                if i+1 >= len(matches) or matches[i+1][0].lower() not in NUMBER_WORDS - {'and'}: break
            words.append(following); i += 1
        end = matches[i-1].end()
        before = text[:matches[start].start()]
        following = text[end:]
        # Keep proper names (One Direction), ordinal compounds, identifiers,
        # years/digit strings and malformed runs rather than guessing a value.
        next_word = re.match(r'\s+([A-Z][a-z]+)', following)
        proper = matches[start][0][:1].isupper() and next_word is not None
        ordinal_tail = re.match(r'-(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)\b', following, re.I)
        embedded = bool(re.search(r'[\w_/@.-]$', before) or re.match(r'[_/@-]|\.(?=\w)', following))
        value = _number(words)
        if words == ['one'] and not _numeric_one(text, matches[start].start(), end):
            value = None
        if value is not None and not proper and not ordinal_tail and not embedded:
            spans.append((matches[start].start(), end, value))
    for start, end, value in reversed(spans): text = text[:start] + value + text[end:]
    return text


_HOUR = r'(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d{1,2})'
_MINUTE = r'(?:(?:oh|zero) (?:one|two|three|four|five|six|seven|eight|nine)|(?:twenty|thirty|forty|fifty)(?:[ -](?:one|two|three|four|five|six|seven|eight|nine))?|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|\d{2})'


def _clocks(text):
    def clock(match):
        hour = int(match[1]) if match[1].isdigit() else SMALL[match[1].lower()]
        parts = match[2].lower().replace('-', ' ').split()
        minute = int(parts[0]) if parts[0].isdigit() else SMALL[parts[1]] if parts[0] in {'oh', 'zero'} else _integer(parts)
        meridiem = match[3]
        context = text[:match.start()]
        explicit = meridiem or re.search(r'\b(?:at|around|before|after|until|from|by)\s*$', context, re.I)
        if re.search(r'\b(?:divided|multiplied) by\s*$', context, re.I): explicit = False
        if not meridiem and re.match(r'\s+(?:dollars|cents|euros|pounds|percent|per cent|items|units|seats|people|miles|kilometers|grams|hours|minutes|seconds)\b', text[match.end():], re.I): explicit = False
        if not explicit or minute is None or not 0 <= minute < 60 or not 0 <= hour < 24 or (meridiem and not 1 <= hour <= 12): return match[0]
        return f'{hour}:{minute:02d}' + (' ' + meridiem.upper() if meridiem else '')
    text = re.sub(r'\b(' + _HOUR + r')\s+(' + _MINUTE + r')(?:\s+(am|pm))?\b', clock, text, flags=re.I)
    text = re.sub(r'\b(' + _HOUR + r')\s+(am|pm)\b', lambda m: str(SMALL.get(m[1].lower(), m[1])) + ' ' + m[2].upper(), text, flags=re.I)
    return text


def normalize(text):
    probe = re.sub(r'(?<![\w.])\d+\.\d+(?![\w.])', 'DECIMAL', text)
    if len(text) > 8000 or re.search(r'''[`"“”‘]|(?<!\w)'[^'\n]+'(?!\w)|https?://|\b\w+[.@_]\w+''', probe): return text
    if re.search(r'\b(?:word|phrase|term|literal|literally|spell|spelling|called|named|say exactly)\b', text, re.I): return text
    # These uses of one are pronouns/idioms, not numeric quantities.
    idioms = re.compile(r'\b(?:one another|one by one|one of a kind|for one thing|on the one hand|one way or another|at one with)\b', re.I)
    saved = []
    def hold(match):
        saved.append(match[0]); return '\ue000' + chr(0xe100 + len(saved)-1) + '\ue001'
    text = idioms.sub(hold, text)
    text = _cardinals(_clocks(text))
    # Operators need complete operands on both sides. Ordinary "times" or
    # "over" in prose stays prose. Existing numbers are never evaluated.
    text = re.sub(r'\bnegative\s+(\d+(?:\.\d+)?)\b', r'−\1', text, flags=re.I)
    atom = r'(?:−?\d+(?:\.\d+)?(?:%|[²³]|\^\d+)?|[xyzXYZ](?:[²³]|\^\d+)?)'
    text = re.sub(r'\b(\d+(?:\.\d+)?)\s+(?:percent|per cent)\b', r'\1%', text, flags=re.I)
    text = re.sub(r'(?<!\w)(\d+(?:\.\d+)?|[xyzXYZ])\s+(squared|cubed)\b', lambda m: m[1] + ('²' if m[2].lower() == 'squared' else '³'), text, flags=re.I)
    text = re.sub(r'(?<!\w)(\d+(?:\.\d+)?|[xyzXYZ])\s+to the power of\s+(\d+)\b', r'\1^\2', text, flags=re.I)
    operations = {'plus': '+', 'minus': '−', 'times': '×', 'multiplied by': '×', 'divided by': '÷', 'over': '/', 'equals': '=', 'is equal to': '=', 'is less than': '<', 'is greater than': '>', 'less than': '<', 'greater than': '>', 'is less than or equal to': '≤', 'is greater than or equal to': '≥', 'less than or equal to': '≤', 'greater than or equal to': '≥', 'is not equal to': '≠', 'not equal to': '≠'}
    pattern = re.compile(r'(?<!\w)(' + atom + r')\s+(' + '|'.join(sorted(operations, key=len, reverse=True)) + r')\s+(?=' + atom + r'(?!\w))', re.I)
    for _ in range(4):
        updated = pattern.sub(lambda m: m[1] + ' ' + operations[m[2].lower()] + ' ', text)
        if updated == text: break
        text = updated
    text = re.sub(r'(?<!\w)minus\s+(\d+(?:\.\d+)?)(?=\s*(?:[+×÷=^−]|$|[.,?!]))', r'−\1', text, flags=re.I)
    for i, original in enumerate(saved): text = text.replace('\ue000' + chr(0xe100 + i) + '\ue001', original)
    return text
