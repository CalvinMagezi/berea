METHOD. Scripts: /tmp/claude-0/-home-user/238c2100-29fb-54dd-a418-155245010f46/scratchpad/probe/scripts/{bsb,tagnt,tahot,tahot_coh,extras,coverage,homograph}.py, run as `python3 -I <script> <probe/data> [/home/user/berea/site/data]`; outputs in probe/out. Fetched with curl from raw.githubusercontent.com/STEPBible/STEPBible-Data/master: 4 TAHOT, 2 TAGNT, TBESH, TBESG, README.md, "Morphology codes/TEHMC". Counts over raw files are measured. No built berea.sqlite exists in the repo, so what the app stores or shows is INFERRED from the Dart code. B = packages/harness/bin/build_db.dart; D = packages/harness/lib/src/bible_db.dart.

1 QUESTIONS (BSB 31,102 verses: OT 23,145, NT 7,957; 16 NT verse strings are empty)
Verses with "?": 2,527 (OT 1,706, NT 821); 3,198 question marks. Top 12 books: Job 218, John 143, Matthew 142, Luke 142, Jeremiah 138, Genesis 130, Isaiah 124, 1 Samuel 121, Psalms 113, Mark 99, 2 Samuel 97, 2 Kings 97. None: Zephaniah, 2 Timothy, Titus, Philemon, 2 John, 3 John, Jude.
Verses made only of question sentences: 1,129; 68 of them are 60 characters or fewer. Any verse with "?" and 60 characters or fewer: 102. Question sentences inside verses: 3,197, of which 1,615 are 60 characters or fewer.
Samples (seeded random from the 68): Job 19:2 “How long will you torment me and crush me with your words? | Job 27:9 Will God hear his cry when distress comes upon him? | Psalms 50:13 Do I eat the flesh of bulls, or drink the blood of goats? | Psalms 115:2 Why should the nations say, “Where is their God?” | Micah 6:11 Can I excuse dishonest scales or bags of false weights? | Matthew 6:27 Who of you by worrying can add a single hour to his life? | Matthew 22:36 “Teacher, which commandment is the greatest in the Law?” | Matthew 25:39 When did we see You sick or in prison and visit You?’ | Luke 11:12 Or if he asks for an egg, will give him a scorpion? | Luke 17:9 Does he thank the servant because he did what he was told? | Romans 11:35 “Who has first given to God, that God should repay him?” | 2 Corinthians 12:17 Did I exploit you by anyone I sent you?

2 GREEK IMPERATIVES (TAGNT 142,095 word rows, 7,958 verses; mood = third letter of V-xxM)
Imperative tokens 1,646: 2S 645, 2P 765, 3S 204, 3P 32 (present 868, aorist 773, perfect 5). In rows whose type includes N: 1,617 (2S 629, 2P 755, 3S 201, 3P 32). Verses with a second-person imperative: 1,045 (1,035 in N rows). 446 distinct lemmas.
Top 30 (N rows; dStrong, lemma, TBESG gloss, count): G1096 γίνομαι to be 45; G4160G ποιέω to do/make 43; G5217 ὑπάγω to go 38; G1325 δίδωμι to give 35; G2036 ἔπω/ἐρῶ/εἶπον to say 34; G0191 ἀκούω to hear 32; G5399 φοβέω to fear 29; G0991 βλέπω to see 27; G0782 ἀσπάζομαι to pay respects to 27; G4198 πορεύω to travel 26; G0142 αἴρω to take up 26; G1510 εἰμί to be 21; G1453 ἐγείρω to arise 20; G2064 ἔρχομαι to come/go 20; G0190 ἀκολουθέω to follow 18; G3306 μένω to stay 17; G4336 προσεύχομαι to pray 17; G5463 χαίρω to rejoice 17; G1125 γράφω to write 15; G1097 γινώσκω to know 14; G4043 περιπατέω to walk 14; G1831 ἐξέρχομαι to go out 14; G1492H εἴδω to perceive 13; G4100 πιστεύω to trust (in) 13; G1653 ἐλεέω/ἐλεάω to have mercy 13; G2983 λαμβάνω to take 12; G2919 κρίνω to judge 12; G4337 προσέχω to watch out 12; G0863I ἀφίημι to release 12; G2212 ζητέω to seek 12.
By book (all rows): Mat 290, Mrk 152, Luk 290, Jhn 129, Act 126, Rom 61, 1Co 100, 2Co 22, Gal 21, Eph 42, Php 25, Col 29, 1Th 20, 2Th 7, 1Ti 44, 2Ti 33, Tit 14, Phm 5, Heb 28, Jas 55, 1Pe 35, 2Pe 7, 1Jn 9, 2Jn 3, 3Jn 2, Jud 5, Rev 92.
Not counted by mood (adjacency, N rows): μή directly before a 2nd-person aorist subjunctive 103; μή before a 2nd-person present imperative 106; 2nd-person future indicatives 233.

