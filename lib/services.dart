import 'alerts/alerts_repository.dart';
import 'collection/collection_repository.dart';
import 'collection/reminders.dart';
import 'push/push_service.dart';

/// The app's connections to the outside world, created once in main.dart.
/// Tests pass fakes instead, so no screen talks to Firebase directly.
class AppServices {
  const AppServices({
    required this.alerts,
    required this.collection,
    required this.push,
    required this.reminders,
  });

  final AlertsRepository alerts;
  final CollectionRepository collection;
  final ReminderService reminders;
  final PushService push;
}
