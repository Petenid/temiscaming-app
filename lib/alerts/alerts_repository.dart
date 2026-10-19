import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'town_alert.dart';

/// Gives the screens the latest town alerts and source health, and tells
/// them when either changes. The real one reads Firestore; tests use a fake.
abstract class AlertsRepository extends ChangeNotifier {
  /// Newest first.
  List<TownAlert> get alerts;

  /// `null` until known, or if the backend has never run.
  SourceHealth? get health;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when the alerts couldn't be loaded at all.
  bool get failed;

  /// One alert by id, e.g. when a notification is tapped. `null` if not found.
  Future<TownAlert?> byId(String id);
}

/// Reads alerts from Firestore. Firestore keeps a copy on the phone, so the
/// last alerts still show offline, with the "last checked" time (DESIGN §7).
class FirestoreAlertsRepository extends AlertsRepository {
  FirestoreAlertsRepository(this._db) {
    _subscriptions = [
      _db
          .collection('alerts')
          .orderBy('published_at', descending: true)
          // Enough for over a year of alerts; keeps reads (and costs) small.
          .limit(_maxAlerts)
          .snapshots()
          .listen((snap) {
            _alerts = [
              for (final doc in snap.docs)
                TownAlert.fromMap(doc.id, _withDates(doc.data())),
            ];
            _loading = false;
            _failed = false;
            notifyListeners();
          }, onError: _onError),
      _db
          .collection('sources')
          .doc('alertes-municipales')
          .snapshots()
          .listen((snap) {
            final data = snap.data();
            _health = data == null ? null : SourceHealth.fromMap(_withDates(data));
            notifyListeners();
          }, onError: _onError),
    ];
  }

  static const _maxAlerts = 60;

  final FirebaseFirestore _db;
  late final List<StreamSubscription<Object?>> _subscriptions;
  List<TownAlert> _alerts = const [];
  SourceHealth? _health;
  bool _loading = true;
  bool _failed = false;

  @override
  List<TownAlert> get alerts => _alerts;
  @override
  SourceHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void _onError(Object error) {
    debugPrint('Alerts: Firestore error: $error');
    _loading = false;
    _failed = _alerts.isEmpty;
    notifyListeners();
  }

  @override
  Future<TownAlert?> byId(String id) async {
    for (final a in _alerts) {
      if (a.id == id) return a;
    }
    try {
      final doc = await _db.collection('alerts').doc(id).get();
      final data = doc.data();
      return data == null ? null : TownAlert.fromMap(doc.id, _withDates(data));
    } catch (error) {
      debugPrint('Alerts: could not load $id: $error');
      return null;
    }
  }

  /// Firestore timestamps → Dart DateTimes (local time).
  static Map<String, Object?> _withDates(Map<String, dynamic> data) => {
    for (final e in data.entries)
      e.key: e.value is Timestamp ? (e.value as Timestamp).toDate() : e.value,
  };

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Used when Firebase couldn't start: the screens say alerts can't be
/// loaded, rather than showing an empty, all-clear list (principle 3).
class UnavailableAlertsRepository extends AlertsRepository {
  @override
  List<TownAlert> get alerts => const [];
  @override
  SourceHealth? get health => null;
  @override
  bool get loading => false;
  @override
  bool get failed => true;
  @override
  Future<TownAlert?> byId(String id) async => null;
}
