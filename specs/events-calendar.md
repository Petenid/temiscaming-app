# Spec — Milestone 3: Events calendar

Status: **agreed** · 2026-10-20 (owner agreed D1, D3, D6, D10 explicitly and the rest by default; D6: iOS and Android must both work, desktop doesn't matter). Backend built: 94 backend tests green (17 new).
Reads with: `DESIGN.md` (§2 principles, §4 architecture, §5 language, §6.3 events, §7 app structure), `specs/collection-day.md` (§2 source findings, the month parser)

---

## 1. Goal

1. The backend reads the **same Town calendar pages** Milestone 2 already downloads, keeps everything that **isn't** a pickup, and stores one clean event per Town event in Firestore `events`.
2. The app's **Events tab** lists upcoming events by date in the user's language; tapping one shows its detail with a link to the Town's page and **"Add to my calendar"**.
3. **Today** shows the next few events (DESIGN §7).
4. Collection pickups never appear in Events. Events never push (DESIGN §3).

---

## 2. What the source actually looks like (checked 2026-10-20 against the saved fixtures and two live detail pages)

Fixtures: `functions/test/fixtures/calendar/2026-10-19/` (all of 2026 + Jan 2027, FR and EN) — already in the repo, no new capture needed.

| Finding | Consequence |
|---|---|
| 2026 has **73 non-pickup events** (86 day-entries) across all 12 months, 3–13 per month. Every id appears in both FR and EN. | Pair FR/EN by event id, exactly like pickups. |
| Each agenda entry has: icon, title, and sometimes a **place** in a small `<span>` (51 of 86 have none). Places are translated: "Le Centre - Salle Dottori" / "The Centre - Dottori Hall", "Musée de la Gare" / "Train Station Museum". | Extend `parseMonth` to return the place it currently throws away. Store `place_fr` / `place_en`. |
| **No start time anywhere** — not in the agenda, not in the month grid, not on the detail page (checked a show and a council meeting). Detail pages add only the street address, sometimes a one-line description or a ticket link. | Events are **all-day**. Don't fetch detail pages (D2). "Add to my calendar" creates an all-day event. |
| Icons (FR count): `pm-circle-info` 32 (Town hall / Ecocentre / library **closed**), `pm-gavel` 16 (council meetings), `pm-leaf-maple` 12 (**Service Canada** visits), `pm-microphone-stand` 8 + `pm-masks-theater` 5 (shows, museum), `pm-star-sharp` 5, `pm-group-hands-up` 3, `pm-family` 2, `pm-hockey-stick-puck` 3 (community). | Category from the icon (D4). Unknown icon → "community" + warning. |
| **Multi-day events** are listed under every day, always linking to the start date: hockey tournament 23–25 Jan, museum expo 10–13 Aug, Town hall closed 21–25 Dec and 28–31 Dec. The link date is the real start even across months: Town hall closed from **29 Dec 2025**, listed from 1 Jan. | Start = the link date (or first day listed, if earlier); end = last day listed. |
| Council titles in English drop the word "council": "Séance ordinaire du conseil" → "Regular session". 17 of 73 events have identical FR and EN titles (names: "SERVICE CANADA", show titles). | Our category label ("Conseil municipal" / "Town council") gives the context. Identical titles are normal, not "one language only". |
| One council meeting (11 Mar, id 143095) has an **empty title** in both languages. | D3. |
| Some titles carry their own date ("VOLUNTEER PICNIC \| MAY 24TH 2026"). | Show as posted; our date comes from the agenda heading. |
| Jan 2027 is empty today (not posted yet). | Show "Events after Dec 31 aren't posted yet" (D8), never an empty "nothing coming up" past the horizon. |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Where events come from** | Extend the existing `pollTownCalendar` run: after the pickups step, the **same 6 downloaded pages** feed an events step that writes Firestore `events`. The events step runs in its own try/catch with its own health record (`sources/town-events`), so a bug there can never break bin pickups. | Zero extra requests to the Town's server (principle 4); no second scheduled function to deploy and watch. |
| D2 | **Detail pages** | **Not fetched.** The list gives title, dates, place and link; detail pages add only an address and rarely a line of text. The detail screen links to the Town's page. | Would multiply requests by ~30 per run for almost nothing. |
| D3 | **Event with an empty title** | Show it with our category label as the title, in italics ("Conseil municipal" / "Town council"), plus the usual link. Logged as a warning. | It's a real meeting on the calendar; hiding it loses information. The label is ours and true (from the icon), not a guess at the Town's wording. |
| D4 | **Categories** | From the icon: `council` (gavel), `closure` (circle-info), `service-canada` (leaf-maple), `culture` (microphone, theatre masks), `community` (star, hands, family, hockey, and any unknown icon + warning). Shown as a small label and icon on each row. **No filters** in v1. | Gives the English council titles their missing context, and lets closures look different from celebrations. Filters can wait until there's real demand (principle 7). |
| D5 | **Languages** | Titles and places from each language's page. If one language's title is missing, show the other with the "Disponible en français seulement" / "Available in English only" label (DESIGN §5). | Same rule as alerts. |
| D6 | **Add to my calendar** | Package `add_2_calendar` ^3.1.1 (June 2026; source read 2026-10-20). **iOS 17+:** shows Apple's own "new event" sheet, **no permission prompt**; the user taps Add or Cancel. **iOS 16 and older:** asks for calendar access once, so Info.plist needs `NSCalendarsUsageDescription` (+ `NSContactsUsageDescription`, which the package says the sheet's place field can need). One string each, **French first, then English** (localized plist files would mean hand-editing the Xcode project without a Mac). **Android:** sends the standard "insert event" request to the installed calendar app (no permission; needs the `<queries>` manifest entry on Android 11+); if no calendar app is installed it returns false and we show "No calendar app found on this phone". **All-day dates** differ by platform: Android gets UTC midnights with an exclusive end day, iOS local dates — in one small tested function. **Desktop: button hidden.** | The user stays in control (nothing is written without their tap in their own calendar). `.ics` files were the alternative, but Google Calendar on Android doesn't reliably open them. |
| D7 | **Changes and cancellations** | No push, no "changed" labels. Each run replaces upcoming events: an event the Town removes disappears; one it edits shows the new text. Past events (ended before today) are deleted. | DESIGN §3: events don't notify. Tracking edits adds complexity nobody asked for. |
| D8 | **Horizon line** | The list ends with "Events after [last day of the last month fetched] aren't posted yet" and a link to the Town's calendar. | Principle 3 in spirit: the end of our window shouldn't look like the end of the Town's events. |
| D9 | **Source health** | `sources/town-events` mirrors the calendar fetch: a failed download is a failure. A run that finds **zero events across all 3 months** while pickups parsed fine is recorded as a failure too (a quiet layout change); a single empty month is normal. Red after **5 hours**, same as the bin schedule. | Principle 3: a broken parser must not look like a quiet month. |
| D10 | **Today** | A card "Coming up" / "À venir" with the next **3** events (today first, labelled "Aujourd'hui" / "Today"), tap → Events tab. Closures today or tomorrow are included like any other event. | DESIGN §7 home layout. "Town hall closed tomorrow" is exactly what Today is for. |

