import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'settings/app_settings.dart';

/// Where the app starts: connect to Firebase, load the saved settings,
/// then show the app.
Future<void> main() async {
  // Needed before using plugins (like shared_preferences) ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();
  await _startFirebase();
  final settings = await AppSettings.load();
  runApp(TemiscamingApp(settings: settings));
}

/// Connects to the Firebase project. Nothing reads from it yet (Milestone 1
/// will), and the first-launch screens don't need it, so if it fails the
/// problem is logged and the app carries on.
Future<void> _startFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(
      'Firebase initialized (project: ${Firebase.app().options.projectId})',
    );
  } catch (error) {
    debugPrint('Firebase failed to initialize: $error');
  }
}
