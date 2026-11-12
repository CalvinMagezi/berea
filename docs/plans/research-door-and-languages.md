# Research for decisions 4 and 7 (2026-11-12)

Read at source on 2026-11-12. Nothing here is built. Each finding names where it was read and what
could not be confirmed.

## Decision 4: a door from a life need to verses

**Nave's Topical Bible.** The CrossWire SWORD module `nave` is TEI, version 3.0, English, with
`DistributionLicense=Public Domain` in its own conf file
(crosswire.org/ftpmirror/pub/sword/raw/mods.d/nave.conf). The 1903 print edition is listed as "No
Copyright - United States" by Princeton Theological Seminary (commons.ptsem.edu). The CrossWire
library page repeats "Public Domain -- Copy Freely". The electronic text was cleaned after scanning
and is said to be over 99% clean; a project at navestopicalbible.org warns that some newer
versions were heavily edited and are not public domain, so the file must come from the CrossWire
module, not from a commercial copy. Author: Orville J. Nave, 1903.

**Torrey's New Topical Textbook.** The SWORD module `torrey` is ThML, version 1.3, English,
`DistributionLicense=Public Domain` (crosswire.org/ftpmirror/pub/sword/raw/mods.d/torrey.conf). The
book is R. A. Torrey, Fleming H. Revell, 1897. A commercial SwordSearcher edition exists and is
not the module to use.

**What this settles.** Both are named, public domain works a script can turn into a topic to
references list under their authors' names, which is what decision 4's first option asks for.
Not settled: the plan's requirement that every author be dead more than 70 years is met by the
dates (1903 and 1897 publications) but each author's death date was not read; and the module
text's own cleanliness needs the build to report entries it cannot parse. Nave's topic list is
about 20,000 topics, Torrey's far fewer.

**Recommendation.** Build the door from Nave and Torrey, shown as "Nave's Topical Bible (1903)"
and "Torrey's New Topical Textbook (1897)", each topic a list of references that open in the
reader, with no Berea-written words. It is the answer to "no topic is removed before a door
ships". It does not need decision 3's editor, so Release F's removals can proceed once it exists.

## Decision 7: a Luganda or Swahili Bible

**Luganda.** One openly licensed text was found: Biblica's *Bayibuli Entukuvu* (Luganda
Contemporary Bible, copyright 1984, 1986, 1993, 2014 Biblica, Inc.) on ebible.org, with USFM
available, under Creative Commons Attribution-ShareAlike 4.0 (ebible.org/lug/copyright.htm). The
licence lets Berea copy and redistribute it unmodified if the Biblica trademark is kept, and
requires any derivative to be shared under the same licence. The Luganda Bible 2003 is free in
other apps, but no licence terms for it were found. Nothing was found on a Bible Society of Uganda
copyright.

**Swahili.** ebible.org carries Biblica's *Toleo Wazi Neno* (copyright 2018, 2024 Biblica, Inc.,
CC BY-SA 4.0, USFM available), the Unlocked Literal Bible (CC BY-SA 4.0), and Krapf's 1850 text
(public domain, but only parts of the New Testament, in the Kimvita dialect). The Swahili Union
Version was not found with a licence.

**What this settles.** Both languages can be offered from ebible.org USFM, which Berea already
imports, if the share-alike condition is kept: the text lives in its own file beside the app,
never merged into the bundled database, as with the Middle Liddell pack, with Biblica's credit,
the licence name and the "changes" line. Berea would add book names to the reference parser and
search on the text. Not settled: how complete each translation is (Old and New Testament), which
needs the USFM downloaded and counted; the Bible Society of Uganda's position on the Luganda 2003
text; whether Biblica's trademark condition allows an in-app title.

**Recommendation.** Offer Biblica's two texts as optional downloads ("Luganda: Bayibuli
Entukuvu", "Swahili: Toleo Wazi Neno") as soon as a reader who uses them can be asked whether the
modern wording is what their church reads. Release L starts with downloading the two USFM sets,
counting books and verses, and testing the importer.

## Measured 2026-11-12: Luganda and Swahili against the BSB's verse numbering

`packages/harness/bin/language_check.dart` reads a USFM zip with Berea's own importer and compares
its chapter and verse numbers to the BSB's 31,102 verses. Run on the ebible.org files:

| | Luganda (Bayibuli Entukuvu) | Swahili (Toleo Wazi Neno) |
|---|---|---|
| Verses read | 31,104 | 31,103 |
| Books | 66 of 66 | 66 of 66 |
| Empty verses | 0 | 0 |
| BSB verse numbers with no text | 0 | 0 |
| Verse numbers the BSB lacks | 2 (Revelation 12:18, 3 John 1:15) | 1 (3 John 1:15) |

Both are complete Bibles and carry text for the sixteen verses the BSB leaves empty. The three extra
numbers are versification differences (Revelation 12:18 is 13:1 in some numberings; 3 John 1:15 is
1:14 in others), so a reference from one Bible reaches the same place in the other for all but those.

Imported into a copy of the built database: 31,104 and 31,103 rows in about 0.3 s each; a search for
Katonda finds 5,094 verses, okwagala 301, Mungu 8,827, upendo 258, each in 2 to 28 ms. The search
index stems with an English stemmer, which treats other languages' words as it finds them and
matches them to themselves, but may join unrelated words that share an English-looking stem.

**Not working yet, by design:** Berea's reference parser does not know the book names. "Yokaana
3:16" and "Mwanzo 1:1" parse to nothing. The USFM headers carry each book's name (`\h Yokaana`,
`\toc2 3 Yokaana`, `\toc3 3Yk`), so the importer can read them and register them as aliases for any
imported translation; that is the next step if a reader wants these languages, and it is small. The
interface stays English; see the answer in the conversation of 2026-11-12 on what translating it
would take.
