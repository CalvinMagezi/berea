import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bible.dart';

/// Hand-checked (verse, word, Strong's number) pairs, one verse a line: `Reference|word=number`,
/// where `word#2` is the word's third use in the verse. Each number is the original word the BSB's
/// own translation tables and the lexicon agree stands behind the English there.
const _golden = '''
Genesis 1:1|God=H430 created=H1254 heavens=H8064 earth=H776 beginning=H7225
Genesis 1:2|Spirit=H7307 waters=H4325 darkness=H2822 deep=H8415 formless=H8414
Genesis 1:3|said=H559 light=H216
Genesis 1:5|day=H3117 night=H3915 evening=H6153 morning=H1242
Genesis 1:26|image=H6754 likeness=H1823
Genesis 1:27|male=H2145 female=H5347 created=H1254
Genesis 2:4|LORD=H3068 God=H430
Genesis 2:7|dust=H6083 breath=H5397 being=H5315
Genesis 3:1|serpent=H5175 crafty=H6175
Genesis 6:8|Noah=H5146 favor=H2580 LORD=H3068
Genesis 12:2|nation=H1471 bless=H1288 name=H8034
Genesis 15:6|believed=H539 righteousness=H6666 LORD=H3068
Genesis 17:1|Almighty=H7706 Walk=H1980 blameless=H8549
Genesis 22:8|lamb=H7716 God=H430
Exodus 14:14|LORD=H3068 fight=H3898
Leviticus 19:18|love=H157 neighbor=H7453
Numbers 6:24|bless=H1288 LORD=H3068 keep=H8104
Numbers 6:25|face=H6440 shine=H215 gracious=H2603
Numbers 6:26|peace=H7965 LORD=H3068
Deuteronomy 6:4|Hear=H8085 LORD=H3068 God=H430 One=H259
Deuteronomy 6:5|love=H157 heart=H3824 soul=H5315
Psalm 1:2|delight=H2656 law=H8451
Psalm 23:1|shepherd=H7462 LORD=H3068 want=H2637
Psalm 23:4|valley=H1516 rod=H7626 staff=H4938 comfort=H5162
Psalm 27:1|light=H216 salvation=H3468 stronghold=H4581
Psalm 34:8|Taste=H2938 good=H2896 refuge=H2620
Psalm 46:1|refuge=H4268 strength=H5797 help=H5833 trouble=H6869
Psalm 51:10|clean=H2889 heart=H3820 spirit=H7307 right=H3559
Psalm 119:105|word=H1697 lamp=H5216 light=H216
Psalm 150:6|breath=H5397 praise=H1984
Proverbs 3:5|Trust=H982 LORD=H3068 heart=H3820 understanding=H998
Proverbs 9:10|fear=H3374 wisdom=H2451 knowledge=H1847
Isaiah 6:8|send=H7971 voice=H6963
Isaiah 9:6|child=H3206 son=H1121 Counselor=H3289 Peace=H7965
Isaiah 40:31|wait=H6960 strength=H3581 eagles=H5404
Isaiah 41:10|fear=H3372 afraid=H8159 God=H430 strengthen=H553 help=H5826 righteous=H6664
Isaiah 53:5|pierced=H2490 transgressions=H6588 iniquities=H5771 peace=H7965 healed=H7495
Jeremiah 29:11|plans=H4284 future=H319 hope=H8615
Habakkuk 2:4|faith=H530 live=H2421 righteous=H6662
Joel 2:28|Spirit=H7307 pour=H8210 sons=H1121 daughters=H1323 prophesy=H5012
Matthew 1:1|Jesus=G2424 Christ=G5547 David=G1138 Abraham=G11
Matthew 1:21|Jesus=G2424 save=G4982 sins=G266 people=G2992
Matthew 5:3|poor=G4434 spirit=G4151 kingdom=G932
Matthew 5:44|love=G25 enemies=G2190 pray=G4336 persecute=G1377
Matthew 6:9|Father=G3962 hallowed=G37 name=G3686
Matthew 6:33|seek=G2212 kingdom=G932 righteousness=G1343
Matthew 11:28|weary=G2872 rest=G373
Matthew 22:37|Love=G25 heart=G2588 soul=G5590 mind=G1271 Lord=G2962 God=G2316
Matthew 28:19|disciples=G3100 nations=G1484 baptizing=G907 Father=G3962 Son=G5207 Spirit=G4151 name=G3686
Matthew 28:20|commanded=G1781 age=G165
Mark 1:15|time=G2540 kingdom=G932 Repent=G3340 believe=G4100 gospel=G2098
Mark 10:45|serve=G1247 ransom=G3083 Son=G5207
Luke 2:11|Savior=G4990 Christ=G5547 Lord=G2962 born=G5088
Acts 1:8|power=G1411 Spirit=G4151 witnesses=G3144
Acts 2:38|Repent=G3340 baptized=G907 forgiveness=G859 Jesus=G2424 Christ=G5547 Spirit=G4151 gift=G1431
Acts 4:12|Salvation=G4991 name=G3686
John 1:1|Word=G3056 God=G2316 beginning=G746
John 1:14|flesh=G4561 glory=G1391 grace=G5485 truth=G225 Father=G3962
John 3:3|born=G1080 kingdom=G932
John 3:16|God=G2316 loved=G25 world=G2889 Son=G5207 believes=G4100 eternal=G166 life=G2222 perish=G622 gave=G1325
John 11:35|Jesus=G2424 wept=G1145
John 13:34|commandment=G1785 new=G2537
John 14:6|way=G3598 truth=G225 life=G2222 Father=G3962
John 14:15|love=G25 keep=G5083 commandments=G1785
John 21:15|love=G25 love#1=G5368 lambs=G721
John 21:16|love=G25 love#1=G5368
John 21:17|love=G5368 love#1=G5368
Romans 3:23|sinned=G264 glory=G1391
Romans 5:8|love=G26 sinners=G268 died=G599 Christ=G5547 God=G2316
Romans 6:23|wages=G3800 sin=G266 death=G2288 gift=G5486 eternal=G166 Christ=G5547 Jesus=G2424 Lord=G2962
Romans 8:1|condemnation=G2631 Christ=G5547 Jesus=G2424
Romans 8:28|good=G18 love=G25 purpose=G4286
Romans 8:38|death=G2288 life=G2222 angels=G32 present=G1764 future=G3195
Romans 10:9|confess=G3670 Lord=G2962 Jesus=G2424 believe=G4100 raised=G1453 saved=G4982
Romans 12:2|conformed=G4964 transformed=G3339 renewing=G342 mind=G3563 will#1=G2307
1 Corinthians 13:4|Love=G26 patient=G3114 kind=G5541 envy=G2206 boast=G4068
1 Corinthians 13:13|faith=G4102 hope=G1680 love=G26
2 Corinthians 5:17|new=G2537 creation=G2937 Christ=G5547
2 Corinthians 5:21|sin=G266 righteousness=G1343
2 Corinthians 12:9|grace=G5485 power=G1411 weakness=G769 sufficient=G714
Galatians 2:20|crucified=G4957 Christ=G5547 faith=G4102 Son=G5207 loved=G25
Galatians 5:22|Spirit=G4151 love=G26 joy=G5479 peace=G1515 patience=G3115 kindness=G5544 goodness=G19 faithfulness=G4102
Ephesians 2:8|grace=G5485 faith=G4102 saved=G4982 gift=G1435
Ephesians 2:9|works=G2041
Philippians 4:6|anxious=G3309 prayer=G4335 thanksgiving=G2169 requests=G155
Philippians 4:7|peace=G1515 understanding=G3563 guard=G5432 hearts=G2588
Philippians 4:13|strength=G1743
Colossians 1:15|image=G1504 invisible=G517 firstborn=G4416 creation=G2937
1 Timothy 2:5|mediator=G3316 God=G2316 Christ=G5547 Jesus=G2424
2 Timothy 3:16|Scripture=G1124 useful=G5624 instruction=G1319 conviction=G1650 correction=G1882 training=G3809 righteousness=G1343
Hebrews 4:12|word=G3056 living=G2198 sword=G3162 soul=G5590 spirit=G4151 heart=G2588
Hebrews 11:1|faith=G4102 assurance=G5287
Hebrews 13:8|Jesus=G2424 Christ=G5547 yesterday=G5504 today=G4594 forever=G165
James 1:2|joy=G5479 trials=G3986
James 1:5|wisdom=G4678 lacks=G3007 ask=G154 God=G2316 generously=G574
1 Peter 5:7|anxiety=G3308 cares=G3199
1 John 1:9|confess=G3670 sins=G266 faithful=G4103 just=G1342 forgive=G863 cleanse=G2511 unrighteousness=G93
1 John 3:16|love=G26 laid=G5087 life=G5590
1 John 4:8|love=G25 love#1=G26 God=G2316
1 John 4:19|love=G25
Revelation 1:8|Alpha=G1 Omega=G5598 Almighty=G3841 Lord=G2962 God=G2316
Revelation 3:20|door=G2374 knock=G2925 voice=G5456
Revelation 21:4|tear=G1144 death=G2288 mourning=G3997 crying=G2906 pain=G4192
Revelation 22:13|Alpha=G1 First=G4413 Last=G2078 Beginning=G746 End=G5056
''';

