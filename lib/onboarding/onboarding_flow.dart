import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'language_screen.dart';
import 'sector_screen.dart';

/// First launch: language, then sector.
///
/// Both steps live in this one widget (rather than pushing screens on top of
/// each other) so that when the sector is saved, the app can swap the whole
/// flow for the Today screen with nothing left behind.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  bool _languageChosen = false;

  void _back() => setState(() => _languageChosen = false);

  @override
  Widget build(BuildContext context) {
    if (!_languageChosen) {
      return LanguageScreen(
        onSelected: (language) {
          widget.settings.setLanguage(language);
          setState(() => _languageChosen = true);
        },
      );
    }
    // PopScope makes Android's system back gesture return to the language
    // step instead of closing the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SectorScreen(onBack: _back, onSelected: widget.settings.setSector),
    );
  }
}
