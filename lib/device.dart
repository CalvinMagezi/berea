import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('berea/device');
const bytesPerGb = 1024 * 1024 * 1024;

/// Total device RAM in bytes, or null where the platform does not report it.
Future<int?> totalMemoryBytes() async {
  if (Platform.isLinux) return _linuxMemory();
  try {
    return await _channel.invokeMethod<int>('totalMemory');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

int? _linuxMemory() {
  final line = File(
    '/proc/meminfo',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('MemTotal:'), orElse: () => '');
  final kb = int.tryParse(RegExp(r'\d+').firstMatch(line)?[0] ?? '');
  return kb == null ? null : kb * 1024;
}

/// Keeps [dir] out of iCloud backups on iOS. Android opts out in its manifest; desktops back up
/// only where their owner chooses.
Future<void> excludeFromBackup(Directory dir) async {
  if (!Platform.isIOS) return;
  try {
    await _channel.invokeMethod<bool>('excludeFromBackup', dir.path);
  } on PlatformException {
    return;
  }
}
