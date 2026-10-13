// A JavaScript port of Berea's reference check (ref_parser.dart, books.dart and
// citation_guard.dart). It must agree with the Dart original; check/selftest.mjs compares it
// against fixture.json, which the real harness wrote.
(function (root) {
  const MIN_QUOTE_CHARS = 30;
  const MIN_QUOTE_OVERLAP = 0.7;
  const MIN_QUOTE_CONTENT_WORDS = 4;
  const MIN_QUOTE_MARGIN = 0.15;
  const QUOTE_CITATION_WINDOW = 48;
  const MAX_PASSAGE_VERSES = 40;
  const MIN_JUDGED_NAME = 4;
  const WHOLE_CHAPTER_END = 999;

  const NOT_BOOKS = new Set(['Verse', 'Verses', 'Chapter', 'Chapters', 'Section', 'Part', 'Page',
    'Day', 'Days', 'Week', 'At', 'By', 'In', 'On', 'Around', 'About', 'Until', 'Since', 'Between',
    'Before', 'After', 'From', 'To', 'And', 'Or', 'The', 'See', 'Cf', 'Compare', 'Also', 'Read',
    'Ratio', 'Score', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
    'October', 'November', 'December', 'Time', 'Hour', 'Minute', 'Mr', 'Mrs', 'Dr', 'Mark', 'Room',
    'Gate']);
  const ORDINALS = { First: '1', Second: '2', Third: '3' };
  const LEADING_PROSE = new Set(['See', 'Cf', 'Compare', 'Also', 'Read', 'In', 'From', 'And', 'Or',
    'The', 'By', 'On', 'At', 'To', 'About', 'Before', 'After', 'Since', 'Until']);
  const FUNCTION_WORDS = new Set(['a', 'an', 'and', 'as', 'at', 'be', 'but', 'by', 'for', 'from',
    'he', 'her', 'him', 'his', 'i', 'in', 'is', 'it', 'me', 'my', 'not', 'of', 'on', 'or', 'our',
    'shall', 'she', 'so', 'that', 'the', 'their', 'them', 'they', 'this', 'to', 'us', 'was', 'we',
    'were', 'who', 'will', 'with', 'you', 'your', 'said', 'all', 'are', 'have', 'has', 'had', 'do',
    'did', 'no', 'one', 'which']);
  const ROMAN = { i: '1', ii: '2', iii: '3' };
  const OPEN = '“';
  const CLOSE = '”';

  const normalizeBookKey = (s) => s.trim()
    .replace(/^(iii|ii|i)\s+/i, (_, r) => ROMAN[r.toLowerCase()])
    .toLowerCase()
    .replace(/[\s.]/g, '');

  // Words of any script, combining marks dropped, as CitationGuard.normalize does.
  const normalize = (s) => s.toLowerCase().replace(/\p{M}/gu, '').replace(/[^\p{L}\p{N} ]/gu, ' ')
    .replace(/\s+/g, ' ').trim();

  const contentWords = (s) => new Set(normalize(s).split(' ').filter((w) => w && !FUNCTION_WORDS.has(w)));

  function create(books, index) {
    const byAlias = new Map();
    for (const b of books) {
      byAlias.set(normalizeBookKey(b.name), b);
      byAlias.set(normalizeBookKey(b.step), b);
      for (const a of b.aliases) byAlias.set(a, b);
    }
    const bookFor = (raw) => byAlias.get(normalizeBookKey(raw)) || null;

    const aliasPattern = (key) => {
      const numerals = { 1: '(?:1|i)', 2: '(?:2|ii)', 3: '(?:3|iii)' };
      return key.replace(/^([1-3])/, (_, n) => `${numerals[n]}\\s*`).replace('songof', 'song\\s*of\\s*');
    };
    const keys = [...new Set([
      ...books.flatMap((b) => [normalizeBookKey(b.name), normalizeBookKey(b.step), ...b.aliases]),
      'songofsongs',
    ])].sort((a, b) => b.length - a.length);
    const refSource = `\\b(${keys.map(aliasPattern).join('|')})\\.?\\s*(\\d{1,3})(?:\\s*[:.]\\s*(\\d{1,3})(?:\\s*[-\\u2013]\\s*(\\d{1,3}))?)?(?!\\d)`;
    const citationShape = () => /\b((?:[1-3]|I{1,3})\s?)?([A-Z][a-z]+(?:\s+(?:of\s+)?[A-Z][a-z]+)?)\.?\s+(\d{1,3})\s*:\s*(\d{1,3})/g;

    // Identity as Dart's Ref ==: "John 3:16" and "John 3:16-16" share a label but are different refs.
    const refKey = (r) => [r.book.id, r.chapter, r.verseStart, r.verseEnd].join(':');

    const label = (r) => {
      if (r.verseStart == null) return `${r.book.name} ${r.chapter}`;
      if (r.verseEnd == null || r.verseEnd === r.verseStart) return `${r.book.name} ${r.chapter}:${r.verseStart}`;
      return `${r.book.name} ${r.chapter}:${r.verseStart}-${r.verseEnd}`;
    };

    function matches(text) {
      const out = [];
      for (const m of text.matchAll(new RegExp(refSource, 'gi'))) {
        const book = bookFor(m[1]);
        if (!book) continue;
        const chapter = Number(m[2]);
        if (chapter === 0) continue;
        const vs = m[3] == null ? null : Number(m[3]);
        let ve = m[4] == null ? null : Number(m[4]);
        if (vs != null && ve != null && ve < vs) ve = vs;
        out.push({ ref: { book, chapter, verseStart: vs, verseEnd: ve }, start: m.index, end: m.index + m[0].length });
      }
      return out;
    }

    const hasVerse = (bookId, chapter, verse) => {
      const ch = index[bookId]?.[chapter - 1];
      return Boolean(ch) && verse >= 1 && verse <= ch[0] && !ch[1].includes(verse);
    };

    const exists = (r) => {
      const vs = r.verseStart ?? 1;
      const ve = r.verseEnd ?? vs;
      const found = new Set([vs, ve].filter((v) => hasVerse(r.book.id, r.chapter, v)));
      return found.size === (vs === ve ? 1 : 2);
    };

    const overlaps = (a, b) => {
      if (a.book.id !== b.book.id || a.chapter !== b.chapter) return false;
      if (a.verseStart == null || b.verseStart == null) return true;
      const aEnd = a.verseEnd ?? a.verseStart;
      const bEnd = b.verseEnd ?? b.verseStart;
      return a.verseStart <= bEnd && b.verseStart <= aEnd;
    };

    function passage(r, text) {
      const vs = r.verseStart ?? 1;
      const ve = r.verseStart == null ? WHOLE_CHAPTER_END : (r.verseEnd ?? vs);
      const chapter = text[r.book.id]?.[r.chapter - 1] || [];
      const out = [];
      for (let v = vs; v <= Math.min(ve, chapter.length) && out.length < MAX_PASSAGE_VERSES; v++) {
        if (chapter[v - 1] != null) out.push({ book: r.book, chapter: r.chapter, verse: v, text: chapter[v - 1] });
      }
      return out;
    }

    function unknownBook(m) {
      let words = m[2].split(/\s+/);
      let numeral = m[1] ?? '';
      while (words.length > 1 && LEADING_PROSE.has(words[0])) words = words.slice(1);
      if (words.some((w) => NOT_BOOKS.has(w))) return null;
      const ordinal = ORDINALS[words[0]];
      if (ordinal != null && words.length > 1) {
        numeral = ordinal;
        words = words.slice(1);
      }
      if (words.join('').length < MIN_JUDGED_NAME) return null;
      for (let i = 0; i < words.length; i++) {
        const tail = words.slice(i).join(' ');
        if (bookFor(tail) || bookFor(`${numeral}${tail}`)) return null;
        if (bookFor(`1 ${tail}`)) return null;
      }
      if (words.some((w) => bookFor(w) || bookFor(`1 ${w}`))) return null;
      return m[0];
    }

    function quoteSpans(s) {
      const spans = [];
      let open = null;
      for (let i = 0; i < s.length; i++) {
        const ch = s[i];
        if (ch === '\n') open = null;
        else if (ch === OPEN || (ch === '"' && open == null)) open = i + 1;
        else if ((ch === CLOSE || ch === '"') && open != null) {
          spans.push([open, i]);
          open = null;
        }
      }
      return spans;
    }

    function correctQuote(quote, shown, citedAs) {
      const q = normalize(quote).split(' ').filter(Boolean);
      const qContent = contentWords(quote);
      if (!q.length || qContent.size < MIN_QUOTE_CONTENT_WORDS) return null;
      const candidates = citedAs == null ? shown
        : shown.filter((v) => overlaps(citedAs, { book: v.book, chapter: v.chapter, verseStart: v.verse, verseEnd: v.verse }));
      const qAll = new Set(q);
      let best = 0;
      let second = 0;
      let bestSpan = null;
      for (const v of candidates) {
        const words = v.text.split(/\s+/);
        let verseBest = 0;
        let bestAllShared = -1;
        let verseSpan = null;
        for (let len = q.length - 2; len <= q.length + 3; len++) {
          if (len < 1 || len > words.length) continue;
          for (let i = 0; i + len <= words.length; i++) {
            const span = words.slice(i, i + len).join(' ');
            const spanContent = contentWords(span);
            let shared = 0;
            for (const w of qContent) if (spanContent.has(w)) shared++;
            if (shared < MIN_QUOTE_CONTENT_WORDS) continue;
            const score = shared / qContent.size;
            const spanAll = new Set(normalize(span).split(' '));
            let allShared = 0;
            for (const w of qAll) if (spanAll.has(w)) allShared++;
            if (score > verseBest || (score === verseBest && allShared > bestAllShared)) {
              verseBest = score;
              bestAllShared = allShared;
              verseSpan = span;
            }
          }
        }
        if (verseBest > best) {
          second = best;
          best = verseBest;
          bestSpan = verseSpan;
        } else if (verseBest > second) {
          second = verseBest;
        }
      }
      if (best < MIN_QUOTE_OVERLAP || best - second < MIN_QUOTE_MARGIN) return null;
      return bestSpan == null ? null : bestSpan.replace(/^[^\w‘“]+|[,;:]+$/g, '');
    }

    // Runs the check on one piece of text. loadBook(id) returns that book's chapters.
    async function check(output, loadBook) {
      const found = matches(output);
      const text = {};
      for (const m of found) {
        const id = m.ref.book.id;
        if (index[id]?.[m.ref.chapter - 1] && !text[id]) text[id] = await loadBook(id);
      }
      const verified = new Map();
      const unverified = new Map();
      let buf = '';
      let cursor = 0;
      for (const m of found) {
        buf += output.substring(cursor, m.start);
        if (exists(m.ref)) {
          verified.set(refKey(m.ref), m.ref);
          buf += output.substring(m.start, m.end);
        } else {
          unverified.set(refKey(m.ref), m.ref);
          buf += `[unverified: ${label(m.ref)}]`;
        }
        cursor = m.end;
      }
      buf += output.substring(cursor);

      const unknownBooks = [];
      const withRefs = buf.replace(citationShape(), (...args) => {
        const bad = unknownBook(args);
        if (bad == null) return args[0];
        unknownBooks.push(bad.trim());
        return `[unverified: ${bad.trim()}]`;
      });

      const seen = new Set();
      const shown = [];
      for (const m of found) {
        const key = refKey(m.ref);
        if (seen.has(key)) continue;
        seen.add(key);
        shown.push(...passage(m.ref, text));
      }
      const shownText = normalize(shown.map((v) => v.text).join(' '));
      const badQuotes = [];
      const corrected = [];
      let out = '';
      cursor = 0;
      for (const [start, end] of quoteSpans(withRefs)) {
        const quoted = withRefs.substring(start, end);
        const q = normalize(quoted);
        // A quote with no letters or digits left is never taken as shown.
        if (quoted.length < MIN_QUOTE_CHARS || (q && shownText.includes(q))) continue;
        const after = withRefs.substring(end, Math.min(withRefs.length, end + QUOTE_CITATION_WINDOW));
        const beforeStart = Math.max(0, start - 1 - QUOTE_CITATION_WINDOW);
        const before = withRefs.substring(beforeStart, Math.max(beforeStart, start - 1));
        const citedAs = matches(after)[0]?.ref ?? matches(before).at(-1)?.ref ?? null;
        const fix = correctQuote(quoted, shown, citedAs);
        if (fix != null) {
          corrected.push(quoted);
          out += withRefs.substring(cursor, start) + fix + withRefs[end] + ' [quote corrected]';
          cursor = end + 1;
          continue;
        }
        badQuotes.push(quoted);
        out += withRefs.substring(cursor, end + 1) + ' [unverified quote]';
        cursor = end + 1;
      }
      out += withRefs.substring(cursor);

      return {
        text: out,
        verified: [...verified.values()].map(label),
        unverified: [...unverified.values()].map(label),
        unknownBooks,
        badQuotes,
        corrected,
        passages: shown.map((v) => ({ label: `${v.book.name} ${v.chapter}:${v.verse}`, text: v.text })),
      };
    }

    return { check, matches, label };
  }

  const api = { create, normalize };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.BereaCheck = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
