# Spec — Milestone 8: Power outages

Status: **agreed** · 2026-10-27 (owner agreed all of §3: Lac Tee included, push threshold 25 customers)
Reads with: `DESIGN.md` (§2 principles, §4 architecture and source health, §5 language, §6.8 power outages, §7 app structure)

---

## 1. Goal

1. Every 15 minutes the backend knows about **Hydro-Québec outages in Témiscaming** (customers affected, since when, estimated restoration, cause) and **planned interruptions** in the coming days.
2. An **Outages screen** (More tab) shows both, with Hydro-Québec's own caveats and links.
3. **Today** shows an amber card only when the power is out here, a planned interruption is today or tomorrow, or the check is failing.
4. People who opt in get a push when the power goes out in Témiscaming, and when it's back.

---

## 2. What the source actually looks like (checked live 2026-10-27, 13:20–13:50)

Hydro-Québec open data, "Pannes et interruptions planifiées" (`donnees.hydroquebec.com/explore/dataset/pannes-interruptions/information/`). **Licence: CC BY-NC 4.0** (non-commercial). Update frequency stated: 15 minutes.

| Request | What it returns |
|---|---|
| `pannes.hydroquebec.com/pannes/donnees/v3_0/bisversion.json` | A timestamp in quotes, e.g. `"20261027134010"` (Montréal time). |
| `…/bismarkers<version>.json` | `{ "messages": {}, "pannes": [ [...], … ] }`, one 10-item array per **ongoing** interruption, province-wide (105 at 13:40). |
| `…/aipversion.json` | Same kind of timestamp. |
| `…/aipmarkers<version>.json` | A bare array, one 16-item array per **planned** interruption, province-wide (190). |

**Ongoing (`bismarkers`), per row:** `[customers, start, estimated end, type, "[lon, lat]", status, (ignore), cause, locality, message id]`.
**Planned (`aipmarkers`), per row:** `[customers, notice no., planned start, planned end, actual start, actual end, postponed start, postponed end, shifted start, shifted end, cause, equipment, remark, municipality, status, "[lon, lat]"]`.

