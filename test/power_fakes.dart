import 'package:community/power/power_data.dart';
import 'package:community/power/power_repository.dart';

/// Power outage information held in memory; tests set it and the screens
/// update. By default: both lists checked 5 minutes ago, nothing in
/// Témiscaming — the real state on 27 October 2026.
class FakePowerRepository extends PowerRepository {
  FakePowerRepository({PowerStatus? status, bool loading = false, bool failed = false, bool never = false})
    : _status = never ? null : (status ?? SamplePower.quiet()),
      _loading = loading,
      _failed = failed;

  PowerStatus? _status;
  final bool _loading;
  final bool _failed;

  @override
  PowerStatus? get status => _status;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set(PowerStatus? status) {
    _status = status;
    notifyListeners();
  }
}

/// Outages modelled on what Hydro-Québec's file holds (spec §2): customers,
/// start, often no estimate at first, a crew status, a cause code.
class SamplePower {
  static DateTime ago(Duration d) => DateTime.now().subtract(d);
  static DateTime ahead(Duration d) => DateTime.now().add(d);

  /// Today at [hour]:[minute], or tomorrow / the day after with [days].
  static DateTime at(int hour, [int minute = 0, int days = 0]) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + days, hour, minute);
  }

  static PowerStatus quiet({Duration age = const Duration(minutes: 5)}) =>
      PowerStatus(outagesCheckedAt: ago(age), plannedCheckedAt: ago(age));

  /// A storm outage in town, 120 customers, crew on the way, no estimate yet.
  static Outage stormOutage() => Outage(
    kind: OutageKind.outage,
    customers: 120,
    startedAt: ago(const Duration(minutes: 40)),
    status: CrewStatus.onTheWay,
    cause: OutageCause.weather,
    area: PowerArea.temiscaming,
  );

  /// A small outage at Lac Tee with Hydro-Québec's estimate.
  static Outage lacTeeOutage() => Outage(
    kind: OutageKind.outage,
    customers: 3,
    startedAt: ago(const Duration(hours: 1)),
    estimatedEndAt: ahead(const Duration(hours: 2)),
    status: CrewStatus.atWork,
    cause: OutageCause.vegetation,
    area: PowerArea.lacTee,
  );

  /// Planned work under way in town.
  static Outage plannedWork() => Outage(
    kind: OutageKind.plannedInProgress,
    customers: 80,
    startedAt: ago(const Duration(hours: 1)),
    estimatedEndAt: ahead(const Duration(hours: 3)),
    status: CrewStatus.atWork,
    cause: OutageCause.plannedWork,
    area: PowerArea.temiscaming,
  );

  /// Tomorrow, 8:30 to 12:00, moved from today, with a backup date.
  static PlannedInterruption tomorrow() => PlannedInterruption(
    customers: 63,
    startsAt: at(8, 30, 1),
    endsAt: at(12, 0, 1),
    originalStartsAt: at(8, 30),
    alternateStartsAt: at(8, 30, 8),
    alternateEndsAt: at(12, 0, 8),
    area: PowerArea.temiscaming,
  );

  /// Next week, not on Today.
  static PlannedInterruption nextWeek() => PlannedInterruption(
    customers: 155,
    startsAt: at(8, 30, 6),
    endsAt: at(10, 30, 6),
    area: PowerArea.lacTee,
  );

  static PowerStatus stormDay() => PowerStatus(
    outages: [stormOutage(), plannedWork(), lacTeeOutage()],
    planned: [tomorrow(), nextWeek()],
    outagesCheckedAt: ago(const Duration(minutes: 5)),
    plannedCheckedAt: ago(const Duration(minutes: 20)),
  );
}

/// Named states for screenshots.
class PowerStatusSamples {
  /// The last check two hours ago, with the storm outage still on record.
  static PowerStatus staleWithOutage() => PowerStatus(
    outages: [SamplePower.stormOutage()],
    outagesCheckedAt: SamplePower.ago(const Duration(hours: 2)),
    plannedCheckedAt: SamplePower.ago(const Duration(hours: 2)),
  );
}
