#!/usr/bin/env python3
"""A tripwire, not proof: interface strings in lib/ must not use words that say what a verse
means or tell the reader what to do. A person reads each changed string (see the plan, section 2);
this only catches the words a script can. Strings already shipped are listed, dated, in
tool/strings_allow.txt; the list shrinks as Release E removes them and a new entry needs a reason.

Usage: tool/guard_strings.py [--write-baseline]
"""
import re
import sys
from pathlib import Path

DENY = ['mean', 'means', 'meaning', 'should', 'must', 'worth', 'key', 'deeper', 'promise', 'promises']
LITERAL = re.compile(r"""'((?:\\.|[^'\\\n])*)'|"((?:\\.|[^"\\\n])*)\"""")
ROOT = Path(__file__).resolve().parent.parent
ALLOW = ROOT / 'tool' / 'strings_allow.txt'


def hits():
    found = set()
    for path in sorted((ROOT / 'lib').rglob('*.dart')):
        for line in path.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith(('//', 'import ', 'export ', 'part ')):
                continue
            for m in LITERAL.finditer(line):
                text = m.group(1) if m.group(1) is not None else m.group(2)
                if ' ' not in text.strip():
                    continue  # one word is an identifier or a key, not a sentence
                if re.match(r'(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b|\$\w+\.\$', text):
                    continue  # SQL and developer error messages are not interface wording
                words = set(re.findall(r"[a-z']+", text.lower()))
                bad = sorted(words.intersection(DENY))
                if bad:
                    found.add(f"{path.relative_to(ROOT)}\t{text}")
    return found


def main():
    found = hits()
    if '--write-baseline' in sys.argv:
        ALLOW.write_text('# Written 2026-11-10. Interface strings that use a deny-list word and are\n'
                         '# still shipped. Remove a line when its string goes; add one only with a reason.\n'
                         + '\n'.join(sorted(found)) + '\n')
        print(f'wrote {len(found)} entries')
        return 0
    allowed = {l for l in ALLOW.read_text().splitlines() if l and not l.startswith('#')} if ALLOW.exists() else set()
    new = sorted(found - allowed)
    for entry in new:
        print('new string with a deny-list word:', entry.replace('\t', ' : '), file=sys.stderr)
    stale = sorted(allowed - found)
    for entry in stale:
        print('allow-list entry no longer in the code (remove it):', entry.replace('\t', ' : '), file=sys.stderr)
    return 1 if new or stale else 0


sys.exit(main())
