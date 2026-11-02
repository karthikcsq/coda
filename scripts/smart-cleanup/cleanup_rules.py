"""Source-preserving dictation formatting. Standard library only; no model or I/O."""
import re

WORD = re.compile(r"\w+(?:['’]\w+)*", re.UNICODE)
NOISE = {'um', 'uh', 'erm'}
LABELS = set('cs technical software math engineering finance business and or yes no true false ui ux input output'.split())
VERBS = set('open read write prepare check call email send buy bring review finish submit test pack print clean book order wash visit meet get take pay copy paste save close ask give make walk explain install run collect compare choose record ship assess discuss wait'.split())
ORDINALS = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth']
COUNTS = {word: i for i, word in enumerate(['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'])}
LIST_LABEL = r'(?:agenda|list|items|tasks|things|steps|priorities|options|groups|categories|supplies|ingredients|goals|requirements|topics|points|checks|process|groceries|shopping|packing|attendees|participants|deliverables|suggestions)'
ABBREVIATION = re.compile(r'\b(?:e\.g|i\.e|mr|mrs|ms|dr|prof|vs|etc)\.$', re.I)


def protected(text):
    """Quoted/code/literal syntax stays literal; ordinary 'explain' is not code."""
    if re.search(r'\b(?:ignore|disregard|override)\b[^\n]{0,100}\b(?:instructions|prompt|system)\b', text, re.I):
        return True
    if re.search(r'''["“”‘`{}]|(?<!\w)'[^'\n]+'(?!\w)|https?://|\b\w+[.@_]\w+''', text):
        return True
    for match in re.finditer(r'\b(\w+)/(\w+)\b', text):
        if match[1].casefold() not in LABELS or match[2].casefold() not in LABELS:
            return True
    markers = r'(?:comma|period|colon|slash|question mark|exclamation mark|new paragraph|new line)'
    return bool(re.search(r'\b(?:explain|discuss|phrase|word|term|literal|say exactly)\b[^.!?\n]{0,70}\b'+markers+r'\b|\b(?:a|an|the|this|that)\s+'+markers+r'\b', text, re.I))


def _words(text):
    return [(m.group().casefold(), m.start(), m.end()) for m in WORD.finditer(text)]


def _fillers(text, words):
    found = set()
    for i, (word, start, end) in enumerate(words):
        if word in NOISE and not text[start:end].isupper():
            found.add(i)
        if word != 'like' or i == 0 or i == len(words)-1:
            continue
        previous, following = words[i-1][0], words[i+1][0]
        left, right = text[words[i-1][2]:start], text[end:words[i+1][1]]
        comparison = following in {'a','an','the','her','his','their','our','my','your','its'}
        if (',' in left and ',' in right and not comparison
            or previous in {'it', 'this', 'that', 'them'} and following.endswith('ly')
            or previous == 'also' and following in {'give', 'make', 'take', 'send', 'check', 'walk', 'explain'}
                and (i<2 or words[i-2][0] not in {'i','we','you','they','he','she'})):
            found.add(i)
    return found


