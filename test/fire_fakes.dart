import 'package:community/fire/fire_data.dart';
import 'package:community/fire/fire_repository.dart';

/// Fire-ban status held in memory; tests set it and the screens update.
class FakeFireRepository extends FireRepository {
  FakeFireRepository({FireStatus? status, bool useDefault = true, bool loading = false, bool failed = false})
    : _status = status ?? (useDefault ? SampleFire.none() : null),
      _loading = loading,
      _failed = failed;

  FireStatus? _status;
  bool _loading;
  final bool _failed;

  @override
  FireStatus? get status => _status;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set(FireStatus? status) {
    _status = status;
    _loading = false;
    notifyListeners();
  }
}

/// Sample states modelled on the backend's first live run (2026-10-21: no
/// ban anywhere in Quebec since 20 July, noon) and the hand-made ban
/// fixtures in functions/test/fixtures/fire/hand-made/.
class SampleFire {
  static DateTime ago(Duration d) => DateTime.now().subtract(d);

  /// 20 July 2026, 12:00 in Témiscaming (EDT).
  static final lastLifted = DateTime.utc(2026, 7, 20, 16);

  static FireLayerStatus layer(
    FireLayer l,
    FireLayerState state, {
    DateTime? startsAt,
    Duration checkedAge = const Duration(minutes: 10),
    int? nearestKm,
  }) => FireLayerStatus(
    layer: l,
    state: state,
    checkedAt: ago(checkedAge),
    startsAt: startsAt,
    noneSince: state == FireLayerState.none && nearestKm == null ? lastLifted : null,
    nearestKm: nearestKm ?? (state == FireLayerState.none ? null : 0),
  );

  /// Today's real state: nothing anywhere.
  static FireStatus none({Duration checkedAge = const Duration(minutes: 10)}) => FireStatus(
    ifco: layer(FireLayer.ifco, FireLayerState.none, checkedAge: checkedAge),
    icaf: layer(FireLayer.icaf, FireLayerState.none, checkedAge: checkedAge),
  );

  /// An open-fire ban covering the MRC, in effect since this morning.
  static FireStatus banStarted({Duration checkedAge = const Duration(minutes: 10)}) => FireStatus(
    ifco: layer(FireLayer.ifco, FireLayerState.town, startsAt: ago(const Duration(hours: 3)), checkedAge: checkedAge),
    icaf: layer(FireLayer.icaf, FireLayerState.none, checkedAge: checkedAge),
  );

  /// Announced: starts tomorrow at 8 a.m.
  static FireStatus banAnnounced() {
    final now = DateTime.now();
    return FireStatus(
      ifco: layer(FireLayer.ifco, FireLayerState.town, startsAt: DateTime(now.year, now.month, now.day + 1, 8)),
      icaf: layer(FireLayer.icaf, FireLayerState.none),
    );
  }

  /// Both: open fires banned in town, and the forest closed around it.
  static FireStatus both() => FireStatus(
    ifco: layer(FireLayer.ifco, FireLayerState.town, startsAt: ago(const Duration(days: 2))),
    icaf: layer(FireLayer.icaf, FireLayerState.around, startsAt: ago(const Duration(hours: 5)), nearestKm: 4),
  );

  /// Like July 2026: a ban over Rouyn-Noranda and Abitibi, not here.
  static FireStatus region() => FireStatus(
    ifco: layer(FireLayer.ifco, FireLayerState.region, nearestKm: 131),
    icaf: layer(FireLayer.icaf, FireLayerState.none),
  );
}
