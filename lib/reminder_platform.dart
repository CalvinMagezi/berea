import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'daily_reminder.dart';

const _channelId = 'daily_prayer';
const _channelName = 'Verse of the day and prayer';
const _channelDescription = 'One notification a day at the time you choose.';
const _androidIcon = 'ic_stat_berea';

/// A platform call that never answers must not hold every later update behind it.
const _updateTimeout = Duration(seconds: 30);

/// Sets up [plugin] without asking for permission: that is asked when the reader turns
/// notifications on, or starts a deep dive, never at launch.
Future<void> initLocalNotifications(FlutterLocalNotificationsPlugin plugin) async {
  const darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings(_androidIcon),
      iOS: darwin,
      macOS: darwin,
    ),
  );
}

/// Notifications on the platforms that have them. Everything is scheduled on this device; the
/// plugin sends nothing anywhere.
class LocalNotificationsPlatform implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;

  /// Whether this build can show scheduled notifications at all.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  var _zoneReady = false;

  /// The time zone is needed to schedule, not to cancel, so a zone the package does not know
  /// cannot stop Turn off.
  Future<void> _initZone() async {
    if (_zoneReady) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    _zoneReady = true;
  }

  Future<void> _init() async {
    if (_ready) return;
    await initLocalNotifications(_plugin);
    _ready = true;
  }

  @override
  Future<bool> allowed() async {
    await _init();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    return (await mac?.checkPermissions())?.isEnabled ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    return await mac?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Updates run one after another, so a sync on resume cannot interleave with Turn off or a new
  /// time and leave some days at the old one.
  Future<void> _queue = Future.value();

  @override
  Future<void> replaceAll(List<ReminderMessage> messages) {
    final run = _queue.then((_) => _replace(messages).timeout(_updateTimeout));
    _queue = run.catchError((Object _) {});
    return run;
  }

  Future<void> _replace(List<ReminderMessage> messages) async {
    await _init();
    await _plugin.cancelAll();
    if (messages.isNotEmpty) await _initZone();
    // Time has passed since the messages were built: a time that is now behind is skipped, since
    // the plugin refuses a date that is not in the future.
    final now = DateTime.now();
    for (final m in messages.where((m) => m.when.isAfter(now))) {
      await _plugin.zonedSchedule(
        id: m.id,
        title: m.title,
        body: m.body,
        scheduledDate: tz.TZDateTime.from(m.when, tz.local),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            styleInformation: BigTextStyleInformation(m.body),
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        // Inexact, so no special alarm permission is asked for: a verse a few minutes late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
