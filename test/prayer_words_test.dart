import 'package:berea/prayer_plan_store.dart';
import 'package:berea/prayer_screen.dart';
import 'package:berea/prayer_store.dart';
import 'package:berea/prayer_today.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'prayer_screen_test.dart' show fakePassage;

PrayerTopic _topic(String id, String group, String title, List<String> words, List<String> texts) =>
    PrayerTopic(id, group, title, words, [
      for (var i = 0; i < texts.length; i++) PrayerPoint(texts[i], 'Isaiah 41:10'),
    ]);

final content = PrayerContent(
  topics: [
    _topic('praise', 'Every day', 'Praise', ['worship'], ['Praise line.']),
    _topic('confession', 'Every day', 'Confession', ['sin'], ['Confess line.']),
    _topic('thanksgiving', 'Every day', 'Thanksgiving', ['thanks'], ['Thank line.']),
    _topic('others', 'Every day', 'For others', ['people'], ['Others line.']),
    _topic(
      'farming',
      'Daily life',
      'Farming, rain and harvest',
      ['crops', 'rain'],
      ['Send rain.', 'Bless the seed.', 'Give me patience.'],
    ),
    _topic('fear', 'The heart', 'Fear and worry', ['afraid'], ['Hold me.']),
  ],
  biblePrayers: [
    BiblePrayer('lords-prayer', "The Lord's Prayer", 'Matthew 6:9-13'),
    BiblePrayer('shepherd', 'The shepherd', 'Psalm 23'),
  ],
);

