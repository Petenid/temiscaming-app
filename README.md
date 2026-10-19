# Témiscaming community app

A free, independent app with local information for residents of Témiscaming, Quebec, in French and English. Not affiliated with the Ville de Témiscaming.

Built with Flutter for iOS, Android, Windows and macOS. Design and decisions: `DESIGN.md` (in the project docs); per-milestone specs in `specs/`.

## Status

Milestone 0 (foundation): first-launch language and collection-sector screens, a placeholder Today screen, and Settings.

## Run it

```
flutter pub get
flutter run -d windows     # or pick an Android emulator: flutter devices
```

## Test it

```
flutter analyze
flutter test --exclude-tags screenshots
```

Every push runs these on GitHub (see the Actions tab), plus an iOS compile check and screenshots of each screen in both languages.

## Where things are

| Path | What it is |
|---|---|
| `lib/main.dart` | Starts the app |
| `lib/app.dart` | Language, theme, first screen |
| `lib/l10n/app_fr.arb`, `app_en.arb` | Every piece of text, in both languages |
| `lib/settings/` | The saved language and sector |
| `lib/onboarding/` | First-launch screens |
| `test/` | Automated tests |
