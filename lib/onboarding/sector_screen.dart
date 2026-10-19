import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/sector.dart';
import '../widgets/centered_scroll_column.dart';

/// Second first-launch screen: which collection sector the user lives in.
class SectorScreen extends StatelessWidget {
  const SectorScreen({
    super.key,
    required this.onBack,
    required this.onSelected,
  });

  final VoidCallback onBack;
  final ValueChanged<Sector> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: onBack),
        title: Text(l10n.sectorTitle),
      ),
      body: SafeArea(
        child: CenteredScrollColumn(
          children: [
            Semantics(
              header: true,
              child: Text(l10n.sectorPrompt, style: textTheme.headlineSmall),
            ),
            const SizedBox(height: 8),
            Text(l10n.sectorExplanation, style: textTheme.bodyLarge),
            const SizedBox(height: 24),
            for (final sector in Sector.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _SectorButton(
                  sector: sector,
                  onPressed: () => onSelected(sector),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A large button showing a sector's area names and its collection day.
class _SectorButton extends StatelessWidget {
  const _SectorButton({required this.sector, required this.onPressed});

  final Sector sector;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(72),
        padding: const EdgeInsets.all(20),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sector.displayName(context), style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(sector.collectionDayLabel(context), style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}