def surface(raw):
    """Remove clear speech noise; normalize explicitly spoken symbols and punctuation.

    Meaningful words, hedges, grammar, emphasis and quotations are retained. Empty
    filler-only input returns empty. Terminal punctuation is added to prose, not
    to an existing multiline list. Capitalization changes never replace words.
    """
    if not raw.strip() or protected(raw):
        return raw
    words = _words(raw)
    fillers = _fillers(raw, words)
    if words and len(fillers) == len(words):
        return ''
    spans = []
    for i in fillers:
        start, end = words[i][1:]
        before = re.search(r',[ \t]*$', raw[:start])
        after = re.match(r'[ \t]*[,;:]?[ \t]*', raw[end:])
        # A greeting comma still belongs in 'Hello, Jo' after removing a filler.
        if before and (i == 0 or words[i-1][0] not in {'hi', 'hello', 'hey', 'dear'}):
            start = before.start()
        end += after.end()
        if (i == 0 or re.search(r'[.!?][ \t]*$', raw[:start])) and raw[end:end+1] and raw[end:end+1] in '.?!':
            end += 1
        spans.append((start, end))
    merged = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    text = raw
    for start, end in reversed(merged):
        text = text[:start] + ' ' + text[end:]
    labels = '|'.join(sorted(LABELS, key=len, reverse=True))
    text = re.sub(r'\b('+labels+r')[ \t]+slash[ \t]+('+labels+r')\b', lambda m: m[1]+'/'+m[2], text, flags=re.I)
    text = re.sub(r'\b(domain)[ \t]+(specific)\b(?![ \t]+to\b)', lambda m: m[1]+'-'+m[2], text, flags=re.I)
    if re.search(r'\b(?:period|question mark|exclamation mark)\s*[.!?]?$', text, re.I):
        punctuation = {'comma': ',', 'period': '.', 'colon': ':', 'question mark': '?', 'exclamation mark': '!', 'new paragraph': '\n\n', 'new line': '\n'}
        text = re.sub(r'\b(new paragraph|new line|question mark|exclamation mark|comma|period|colon)\b', lambda m: punctuation[m[0].casefold()], text, flags=re.I)
        text = re.sub(r'([.!?])\s*[.!?]$', r'\1', text)
        text = re.sub(r'[ \t]*\n[ \t]*', '\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'[ \t]+([,.;:?!])', r'\1', text).strip()
    if fillers:
        text = re.sub(r'^[,.;:?!]+[ \t]*', '', text)
        text = re.sub(r'([.!?])[ \t]+[.!?](?=[ \t]|$)', r'\1', text)
    return capitalize(text)


def capitalize(text):
    """Case and terminal punctuation only; never remove or replace a word."""
    def initial(match):
        prefix = text[:match.start(2)].rstrip()
        return match[1]+(match[2] if ABBREVIATION.search(prefix) else match[2].upper())
    text = re.sub(r'(^[ \t]*|[.!?][ \t\n]+|\n[ \t]*(?:[-*•][ \t]+|\d+[.)][ \t]+)?)([a-z])', initial, text)
    text = re.sub(r'\bi\b', 'I', text)
    if text and text[-1].isalnum() and '\n' not in text:
        text += '.'
    return text


def _sentences(text):
    result, start = [], 0
    for match in re.finditer(r'[.!?](?:[ \t\n]+|$)', text):
        end = match.start()+1
        if ABBREVIATION.search(text[start:end]):
            continue
        result.append(text[start:end].strip())
        start = match.end()
    if text[start:].strip():
        result.append(text[start:].strip())
    return result


def _parts(body):
    """Split explicit list separators, preserving final conjunctions as words."""
    delimiter = ';' if ';' in body else ','
    items, depth, start = [], 0, 0
    for i, char in enumerate(body):
        if char in '([': depth += 1
        if char in ')]': depth = max(0, depth-1)
        if char == delimiter and depth == 0:
            items.append(body[start:i].strip()); start = i+1
    items.append(body[start:].strip())
    if len(items) == 1:
        boundaries = [m.start() for m in re.finditer(r'\s+(?=and\s+)', body)
                      if body[:m.start()].count('(')==body[:m.start()].count(')')
                      and body[:m.start()].count('[')==body[:m.start()].count(']')]
        items = [body[start:end].strip() for start,end in zip([0]+boundaries,boundaries+[len(body)])]
    return [item for item in items if item]


def _item(text):
    text = text.strip(' \t\n,;:')
    # Short fragments use conventional punctuation-free bullet/step style.
    if len(WORD.findall(text)) <= 10:
        text = text.rstrip('.')
    return text[:1].upper()+text[1:]


def _list(text):
    bullets = list(re.finditer(r'\bbullet point\b[ \t]*[,.:]?[ \t]+', text, re.I))
    if len(bullets)>=2:
        intro = text[:bullets[0].start()].strip()
        if not intro or (intro.endswith(':') and re.search(r'\b'+LIST_LABEL+r'\b', intro, re.I)):
            items = [text[m.end():bullets[i+1].start() if i+1<len(bullets) else len(text)].strip() for i,m in enumerate(bullets)]
            if all(WORD.search(item) for item in items):
                return (intro+'\n' if intro else '')+'\n'.join('- '+_item(item) for item in items)
    # Ordinals are structural only when they introduce actual actions in order.
    matches = list(re.finditer(r'\b('+ '|'.join(ORDINALS) +r')\b[ \t]*[,.:]?[ \t]+', text, re.I))
    usable = []
    for match in matches:
        following = WORD.findall(text[match.end():])
        prior = WORD.findall(text[:match.start()])
        first = following[0].casefold() if following else ''
        second = following[1].casefold() if len(following)>1 else ''
        if (first in VERBS or first in {'i','we','you'} and second in VERBS) and (not prior or prior[-1].casefold() not in {'the','a','an','my','your','our','his','her','their'}):
            usable.append(match)
    if len(usable)>=2 and [m[1].casefold() for m in usable] == ORDINALS[:len(usable)]:
        intro = text[:usable[0].start()].strip()
        if not intro or re.search(r'\b'+LIST_LABEL+r'\b', intro, re.I):
            items = []
            for i, match in enumerate(usable):
                end = usable[i+1].start() if i+1<len(usable) else len(text)
                item = text[match.end():end].strip()
                # Keep an 'and' before the next ordinal with that next item.
                connector = ''
                if i and items[-1].lower().endswith(' and'):
                    items[-1] = items[-1][:-4].rstrip(' ,;')
                    connector = 'and '
                items.append(connector+item)
            prefix = (intro+'\n' if intro.endswith(('.', '?', '!')) else intro.rstrip(' ,;:')+':\n') if intro else ''
            return prefix+'\n'.join(str(i+1)+'. '+_item(item) for i,item in enumerate(items))
    colon = re.match(r'^([^:\n]{1,130}):\s*(.+)$', text, re.S)
    header, body, count = None, None, None
    if colon and re.search(r'\b'+LIST_LABEL+r'\b', colon[1], re.I):
        header, body = colon[1], colon[2]
    else:
        explicit = re.match(r'^(.*?\b(?:bulleted list|bullet points))\s+(.+)$', text, re.I|re.S)
        if explicit and re.search(r'\bcomma\b', explicit[2], re.I):
            header, body = explicit[1], re.sub(r'\s+comma\s+', ', ', explicit[2], flags=re.I)
        counted = re.match(r'^(.*?\b(\d+|two|three|four|five|six|seven|eight|nine|ten)\s+'+LIST_LABEL+r')\s+(.+)$', text, re.I|re.S)
        if counted:
            header, body = counted[1], counted[3]
            count = int(counted[2]) if counted[2].isdigit() else COUNTS[counted[2].casefold()]
        else:
            # A named enumeration can be clear without a dictated colon/count.
            named = re.match(r'^(.*?\b'+LIST_LABEL+r'\b(?:[ \t]+\w+){0,7}?[ \t]+(?:is|are|include|contain))[ \t]+(.+)$', text, re.I|re.S)
            if named:
                first = _sentences(named[2])[0]
                parts = _parts(first)
                # Require three explicit separators/items; clauses such as
                # "for engineering" are ambiguous grouping, so remain prose.
                if len(parts)>=3 and not any(re.match(r'^(?:and\s+)?(?:for|which|that|because)\b', part, re.I) for part in parts):
                    header, body = named[1], named[2]
    if header and body:
        sentences = _sentences(body)
        first = sentences[0] if sentences else body
        parts = _parts(first)
        if len(parts)>=2 and (count is None or count==len(parts)):
            result = header+':\n'+'\n'.join('- '+_item(item) for item in parts)
            if len(sentences)>1: result += '\n\n'+' '.join(sentences[1:])
            return result
    return None


def layout(text):
    """Render explicit lists and automatic readable paragraphs using source words.

    Lists retain the heading/count and final 'and'; ordinal cue words become
    numbered labels only for a clear consecutive action sequence. Prose does not
    acquire invented headings or lists. Existing quoted/code text stays literal.
    """
    if not text.strip() or protected(text):
        return text
    blocks = []
    for block in re.split(r'\n[ \t]*\n', text):
        block = block.strip()
        if not block: continue
        listed = _list(block)
        if listed is not None:
            blocks.append(listed); continue
        if re.search(r'(?m)^\s*(?:[-*•]|\d+[.)])\s+', block) or len(WORD.findall(block))<=60:
            blocks.append(block); continue
        sentences = _sentences(block)
        paragraphs, current, size = [], [], 0
        for sentence in sentences:
            topic = re.match(r'^(?:For example|Separately|In contrast|On another topic|Next),?\s', sentence, re.I)
            if current and (len(current)>=3 or size>=80 or topic and size>=20):
                paragraphs.append(' '.join(current)); current=[]; size=0
            current.append(sentence); size+=len(WORD.findall(sentence))
        if current: paragraphs.append(' '.join(current))
        blocks.extend(paragraphs)
    return '\n\n'.join(blocks)
