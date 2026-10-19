import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';

/// Push notifications for water advisories (spec §3 D5).
///
/// Each phone subscribes to one FCM "topic" matching its language
/// (`water-fr` or `water-en`). The backend sends one message per topic, so
/// every phone gets exactly one notification, in its own language, and we
/// never need to store anyone's device token.
abstract class PushService {
  /// Push works on iPhone and Android only; desktop shows alerts in-app (DESIGN §4).
  bool get isSupported;

  /// Shows the system "allow notifications?" prompt. True if allowed.
  Future<bool> requestPermission();

  /// Subscribes to the right topic (or none) and, on Android, (re)creates the
  /// notification channels with names in the user's language.
  Future<void> apply({required AppLanguage language, required bool enabled});

  /// Alert ids from notifications the user taps while the app is running.
  Stream<String> get openedAlertIds;

  /// The alert id of the notification that launched the app, if any.
  Future<String?> initialAlertId();
}

String topicFor(AppLanguage language) => 'water-${language.name}';

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
        });
      }
      for (final each in AppLanguage.values) {
        if (enabled && each == language) {
          await _messaging.subscribeToTopic(topicFor(each));
        } else {
          await _messaging.unsubscribeFromTopic(topicFor(each));
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
            .map((m) => m.data['alert_id'] as String?)
            .where((id) => id != null)
            .cast<String>()
      : const Stream.empty();

  @override
  Future<String?> initialAlertId() async {
    if (!isSupported) return null;
    final message = await _messaging.getInitialMessage();
    return message?.data['alert_id'] as String?;
  }
}

/// Keeps the push subscription in step with the settings: called at start
/// and whenever the language or the water-alerts switch changes.
class PushSync {
  PushSync(this._settings, this._push) {
    _settings.addListener(_sync);
    _sync();
  }

  final AppSettings _settings;
  final PushService _push;
  (AppLanguage, bool)? _applied;

  void _sync() {
    final language = _settings.language;
    if (language == null || !_settings.notificationsAsked) return;
    final wanted = (language, _settings.waterAlertsEnabled);
    if (wanted == _applied) return;
    _applied = wanted;
    unawaited(_push.apply(language: language, enabled: wanted.$2));
  }
}
