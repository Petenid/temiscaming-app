import 'dart:convert';

import 'package:community/roads/road_data.dart';
import 'package:community/roads/roads_repository.dart';
import 'package:flutter/painting.dart';

/// A 1×1 grey PNG, standing in for camera images (no network in tests).
final testCameraImage = MemoryImage(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mN8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
));

/// Road information held in memory; tests set it and the screens update.
/// By default: everything checked 5 minutes ago, nothing reported, bare
/// and dry roads — the real state on 22–23 October 2026.
class FakeRoadsRepository extends RoadsRepository {
  FakeRoadsRepository({
    List<RoadItem> items = const [],
    Map<Road, RoadConditions>? conditions,
    List<RoadCamera> cameras = const [],
    Map<String, DateTime?>? lastSuccess,
    bool loading = false,
    bool failed = false,
  }) : _items = sortRoadItems(items),
       _conditions = conditions ?? SampleRoads.bareAndDry(),
       _cameras = cameras,
       _lastSuccess = lastSuccess ?? SampleRoads.checked(),
       _loading = loading,
       _failed = failed;

  List<RoadItem> _items;
  Map<Road, RoadConditions> _conditions;
  List<RoadCamera> _cameras;
  Map<String, DateTime?> _lastSuccess;
  final bool _loading;
  final bool _failed;

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

  void set({
    List<RoadItem>? items,
    Map<Road, RoadConditions>? conditions,
    List<RoadCamera>? cameras,
    Map<String, DateTime?>? lastSuccess,
  }) {
    if (items != null) _items = sortRoadItems(items);
    if (conditions != null) _conditions = conditions;
    if (cameras != null) _cameras = cameras;
    if (lastSuccess != null) _lastSuccess = lastSuccess;
    notifyListeners();
  }
}

/// Samples modelled on the real captures (functions/test/fixtures/roads/)
/// and the hand-made ones in functions/test/fixtures/roads/hand-made/.
class SampleRoads {
  static DateTime ago(Duration d) => DateTime.now().subtract(d);

  static const allSources = [
    'mtmd-warnings', 'mtmd-roadworks', 'mtmd-conditions',
    'on511-events', 'on511-construction', 'on511-conditions', 'town-work-info',
  ];

  /// Every source read [age] ago.
  static Map<String, DateTime?> checked({Duration age = const Duration(minutes: 5)}) => {
    for (final s in allSources) s: ago(age),
  };

  static RoadSegment segment({
    required String from,
    required String to,
    String surfaceFr = 'Dégagée et sèche',
    String surfaceEn = 'Bare and Dry',
    bool surfaceOk = true,
    String visibilityFr = 'Bonne',
    String visibilityEn = 'Good',
    bool visibilityOk = true,
    bool? drifting = false,
    bool noReport = false,
  }) => RoadSegment(
    fromFr: from, fromEn: from, toFr: to, toEn: to,
    surfaceFr: surfaceFr, surfaceEn: surfaceEn, surfaceOk: surfaceOk,
    visibilityFr: visibilityFr, visibilityEn: visibilityEn, visibilityOk: visibilityOk,
    drifting: drifting, noReport: noReport, since: ago(const Duration(hours: 3)),
  );

  /// 22–23 October 2026: everything bare and dry.
  static Map<Road, RoadConditions> bareAndDry({bool inSeason = true}) => {
    Road.route101: RoadConditions(
      segments: inSeason
          ? [
              segment(from: 'Témiscaming', to: 'Saint-Édouard-de-Fabre'),
              segment(from: 'Saint-Édouard-de-Fabre', to: 'Ville-Marie'),
            ]
          : const [],
      inSeason: inSeason,
      checkedAt: ago(const Duration(minutes: 5)),
    ),
    Road.highway63: RoadConditions(
      segments: [
        segment(from: 'North Bay', to: 'Thorne', surfaceEn: 'Bare and dry road'),
      ],
      inSeason: null,
      checkedAt: ago(const Duration(minutes: 5)),
    ),
  };

  /// Hand-made: icy on the first Route 101 segment, snow packed with drifting on 63.
  static Map<Road, RoadConditions> winterStorm() => {
    Road.route101: RoadConditions(
      segments: [
        segment(
          from: 'Témiscaming', to: 'Saint-Édouard-de-Fabre',
          surfaceFr: 'Glacée', surfaceEn: 'Ice Covered', surfaceOk: false,
          visibilityFr: 'Réduite', visibilityEn: 'Poor', visibilityOk: false, drifting: true,
        ),
        segment(from: 'Saint-Édouard-de-Fabre', to: 'Ville-Marie'),
      ],
      inSeason: true,
      checkedAt: ago(const Duration(minutes: 5)),
    ),
    Road.highway63: RoadConditions(
      segments: [
        segment(
          from: 'North Bay', to: 'Thorne',
          surfaceFr: 'Neige durcie', surfaceEn: 'Snow packed', surfaceOk: false, drifting: true,
        ),
      ],
      inSeason: null,
      checkedAt: ago(const Duration(minutes: 5)),
    ),
  };

