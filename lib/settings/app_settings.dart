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
  );

  static const _languageKey = 'language';
  static const _sectorKey = 'sector';
  static const _waterAlertsKey = 'water_alerts';

  final SharedPreferences _prefs;
  AppLanguage? _language;
  Sector? _sector;
  bool? _waterAlerts;

  /// Loads saved choices from the device. Called once at startup.
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(
      prefs,
      AppLanguage.fromId(prefs.getString(_languageKey)),
      Sector.fromId(prefs.getString(_sectorKey)),
      prefs.getBool(_waterAlertsKey),
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
