package ca.temiscaming.community

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Android groups notifications into "channels" that people can silence
    // separately in system settings. The backend sends urgent advisories on
    // "water_urgent" and "advisory lifted" notices on "water_updates"; bin
    // reminders (scheduled on the phone) and pickup changes use "collection";
    // fire bans announced or starting use "fire_urgent", lifted "fire_updates";
    // road closures and reopenings (opt-in) use "roads", which pops up.
    // The names come from the app's translation files (lib/l10n/*.arb), sent
    // over from Dart, so they appear in the user's language.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ca.temiscaming.community/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "createChannels") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Channels exist from Android 8 (API 26); older versions have none.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val manager = getSystemService(NotificationManager::class.java)
                    // Re-creating a channel with the same id just updates its name.
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "water_urgent",
                            call.argument<String>("urgentName"),
                            NotificationManager.IMPORTANCE_HIGH,
                        ).apply { description = call.argument<String>("urgentDescription") },
                    )
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "water_updates",
                            call.argument<String>("updatesName"),
                            NotificationManager.IMPORTANCE_DEFAULT,
                        ).apply { description = call.argument<String>("updatesDescription") },
                    )
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "collection",
                            call.argument<String>("collectionName"),
                            NotificationManager.IMPORTANCE_DEFAULT,
                        ).apply { description = call.argument<String>("collectionDescription") },
                    )
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "fire_urgent",
                            call.argument<String>("fireUrgentName"),
                            NotificationManager.IMPORTANCE_HIGH,
                        ).apply { description = call.argument<String>("fireUrgentDescription") },
                    )
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "fire_updates",
                            call.argument<String>("fireUpdatesName"),
                            NotificationManager.IMPORTANCE_DEFAULT,
                        ).apply { description = call.argument<String>("fireUpdatesDescription") },
                    )
                    manager.createNotificationChannel(
                        NotificationChannel(
                            "roads",
                            call.argument<String>("roadsName"),
                            NotificationManager.IMPORTANCE_HIGH,
                        ).apply { description = call.argument<String>("roadsDescription") },
                    )
                }
                result.success(null)
            }
    }
}
