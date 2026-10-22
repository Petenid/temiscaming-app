/// Quebec's two forest-fire measures the app follows (fire-bans spec D1).
enum FireLayer {
  /// Open-fire ban: "Interdiction de faire des feux à ciel ouvert" (IFCO).
  ifco,

  /// Ban on travelling in or entering the forest (ICAF).
  icaf,
}

/// What a layer means for Témiscaming (spec D2), as the backend works it out.
enum FireLayerState {
  /// IFCO: the ban's area contains the town centre or Lumsden.
  town,

  /// ICAF: the ban's area comes within 15 km of town.
  around,

  /// A ban farther away, still in the region (up to 150 km): no banner.
  region,

  /// Nothing in effect near Témiscaming.
  none,
}

/// One layer of Firestore `fire/temiscaming` (spec §5).
class FireLayerStatus {
  const FireLayerStatus({
    required this.layer,
    required this.state,
    required this.checkedAt,
    this.startsAt,
    this.noneSince,
    this.nearestKm,
  });

  final FireLayer layer;
  final FireLayerState state;

  /// When the ministry's data was last read successfully: this layer's health.
  final DateTime checkedAt;

  /// When the ban that applies here starts; in the future if only announced.
  final DateTime? startsAt;

  /// When the last ban anywhere in Quebec was lifted (only when none is in effect anywhere).
  final DateTime? noneSince;

  /// How far the nearest ban is from town, in km.
  final int? nearestKm;

  /// Checked every 30 minutes: red after 4 missed runs (spec D4).
  static const staleAfter = Duration(hours: 2);

  bool isStale(DateTime now) => now.difference(checkedAt) > staleAfter;

  /// A ban for Témiscaming (IFCO) or around it (ICAF): banner and push.
  bool get isHere => state == (layer == FireLayer.ifco ? FireLayerState.town : FireLayerState.around);

  /// Announced, not yet in effect.
  bool isUpcoming(DateTime now) => isHere && startsAt != null && startsAt!.isAfter(now);

  static FireLayerStatus? fromMap(FireLayer layer, Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final checked = m['checked_at'];
    if (checked is! DateTime) return null;
    final state = FireLayerState.values.where((s) => s.name == m['state']).firstOrNull;
    // An unknown state can't be shown as "none": treat it as here, so the
    // person looks at the official page rather than trusting silence.
    return FireLayerStatus(
      layer: layer,
      state: state ?? (layer == FireLayer.ifco ? FireLayerState.town : FireLayerState.around),
      checkedAt: checked,
      startsAt: m['starts_at'] as DateTime?,
      noneSince: m['none_since'] as DateTime?,
      nearestKm: (m['nearest_km'] as num?)?.round(),
    );
  }
}

/// Official pages (spec D9). The backend stores them too, so they can be
/// changed without an app update; these are used when it hasn't.
class FireLinks {
  static const officialFr =
      'https://www.quebec.ca/agriculture-environnement-et-ressources-naturelles/forets/protection-forets/gestion-feux/mesures-prevention';
  static const map = 'https://www.carte-igo.donneesquebec.ca/igo2/apercu-qc/?pos=@-79.1,46.9,8&ctx=msp_feu_mesure_preventive';
  static const sopfeuFr = 'https://www.sopfeu.qc.ca/etat-situation/abitibi-temiscamingue/';
  static const sopfeuEn = 'https://www.sopfeu.qc.ca/en/current-situation/abitibi-temiscamingue/';
}

/// Firestore `fire/temiscaming`.
class FireStatus {
  const FireStatus({
    this.ifco,
    this.icaf,
    this.officialUrlFr = FireLinks.officialFr,
    this.mapUrl = FireLinks.map,
    this.sopfeuUrlFr = FireLinks.sopfeuFr,
    this.sopfeuUrlEn = FireLinks.sopfeuEn,
  });

  /// Null until the backend has read that layer once.
  final FireLayerStatus? ifco;
  final FireLayerStatus? icaf;
  final String officialUrlFr;
  final String mapUrl;
  final String sopfeuUrlFr;
  final String sopfeuUrlEn;

  FireLayerStatus? layer(FireLayer l) => l == FireLayer.ifco ? ifco : icaf;

  /// Layers with a ban here, open-fire ban first.
  List<FireLayerStatus> get here => [
    for (final l in [ifco, icaf])
      if (l != null && l.isHere) l,
  ];

  /// Something worth a look on the Fire screen even outside the season.
  bool get anyBan => [ifco, icaf].any((l) => l != null && l.state != FireLayerState.none);

  factory FireStatus.fromMap(Map<String, Object?> m) {
    String link(String k, String fallback) {
      final v = m[k];
      return v is String && v.startsWith('https://') ? v : fallback;
    }

    return FireStatus(
      ifco: FireLayerStatus.fromMap(FireLayer.ifco, m['ifco']),
      icaf: FireLayerStatus.fromMap(FireLayer.icaf, m['icaf']),
      officialUrlFr: link('official_url_fr', FireLinks.officialFr),
      mapUrl: link('map_url', FireLinks.map),
      sopfeuUrlFr: link('sopfeu_url_fr', FireLinks.sopfeuFr),
      sopfeuUrlEn: link('sopfeu_url_en', FireLinks.sopfeuEn),
    );
  }
}

/// SOPFEU's season, when burning permits are required: 1 April to
/// 15 November (spec D8). Outside it the Today card hides unless there's a
/// ban or a problem.
bool isFireSeason(DateTime now) {
  final d = now.toLocal();
  final md = d.month * 100 + d.day;
  return md >= 401 && md <= 1115;
}
