import 'package:berea_harness/berea_harness.dart';
import 'package:test/test.dart';

void main() {
  test('Greek verbs read as tense voice mood', () {
    expect(verbSense('V-AAI-3S'), 'aorist active indicative');
    expect(verbSense('V-PAP-NSM'), 'present active participle');
    expect(verbSense('V-RPI-1P'), 'perfect passive indicative');
    expect(verbSense('V-2AAI-3S'), 'aorist active indicative');
    expect(verbSense('V-PAN'), 'present active infinitive');
    expect(verbSense('V-AMM-2S'), 'aorist middle imperative');
  });

  test('Hebrew verbs read as stem and conjugation, also behind prefixes', () {
    expect(verbSense('HVqp3ms'), 'qal perfect');
    expect(verbSense('HVhi'), 'hiphil imperfect');
    expect(verbSense('HVqw3ms'), 'qal wayyiqtol');
    expect(verbSense('HVqrmsc/Sp1bs'), 'qal active participle');
    expect(verbSense('Hc/Vqq1cs'), 'qal sequential perfect');
    expect(verbSense('Hc/Vvw3mp'), 'hishtaphel wayyiqtol');
    // A stem the table lacks still gives the conjugation.
    expect(verbSense('HVuc'), 'infinitive construct');
  });

  test('non-verbs and garbage give null', () {
    for (final m in [
      'N-NSM',
      'CONJ',
      'PRT-N',
      'T-NSM',
      'HNcmsa',
      'HC/Ncfsc',
      'HR/Npm',
      '',
      'zzz',
      'V-',
      'V-QQQ',
      'HVzz',
    ]) {
      expect(verbSense(m), isNull, reason: m);
    }
  });
}
