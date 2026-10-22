import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/alerts_repository.dart';
import 'app.dart';
import 'collection/collection_repository.dart';
import 'collection/local_reminder_service.dart';
import 'collection/reminders.dart';
import 'events/calendar_adder.dart';
import 'events/events_repository.dart';
import 'fire/fire_repository.dart';
import 'firebase_options.dart';
import 'push/push_service.dart';
import 'services.dart';
import 'settings/app_settings.dart';
import 'weather/weather_repository.dart';

/// Where the app starts: connect to Firebase, load the saved settings,
/// then show the app.
Future<void> main() async {
  // Needed before using plugins (like shared_preferences) ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await _startFirebase();
  final settings = await AppSettings.load();
  final prefs = await SharedPreferences.getInstance();
  final services = AppServices(
    // Without Firebase the alert screens say they can't load, rather than
    // showing an empty list that looks like "no alerts" (principle 3).
    alerts: firebaseReady
        ? FirestoreAlertsRepository(FirebaseFirestore.instance)
        : UnavailableAlertsRepository(),
    // The pickup schedule also keeps its own copy on the phone, for offline
    // use and reminders (spec D1).
    collection: firebaseReady
        ? FirestoreCollectionRepository(FirebaseFirestore.instance, prefs)
        : OfflineCollectionRepository(prefs),
    push: FcmPushService(),
    reminders: LocalReminderService(),
    events: firebaseReady
        ? FirestoreEventsRepository(FirebaseFirestore.instance)
        : UnavailableEventsRepository(),
    calendar: DeviceCalendarAdder(),
    weather: firebaseReady
        ? FirestoreWeatherRepository(FirebaseFirestore.instance)
        : UnavailableWeatherRepository(),
    fire: firebaseReady
        ? FirestoreFireRepository(FirebaseFirestore.instance)
        : UnavailableFireRepository(),
  );
  // Keeps the push subscription matching the language and settings.
  if (firebaseReady) PushSync(settings, services.push);
  // Bin reminders are scheduled on the phone, so they don't need Firebase.
  ReminderSync(settings, services.collection, services.reminders);
  runApp(TemiscamingApp(settings: settings, services: services));
}

/// Connects to the Firebase project. If it fails, the problem is logged and
/// the app carries on: first-launch screens and settings don't need it.
Future<bool> _startFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(
      'Firebase initialized (project: ${Firebase.app().options.projectId})',
    );
    return true;
  } catch (error) {
    debugPrint('Firebase failed to initialize: $error');
    return false;
  }
}
