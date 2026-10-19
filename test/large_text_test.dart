// Every screen must work at 200% system text size on a small phone
// (DESIGN.md §7). A layout overflow makes the test fail.
import 'package:community/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('all screens fit at 200% text (${language.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final strings = stringsFor(language);

      await pumpApp(tester);
      expect(tester.takeException(), isNull, reason: 'language screen');

      await scrollAndTap(tester, find.text(strings.languageName));
      expect(tester.takeException(), isNull, reason: 'sector screen');

      await scrollAndTap(tester, find.text(strings.sectorTownName));
      expect(tester.takeException(), isNull, reason: 'Today screen');

      await tester.tap(find.byTooltip(strings.settingsTitle));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Settings screen');
    });
  }
}
