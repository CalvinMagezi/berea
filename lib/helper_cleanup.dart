import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// The folders the helper, its voice and its recordings kept under the app's support folder, by
/// name. Nothing else is deleted.
const helperFolders = ['models', 'listen'];

/// Preferences only the helper read.
const helperPreferenceKeys = [
  'helperWifiOnly',
  'helperDownload',
  'termsAccepted',
];

const _bytesPerGb = 1024 * 1024 * 1024;

/// Deletes what the removed helper left on this device and returns the bytes freed. Safe to run on
/// every launch: with nothing left it does nothing and returns 0.
Future<int> removeHelperFiles(
  Directory supportDir,
  SharedPreferences prefs,
) async {
  var freed = 0;
  for (final name in helperFolders) {
    final dir = Directory('${supportDir.path}/$name');
    if (!dir.existsSync()) continue;
    freed += _size(dir);
    await dir.delete(recursive: true);
  }
  for (final key in helperPreferenceKeys) {
    await prefs.remove(key);
  }
  return freed;
}

int _size(Directory dir) {
  var total = 0;
  for (final f in dir.listSync(recursive: true, followLinks: false)) {
    if (f is File) total += f.lengthSync();
  }
  return total;
}

/// What the reader is told once after an update that removed the helper; null when there was
/// nothing to tell.
String? upgradeNoticeText({
  required int freedBytes,
  required int chatsDeleted,
}) {
  final parts = [
    if (freedBytes > 0)
      'The helper was removed. ${(freedBytes / _bytesPerGb).toStringAsFixed(1)} GB freed.',
    if (chatsDeleted > 0) 'Saved questions and answers were deleted. Notes you kept from them are still in Notes.',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}
