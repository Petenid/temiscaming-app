import 'dart:async';

import 'package:community/collection/collection_repository.dart';
import 'package:community/collection/pickup.dart';
import 'package:community/collection/reminders.dart';
import 'package:community/collection/schedule.dart';
import 'package:community/l10n/app_localizations.dart';
import 'package:community/settings/sector.dart';

/// Pickups held in memory; tests set them and the screens update.
class FakeCollectionRepository extends CollectionRepository {
  FakeCollectionRepository({
    List<Pickup> pickups = const [],
    CollectionHealth? health,
    bool loading = false,
    bool failed = false,
  }) : _pickups = pickups,
       _health = health ?? CollectionHealth(lastSuccessAt: DateTime.now()),
       _loading = loading,
       _failed = failed;

  List<Pickup> _pickups;
  CollectionHealth? _health;
  bool _loading;
  bool _failed;

  @override
  List<Pickup> get pickups => _pickups;
  @override
  CollectionHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set({List<Pickup>? pickups, CollectionHealth? health, bool? failed}) {
    _pickups = pickups ?? _pickups;
    _health = health ?? _health;
    _failed = failed ?? _failed;
    _loading = false;
    notifyListeners();
  }
}

/// Builds pickups the way the backend stores them.
Pickup pickup(
  String date,
  Sector sector,
  BinMaterial? material, {
  String? special,
  PickupOrigin origin = PickupOrigin.town,
  bool cancelled = false,
  String? movedFrom,
}) => Pickup(
  id: '${date}_${sector.name}_${material?.name ?? special}',
  date: parseDay(date)!,
  sector: sector,
  material: material,
  special: special,
  origin: origin,
  cancelled: cancelled,
  previousDate: movedFrom == null ? null : parseDay(movedFrom),
  change: cancelled ? 'cancelled' : movedFrom != null ? 'moved' : null,
);

/// Modelled on the Town's real calendar for October–November 2026
/// (Monday 19 October 2026 is "today" in most tests).
class SamplePickups {
  static final monday19Oct = DateTime(2026, 10, 19, 10);

  static List<Pickup> octoberNovember() => [
    pickup('2026-10-20', Sector.town, BinMaterial.garbage),
    pickup('2026-10-21', Sector.lumsden, BinMaterial.garbage),
    pickup('2026-10-27', Sector.town, BinMaterial.recycling),
    pickup('2026-10-28', Sector.lumsden, BinMaterial.recycling),
    pickup('2026-11-03', Sector.town, BinMaterial.compost),
    pickup('2026-11-04', Sector.lumsden, BinMaterial.compost),
  ];

  /// Pickups relative to today, for whole-app tests and screenshots: one
  /// tomorrow, one moved, one cancelled, a two-bin day from the MRC calendar
  /// and a Christmas-tree pickup.
  static List<Pickup> aroundToday() {
    final today = dateOnly(DateTime.now());
    String d(int days) => dayKey(addDays(today, days));
    return [
      for (final sector in Sector.values) ...[
        pickup(d(1), sector, BinMaterial.recycling),
        pickup(d(2), sector, null, special: 'christmas-trees'),
        pickup(d(8), sector, BinMaterial.garbage, movedFrom: d(7)),
        pickup(d(14), sector, BinMaterial.recycling, cancelled: true),
        pickup(d(21), sector, BinMaterial.compost, origin: PickupOrigin.mrc),
        pickup(d(21), sector, BinMaterial.recycling, origin: PickupOrigin.mrc),
      ],
    ];
  }
}

/// Records what the app scheduled, instead of showing notifications.
class FakeReminderService implements ReminderService {
  FakeReminderService({this.isSupported = false});

  @override
  final bool isSupported;

  /// Every replacement, newest last.
  final replacements = <List<Reminder>>[];
  final tests = <Reminder>[];
  final _tapped = StreamController<void>.broadcast();
  bool launched = false;

  /// What's currently scheduled.
  List<Reminder> get scheduled => replacements.isEmpty ? const [] : replacements.last;

  /// Simulates tapping a reminder.
  void tap() => _tapped.add(null);

  @override
  Future<void> replaceAll(List<Reminder> reminders, AppLocalizations strings) async {
    replacements.add(List.of(reminders));
  }

  @override
  Future<void> scheduleTest(Reminder reminder, AppLocalizations strings) async => tests.add(reminder);

  @override
  Stream<void> get tapped => _tapped.stream;

  @override
  Future<bool> launchedByReminder() async => launched;
}