### Findings that shape the design
| Finding | Consequence |
|---|---|
| **The "municipality" in `bismarkers` is Hydro-Québec's own 4-digit locality ID**, not the government code. Checked 29 IDs against Hydro-Québec's own region list (`infopannes…/assets/data/bilan-par-region.json`): all matched (e.g. `1000` Montréal, `2375` Gatineau). **Témiscaming = `9130`** (one locality covering the whole Ville, 1,636 customers — Lumsden and Letang aren't separate). **Tee Lake = `9124`**, which Hydro-Québec files under **Kipawa**, not Témiscaming. | Filter by locality ID, exact. Lac Tee is a decision (D1). |
| `aipmarkers` uses the **5-digit government code** instead: Témiscaming (V) = `85005`, Kipawa (M) = `85010`. (My first guess, 85037, is Lorrainville: checked by name, not memory.) | Planned interruptions are filtered by `85005`, and Lac Tee by distance within `85010` (D1). |
| **Rows of type `I` appear in `bismarkers`**: planned interruptions *in progress* (70 of 106 rows). The documentation only mentions `P` (outage). `I` rows carry causes 61–63 and 77, which the documentation doesn't list. | `P` = outage, `I` = planned work in progress. Unknown cause codes are shown as nothing, never guessed. |
| Status `N` appears (16 rows), undocumented; documented are `A` assigned, `R` crew on the way, `L` crew at work. The estimated end is often **blank** on new outages. | We label A/R/L only; anything else shows no status. Blank end → "No estimate yet". |
| **The feed works and is honest about our region.** A real outage at Lorrainville (29 customers, started 13:34) appeared in the 13:40 version, matching Hydro-Québec's own regional count. But the version stayed at 13:30 for 18 minutes before that. | End-to-end delay is up to ~30 min (theirs + our poll). The version timestamp itself is the freshness check (D3). |
| The live answer is province-wide and never empty in practice (105 ongoing, 190 planned on a quiet Tuesday). Témiscaming has nothing today. | "Nothing in Témiscaming" is the normal state; a province-wide empty file is suspicious (D3). |
| Hydro-Québec's notices: some outage areas may not appear; times, causes and counts are indicative; everyone must protect themselves against outage damage. | Shown on the Outages screen (principle 2). |
| Hydro-Québec also runs a newer site (`infopannes.solutions.hydroquebec.com`) with an undocumented API and ArcGIS layers. | **Not used**: it's not the published open data and could change without notice. Only linked, for the map. |
| Neither Claude's workspace nor the owner's linked computer can reach `pannes.hydroquebec.com` from a shell (refused by the network proxy); the desktop app's browser can. | Fixtures come from the *Capture fixtures* workflow (`power` option). The first live run's log must be read (DESIGN §8 "test from where the code runs"). |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **What counts as Témiscaming** | **Ongoing:** locality `9130` (Témiscaming, incl. Lumsden and Letang). **Lac Tee (agreed: included):** locality `9124` "Tee Lake", and planned interruptions in Kipawa within 3 km of Lac Tee. The app's town sector already includes Lac Tee. Kipawa village itself stays out. **Planned:** municipality `85005` (+ Lac Tee per above). | Exact IDs from Hydro-Québec's own list; distance only where the IDs can't separate Lac Tee from Kipawa. |
| D2 | **Kinds of item** | **Outage:** `bismarkers` type `P`. **Planned work in progress:** type `I` (labelled "Planned interruption — in progress"). **Upcoming planned:** `aipmarkers` rows here whose (postponed or shifted, else planned) end is in the future, up to 14 days ahead. Postponed shows "Postponed to …". | Residents feel `P` and `I` the same way (no power), but only `P` is a surprise. |
| D3 | **Reading the files (silence ≠ safety)** | Valid read: version is a 14-digit timestamp; markers file has the right shape (each row 10 or 16 items, parseable start date or planned date, `[lon, lat]`). **Failure** (previous state kept, health red): bad JSON, wrong shape, HTTP error, a province-wide file with **zero** rows, or a **version older than 45 minutes** (ongoing) / 6 hours (planned). A valid file with nothing for Témiscaming = "No outage reported in Témiscaming", shown only after a successful read. | The version stalled 18 min while we watched; a frozen file would otherwise look like "all clear" forever. Hydro-Québec has outages somewhere in Quebec at all times. |
| D4 | **Schedule and health** | `pollPowerOutages` **every 15 minutes** (2 requests for ongoing + 2 for planned; the 2 planned ones only every hour). Health `sources/hq-outages` (red after **1 h**) and `sources/hq-planned` (red after **3 h**). | Matches Hydro-Québec's own update rate; ~100 small requests a day. |
| D5 | **Push: when** | Opt-in. Push when **unplanned outages (`P`) in Témiscaming first total at least the threshold**, and a quieter "power restored" push once **no `P` outage has been listed for 20 minutes**. A second outage during the first: no new push. Planned interruptions: **no push** (Hydro-Québec notifies the affected customers itself; shown in the app and on Today). First run after a deploy records without pushing. **Threshold (agreed): 25 customers** (~1.5% of the town); smaller ones are shown in the app only. | Single-house outages are common and would push everyone who opted in. 20 minutes avoids "restored / out again" flapping. |
| D6 | **Push: wording, topics, channel** | Our templates: *"Panne de courant à Témiscaming — 120 clients touchés"* / *"Power outage in Témiscaming — 120 customers affected"*; *"Courant rétabli à Témiscaming"* / *"Power restored in Témiscaming"*. Topics **`power-fr`, `power-en`**. Android channel **`power`**, high importance (pop-up). | DESIGN §5; same pattern as roads. |
| D7 | **Opt-in** | Settings toggle **"Power outages"**, **off by default for everyone** (first-launch answer doesn't turn it on). The Outages screen shows a "Notify me" switch. | DESIGN §3: opt-in only. |
| D8 | **Language** | The data has **no text**: every label is ours, FR and EN (type, status A/R/L, cause groups from the documentation: equipment failure, weather, accident or incident, vegetation, animal, planned work for 61–63/77 on `I` rows only). Unknown codes → no label. Times in fr-CA / en-CA. | DESIGN §5. Fully bilingual with no "available in … only" labels. |
| D9 | **Today** | **Amber** card when: an outage or planned work is in progress here ("Power outage — 120 customers since 2:15 p.m., estimated back 6:00 p.m."), or a planned interruption starts **today or tomorrow**, or "Couldn't check Hydro-Québec since …". Otherwise no card. Tap → Outages screen. | DESIGN §7 "outage status if anything's wrong". Red stays for boil water and fire bans. |
| D10 | **Outages screen** | In More. **Now:** each outage / work in progress: customers affected, since, Hydro-Québec's estimated restoration ("estimate"), crew status, cause. **Planned:** date, time window, customers, postponed/shifted. "Last checked", Hydro-Québec's notices (some outages may not appear; times are estimates), link to Hydro-Québec's outage map and to report an outage (exact pages and phone number confirmed while coding), credit "Hydro-Québec, open data (CC BY-NC 4.0)", and the Notify switch. Coordinates aren't shown (no map in the app). | Principle 2: relay and link; never present an estimate as a promise. |
| D11 | **Firestore shape** | One public document **`power/temiscaming`**: `{ outages: [...], planned: [...], version_ongoing, version_planned, checked_at }` + backend-only `power_state/temiscaming` (what was last pushed). | Like fire bans: one read, offline cache, nothing to clean up. |

---

## 4. Files touched

```
functions/
  src/power/parse.ts         NEW — version + bismarkers/aipmarkers → rows (pure; D3 shape checks)
  src/power/filter.ts        NEW — rows → Témiscaming items (D1, D2)
  src/power/sync.ts          NEW — runPowerPoll: fetch, freshness check, save, push (D5)
  src/push/templates.ts      + power templates (FR/EN)
  src/adapters.ts            + firestorePowerStore; channel id `power`
  src/index.ts               + pollPowerOutages (every 15 min, Montréal region)
  test/power-*.test.ts       NEW — parse, filter, whole runs
  test/fixtures/power/<date>/ NEW — real captures + hand-made Témiscaming files (marked as such)
firestore.rules              + public read on power/{doc}; power_state backend-only
.github/workflows/capture-fixtures.yml  + "power": both version files and both markers files
lib/power/                   NEW — power_data.dart, power_repository.dart, power_widgets.dart, power_screen.dart
lib/home/today_screen.dart   + outage card
lib/more/more_screen.dart    + Outages entry
lib/push/push_service.dart   + power-fr / power-en topics
lib/settings/…, lib/settings_screen.dart  + "Power outages" toggle (off by default)
android/…                    channel `power` (name from ARB)
lib/l10n/app_fr.arb, app_en.arb  + all outage text
test/power/…                 NEW — widget tests, screenshot cases
README.md                    + outages troubleshooting and test-push lines
```

---

## 5. Data shapes

`power/temiscaming`
```
{
  outages: [{
    kind: "outage" | "planned_in_progress",
    customers, started_at, estimated_end_at (or null),
    status: "assigned" | "on_the_way" | "at_work" | null,
    cause: "equipment" | "weather" | "accident" | "vegetation" | "animal" | "planned_work" | null,
    area: "temiscaming" | "lac_tee"
  }],
  planned: [{
    notice, customers, starts_at, ends_at,          // effective window (postponed/shifted if any)
    original_starts_at,                             // set when postponed or shifted
    change: "postponed" | "shifted" | null, area
  }],
  version_ongoing, version_planned, checked_at
}
```
`power_state/temiscaming` (backend only): `{ pushed: "out" | "restored" | null, pushed_at, last_seen_outage_at }`.
Health docs: the usual `last_success_at`, `last_attempt_at`, `last_item_count` (province-wide row count).

---

## 6. Behaviour

### Backend
`pollPowerOutages` (15 min): version → markers (ongoing); hourly also version → markers (planned); each part in its own try/catch → parse (D3) → filter (D1, D2) → save → push on change (D5). Log `power: ongoing ok (v20261027134010, 105 rows, 0 here), planned ok (190 rows, 0 here)`.

### App
- **Today:** D9.
- **Outages screen:** D10. Offline: last cached document with its "last checked" time; stale → red "Couldn't check Hydro-Québec since …", and an outage last known stays shown as last known.

---

## 7. Out of scope for this milestone
Outage polygons or a map, Kipawa village and other neighbours, Ontario (Hydro One) outages, Hydro-Québec's undocumented API, address-level "is my house affected", pushes for planned interruptions, outage history.

---

## 8. Verification ("done means")
1. Backend tests on fixtures: today's real captures → nothing in Témiscaming, all rows parsed, Lorrainville's outage read correctly; hand-made files built from the real rows: an outage in `9130` → listed; `9124` Tee Lake → per D1; a planned interruption in `85005` and a postponed one; a stale version → failure, previous state kept; empty or malformed file → failure; whole runs: out → still out → restored (after 20 min) gives exactly one push per step per language; below threshold → none; first run → none.
2. App analyze + tests + iOS build green on CI; screenshots in both languages (outage, planned tomorrow, nothing, stale, 200% text).
3. Deployed: the first live run's log reads every file (from the Cloud Function, not just GitHub); app on the Android emulator; test push to `power-fr` / `power-en`.
4. Next real outage in Témiscaming: capture it as a fixture and compare with Hydro-Québec's map.

---

## 9. DESIGN.md changes on approval
§6.8 source details (locality vs municipality IDs, `I` rows, freshness check, CC BY-NC); §4 stack (`pollPowerOutages`, `power` collection, `power-fr/en` topics, `power` channel); §7 Settings (Power outages toggle); §10 open question: Hydro-Québec's licence is non-commercial, like Open-Meteo's; §8 lesson: "IDs that look like government codes may be a publisher's own — check them by name".
