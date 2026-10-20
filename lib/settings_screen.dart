import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'collection/collection_repository.dart';
import 'collection/reminders.dart';
import 'l10n/app_localizations.dart';
import 'push/push_service.dart';
import 'settings/app_settings.dart';
import 'settings/sector.dart';
import 'widgets/dates.dart';

/// Change the language, sector or notifications after first launch.
/// Changes apply at once.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.push,
    required this.reminders,
    required this.collection,
  });

  final AppSettings settings;
  final PushService push;
  final ReminderService reminders;
  final CollectionRepository collection;

  /// Turning a notification on asks the system first (once granted, it
  /// doesn't ask again); turning it off never asks.
  Future<void> _setNotified(BuildContext context, bool on, Future<void> Function(bool) save) async {
    if (!on) return save(false);
    final messenger = ScaffoldMessenger.of(context);
    final denied = AppLocalizations.of(context).settingsPermissionDenied;
    if (await push.requestPermission()) {
      await save(true);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
    }
  }

  Future<void> _pickReminderTime(BuildContext context) async {
    final m = settings.reminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (picked != null) await settings.setReminderMinutes(picked.hour * 60 + picked.minute);
  }

  /// Debug builds only: a reminder in 2 minutes, to check reminders arrive
  /// even in airplane mode (spec §8 step 5).
  Future<void> _testReminder(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final next = buildReminders(
      pickups: collection.pickups,
      sector: settings.sector ?? Sector.town,
      now: DateTime.now(),
      minutes: settings.reminderMinutes,
      strings: l10n,
    ).firstOrNull;
    await reminders.scheduleTest(
      Reminder(
        id: 1,
        at: DateTime.now().add(const Duration(minutes: 2)),
        title: next?.title ?? l10n.reminderTitle(l10n.binRecyclingShort),
        body: next?.body ?? l10n.reminderBodyOne,
      ),
      l10n,
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsTestReminderScheduled)));
  }

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
              // Push works on phones only (DESIGN §4).
              if (push.isSupported) ...[
                const Divider(),
                _SectionHeader(l10n.settingsNotifications),
                SwitchListTile(
                  title: Text(l10n.settingsWaterAlerts),
                  subtitle: Text(l10n.settingsWaterAlertsSubtitle),
                  value: settings.waterAlertsEnabled,
                  onChanged: (on) => _setNotified(context, on, settings.setWaterAlerts),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsBinReminder),
                  subtitle: Text(l10n.settingsBinReminderSubtitle),
                  value: settings.binReminderEnabled,
                  onChanged: (on) => _setNotified(context, on, settings.setBinReminder),
                ),
                ListTile(
                  title: Text(l10n.settingsReminderTime),
                  trailing: Text(
                    formatTime(
                      context,
                      DateTime(2000, 1, 1, settings.reminderMinutes ~/ 60, settings.reminderMinutes % 60),
                    ),
                  ),
                  enabled: settings.binReminderEnabled,
                  onTap: () => _pickReminderTime(context),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsCollectionChanges),
                  subtitle: Text(l10n.settingsCollectionChangesSubtitle),
                  value: settings.collectionChangesEnabled,
                  onChanged: (on) => _setNotified(context, on, settings.setCollectionChanges),
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(l10n.settingsTestReminder),
                    onTap: () => _testReminder(context),
                  ),
              ],
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
