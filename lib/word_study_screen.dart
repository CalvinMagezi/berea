import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_state.dart';
import 'keep_sheet.dart';
import 'study_store.dart' show keptWordKind;
import 'theme.dart';

/// Verses of a word's use loaded at a time; "Show more" loads the next page.
const wordUsesPage = 30;

/// Other words glossed with the pressed English word, at most.
const glossedWordsShown = 6;

/// Opens a word study on [ref] for the [english] word the reader pressed (its [occurrence] in the
/// verse by stem and its [wordIndex] among the verse's words, from 0), or on the original word at
/// [pos]. Asking about the word sends the question to
/// the Study tab; tapping a verse opens it in the reader.
Future<void> showWordStudy(
  BuildContext context,
  AppState s,
  Ref ref, {
  String? english,
  int occurrence = 0,
  int? wordIndex,
  int? pos,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (ctx) => WordStudyScreen(
        db: s.db,
        ref: ref,
        english: english,
        occurrence: occurrence,
        wordIndex: wordIndex,
        pos: pos,
        translation: s.settings.translation,
        onAsk: (question) {
          Navigator.of(ctx).popUntil((r) => r.isFirst);
          s.askAboutWord(question);
        },
        onOpen: (verse) {
          Navigator.of(ctx).popUntil((r) => r.isFirst);
          s.openInReader(verse);
        },
        onKeep: ({required title, required body, required subtitle, verse}) =>
            showKeepSheet(
              ctx,
              s,
              title: title,
              body: body,
              subtitle: subtitle,
              verse: verse,
              kind: keptWordKind,
            ),
      ),
    ),
  );
}

/// Files a word in a notebook: Save word.
typedef KeepWord =
    void Function({
      required String title,
      required String body,
      required String subtitle,
      Ref? verse,
    });

/// The word under [global] in the verse laid out by the text widget at [textContext], whose first
/// [prefixLength] characters (the verse number) come before [text]. Null when the press is not on
/// a word of [text], as on the verse number or a parallel translation.
({String word, int index, int occurrence})? pressedWord(
  BuildContext textContext,
  Offset global,
  String text,
  int prefixLength,
) {
  final paragraph = _paragraphIn(textContext.findRenderObject());
  if (paragraph == null || !paragraph.hasSize) return null;
  final local = paragraph.globalToLocal(global);
  if (!(Offset.zero & paragraph.size).contains(local)) return null;
  final offset = paragraph.getPositionForOffset(local).offset - prefixLength;
  final hit = wordAt(text, offset);
  return hit == null ? null : (word: hit.word, index: hit.index, occurrence: hit.occurrence);
}

RenderParagraph? _paragraphIn(RenderObject? o) {
  if (o == null || o is RenderParagraph) return o as RenderParagraph?;
  RenderParagraph? found;
  o.visitChildren((c) => found ??= _paragraphIn(c));
  return found;
}

/// One original-language word: what it means, how often and where it is used, how it is
/// glossed, which other words stand behind the same English, and every verse that uses it.
class WordStudyScreen extends StatefulWidget {
  final BibleDb db;

  /// The verse the study started from.
  final Ref ref;
  final String? english;
  final int occurrence;

  /// The pressed word's place among the verse's words ([verseWordPattern]), which the BSB
  /// translation tables map to its original word exactly.
  final int? wordIndex;
  final int? pos;
  final String translation;
  final void Function(String question) onAsk;
  final void Function(Ref verse) onOpen;

  /// Null hides Save word.
  final KeepWord? onKeep;

  const WordStudyScreen({
    super.key,
    required this.db,
    required this.ref,
    required this.onAsk,
    required this.onOpen,
    this.english,
    this.occurrence = 0,
    this.wordIndex,
    this.pos,
    this.translation = defaultTranslation,
    this.onKeep,
  });

  @override
  State<WordStudyScreen> createState() => _WordStudyScreenState();
}

