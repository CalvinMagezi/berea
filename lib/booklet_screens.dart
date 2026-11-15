import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'booklets.dart';
import 'notebook_store.dart';
import 'notebooks_screen.dart' show createNotebook;
import 'theme.dart';

const _labelSpacing = 1.2;
const _pagePadding = 16.0;
const _cardRadius = 12.0;
const _bar = 2.0;

TextStyle _muted(BuildContext context) =>
    TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);

/// The booklet's text with its bold and italic marks drawn.
List<InlineSpan> bookletSpans(String s) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final m in bookletInline.allMatches(s)) {
    if (m.start > cursor) spans.add(TextSpan(text: s.substring(cursor, m.start)));
    spans.add(
      m[1] != null
          ? TextSpan(
              text: m[1],
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          : TextSpan(
              text: m[2],
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
    );
    cursor = m.end;
  }
  if (cursor < s.length) spans.add(TextSpan(text: s.substring(cursor)));
  return spans;
}

/// A booklet's blocks as they read on a screen. A quotation that names a Bible reference gets a
/// button that opens it in the Bible, so the reader can see it in a translation they have.
class BookletBlocks extends StatelessWidget {
  final List<BookletBlock> blocks;
  final void Function(Ref)? onOpenRef;
  const BookletBlocks(this.blocks, {super.key, this.onOpenRef});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final b in blocks) _block(context, b)],
  );

  Widget _block(BuildContext context, BookletBlock b) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge!.copyWith(height: 1.6);
    switch (b) {
      case BookletHeading(level: 3, :final text):
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text.rich(
            TextSpan(children: bookletSpans(text)),
            style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      case BookletHeading(:final text):
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            plainInline(text).toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: _labelSpacing, color: scheme.primary),
          ),
        );
      case BookletParagraph(:final text):
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText.rich(TextSpan(style: body, children: bookletSpans(text))),
        );
      case BookletList(:final items):
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 22, child: Text('•', style: body)),
                      Expanded(
                        child: SelectableText.rich(
                          TextSpan(style: body, children: bookletSpans(item)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case BookletQuote(:final text, :final cite):
        final ref = cite == null ? null : RefParser.parse(cite).firstOrNull;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText.rich(
                  TextSpan(
                    style: body.copyWith(fontStyle: FontStyle.italic),
                    children: bookletSpans(text),
                  ),
                ),
                if (cite != null)
                  Row(
                    children: [
                      Flexible(child: Text(cite, style: _muted(context))),
                      if (ref != null && onOpenRef != null)
                        IconButton(
                          tooltip: 'Open ${ref.label} in the Bible',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.menu_book_outlined, size: 18),
                          onPressed: () => onOpenRef!(ref),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      case BookletCallout(:final title, :final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: _labelSpacing,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText.rich(TextSpan(style: body, children: bookletSpans(text))),
                  ],
                ),
              ),
            ),
          ),
        );
      case BookletNote(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: _muted(context).copyWith(fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        );
    }
  }
}

/// Says whose words these are and what they are not, under a booklet's title.
class BookletLabelLine extends StatelessWidget {
  final Booklet booklet;
  const BookletLabelLine(this.booklet, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(
      [bookletLabel, if (booklet.author case final a?) 'By $a.'].join(' '),
      style: _muted(context).copyWith(fontStyle: FontStyle.italic),
    ),
  );
}

Widget _page(Widget child) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: contentMaxWidth),
    child: child,
  ),
);

/// Opens booklet [b] at its contents.
void openBooklet(BuildContext context, AppState s, Booklet b) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => BookletScreen(state: s, booklet: b),
  ),
);

/// Opens booklet [b] at section [index].
void openBookletSection(BuildContext context, AppState s, Booklet b, int index) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => BookletSectionScreen(state: s, booklet: b, index: index),
  ),
);

/// A booklet's contents: its sections with what has been read, and the way to start reading it
/// as a plan or to copy it into a notebook.
class BookletScreen extends StatelessWidget {
  final AppState state;
  final Booklet booklet;
  const BookletScreen({super.key, required this.state, required this.booklet});

