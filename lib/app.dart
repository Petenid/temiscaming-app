import 'package:flutter/material.dart';

import 'dart:async';

import 'alerts/alert_detail_screen.dart';
import 'home/home_shell.dart';
import 'l10n/app_localizations.dart';
import 'onboarding/notifications_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'services.dart';
import 'settings/app_settings.dart';

/// The root widget: language, theme, and which screen to show first.
class TemiscamingApp extends StatefulWidget {
  const TemiscamingApp({super.key, required this.settings, required this.services});

  final AppSettings settings;
  final AppServices services;

  @override
  State<TemiscamingApp> createState() => _TemiscamingAppState();
}

class _TemiscamingAppState extends State<TemiscamingApp> {
  // Lets a tapped notification open its alert from outside any screen.
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _opened;

  AppSettings get settings => widget.settings;
  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _opened = services.push.openedAlertIds.listen(_openAlert);
    services.push.initialAlertId().then((id) {
      if (id != null) _openAlert(id);
    });
  }

  void _openAlert(String id) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => AlertByIdScreen(
          id: id,
          repository: services.alerts,
          language: settings.language ?? AppLanguage.fr,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app whenever a setting changes, so a new language
    // applies everywhere at once.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        // Before the user chooses, built-in widgets need *some* language;
        // French is the majority language here. The language screen itself
        // shows both languages equally and doesn't depend on this.
        locale: (settings.language ?? AppLanguage.fr).locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: !settings.isOnboarded
            ? OnboardingFlow(settings: settings)
            : services.push.isSupported && !settings.notificationsAsked
            ? NotificationsScreen(settings: settings, push: services.push)
            : HomeShell(settings: settings, services: services),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    // Placeholder colour (lake blue) until the app has a visual identity.
    colorSchemeSeed: const Color(0xFF1B5E7A),
    brightness: brightness,
  );
}
