import 'package:berea/prayer_screen.dart';
import 'package:berea/prayer_plan_tables.dart';
import 'package:berea/prayer_store.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const isaiah4110 = 'Do not fear, for I am with you; do not be afraid, for I am your God.';
const lordsPrayerLines = [
  'Our Father in heaven, hallowed be Your name,',
  'Your kingdom come, Your will be done,',
  'Give us this day our daily bread.',
  'And forgive us our debts,',
  'And lead us not into temptation,',
];

/// Isaiah 41:10, Matthew 6:9-13 and 1 Thessalonians 5:16-18, in place of a Bible database.
List<Verse> fakePassage(Ref ref) => switch ((ref.book.id, ref.chapter)) {
  (23, 41) => [Verse(ref.book, 41, 10, isaiah4110)],
  (40, 6) => [
    for (var i = 0; i < lordsPrayerLines.length; i++)
      Verse(ref.book, 6, 9 + i, lordsPrayerLines[i]),
  ],
  (52, 5) => [Verse(ref.book, 5, 16, 'Rejoice at all times.')],
  _ => const [],
};

void main() {
  late PrayerStore store;
  late List<String> shared;
  late List<Rect?> origins;

  setUp(() {
    store = PrayerStore(sqlite3.openInMemory()..execute(prayerSchema)..execute(prayerPlanSchema));
    shared = [];
    origins = [];
  });

  /// A phone-sized window; the default test surface is wide enough for the Mac layout.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app() => MaterialApp(
    home: Scaffold(
      body: PrayerScreen(
        store: store,
        passage: fakePassage,
        translation: () => 'BSB',
        share: (t, origin) async {
          shared.add(t);
          origins.add(origin);
        },
      ),
    ),
  );

  testWidgets('first time explains Prayer and adds a prayer from the sheet', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    expect(find.text('Bring it to God, and remember the answer'), findsOneWidget);
    expect(find.text('1 Thessalonians 5:16-18 · BSB'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Nothing is sent anywhere'), findsOneWidget);

    await tester.tap(find.text('Add a prayer'));
    await tester.pumpAndSettle();
    expect(find.text('New prayer'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    // Saving with nothing written says why.
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Write what you are praying for first.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'What are you praying for?'),
      'Mama’s knee operation',
    );
    await tester.enterText(find.widgetWithText(TextField, 'For whom (optional)'), 'Mama');
    await tester.enterText(
      find.widgetWithText(TextField, 'A verse to pray (optional)'),
      'isa 41:10',
    );
    await tester.pump();
    expect(find.text(isaiah4110), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final p = store.praying().single;
    expect(p.title, 'Mama’s knee operation');
    expect(p.verse, 'Isaiah 41:10');
    expect(find.text('PRAYING · 1'), findsOneWidget);
    expect(find.text('Isaiah 41:10'), findsOneWidget);
    expect(find.text('added today'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a verse from the Bible opens the sheet already filled in', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showPrayerSheet(context, store, verse: 'Isaiah 41:10', passage: fakePassage),
            child: const Text('Pray'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pray'));
    await tester.pumpAndSettle();
    expect(find.text(isaiah4110), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'What are you praying for?'), 'Courage');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.praying().single.verse, 'Isaiah 41:10');
  });

  testWidgets('a prefilled title shows in the new prayer sheet and saves', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrayerSheet(context, store, title: 'Strength for Mum'),
            child: const Text('Pray'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pray'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Strength for Mum'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.praying().single.title, 'Strength for Mum');
  });

  testWidgets('the list shows Praying and Answered and shares as text', (tester) async {
    phone(tester);
    store.add(title: 'Rain for the harvest', forWhom: 'Uncle Ssali');
    final job = store.add(title: 'Job interview at the bank', forWhom: 'Me');
    store.markAnswered(job, 'I got the job.');
    await tester.pumpWidget(app());

    expect(find.text('PRAYING · 1'), findsOneWidget);
    expect(find.text('Rain for the harvest'), findsOneWidget);
    expect(find.text('Answered · 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Share the list'));
    expect(shared.single, 'Praying for\n- Rain for the harvest (for Uncle Ssali)');

    await tester.tap(find.text('Answered · 1'));
    await tester.pumpAndSettle();
    expect(find.text('I got the job.'), findsOneWidget);
    expect(find.text('answered today'), findsOneWidget);
    await tester.tap(find.text('Share a testimony'));
    await tester.pumpAndSettle();
    expect(find.text('This exact text is shared. Nothing else.'), findsOneWidget);
    await tester.tap(find.text('Share'));
    expect(shared.last, 'Answered prayer: Job interview at the bank\nI got the job.');
  });

  testWidgets('marking a prayer answered keeps the line and offers Undo', (tester) async {
    phone(tester);
    store.add(title: 'Safe journey to Gulu');
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Answered'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'We arrived safely.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.answered().single.answer, 'We arrived safely.');
    expect(find.text('Moved to Answered'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.answered(), isEmpty);
    expect(find.text('Safe journey to Gulu'), findsOneWidget);
  });

  testWidgets('the sheet asks for verses, not a whole chapter', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Add a prayer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What are you praying for?'), 'Rest');
    await tester.enterText(
      find.widgetWithText(TextField, 'A verse to pray (optional)'),
      'Psalm 23',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Choose a verse or a few verses, such as Psalm 23:1-4.'), findsOneWidget);
    expect(store.isEmpty, isTrue);

    await tester.enterText(
      find.widgetWithText(TextField, 'A verse to pray (optional)'),
      'Psalm 23:1-4',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.praying().single.verse, 'Psalms 23:1-4');
  });

  testWidgets('Still praying offers Undo that brings back the line and the date', (tester) async {
    phone(tester);
    var clock = DateTime(2026, 8, 3, 9);
    store = PrayerStore(sqlite3.openInMemory()..execute(prayerSchema)..execute(prayerPlanSchema), now: () => clock);
    final job = store.add(title: 'Job interview at the bank');
    store.markAnswered(job, 'I got the job.');
    clock = DateTime(2026, 10, 28, 9);
    await tester.pumpWidget(MaterialApp(home: AnsweredScreen(store: store)));
    expect(find.text('1 answered since August, newest first.'), findsOneWidget);

    await tester.tap(find.text('Still praying'));
    await tester.pumpAndSettle();
    expect(store.answered(), isEmpty);
    expect(find.textContaining('Nothing is marked answered yet.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final back = store.answered().single;
    expect(back.answer, 'I got the job.');
    expect(back.answered, DateTime(2026, 8, 3, 9));
  });

  testWidgets('the Answered row shows the latest answer and when', (tester) async {
    phone(tester);
    store.add(title: 'Rain for the harvest');
    const long = 'Job interview at the bank on Kampala Road, with the manager and two others';
    store.markAnswered(store.add(title: long), '');
    await tester.pumpWidget(app());
    final title = tester.renderObject<RenderParagraph>(find.text(long));
    expect(title.didExceedMaxLines, isTrue, reason: 'the title gives way');
    final day = tester.getRect(find.text(', today'));
    expect(day.right, lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.chevron_right)).left));
  });

  testWidgets('Delete asks first, and a stopped prayer can be resumed', (tester) async {
    phone(tester);
    final rain = store.add(title: 'Rain for the harvest');
    store.add(title: 'Wisdom in the new job');
    await tester.pumpWidget(app());

    await tester.tap(find.text('Rain for the harvest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this prayer?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(store.prayer(rain), isNotNull);

    await tester.tap(find.text('Stop praying'));
    await tester.pumpAndSettle();
    expect(find.text('PRAYING · 1'), findsOneWidget);
    await tester.tap(find.text('No longer praying · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(store.prayer(rain)!.archived, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('PRAYING · 2'), findsOneWidget);
    expect(find.textContaining('No longer praying'), findsNothing);
  });


}