class _WordStudyScreenState extends State<WordStudyScreen> {
  late final List<WordTag> _verseWords = widget.db.words(widget.ref);
  late final List<GlossedWord> _glossed = widget.english == null
      ? const []
      : widget.db.wordsGlossed(widget.english!, k: glossedWordsShown + 1);

  /// The word in this verse being studied; null for a word reached from another word's study.
  WordTag? _tag;

  /// The base Strong's number studied; null until the reader picks a word.
  String? _code;
  LexEntry? _entry;
  ({int uses, int verses}) _count = (uses: 0, verses: 0);
  List<(Book, int)> _books = const [];
  List<(String, int)> _glosses = const [];
  Book? _book;
  final _uses = <WordUse>[];
  var _more = false;

  /// True when Berea chose the word from the English, so the reader is asked to check it.
  var _guessed = false;

  /// True when the BSB tables say the translators supplied the pressed word.
  var _supplied = false;

  @override
  void initState() {
    super.initState();
    WordTag? start;
    if (widget.pos != null) {
      start = _verseWords.where((w) => w.pos == widget.pos).firstOrNull;
    } else if (_exactCode() case final exact?) {
      if (exact.code.isEmpty) {
        _supplied = true;
      } else {
        final same = [
          for (final w in _verseWords)
            if (studyCode(w) == exact.code) w,
        ];
        if (same.isEmpty) {
          // STEP numbers this verse's word differently; the word itself is still known.
          _study(exact.code);
        } else {
          start = same[exact.repeat.clamp(0, same.length - 1)];
        }
      }
    } else if (widget.english != null) {
      final ranked = matchOriginal(
        _verseWords,
        widget.english!,
        occurrence: widget.occurrence,
        lexicon: widget.db.lexicon,
      );
      if (ranked.isNotEmpty) start = _verseWords[ranked.first];
      _guessed = start != null;
    }
    if (start != null) _studyTag(start);
  }

  /// In the BSB, the pressed word's Strong's number from the translation tables ('' for a word the
  /// translators supplied), and how many times the same word came earlier in the English, to pick
  /// among repeats. Null in other translations or where the tables do not cover the verse.
  ({String code, int repeat})? _exactCode() {
    final at = widget.wordIndex;
    if (at == null || widget.translation != defaultTranslation) return null;
    final codes = widget.db.bsbCodes(widget.ref);
    if (codes == null || at >= codes.length) return null;
    final code = codes[at];
    var repeat = 0;
    for (var j = 0; j < at; j++) {
      // A phrase ("and multiply") gives its number to each of its words; count phrases.
      if (codes[j] == code && (j == 0 || codes[j - 1] != code)) repeat++;
    }
    return (code: code, repeat: repeat);
  }

  void _studyTag(WordTag w) {
    final code = studyCode(w);
    if (code == null) return;
    final codes = w.strongs.split(' ').where((c) => c.isNotEmpty && !isParticleCode(c));
    _tag = w;
    _study(code, codes.isEmpty ? null : widget.db.lexicon(codes.first));
  }

  /// Loads everything about [code] once, so building the screen reads no SQL.
  void _study(String code, [LexEntry? entry]) {
    _code = code;
    _entry = entry ?? widget.db.lexicon(code);
    _count = widget.db.wordCount(code);
    _books = widget.db.wordBooks(code);
    _glosses = widget.db.wordGlosses(code);
    _book = null;
    _uses.clear();
    _loadUses();
  }

  void _loadUses() {
    final page = widget.db.wordUses(
      _code!,
      translation: widget.translation,
      book: _book,
      limit: wordUsesPage + 1,
      offset: _uses.length,
    );
    _more = page.length > wordUsesPage;
    _uses.addAll(page.take(wordUsesPage));
  }

  void _pick(WordTag w) => setState(() {
    _guessed = false;
    _studyTag(w);
  });

  void _switchTo(GlossedWord g) => setState(() {
    _guessed = false;
    _tag = null;
    _study(g.code, g.entry);
  });

  void _filter(Book? b) => setState(() {
    _book = b;
    _uses.clear();
    _loadUses();
  });

