import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings/sector.dart';

/// Push notifications for water advisories (Milestone 1, spec §3 D5) and
/// pickup changes (Milestone 2, spec D6).
///
/// Each phone subscribes to one FCM "topic" matching its language
/// (`water-fr` or `water-en`), and one matching its sector and language
/// (`collection-town-fr` …). The backend sends one message per topic, so
/// every phone gets exactly one notification, in its own language, and we
/// never need to store anyone's device token.
abstract class PushService {
  /// Push works on iPhone and Android only; desktop shows alerts in-app (DESIGN §4).
  bool get isSupported;

  /// Shows the system "allow notifications?" prompt. True if allowed.
  Future<bool> requestPermission();

  /// Subscribes to the right topics (or none) and, on Android, (re)creates
  /// the notification channels with names in the user's language.
  /// [enabled] is for water advisories; [collectionChanges] for pickup
  /// changes in [sector].
  Future<void> apply({
    required AppLanguage language,
    required bool enabled,
    Sector? sector,
    bool collectionChanges = false,
  });

  /// What the user tapped while the app was running: an alert id, or
  /// [collectionTarget] for a pickup notice.
  Stream<String> get openedAlertIds;

  /// The same for the notification that launched the app, if any.
  Future<String?> initialAlertId();
}

String topicFor(AppLanguage language) => 'water-${language.name}';

/// Pickup-change topic for a sector and language; matches the backend's
/// `topicFor` in functions/src/collection/sync.ts.
String collectionTopicFor(Sector sector, AppLanguage language) =>
    'collection-${sector.name}-${language.name}';

/// Stands for "open the pickup schedule" where an alert id would go.
const collectionTarget = 'collection';

/// Where a tapped push leads: its alert, or the schedule for pickup notices.
String? targetOf(Map<String, dynamic> data) =>
    data['alert_id'] as String? ?? (data['type'] == 'collection' ? collectionTarget : null);

class FcmPushService implements PushService {
  // Talks to MainActivity.kt to create Android notification channels.
  static const _channels = MethodChannel('ca.temiscaming.community/notifications');

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      final settings = await _messaging.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error) {
      debugPrint('Push: permission request failed: $error');
      return false;
    }
  }

  @override
  Future<void> apply({
    required AppLanguage language,
    required bool enabled,
    Sector? sector,
    bool collectionChanges = false,
  }) async {
    if (!isSupported) return;
    final strings = lookupAppLocalizations(language.locale);
    try {
      if (Platform.isAndroid) {
        await _channels.invokeMethod<void>('createChannels', {
          'urgentName': strings.channelUrgentName,
          'urgentDescription': strings.channelUrgentDescription,
          'updatesName': strings.channelUpdatesName,
          'updatesDescription': strings.channelUpdatesDescription,
          'collectionName': strings.channelCollectionName,
          'collectionDescription': strings.channelCollectionDescription,
        });
      }
      for (final each in AppLanguage.values) {
        if (enabled && each == language) {
          await _messaging.subscribeToTopic(topicFor(each));
        } else {
          await _messaging.unsubscribeFromTopic(topicFor(each));
        }
        for (final s in Sector.values) {
          final topic = collectionTopicFor(s, each);
          if (collectionChanges && each == language && s == sector) {
            await _messaging.subscribeToTopic(topic);
          } else {
            await _messaging.unsubscribeFromTopic(topic);
          }
        }
      }
    } catch (error) {
      // Typically no network. Applied again at every start, so it self-heals.
      debugPrint('Push: could not update topics: $error');
    }
  }

  @override
  Stream<String> get openedAlertIds => isSupported
      ? FirebaseMessaging.onMessageOpenedApp
            .map((m) => targetOf(m.data))
            .where((id) => id != null)
            .cast<String>()
      : const Stream.empty();

  @override
  Future<String?> initialAlertId() async {
    if (!isSupported) return null;
    final message = await _messaging.getInitialMessage();
    return message == null ? null : targetOf(message.data);
  }
}

/// Keeps the push subscriptions in step with the settings: called at start
/// and whenever the language, sector or a notification switch changes.
class PushSync {
  PushSync(this._settings, this._push) {
    _settings.addListener(_sync);
    _sync();
  }

  final AppSettings _settings;
  final PushService _push;
  (AppLanguage, bool, Sector?, bool)? _applied;

  void _sync() {
    final language = _settings.language;
    if (language == null || !_settings.notificationsAsked) return;
    final wanted = (
      language,
      _settings.waterAlertsEnabled,
      _settings.sector,
      _settings.collectionChangesEnabled,
    );
    if (wanted == _applied) return;
    _applied = wanted;
    unawaited(_push.apply(
      language: language,
      enabled: wanted.$2,
      sector: wanted.$3,
      collectionChanges: wanted.$4,
    ));
  }
}