/// Words that repeat in a verse, and the original word the press must pick among the repeats:
/// `Reference|word|gloss of the verse's tag`. Genesis 26:29 has "you will do" before "we have done",
/// both H6213, with an original word the BSB leaves out in between.
const _repeatedTags = [
  'Genesis 26:29|done|we have done',
];

/// A name pressed where the BSB wrote it onto a verb or pronoun: "Jesus replied" is one Greek
/// verb. None of these may open that verb as if it were the name.
const _namesOnOtherWords = [
  'John 21:17|Jesus#1',
  'Acts 1:7|Jesus',
  'Matthew 9:12|Jesus',
  'Acts 13:33|Jesus',
  'Hebrews 8:6|Jesus',
];

void main() {
  final skip = needsBuiltBible;
  late BibleDb db;
  setUpAll(() {
    if (skip == null) db = BibleDb.open(File('assets/berea.sqlite').absolute.path);
  });

  PressedWord? press(String ref, String word, int nth) {
    final r = RefParser.parse(ref).first;
    final text = db.passage(r).single.text;
    final all = verseWordPattern.allMatches(text).toList();
    final at = [
      for (var i = 0; i < all.length; i++)
        if (all[i][0] == word) i,
    ];
    if (at.length <= nth) return null;
    final index = at[nth];
    return pressedStudy(
      db,
      r,
      english: word,
      translation: defaultTranslation,
      occurrence: nth,
      wordIndex: index,
    );
  }

  test('at least 200 hand-checked words open the original word behind them', skip: skip, () {
    var checked = 0;
    final wrong = <String>[];
    for (final line in _golden.trim().split('\n')) {
      final parts = line.split('|');
      for (final pair in parts[1].split(' ')) {
        final eq = pair.indexOf('=');
        final key = pair.substring(0, eq).split('#');
        final p = press(parts[0], key[0], key.length > 1 ? int.parse(key[1]) : 0);
        final want = strongsBase(pair.substring(eq + 1));
        checked++;
        if (p == null) {
          wrong.add('${parts[0]} ${key[0]}: not in the verse');
        } else if (p.kind != PressKind.exact || p.code != want) {
          wrong.add('${parts[0]} ${key[0]}: wanted $want, got ${p.kind.name} ${p.code}');
        }
      }
    }
    expect(wrong, isEmpty);
    expect(checked, greaterThanOrEqualTo(200));
  });

  test('a word that repeats in a verse picks its own original word', skip: skip, () {
    for (final line in _repeatedTags) {
      final parts = line.split('|');
      final p = press(parts[0], parts[1], 0);
      expect(p?.kind, PressKind.exact, reason: line);
      expect(p?.tag?.gloss, parts[2], reason: line);
    }
  });

  test('a name the BSB wrote onto a verb or pronoun does not open that word', skip: skip, () {
    for (final line in _namesOnOtherWords) {
      final parts = line.split('|');
      final key = parts[1].split('#');
      final p = press(parts[0], key[0], key.length > 1 ? int.parse(key[1]) : 0);
      expect(p, isNotNull, reason: line);
      expect(p!.kind, isNot(PressKind.exact), reason: line);
      expect(p.kind, isNot(PressKind.supplied), reason: line);
    }
  });

  test('across the whole BSB no name or title of God opens a verb or a pronoun', skip: skip, () {
    final bad = <String>[];
    final lex = <String, LexEntry?>{};
    for (final r in db.db.select("SELECT book, chapter, verse, text FROM verses WHERE translation = 'BSB'")) {
      final ref = Ref(bookById(r['book'] as int), r['chapter'] as int, r['verse'] as int);
      final bsb = db.bsbWords(ref);
      if (bsb == null) continue;
      final words = verseWordPattern.allMatches(r['text'] as String).toList();
      for (var i = 0; i < words.length && i < bsb.length; i++) {
        final w = words[i][0]!;
        if (!const {'Jesus', 'Christ', 'God', 'LORD'}.contains(w) || bsb[i].code.isEmpty) continue;
        final pos = partOfSpeech(lex.putIfAbsent(bsb[i].code, () => db.lexicon(bsb[i].code))?.pos ?? '');
        final p = resolvePress(
          english: w,
          translation: defaultTranslation,
          tags: const [],
          lexicon: (c) => lex.putIfAbsent(c, () => db.lexicon(c)),
          isName: db.isName,
          bsb: bsb,
          wordIndex: i,
        );
        final opensWord = p.kind == PressKind.exact;
        final isNoun = pos.startsWith('noun') || pos.startsWith('name') || pos.startsWith('adjective');
        if (opensWord && !isNoun) bad.add('${ref.label} $w opens ${bsb[i].code} ($pos)');
      }
    }
    expect(bad, isEmpty);
  });
}