3 HEBREW IMPERATIVES (TAHOT 305,648 word rows; verb form = third letter of the V segment)
Imperative (v): 4,305 (Hebrew 4,270, Aramaic 35) in 2,684 verses: 2ms 2,338, 2mp 1,630, 2fs 315, 2fp 22.
Jussive (j): 1,099 in 934 verses: 3ms 370, 2ms 346, 2mp 173, 3fs 95, 3mp 66, 2fs 36, first person 10.
Cohortative: the OpenScriptures letter h never occurs. TEHMC lines 3477 and 3487 define c plus a person as cohortative: 534 (1cs 358, 1cp 176) in 421 verses. The same c without a person is the infinitive construct (6,759).
Imperfect (i): 13,471, which TEHMC labels "Indicative/jussive" or "Indicative/cohortative"; 2,817 are second person. Negative particle directly before a 2nd-person verb: לֹא (H3808) + imperfect 724, אַל (H0408) + jussive 473, אַל + imperfect 42; 976 verses. Exo.20.2-17 and Deu.5.6-21 each hold 12 second-person imperfects and 1 imperative.
Top 30 (root dStrong, lemma, gloss from the Expanded tags field, count): H8085G שָׁמַע to hear 191; H1980G הָלַךְ to go 161; H3947G לָקַח to take 104; H6965B קוּם to arise 91; H0559 אָמַר to say 88; H7200G רָאָה to see 85; H1696G דָבַר to speak 82; H7725G שׁוּב to return 76; H6213A עָשָׂה to make: do 69; H0935G בּוֹא to come (in) 67; H5927G עָלָה to ascend 66; H5414G נָתַן to give 64; H3045 יָדַע to know 54; H1980K הָלַךְ to go: come[hortative] 53; H1984B הָלַל to boast: praise 52; H2142 זָכַר to remember 51; H3427 יָשַׁב to dwell 44; H7200I רָאָה to see: behold! 44; H5046 נָגַד to tell 43; H2388G חָזַק to strengthen 41; H3318G יָצָא to come out 35; H3051 יָהַב to give 34; H3381 יָרַד to go down 34; H0398 אָכַל to eat 33; H3467 יָשַׁע to save 32; H5186 נָטָה to stretch 31; H7971G שָׁלַח to send 31; H0238 אָזַן to listen 30; H1288 בָּרַךְ to bless 30; H5337 נָצַל to rescue 29. 607 distinct lemmas.
By book: Gen 298, Exo 198, Lev 41, Num 135, Deu 111, Jos 110, Jdg 133, Rut 25, 1Sa 208, 2Sa 136, 1Ki 166, 2Ki 183, 1Ch 71, 2Ch 92, Ezr 17, Neh 30, Est 12, Job 117, Psa 699, Pro 138, Ecc 28, Sng 34, Isa 355, Jer 396, Lam 29, Ezk 232, Dan 51, Hos 34, Jol 43, Amo 43, Oba 1, Jon 13, Mic 26, Nam 16, Hab 13, Zep 12, Hag 14, Zec 39, Mal 6.

