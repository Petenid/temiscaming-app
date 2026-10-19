import 'package:community/settings/app_settings.dart';
import 'package:community/settings/sector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh install: nothing chosen, first launch not done', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.language, isNull);
    expect(settings.sector, isNull);
    expect(settings.isOnboarded, isFalse);
  });

  test('language alone does not finish first launch', () async {
    SharedPreferences.setMockInitialValues({'language': 'fr'});
    final settings = await AppSettings.load();
    expect(settings.language, AppLanguage.fr);
    expect(settings.isOnboarded, isFalse);
  });

  test('choices are saved and survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    await settings.setLanguage(AppLanguage.en);
    await settings.setSector(Sector.lumsden);

    // Simulate a restart: load again from the same saved storage.
    final reloaded = await AppSettings.load();
    expect(reloaded.language, AppLanguage.en);
    expect(reloaded.sector, Sector.lumsden);
    expect(reloaded.isOnboarded, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('language'), 'en');
    expect(prefs.getString('sector'), 'lumsden');
  });

  test('changing a setting notifies listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.setLanguage(AppLanguage.fr);
    await settings.setSector(Sector.town);
    expect(notifications, 2);
  });

  test('an unknown saved value is treated as not chosen', () async {
    SharedPreferences.setMockInitialValues({
      'language': 'de',
      'sector': 'moon',
    });
    final settings = await AppSettings.load();
    expect(settings.language, isNull);
    expect(settings.sector, isNull);
    expect(settings.isOnboarded, isFalse);
  });

  test('sectors keep their collection days', () {
    expect(Sector.town.collectionWeekday, DateTime.tuesday);
    expect(Sector.lumsden.collectionWeekday, DateTime.wednesday);
  });
}
