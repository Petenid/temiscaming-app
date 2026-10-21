import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/links.dart';
import 'calendar_adder.dart';
import 'event_widgets.dart';
import 'town_event.dart';

/// One event: what the Town's calendar says, a link to the Town's page
/// (principle 2), and "Add to my calendar" on phones (events spec D6).
class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({
    super.key,
    required this.event,
    required this.language,
    required this.calendar,
  });

  final TownEvent event;
  final AppLanguage language;
  final CalendarAdder calendar;

  /// What goes into the phone's calendar: the Town's title (or our category
  /// name), the place, and the Town's page in the notes.
  CalendarRequest requestFor(AppLocalizations l10n) {
    final place = event.place(language);
    final url = event.sourceUrl(language);
    return CalendarRequest(
      title: event.isUntitled ? categoryName(l10n, event.category) : event.title(language),
      firstDay: event.startsOn,
      lastDay: event.endsOn,
      location: place.isEmpty ? l10n.eventLocationTown : l10n.eventLocation(place),
      notes: url.isEmpty ? l10n.eventsSourceNote : l10n.eventCalendarNotes(url),
    );
  }

  Future<void> _addToCalendar(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await calendar.add(requestFor(l10n));
    if (outcome == CalendarOutcome.noCalendarApp) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.eventNoCalendarApp)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final shownIn = event.displayLanguage(language);
    final place = event.place(language);
    final url = event.sourceUrl(language);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.eventsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (shownIn != language) ...[
              _Notice(
                icon: Icons.translate,
                text: shownIn == AppLanguage.fr ? l10n.alertOnlyFrench : l10n.alertOnlyEnglish,
              ),
              const SizedBox(height: 16),
            ],
            // The category above the title; an untitled event (spec D3) shows
            // the category as its title, so it isn't said twice.
            Row(
              children: [
                CategoryIcon(event.category, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: event.isUntitled
                      ? Semantics(
                          header: true,
                          child: EventTitle(event: event, language: language, style: textTheme.headlineSmall),
                        )
                      : Text(categoryName(l10n, event.category), style: textTheme.labelLarge),
                ),
              ],
            ),
            if (!event.isUntitled) ...[
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: EventTitle(event: event, language: language, style: textTheme.headlineSmall),
              ),
            ],
            const SizedBox(height: 16),
            _Fact(icon: Icons.event_outlined, text: formatEventDates(context, event)),
            if (place.isNotEmpty) _Fact(icon: Icons.place_outlined, text: place),
            const SizedBox(height: 8),
            _Notice(icon: Icons.schedule, text: l10n.eventNoTimesNote),
            const SizedBox(height: 24),
            if (url.isNotEmpty)
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.alertViewOnSite),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => openLink(Uri.parse(url)),
              ),
            if (calendar.isSupported) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available_outlined),
                label: Text(l10n.eventAddToCalendar),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => _addToCalendar(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
