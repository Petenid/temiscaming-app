import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web page in the phone's or computer's browser.
Future<void> openLink(Uri url) async {
  try {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (error) {
    debugPrint('Could not open $url: $error');
  }
}
