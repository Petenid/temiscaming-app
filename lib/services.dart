import 'alerts/alerts_repository.dart';
import 'push/push_service.dart';

/// The app's connections to the outside world, created once in main.dart.
/// Tests pass fakes instead, so no screen talks to Firebase directly.
class AppServices {
  const AppServices({required this.alerts, required this.push});

  final AlertsRepository alerts;
  final PushService push;
}