  String get _verseLanguage => widget.ref.book.id < 40 ? 'Hebrew' : 'Greek';

  String get _language => languageOf(_code ?? '', morph: _tag?.morph ?? '');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final english = widget.english;
    return Scaffold(
      appBar: AppBar(title: const Text('Word study')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text(
                [
                  if (english != null) '"$english"',
                  widget.ref.label,
                  widget.translation,
                ].join(' · '),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (_code == null)
                Text(
                  english == null
                      ? 'Choose a word from ${widget.ref.label}.'
                      : _supplied
                      ? 'The translators supplied "$english" here so the English reads well; no '
                            '$_verseLanguage word stands behind it. Choose a word from the verse:'
                      : 'Berea could not tell which $_verseLanguage word is behind "$english" '
                            'here. It may be a word the translators added. Choose one:',
                  style: const TextStyle(height: 1.45),
                )
              else
                ..._header(scheme),
              if (_verseWords.isNotEmpty) ..._verseRow(scheme),
              if (_code != null) ..._body(scheme),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _header(ColorScheme scheme) {
    final e = _entry;
    final tag = _tag;
    final here = tag == null ? '' : cleanOriginal(tag.original);
    final lemma = e?.lemma ?? here;
    return [
      Text(
        lemma,
        style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 34, height: 1.2),
      ),
      Text(
        [
          if (e != null && e.translit.isNotEmpty) e.translit,
          _code!,
          _language,
          if (e != null && partOfSpeech(e.pos).isNotEmpty) partOfSpeech(e.pos),
        ].join(' · '),
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
      if (e != null && e.gloss.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            e.gloss,
            style: TextStyle(color: scheme.primary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      if (tag != null && here.isNotEmpty && here != lemma)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'In ${widget.ref.label}: $here (${tag.translit}), "${cleanGloss(tag.gloss, strongs: tag.strongs)}"',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
      const SizedBox(height: 16),
      if (e != null)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text('Ask Berea about $lemma'),
              onPressed: () => widget.onAsk(
                wordStudyQuestion(
                  entry: e,
                  language: _language,
                  english: tag == null ? null : widget.english,
                  ref: tag == null ? null : widget.ref,
                ),
              ),
            ),
            if (widget.onKeep != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save word'),
                onPressed: () => _keep(e, lemma),
              ),
          ],
        ),
    ];
  }

  /// Files the word as a note titled with the word and its gloss; see [keptWordBody].
  void _keep(LexEntry e, String lemma) {
    final from = _tag == null ? null : widget.ref;
    widget.onKeep!(
      title: e.gloss.isEmpty ? lemma : '$lemma, ${e.gloss}',
      body: keptWordBody(
        code: _code!,
        meaning: e.definition.isEmpty ? e.gloss : e.definition,
        translit: e.translit,
        language: _language,
        from: from,
        translation: widget.translation,
      ),
      subtitle: [
        if (e.gloss.isNotEmpty) e.gloss,
        _code!,
        if (from != null) 'from ${from.label}, ${widget.translation}',
      ].join(' · '),
      verse: from,
    );
  }

  /// The original words of the verse, so a wrong guess is one tap from the right word.
  List<Widget> _verseRow(ColorScheme scheme) => [
    const SizedBox(height: 20),
    Text(
      _guessed
          ? 'Chosen by meaning. Not the word you meant? Choose another from ${widget.ref.label}:'
          : 'Words in ${widget.ref.label}',
      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    ),
    const SizedBox(height: 6),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: widget.ref.book.id < 40,
      child: Row(
        textDirection: widget.ref.book.id < 40 ? TextDirection.rtl : TextDirection.ltr,
        children: [
          for (final w in _verseWords)
            if (studyCode(w) != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  selected: identical(w, _tag),
                  showCheckmark: false,
                  onSelected: (_) => _pick(w),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(cleanOriginal(w.original), style: const TextStyle(fontSize: 17)),
                      Text(
                        cleanGloss(w.gloss, strongs: w.strongs),
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    ),
  ];

  List<Widget> _body(ColorScheme scheme) {
    final e = _entry;
    final heading = TextStyle(
      fontSize: 12,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      color: scheme.onSurfaceVariant,
    );
    final full = _code!.startsWith('G') ? widget.db.fullLexicon(e?.key ?? _code!) : null;
    final others = [
      for (final g in _glossed)
        if (g.code != _code) g,
    ].take(glossedWordsShown).toList();
    final english = widget.english;
    return [
      const SizedBox(height: 24),
      Text('MEANING', style: heading),
      const SizedBox(height: 6),
      SelectableText(
        e == null || e.definition.isEmpty ? 'No lexicon entry for $_code.' : e.definition,
        style: const TextStyle(height: 1.5),
      ),
      if (full != null)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Full LSJ entry'),
          children: [SelectableText(full, style: const TextStyle(height: 1.45))],
        ),
      const SizedBox(height: 24),
      Text('USE', style: heading),
      const SizedBox(height: 6),
      Text(
        _count.uses == 0
            ? 'Not found anywhere else in the tagged text.'
            : 'Used ${_times(_count.uses)} in ${_plural(_count.verses, 'verse')} across '
                  '${_plural(_books.length, 'book')}.',
      ),
      if (_glosses.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Glossed as', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (g, n) in _glosses.take(8))
              Chip(label: Text('$g · $n'), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
      if (_books.length > 1) ...[
        const SizedBox(height: 10),
        Text(
          'By book (tap to show only that book)',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (b, n) in _books)
              FilterChip(
                label: Text('${b.name} $n'),
                visualDensity: VisualDensity.compact,
                selected: _book?.id == b.id,
                onSelected: (on) => _filter(on ? b : null),
              ),
          ],
        ),
      ],
      if (english != null && others.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('OTHER WORDS GLOSSED "${english.toUpperCase()}"', style: heading),
        const SizedBox(height: 2),
        Text(
          'One English word can stand for several Hebrew and Greek words.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        for (final g in others)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${g.entry?.lemma ?? g.code}  ${g.entry?.translit ?? ''}',
              style: TextStyle(fontFamilyFallback: scriptureFontFallback, fontSize: 17),
            ),
            subtitle: Text(
              '${languageOf(g.code)} · ${g.code} · "${g.entry?.gloss ?? ''}" · glossed '
              '"$english" ${_times(g.glossed)} of ${g.uses}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _switchTo(g),
          ),
      ],
      const SizedBox(height: 24),
      Text(_book == null ? 'EVERY VERSE' : 'IN ${_book!.name.toUpperCase()}', style: heading),
      for (final u in _uses) _UseTile(use: u, onTap: () => widget.onOpen(u.ref)),
      if (_more)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(_loadUses), child: const Text('Show more')),
        ),
    ];
  }

  static String _times(int n) => n == 1 ? 'once' : (n == 2 ? 'twice' : '$n times');
  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
}

/// One verse that uses the word, with the English words that render it marked.
class _UseTile extends StatelessWidget {
  final WordUse use;
  final VoidCallback onTap;
  const _UseTile({required this.use, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = use.text;
    final marks = text == null
        ? const <(int, int)>[]
        : ({for (final w in use.words) ...glossRanges(text, w.gloss, strongs: w.strongs)}.toList()
            ..sort((a, b) => a.$1.compareTo(b.$1)));
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in marks) {
      if (start < at) continue;
      spans
        ..add(TextSpan(text: text!.substring(at, start)))
        ..add(
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
          ),
        );
      at = end;
    }
    final here = use.words.map((w) => cleanOriginal(w.original)).toSet().join(', ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${use.ref.label} · $here',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamilyFallback: scriptureFontFallback,
              ),
            ),
            const SizedBox(height: 2),
            text == null
                ? Text(
                    'Not at this reference in this translation.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                : Text.rich(
                    TextSpan(
                      style: scriptureStyle(context),
                      children: [
                        ...spans,
                        TextSpan(text: text.substring(at)),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
