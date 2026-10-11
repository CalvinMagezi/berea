import 'package:berea/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model recommendation follows device memory', () {
    expect(recommendedModel(null).id, 'gemma-4-e2b');
    expect(recommendedModel(3.8).id, 'gemma-3-1b');
    expect(recommendedModel(6).id, 'gemma-4-e2b');
    expect(recommendedModel(12).id, 'gemma-4-e4b');
  });
}