4 COLUMNS AND WHAT B KEEPS
TAGNT (17 tab fields, 14 used). Kept: 1 Word & Type, ref and position only (B:282, :328); 2 Greek (transliteration) (B:330-332); 3 English translation, as gloss (B:336); 4 dStrongs = Grammar (B:334-335). Dropped: the type letters of field 1; 5 Dictionary form = Gloss; 6 Editions; 7 Meaning variants (3,866 rows, 2,643 verses); 8 Spelling variants (2,424); 9 Spanish translation; 10 Sub-meaning (differs from the lexicon gloss on 73,062 rows; person or place id with "@" on 5,446); 11 Conjoin word (41,049 rows link a word to its head word); 12 sStrong+Instance; 13 Alt Strongs (18,368); 14 Variant notes, described in the header but unnamed in the column row (3,386 rows, 1,640 with a sentence).
TAHOT (17 tab fields, 12 named). Kept: 1 Eng (Heb) Ref & Type, ref and position only; 2 Hebrew; 3 Transliteration; 4 Translation (B:308-310); 5 dStrongs, numbers only, space-joined (B:302); 6 Grammar (B:312). Dropped: the text type and bracketed Hebrew verse number of field 1 (21,915 rows); the braces in field 5 that mark the root; 7 Meaning variants (1,039 rows, 1,012 of them Ketiv readings "K="); 8 Spelling variants (1,592); 9 Root dStrong+Instance; 10 Alternative Strongs+Instance (5,464); 11 Conjoin word (empty everywhere, "Not yet implemented"); 12 Expanded Strong tags (lemma, gloss, sub-meaning after "»", person or place id).
Edition legend (header): N = Nestle-Aland (NA27 text, NA28 spelling); K = the Greek behind the KJV (Scrivener 1894); O = other editions; lower case = too minor to change a translation; brackets = variant. Rows by unbracketed type: NKO 132,893; NO 3,349; K 1,690; k 1,532; NK 714; KO 659; no 588; ko 284; O 175; o 110; N 68; n 33. Not NKO: 9,202 rows (6.5%) in 4,095 verses; no N reading: 4,450. Editions column missing at least one of eight editions: 10,156 rows (7.15%); missing NA28 4,177, NA27 4,087, Tyn (Tyndale House 2017) 4,571, SBL 4,886, WH (Westcott-Hort) 4,888, Treg (Tregelles) 4,722, TR 4,535, Byz (Robinson-Pierpont 2005) 4,856. 1,750 rows carry a word-order marker such as "TR»2".
Qere and Ketiv: 1,323 Qere rows in 1,149 verses (Q(K) 1,013, Q(k) 310); X (from the LXX) 152; R (restored) 27; other bracketed sources (Aleppo, BHS, Ben Chayim, punctuation, Dead Sea) 289. Header: "Most of these variants are yet to be added."
Speaker or quotation marking: none in either file. The BSB text has an opening “ in 5,496 verses.
Raw rows (¦ = tab, trailing empty fields omitted):
Act.24.12#12=N(k)O ¦ ἐπίστασιν (epistasin) ¦ obstruction ¦ G20447=N-ASF ¦ ἐπίστασις=stoppage ¦ NA28+NA27+Tyn+SBL+WH+Treg ¦ ἐπισύστασιν (t=episustasin) insurrection - G1999=N-ASF in: TR+Byz ¦  ¦ detención en hacer un alto ¦ stoppage ¦ #12 ¦ G20447 ¦ G1999
Mat.6.13#09=NKO ¦ ἡμᾶς (hēmas) ¦ us ¦ G3165=P-1AP ¦ ἐγώ=I/we ¦ NA28+NA27+Tyn+SBL+WH+Treg+TR+Byz ¦  ¦  ¦ a nosotros ¦ us ¦ #09«08:G4506 ¦ G3165_B ¦ G2248
Gen.1.1#01=L ¦ בְּ/רֵאשִׁ֖ית ¦ be./re.Shit ¦ in/ beginning ¦ H9003/{H7225G} ¦ HR/Ncfsa ¦  ¦  ¦ H7225G ¦  ¦  ¦ H9003=ב=in/{H7225G=רֵאשִׁית=: beginning»first:1_beginning}
Jer.49.30#18=Q(K) ¦ עֲלֵי/כֶ֖ם ¦ 'a.lei./khem ¦ on/ you ¦ {H5921A}/H9036 ¦ HRd/Sp2mp ¦ K= 'a.lei./hem (עֲלֵי/הֶם) "on/ them" (H5921A/H9038=HRd/Sp3mp) ¦ L= עֲלֵי/הֶ֖ם ¦ ; ¦ H5921A_B ¦  ¦  ¦ {H5921A=עַל=upon}/H9036=Op2m=you

