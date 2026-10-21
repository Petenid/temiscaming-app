import 'package:flutter/material.dart';

import '../collection/collection_widgets.dart' show townCalendarUrlEn, townCalendarUrlFr;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import '../widgets/links.dart';
import 'calendar_adder.dart';
import 'event_detail_screen.dart';
import 'event_widgets.dart';
import 'events_repository.dart';
import 'town_event.dart';

/// The Town's upcoming events, grouped by day (events spec §6).
class EventsScreen extends StatelessWidget {
  const EventsScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.calendar,
    required this.appBarActions,
    this.now,
  });

  final AppSettings settings;
  final EventsRepository repository;
  final CalendarAdder calendar;
  final List<Widget> appBarActions;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final language = settings.language ?? AppLanguage.fr;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.eventsTitle), actions: appBarActions),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final days = agenda(repository.events, now ?? DateTime.now());
          final listedThrough = repository.health?.listedThrough;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: EventsHealthLine(repository: repository),
              ),
              if (repository.loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (days.isEmpty && !repository.failed)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.eventsEmpty, style: textTheme.bodyLarge),
                ),
              for (final day in days) ...[
                _DayHeading(day.date),
                for (final event in day.events)
                  _EventTile(event: event, language: language, calendar: calendar),
              ],
              // Our window ends; the Town's events don't (spec D8).
              if (listedThrough != null && !repository.loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    l10n.eventsNotPostedAfter(formatLongDay(context, listedThrough)),
                    style: textTheme.bodyMedium,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.collectionTownCalendarLink),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => openLink(Uri.parse(
                    language == AppLanguage.fr ? townCalendarUrlFr : townCalendarUrlEn,
                  )),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(l10n.eventsSourceNote, style: textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final text = formatLongDay(context, date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          text[0].toUpperCase() + text.substring(1),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.language, required this.calendar});

  final TownEvent event;
  final AppLanguage language;
  final CalendarAdder calendar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final place = event.place(language);
    final details = [
      // An untitled event already shows the category as its title (spec D3).
      if (!event.isUntitled) categoryName(l10n, event.category),
      if (event.isMultiDay) formatDayRange(context, event.startsOn, event.endsOn),
      if (place.isNotEmpty) place,
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CategoryIcon(event.category),
      title: EventTitle(event: event, language: language),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(details.join(' · ')),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailScreen(event: event, language: language, calendar: calendar),
        ),
      ),
    );
  }
}
