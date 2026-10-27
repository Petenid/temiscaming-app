import 'package:flutter/material.dart';

import '../collection/collection_screen.dart';
import '../fire/fire_screen.dart';
import '../l10n/app_localizations.dart';
import '../power/power_screen.dart';
import '../roads/roads_screen.dart';
import '../services.dart';
import '../settings/app_settings.dart';
import '../settings_screen.dart';
import '../weather/weather_screen.dart';

/// The fourth tab (roads spec D13): the screens that don't have a tab of
/// their own. Today's cards still open them directly too.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.settings, required this.services});

  final AppSettings settings;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void open(Widget Function() screen) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen()));
    Widget tile(IconData icon, String title, Widget Function() screen) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => open(screen),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            tile(Icons.directions_car_outlined, l10n.roadsTitle,
                () => RoadsScreen(settings: settings, repository: services.roads, push: services.push)),
            tile(Icons.power_outlined, l10n.powerTitle,
                () => PowerScreen(settings: settings, repository: services.power, push: services.push)),
            tile(Icons.local_fire_department_outlined, l10n.fireTitle,
                () => FireScreen(settings: settings, repository: services.fire)),
            tile(Icons.wb_cloudy_outlined, l10n.weatherTitle,
                () => WeatherScreen(settings: settings, repository: services.weather)),
            tile(Icons.delete_outline, l10n.collectionScheduleTitle,
                () => CollectionScreen(settings: settings, repository: services.collection)),
            const Divider(),
            tile(Icons.settings_outlined, l10n.settingsTitle, () => SettingsScreen(
              settings: settings,
              push: services.push,
              reminders: services.reminders,
              collection: services.collection,
            )),
          ],
        ),
      ),
    );
  }
}