5 VERSE LENGTH (31,086 non-empty BSB verses, words split on spaces)
Min 2, Q1 16, median 22, Q3 29, max 75 (2 Chronicles 2:14). 25 words or fewer: 19,613 (63.1%; OT 13,988, NT 5,625). 20 or fewer 14,029; 15 or fewer 7,588; 12 or fewer 3,620; 10 or fewer 1,801; 8 or fewer 852; 5 or fewer 271.

6 REFRAINS (punctuation-delimited units of 6+ words, exact match; first and last occurrence)
76 Then the LORD said to Moses (Exodus 7:14; Deuteronomy 31:14)
72 This is what the LORD says (Exodus 7:17; Zechariah 8:3)
36 This is what the Lord GOD says (Isaiah 49:22; Amos 5:3)
26 I am the LORD your God (Exodus 20:2; Ezekiel 20:19)
25 And the LORD said to Moses (Exodus 7:19; Deuteronomy 31:16)
25 As surely as the LORD lives (Judges 8:19; Hosea 4:15)
23 Therefore this is what the Lord GOD says (Isaiah 65:13; Amos 3:11)
22 This is what the LORD of Hosts says (1 Samuel 15:2; Zechariah 8:23)
21 Then the word of the LORD came to me (Jeremiah 13:8; Zechariah 4:8)
18 Then you will know that I am the LORD (1 Kings 20:28; Ezekiel 37:6)
15 Then they will know that I am the LORD (Ezekiel 6:14; Ezekiel 38:23)
14 a land flowing with milk and honey (Exodus 3:8; Ezekiel 20:15)
14 a pleasing aroma to the LORD (Leviticus 1:9; Numbers 28:24)
14 are they not written in the Book of the Chronicles of the Kings of Judah (1 Kings 14:29; 2 Kings 24:5)
14 For this is what the LORD says (Isaiah 52:3; Ezekiel 30:6)
2,232 such units repeat; 40 occur 10+ times. Whole sentences: 689 repeat, 14 occur 5+ times. The 6-word floor excludes "His loving devotion endures forever" (41 verses). 385 whole verses occur more than once.

7 PHRASES (verses, case-insensitive)
"you shall" 150 (OT 146, NT 4). "do not" 1,108 (OT 733, NT 375). "let us" 199 (OT 147, NT 52). For scale: "you are to" 327, "you must" 325, "you must not" 149, "you shall not" 35.

