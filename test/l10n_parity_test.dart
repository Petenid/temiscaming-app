// "Both languages or not done" (DESIGN.md §8): fails if a string exists in
// one language but not the other, or is left empty.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Message keys only (keys starting with "@" are metadata).
Map<String, dynamic> _messages(Map<String, dynamic> arb) => {
  for (final entry in arb.entries)
    if (!entry.key.startsWith('@')) entry.key: entry.value,
};

void main() {
  final fr = _readArb('lib/l10n/app_fr.arb');
  final en = _readArb('lib/l10n/app_en.arb');

  test('each ARB file declares its own locale', () {
    expect(fr['@@locale'], 'fr');
    expect(en['@@locale'], 'en');
  });

  test('French and English have exactly the same strings', () {
    final frKeys = _messages(fr).keys.toSet();
    final enKeys = _messages(en).keys.toSet();
    expect(
      frKeys.difference(enKeys),
      isEmpty,
      reason: 'Strings in French but missing from English',
    );
    expect(
      enKeys.difference(frKeys),
      isEmpty,
      reason: 'Strings in English but missing from French',
    );
  });

  test('no string is empty in either language', () {
    for (final (name, arb) in [('fr', fr), ('en', en)]) {
      _messages(arb).forEach((key, value) {
        expect(
          value is String && value.trim().isNotEmpty,
          isTrue,
          reason: '"$key" is empty in $name',
        );
      });
    }
  });
}
