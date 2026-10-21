import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'weather_data.dart';

/// Gives the screens the weather for Témiscaming and tells them when it
/// changes. The real one reads Firestore; tests use a fake.
abstract class WeatherRepository extends ChangeNotifier {
  /// `null` until known, or if the backend has never run.
  Weather? get weather;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when the weather couldn't be loaded at all.
  bool get failed;
}

/// Reads the one document `weather/temiscaming`. Firestore keeps a copy on
/// the phone, so the last weather still shows offline, with its times.
class FirestoreWeatherRepository extends WeatherRepository {
  FirestoreWeatherRepository(FirebaseFirestore db) {
    _subscription = db.collection('weather').doc('temiscaming').snapshots().listen((snap) {
      final data = snap.data();
      _weather = data == null ? null : Weather.fromMap(_withDates(data));
      _loading = false;
      _failed = false;
      notifyListeners();
    }, onError: (Object error) {
      debugPrint('Weather: Firestore error: $error');
      _loading = false;
      _failed = _weather == null;
      notifyListeners();
    });
  }

  late final StreamSubscription<Object?> _subscription;
  Weather? _weather;
  bool _loading = true;
  bool _failed = false;

  @override
  Weather? get weather => _weather;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  /// Firestore timestamps → Dart DateTimes, inside maps and lists too
  /// (the alerts and conditions are nested).
  static Object? _convert(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is Map) return {for (final e in v.entries) e.key as String: _convert(e.value)};
    if (v is List) return [for (final x in v) _convert(x)];
    return v;
  }

  static Map<String, Object?> _withDates(Map<String, dynamic> data) =>
      _convert(data)! as Map<String, Object?>;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Used when Firebase couldn't start: the screens say the weather can't be
/// loaded, rather than showing nothing.
class UnavailableWeatherRepository extends WeatherRepository {
  @override
  Weather? get weather => null;
  @override
  bool get loading => false;
  @override
  bool get failed => true;
}
