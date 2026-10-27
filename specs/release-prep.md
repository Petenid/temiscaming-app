# Spec — Milestone 9: Last features + release prep

Status: **agreed** · 2026-10-27 (owner agreed §3; name Mon Témis confirmed — owner sees no real Témiscouata confusion; domain montemis.ca and a project email to be set up by the owner, walkthrough given in chat)
Reads with: `DESIGN.md` (§2 principles, §3 scope, §5 language, §6.2 collection, §6.3 events, §6.7 roads, §7 app structure, §9 milestone 9)

---

## 1. Goal

Part A — five last features (owner, 2026-10-27):
1. **Community events**: events the owner adds (Christmas parade, charity events) and, later, events organizations submit through a form the owner approves.
2. **Town work moves to Alerts**, in its own section (most of it isn't about roads: e.g. October's water system flushing).
3. **Share button** on alerts.
4. **Winter overnight parking reminder** on Today, around the start and end of the ban.
5. **Bin-day home-screen widget**.

Part B — release prep (DESIGN §9): About screen with a feedback link, final name **Mon Témis** and app ID, store listings FR + EN, privacy policy, Charter of the French Language check, desktop builds, iOS push, "Add to my calendar" on a real iPhone, `firebase_core` update.

Not changed: fire bans stay as they are (card 1 April – 15 November, SOPFEU's season). Useful-numbers list: later.

---

## 2. What the sources look like (checked 2026-10-27)

| Finding | Consequence |
|---|---|
| **Winter parking is fixed by By-law #140**: "From November 1st to April 15, parking on the streets is prohibited between midnight (12:00 a.m.) and 8:00 a.m." (Town news, 4 Nov 2025; same dates 1 Nov 2024). On 15 Apr 2025 the Town posted "Dès ce soir, c'est permis!" | Dates can live in the app (no new backend source). The Town's own notices still show in Alerts if it ever posts a change. Link the Town's "Overnight Parking" page. |
| The Town also offers free night lots (church lot on Boucher St., next to Parc Philippe-Barette), "new" in 2024. | Not listed in-app (could change); the link covers it. |
| Town Work Info has a single item today (1019, "Water system flushing — month of October"). Items stay in Firestore `roads` with `source: town-work-info`. | Moving them is app-only; the backend doesn't change. |
| "Mon Témis": no app or service by that name found. **But** "Mon Temiscouata" (montemiscouata.com) is a news site in Arsenal Media's "Mon [region]" network (Mon Joliette, Mon Matane…), and "Témis" usually means **Témiscouata** in Quebec (e.g. "Région Témis", "Marché du Témis"). | Risk of confusion, not a legal block (not legal advice). Mitigation: store name always "Mon Témis – Témiscaming" (D9). |
| Google Sheets "Publish to web" can publish **one tab** as CSV at a fixed URL, refreshed by Google within about 5 minutes of an edit. | The backend reads only the "Approved" tab; form answers (with organizers' contact details) are never published. |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Community events: the sheet** | One Google Sheet owned by the owner. Tab **"Approved"** with fixed columns: `id` (owner-chosen, e.g. `parade-2026`), `title_fr`, `title_en`, `start_date`, `start_time` (optional), `end_date` (optional), `end_time` (optional), `place_fr`, `place_en`, `organizer`, `description_fr`, `description_en`, `link` (optional). Only this tab is published as CSV. A row in it = published; delete the row to remove it. | Owner edits a spreadsheet, not the Firebase console; the form plugs into the same sheet later. |
| D2 | **Community events: the form** | A Google Form (questions written "Titre / Title"), answers going to a private **"Submissions"** tab. Owner copies approved rows to "Approved". An **"Submit an event / Proposer un événement"** link at the end of the Events tab, opening the form. The form asks for a contact email for the owner only (privacy policy mentions it). | Organizations submit; the owner stays the gatekeeper. No accounts, nothing written by the public goes straight into the app. |
| D3 | **Community events: backend** | New `pollCommunityEvents`, **every 30 minutes** (one small download). Writes to `events` with `source: "community"`, IDs `community-<id>`; removed rows disappear, ended events deleted, like Town events. Health `sources/community-events`, red after 2 h. **An empty Approved tab is normal**; failure = download error, missing/renamed columns. A row with a bad date is skipped and logged (one bad row never hides the others). Sheet URL stored as a Firebase parameter, not in the code. | Same rules as the Town calendar; quick enough that a fix shows within the hour. |
| D4 | **Community events: in the app** | Same list and Today "Coming up" card as Town events, labelled **"Organized by <organizer>"** instead of a Town category, with its own icon. Times shown when given (Town events stay all-day). "Add to my calendar" uses the times. One-language titles get the usual "only in French/English" label; never machine-translated. Health line only when failing. | Readers must tell a Town event from a community one (principle 2). |
| D5 | **Town work in Alerts** | Alerts tab: alerts as now, then a **"Town work / Travaux de la Ville"** section (dates, "in effect from … to …", the Town's link, its own "last checked" line). Roads screen: Town section removed, replaced by one line "Town work is listed in Alerts". Still no push. | Owner, 2026-10-27. No guessing which items are about roads. |
| D6 | **Share an alert** | A Share button on each alert's detail screen (and Town work items). Opens the phone's share sheet (package `share_plus`) with text in the **reader's language**: our status label + the alert's title + date + the **Town's link**, e.g. *"Avis d'ébullition — en vigueur depuis le 27 octobre · https://temiscaming.alertesmunicipales.com/…"*. Desktop: copies the text. No app link until the app is in stores. | Word of mouth for boil-water notices; always points to the official source. |
| D7 | **Winter parking reminder** | An **info card** on Today (lake blue, not amber: it's a reminder, not a problem) shown **3 days before through 3 days after** each date: **29 Oct – 4 Nov** ("Starting 1 November: no street parking from midnight to 8 a.m., until 15 April") and **12 – 18 April** ("Night parking on the street allowed again from 15 April"). Link to the Town's page, source "Town of Témiscaming, By-law #140". Dates in one constant. Can be dismissed for that period. **No push.** | Owner, 2026-10-27. It's a fixed by-law, so no backend source to fail. |
| D8 | **Bin-day widget** | **Android (this milestone):** home-screen widget (package `home_widget`) showing "This week: blue bin · Tuesday" and the next pickup, with bin icons always named. The app writes the next 8 weeks into the widget's storage, **already worded in the user's language**; the widget picks the right week from today's date, so it stays right offline and without opening the app. Past 8 weeks: "Open the app to update". Tap → app. **iOS:** needs a WidgetKit extension and an App Group, which must be signed with the Apple Developer account. Built alongside iOS push (Part B), same signing work. | Most-used information for older residents; bins already work offline (DESIGN §4 "Reminders vs. changes"). |
| D9 | **Name and app ID** | Name **Mon Témis** (confirmed); store name **"Mon Témis – Témiscaming"**; keywords "Mon Temis, Temiscaming, Témiscaming, Lumsden". App ID **`ca.montemis.app`**. **montemis.ca** is registered by the owner's spouse (CIRA's Canadian Presence Requirement: the owner is a temporary resident; the registrant can be changed to the owner after permanent residence), with the project Gmail as the account contact. Icon: a new mark is needed (the "ô" was Allô's); proposal: lake-blue square with "MT" or a pine + lake, explored in a design pass. User-Agent becomes `MonTemis/1.0 (…)` (ASCII). | The ID can never change after the first store upload. |
| D10 | **About + feedback** | About screen (More tab): independence statement, every source with its licence and link, the Town's official alert sign-up, privacy summary, version, and **"Send feedback / Envoyer un commentaire"** (opens an email to the project address, `contact@montemis.ca` forwarding to a new project Gmail; never the owner's personal address). | DESIGN §7. |

---

## 4. Files touched (planned)

- **Backend:** `functions/src/events/community.ts` (CSV → items), `functions/src/index.ts` (`pollCommunityEvents`), `firestore.rules` (unchanged: `events` already public-read), tests + fixtures `functions/test/fixtures/events/community-*.csv` (hand-made: normal, empty, renamed column, bad date, FR-only row).
- **App:** `lib/events/*` (source, organizer, times; form link), `lib/alerts/alerts_screen.dart` + a Town work section reusing `lib/roads/roads_widgets.dart`, `lib/roads/roads_screen.dart` (line to Alerts), `lib/alerts/alert_detail_screen.dart` (Share), `lib/home/parking_card.dart` + `today_screen.dart`, `lib/collection/widget_sync.dart`, `android/app/src/main/…` (widget layout + Kotlin provider), `lib/more/about_screen.dart`, ARB files.
- **Rename:** `appTitle`, Android `applicationId` / namespace, iOS bundle ID, macOS/Windows names, Firebase app registrations (new IDs need new `google-services.json` / `GoogleService-Info.plist` — owner step), User-Agent.
- **Docs:** this spec, `DESIGN.md` (§3: community events through the owner; §6.3; §6.7 Town work; §7), README (sheet + form how-to).

## 5. Out of scope

Useful-numbers list; organizations editing their own events; importing organizations' calendar links (.ics) — possible later; machine translation; pushes for community events or parking; desktop widgets.

## 6. Order of work (one patch each)

1. Town work → Alerts (D5) · 2. Share (D6) · 3. Parking card (D7) · 4. Community events backend (D3) · 5. Community events app + form link (D4, D2) · 6. Android widget (D8) · 7. About + feedback (D10) · 8. Rename + ID (D9) · 9. Release prep (store listings, privacy policy, Charter check, desktop builds, iOS push + iOS widget, iPhone checks, `firebase_core`).

## 7. Verification

- Backend: fixture tests for every CSV case in §4; a whole poll adding, editing and removing a row; first live run's log read.
- App: tests + CI screenshots in both languages for the Alerts Town-work section, Share text, parking card on 29 Oct / 1 Nov / 4 Nov / 5 Nov (gone), community events (with and without times, FR-only), About; 200% text.
- Device: Android emulator — add a row to the sheet, see it in Events within the hour; widget shows the right bin, survives airplane mode and a date change; share sheet opens.

## 8. Commercial option (exploration only — nothing built)

If costs ever need covering: findings and what would change are in the project doc `research/commercial.md`. Short version: banner ads would make the app commercial under Open-Meteo's terms (paid plan or a new forecast source) and Hydro-Québec's CC BY-NC licence (permission needed), and bring privacy work (Law 25: tracking off by default). Voluntary donations keep every licence as it is.
