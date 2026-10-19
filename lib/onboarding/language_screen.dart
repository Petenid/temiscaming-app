import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/centered_scroll_column.dart';

/// The very first screen: "Français" or "English" (DESIGN.md §5).
///
/// No language has been chosen yet, so everything here is shown in both
/// languages, each looked up from its own ARB file. The two buttons are the
/// same widget with the same style, and neither is pre-selected. French comes
/// first only because [AppLanguage.values] lists it first.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, required this.onSelected});

  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: CenteredScrollColumn(
          children: [
            for (final language in AppLanguage.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    lookupAppLocalizations(language.locale).chooseLanguage,
                    // Tells screen readers which language to pronounce.
                    locale: language.locale,
                    style: textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SizedBox(height: 32),
            for (final language in AppLanguage.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton(
                  onPressed: () => onSelected(language),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    textStyle: textTheme.titleLarge,
                  ),
                  child: Text(
                    lookupAppLocalizations(language.locale).languageName,
                    locale: language.locale,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