8 SUFFIXED STRONG'S
TAGNT: 11,227 of 142,095 tokens (7.90%); 270 suffixed tags; 95 base numbers split into 2+ tags in the text. TAHOT: 140,621 of 305,634 root tags (46.01%); 4,286 of 11,423 tags suffixed; 1,356 bases split. Hebrew letters A-F repeat the eStrong homograph split (1,151 tags); G onward are STEP senses and namesakes (3,125). 522 Hebrew bases join tags from two or more different eStrong entries (61,281 tokens).
Examples with token counts: H7307 רוּחַ G spirit 216, H breath 145, I side 7, J temper 10. H5315 נֶפֶשׁ G soul 246, H life 207, I myself 130, J person 96, L appetite 47, K animal 13, M dead 13, N neck 2. H1254 בָּרָא A to create 53, B to fatten 2. H2617 חֶסֶד A kindness 245, B shame 2. G4160 ποιέω G do 566, H make 1, I appoint 7, J spend(TIME) 5. G1492 εἴδω G understand 3, H see 347, I know 31. G2264 Ἡρώδης G 11, H 27, I 6 (three different people per TBESG).
The suffix survives in words.strongs (B:283), but word_index and study codes use the base number (D:529; packages/harness/lib/src/word_study.dart:7-8, :29-33).

SURPRISES BEARING ON WORD-STUDY ACCURACY
a. The reference pattern (B:282) allows only (…) after the verse. 350 TAGNT rows in 48 verses use […] (KJV numbering) or {…} and fail it. No row survives for John 7:53, Romans 16:25-27, 2 Corinthians 13:13-14, Philippians 1:16-17.
b. 58 TAHOT rows repeat a (book, chapter, verse, position) key and lose to INSERT OR IGNORE (B:294): Num 26:1; 1Sa 20:42; 1Ki 18:33, 20:2, 22:22, 22:43; 1Ch 12:4; titles of Psalms 51, 52, 54, 60.
c. Psalm titles are verse 0 in TAHOT (478 rows, 116 psalms); the BSB JSON has the title inside verse 1.
d. 159 TAHOT rows (X and R words) have four-digit positions such as Gen.4.8#0501, parsed as position 501.
e. Three TAGNT tokens carry five-digit numbers (G20447 at Act.24.12 and 2Co.11.28; G20833 at 1Th.2.8). The four-digit pattern (B:283) turns them into G2044 (ἐρεύγομαι "to utter/proclaim") and G2083 (ἑταῖρος "friend"). The lexicon pattern (B:344) skips all 1,485 five-digit TBESG rows.
f. Every word type is loaded (B:321-342 has no filter), so 4,450 rows with no N reading sit beside the N text. The 16 verses with no word in NA27 or NA28 are exactly the 16 empty BSB verse strings.
g. lexicon() given only a base number returns the lowest key under that base (D:844-849; reached that way from lib/word_study_screen.dart:211 via :227, and at :338). Emulating that query on the raw files, the entry returned is not the token's own tagged entry for 41,110 Hebrew tokens (13.45%) and 2,588 Greek tokens (1.82%). Largest cases: H1121G "son: descendant/people" (1,560) gives H1121A "son: child"; H5892B "city" (1,085) gives H5892A "excitement"; H1004B "house: home" (898) gives H1004A "place"; H3651C "so" (734) gives H3651A "right"; G3754H "since" (468) gives G3754G "that"; G1492H "see" (347) gives G1492G "understand"; G2962H "lord: master" (89) gives G2962G "lord: God". When the pressed word's own tag is known, :221 looks up the full tagged number instead.
h. Tagged numbers with no exact lexicon key: 317 Greek tokens (G2453 197, G3708 61) and 383 Hebrew (H0430J "gods" 216, H3064 75).
i. Definitions are cut at 600 characters (B:63, :357): 769 Hebrew entries (6.6%) and 779 Greek (8.2%); the longest are 2,607 and 4,194.
j. Type and Editions can disagree: Mrk.16.9#01 is type KO while its editions column lists NA28 and NA27.
k. Provenance. TAGNT header: the English column is "Based on Berean Study Bible, with permission, as at 1-July02019 and adapted"; sub-meanings come from the Marvel Bible Project. README: TIPNR descriptions and the planned TBCWG concept groups were "created by Claude 3 AI".