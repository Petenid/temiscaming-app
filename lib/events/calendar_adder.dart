import 'dart:io' show Platform;

import 'package:add_2_calendar/add_2_calendar.dart' as a2c;
import 'package:flutter/foundation.dart';

/// What to put in the phone's calendar (events spec D6).
class CalendarRequest {
  const CalendarRequest({
    required this.title,
    required this.firstDay,
    required this.lastDay,
    required this.location,
    required this.notes,
  });

  final String title;

  /// All-day: dates only (local midnight), inclusive.
  final DateTime firstDay;
  final DateTime lastDay;
  final String location;
  final String notes;
}

/// What happened after asking.
enum CalendarOutcome {
  /// The calendar's own screen opened (the user saves or cancels there).
  opened,

  /// Android: no app on the phone can take a new event.
  noCalendarApp,
}

/// Opens the phone's own calendar with an event filled in; the user confirms
/// there, so nothing is written without their tap. Tests use a fake.
abstract class CalendarAdder {
  /// False on desktop: the button is hidden there (spec D6).
  bool get isSupported;

  Future<CalendarOutcome> add(CalendarRequest request);
}

/// Start and end times for an all-day event, as each platform expects them.
class AllDayTimes {
  const AllDayTimes(this.start, this.end, this.timeZone);

  final DateTime start;
  final DateTime end;
  final String? timeZone;
}

/// Android's calendar wants all-day events at midnight UTC, ending at the
/// start of the day after (otherwise the event can shift by a day). iOS
/// wants local dates, ending on the last day.
AllDayTimes allDayTimes(DateTime firstDay, DateTime lastDay, {required bool android}) {
  if (android) {
    return AllDayTimes(
      DateTime.utc(firstDay.year, firstDay.month, firstDay.day),
      DateTime.utc(lastDay.year, lastDay.month, lastDay.day + 1),
      'UTC',
    );
  }
  return AllDayTimes(
    DateTime(firstDay.year, firstDay.month, firstDay.day),
    DateTime(lastDay.year, lastDay.month, lastDay.day),
    null,
  );
}

/// The real one: the add_2_calendar package (Android and iOS).
class DeviceCalendarAdder implements CalendarAdder {
  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<CalendarOutcome> add(CalendarRequest request) async {
    final android = Platform.isAndroid;
    final times = allDayTimes(request.firstDay, request.lastDay, android: android);
    try {
      final ok = await a2c.Add2Calendar.addEvent2Cal(a2c.Event(
        title: request.title,
        description: request.notes,
        location: request.location,
        startDate: times.start,
        endDate: times.end,
        timeZone: times.timeZone,
        allDay: true,
      ));
      // On Android, false means no calendar app could open. On iOS it means
      // the user cancelled (or, before iOS 17, refused access): nothing to say.
      return android && !ok ? CalendarOutcome.noCalendarApp : CalendarOutcome.opened;
    } catch (error) {
      debugPrint('Calendar: could not add event: $error');
      return android ? CalendarOutcome.noCalendarApp : CalendarOutcome.opened;
    }
  }
}
