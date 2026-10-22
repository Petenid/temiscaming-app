# Spec — Milestone 6: Fire bans

Status: **complete** · 2026-10-22 · agreed 2026-10-21 (owner agreed all of §3)
Reads with: `DESIGN.md` (§2 principles, §4 architecture and source health, §5 language, §6.6 fire bans, §7 app structure)

---

## 1. Goal

1. The backend knows, every 30 minutes, whether Quebec's **open-fire ban (IFCO)** or **forest access ban (ICAF)** is in effect for Témiscaming — or about to be.
2. When a ban **starts or lifts for Témiscaming**, phones that opted in get one push in their language.
3. **Today** shows a red banner while a ban covers the town, and a small fire card during fire season (status + "Check today's fire danger" → SOPFEU).
4. A **Fire screen** explains what's in effect, since when, what it means, and links to the official decision and map.

---

## 2. What the source actually looks like (checked live 2026-10-21)

Dataset: Données Québec, "Mesures préventives en lien avec les feux de forêt" — Ministère de la Sécurité intérieure (MSI), **CC-BY 4.0**, updated "as needed". Three layers, served by the ministry's WFS at `geoegl.msp.gouv.qc.ca/apis/wss/complet.fcgi` (GeoJSON, EPSG 4326):

| Layer (`typename`) | Meaning | Use |
|---|---|---|
| `msp_interdiction_feu_ciel_ouvert_ifco` | Open-fire ban in or near the forest | **Yes** |
| `msp_interdiction_circuler_foret_icaf` | Ban on travelling in / entering the forest | **Yes** |
| `msp_restriction_travaux_foret_rtf` | SOPFEU's work restrictions for forestry members | No (not for residents) |

| Finding | Consequence |
|---|---|
| Properties: `mes_prev` (measure name, **French only**), `date_eff` (`2026-07-20`), `heure_eff` (`12h`, `8h`, `18h`). No end date: a measure lasts until lifted or changed. | We show our own FR/EN labels per layer, never `mes_prev` (DESIGN §5). |
| **"No ban" is not an empty file.** Today both layers return exactly one feature: `mes_prev: "AUCUNE - Interdiction de faire des feux…"`, `date_eff: 2026-07-20`, `heure_eff: 12h`, a ~1 m square near 50.52 N, 73.95 W. The dataset page says the opposite ("no polygon appears"). | The `AUCUNE` placeholder is read as a confirmed "no ban since 20 July, noon". An **empty** collection is treated as a failure (D3). |
| `date_eff` + `heure_eff` may be **in the future**: bans are usually announced the day before (e.g. 1 July 2026 announcement, "takes effect 2 July at 8 a.m."). | "Starts Thursday at 8 a.m." is shown and pushed (D5). |
| Bans are drawn by territory (MRCs, parts of Nord-du-Québec). **2023:** Témiscamingue was covered and the Town posted its own measures on the alert site (5 and 12 June 2023 — already in our alert fixtures). **2026:** the 1–20 July ban covered Rouyn-Noranda and the Abitibi MRCs but **not Témiscamingue**. | A real "near but not here" case, and a reason for the point test (D2). |
| The ministry warns the polygons are **a map representation; the official territory is the ministerial decision** on Québec.ca. | Principle 2: always link the official decision; say so on the Fire screen. |
| ICAF in 2023 applied to **public lands** ("terres du domaine de l'État"), not to private land in town. The town point can sit outside the polygon while the forest all around is closed. | ICAF uses a "near Témiscaming" test, not "contains the town" (D2). |
| No live ban exists now, so no real "ban" polygon can be captured until one happens. | Ban fixtures are hand-made with the real property names; a real one is saved next time (§8 step 4). |

