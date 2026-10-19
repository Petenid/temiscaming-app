// The notifications step, the Settings switch, and keeping the push topic
// in step with the language (spec §3 D5, §6).
import 'package:community/home/home_shell.dart';
import 'package:community/onboarding/notifications_screen.dart';
import 'package:community/push/push_service.dart';
import 'package:community/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('phone first launch in ${language.name}: language → sector → notifications → home', (tester) async {
      final push = FakePushService(isSupported: true);
      final settings = await pumpApp(tester, const {}, null, push);
      final strings = stringsFor(language);

      await scrollAndTap(tester, find.text(strings.languageName));
      await scrollAndTap(tester, find.text(strings.sectorTownName));
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text(strings.notificationsExplanation), findsOneWidget);

      await scrollAndTap(tester, find.text(strings.notificationsAllow));
      expect(push.permissionRequests, 1);
      expect(settings.waterAlertsEnabled, isTrue);
      expect(find.byType(HomeShell), findsOneWidget);
    });
  }

  testWidgets('"Not now" skips notifications without asking the system', (tester) async {
    final push = FakePushService(isSupported: true);
    final settings = await pumpApp(tester, {'language': 'en', 'sector': 'town'}, null, push);
    // Already onboarded before this version: asked once now.
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await scrollAndTap(tester, find.text('Not now'));
    expect(push.permissionRequests, 0);
    expect(settings.notificationsAsked, isTrue);
    expect(settings.waterAlertsEnabled, isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('permission refused → water alerts off', (tester) async {
    final push = FakePushService(isSupported: true, grantPermission: false);
    final settings = await pumpApp(tester, {'language': 'fr', 'sector': 'town'}, null, push);
    await scrollAndTap(tester, find.text('Autoriser les notifications'));
    expect(settings.waterAlertsEnabled, isFalse);
    expect(settings.notificationsAsked, isTrue);
  });

  testWidgets('desktop: no notifications step, no Settings switch', (tester) async {
    await pumpApp(tester, {'language': 'en', 'sector': 'town'});
    expect(find.byType(HomeShell), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Water advisories'), findsNothing);
  });

  testWidgets('Settings switch turns water alerts on and off', (tester) async {
    final push = FakePushService(isSupported: true);
    final settings = await pumpApp(
      tester, {'language': 'en', 'sector': 'town', 'water_alerts': false}, null, push,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await scrollAndTap(tester, find.text('Water advisories'));
    expect(settings.waterAlertsEnabled, isTrue);
    expect(push.permissionRequests, 1);
    await scrollAndTap(tester, find.text('Water advisories'));
    expect(settings.waterAlertsEnabled, isFalse);
  });

  group('PushSync', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('subscribes to the topic of the current language, and switches with it', () async {
      SharedPreferences.setMockInitialValues({'language': 'fr', 'sector': 'town', 'water_alerts': true});
      final settings = await AppSettings.load();
      final push = FakePushService(isSupported: true);
      PushSync(settings, push);
      expect(push.applied, [(AppLanguage.fr, true)]);

      await settings.setLanguage(AppLanguage.en);
      await settings.setWaterAlerts(false);
      await settings.setSector(settings.sector!); // unrelated change: no extra call
      expect(push.applied, [(AppLanguage.fr, true), (AppLanguage.en, true), (AppLanguage.en, false)]);
    });

    test('does nothing until the notifications question is answered', () async {
      SharedPreferences.setMockInitialValues({'language': 'fr', 'sector': 'town'});
      final settings = await AppSettings.load();
      final push = FakePushService(isSupported: true);
      PushSync(settings, push);
      expect(push.applied, isEmpty);
    });

    test('topic names match the backend', () {
      expect(topicFor(AppLanguage.fr), 'water-fr');
      expect(topicFor(AppLanguage.en), 'water-en');
    });
  });
}
