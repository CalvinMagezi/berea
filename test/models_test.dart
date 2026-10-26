import 'package:berea/app_state.dart';
import 'package:berea/models.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('model recommendation follows device memory', () {
    expect(recommendedModel(null).id, 'gemma-4-e2b');
    expect(recommendedModel(3.8).id, 'gemma-3-1b');
    expect(recommendedModel(6).id, 'gemma-4-e2b');
    expect(recommendedModel(12).id, 'gemma-4-e4b');
  });

  test('a phone under 7 GB runs the mid-tier model at the low tier', () {
    final e2b = recommendedModel(5.5);
    expect(recommendedTier(e2b, 5.5), Tier.low);
    expect(recommendedTier(e2b, 7.0), Tier.mid);
    expect(recommendedTier(e2b, null), Tier.mid);
    expect(recommendedTier(recommendedModel(12), 12), Tier.high);
  });

  test('no model needs an account: a catalog file is hosted by Berea or is ungated on Hugging Face', () {
    final hosted = edgeModels.where((m) => m.source != null);
    expect(hosted.map((m) => m.id), ['gemma-3-1b']);
    for (final m in hosted) {
      final source = m.source!;
      expect(source.url, startsWith('https://github.com/CalvinMagezi/berea/releases/download/'));
      expect(source.url, endsWith(m.file));
      expect(source.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(source.bytes, greaterThan(0));
      expect(m.notice, gemmaNotice);
    }
  });

  test('a token saved by an older build is removed', () async {
    SharedPreferences.setMockInitialValues({'hfToken': 'hf_old', 'tier': 'low'});
    final prefs = await SharedPreferences.getInstance();
    await Settings.dropLegacyToken(prefs);
    expect(prefs.containsKey('hfToken'), isFalse);
    expect(Settings.load(prefs).tier, Tier.low);
  });
}