  @override
  Widget build(BuildContext context) {
    final reading = state.bookletReading;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(booklet.short, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'Booklet options',
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => addBookletToNotebook(context, state, booklet),
                child: const Text('Add to a notebook'),
              ),
            ],
          ),
        ],
      ),
      body: _page(
        ListenableBuilder(
          listenable: reading,
          builder: (context, _) {
            final next = reading.next(booklet);
            final done = reading.readCount(booklet);
            final index = next == null ? 0 : booklet.sections.indexOf(next);
            return ListView(
              padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 32),
              children: [
                Text(
                  booklet.title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(booklet.subtitle, style: Theme.of(context).textTheme.bodyLarge),
                BookletLabelLine(booklet),
                Text(
                  '${booklet.sections.length} sections · ${booklet.words} words · '
                  'about ${booklet.minutes} minutes',
                  style: _muted(context),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (next != null)
                      FilledButton.icon(
                        onPressed: () {
                          reading.start(booklet.id);
                          openBookletSection(context, state, booklet, index);
                        },
                        icon: const Icon(Icons.menu_book_outlined),
                        label: Text(done == 0 ? 'Start reading' : 'Continue reading'),
                      )
                    else
                      Text('Every section is read.', style: TextStyle(color: scheme.primary)),
                    if (done > 0)
                      TextButton(
                        onPressed: () => reading.startOver(booklet.id),
                        child: const Text('Start over'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$done of ${booklet.sections.length} sections read', style: _muted(context)),
                const SizedBox(height: 16),
                for (var i = 0; i < booklet.sections.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      reading.isRead(booklet.id, booklet.sections[i].id)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: reading.isRead(booklet.id, booklet.sections[i].id)
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      semanticLabel: reading.isRead(booklet.id, booklet.sections[i].id)
                          ? 'Read'
                          : 'Not read',
                    ),
                    title: Text(plainInline(booklet.sections[i].title)),
                    subtitle: Text('${booklet.sections[i].words} words', style: _muted(context)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openBookletSection(context, state, booklet, i),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One section of a booklet, with the buttons to mark it read and to move on.
class BookletSectionScreen extends StatefulWidget {
  final AppState state;
  final Booklet booklet;
  final int index;
  const BookletSectionScreen({
    super.key,
    required this.state,
    required this.booklet,
    required this.index,
  });

  @override
  State<BookletSectionScreen> createState() => _BookletSectionScreenState();
}

class _BookletSectionScreenState extends State<BookletSectionScreen> {
  late var _index = widget.index;

  @override
  Widget build(BuildContext context) {
    final b = widget.booklet;
    final section = b.sections[_index];
    final reading = widget.state.bookletReading;
    return Scaffold(
      appBar: AppBar(title: Text(b.short, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _page(
        ListView(
          key: ValueKey(_index),
          padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 32),
          children: [
            Text(
              '${_index + 1} of ${b.sections.length}'.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: _labelSpacing,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              plainInline(section.title),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            BookletLabelLine(b),
            const SizedBox(height: 8),
            BookletBlocks(section.blocks, onOpenRef: widget.state.openInReader),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: reading,
              builder: (context, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: reading.isRead(b.id, section.id),
                onChanged: (v) => reading.setRead(b.id, section.id, v ?? false),
                title: const Text('Mark this section read'),
              ),
            ),
            Row(
              children: [
                if (_index > 0)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _index--),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                const Spacer(),
                if (_index < b.sections.length - 1)
                  FilledButton.icon(
                    onPressed: () => setState(() => _index++),
                    icon: const Icon(Icons.chevron_right),
                    iconAlignment: IconAlignment.end,
                    label: const Text('Next'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Plans: the booklets, each started like a plan and read a section at a time. Sections are
/// ticked as they are read, with no dates and no count of days in a row.
class BookletPlans extends StatelessWidget {
  final AppState state;
  const BookletPlans({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.booklets.isEmpty) return const SizedBox.shrink();
    final reading = state.bookletReading;
    return ListenableBuilder(
      listenable: reading,
      builder: (context, _) {
        final running = [
          for (final b in state.booklets)
            if (reading.isStarted(b.id)) b,
        ];
        final others = [
          for (final b in state.booklets)
            if (!reading.isStarted(b.id)) b,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(
                'BOOKLETS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            for (final b in running) _Running(state: state, booklet: b),
            for (final b in others)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text(b.short),
                subtitle: Text('${b.sections.length} sections · about ${b.minutes} minutes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openBooklet(context, state, b),
              ),
          ],
        );
      },
    );
  }
}

class _Running extends StatelessWidget {
  final AppState state;
  final Booklet booklet;
  const _Running({required this.state, required this.booklet});

  @override
  Widget build(BuildContext context) {
    final reading = state.bookletReading;
    final scheme = Theme.of(context).colorScheme;
    final next = reading.next(booklet);
    final done = reading.readCount(booklet);
    final total = booklet.sections.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${booklet.short} · ${next == null ? 'all read' : 'section ${done + 1} of $total'}'
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    PopupMenuButton<void>(
                      tooltip: 'Booklet options',
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          onTap: () => openBooklet(context, state, booklet),
                          child: const Text('Contents'),
                        ),
                        PopupMenuItem(
                          onTap: () => reading.startOver(booklet.id),
                          child: const Text('Start over'),
                        ),
                        PopupMenuItem(
                          onTap: () => reading.stop(booklet.id),
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (next != null) ...[
                  Text(
                    plainInline(next.title),
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        openBookletSection(context, state, booklet, booklet.sections.indexOf(next)),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read'),
                  ),
                ] else
                  Text('Every section is read.', style: TextStyle(color: scheme.primary)),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  backgroundColor: scheme.outline.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(_bar),
                ),
                const SizedBox(height: 6),
                Text('$done of $total sections', style: _muted(context)),
                const SizedBox(height: 6),
                Text(
                  'Sections are ticked as you read them. No dates, no streak.',
                  style: _muted(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The prayers taken from the booklets, each shown whole under the booklet's name. They are not
/// in the person's own list and nothing is added to it.
class BookletPrayersScreen extends StatelessWidget {
  final AppState state;
  const BookletPrayersScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final prayers = bookletPrayers(state.booklets);
    return Scaffold(
      appBar: AppBar(title: const Text('Prayers from booklets')),
      body: _page(
        ListView(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 32),
          children: [
            Text(
              '$bookletPrayersSelector Your own prayers are in the list; these are not.',
              style: _muted(context).copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            for (final p in prayers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text(plainInline(p.title)),
                subtitle: Text(plainInline(p.where)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => BookletPrayerScreen(state: state, prayer: p),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BookletPrayerScreen extends StatelessWidget {
  final AppState state;
  final BookletPrayer prayer;
  const BookletPrayerScreen({super.key, required this.state, required this.prayer});

  @override
  Widget build(BuildContext context) {
    final b = prayer.booklet;
    return Scaffold(
      appBar: AppBar(title: Text(b.short, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _page(
        ListView(
          padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 32),
          children: [
            Text(
              plainInline(prayer.title),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            BookletLabelLine(b),
            const SizedBox(height: 8),
            BookletBlocks(prayer.blocks, onOpenRef: state.openInReader),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    openBookletSection(context, state, b, b.sections.indexOf(prayer.section)),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Read it in the booklet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _newNotebook = -1;

/// A message that replaces any showing and goes by itself, even with an action on it.
void _say(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, persist: false));
}

/// Copies the booklet into a notebook the reader picks, as a text source that keeps where it
/// came from, so it is searched with the notebook and sits beside the reader's own notes.
Future<void> addBookletToNotebook(BuildContext context, AppState s, Booklet b) async {
  final choices = [
    for (final n in s.notebooks.notebooks())
      if (!s.notebooks.isNotesOnVerses(n.id)) n,
  ];
  final choice = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add to a notebook'),
      children: [
        for (final n in choices)
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, n.id), child: Text(n.title)),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _newNotebook),
          child: const Text('New notebook'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final id = choice == _newNotebook ? await createNotebook(context, s.notebooks) : choice;
  if (id == null || !context.mounted) return;
  final notebook = s.notebooks.notebook(id);
  if (notebook == null) return;
  if (s.notebooks.sources(id).any((r) => r.title == b.short && r.origin == b.origin)) {
    _say(context, '${b.short} is already in ${notebook.title}.');
    return;
  }
  try {
    await s.notebooks.addSource(
      id,
      SourceRequest(SourceKind.text, b.short, origin: b.origin, text: b.plainText),
    );
    if (!context.mounted) return;
    _say(
      context,
      'Added to ${notebook.title}.',
      action: SnackBarAction(label: 'Open', onPressed: () => s.openNotebook(id)),
    );
  } on FormatException catch (e) {
    if (context.mounted) _say(context, e.message);
  }
}
