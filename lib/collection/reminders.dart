import 'dart:async';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings/sector.dart';
import 'bin_icon.dart';
import 'collection_repository.dart';
import 'pickup.dart';
import 'schedule.dart';

/// Evening-before bin reminders (DESIGN §4 "Reminders vs. changes", spec D7).
///
/// They're scheduled on the phone itself, from the schedule copy saved on
/// the phone, so they still arrive when our backend, the Town's site or the
/// network is down.

/// One reminder to show at [at] (Témiscaming time).
class Reminder {
  const Reminder({required this.id, required this.at, required this.title, required this.body});

  /// Unique per pickup day: 20261019 for the reminder before 20 October.
  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => '$id@$at $title / $body';
}

/// How far ahead reminders are scheduled (well under iOS's limit of 64).
const reminderWeeks = 8;

/// The reminders for [sector]'s next pickups: the evening before each day
/// with bins to put out, at [minutes] after midnight, in [strings]' language.
/// Cancelled pickups and special collections get none (spec D9); reminders
/// whose time has passed are left out.
List<Reminder> buildReminders({
  required List<Pickup> pickups,
  required Sector sector,
  required DateTime now,
  required int minutes,
  required AppLocalizations strings,
}) {
  final today = dateOnly(now);
  final days = pickupDays(
    pickups,
    sector,
    from: today,
    until: addDays(today, reminderWeeks * 7 + 1),
  ).where((d) => d.hasBins);
  return [
    for (final day in days)
      if (_eveningBefore(day.date, minutes).isAfter(now))
        Reminder(
          id: day.date.year * 10000 + day.date.month * 100 + day.date.day,
          at: _eveningBefore(day.date, minutes),
          title: strings.reminderTitle(binsInSentence(strings, day.bins)),
          body: day.bins.length > 1 ? strings.reminderBodyMany : strings.reminderBodyOne,
        ),
  ];
}

DateTime _eveningBefore(DateTime day, int minutes) {
  final eve = addDays(day, -1);
  return DateTime(eve.year, eve.month, eve.day, minutes ~/ 60, minutes % 60);
}

/// Shows reminders. The real one uses the phone's notification system;
/// tests use a fake.
abstract class ReminderService {
  /// Phones only, like push (spec D7).
  bool get isSupported;

  /// Replaces every scheduled reminder with [reminders]. Notifications
  /// already on screen (a boil-water notice, say) are left alone.
  Future<void> replaceAll(List<Reminder> reminders, AppLocalizations strings);

  /// For the owner's check (spec §8 step 5): one reminder at [reminder.at].
  Future<void> scheduleTest(Reminder reminder, AppLocalizations strings);

  /// Fires when the user taps a reminder while the app is running.
  Stream<void> get tapped;

  /// True if a reminder launched the app.
  Future<bool> launchedByReminder();
}

/// Keeps the scheduled reminders in step with the settings and the schedule:
/// at start, and whenever either changes.
class ReminderSync {
  ReminderSync(this._settings, this._collection, this._service, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _settings.addListener(_sync);
    _collection.addListener(_sync);
    _sync();
  }

  final AppSettings _settings;
  final CollectionRepository _collection;
  final ReminderService _service;
  final DateTime Function() _now;
  String? _applied;
  Future<void> _queue = Future.value();

  void _sync() {
    final language = _settings.language;
    final sector = _settings.sector;
    if (!_service.isSupported || language == null || sector == null) return;
    if (!_settings.notificationsAsked) return;
    final strings = lookupAppLocalizations(language.locale);
    final reminders = _settings.binReminderEnabled
        ? buildReminders(
            pickups: _collection.pickups,
            sector: sector,
            now: _now(),
            minutes: _settings.reminderMinutes,
            strings: strings,
          )
        : const <Reminder>[];
    final key = reminders.join(';');
    if (key == _applied) return;
    _applied = key;
    // One replacement at a time, in order.
    _queue = _queue.then((_) => _service.replaceAll(reminders, strings)).catchError((Object _) {});
  }
}
