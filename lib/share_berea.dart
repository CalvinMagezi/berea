import 'dart:io';

import 'package:berea_harness/berea_harness.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';

const _appChannel = MethodChannel('berea/app');
const _apkMime = 'application/vnd.android.package-archive';

/// A file Berea can hand to the share sheet, with the words that name it.
typedef Shareable = ({String label, String path});

/// The installed packs, which a reader can pass on with the app so a friend needs no download.
List<Shareable> sharePacks(AppState s) => [
  if (s.db.hasFullLexicon) (label: 'Full Greek lexicon', path: s.lexiconPackPath),
  if (s.db.hasMiddleLiddell) (label: 'Middle Liddell definitions', path: s.middleLiddellPackPath),
  if (s.db.hasTopics) (label: 'Topics', path: s.topicsPackPath),
  for (final p in s.commentary.installedFiles()) (label: _packTitle(p.$1), path: p.$2),
];

String _packTitle(String id) {
  final spec = commentaryPackSpecs.where((s) => s.id == id).firstOrNull;
  return spec == null ? id : spec.title;
}

/// The message a reader sends about Berea: their own words, then the app's version and platform,
/// and nothing else. Berea sends nothing itself; this text goes to the share sheet only after the
/// reader has read it.
String feedbackMessage(String words, {required String version}) =>
    '${words.trim()}\n\n(Berea $version, ${Platform.operatingSystem})';

/// Offers [message] to the share sheet so the reader picks where it goes.
Future<void> sendFeedback(String message) =>
    SharePlus.instance.share(ShareParams(text: message, subject: 'Berea feedback'));

/// Whether this device can hand its own app to another: Android installs from a file.
bool get canShareApp => Platform.isAndroid;

/// Offers the installed app as a file to the system share sheet. Returns false when the device
/// will not say where the app is.
Future<bool> shareApp() async {
  final source = await _appChannel.invokeMethod<String>('apkPath');
  if (source == null) return false;
  final cache = await getTemporaryDirectory();
  final copy = await File(source).copy('${cache.path}/Berea.apk');
  await SharePlus.instance.share(ShareParams(files: [XFile(copy.path, mimeType: _apkMime)]));
  return true;
}

/// Offers one downloaded pack to the share sheet.
Future<void> sharePack(Shareable pack) =>
    SharePlus.instance.share(ShareParams(files: [XFile(pack.path)]));
