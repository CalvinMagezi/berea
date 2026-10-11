class Book {
  final int id;
  final String name;

  /// Three letter code used by STEPBible and OpenBible data files.
  final String step;
  final List<String> aliases;
  const Book(this.id, this.name, this.step, this.aliases);
}

final _roman = RegExp(r'^(iii|ii|i)\s+', caseSensitive: false);
const _romanValue = {'i': '1', 'ii': '2', 'iii': '3'};

String normalizeBookKey(String s) => s
    .trim()
    .replaceFirstMapped(_roman, (m) => _romanValue[m[1]!.toLowerCase()]!)
    .toLowerCase()
    .replaceAll(RegExp(r'[\s.]'), '');

const books = <Book>[
  Book(1, 'Genesis', 'Gen', ['ge']),
  Book(2, 'Exodus', 'Exo', ['exod', 'ex']),
  Book(3, 'Leviticus', 'Lev', ['le']),
  Book(4, 'Numbers', 'Num', ['nu', 'nm']),
  Book(5, 'Deuteronomy', 'Deu', ['deut', 'dt']),
  Book(6, 'Joshua', 'Jos', ['josh']),
  Book(7, 'Judges', 'Jdg', ['judg', 'jdgs']),
  Book(8, 'Ruth', 'Rut', ['ru']),
  Book(9, '1 Samuel', '1Sa', ['1sam', '1sm']),
  Book(10, '2 Samuel', '2Sa', ['2sam', '2sm']),
  Book(11, '1 Kings', '1Ki', ['1kgs', '1kg']),
  Book(12, '2 Kings', '2Ki', ['2kgs', '2kg']),
  Book(13, '1 Chronicles', '1Ch', ['1chr', '1chron']),
  Book(14, '2 Chronicles', '2Ch', ['2chr', '2chron']),
  Book(15, 'Ezra', 'Ezr', []),
  Book(16, 'Nehemiah', 'Neh', ['ne']),
  Book(17, 'Esther', 'Est', ['esth']),
  Book(18, 'Job', 'Job', ['jb']),
  Book(19, 'Psalms', 'Psa', ['ps', 'psalm', 'pss', 'psm']),
  Book(20, 'Proverbs', 'Pro', ['prov', 'prv', 'pr', 'proverb']),
  Book(21, 'Ecclesiastes', 'Ecc', ['eccl', 'ec', 'qoh']),
  Book(22, 'Song of Solomon', 'Sng', ['song', 'sos', 'songofsongs', 'canticles']),
  Book(23, 'Isaiah', 'Isa', []),
  Book(24, 'Jeremiah', 'Jer', ['je']),
  Book(25, 'Lamentations', 'Lam', ['la', 'lamentation']),
  Book(26, 'Ezekiel', 'Ezk', ['ezek', 'eze']),
  Book(27, 'Daniel', 'Dan', ['da', 'dn']),
  Book(28, 'Hosea', 'Hos', ['ho']),
  Book(29, 'Joel', 'Jol', ['jl']),
  Book(30, 'Amos', 'Amo', []),
  Book(31, 'Obadiah', 'Oba', ['obad', 'ob']),
  Book(32, 'Jonah', 'Jon', ['jnh']),
  Book(33, 'Micah', 'Mic', ['mi']),
  Book(34, 'Nahum', 'Nam', ['nah', 'na']),
  Book(35, 'Habakkuk', 'Hab', []),
  Book(36, 'Zephaniah', 'Zep', ['zeph']),
  Book(37, 'Haggai', 'Hag', ['hg']),
  Book(38, 'Zechariah', 'Zec', ['zech', 'zch']),
  Book(39, 'Malachi', 'Mal', ['ml']),
  Book(40, 'Matthew', 'Mat', ['matt', 'mt']),
  Book(41, 'Mark', 'Mrk', ['mk', 'mr']),
  Book(42, 'Luke', 'Luk', ['lk']),
  Book(43, 'John', 'Jhn', ['jn', 'joh']),
  Book(44, 'Acts', 'Act', ['ac', 'actsoftheapostles']),
  Book(45, 'Romans', 'Rom', ['ro', 'rm']),
  Book(46, '1 Corinthians', '1Co', ['1cor']),
  Book(47, '2 Corinthians', '2Co', ['2cor']),
  Book(48, 'Galatians', 'Gal', ['ga']),
  Book(49, 'Ephesians', 'Eph', []),
  Book(50, 'Philippians', 'Php', ['phil', 'philip']),
  Book(51, 'Colossians', 'Col', []),
  Book(52, '1 Thessalonians', '1Th', ['1thess', '1thes']),
  Book(53, '2 Thessalonians', '2Th', ['2thess', '2thes']),
  Book(54, '1 Timothy', '1Ti', ['1tim']),
  Book(55, '2 Timothy', '2Ti', ['2tim']),
  Book(56, 'Titus', 'Tit', []),
  Book(57, 'Philemon', 'Phm', ['philem', 'phlm']),
  Book(58, 'Hebrews', 'Heb', []),
  Book(59, 'James', 'Jas', ['jam', 'jm']),
  Book(60, '1 Peter', '1Pe', ['1pet', '1pt']),
  Book(61, '2 Peter', '2Pe', ['2pet', '2pt']),
  Book(62, '1 John', '1Jn', ['1jo', '1joh']),
  Book(63, '2 John', '2Jn', ['2jo', '2joh']),
  Book(64, '3 John', '3Jn', ['3jo', '3joh']),
  Book(65, 'Jude', 'Jud', []),
  Book(66, 'Revelation', 'Rev', ['re', 'revelations', 'revelationofjohn', 'apocalypse']),
];

final Map<String, Book> _byAlias = {
  for (final b in books) ...{
    normalizeBookKey(b.name): b,
    normalizeBookKey(b.step): b,
    for (final a in b.aliases) a: b,
  },
};

Book? bookFor(String raw) => _byAlias[normalizeBookKey(raw)];

Book bookById(int id) => books[id - 1];
