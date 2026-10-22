import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'fire_data.dart';

/// Gives the screens the fire-ban status for Témiscaming and tells them
/// when it changes. The real one reads Firestore; tests use a fake.
abstract class FireRepository extends ChangeNotifier {
  /// `null` until known, or if the backend has never run.
  FireStatus? get status;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when the status couldn't be loaded at all.
  bool get failed;
}

/// Reads the one document `fire/temiscaming`. Firestore keeps a copy on the
/// phone, so the last status still shows offline, with its "checked" time.
class FirestoreFireRepository extends FireRepository {
  FirestoreFireRepository(FirebaseFirestore db) {
    _subscription = db.collection('fire').doc('temiscaming').snapshots().listen((snap) {
      final data = snap.data();
      _status = data == null ? null : FireStatus.fromMap(_withDates(data));
      _loading = false;
      _failed = false;
      notifyListeners();
    }, onError: (Object error) {
      debugPrint('Fire bans: Firestore error: $error');
      _loading = false;
      _failed = _status == null;
      notifyListeners();
    });
  }

  late final StreamSubscription<Object?> _subscription;
  FireStatus? _status;
  bool _loading = true;
  bool _failed = false;

  @override
  FireStatus? get status => _status;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  /// Firestore timestamps → Dart DateTimes, inside the layer maps too.
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

/// Used when Firebase couldn't start: the screens say the status can't be
/// loaded, rather than showing nothing (principle 3).
class UnavailableFireRepository extends FireRepository {
  @override
  FireStatus? get status => null;
  @override
  bool get loading => false;
  @override
  bool get failed => true;
}
