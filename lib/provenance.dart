/// Who wrote the text of a note, a study page or a note source. Stored by name. A migration that
/// has shipped is never edited, so these five names and their meanings are fixed.
const provenancePerson = 'person';
const provenanceSource = 'source';
const provenanceRewrite = 'berea_rewrite';
const provenanceMachine = 'machine';
const provenanceUnknown = 'unknown';

const provenanceValues = {
  provenancePerson,
  provenanceSource,
  provenanceRewrite,
  provenanceMachine,
  provenanceUnknown,
};

/// What the reader is told about text a person did not write. Null for a person's own words and
/// for a named source, which shows its author and licence beside it.
String? provenanceLabel(String provenance) => switch (provenance) {
  provenanceMachine =>
    'Written by a language model in an earlier version of Berea. It is not Scripture and not a '
        'named source.',
  provenanceRewrite => 'Shortened by an earlier version of Berea from a lexicon entry. Not the entry as written.',
  provenanceUnknown => 'Written before this version. Parts may have been drafted by a language model.',
  _ => null,
};

/// A kept commentary is titled "WORK on REFERENCE" and ends with a line "AUTHOR · LICENCE".
bool looksLikeKeptCommentary(String title, String text) {
  if (!title.contains(' on ')) return false;
  final lines = text.trimRight().split('\n');
  return lines.isNotEmpty && lines.last.contains(' · ');
}

/// How a note being written is labelled: the one rule the migration's backfill and every new note
/// share. A kept word holds Berea's shortened form of a lexicon entry; a kept commentary is a
/// named source's words; the rest is the person's.
String provenanceFor({
  required String kind,
  required String title,
  required String text,
}) {
  if (kind == 'word' || kind == 'studyword') return provenanceRewrite;
  if (looksLikeKeptCommentary(title, text)) return provenanceSource;
  return provenancePerson;
}
