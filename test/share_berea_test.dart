import 'package:berea/share_berea.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feedback is the reader\'s words and the app version and platform, nothing else', () {
    final message = feedbackMessage('  The search found it at once.  ', version: '0.9.0');
    expect(message.split('\n').first, 'The search found it at once.');
    expect(message, contains('(Berea 0.9.0, '));
    expect(message.split('\n').length, 3, reason: 'words, a blank line, the version line');
  });
}
