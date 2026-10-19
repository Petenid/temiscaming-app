# Spec — Milestone 1: Town alerts + urgent water push

Status: **agreed** · 2026-10-19 (owner confirmed D1 Blaze + budget alert, D4 quieter lift push, D6 firebase_core 5)
Reads with: `DESIGN.md` (§2 principles, §4 architecture, §5 language, §6.1 town alerts, §7 app structure)

---

## 1. Goal

When the Town posts an alert on `temiscaming.alertesmunicipales.com`:

1. a backend job notices it within ~10 minutes,
2. stores it in Firestore in both languages (when the source has both),
3. if it's a **new water advisory** (boil water, do-not-consume, water interruption, main break, cloudy water), sends **exactly one push per device, in that device's language**,
4. the app shows it in an **Alerts** list and, while a boil-water advisory is active, as a red banner on **Today**.

If the source can't be read, the app says so ("Couldn't check town alerts since 14:20") instead of looking all-clear (principle 3).

---

## 2. What the source actually looks like (checked 2026-10-19)

Findings that shape the design — several are surprises:

| Finding | Consequence |
|---|---|
| French list at `/alertes`, English list at `/alerts`. Each lists **every** alert (94 today, back to 2023) on one page, no pagination. No RSS/JSON feed. | Poll two pages per run. Normal item count ≈ 94; zero or a sudden large drop = failure. |
| Each item: title, link `/alertes/YYYY/MM/DD/slug` (EN: `/alerts/...`), "Publié le lundi 19 octobre 2026 à 13h58" / "Published on monday 19 october 2026 in 13h58", short excerpt. | Parse these four fields from the list page. |
| **Two different alerts can share one URL** (e.g. two lifting notices on 19 Oct at 13h38 and 13h58, same slug). | The item ID can't be the URL alone. ID = date + slug + publish time (see §5). |
| When an advisory ends, the Town (a) posts a separate "LEVÉE DE L'AVIS…" alert, and (b) prefixes the original's title with **"(Alerte levée)"**. The slug doesn't change. | (b) updates the existing item, not a new one — this is how DESIGN §6.1's "lifted advisory updates the item" is met. |
| ⚠️ The English site translates "(Alerte levée)" as **"(Alert raised)"** — the opposite meaning. | We never show that prefix as a status. We strip it and show our own bilingual status label ("Lifted / Levé"). Both spellings mean *lifted*. |
| Expired alerts appear under "Cette alerte n'est plus valide" / "This alert is no longer valid". | Store as `status: expired`. |
| Categories (≈30 types, e.g. Avis d'ébullition) exist as sidebar filters, but **items don't show their category**. | Classify water alerts by keywords in the FR **and** EN titles (§6). Category filter pages may give exact categories — check when real HTML fixtures are captured. |
| FR and EN versions of one alert share the same publish date and minute. Not every alert necessarily has an English version. | Pair by publish timestamp. No English pair → English fields empty + "Disponible en français seulement" label (DESIGN §5). |
| The detail page has the full text; the list only has a truncated excerpt. | Fetch a detail page only when an item is new or its title changed — not every run. |

**Raw HTML fixtures:** Claude's workspace can't reach the site directly. A small manual GitHub Actions workflow (`capture-fixtures.yml`) downloads the FR/EN list pages and a few detail pages and commits them under `functions/test/fixtures/`. Parser tests run against those saved files.

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Firebase Blaze plan** | Upgrade `temiscaming-app` to Blaze (pay-as-you-go, card required) and set a **$1 budget alert**. | Cloud Functions require Blaze. Our use (~9,000 runs/month) is far inside the free monthly allowance (2M invocations). Expected bill: $0. The budget alert emails you if that's ever wrong. |
| D2 | Backend language | **TypeScript** (Node 22) in `functions/` | Firebase's best-supported option; tests run in Claude's workspace, so test output can be shown directly. |
| D3 | Polling | Every **10 minutes**, two list pages per run (+ detail pages only for new/changed items) | Timely enough for boil-water; ~290 small requests/day to the Town's host, about what a few residents browsing would make. |
| D4 | What pushes | **New water advisory → urgent push.** Lifted advisory → normal (quieter) push. Everything else → in-app only. | A lift also changes what people do today (they can drink tap water again). Separate Android channels so people can silence one without the other. |
| D5 | Push routing | FCM **topics per language**: `water-fr`, `water-en`. The app subscribes to exactly one, matching its language; switching language swaps the topic. | One message per topic → each device gets exactly one push, in its language. No device tokens stored on our side (principle 6). |
| D6 | firebase_core | **Upgrade to 5.0** now, with `cloud_firestore` and `firebase_messaging` at matching versions. | We're about to add two Firebase packages anyway; doing the jump before they exist is cheaper than after. Android minSdk 24 is already Flutter's default. If CI's iOS build breaks, fall back to the 4.x line. |
| D7 | Tabs | Add a bottom bar with **Today · Alerts** now (Events and More arrive with their milestones). Settings stays behind the gear icon. | Minimal step towards DESIGN §7. |
| D8 | First-run safety | The first time the job runs (empty database) it **stores everything and pushes nothing**. Afterwards, never push an item published more than 24 h ago. | Otherwise the first deploy would push 94 old alerts. |

---

## 4. Files touched

```
functions/                              NEW — the backend (Cloud Functions, TypeScript)
  package.json, tsconfig.json
  src/index.ts                          scheduled function `pollTownAlerts` (every 10 min, Montréal region)
  src/alerts/parse.ts                   HTML list/detail page → raw items (pure function, no network)
  src/alerts/classify.ts                title → water category, status (active / lifted / expired)
  src/alerts/pair.ts                    match FR and EN items by publish time
  src/alerts/sync.ts                    compare with Firestore, write changes, decide pushes
  src/push/templates.ts                 our bilingual push texts (DESIGN §5)
  src/sourceHealth.ts                   record last success / attempt / item count
  test/*.test.ts                        tests against fixtures; Firestore + FCM faked
  test/fixtures/                        saved real pages (captured by CI workflow)
.github/workflows/capture-fixtures.yml  NEW — manual: download source pages into fixtures
.github/workflows/ci.yml                + job: build and test `functions/`
firebase.json                           + functions config
firestore.rules                         allow public read of `alerts` and `sources`; still no writes
pubspec.yaml                            firebase_core ^5, + cloud_firestore, firebase_messaging
lib/
  app.dart                              home → new shell with Today / Alerts tabs
  home/home_shell.dart                  NEW — bottom navigation bar
  home/today_screen.dart                + urgent water banner
  alerts/alert.dart                     NEW — the Alert data shape (from Firestore)
  alerts/alerts_repository.dart         NEW — listens to Firestore `alerts` + source health
  alerts/alerts_screen.dart             NEW — list, newest first, source-health line, sign-up link
  alerts/alert_detail_screen.dart       NEW — full text, language label, "View on the Town's site"
  push/push_service.dart                NEW — permission, topic subscribe/swap, channels
  onboarding/notifications_screen.dart  NEW — third onboarding step (explains what will/won't notify)
  settings_screen.dart                  + "Water alerts" on/off
  l10n/app_fr.arb, app_en.arb           + every new string
android/app/src/main/AndroidManifest.xml  notification permission + channels
ios/Runner/…                            push capability (compiles in CI; can't be tested without an Apple Developer account)
test/                                   + alerts list, banner, detail, onboarding step; FR + EN; 200% text
README.md                               + how to deploy functions and rules from VS Code's terminal
```

---

## 5. Data shapes

**Firestore `alerts/{id}`** — the normalized item from DESIGN §4, plus alert-specific fields:

```
id                 "2026-10-12_1432_avis-d-ebullition-preventif"   date_time_FR-slug
source             "alertes-municipales"
type               "town-alert"
category           "boil-water" | "do-not-consume" | "water-interruption"
                   | "water-main-break" | "cloudy-water" | "other"
status             "active" | "lifted" | "expired"
severity           "urgent" (water categories) | "info"
title_fr, title_en          prefix "(Alerte levée)/(Alert raised)" removed
body_fr,  body_en           plain text; "" if that language doesn't exist
original_language  "fr" | "en" | "both"
source_url_fr, source_url_en
published_at       timestamp (America/Toronto → UTC)
updated_at         when we last saw a change
pushed_at          when we sent its push (missing = never pushed)
```

**Firestore `sources/alertes-municipales`** — source health (DESIGN §4):
`last_attempt_at`, `last_success_at`, `last_item_count`, `last_error` (short text, or empty).

**Derived on the device, not stored:** "is a boil-water advisory active?" = any `boil-water` or `do-not-consume` alert with `status: active` published in the last 30 days. (The 30-day cap stops a forgotten, never-lifted alert from showing a banner forever; it still appears in the list.)

**On the device (`shared_preferences`):** `water_alerts_enabled` (default true), `notifications_asked` (onboarding done).

---

## 6. Behaviour

### Backend run (every 10 min)
1. Download `/alertes` and `/alerts`. On network error, HTTP error, or fewer than half of `last_item_count` items parsed → record failure in source health, change nothing else, stop.
2. Parse, pair FR/EN by publish minute, classify.
   - Water keywords (accents/case ignored), FR: *ébullition, bouillir, non-consommation, ne pas consommer, interruption, coupure, fermeture d'eau, bris, aqueduc, eau trouble, coloration*; EN: *boil, do not consume, interruption, shutdown, cut-off, cut off, main break, water break, cloudy, coloration, discolour*.
   - Lifted if the title has *(Alerte levée)/(Alert raised)/levée/lifted/lifting*, or the item is in the "no longer valid" group (→ expired).
3. For new or title-changed items, fetch the detail page(s) for the full body.
4. Write changes to Firestore. Record success in source health.
5. Push, once per item (guarded by `pushed_at`, so a retry never double-pushes): new active water alert → urgent; new lifting notice → normal. Not on first run; not if published > 24 h ago.

### Push text (our templates; source text one tap away)
| Case | Français | English |
|---|---|---|
| Boil water | **Avis d'ébullition à Témiscaming** — Faites bouillir l'eau du robinet avant de la boire. Touchez pour les détails. | **Boil-water advisory in Témiscaming** — Boil tap water before drinking it. Tap for details. |
| Do not consume | **Avis de non-consommation** — Ne buvez pas l'eau du robinet. Touchez pour les détails. | **Do-not-consume advisory** — Don't drink tap water. Tap for details. |
| Interruption / main break / cloudy | **Avis sur l'eau à Témiscaming** — {interruption d'eau \| bris d'aqueduc \| eau trouble}. Touchez pour les détails. | **Water notice in Témiscaming** — {water interruption \| water main break \| cloudy water}. Tap for details. |
| Lifted | **Avis levé** — L'avis sur l'eau est levé. Touchez pour les détails. | **Advisory lifted** — The water advisory has been lifted. Tap for details. |

Tapping opens that alert in the app.

### App
- **Onboarding step 3 — notifications:** explains in plain words: "We'll notify you about water advisories (boil water, water cuts) in Témiscaming. Weather and general news never notify." Buttons: *Allow notifications* / *Not now*. Then the system permission prompt. Skipped on Windows/macOS (no desktop push in v1).
- **Today:** while a boil-water/do-not-consume advisory is active, a red banner at the top (red + icon + words, never colour alone) that opens the alert. Otherwise unchanged placeholder.
- **Alerts tab:** newest first. Each row: our status label (*En vigueur / Active*, *Levé / Lifted*, *Expiré / Expired*), title in the user's language, date in their locale. Water alerts show a water icon. At the top: source-health line ("Last checked 16:40" or, in red, "Couldn't check town alerts since 14:20"). At the bottom, always: "Get official alerts from the Town — sign up" → `/inscrivez-vous` (FR) or `/register` (EN).
- **Alert detail:** title, date, full body. If only one language exists: "Disponible en français seulement / Available in English only" and the original text. Button: "View on the Town's site".
- **Offline:** Firestore's built-in cache shows the last data, with the "last checked" time (DESIGN §7).
- **Settings:** "Water alerts" switch → subscribes/unsubscribes the topic.

---

## 7. Out of scope for this milestone

- The Town's "Work Info" pages on `temiscaming.net` (road disruptions) — move to Milestone 7 (Roads).
- Pushes for non-water categories (they show in-app only).
- Desktop notifications (DESIGN §4).
- Installing on an iPhone (needs the Apple Developer Program). iOS push code compiles in CI but is untested until then; **Milestone 1 is verified on Android**.
- Machine translation of French-only alerts.
- Applying the visual identity (lake blue palette, Atkinson Hyperlegible) — still waits for the Today screen design.

---

## 8. Verification ("done means", DESIGN §6.1)

1. **Parser tests (CI + shown in chat):** FR and EN fixture pages parse to the right count, titles, dates, URLs; the two same-URL alerts on 2026-10-19 get different IDs; "(Alert raised)" is read as *lifted*; FR/EN pairs match.
2. **Sync tests (fake Firestore + fake FCM):** a fixture with a new boil-water alert → exactly one urgent push to `water-fr` and one to `water-en`; running again → no further push; the "(Alerte levée)" version of the same page → the item's status changes to *lifted*, no new item; first run → zero pushes; a page parsing to 0 items → source health marked failed, data untouched.
3. **App tests:** Alerts list, detail and Today banner in FR and EN, at 200% text; health line shows the failure text when the source is stale. Screenshots on the `screenshots` branch.
4. **End to end (owner, Android emulator with Google Play):** deploy rules + function; the list in the app matches the Town's site; send one test push to a **test-only topic** the emulator is subscribed to (no real users exist yet) and confirm it arrives in French, then switch to English and confirm the English one.
