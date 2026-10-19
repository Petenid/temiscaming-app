import 'package:flutter/material.dart';

import 'home/today_screen.dart';
import 'l10n/app_localizations.dart';
import 'onboarding/onboarding_flow.dart';
import 'settings/app_settings.dart';

/// The root widget: language, theme, and which screen to show first.
class TemiscamingApp extends StatelessWidget {
  const TemiscamingApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app whenever a setting changes, so a new language
    // applies everywhere at once.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
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
        home: settings.isOnboarded
            ? TodayScreen(settings: settings)
            : OnboardingFlow(settings: settings),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    // Placeholder colour (lake blue) until the app has a visual identity.
    colorSchemeSeed: const Color(0xFF1B5E7A),
    brightness: brightness,
  );
}
