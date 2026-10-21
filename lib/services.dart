import 'alerts/alerts_repository.dart';
import 'collection/collection_repository.dart';
import 'collection/reminders.dart';
import 'events/calendar_adder.dart';
import 'events/events_repository.dart';
import 'push/push_service.dart';
import 'weather/weather_repository.dart';

/// The app's connections to the outside world, created once in main.dart.
/// Tests pass fakes instead, so no screen talks to Firebase directly.
class AppServices {
  const AppServices({
    required this.alerts,
    required this.collection,
    required this.push,
    required this.reminders,
    required this.events,
    required this.calendar,
    required this.weather,
  });

  final AlertsRepository alerts;
  final CollectionRepository collection;
  final ReminderService reminders;
  final PushService push;
  final EventsRepository events;

  /// "Add to my calendar" (events spec D6).
  final CalendarAdder calendar;

  /// Weather for Témiscaming (Milestone 4).
  final WeatherRepository weather;
}
