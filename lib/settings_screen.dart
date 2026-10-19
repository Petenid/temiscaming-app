import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'settings/sector.dart';

/// Change the language or sector after first launch. Changes apply at once.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).settingsTitle)),
      // Rebuilds the list when a setting changes, to move the checkmark.
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final l10n = AppLocalizations.of(context);
          return ListView(
            children: [
              _SectionHeader(l10n.settingsLanguage),
              for (final language in AppLanguage.values)
                _ChoiceTile(
                  // Each language's name is always written in itself.
                  title: Text(
                    lookupAppLocalizations(language.locale).languageName,
                    locale: language.locale,
                  ),
                  selected: settings.language == language,
                  onTap: () => settings.setLanguage(language),
                ),
              const Divider(),
              _SectionHeader(l10n.settingsSector),
              for (final sector in Sector.values)
                _ChoiceTile(
                  title: Text(sector.displayName(context)),
                  subtitle: Text(sector.collectionDayLabel(context)),
                  selected: settings.sector == sector,
                  onTap: () => settings.setSector(sector),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One option in a list. The current choice gets a checkmark (not just a
/// colour change), and screen readers announce it as selected.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: title,
      subtitle: subtitle,
      selected: selected,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
