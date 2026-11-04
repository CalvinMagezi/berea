// Readable verb tags for STEP/Robinson morphology codes, so a small model need not decode them.

const _greekTense = {
  'P': 'present',
  'I': 'imperfect',
  'F': 'future',
  'A': 'aorist',
  'R': 'perfect',
  'L': 'pluperfect',
};

const _greekVoice = {
  'A': 'active',
  'M': 'middle',
  'P': 'passive',
  'E': 'middle or passive',
  'D': 'middle deponent',
  'N': 'middle deponent',
  'O': 'passive deponent',
  'Q': 'impersonal active',
};

const _greekMood = {
  'I': 'indicative',
  'S': 'subjunctive',
  'O': 'optative',
  'M': 'imperative',
  'N': 'infinitive',
  'P': 'participle',
};

const _hebrewStem = {
  'q': 'qal',
  'N': 'niphal',
  'p': 'piel',
  'P': 'pual',
  'h': 'hiphil',
  'H': 'hophal',
  't': 'hithpael',
  'o': 'polel',
  'O': 'polal',
  'r': 'hithpolel',
  'Q': 'qal passive',
  'v': 'hishtaphel',
};

const _hebrewConjugation = {
  'p': 'perfect',
  'q': 'sequential perfect',
  'i': 'imperfect',
  'w': 'wayyiqtol',
  'h': 'cohortative',
  'j': 'jussive',
  'v': 'imperative',
  'r': 'active participle',
  's': 'passive participle',
  'a': 'infinitive absolute',
  'c': 'infinitive construct',
};

const _greekVerbPrefix = 'V-';
const _hebrewVerbPrefixes = ['HV', 'AV'];
const _hebrewPartSeparator = '/';
const _greekFormLength = 3;

/// A short English tag for a verb's morphology code, or null for anything that is not a verb.
String? verbSense(String morph) {
  if (morph.startsWith(_greekVerbPrefix)) return _greekSense(morph);
  return _hebrewSense(morph);
}

String? _greekSense(String morph) {
  final form = morph.substring(_greekVerbPrefix.length).split('-').first;
  // A leading 2 marks a second-aorist style form and does not change the sense.
  final letters = form.replaceFirst(RegExp(r'^\d'), '');
  if (letters.length != _greekFormLength) return null;
  final tense = _greekTense[letters[0]];
  final voice = _greekVoice[letters[1]];
  final mood = _greekMood[letters[2]];
  if (tense == null || voice == null || mood == null) return null;
  return '$tense $voice $mood';
}

String? _hebrewSense(String morph) {
  for (final part in morph.split(_hebrewPartSeparator)) {
    final code = part.startsWith('H') || part.startsWith('A') ? part : 'H$part';
    final prefix = _hebrewVerbPrefixes.where(code.startsWith);
    if (prefix.isEmpty || code.length < 4) continue;
    final conjugation = _hebrewConjugation[code[3]];
    if (conjugation == null) continue;
    // An Aramaic or rare stem still gives the reader its conjugation.
    final stem = _hebrewStem[code[2]];
    return stem == null ? conjugation : '$stem $conjugation';
  }
  return null;
}