void main() {
  late PrayerStore store;
  late List<String> shared;

  setUp(() {
    store = PrayerStore(
      sqlite3.openInMemory()
        ..execute(prayerSchema)
        ..execute(prayerPlanSchema),
    );
    shared = [];
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app({TodayPrayer? Function()? today, PrayerContent? words}) => MaterialApp(
    home: Scaffold(
      body: PrayerScreen(
        store: store,
        passage: fakePassage,
        translation: () => 'BSB',
        share: (t, origin) async => shared.add(t),
        content: words ?? content,
        todayPrayer: today,
      ),
    ),
  );

  testWidgets('a new reader finds words to pray, opens a topic and prays its points', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Find words to pray'));
    await tester.pumpAndSettle();

    expect(find.text('Prayers of the Bible'), findsOneWidget);
    expect(find.text('EVERY DAY'), findsOneWidget);
    expect(find.text('Farming, rain and harvest'), findsOneWidget);
    await tester.tap(find.text('Farming, rain and harvest'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 prayer points from the Bible'), findsOneWidget);
    expect(find.text('Send rain.'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Pray these now'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('Bless the seed.'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amen'));
    await tester.pumpAndSettle();
    expect(find.text('Farming, rain and harvest'), findsWidgets);
  });

  testWidgets('Add to my list opens the new prayer sheet on the topic, and keeps it', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Find words to pray'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Farming, rain and harvest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to my list'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Farming, rain and harvest'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final p = store.praying().single;
    expect(p.topic, 'farming');
    expect(p.verse, 'Isaiah 41:10');
  });

  testWidgets('search finds a topic by the words people type', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Find words to pray'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search topics'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my crops need rain');
    await tester.pumpAndSettle();
    expect(find.text('Farming, rain and harvest'), findsOneWidget);
    expect(find.text('Praise'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No topic fits'), findsOneWidget);
  });

  testWidgets('Prayers of the Bible pray a passage a verse at a time', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Find words to pray'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prayers of the Bible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("The Lord's Prayer"));
    await tester.pumpAndSettle();
    expect(find.text('Our Father in heaven, hallowed be Your name,'), findsOneWidget);
  });

  testWidgets("the list shows today's prayer and topics that match the reader's prayers first", (
    tester,
  ) async {
    phone(tester);
    store.add(title: 'Rain for the harvest', note: 'The crops are dry');
    await tester.pumpWidget(
      app(
        today: () => const TodayPrayer(
          PrayerPoint('Lord, lift my eyes.', 'Isaiah 41:10'),
          "in today's plan",
        ),
      ),
    );

    expect(find.text("TODAY'S PRAYER · IN TODAY'S PLAN"), findsOneWidget);
    expect(find.text('Lord, lift my eyes.'), findsOneWidget);
    expect(find.text('All 6 topics'), findsOneWidget);
    final cards = find.byType(Card);
    final firstTitle = find.descendant(of: cards.first, matching: find.byType(Text)).first;
    expect(tester.widget<Text>(firstTitle).data, 'Farming, rain and harvest');
    await tester.tap(find.text('Pray it'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('without the bundled lines Prayer is the list alone', (tester) async {
    phone(tester);
    store.add(title: 'Rain for the harvest');
    await tester.pumpWidget(app(words: PrayerContent.empty));
    expect(find.text('From the Word'.toUpperCase()), findsNothing);
    expect(find.textContaining('topics'), findsNothing);
    expect(find.text('Pray now · 1 prayer'), findsOneWidget);
  });

  testWidgets('Pray now opens with praise, confession and thanks, asks, then others', (
    tester,
  ) async {
    phone(tester);
    store.add(title: 'Rain for the harvest');
    store.add(title: 'Peace for Brian');
    await tester.pumpWidget(app());
    await tester.tap(find.text('Pray now · 2 prayers'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 6'), findsOneWidget);
    expect(find.text('Praise line.'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('Confess line.'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('Thank line.'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 6'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('Others line.'), findsOneWidget);
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(find.text('You prayed for 2 requests today.'), findsOneWidget);
    expect(store.praying().where((p) => p.daysPrayed == 1).length, 2);
  });

  testWidgets('Ask only goes straight to the list, and Amen on the frame records no day', (
    tester,
  ) async {
    phone(tester);
    final id = store.add(title: 'Rain for the harvest');
    await tester.pumpWidget(app());
    await tester.tap(find.text('Pray now · 1 prayer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amen, next'));
    await tester.pumpAndSettle();
    expect(store.prayer(id)!.daysPrayed, 0);
    await tester.tap(find.text('Ask only'));
    await tester.pumpAndSettle();
    expect(find.text('Rain for the harvest'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
  });

  testWidgets('a prayer that keeps a topic is prayed with two lines from it', (tester) async {
    phone(tester);
    store.add(title: 'Rain for the harvest', topic: 'farming');
    await tester.pumpWidget(app(words: PrayerContent(topics: content.topics.sublist(4, 5))));
    await tester.tap(find.text('Pray now · 1 prayer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRAY IT WITH THE WORD'), findsOneWidget);
    expect(find.text('Send rain.'), findsOneWidget);
    expect(find.text('Bless the seed.'), findsOneWidget);
    expect(find.text('Give me patience.'), findsNothing);
  });

  testWidgets('a new prayer is offered verses from its own words, and the topic with it', (
    tester,
  ) async {
    phone(tester);
    store.add(title: 'Something else');
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Add a prayer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What are you praying for?'),
      'Rain for my crops',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('A verse to stand on'), findsOneWidget);
    expect(find.text("Pray the topic's points with it"), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Isaiah 41:10'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final p = store.praying().firstWhere((p) => p.title == 'Rain for my crops');
    expect(p.verse, 'Isaiah 41:10');
    expect(p.topic, 'farming');
  });

  testWidgets('with no match the sheet offers the verses many people stand on', (tester) async {
    phone(tester);
    store.add(title: 'Something else');
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Add a prayer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What are you praying for?'),
      'My sister',
    );
    await tester.pumpAndSettle();
    expect(find.text('Verses many people stand on'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Philippians 4:6-7'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a wide window opens a topic beside the list, and closes it', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.add(title: 'Rain for the harvest');
    await tester.pumpWidget(app());

    await tester.tap(find.text('Farming, rain and harvest').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close the topic'), findsOneWidget);
    expect(find.text('Send rain.'), findsOneWidget);
    expect(find.text('Pray these now'), findsOneWidget);
    await tester.tap(find.byTooltip('Close the topic'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close the topic'), findsNothing);
  });

  testWidgets('a topic shares as numbered text with its verses', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.text('Find words to pray'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Farming, rain and harvest'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share as text'));
    await tester.pump();
    expect(
      shared.single,
      'Farming, rain and harvest\n1. Send rain. (Isaiah 41:10)\n2. Bless the seed. '
      '(Isaiah 41:10)\n3. Give me patience. (Isaiah 41:10)',
    );
  });
}
