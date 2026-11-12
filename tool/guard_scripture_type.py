#!/usr/bin/env python3
"""A tripwire for the plan's rule that nothing Berea wrote is drawn in Scripture type.

`scriptureStyle` is for Scripture and the person's own quoted text. A line that uses it within
four lines of a Berea-authored value (a prayer point's text, a plan day's title, a topic title, a
study-page question) fails. Usage: tool/guard_scripture_type.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUTHORED = re.compile(r'(point\.text|\bday\.title|\btopic\.title|\.question\b|authored)')
WINDOW = 4


def main():
    bad = []
    for path in sorted((ROOT / 'lib').rglob('*.dart')):
        if path.name == 'theme.dart':
            continue
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if 'scriptureStyle(' not in line:
                continue
            near = '\n'.join(lines[max(0, i - WINDOW):i + 1])
            if AUTHORED.search(near):
                bad.append(f'{path.relative_to(ROOT)}:{i + 1}: {line.strip()}')
    for b in bad:
        print('authored text in Scripture type:', b, file=sys.stderr)
    return 1 if bad else 0


sys.exit(main())
