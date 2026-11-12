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

const _greekVerbPrefix = 'V-';
const _greekFormLength = 3;

/// A short English tag for a Greek verb's morphology code, or null for anything else. Hebrew and
/// Aramaic codes are read from STEPBible's own table, [BibleDb.hebrewParsing].
String? verbSense(String morph) => morph.startsWith(_greekVerbPrefix) ? _greekSense(morph) : null;

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