---

## 4. Files touched

```
functions/
  src/collection/parse.ts        + return `place` and `linkDate`; pickups ignore them
  src/collection/classify.ts     + isPickupIcon(): the one test that routes an entry to bins or events
  src/events/build.ts            NEW — icon → category, FR/EN pairing, multi-day spans, empty titles, warnings (pure)
  src/events/sync.ts             NEW — write/delete `events`, health `sources/town-events`
  src/collection/sync.ts         + return the downloaded pages (also when a later pickup check fails)
  src/index.ts                   + events step after the pickups step, each in its own try/catch
  src/adapters.ts                + Firestore events store
  test/events-*.test.ts          NEW — against the 2026 fixtures; fake store
firestore.rules                  + public read of `events`
pubspec.yaml                     + add_2_calendar
ios/Runner/Info.plist            + NSCalendarsUsageDescription, NSContactsUsageDescription
android/app/src/main/AndroidManifest.xml    + <queries> for the calendar insert intent
lib/
  events/town_event.dart         NEW — one event (dates, titles, place, category, links)
  events/events_repository.dart  NEW — Firestore listener (on-device cache like alerts) + health
  events/events_screen.dart      NEW — Events tab: grouped by date, horizon line, health line
  events/event_detail_screen.dart NEW — detail, Town link, add to calendar (phones only)
  events/events_card.dart        NEW — Today "Coming up" card
  events/category_icon.dart      NEW — category icon + label (never icon alone)
  home/home_shell.dart           + Events tab
  home/today_screen.dart         + events card (replaces that part of the placeholder)
  services.dart                  + events repository; calendar adder behind an interface (fake in tests)
  l10n/app_fr.arb, app_en.arb    + every new string
test/                            + list, detail, card; FR + EN; 200% text; offline; empty title; one-language title
README.md                        + fold in the deploy-timeout and `git am --quit` notes (DESIGN §10 to-do)
DESIGN.md                        status lines (§6.3, §7, §9) when done
```

