import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_localizations.dart';
import 'reminders.dart';

/// Reminders through the phone's own notification system
/// (flutter_local_notifications).
class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _tapped = StreamController<void>.broadcast();
  Future<void>? _ready;
  late tz.Location _town;

  /// Payload marking our reminders, so a tap opens the pickup schedule.
  static const _payload = 'collection';

  /// Android channel shared with the backend's change notices (spec D10).
  static const _channelId = 'collection';

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    // Pickups and reminder times are in Témiscaming's time zone.
    _town = tz.getLocation('America/Toronto');
    // Permission is asked once, by the notifications step (push); don't ask again here.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == _payload) _tapped.add(null);
      },
    );
  }();

  NotificationDetails _details(AppLocalizations strings) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      strings.channelCollectionName,
      channelDescription: strings.channelCollectionDescription,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  Future<void> _schedule(Reminder r, AppLocalizations strings) async {
    final at = tz.TZDateTime(_town, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute);
    if (!at.isAfter(tz.TZDateTime.now(_town))) return;
    await _plugin.zonedSchedule(
      id: r.id,
      scheduledDate: at,
      notificationDetails: _details(strings),
      // Inexact: may arrive a few minutes late, but needs no "alarms &
      // reminders" permission, which Google Play restricts (spec D7).
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: r.title,
      body: r.body,
      payload: _payload,
    );
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders, AppLocalizations strings) async {
    if (!isSupported) return;
    try {
      await _init();
      // Only scheduled ones: cancelAll() would also clear notifications
      // already on screen, such as an unread boil-water notice.
      await _plugin.cancelAllPendingNotifications();
      for (final r in reminders) {
        await _schedule(r, strings);
      }
    } catch (error) {
      debugPrint('Reminders: could not schedule: $error');
    }
  }

  @override
  Future<void> scheduleTest(Reminder reminder, AppLocalizations strings) async {
    if (!isSupported) return;
    await _init();
    await _schedule(reminder, strings);
  }

  @override
  Stream<void> get tapped => _tapped.stream;

  @override
  Future<bool> launchedByReminder() async {
    if (!isSupported) return false;
    await _init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true &&
        details?.notificationResponse?.payload == _payload;
  }
}
