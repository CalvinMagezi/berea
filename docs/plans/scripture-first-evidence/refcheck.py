"""Look up Bible references in the BSB text committed under berea/site/data.

Usage: python3 refcheck.py "Joshua 1:8" "Psalm 1:2" "Col 3:16-17"
       python3 refcheck.py --file plan.md      (finds every reference in a file)
Prints each reference with its verse text, or NOT FOUND.
"""
import json, re, sys, pathlib

DATA = pathlib.Path(__file__).resolve().parents[3] / 'site' / 'data'
books = json.loads((DATA / 'books.json').read_text())

def norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())

names = {}
def add(name, num):
    names[norm(name)] = num

if isinstance(books, list):
    for i, b in enumerate(books):
        num = b.get('n') or b.get('number') or b.get('id') or (i + 1) if isinstance(b, dict) else i + 1
        if isinstance(b, dict):
            for k, v in b.items():
                if isinstance(v, str):
                    add(v, num)
                elif isinstance(v, list):
                    for x in v:
                        if isinstance(x, str):
                            add(x, num)
        else:
            add(b, num)
else:
    for k, v in books.items():
        pass

add('Psalm', names.get('psalms', 19)); add('Song of Songs', names.get('songofsolomon', 22))

_cache = {}
def book(num):
    if num not in _cache:
        _cache[num] = json.loads((DATA / 'bible' / f'{num}.json').read_text())
    return _cache[num]

REF = re.compile(r'((?:[1-3]\s)?[A-Z][a-z]+(?:\s(?:of\s)?[A-Z][a-z]+)*)\s(\d+)(?::(\d+)(?:\s?[-–]\s?(\d+))?)?')

def lookup(ref):
    m = REF.fullmatch(ref.strip())
    if not m:
        return None, 'UNPARSED'
    name, ch, v1, v2 = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    num = names.get(norm(name))
    if not num:
        return None, 'UNKNOWN BOOK'
    b = book(num)
    if ch < 1 or ch > len(b):
        return None, 'NO SUCH CHAPTER'
    verses = b[ch - 1]
    if v1 is None:
        return f'[{len(verses)} verses] ' + verses[0][:90], 'OK'
    a = int(v1); z = int(v2) if v2 else a
    if a < 1 or z > len(verses) or z < a:
        return None, 'NO SUCH VERSE'
    return ' '.join(f'({i}) {verses[i-1]}' for i in range(a, z + 1)), 'OK'

def main(argv):
    refs = []
    if argv and argv[0] == '--file':
        text = pathlib.Path(argv[1]).read_text()
        seen = set()
        for m in REF.finditer(text):
            r = m.group(0)
            if names.get(norm(m.group(1))) and r not in seen:
                seen.add(r); refs.append(r)
    else:
        refs = argv
    bad = 0
    for r in refs:
        text, status = lookup(r)
        if status != 'OK':
            bad += 1
            print(f'!! {r}: {status}')
        else:
            print(f'{r}: {text}')
    print(f'\n{len(refs)} references, {bad} not found')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
