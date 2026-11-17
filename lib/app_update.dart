import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pinned_download.dart';

/// Where the newest release is published. Berea asks this one address, sends nothing about the
/// reader, and only on Android, where it can install what it finds.
const latestReleaseUrl = 'https://api.github.com/repos/CalvinMagezi/berea/releases/latest';

/// The file every release carries under this one name.
const updateAssetName = 'berea-android-arm64.apk';

const _updateKeyOn = 'updateCheckOn';
const _updateKeyLast = 'updateCheckedAt';
const _updateKeyDismissed = 'updateDismissed';

/// The shortest wait between two checks made when Berea opens.
const updateCheckEvery = Duration(hours: 24);

/// Past this size a download is refused, so a wrong file can never fill the disk. The app is
/// about 60 MB.
const updateMaxBytes = 200 * 1024 * 1024;

const _checkTimeout = Duration(seconds: 10);
const _downloadTimeout = Duration(seconds: 60);
const _appChannel = MethodChannel('berea/app');

/// A version such as `0.9.1` or `0.9.0-rc1`. A release candidate comes before its release.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  /// The text after the dash, or null for a full release.
  final String? pre;
  const AppVersion(this.major, this.minor, this.patch, [this.pre]);

  /// Reads `1.2.3`, `v1.2.3`, `1.2.3+4` and `1.2.3-rc1`; null for anything else.
  static AppVersion? tryParse(String text) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$').firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4]);
  }

  @override
  int compareTo(AppVersion o) {
    for (final (a, b) in [(major, o.major), (minor, o.minor), (patch, o.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    if (pre == o.pre) return 0;
    if (pre == null) return 1;
    if (o.pre == null) return -1;
    return _comparePre(pre!, o.pre!);
  }

  /// `rc2` before `rc10`: numbers inside the label are compared as numbers.
  static int _comparePre(String a, String b) {
    final pa = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
    final pb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final x = int.tryParse(pa[i]);
      final y = int.tryParse(pb[i]);
      final c = x != null && y != null ? x.compareTo(y) : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, pre);

  @override
  String toString() => '$major.$minor.$patch${pre == null ? '' : '-$pre'}';
}

/// The newest release, as far as Berea needs it.
class ReleaseInfo {
  final AppVersion version;
  final Uri apk;

  /// The SHA-256 GitHub published for the file. Without one the file is not downloaded: what
  /// arrives has to be exactly what was released.
  final String? sha256;
  final int? bytes;
  const ReleaseInfo({required this.version, required this.apk, this.sha256, this.bytes});

  bool get installable => sha256 != null;
}

/// The release in [body], GitHub's answer for `releases/latest`; null when it has no version Berea
/// reads or no Android file.
ReleaseInfo? parseLatestRelease(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  final version = AppVersion.tryParse('${json['tag_name']}');
  if (version == null) return null;
  final assets = json['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map<String, Object?> || a['name'] != updateAssetName) continue;
    final url = Uri.tryParse('${a['browser_download_url']}');
    if (url == null || url.scheme != 'https' || url.host != 'github.com') return null;
    final digest = '${a['digest']}';
    final sha = digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null;
    return ReleaseInfo(
      version: version,
      apk: url,
      sha256: sha != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      bytes: a['size'] is int ? a['size'] as int : null,
    );
  }
  return null;
}

enum UpdateStage { idle, downloading, installing, failed }

/// Looks for a newer Berea, downloads it when asked, and hands it to the system installer. All
/// of it is on Android only; elsewhere nothing is ever requested.
class UpdateService extends ChangeNotifier {
  final SharedPreferences prefs;
  final bool supported;
  final Future<AppVersion?> Function() currentVersion;
  final http.Client Function() newClient;
  final DateTime Function() now;
  final Future<Directory> Function() cacheDir;
  final Future<String?> Function(String path) install;

  UpdateService(
    this.prefs, {
    bool? supported,
    Future<AppVersion?> Function()? currentVersion,
    http.Client Function()? newClient,
    DateTime Function()? now,
    Future<Directory> Function()? cacheDir,
    Future<String?> Function(String path)? install,
  }) : supported = supported ?? (!kIsWeb && Platform.isAndroid),
       currentVersion = currentVersion ?? _installedVersion,
       newClient = newClient ?? http.Client.new,
       now = now ?? DateTime.now,
       cacheDir = cacheDir ?? getTemporaryDirectory,
       install = install ?? _installApk;

  /// Whether Berea looks when it opens. On until the reader turns it off.
  bool get checkOnOpen => prefs.getBool(_updateKeyOn) ?? true;

  Future<void> setCheckOnOpen(bool on) async {
    await prefs.setBool(_updateKeyOn, on);
    if (!on) _available = null;
    notifyListeners();
  }

  ReleaseInfo? _available;

  /// A newer release the reader has not put off, if one was found.
  ReleaseInfo? get available {
    final a = _available;
    if (a == null || prefs.getString(_updateKeyDismissed) == a.version.toString()) return null;
    return a;
  }

  var _stage = UpdateStage.idle;
  UpdateStage get stage => _stage;

  /// Bytes received and the size, while downloading.
  (int, int?) progress = (0, null);

  /// What went wrong, in words the reader can use, while [stage] is failed.
  String? failure;

  void _set(UpdateStage s) {
    _stage = s;
    notifyListeners();
  }

  /// Looks once when Berea opens, if the reader allows it and a day has passed.
  Future<void> checkWhenOpened() async {
    if (!supported || !checkOnOpen) return;
    final last = prefs.getInt(_updateKeyLast);
    if (last != null && now().millisecondsSinceEpoch - last < updateCheckEvery.inMilliseconds) {
      return;
    }
    await check();
  }

  /// Looks now. Returns a sentence saying what was found, for the Settings button.
  Future<String> check() async {
    if (!supported) return 'Updates from inside Berea are for Android.';
    final client = newClient();
    try {
      final r = await client
          .get(Uri.parse(latestReleaseUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(_checkTimeout);
      if (r.statusCode != 200) return 'Berea could not reach the release page just now.';
      await prefs.setInt(_updateKeyLast, now().millisecondsSinceEpoch);
      final release = parseLatestRelease(r.body);
      final mine = await currentVersion();
      if (release == null || mine == null) return 'Berea could not read the release page.';
      if (release.version.compareTo(mine) <= 0) {
        _available = null;
        notifyListeners();
        return 'Berea $mine is the newest version.';
      }
      _available = release;
      notifyListeners();
      return release.installable
          ? 'Berea ${release.version} is ready to download.'
          : 'Berea ${release.version} is out, but this release has no checksum, so it is not installed from here.';
    } on Object catch (e) {
      debugPrint('The update check failed: $e');
      return 'Berea could not reach the release page just now.';
    } finally {
      client.close();
    }
  }

  /// Puts the bar away until a newer release than this one comes out.
  Future<void> later() async {
    final a = _available;
    if (a != null) await prefs.setString(_updateKeyDismissed, a.version.toString());
    notifyListeners();
  }

  /// Downloads the update and opens the system installer. The system asks the reader to confirm
  /// and only installs a file signed with the same key as the app it replaces.
  Future<void> update() async {
    final release = _available;
    if (release == null || !release.installable || _stage == UpdateStage.downloading) return;
    failure = null;
    progress = (0, release.bytes);
    _set(UpdateStage.downloading);
    try {
      final dir = Directory('${(await cacheDir()).path}/updates');
      await dir.create(recursive: true);
      for (final old in dir.listSync()) {
        if (old is File) old.deleteSync();
      }
      final file = File('${dir.path}/Berea-${release.version}.apk');
      await downloadPinned(
        release.apk,
        file,
        sha256: release.sha256!,
        maxBytes: updateMaxBytes,
        timeout: _downloadTimeout,
        onProgress: (received, total) {
          progress = (received, total ?? release.bytes);
          notifyListeners();
        },
      );
      _set(UpdateStage.installing);
      final outcome = await install(file.path);
      if (outcome == 'needsPermission') {
        failure =
            'Allow Berea to install apps in the screen that opened, then tap Update again.';
        _set(UpdateStage.failed);
        return;
      }
      _set(UpdateStage.idle);
    } on Object catch (e) {
      debugPrint('The update failed: $e');
      failure = e is FormatException
          ? 'The download did not match the published file, so it was not installed.'
          : 'The download did not finish. Check your connection and try again.';
      _set(UpdateStage.failed);
    }
  }
}

Future<AppVersion?> _installedVersion() async =>
    AppVersion.tryParse((await PackageInfo.fromPlatform()).version);

/// Hands [path] to Android's installer. Returns `needsPermission` when the reader first has to
/// allow Berea to install apps, which opens the screen for it.
Future<String?> _installApk(String path) =>
    _appChannel.invokeMethod<String>('installApk', {'path': path});
