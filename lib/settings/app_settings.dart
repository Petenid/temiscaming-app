import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sector.dart';

/// The two languages the app supports, saved as "fr" / "en".
enum AppLanguage {
  fr,
  en;

  Locale get locale => Locale(name);

  static AppLanguage? fromId(String? id) => AppLanguage.values.asNameMap()[id];
}

/// The user's choices, kept in memory and saved on the device.
///
/// It's a [ChangeNotifier]: when a setting changes it calls
/// [notifyListeners], and any widget listening (the whole app, here) rebuilds.
/// That's how changing the language in Settings takes effect immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._(
    this._prefs,
    this._language,
    this._sector,
    this._waterAlerts,
    this._binReminder,
    this._reminderMinutes,
    this._collectionChanges,
    this._fireBans,
    this._roadClosures,
    this._powerOutages,
  );

  static const _languageKey = 'language';
  static const _sectorKey = 'sector';
  static const _waterAlertsKey = 'water_alerts';
  static const _binReminderKey = 'bin_reminder';
  static const _reminderTimeKey = 'bin_reminder_time';
  static const _collectionChangesKey = 'collection_changes';
  static const _fireBansKey = 'fire_bans';
  static const _roadClosuresKey = 'road_closures';
  static const _powerOutagesKey = 'power_outages';

  /// The evening-before reminder's default time: 7 p.m. (DESIGN §6.2).
  static const defaultReminderMinutes = 19 * 60;

  final SharedPreferences _prefs;
  AppLanguage? _language;
  Sector? _sector;
  bool? _waterAlerts;
  bool? _binReminder;
  int _reminderMinutes;
  bool? _collectionChanges;
  bool? _fireBans;
  bool _roadClosures;
  bool _powerOutages;

  /// Loads saved choices from the device. Called once at startup.
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final water = prefs.getBool(_waterAlertsKey);
    return AppSettings._(
      prefs,
      AppLanguage.fromId(prefs.getString(_languageKey)),
      Sector.fromId(prefs.getString(_sectorKey)),
      water,
      // People who answered the notifications question before bin reminders
      // existed get them on if they said yes then (and off if they said no).
      prefs.getBool(_binReminderKey) ?? water,
      _parseTime(prefs.getString(_reminderTimeKey)) ?? defaultReminderMinutes,
      prefs.getBool(_collectionChangesKey) ?? water,
      // Not defaulted from the water answer: people who installed before
      // fire bans are asked once, on Today (fire-bans spec D7).
      prefs.getBool(_fireBansKey),
      // Opt-in only, off for everyone until turned on (roads spec D9).
      prefs.getBool(_roadClosuresKey) ?? false,
      // Opt-in only too (power-outages spec D7).
      prefs.getBool(_powerOutagesKey) ?? false,
    );
  }

  /// `null` until the user has picked a language.
  AppLanguage? get language => _language;

  /// `null` until the user has picked a sector.
  Sector? get sector => _sector;

  /// First launch is over once both choices are saved.
  bool get isOnboarded => _language != null && _sector != null;

  /// Whether the user has answered the notifications question (once, after
  /// first launch; existing users see it once after updating).
  bool get notificationsAsked => _waterAlerts != null;

  /// Push notifications for water advisories (spec §6, Settings).
  bool get waterAlertsEnabled => _waterAlerts ?? false;

  /// The evening-before bin reminder (spec D8).
  bool get binReminderEnabled => _binReminder ?? false;

  /// Reminder time as minutes after midnight (19:00 = 1140).
  int get reminderMinutes => _reminderMinutes;

  /// Notices when the Town moves, cancels or adds a pickup (spec D8).
  bool get collectionChangesEnabled => _collectionChanges ?? false;

  /// Notifications when a fire ban starts or lifts for Témiscaming (fire-bans spec D7).
  bool get fireBansEnabled => _fireBans ?? false;

  /// True for people who answered the notifications question before fire
  /// bans existed and haven't been asked about them yet: Today offers them
  /// once (spec D7).
  /// Notifications when Route 101 or Highway 63 closes or reopens. Opt-in:
  /// the notifications question never turns it on (roads spec D9).
  bool get roadClosuresEnabled => _roadClosures;

  /// Notifications when the power goes out in Témiscaming (25+ customers) and
  /// when it's back. Opt-in, like road closures (power-outages spec D7).
  bool get powerOutagesEnabled => _powerOutages;

  bool get fireBansToOffer => notificationsAsked && _fireBans == null;

  /// The answer to the notifications question: turns every kind of
  /// notification on (permission granted) or off.
  Future<void> setNotificationsAnswer(bool granted) async {
    _waterAlerts = granted;
    _binReminder = granted;
    _collectionChanges = granted;
    _fireBans = granted;
    notifyListeners();
    await _prefs.setBool(_waterAlertsKey, granted);
    await _prefs.setBool(_binReminderKey, granted);
    await _prefs.setBool(_collectionChangesKey, granted);
    await _prefs.setBool(_fireBansKey, granted);
  }

  Future<void> setRoadClosures(bool enabled) async {
    _roadClosures = enabled;
    notifyListeners();
    await _prefs.setBool(_roadClosuresKey, enabled);
  }

  Future<void> setPowerOutages(bool enabled) async {
    _powerOutages = enabled;
    notifyListeners();
    await _prefs.setBool(_powerOutagesKey, enabled);
  }

  Future<void> setFireBans(bool enabled) async {
    _fireBans = enabled;
    notifyListeners();
    await _prefs.setBool(_fireBansKey, enabled);
  }

  Future<void> setBinReminder(bool enabled) async {
    _binReminder = enabled;
    notifyListeners();
    await _prefs.setBool(_binReminderKey, enabled);
  }

  Future<void> setReminderMinutes(int minutes) async {
    _reminderMinutes = minutes;
    notifyListeners();
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    await _prefs.setString(_reminderTimeKey, '$h:$m');
  }

  Future<void> setCollectionChanges(bool enabled) async {
    _collectionChanges = enabled;
    notifyListeners();
    await _prefs.setBool(_collectionChangesKey, enabled);
  }

  /// "19:00" → 1140; null if missing or malformed.
  static int? _parseTime(String? s) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s ?? '');
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    return h < 24 && min < 60 ? h * 60 + min : null;
  }

  Future<void> setLanguage(AppLanguage language) async {
    _language = language;
    notifyListeners();
    await _prefs.setString(_languageKey, language.name);
  }

  Future<void> setWaterAlerts(bool enabled) async {
    _waterAlerts = enabled;
    notifyListeners();
    await _prefs.setBool(_waterAlertsKey, enabled);
  }

  Future<void> setSector(Sector sector) async {
    _sector = sector;
    notifyListeners();
    await _prefs.setString(_sectorKey, sector.name);
  }
}
