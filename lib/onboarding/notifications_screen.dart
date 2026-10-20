import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../push/push_service.dart';
import '../settings/app_settings.dart';
import '../widgets/centered_scroll_column.dart';

/// Explains what will (and won't) notify, then asks (DESIGN §7). Shown once,
/// on phones only: after first launch, and once to people who installed
/// before notifications existed.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.settings, required this.push});

  final AppSettings settings;
  final PushService push;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final granted = await widget.push.requestPermission();
    // Saving the answer moves the app on to the home screen.
    await widget.settings.setNotificationsAnswer(granted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle), automaticallyImplyLeading: false),
      body: SafeArea(
        child: CenteredScrollColumn(
          children: [
            const Icon(Icons.notifications_active_outlined, size: 48),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(l10n.notificationsPrompt, style: textTheme.headlineSmall),
            ),
            const SizedBox(height: 8),
            Text(l10n.notificationsExplanation, style: textTheme.bodyLarge),
            const SizedBox(height: 16),
            Text(l10n.notificationsReminder, style: textTheme.bodyMedium),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _busy ? null : _allow,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(l10n.notificationsAllow),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : () => widget.settings.setNotificationsAnswer(false),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(l10n.notificationsNotNow),
            ),
          ],
        ),
      ),
    );
  }
}
