import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pickup.dart';
import 'schedule.dart';

/// Gives the screens (and, from step 5b, the reminders) the upcoming pickups
/// and the calendar's source health. The real one reads Firestore; tests use
/// a fake.
abstract class CollectionRepository extends ChangeNotifier {
  /// Pickups for both sectors, from a week ago onwards, oldest first.
  List<Pickup> get pickups;

  /// `null` until known.
  CollectionHealth? get health;

  /// True until the first answer.
  bool get loading;

  /// Set when nothing could be loaded at all (not even the copy on the phone).
  bool get failed;
}

/// Key of the schedule copy saved on the phone (spec §5).
const collectionCacheKey = 'collection_cache';

/// Reads pickups from Firestore and keeps its own copy on the phone
/// (spec D1): reminders must work from that copy even when the backend, the
/// Town's site or the network is down.
class FirestoreCollectionRepository extends CollectionRepository {
  FirestoreCollectionRepository(this._db, this._prefs) {
    _readCopy(_prefs, (pickups, health) {
      _pickups = pickups;
      _health = health;
      if (pickups.isNotEmpty) _loading = false;
    });
    final since = dayKey(addDays(DateTime.now(), -7));
    _subscriptions = [
      _db
          .collection('collections')
          .where('date', isGreaterThanOrEqualTo: since)
          .snapshots()
          .listen((snap) {
            _pickups = [
              for (final doc in snap.docs) ?Pickup.fromMap(doc.id, doc.data()),
            ]..sort((a, b) => a.date.compareTo(b.date));
            _loading = false;
            _failed = false;
            _saveCopy();
            notifyListeners();
          }, onError: _onError),
      _db.collection('sources').doc('town-calendar').snapshots().listen((snap) {
        final data = snap.data();
        if (data == null) return;
        _health = CollectionHealth.fromMap({
          for (final e in data.entries)
            e.key: e.value is Timestamp ? (e.value as Timestamp).toDate() : e.value,
        });
        _saveCopy();
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final FirebaseFirestore _db;
  final SharedPreferences _prefs;
  late final List<StreamSubscription<Object?>> _subscriptions;
  List<Pickup> _pickups = const [];
  CollectionHealth? _health;
  bool _loading = true;
  bool _failed = false;

  @override
  List<Pickup> get pickups => _pickups;
  @override
  CollectionHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void _onError(Object error) {
    debugPrint('Collection: Firestore error: $error');
    _loading = false;
    _failed = _pickups.isEmpty;
    notifyListeners();
  }

  void _saveCopy() => unawaited(_writeCopy(_prefs, _pickups, _health));

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Used when Firebase couldn't start: the copy saved on the phone, if any,
/// with its age shown; otherwise the screens say the schedule can't load.
class OfflineCollectionRepository extends CollectionRepository {
  OfflineCollectionRepository(SharedPreferences prefs) {
    _readCopy(prefs, (pickups, health) {
      _pickups = pickups;
      _health = health;
    });
  }

  List<Pickup> _pickups = const [];
  CollectionHealth? _health;

  @override
  List<Pickup> get pickups => _pickups;
  @override
  CollectionHealth? get health => _health;
  @override
  bool get loading => false;
  @override
  bool get failed => _pickups.isEmpty;
}

void _readCopy(
  SharedPreferences prefs,
  void Function(List<Pickup>, CollectionHealth?) use,
) {
  final raw = prefs.getString(collectionCacheKey);
  if (raw == null) return;
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final pickups = <Pickup>[
      for (final e in (json['pickups'] as Map<String, dynamic>).entries)
        ?Pickup.fromMap(e.key, Map<String, Object?>.from(e.value as Map)),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final health = json['health'] == null
        ? null
        : CollectionHealth.fromMap(Map<String, Object?>.from(json['health'] as Map));
    use(pickups, health);
  } catch (error) {
    // A copy from an older app version, or damaged: ignore it.
    debugPrint('Collection: ignoring saved copy: $error');
  }
}

Future<void> _writeCopy(SharedPreferences prefs, List<Pickup> pickups, CollectionHealth? health) =>
    prefs.setString(
      collectionCacheKey,
      jsonEncode({
        'pickups': {for (final p in pickups) p.id: p.toMap()},
        'health': health?.toMap(),
      }),
    );