  /// Hand-made: Route 101 closed at Saint-Édouard-de-Fabre since 40 minutes ago (French only).
  static RoadItem closure101() => RoadItem(
    id: 'qc-warning-900001',
    kind: RoadItemKind.closure,
    road: Road.route101,
    place: 'Saint-Édouard-de-Fabre',
    titleFr: 'Route fermée',
    titleEn: 'Road closed',
    bodyFr: 'R-101 à la hauteur de Saint-Édouard-de-Fabre\n\nDétails à venir.\nCause : Accident\nDurée : Indéterminée\nDétour : Aucun détour possible',
    bodyEn: '',
    originalLanguage: 'fr',
    sourceUrlFr: RoadLinks.quebec511Fr,
    sourceUrlEn: RoadLinks.quebec511En,
    startsAt: ago(const Duration(minutes: 40)),
    endsAt: null,
    onToday: true,
  );

  /// Hand-made: Highway 63 fully closed near Highway 533 (both languages).
  static RoadItem closure63() => RoadItem(
    id: 'on-event-900100',
    kind: RoadItemKind.closure,
    road: Road.highway63,
    place: '',
    titleFr: 'Route fermée',
    titleEn: 'Road closed',
    bodyFr: 'Collision sur RTE 63 dans les deux directions entre RTE 533 et chemin Wyse. TOUTES LES VOIES FERMÉES.',
    bodyEn: 'Collision on HWY 63 both directions between HWY 533 and Wyse Rd. ALL LANES CLOSED.',
    originalLanguage: 'both',
    sourceUrlFr: RoadLinks.ontario511Fr,
    sourceUrlEn: RoadLinks.ontario511En,
    startsAt: ago(const Duration(hours: 1)),
    endsAt: null,
    onToday: true,
  );

  /// Hand-made: a night closure for roadwork on Route 101, planned for next week.
  static RoadItem plannedClosure() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 7, 19);
    return RoadItem(
      id: 'qc-roadwork-900010',
      kind: RoadItemKind.closure,
      road: Road.route101,
      place: '',
      titleFr: 'Route fermée (travaux)',
      titleEn: 'Road closed (roadwork)',
      bodyFr: 'À Saint-Édouard-de-Fabre, R-101\nFermeture complète\nNuit seulement, de 19 h à 6 h',
      bodyEn: 'In Saint-Édouard-de-Fabre, R-101\nComplete closure\nNights only, 7 p.m. to 6 a.m.',
      originalLanguage: 'both',
      sourceUrlFr: RoadLinks.quebec511Fr,
      sourceUrlEn: RoadLinks.quebec511En,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 35)),
      onToday: true,
    );
  }

  /// Like the real 21–23 October roadwork (moved onto our stretch): alternating traffic.
  static RoadItem roadwork101() => RoadItem(
    id: 'qc-roadwork-174048',
    kind: RoadItemKind.roadwork,
    road: Road.route101,
    place: '',
    titleFr: 'Travaux routiers',
    titleEn: 'Roadwork',
    bodyFr: 'À Duhamel-Ouest et Saint-Bruno-de-Guigues entre la rue Dubrûle et route à Cotnoir\nDans les deux directions\nCirculation en alternance\nMardi à vendredi entre 7 h et 19 h',
    bodyEn: 'In Duhamel-Ouest and Saint-Bruno-de-Guigues, between Dubrûle Street and Cotnoir Road\nIn both directions\nAlternating traffic\nTuesday to Friday between 7 a.m. and 7 p.m.',
    originalLanguage: 'both',
    sourceUrlFr: RoadLinks.quebec511Fr,
    sourceUrlEn: RoadLinks.quebec511En,
    startsAt: ago(const Duration(days: 1)),
    endsAt: ago(const Duration(days: -2)),
    onToday: false,
  );

  /// The real Town item on 22 October: water-system flushing, all October.
  static RoadItem townFlushing() {
    final now = DateTime.now();
    return RoadItem(
      id: 'town-1019',
      kind: RoadItemKind.town,
      road: null,
      place: 'Témiscaming',
      titleFr: "RINÇAGE DU RÉSEAU D'AQUEDUC | MOIS D'OCTOBRE",
      titleEn: 'WATER SYSTEM FLUSHING | MONTH OF OCTOBER',
      bodyFr: "Au cours du mois d'octobre, l'équipe des travaux publics procédera au rinçage du réseau d'aqueduc et des bornes-fontaines sur le territoire de la Ville.",
      bodyEn: 'Throughout the month of October, the Public Works Department will be conducting the flushing of the water distribution system and fire hydrants throughout the Town.',
      originalLanguage: 'both',
      sourceUrlFr: 'https://www.temiscaming.net/fr/info-travaux/1019/rincage-du-reseau-d-aqueduc-mois-d-octobre-',
      sourceUrlEn: 'https://www.temiscaming.net/en/work-info/1019/water-system-flushing-month-of-october',
      startsAt: DateTime(now.year, now.month, now.day - 10),
      endsAt: DateTime(now.year, now.month, now.day + 10),
      onToday: false,
    );
  }

  /// The real Highway 63 cameras (2026-10-23).
  static List<RoadCamera> cameras() => const [
    RoadCamera(location: 'Highway 63 at Highway 533', views: [
      CameraView(imageUrl: 'https://511on.ca/map/Cctv/519', directionFr: "Vers l'est", directionEn: 'Looking East'),
    ]),
    RoadCamera(location: 'Highway 63 at Wyse Road', views: [
      CameraView(imageUrl: 'https://511on.ca/map/Cctv/2720', directionFr: 'Vers le nord', directionEn: 'Looking North'),
      CameraView(imageUrl: 'https://511on.ca/map/Cctv/2721', directionFr: 'Vers le sud', directionEn: 'Looking South'),
    ]),
  ];
}
