import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../roads/road_data.dart';
import '../roads/roads_repository.dart';
import '../roads/roads_screen.dart' show RoadItemScreen;
import '../roads/roads_widgets.dart';
import '../settings/app_settings.dart';
import '../widgets/links.dart';

/// The Town's Work Info items, on the Alerts tab (release-prep spec D5).
/// Most of them aren't about roads (e.g. water system flushing), so they
/// moved here from the Roads screen in Milestone 9. The data still comes
/// from Firestore `roads` (`source: town-work-info`) via [RoadsRepository].
class TownWorkSection extends StatelessWidget {
  const TownWorkSection({super.key, required this.repository, required this.language, required this.now});

  final RoadsRepository repository;
  final AppLanguage language;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = repository.itemsFor(null);
    final health = roadsHealthLine(context, repository, townSources, now);
    // "Nothing posted" is a claim: only after a recent check (DESIGN §8).
    final checked = repository.health(townSources, now) is CheckedRecently;
    final fr = language == AppLanguage.fr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(l10n.roadsTownWorkHeading, style: textTheme.titleLarge)),
        const SizedBox(height: 8),
        Text(l10n.roadsTownWorkNote, style: textTheme.bodyLarge),
        const SizedBox(height: 8),
        if (health != null) ...[RoadsHealthLine(health: health), const SizedBox(height: 8)],
        for (final item in items)
          RoadItemCard(
            item: item,
            language: language,
            now: now,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => RoadItemScreen(item: item, language: language)),
            ),
          ),
        if (items.isEmpty && checked) Text(l10n.roadsNoTownWork, style: textTheme.bodyLarge),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.roadsTownLink),
            onPressed: () => openLink(Uri.parse(fr ? RoadLinks.townFr : RoadLinks.townEn)),
          ),
        ),
        Text(
          l10n.roadsTownSource,
          style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
