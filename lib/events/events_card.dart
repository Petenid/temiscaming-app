import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import 'event_widgets.dart';
import 'events_repository.dart';
import 'town_event.dart';

/// Today's "Coming up" card: the next three events, closures included
/// ("Town hall closed tomorrow"), events spec D10. Tapping opens the Events tab.
class EventsCard extends StatelessWidget {
  const EventsCard({
    super.key,
    required this.settings,
    required this.repository,
    required this.onOpenEvents,
    this.now,
  });

  final AppSettings settings;
  final EventsRepository repository;
  final VoidCallback onOpenEvents;

  /// For tests; defaults to the current time.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final language = settings.language ?? AppLanguage.fr;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final today = now ?? DateTime.now();
        final next = nextEvents(repository.events, today);
        final waiting = repository.loading && repository.events.isEmpty;
        // "Nothing coming up" only once the calendar has actually been read;
        // before that, the health line explains (principle 3).
        final checked = repository.health?.lastSuccessAt != null;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenEvents,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(l10n.eventsCardTitle, style: textTheme.titleSmall),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (waiting) const LinearProgressIndicator(),
                  if (!waiting && !repository.failed && checked && next.isEmpty)
                    Text(l10n.eventsCardNone, style: textTheme.bodyLarge),
                  for (final event in next)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CategoryIcon(event.category, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _when(context, event, today),
                                  style: textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                EventTitle(event: event, language: language, style: textTheme.bodyLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  EventsHealthLine(repository: repository, onlyWhenStale: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Today", "Tomorrow" or "Tue, Oct 27"; a running multi-day event says
  /// until when ("Today – until Dec 25").
  static String _when(BuildContext context, TownEvent event, DateTime today) {
    final l10n = AppLocalizations.of(context);
    final day = event.listedOn(today);
    final label = switch (eventWhen(day, today)) {
      EventWhen.today => l10n.eventToday,
      EventWhen.tomorrow => l10n.eventTomorrow,
      EventWhen.later => formatShortDay(context, day),
    };
    if (!event.isMultiDay) return label;
    return l10n.eventUntil(label, formatShortDay(context, event.endsOn));
  }
}
