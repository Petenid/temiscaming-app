# Spec — Milestone 2: Collection day, local reminders, change notices

Status: **agreed** · 2026-10-19 (owner agreed D1–D10)
Reads with: `DESIGN.md` (§2 principles, §4 architecture incl. "Reminders vs. changes", §5 language, §6.2 collection day, §7 app structure)

---

## 1. Goal

1. A backend job reads the Town's events calendar, keeps only the **collection** events, and stores them in Firestore as a clean schedule per sector (`town`, `lumsden`).
2. The app shows **"This week: blue bin, Tuesday"** on Today (and the following pickups on a small schedule screen), in the user's language, for the sector they picked.
3. The app keeps a copy of the schedule **on the phone** and schedules the **evening-before reminder** itself (default 7 p.m.), so reminders still fire if our backend or the Town's site is down.
4. When the Town **moves, cancels or adds** a pickup in the next two weeks, the backend sends one **change notice** per phone, in its language, only to people in that sector.

If the calendar can't be read, or the Town hasn't posted far enough ahead, the app says so plainly instead of showing an empty "nothing this week" (principle 3).

---

## 2. What the source actually looks like (checked 2026-10-19, web reads)

These come from reading the live pages through a web reader, not yet from saved fixtures; step 1 of the build captures real fixtures and re-checks every row.