Fire danger: stays a **link** to SOPFEU (research §3, no permission to redistribute). FR page and EN page `sopfeu.qc.ca/en/current-situation/` — exact FR URL confirmed while coding.

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Which layers** | IFCO and ICAF. RTF ignored. | IFCO is the one residents feel (campfires, burning brush). ICAF matters to hunters, cottagers and anyone on forest roads. RTF targets forestry companies. |
| D2 | **What counts as "for Témiscaming"** | **IFCO:** in effect for Témiscaming when a polygon **contains the town centre or Lumsden** (reuse `weather/geo.ts`). **ICAF:** in effect "around Témiscaming" when a polygon comes **within 15 km** of either point. Either layer, if within 50 km but not matching: shown on the Fire screen as "in effect elsewhere in the region", no banner, no push. | IFCO covers whole territories, so the point test is exact. ICAF covers forest land and may exclude the town itself. "Elsewhere in the region" answers "I heard there's a ban — is it here?" without crying wolf. |
| D3 | **Reading the file (silence ≠ safety)** | Valid read = FeatureCollection whose features are all either the `AUCUNE` placeholder or real measures with a polygon and a parseable date. **Empty collection, bad JSON, a feature without geometry or date → failure**; the previous state is kept and health goes red. | The publisher's own docs contradict what it serves; if it ever switches to "empty means none", we'd rather show "couldn't check" than guess. |
| D4 | **Schedule and health** | `pollFireBans` **every 30 min**, both layers in one run, each with its own health: `sources/msi-ifco`, `sources/msi-icaf`. Red after **2 h**. Polled all year (2 small requests per run). | Bans take effect at a stated hour, usually announced the day before, so 30 min is ample. Gentle on the ministry's server (principle 4). |
| D5 | **When to push** | Push on a **change of state for Témiscaming** only: ban announced (future start) or started, and ban lifted. Not for boundary amendments that leave the town's state unchanged, not for "elsewhere in the region". If a ban was already pushed as announced, its start time doesn't push again. A lift followed by a new ban within 6 h doesn't push twice. | "Notifications only when they earn it" (principle 5); mirrors the water-advisory rules. |
| D6 | **Push wording and topics** | Bilingual templates in our own words, e.g. *"Interdiction de faire des feux à ciel ouvert à Témiscaming à partir de jeudi 8 h"* / *"Open-fire ban for Témiscaming starting Thursday at 8 a.m."*; *"…levée"* / *"…lifted"*. Topics **`fire-fr`, `fire-en`** (no tokens stored). Android channels **`fire_urgent`** (high, pop-up: ban starts) and **`fire_updates`** (default: lifted). | DESIGN §5 push rules; same pattern as water. |
| D7 | **Opt-in** | New Settings toggle **"Fire bans"**. On for new installs that accept notifications (the first-launch step turns all categories on together); **off** for people who installed before this, with a one-time card on Today offering to turn it on. | DESIGN §3 says fire bans notify; but silently adding a new push category to existing users is impolite. |
| D8 | **Today screen** | Ban covering town → **red banner** at the top (red is reserved for boil water and fire bans): "Open-fire ban in effect" / "Forest access ban around Témiscaming", tap → Fire screen. **Fire season (1 April – 15 November, SOPFEU's permit season):** a small fire card — "No open-fire ban for Témiscaming (since 20 July)" + "Check today's fire danger". Out of season: no card unless a ban or a stale source. | DESIGN §7; "seasonal: minimize outside fire season" (§6.6). |
| D9 | **Fire screen** | Status per layer (in effect for Témiscaming / around Témiscaming / elsewhere in the region / none since …), start date and time, what it means in plain words (e.g. IFCO: no campfires or brush fires; gas BBQs and solid-fuel appliances with a spark arrestor still allowed), "The official territory is the government's decision" + link, interactive map link, SOPFEU fire danger link, last-checked line. Opened from the banner or the card. | Principle 2; DESIGN §8 "status labels are a safety claim". |
| D10 | **Town's own fire notices** | Stay in **Alerts** as they are (the Town posted its own measures in 2023). The Fire screen adds a line: "The Town may add its own rules — see Alerts." No parsing of Town notices into the fire status. | The provincial data is the structured source; guessing from free text is what DESIGN §8 warns against. |
| D11 | **Firestore shape** | One document `fire/temiscaming`, public read. | One read for the app, offline cache, nothing to clean up. Same as weather. |

---

## 4. Files touched

```
functions/
  src/fire/parse.ts          NEW — WFS GeoJSON → Measure[] | "none since" (pure; AUCUNE placeholder, D3 checks)
  src/fire/status.ts         NEW — Measure[] → status for town (D2: contains / within 15 km / within 50 km)
  src/weather/geo.ts         + distance from a point to a polygon (km), next to the existing point-in-polygon
  src/fire/sync.ts           NEW — runFireBanPoll: fetch both layers, compare with previous state, push (D5)
  src/push/templates.ts      + fire templates (FR/EN)
  src/adapters.ts            + firestoreFireStore; channel IDs fire_urgent / fire_updates
  src/index.ts               + pollFireBans (every 30 min, Montréal region)
  test/fire-*.test.ts        NEW — parse, status, whole runs
  test/fixtures/fire/<date>/ NEW — real "none" captures + hand-made ban fixtures (marked as such)
firestore.rules              + public read on fire/{doc}
.github/workflows/capture-fixtures.yml  + "fire": IFCO and ICAF GeoJSON
lib/fire/                    NEW — fire_data.dart, fire_repository.dart, fire_banner.dart, fire_card.dart, fire_screen.dart
lib/home/today_screen.dart   + banner, seasonal card, one-time opt-in card (D7)
lib/push/push_service.dart   + fire-fr / fire-en topics
lib/settings/app_settings.dart, lib/settings_screen.dart  + "Fire bans" toggle
lib/onboarding/notifications_screen.dart  + mention fire bans in what will notify
android/…                    channels fire_urgent / fire_updates (names from ARB)
lib/l10n/app_fr.arb, app_en.arb  + all fire text
test/fire/…                  NEW — widget tests, screenshot cases
README.md                    + "Fire bans" troubleshooting and test-push lines
```

---

## 5. Data shapes

`fire/temiscaming`
```
{
  ifco: {
    state: "town" | "region" | "none",     // D2 ("town" = contains town/Lumsden)
    starts_at,                              // date_eff + heure_eff, America/Toronto; may be future
    none_since,                             // from the AUCUNE placeholder, when state = "none"
    checked_at
  },
  icaf: { state: "around" | "region" | "none", starts_at, none_since, checked_at },
  official_url_fr, official_url_en, map_url, sopfeu_url_fr, sopfeu_url_en,
  pushed: { ifco: { kind: "announced"|"started"|"lifted", at }, icaf: { … } }   // backend only, for D5
}
```
Health docs: the usual `last_success_at`, `last_attempt_at`, `last_item_count` (placeholder counts as 1).

---

## 6. Behaviour

### Backend
`pollFireBans` (30 min): GET IFCO, GET ICAF (each in its own try/catch) → parse (D3) → status (D2) → compare with stored state → save → push on change (D5). Log `fire: ifco ok (none since 2026-07-20), icaf ok (none since 2026-07-20)`.

### App
- **Today:** red banner (ban for town) or stale warning ("Couldn't check fire bans since …", in season or while a ban was last known) at the top; seasonal fire card (D8).
- **Fire screen:** D9. Offline: last cached document with its "last checked" time.

---

## 7. Out of scope for this milestone
Fire danger index in-app (needs SOPFEU's permission), RTF, maps drawn in the app, municipal burning permits, the Town's own fire notices as structured data (D10), Ontario-side bans, the "More" tab (Today card + Fire screen for now; DESIGN §7 tabs unchanged).

---

## 8. Verification ("done means")
1. Backend tests on fixtures: real "none" captures for both layers → `none since 20 July 12 h`; hand-made IFCO ban covering the Témiscamingue MRC → `town`; a 2026-style ban covering Rouyn-Noranda only → `region`; an ICAF polygon that leaves the town out but comes within 15 km → `around`; empty collection / bad JSON → failure, previous state kept; whole runs: announced → started → lifted gives exactly one push per step per language, an amendment gives none, a re-ban within 6 h gives none.
2. App analyze + tests + iOS build green on CI; screenshots reviewed in both languages (ban, no ban in season, out of season, stale, 200% text).
3. On the Android emulator: backend deployed and logging ok; Fire screen matches the ministry's map; a test push to `fire-fr` / `fire-en` arrives on the right channel.
4. Next time a ban is issued anywhere in Quebec: capture it as a fixture and check the real `mes_prev` wording and polygon shape against the hand-made ones.

---

## 9. DESIGN.md changes on approval
§6.6 source details (WFS layers, AUCUNE placeholder, ICAF "around" rule, Town notices stay in Alerts); §4 stack (`pollFireBans`, `fire` collection, `fire-fr/en` topics, `fire_urgent`/`fire_updates` channels); §7 Settings (Fire bans toggle); §8 lesson: "a publisher's description of its data may not match what it serves — check the live file".

---

## 10. Implementation notes (2026-10-21, backend)
- **"Elsewhere in the region" is 150 km, not 50 km** (D2). §8 step 1 asks for the July-2026 ban (Rouyn-Noranda + Abitibi) to show as `region`, but Rouyn-Noranda is ~130 km away. 150 km covers it and the rest of the MRC de Témiscamingue (Ville-Marie ~90 km).
- **The 6-hour re-ban rule (D5) was dropped.** If a ban lifts and comes back within 6 hours, the last push people got would say "lifted" while a ban is in effect. Instead, each layer remembers the last thing pushed (`pushed.kind`); a push goes out only when what's true now disagrees with it. That alone gives "announced then started = one push", "amendment = no push", and a failed push retried next run only if it's still true.
- **First run records, doesn't push**, so deploying never sends a surprise.
- **`pushed` lives inside each layer** (`ifco.pushed`, `icaf.pushed`) rather than a top-level map, so each layer's write is self-contained. It's in a public document; it holds only a kind and a time.
- **Partial push failure:** if one language's push fails and the other goes out, it's recorded as sent (resending the other language every 30 min would be worse); the failure is logged.
- **Links:** the Québec.ca measures page exists in French only (the app labels it, DESIGN §5). SOPFEU's regional pages, both read from the site's own language switch on 2026-10-21: `sopfeu.qc.ca/etat-situation/abitibi-temiscamingue/` (FR) and `sopfeu.qc.ca/en/current-situation/abitibi-temiscamingue/` (EN). The first backend release had a guessed French address; fixed with the app.
- **Fixtures:** `fixtures/fire/2026-10-21/` was copied from the live service through a web reader, not downloaded byte for byte; run *Capture fixtures* → `fire` once to replace it with the exact files (tests should still pass).

## 11. Implementation notes (2026-10-21, app)
- **The banner shows announced bans too** ("For Témiscaming, starting Thursday, October 22 at 8:00 a.m."), not only bans in effect: the announcement is when people need to know.
- **"Announced", never "in effect", before a ban starts** (card and Fire screen); caught in the first screenshot review.
- **Both bans in one banner**, open-fire ban first, rather than two red banners.
- **A stale check:** a ban last known in effect stays on the banner and screen, with "Couldn't check fire bans since …" in red. "No ban" is never shown after a failed check (principle 3). A problem also brings the Today card back outside fire season.
- **Today card:** the open-fire ban line always; the forest access ban only when there's one in the region or around town.
- **Opt-in (D7):** the first-launch answer now sets fire bans with the rest. People who answered before get the one-time card on Today, on phones only; either button hides it for good.
- **Unknown states:** if the backend ever writes a state the app doesn't know, the app treats it as "a ban here", so the person checks the official page rather than trusting silence.
- **SOPFEU's French page** is `/etat-situation/abitibi-temiscamingue/` (read from the site's language switch); the backend's stored link was corrected in the same patch.

## 12. Verification (2026-10-22)
1. Backend: 155 tests (34 new), on the real "no ban" files and the hand-made ban fixtures. Deployed 2026-10-21; first run recorded "none since 20 July" without pushing.
2. App: analyze + 161 tests + iOS build green on CI; screenshots 26–32 reviewed in both languages. Fixed during checks: an announced ban was called "In effect" on the card and Fire screen.
3. On the Android emulator: the app works with the live backend (owner, 2026-10-22).
4. **Still to see:** a real ban. When Quebec issues one anywhere, run *Capture fixtures* → `fire` and compare it with the hand-made fixtures.
