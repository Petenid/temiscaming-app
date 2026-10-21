import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alerts/alert_widgets.dart' show urgentColor;
import '../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/dates.dart';
import 'events_repository.dart';
import 'town_event.dart';

/// Our name for a category (events spec D4), e.g. "Town council" — which
/// also gives English council titles ("Regular session") their context.
String categoryName(AppLocalizations l10n, EventCategory category) => switch (category) {
  EventCategory.council => l10n.eventCategoryCouncil,
  EventCategory.closure => l10n.eventCategoryClosure,
  EventCategory.serviceCanada => l10n.eventCategoryServiceCanada,
  EventCategory.culture => l10n.eventCategoryCulture,
  EventCategory.community => l10n.eventCategoryCommunity,
};

IconData categoryIcon(EventCategory category) => switch (category) {
  EventCategory.council => Icons.gavel,
  EventCategory.closure => Icons.event_busy,
  EventCategory.serviceCanada => Icons.account_balance_outlined,
  EventCategory.culture => Icons.theater_comedy_outlined,
  EventCategory.community => Icons.groups_outlined,
};

/// The category's icon. Rows always show the category name next to it, so
/// the icon is decoration for screen readers (never meaning by icon alone).
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 28});

  final EventCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      categoryIcon(category),
      size: size,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

/// The Town's title in the language it's shown in; for an untitled event
/// (spec D3), our category name in italics.
class EventTitle extends StatelessWidget {
  const EventTitle({super.key, required this.event, required this.language, this.style});

  final TownEvent event;
  final AppLanguage language;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (event.isUntitled) {
      return Text(
        categoryName(AppLocalizations.of(context), event.category),
        style: (style ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic),
      );
    }
    return Text(
      event.title(language),
      style: style,
      // Lets screen readers pronounce a French-only title in French.
      locale: event.displayLanguage(language).locale,
    );
  }
}

/// A short range: "21–25 déc." / "Dec 21–25"; across months
/// "29 déc. – 2 janv." / "Dec 29 – Jan 2".
String formatDayRange(BuildContext context, DateTime first, DateTime last) {
  final code = Localizations.localeOf(context).languageCode;
  final short = DateFormat.MMMd('${code}_CA');
  if (first.year == last.year && first.month == last.month) {
    return code == 'fr'
        ? '${first.day}–${short.format(last)}'
        : '${short.format(first)}–${last.day}';
  }
  return '${short.format(first)} – ${short.format(last)}';
}

/// "Monday, December 21" for one day; "December 21 to 25" style for a range.
String formatEventDates(BuildContext context, TownEvent event) {
  final l10n = AppLocalizations.of(context);
  final first = formatLongDay(context, event.startsOn);
  if (!event.isMultiDay) return _capitalized(first);
  return l10n.eventDateRange(first, formatLongDay(context, event.endsOn));
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "Calendar checked 16:40", or in red "Couldn't check the Town's calendar
/// since 14:20" (principle 3). Same source and wording as the bin schedule.
class EventsHealthLine extends StatelessWidget {
  const EventsHealthLine({super.key, required this.repository, this.onlyWhenStale = false});

  final EventsRepository repository;
  final bool onlyWhenStale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (repository.loading) return const SizedBox.shrink();
    final health = repository.health;
    final String text;
    final bool problem;
    if (repository.failed) {
      text = l10n.eventsLoadFailed;
      problem = true;
    } else if (health == null || health.lastSuccessAt == null) {
      text = l10n.collectionNeverChecked;
      problem = true;
    } else if (health.isStale(DateTime.now())) {
      text = l10n.collectionCheckFailedSince(formatWhen(context, health.lastSuccessAt!));
      problem = true;
    } else {
      text = l10n.collectionLastChecked(formatWhen(context, health.lastSuccessAt!));
      problem = false;
    }
    if (onlyWhenStale && !problem) return const SizedBox.shrink();
    final color = problem ? urgentColor(context) : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        // Icon + words, never colour alone (DESIGN §7).
        Icon(problem ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}
