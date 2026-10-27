import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'road_data.dart';

/// How recently a group of sources was read (DESIGN §4 source health).
sealed class RoadsHealth {
  const RoadsHealth();
}

/// At least one source hasn't been read even once.
class NeverChecked extends RoadsHealth {
  const NeverChecked();
}

/// All read recently; [oldest] is the least recent of them.
class CheckedRecently extends RoadsHealth {
  const CheckedRecently(this.oldest);
  final DateTime oldest;
}

/// At least one hasn't been read for longer than its limit (spec D4).
class CheckFailing extends RoadsHealth {
  const CheckFailing(this.oldest);
  final DateTime oldest;
}

/// Gives the screens the road items, conditions and cameras, and the health
/// of each source. The real one reads Firestore; tests use a fake.
abstract class RoadsRepository extends ChangeNotifier {
  /// Items on our stretches and the Town's work (Firestore `roads`).
  List<RoadItem> get items;

  /// Null until the backend has read that road's conditions once.
  RoadConditions? conditions(Road road);

  /// Highway 63 cameras (empty until known).
  List<RoadCamera> get cameras;

  /// When each source was last read successfully (`sources/{id}`); a source
  /// never read is missing.
  Map<String, DateTime?> get lastSuccess;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when nothing could be loaded at all.
  bool get failed;

  /// The health of [sources] at [now] (spec D4).
  RoadsHealth health(List<String> sources, DateTime now) {
    final times = [for (final s in sources) lastSuccess[s]];
    if (times.any((t) => t == null)) return const NeverChecked();
    final oldest = times.cast<DateTime>().reduce((a, b) => a.isBefore(b) ? a : b);
    final stale = [for (final s in sources) now.difference(lastSuccess[s]!) > staleAfter(s)].any((x) => x);
    return stale ? CheckFailing(oldest) : CheckedRecently(oldest);
  }

  /// Items for a road (or the Town's, when [road] is null).
  List<RoadItem> itemsFor(Road? road) => [
    for (final i in items)
      if (road == null ? i.kind == RoadItemKind.town : i.road == road && i.kind != RoadItemKind.town) i,
  ];
}

/// Reads Firestore. It keeps a copy on the phone, so the last information
/// still shows offline, with its "checked" times.
class FirestoreRoadsRepository extends RoadsRepository {
  FirestoreRoadsRepository(FirebaseFirestore db) {
    void failedWith(Object error) {
      debugPrint('Roads: Firestore error: $error');
      _loading = false;
      _failed = _items.isEmpty && _lastSuccess.isEmpty;
      notifyListeners();
    }

    _subs.add(db.collection('roads').snapshots().listen((snap) {
      _items = snap.docs.map((d) => RoadItem.fromMap(_withDates(d.data()))).whereType<RoadItem>().toList()
        ..sort(_order);
      _loaded();
    }, onError: failedWith));
    _subs.add(db.collection('road_conditions').snapshots().listen((snap) {
      _conditions = {
        for (final d in snap.docs)
          for (final r in Road.values)
            if (r.conditionsDoc == d.id) r: RoadConditions.fromMap(_withDates(d.data())),
      };
      _loaded();
    }, onError: failedWith));
    _subs.add(db.collection('road_cameras').doc('highway-63').snapshots().listen((snap) {
      final data = snap.data();
      _cameras = data == null ? const [] : RoadCamera.listFromMap(_withDates(data));
      notifyListeners();
    }, onError: (Object e) => debugPrint('Roads: cameras: $e')));
    final ids = [for (final r in Road.values) ...r.sources, ...townSources];
    _subs.add(db.collection('sources').where(FieldPath.documentId, whereIn: ids).snapshots().listen((snap) {
      _lastSuccess = {
        for (final d in snap.docs) d.id: _convert(d.data()['last_success_at']) as DateTime?,
      };
      _loaded();
    }, onError: failedWith));
  }

  final _subs = <StreamSubscription<Object?>>[];
  List<RoadItem> _items = const [];
  Map<Road, RoadConditions> _conditions = const {};
  List<RoadCamera> _cameras = const [];
  Map<String, DateTime?> _lastSuccess = const {};
  bool _loading = true;
  bool _failed = false;

  void _loaded() {
    _loading = false;
    _failed = false;
    notifyListeners();
  }

  @override
  List<RoadItem> get items => _items;
  @override
  RoadConditions? conditions(Road road) => _conditions[road];
  @override
  List<RoadCamera> get cameras => _cameras;
  @override
  Map<String, DateTime?> get lastSuccess => _lastSuccess;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  static Object? _convert(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is Map) return {for (final e in v.entries) e.key as String: _convert(e.value)};
    if (v is List) return [for (final x in v) _convert(x)];
    return v;
  }

  static Map<String, Object?> _withDates(Map<String, dynamic> data) => _convert(data)! as Map<String, Object?>;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Closures first, then incidents, roadwork, the Town's work; earliest start first.
int _order(RoadItem a, RoadItem b) {
  final k = a.kind.index.compareTo(b.kind.index);
  if (k != 0) return k;
  final sa = a.startsAt ?? DateTime(0), sb = b.startsAt ?? DateTime(0);
  return sa.compareTo(sb);
}

/// Sorts like the Firestore repository (for fakes).
List<RoadItem> sortRoadItems(List<RoadItem> items) => [...items]..sort(_order);

/// Used when Firebase couldn't start: the screens say road information
/// can't be loaded, rather than showing nothing (principle 3).
class UnavailableRoadsRepository extends RoadsRepository {
  @override
  List<RoadItem> get items => const [];
  @override
  RoadConditions? conditions(Road road) => null;
  @override
  List<RoadCamera> get cameras => const [];
  @override
  Map<String, DateTime?> get lastSuccess => const {};
  @override
  bool get loading => false;
  @override
  bool get failed => true;
}
