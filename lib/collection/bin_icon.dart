import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'pickup.dart';

/// Bin colours appear only on bin icons, always next to the bin's name
/// (research §5b, DESIGN §7: never colour alone).
Color binColor(BinMaterial material) => switch (material) {
  BinMaterial.compost => const Color(0xFF2E7D32),
  BinMaterial.recycling => const Color(0xFF1565C0),
  BinMaterial.garbage => const Color(0xFF212121),
};

/// A round bin badge. Decorative: the bin's name is always written beside it,
/// so screen readers skip the icon.
class BinIcon extends StatelessWidget {
  const BinIcon(this.material, {super.key, this.size = 32});

  final BinMaterial material;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: binColor(material),
          shape: BoxShape.circle,
          // The black bin needs an outline to show on a dark background.
          border: dark ? Border.all(color: Colors.white70, width: 1.5) : null,
        ),
        child: Icon(Icons.delete_outline, color: Colors.white, size: size * 0.6),
      ),
    );
  }
}

/// Icon for special collections (Christmas trees).
class SpecialCollectionIcon extends StatelessWidget {
  const SpecialCollectionIcon({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Icon(Icons.park_outlined, size: size * 0.8, color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// "bac bleu" / "blue bin", for use inside sentences.
String binShortName(AppLocalizations l10n, BinMaterial material) => switch (material) {
  BinMaterial.compost => l10n.binCompostShort,
  BinMaterial.recycling => l10n.binRecyclingShort,
  BinMaterial.garbage => l10n.binGarbageShort,
};

/// "Bac bleu (recyclage)" / "Blue bin (recycling)", for lists.
String binFullName(AppLocalizations l10n, BinMaterial material) => switch (material) {
  BinMaterial.compost => l10n.binCompost,
  BinMaterial.recycling => l10n.binRecycling,
  BinMaterial.garbage => l10n.binGarbage,
};

/// "bac vert et bac bleu" / "green bin and blue bin".
String binsInSentence(AppLocalizations l10n, List<BinMaterial> bins) {
  final names = bins.map((b) => binShortName(l10n, b)).toList();
  if (names.length <= 1) return names.join();
  return l10n.listAnd(names.sublist(0, names.length - 1).join(', '), names.last);
}

/// The name of a special collection ("Christmas tree pickup").
String specialName(AppLocalizations l10n, String special) => switch (special) {
  'christmas-trees' => l10n.specialChristmasTrees,
  _ => l10n.specialOther,
};
