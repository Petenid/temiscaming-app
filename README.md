# Allô Témis — Témiscaming community app

A free, independent app with local information for residents of Témiscaming, Quebec, in French and English. Not affiliated with the Ville de Témiscaming. "Allô Témis" is the working name; the app itself still shows "Témiscaming" and uses the placeholder ID `ca.temiscaming.community` until a final name is settled.

Built with Flutter for iOS, Android, Windows and macOS. Design and decisions: `DESIGN.md` (in the project docs); per-milestone specs in `specs/`.

## Status

- **Milestone 0 — Foundation: complete (2026-10-19).** First-launch language and collection-sector screens, a placeholder Today screen, Settings, Firebase connected, CI. Verified on CI (analyze, 18 tests, iOS build), the Windows app and the Android emulator.
- **Milestone 1 — Town alerts + urgent water push: complete (2026-10-19).** Spec: `specs/town-alerts.md`. Backend in `functions/` reads the Town's alert site every 10 minutes; the app has an Alerts tab, a boil-water banner on Today, and push notifications in the user's language. Verified on the Android emulator (English push tested in code only).
- **Milestone 2 — Collection day + local reminders + change notices: complete (2026-10-20).** Spec: `specs/collection-day.md`.
- **Milestone 3 — Events calendar: complete (2026-10-20).** Spec: `specs/events-calendar.md`. Events tab, event detail with "Add to my calendar" (phones), and a "Coming up" card on Today, read from the same Town calendar pages as the bins. Verified on the Android emulator.
- **Milestone 4 — Weather: complete (2026-10-21).** Spec: `specs/weather.md`. Environment Canada's readings at the Barrage Témiscaming station and its weather alerts for the town, plus a 7-day Open-Meteo forecast for Témiscaming's own coordinates; a weather card and amber alert banner on Today, and a Weather screen. Nothing pushes.
- **Milestone 6 — Fire bans: complete (2026-10-22).** Spec: `specs/fire-bans.md`. Quebec's open-fire ban and forest access ban, checked every 30 minutes: a red banner on Today when one is announced or in effect for Témiscaming, a fire card during fire season (1 April – 15 November) with a link to SOPFEU's fire danger, a Fire screen, and a "Fire bans" notification when a ban starts or lifts.
- **Milestone 7 — Roads: complete (2026-10-27).** Spec: `specs/roads.md`. Route 101 (Témiscaming – Ville-Marie) and Highway 63 (Thorne – North Bay): closures, incidents, roadwork, road conditions and Highway 63's cameras, plus the Town's Work Info, on a Roads screen in a new **More** tab; an amber card on Today only when something's wrong; an opt-in "Road closures" notification (off by default). Verified on the Android emulator against Québec 511 and Ontario 511.

Full plan and milestones: `DESIGN.md` in the project docs.

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

Every push runs these on GitHub (see the Actions tab), plus an iOS compile check. Each push to `main` also refreshes screenshots of every screen in both languages on the `screenshots` branch (switch branch on GitHub to view them).

## Setting up a Windows PC (notes from the first setup)

- **Tools:** Flutter, Git, VS Code with the Flutter extension, Visual Studio 2022+ with "Desktop development with C++", Android Studio (for the Android SDK and emulator), Node.js LTS (for the Firebase CLI).
- **Android NDK:** if a build fails with "sdkmanager did not install NDK x.y.z", install that exact version in Android Studio → SDK Manager → SDK Tools → tick *Show Package Details* → NDK (Side by side).
- **"running scripts is disabled":** `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`
- **`flutterfire` not found:** add `%LOCALAPPDATA%\Pub\Cache\bin` to your PATH, or run `dart pub global run flutterfire_cli:flutterfire …`
- **Emulator from the terminal:** `flutter emulators --launch <id>`, then `flutter run -d emulator-5554`
- **Emulator won't start after being shut off abruptly** ("exited with code 1 during startup", empty stderr): stop leftovers with `Get-Process qemu*, emulator* -ErrorAction SilentlyContinue | Stop-Process -Force`, delete the stale locks with `Get-ChildItem "$env:USERPROFILE\.android\avd\*.avd" -Filter *.lock -Force | Remove-Item -Recurse -Force`, then cold-boot it: `& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd <name> -no-snapshot-load` (names from `-list-avds`). Started this way it prints its real error if it still fails.
- **Applying a patch from Claude:** always give the file name, `git am <file>.patch`. Plain `git am` waits for typed input ("reading patches from stdin") forever: stop it with Ctrl+C, then `git am --quit` (not `--abort`, which can undo a patch already applied). After a patch that changes `pubspec.yaml`, run `flutter pub get` and commit the updated `pubspec.lock`.
- **Deploy fails with "User code failed to load … Timeout after 10000":** run `$env:FUNCTIONS_DISCOVERY_TIMEOUT=60` in that terminal, then deploy again. Windows Defender scanning `node_modules` slows the local load; the code itself loads in under a second.

