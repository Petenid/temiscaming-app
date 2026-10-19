import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// The collection sectors a resident can pick (DESIGN.md §6.2).
///
/// Each sector is saved on the device by its [name] ("town", "lumsden"), so
/// adding a sector later never breaks anyone's saved choice.
enum Sector {
  /// Témiscaming town, Lac Tee and cottage roads.
  town(DateTime.tuesday),

  /// Lumsden and Letang.
  lumsden(DateTime.wednesday);

  const Sector(this.collectionWeekday);

  /// Day of the week bins are collected, using Dart's numbering
  /// (`DateTime.monday` = 1 … `DateTime.sunday` = 7). Used from Milestone 2.
  final int collectionWeekday;

  /// Reads a saved ID back into a sector; `null` if missing or unknown.
  static Sector? fromId(String? id) => Sector.values.asNameMap()[id];

  /// The sector's area names, in the current language.
  String displayName(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (this) {
      Sector.town => l10n.sectorTownName,
      Sector.lumsden => l10n.sectorLumsdenName,
    };
  }

  /// "Collection on Tuesdays" etc., in the current language.
  String collectionDayLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (this) {
      Sector.town => l10n.sectorTownDay,
      Sector.lumsden => l10n.sectorLumsdenDay,
    };
  }
}
