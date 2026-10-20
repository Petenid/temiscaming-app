import 'dart:async';

import 'package:community/alerts/alerts_repository.dart';
import 'package:community/alerts/town_alert.dart';
import 'package:community/push/push_service.dart';
import 'package:community/settings/app_settings.dart';
import 'package:community/settings/sector.dart';

/// Alerts held in memory; tests set them and the screens update.
class FakeAlertsRepository extends AlertsRepository {
  FakeAlertsRepository({
    List<TownAlert> alerts = const [],
    SourceHealth? health,
    bool loading = false,
    bool failed = false,
  }) : _alerts = alerts,
       _health = health ?? SourceHealth(lastSuccessAt: DateTime.now(), lastAttemptAt: DateTime.now()),
       _loading = loading,
       _failed = failed;

  List<TownAlert> _alerts;
  SourceHealth? _health;
  bool _loading;
  bool _failed;

  @override
  List<TownAlert> get alerts => _alerts;
  @override
  SourceHealth? get health => _health;
  @override
  bool get loading => _loading;
  @override
  bool get failed => _failed;

  void set({List<TownAlert>? alerts, SourceHealth? health, bool? failed}) {
    _alerts = alerts ?? _alerts;
    _health = health ?? _health;
    _failed = failed ?? _failed;
    _loading = false;
    notifyListeners();
  }

  @override
  Future<TownAlert?> byId(String id) async =>
      _alerts.where((a) => a.id == id).firstOrNull;
}

/// Records what the app asked of the push service.
class FakePushService implements PushService {
  FakePushService({this.isSupported = false, this.grantPermission = true});

  @override
  final bool isSupported;
  bool grantPermission;
  int permissionRequests = 0;
  /// Water-advisory subscriptions asked for: (language, on).
  final applied = <(AppLanguage, bool)>[];

  /// Pickup-change subscriptions asked for: (sector, on).
  final appliedCollection = <(Sector?, bool)>[];
  final _opened = StreamController<String>.broadcast();
  String? initialId;

  /// Simulates the user tapping a notification for [alertId] (or
  /// `collectionTarget` for a pickup notice).
  void tapNotification(String alertId) => _opened.add(alertId);

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grantPermission;
  }

  @override
  Future<void> apply({
    required AppLanguage language,
    required bool enabled,
    Sector? sector,
    bool collectionChanges = false,
  }) async {
    applied.add((language, enabled));
    appliedCollection.add((sector, collectionChanges));
  }

  @override
  Stream<String> get openedAlertIds => _opened.stream;

  @override
  Future<String?> initialAlertId() async => initialId;
}

/// Sample alerts modelled on the Town's real October 2026 boil-water advisory.
class SampleAlerts {
  static DateTime ago(Duration d) => DateTime.now().subtract(d);

  static TownAlert boilWater({
    String id = '8344',
    AlertStatus status = AlertStatus.active,
    Duration age = const Duration(hours: 2),
  }) => TownAlert(
    id: id,
    category: 'boil-water',
    isLiftingNotice: false,
    status: status,
    titleFr: "AVIS D'ÉBULLITION PRÉVENTIF",
    titleEn: 'PRECAUTIONARY BOIL WATER ADVISORY',
    bodyFr: "La Ville de Témiscaming informe la population qu'un avis d'ébullition préventif est en vigueur jusqu'à nouvel avis.",
    bodyEn: 'The Town of Temiscaming informs residents that a precautionary boil water advisory is in effect until further notice.',
    bodyIsExcerpt: false,
    sourceUrlFr: 'https://temiscaming.alertesmunicipales.com/alertes/2026/10/12/avis-d-ebullition-preventif',
    sourceUrlEn: 'https://temiscaming.alertesmunicipales.com/alerts/2026/10/12/precautionary-boil-water-advisory',
    publishedAt: ago(age),
  );

  static TownAlert liftingNotice() => TownAlert(
    id: '8377',
    category: 'other',
    isLiftingNotice: true,
    status: AlertStatus.active,
    titleFr: "LEVÉE DE L'AVIS D'ÉBULLITION PRÉVENTIF.",
    titleEn: 'PRECAUTIONARY BOIL WATER ADVISORY LIFTED.',
    bodyFr: "L'avis d'ébullition préventif est maintenant levé.",
    bodyEn: 'The precautionary boil water advisory has been lifted.',
    bodyIsExcerpt: false,
    sourceUrlFr: 'https://temiscaming.alertesmunicipales.com/alertes/2026/10/19/levee-de-l-avis-d-ebullition-preventif',
    sourceUrlEn: 'https://temiscaming.alertesmunicipales.com/alerts/2026/10/19/precautionary-boil-water-advisory-lifted',
    publishedAt: ago(const Duration(hours: 1)),
  );

  /// The Town posted this one in French only.
  static TownAlert frenchOnly() => TownAlert(
    id: '9001',
    category: 'traffic',
    isLiftingNotice: false,
    status: AlertStatus.expired,
    titleFr: 'FERMETURE DE RUE - AVENUE MURER',
    titleEn: '',
    bodyFr: "L'avenue Murer sera fermée à la circulation.",
    bodyEn: '',
    bodyIsExcerpt: true,
    sourceUrlFr: 'https://temiscaming.alertesmunicipales.com/alertes/2026/09/01/fermeture-de-rue-avenue-murer',
    sourceUrlEn: '',
    publishedAt: ago(const Duration(days: 40)),
  );
}
