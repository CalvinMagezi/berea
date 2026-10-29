import 'package:berea_harness/berea_harness.dart';

import 'prayer_today.dart';

/// Notifications are scheduled this many days ahead, each with its own day's verse and prayer,
/// and scheduled again whenever Berea opens. Far below the 64 iOS keeps and the 500 Samsung allows.
const reminderDaysAhead = 14;

/// Times offered in the choose-a-time sheet, in minutes after midnight.
const reminderTimes = [6 * 60, 6 * 60 + 30, 7 * 60, 8 * 60];

const defaultReminderMinutes = 6 * 60 + 30;

const _minutesPerHour = 60;

/// "6:30" for 390.
String reminderTimeLabel(int minutes) =>
    '${minutes ~/ _minutesPerHour}:${(minutes % _minutesPerHour).toString().padLeft(2, '0')}';

/// What the reader chose. Off until they turn it on.
class ReminderSettings {
  final bool on;
  final int minutes;

  /// Only the reference on the lock screen, for anyone who would rather keep the words private.
  final bool referenceOnly;
  const ReminderSettings({
    this.on = false,
    this.minutes = defaultReminderMinutes,
    this.referenceOnly = false,
  });

  ReminderSettings copyWith({bool? on, int? minutes, bool? referenceOnly}) => ReminderSettings(
    on: on ?? this.on,
    minutes: minutes ?? this.minutes,
    referenceOnly: referenceOnly ?? this.referenceOnly,
  );
}

/// One notification to be shown at [when], local time.
class ReminderMessage {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  const ReminderMessage(this.id, this.when, this.title, this.body);
}

/// What a platform must do for reminders. The real one wraps the notification plugin.
abstract class ReminderPlatform {
  /// Whether notifications are allowed now, without asking.
  Future<bool> allowed();

  /// Asks the person to allow notifications. True when they are.
  Future<bool> requestPermission();

  /// Drops every scheduled notification and schedules [messages].
  Future<void> replaceAll(List<ReminderMessage> messages);
}

/// The notifications for the next [days] days from [now]. Each shows that day's verse and
/// today's prayer, never the reader's own prayers. A time already past today starts tomorrow.
List<ReminderMessage> buildReminders({
  required DateTime now,
  required ReminderSettings settings,
  required Ref Function(DateTime day) verseOn,
  required String Function(Ref verse) textOf,
  required TodayPrayer? Function(DateTime day) prayerOn,
  int days = reminderDaysAhead,
  DateTime Function(int year, int month, int day, int hour, int minute) clockTime = _local,
}) {
  if (!settings.on) return const [];
  final out = <ReminderMessage>[];
  for (var i = 0; out.length < days; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    // Clock time, so a daylight saving change does not move it an hour.
    final at = clockTime(
      day.year,
      day.month,
      day.day,
      settings.minutes ~/ 60,
      settings.minutes % 60,
    );
    if (!at.isAfter(now)) continue;
    final verse = verseOn(day);
    final prayer = prayerOn(day);
    final words = textOf(verse);
    out.add(
      ReminderMessage(
        reminderId(day),
        at,
        settings.referenceOnly ? 'Verse of the day' : verse.label,
        settings.referenceOnly
            ? verse.label
            : [
                if (words.isNotEmpty) words,
                if (prayer != null) 'Pray: ${prayer.point.text}',
              ].join('\n'),
      ),
    );
  }
  return out;
}

/// A number for [day] that is the same each time it is scheduled, so a new schedule replaces the
/// old one rather than adding to it.
int reminderId(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

DateTime _local(int year, int month, int day, int hour, int minute) =>
    DateTime(year, month, day, hour, minute);