| Finding | Consequence |
|---|---|
| Monthly view: `temiscaming.net/fr/calendrier?year=Y&month=M` (EN: `/en/calendar?year=&month=`). Server-rendered HTML: a month grid **and** an agenda list grouped under day headings ("Mardi, 6 octobre 2026"). No iCal/RSS. | Parse the **agenda list** (one entry per event per day). Poll month by month. |
| Event links: `/fr/evenements/{y}/{m}/{d}/{id}/{slug}`. **The numeric `id` is shared by FR and EN** (141942 = Oct 6 compost on both sites). | `id` is our item ID; FR/EN pairing is exact, like alerts. |
| Month-level "banner" items use `/…/{y}/{m}/c{id}/…` with no day. | Ignored (not collections). |
| FR titles: `COLLECTE DES MATIÈRES COMPOSTABLES / RECYCLABLES / ORDURES MÉNAGÈRES`, then `-` or `--`, then the area. EN titles: `COMPOSTABLE MATERIALS COLLECTION / RECYCLABLE MATERIALS COLLECTION / HOUSEHOLD WASTE DISPOSAL -- …`. | Material from keywords (accent/case-insensitive, loose on dashes). compost → **green**, recycl → **blue**, ordures / household waste → **black**. |
| Areas: "TÉMISCAMING, LAC TEE ET CHEMINS DES CHALETS" (Tue) and "SECTEUR LUMSDEN ET LETANG" / "LETANG ET LUMSDEN" (Wed). EN: "TEMISCAMING, LAC TEE, AND COTTAGES ROADS", "LUMSDEN AND LETANG SECTORS". | Sector from keywords: *lumsden* or *letang* → `lumsden`; *témiscaming* / *lac tee* / *chalets* / *cottage* → `town`. Anything else → **unfamiliar** (§6, schedule check). |
| Regular pattern: a 4-week cycle **compost → recycling → garbage → recycling** (Feb, Oct, Nov, Dec 2026 all follow it). | We don't *assume* the cycle; it's only used by the schedule check to notice oddities. |
| Holiday weeks differ: **22–23 Dec 2026 has two pickups** (recycling + compost); MRC says **none 28–31 Dec**, and **no pickup 24 June** (that week shifts a day). | The app must handle two bins on one day and weeks with no pickup. |
| Some December entries appear **twice**. | De-duplicate by event `id`. |
| ⚠️ January 2026 shows a Lumsden/Letang garbage pickup on a **Tuesday** (27 Jan), and the reader saw no regular pickups 6–21 Jan (Christmas-tree pickup 5–8 Jan instead). | Either the Town's data has errors or the reader missed rows. The fixture check will tell. Rule either way: trust the posted date, flag it (§6). |
| **2027 isn't posted yet** (Jan 2027 is empty today). | The schedule simply ends. The app must say "not posted yet", never "no pickup" (D4). |
| The MRC 2026 PDF (`temiscaming.net/file-24778`) read as **blue-bin only** through the web reader. | DESIGN's fallback ("transcribe the MRC PDF") may not cover all three bins. The PDF is captured as a fixture and checked by eye before we rely on it. |
| The alert platform has a *Collecte domestique* category and has carried street-specific notices (e.g. "Avenue Murer – collecte des bacs", Aug 2025). | Those already appear in the Alerts tab (Milestone 1). Not used as a change source here (§7). |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Where the schedule comes from** | Backend function `pollTownCalendar` parses the calendar into Firestore `collections`. The app reads it, **saves a copy on the phone**, and schedules reminders from that copy. | DESIGN §4: one backend polls the Town; phones never scrape. The on-phone copy is what makes reminders work offline. |
| D2 | **Polling** | Every **2 hours**; this month + the next 2 months, FR + EN = **6 pages per run** (~72 requests/day). No detail pages. | Changes must land well before the 7 p.m. reminder; still far gentler than the alerts poll. |
| D3 | **What is a change notice** | Compared with the last successful run, for a pickup **today or within the next 14 days**: **moved** (same event id, new date — or an event disappears and the same bin + sector reappears within 7 days), **cancelled** (disappears, no replacement), **added** (new event in a month we had already seen). Never for a month seen for the first time, never on the very first run, never for past dates. One push per change, guarded by `pushed_at`. | Matches DESIGN §6.2 "a changed date produces a change notice", without pushing a flood each time a new month comes into view. |
| D4 | **When the Town hasn't posted far enough ahead** | No guessing. Source health records `posted_through` (last date with a pickup). If that's less than 14 days away, Today and the schedule screen say **"The Town hasn't posted pickups after Dec 23 yet"** with a link to the calendar. Reminders stop at the last known pickup. MRC-PDF fallback decided after we've seen the captured PDF (separate small decision, not built now). | A projected rotation would be wrong exactly at New Year, when it matters (double week, no pickup, Christmas trees). Silence must not look like "no pickup" (principle 3). |
| D5 | **Odd entries** (unfamiliar area name, pickup on an unusual weekday, unknown material) | Show the pickup with the date the Town posted. Record each oddity in source health `warnings` and the function log (`firebase functions:log`). No push just for being odd. An entry with an **unfamiliar area** isn't assigned to anyone and isn't shown — the warning tells us to add a sector. | This is DESIGN's "schedule check": a future haut/bas split or a typo gets caught without a phone call, and we don't guess who an unknown area means. |
| D6 | **Push routing for change notices** | FCM topics per **sector and language**: `collection-town-fr`, `collection-town-en`, `collection-lumsden-fr`, `collection-lumsden-en`. The phone subscribes to exactly one (or none). Changing sector or language swaps it. | Same idea as `water-fr/en`: one push per phone, in its language, only to the affected sector, no tokens stored. |
| D7 | **Reminders** | New packages: `flutter_local_notifications` + `timezone`. Phones only (desktop shows the schedule in-app, like alerts). Times are always **America/Toronto** (the town's time zone). Schedule the next **8 weeks**, rebuilt on every app start, schedule update and settings change. Android uses **inexact** scheduling (`inexactAllowWhileIdle`): may arrive a few minutes late, but needs no "alarms & reminders" permission, which Google Play restricts. Survives phone restarts (boot receiver in the manifest). | DESIGN §4 "Reminders vs. changes". 8 weeks stays far under iOS's 64-pending-notification limit. |
| D8 | **Settings** | **"Bin reminder"** on/off (default on) + **time** (default 19:00, time picker). **"Collection changes"** on/off (default on). Both independent of "Water alerts". | DESIGN §6.2: adjustable, can be turned off. Someone may want changes without the nightly reminder. |
| D9 | **Special collections** (Christmas trees, bulky items) | Recognised from the title and shown in the schedule with their own label; **no reminder** and no change push in v1. Christmas trees have no area in the title → shown to both sectors. | They're real and useful, but rare and irregular (Christmas trees ran Mon–Thu). Keep reminders for the three bins. |
| D10 | **Android channel** | New channel "Collection" (name from ARB) for reminders and change notices, default importance (sound, no heads-up). | Lets people silence bins without silencing boil-water alerts. |

---

## 4. Files touched

```
functions/
  src/collection/parse.ts           calendar month HTML → raw events (pure, no network)
  src/collection/classify.ts        title → material, sector(s), special kind; oddity checks
  src/collection/pair.ts            join FR/EN by event id
  src/collection/sync.ts            diff with Firestore, write, detect changes, decide pushes
  src/push/templates.ts             + bilingual change-notice texts
  src/index.ts                      + scheduled `pollTownCalendar` (every 2 h, Montréal)
  src/adapters.ts                   (reused: fetcher, store, messenger)
  test/collection-*.test.ts         parser, classifier, sync against fixtures; fakes for Firestore/FCM
  test/fixtures/calendar/2026-10-19/  FR+EN for Jan–Dec 2026 and Jan 2027, + MRC PDF
.github/workflows/capture-fixtures.yml   + "calendar" option: saves those 26 pages + PDF (2 s apart)
firestore.rules                     + public read of `collections`
pubspec.yaml                        + flutter_local_notifications, timezone
android/app/src/main/AndroidManifest.xml  + boot receiver / scheduled-notification receivers
android/…/MainActivity.kt           + "Collection" channel
lib/
  collection/pickup.dart            NEW — one pickup (date, bins or special kind, sector, links)
  collection/collection_repository.dart  NEW — Firestore listener + on-device copy (shared_preferences JSON)
  collection/reminder_scheduler.dart     NEW — builds the next 8 weeks of local reminders
  collection/collection_card.dart        NEW — Today card ("This week: blue bin, Tuesday")
  collection/collection_screen.dart      NEW — next 8 weeks, health / "not posted yet" line, link to calendar
  collection/bin_icon.dart               NEW — bin icon + name (never colour alone)
  home/today_screen.dart            + collection card
  push/push_service.dart            + collection topic alongside water topic
  settings/app_settings.dart        + reminder on/time, collection-changes on
  settings_screen.dart              + the three controls
  onboarding/notifications_screen.dart  text now mentions bin reminders and changes
  settings/sector.dart              remove "used from Milestone 2" note; weekday used by schedule check display only
  services.dart                     + collection repository, reminder scheduler
  l10n/app_fr.arb, app_en.arb       + every new string
test/                               + card, screen, settings, scheduler; FR + EN; 200% text; offline
README.md                           + how to fire a test reminder; deploy the new function
DESIGN.md                           status lines (§6.2, §7, §9) when done
```

---

## 5. Data shapes

**Firestore `collections/{eventId}`** (normalized item, DESIGN §4, plus collection fields):

```
id                 "141942"   Town event id (shared FR/EN)
source             "town-calendar"
type               "collection"
date               "2026-10-06"   local calendar date (no time; pickups are all-day)
sectors            ["town"] | ["lumsden"] | ["town","lumsden"] (no area in title)
material           "compost" | "recycling" | "garbage" | null (special)
special            "christmas-trees" | "bulky" | null
title_fr, title_en         Town's text, as posted ("" if missing)
source_url_fr, source_url_en
irregular          true if the date isn't the sector's usual weekday
previous_date      set when moved ("2026-06-24"); used by the app's "moved" label
status             "scheduled" | "cancelled"
first_seen_at, updated_at, pushed_at (change push sent)
```

**Firestore `sources/town-calendar`**: `last_attempt_at`, `last_success_at`, `last_item_count`, `last_error`, plus `posted_through` (date), `months_seen` (["2026-10", …]), `warnings` (short texts, latest run only).

**On the phone (`shared_preferences`):** `collection_cache` (JSON of upcoming pickups + `posted_through` + when fetched), `bin_reminder_enabled` (true), `bin_reminder_time` ("19:00"), `collection_changes_enabled` (true).

---

## 6. Behaviour

### Backend run (every 2 h)
1. Download the 3 months × FR/EN. Any network/HTTP error, or the **current month** parsing to zero collection events, or under half its last count → record failure in source health, change nothing, stop. (A later month with zero events is normal: not posted yet.)
2. Parse agenda entries, keep titles starting `COLLECTE` / containing `COLLECTION` / `WASTE DISPOSAL`, de-duplicate by id, pair FR/EN, classify (§2).
3. **Schedule check** (D5): unfamiliar area, unknown material, unusual weekday → `warnings` + log.
4. Diff with stored items **for the months fetched** → changes (D3). Write. Update `posted_through`, `months_seen`. Record success.
5. Push change notices to `collection-{sector}-{lang}` per D3. First run: store only.

### Push text — change notices (our templates; Town's page one tap away)
| Case | Français | English |
|---|---|---|
| Moved | **Collecte déplacée** — Bac bleu : jeudi 25 juin (au lieu du mercredi 24 juin). | **Pickup moved** — Blue bin: Thursday, June 25 (instead of Wednesday, June 24). |
| Cancelled | **Collecte annulée** — Bac bleu du mercredi 24 juin. Touchez pour les détails. | **Pickup cancelled** — Blue bin on Wednesday, June 24. Tap for details. |
| Added | **Collecte ajoutée** — Bac vert : mercredi 23 décembre. | **Pickup added** — Green bin: Wednesday, December 23. |

Bin names: *bac vert (compost) / bac bleu (recyclage) / bac noir (ordures)* · *green bin (compost) / blue bin (recycling) / black bin (garbage)*. Tapping opens the schedule screen.

### Reminder text (scheduled on the phone, user's language at scheduling time)
**Demain : bac bleu (recyclage)** — Sortez-le ce soir. / **Tomorrow: blue bin (recycling)** — Put it out tonight. Two bins → "bac bleu et bac vert" / "blue and green bins". No pickup tomorrow → no reminder.

### App
- **Today card:** "Cette semaine : bac bleu, mardi" / "This week: blue bin, Tuesday" (bin icon + name), then "Ensuite : bac noir, mardi 27 oct." After the pickup day passes, shows next week's. Moved pickups show "déplacée / moved" next to the date. Cancelled: "Pas de collecte cette semaine" only when the Town actually cancelled it. Unknown future → the D4 "not posted yet" line. Tap → schedule screen.
- **Schedule screen:** next 8 weeks for the user's sector, grouped by week, special collections included; health line ("Dernière vérification 16:40" or red "Impossible de vérifier le calendrier depuis 14:20"); "Voir le calendrier de la Ville" link.
- **Settings:** the three controls (D8). Turning the reminder off cancels scheduled ones immediately.
- **Onboarding step 3:** adds "the evening before your pickup, and when a pickup changes".
- **Offline:** everything above works from the on-phone copy, with "last updated" time.

---

## 7. Out of scope for this milestone

- Reading **Town news** or the **alert platform** for cold-weather delays. News posts are free text (unreliable to parse); alert-platform collection notices already show in the Alerts tab. Revisit if a real delay slips past the calendar.
- Projecting the rotation beyond what the Town has posted (D4), and building the MRC-PDF data file (decide after seeing the PDF).
- Reminders for Christmas trees / bulky items (D9); desktop reminders.
- Events calendar (Milestone 3) — the parser is written so Milestone 3 can reuse it, but no events UI now.
- Visual identity (palette, font) — still waits for the Today screen design.
- Street-based sector detection (research §1).

---

## 8. Verification ("done means", DESIGN §6.2)

1. **Fixtures:** run *Capture fixtures → calendar* once; re-check every §2 row against the saved pages (especially the January 2026 oddity and the December duplicates).
2. **Parser/classifier tests (shown in chat):** for each month Jan–Dec 2026, both sectors: correct bin(s) and date for every pickup; Dec 22–23 double; duplicates collapsed; FR/EN paired; Jan 2027 → zero pickups, not a failure. A **hand-made expected table** for the blue bin, typed from the MRC PDF (an independent source), must agree with the parsed calendar; disagreements are listed, not hidden.
3. **Sync tests (fake Firestore + FCM):** first run → no pushes; same pages again → no pushes; a fixture edited to move 24 Jun → 25 Jun → exactly one push to `collection-lumsden-fr` and one to `-en`, none to `town`; a change 3 weeks out → no push; current month parsing to 0 → failure recorded, data untouched; unfamiliar area → warning, item not assigned.
4. **App tests:** Today card and schedule screen in FR/EN at 200% text, including double week, cancelled, moved, "not posted yet", stale source; scheduler test: with the repository **offline** and only the on-phone copy, the right reminders are scheduled at 19:00 Toronto time the evening before, none for no-pickup days; turning the reminder off cancels them. Screenshots on the `screenshots` branch.
5. **End to end (owner, Android emulator, VS Code):** deploy rules + function; the schedule screen matches the Town's calendar for both sectors; set the reminder 2 minutes ahead (debug-only "test reminder" button), turn on **airplane mode**, and confirm it arrives; send a test change notice to a test-only topic and confirm it arrives in French, then English.
