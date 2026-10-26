import 'package:berea/models.dart';
import 'package:berea_harness/berea_harness.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
