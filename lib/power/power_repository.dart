import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'power_data.dart';

/// Gives the screens Témiscaming's power outages and planned interruptions,
/// and tells them when they change. The real one reads Firestore; tests use a fake.
abstract class PowerRepository extends ChangeNotifier {
  /// `null` until known, or if the backend has never run.
  PowerStatus? get status;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when nothing could be loaded at all.
  bool get failed;
}

/// Reads the one document `power/temiscaming`. Firestore keeps a copy on the
/// phone, so the last information still shows offline, with its "checked" time.
class FirestorePowerRepository extends PowerRepository {
  FirestorePowerRepository(FirebaseFirestore db) {
    _subscription = db.collection('power').doc('temiscaming').snapshots().listen((snap) {
      final data = snap.data();
      _status = data == null ? null : PowerStatus.fromMap(_withDates(data));
      _loading = false;
      _failed = false;
      notifyListeners();
    }, onError: (Object error) {
      debugPrint('Power outages: Firestore error: $error');
      _loading = false;
      _failed = _status == null;
      notifyListeners();
    });
  }

  late final StreamSubscription<Object?> _subscription;
  PowerStatus? _status;
  bool _loading = true;
  bool _failed = false;

  @override
  PowerStatus? get status => _status;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  /// Firestore timestamps → Dart DateTimes, inside the lists too.
  static Object? _convert(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is Map) return {for (final e in v.entries) e.key as String: _convert(e.value)};
    if (v is List) return [for (final x in v) _convert(x)];
    return v;
  }

  static Map<String, Object?> _withDates(Map<String, dynamic> data) => _convert(data)! as Map<String, Object?>;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Used when Firebase couldn't start: the screens say outage information
/// can't be loaded, rather than showing nothing (principle 3).
class UnavailablePowerRepository extends PowerRepository {
  @override
  PowerStatus? get status => null;
  @override
  bool get loading => false;
  @override
  bool get failed => true;
}
