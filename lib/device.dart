import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('berea/device');

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
