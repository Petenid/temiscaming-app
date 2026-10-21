import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'town_event.dart';

/// Gives the screens the Town's upcoming events and the calendar's health,
/// and tells them when either changes. The real one reads Firestore; tests
/// use a fake.
abstract class EventsRepository extends ChangeNotifier {
  /// Events the backend keeps: today's and later ones, in no set order
  /// (use `agenda()` to group and sort them).
  List<TownEvent> get events;

  /// `null` until known, or if the backend has never run.
  EventsHealth? get health;

  /// True until the first answer (from the network or the phone's cache).
  bool get loading;

  /// Set when the events couldn't be loaded at all.
  bool get failed;
}

/// Reads events from Firestore. Firestore keeps a copy on the phone, so the
/// last events still show offline, with the "calendar checked" time.
class FirestoreEventsRepository extends EventsRepository {
  FirestoreEventsRepository(this._db) {
    _subscriptions = [
      // The backend deletes past events, so the whole collection is small
      // (a few dozen documents): no query or index needed.
      _db.collection('events').snapshots().listen((snap) {
        _events = [
          for (final doc in snap.docs) ?TownEvent.fromMap(doc.id, _withDates(doc.data())),
        ];
        _loading = false;
        _failed = false;
        notifyListeners();
      }, onError: _onError),
      _db.collection('sources').doc('town-events').snapshots().listen((snap) {
        final data = snap.data();
        _health = data == null ? null : EventsHealth.fromMap(_withDates(data));
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final FirebaseFirestore _db;
  late final List<StreamSubscription<Object?>> _subscriptions;
  List<TownEvent> _events = const [];
  EventsHealth? _health;
  bool _loading = true;
  bool _failed = false;

  @override
  List<TownEvent> get events => _events;
  @override
  EventsHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void _onError(Object error) {
    debugPrint('Events: Firestore error: $error');
    _loading = false;
    _failed = _events.isEmpty;
    notifyListeners();
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

/// Used when Firebase couldn't start: the screens say events can't be
/// loaded, rather than showing an empty list.
class UnavailableEventsRepository extends EventsRepository {
  @override
  List<TownEvent> get events => const [];
  @override
  EventsHealth? get health => null;
  @override
  bool get loading => false;
  @override
  bool get failed => true;
}