## Firebase

Project `temiscaming-app` on the **Blaze** (pay-as-you-go) plan, needed for Cloud Functions; a budget alert emails the owner if spending ever passes $1. Firestore in `northamerica-northeast1` (Montréal), Google Analytics off. `lib/firebase_options.dart` and `android/app/google-services.json` are generated by `flutterfire configure`; their keys identify the project and are safe to publish. Access is controlled by `firestore.rules`: anyone may read `alerts`, `collections`, `events`, `weather`, `fire`, `roads`, `road_conditions`, `road_cameras` and `sources`; `roads_state` (what people were last told about closures) is backend-only; `overrides` (manual corrections, edited in the console) is closed to the app; nothing is writable from the app.

### Backend (`functions/`)

TypeScript Cloud Functions. `pollTownAlerts` runs every 10 minutes: it reads `temiscaming.alertesmunicipales.com` (French and English lists), saves alerts to Firestore `alerts/`, records source health in `sources/alertes-municipales`, and pushes new water advisories to the FCM topics `water-fr` / `water-en`.

```
cd functions
npm install
npm test            # parser and sync tests against saved pages in test/fixtures/
```

Deploy (from the project folder, in VS Code's terminal):

```
firebase deploy --only firestore:rules,functions
```

Logs: Firebase console → Functions → `pollTownAlerts` → Logs. A healthy run ends with `town alerts: ok — 94 alerts …`.

**Fixing an alert by hand** (when an alert says "In effect" but isn't, or the reverse):
1. Firebase console → Firestore Database → `alerts`. Find the alert by its title and copy its document ID (e.g. `8274`).
2. Go back to the top, open the `overrides` collection (first time: *Start collection*, ID `overrides`) → *Add document*. Document ID: the alert's ID. Add a field `status` (string) = `over` (not in effect) or `in-effect` (still in effect). Optionally a field `note` (string) to remind yourself why.
3. Within 10 minutes the alert's `override` field changes and the app follows. To undo, delete the document.
Only mark a boil-water advisory `over` once the Town has confirmed it: the override also removes the red banner on Today. A typo in `status` or an unknown ID is ignored and shows in the `pollTownAlerts` logs as `override … ignored`.

**Bin reminders** are scheduled on the phone itself (flutter_local_notifications), from the schedule copy saved on the phone, so they work offline. To check one arrives: in a debug build, Settings → *Test reminder in 2 minutes*, then turn on airplane mode and wait.

The Town's calendar is read by `pollTownCalendar` every 2 hours: first the bin pickups, then **events from the same pages** (no extra requests to the Town; each step has its own source health, `sources/town-calendar` and `sources/town-events`, and a problem in one never stops the other). A healthy run logs `calendar: ok — 26 Town pickups …` then `events: ok — 16 found, … upcoming …`; `events: warning —` lines flag an untitled event, an unfamiliar icon or an event on one language's calendar only. For bins, `calendar: warning —` lines are the schedule check (odd entries, or the Town and MRC calendars disagreeing) and are worth a look. Each year, as soon as the MRC publishes its new printed calendar (usually around December), ask Claude to turn it into `functions/data/mrc-<year>.json` (`tools/mrc_calendar.py`) and check the table it prints against the PDF.

**Weather** (`functions/src/weather/`) comes from two jobs writing one document, `weather/temiscaming`. `pollWeather` (every 15 minutes) reads Environment Canada: the Barrage Témiscaming station's current conditions, then the weather alerts whose area covers the town centre or Lumsden. `pollForecast` (hourly) reads Open-Meteo's 7-day forecast for the town's coordinates. Each part has its own health record (`sources/eccc-conditions`, `sources/eccc-alerts`, `sources/open-meteo-forecast`) and a failure in one never touches the others. A healthy `pollWeather` run logs `weather conditions: ok — 1.9 °C at Temiskaming Dam, read 30 min ago` and `weather alerts: ok — 0 for Témiscaming (… areas nearby)`; `pollForecast` logs `forecast: ok — 7 days from …`. If the app says "No recent reading from the station", the station has gone quiet (it happens; the forecast still shows). When Environment Canada issues an alert for our area, run *Capture fixtures* → `weather` to save a real example.

**Fire bans** (`functions/src/fire/`): `pollFireBans` (every 30 minutes) reads Quebec's open-fire ban (IFCO) and forest access ban (ICAF) from the Ministère de la Sécurité intérieure's map service and stores what they mean for Témiscaming in `fire/temiscaming`. Each layer has its own health record (`sources/msi-ifco`, `sources/msi-icaf`). When no ban exists anywhere, the ministry serves a tiny placeholder named "AUCUNE – …" whose date is when the last ban was lifted; a healthy run then logs `fire ifco: ok — none since 2026-07-20T16:00:00.000Z`. An **empty** file is treated as a failure on purpose (spec D3). A push goes to `fire-fr` / `fire-en` only when a ban is announced, starts or lifts *for Témiscaming*; the very first run after deploying records the current state without pushing. To see the stored state: Firebase console → Firestore → `fire` → `temiscaming` (`ifco.state` is `town`, `region` or `none`; `ifco.pushed.kind` is the last thing people were told). When a ban is issued anywhere in Quebec, run *Capture fixtures* → `fire` to save a real example.

**Roads** (`functions/src/roads/`, Milestone 7): `pollRoads` (every 15 minutes) reads Quebec's transport ministry (road warnings, roadworks, winter road conditions) and Ontario 511 (events, construction, road conditions, and the camera list once a day), keeps what's on Route 101 from Témiscaming to Ville-Marie and Highway 63 from Thorne to North Bay, and saves it in `roads/`, `road_conditions/route-101`, `road_conditions/highway-63` and `road_cameras/highway-63`. Ontario's calls are spaced 7 seconds apart (its limit is 10 a minute), so a run takes about a minute. Each source has its own health record (`sources/mtmd-warnings`, `mtmd-roadworks`, `mtmd-conditions`, `on511-events`, `on511-construction`, `on511-conditions`). A healthy run logs `roads: mtmd-warnings ok (0), mtmd-roadworks ok (0), mtmd-conditions ok (2), on511-events ok (0), on511-construction ok (0), on511-conditions ok (1)` — the numbers are items on our stretches, and 0 is normal. Pushes go to `roads-fr` / `roads-en` (opt-in) only when a road on our stretch fully closes, and again once it has been gone for 25 minutes ("reopened"); the first run after deploying records without pushing. What people were last told is in `roads_state/pushes`. `pollTownWorkInfo` (hourly) reads the Town's Work Info pages into `roads/town-<id>` (`sources/town-work-info`, no pushes).

**Testing a road push:** in the app, More → Roads → turn on "Get notified when Route 101 or Highway 63 closes" (or Settings → Road closures), put the app in the background, then Firebase console → Messaging → new campaign → topic `roads-fr` or `roads-en`; add the custom data `screen` = `roads` so tapping it opens the Roads screen. It arrives on the "Road closures" channel (pop-up).

**The Ontario 511 key** is a Firebase secret, never in the repo. Once, before the first deploy of `pollRoads` (and again only if the key changes), in VS Code's terminal:
```
firebase functions:secrets:set ONTARIO_511_KEY
```
and paste the key when asked (it doesn't show as you type). Without it, `pollRoads` still reads Quebec and the Ontario sources show "no Ontario 511 key". The *Capture fixtures* workflow uses the GitHub secret of the same name.

**Refreshing the test pages:** GitHub → Actions → *Capture fixtures* → Run workflow, then pick a source. `alerts` saves today's alert pages under `functions/test/fixtures/<date>/`; `calendar` saves every month of the Town calendar (FR + EN) and the MRC collection PDF under `functions/test/fixtures/calendar/<date>/`; `weather` saves Environment Canada's data and the Open-Meteo forecast under `functions/test/fixtures/weather/<date-time>/`; `fire` saves both fire-ban layers under `functions/test/fixtures/fire/<date>/`; `roads` saves the Quebec road layers, the Town's Work Info pages and (with the `ONTARIO_511_KEY` secret) Ontario 511 under `functions/test/fixtures/roads/<date>/`.

## Where things are

| Path | What it is |
|---|---|
| `lib/main.dart` | Starts the app |
| `lib/app.dart` | Language, theme, first screen |
| `lib/l10n/app_fr.arb`, `app_en.arb` | Every piece of text, in both languages |
| `lib/settings/` | The saved language and sector |
| `lib/onboarding/` | First-launch screens (language, sector, notifications) |
| `lib/home/` | Bottom bar, Today screen |
| `lib/alerts/` | Alerts list, alert detail, boil-water banner, reading Firestore |
| `lib/collection/` | Bin card, pickup schedule, on-phone reminders |
| `lib/events/` | Events tab, event detail, "Add to my calendar", Today's "Coming up" card |
| `lib/weather/` | Today's weather card and alert banner, the Weather screen, forecast labels |
| `lib/fire/` | The red fire-ban banner, Today's fire card and one-time notification offer, the Fire screen |
| `lib/push/` | Push notification topics |
| `functions/src/alerts/` | Backend: reads the Town's alert site, decides pushes |
| `functions/src/collection/` | Backend: reads the Town's calendar for bin pickups, merges the MRC calendar |
| `functions/src/events/` | Backend: events from the same calendar pages |
| `functions/src/weather/` | Backend: Environment Canada conditions and alerts, Open-Meteo forecast |
| `functions/src/fire/` | Backend: Quebec's open-fire and forest access bans, and their pushes |
| `test/` | Automated tests |
