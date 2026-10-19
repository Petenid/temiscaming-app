import 'package:flutter/widgets.dart';

import 'app.dart';
import 'settings/app_settings.dart';

/// Where the app starts: load the saved settings, then show the app.
Future<void> main() async {
  // Needed before using plugins (like shared_preferences) ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(TemiscamingApp(settings: settings));
}