---

## 5. Data shapes

**Firestore `events/{eventId}`** (DESIGN §4 normalized item, plus event fields). Document id = the Town's event id (shared FR/EN; one document per event, even multi-day).

```
id                 "138263"   (Kavanagh show, 21 March 2026)
source             "town-calendar"
type               "event"
category           "council" | "closure" | "service-canada" | "culture" | "community"
title_fr, title_en "ANTHONY KAVANAGH | HAPPY" — as posted; "" if missing
original_language  "both" | "fr" | "en" | "none"   (which titles exist; "none" = D3)
place_fr, place_en "Le Centre - Salle Dottori" / "The Centre - Dottori Hall"; "" if none
starts_on          "2026-03-21"   local date, all-day
ends_on            "2026-03-21"   same as starts_on for one-day events
source_url_fr, source_url_en
first_seen_at, updated_at
```

**Firestore `sources/town-events`**: `last_attempt_at`, `last_success_at`, `last_item_count`, `last_error`, `listed_through` (last day of the last month fetched: drives D8), `warnings` (latest run only).

Nothing new stored on the phone beyond Firestore's own cache.

---

## 6. Behaviour

### Backend (inside the 2-hourly calendar run)
1. Pickups step runs exactly as today.
2. Events step, from the same 6 pages: entries **without** a bin or fir icon → pair FR/EN by id → spans (first/last day listed) → category → warnings (empty title, unknown icon).
3. Health check (D9). On failure: record it, change nothing.
4. Write every event ending today or later; delete stored events no longer listed or already ended. Record success and `listed_through`.

### App
- **Events tab:** sections by day ("Mercredi 21 octobre" / "Wednesday, October 21"); a multi-day event appears once, under its start (or under today if it's already running), with "21–25 déc." / "Dec 21–25". Each row: category icon + label, title, place. Health line at the top ("Calendrier vérifié : 16:40" or red after 5 h). Horizon line at the bottom (D8). "Voir le calendrier de la Ville" link.
- **Detail:** title (or italic category label, D3), date or range, place, category, one-language label if needed, "Voir sur le site de la Ville" / "View on the Town's site", "Ajouter à mon calendrier" / "Add to my calendar" (phones).
- **Today:** "À venir" / "Coming up" card (D10).
- **Offline:** last cached list with "last updated" time.

---

## 7. Out of scope for this milestone

- Event reminders or any push (DESIGN §3 "maybe opt-in later").
- Category filters, search, a month-grid view.
- Event start times, descriptions, prices (the source doesn't give times; detail pages not fetched).
- Events from anywhere but the Town's calendar (Facebook pages, the Ontario side).
- Desktop add-to-calendar (D6).
- Visual identity (palette, font) — still waits for the Today screen design.

---

## 8. Verification ("done means", DESIGN §6.3)

1. **Backend tests (shown in chat):** every 2026 month in both languages → exactly the events in §2 (73 events: 24 closures, 16 council, 12 Service Canada, 10 culture, 11 community, every one paired FR/EN, **no pickup ever an event and no event ever a pickup**: the two steps together account for every entry on every page); multi-day spans correct (23–25 Jan, 10–13 Aug, 21–25 Dec, 28–31 Dec); the 11 Mar empty title → category title + warning; places in both languages; Jan 2027 → zero events, not a failure.
2. **Sync tests (fake store):** first run writes; same pages again → no changes; an event removed from a page → deleted; past events deleted; 3 months with zero events but pickups present → failure recorded, data untouched; an exception in the events step → pickups still saved.
3. **App tests:** Events tab, detail and Today card in FR and EN at 200% text, including multi-day, empty title, one-language title, stale source, horizon line; add-to-calendar called with an all-day event (fake), button absent on desktop. Screenshots on the `screenshots` branch.
4. **End to end (owner, Android emulator, VS Code):** deploy rules + functions; the Events tab matches the Town's calendar for the rest of October and November in both languages; "Add to my calendar" opens the emulator's calendar pre-filled with an all-day event.
