# Spec — Milestone 7: Roads

Status: **draft for agreement** · 2026-10-22
Reads with: `DESIGN.md` (§2 principles, §4 architecture and source health, §5 language, §6.7 roads, §7 app structure), `research/roads-sources.md` (project docs)

Milestone 7 is split in two (owner, 2026-10-22):
- **7a (this spec): Route 101 (Quebec) + the Town's Work Info pages**, and the **More** tab.
- **7b (later): Highway 63 (Ontario 511)**, once the owner has a developer key. Until then the app says Ontario isn't covered yet and links to 511on.ca (§3 D10).

---

## 1. Goal

1. Every 15 minutes the backend knows what's happening on **Route 101 between Témiscaming and Ville-Marie**: closures and incidents, roadworks, and winter road conditions.
2. Every hour it reads the **Town's Work Info** list (street work, water-system work, local road disruptions).
3. A **Roads screen** shows all of it, with sources and "last checked" times. It lives in a new **More** tab.
4. **Today** shows a road card only when something's wrong on Route 101 (closure, incident, poor winter conditions) or the check is failing.
5. People who opt in get a push when Route 101 is **fully closed** on our stretch, and when it reopens.

---

## 2. What the sources actually look like (captured 2026-10-22, `functions/test/fixtures/roads/2026-10-22/`)

All three Quebec layers come from the transport ministry (MTMD, **CC-BY 4.0**, real time) through one WFS: `ws.mapserver.transports.gouv.qc.ca/swtq`, `version=2.0.0`, `outputformat=geojson`, `srsname=EPSG:4326`.

| Layer (`typename`) | What it is | Language | Today near us |
|---|---|---|---|
| `ms:evenements` ("Avertissement routier") | Closures and incidents: `identifiant`, `entrave` (*Fermeture*, *Fermeture de 1 voie sur 2*, *Circulation en alternance*…), `numeroRoute`, `localisation`, `municipalite`, `duree` (free text or *Indéterminée*), `cause`, `detour`, `enVigueurDepuis`. No end date: an item lasts until it's removed. | **French only.** Some fields are empty, `localisation` can contain `<br/>`, `numeroRoute` is sometimes blank even on a numbered route. | 0 near us; 16 in Quebec (one on Route 101 at Rouyn-Noranda, outside our stretch). |
| `ms:chantiers_mtmdet` ("Travaux routiers") | Roadworks: `identifiant`, `routeAutoroute`, `entraveType` (*Mineure (semaine)*, *Majeure…*), `entrave`, `debut`, `fin`, `localisation`, `direction`, **`descriptionFrancais` and `descriptionAnglais`**. | **Both languages** (the ministry's own English). | 2: Route 101 at Duhamel-Ouest / Saint-Bruno-de-Guigues (21–23 Oct, alternating traffic, *just north of Ville-Marie*), Route 382 at Belleterre. |
| `ms:conditions_routieres` (winter conditions) | One line per segment: `NumeroSegment`, `NumeroRoute`, start/end place names in FR and EN, `CodeEtatChaussee` + FR/EN description, `CodeVisibilite` + FR/EN description, `IndicateurPresenceLamesNeige`, `EnVigueurDepuis`. | **Both languages.** | Route 101: segment **3001** Témiscaming → Saint-Édouard-de-Fabre, **3011** → Ville-Marie, 3021 → Notre-Dame-du-Nord. All "Bare and dry", visibility good. Updated 04:11 today. |

| Finding | Consequence |
|---|---|
| The box filter must be written **latitude first** (`bbox=46.2,-80.0,47.5,-78.5,urn:ogc:def:crs:EPSG::4326`). Longitude first returns nothing, silently. | The parser test checks the request URL; a valid empty answer is never trusted on its own (D3). |
| "Nothing near us" is a normal, valid answer for warnings and roadworks: a FeatureCollection with `numberMatched: 0`. | An empty answer is **not** a failure for those two layers (unlike fire bans). It is a failure for winter conditions in season (D3). |
| The first capture got an HTTP 400 from the roadworks request; the next run worked. | Each layer is fetched and recorded separately; one failure doesn't block the others. |
| **Town Work Info** (`/fr/info-travaux`, `/en/work-info`): each item has a numeric ID shared by both languages, a title, `<time datetime="2026-10-01 00:00:00">` and "En vigueur du jeudi 1 octobre 2026 au samedi 31 octobre 2026." / "In effect from Thursday October 1, 2026 to Saturday October 31, 2026." The list's text is cut off ("…"); the full text is on each item's page. Past items drop off the list. Today: one item (1019, water-system flushing). Some items have a map point (757, Kipawa Road, 2024). | Read both lists, then each listed item's page in both languages. Not all items are about roads; we show them all, as the Town's own category. |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **What counts as "our stretch"** | A fixed line for Route 101 from Témiscaming to Ville-Marie, taken once from the ministry's own segments 3001 + 3011 (simplified, stored in code). A warning or roadwork counts when any point of it is **within 1 km of that line**, or **within 10 km of the town centre** (catches the interprovincial bridge and other provincial roads in town). Winter conditions: segments of route 101 lying on that line (today 3001 and 3011). | Matching by location works even when `numeroRoute` is blank. The roadwork just north of Ville-Marie (1.17 km from the line, past the end of segment 3011) stays out: the owner chose "to Ville-Marie". It is a test case, since it sits close to the 1 km limit. |
| D2 | **Kinds of item** | **Closure**: a warning or roadwork whose `entrave` starts with "Fermeture" and doesn't mention a lane, shoulder, ramp or parking (*voie, accotement, bretelle, stationnement*). **Incident**: any other road warning. **Roadwork**: any other roadwork. **Town work**: Work Info items. | Only a full closure pushes (DESIGN §6.7); "Fermeture de 1 voie sur 2" (one of two lanes) is not a closure. |
| D3 | **Reading the files (silence ≠ safety)** | Valid read = a GeoJSON FeatureCollection with a `numberMatched` count. Bad JSON, an HTML or XML error page, or features without geometry → failure; the previous items are kept and health goes red. **Winter conditions, 15 Oct–15 Apr:** no route-101 segment on our line → failure. **Outside that season:** no segment = "not published in summer" (not a failure, not "clear"). Town list: the page must have its title and list container; zero items is valid. | Same principle as every other source, adjusted to roads, where "nothing" is the normal state. |
| D4 | **Schedule and health** | `pollRoads` **every 15 min**: the three MTMD layers (3 small requests), each with its own health: `sources/mtmd-warnings`, `sources/mtmd-roadworks`, `sources/mtmd-conditions`; red after **1 h**. `pollTownWorkInfo` **every hour**: 2 list pages + 2 pages per listed item (usually 2–6 requests); `sources/town-work-info`, red after **3 h**. | Closures matter within the hour; the Town posts work a day or more ahead. |
| D5 | **"In effect" (a safety claim)** | Warnings: in effect from `enVigueurDepuis` until the ministry removes them (no end date exists; we never guess one from `duree`, which is shown as written). Roadworks: "Planned" before `debut`, "In effect" between `debut` and `fin`, gone after `fin` or when removed; roadworks starting more than **14 days** ahead aren't shown. Town items: "Planned" before their start date, "In effect" until their end date, hidden after it even if still listed. | DESIGN §8: never show "in effect" or "all clear" on a guess; "announced isn't in effect". |
| D6 | **Language** | Winter conditions and roadworks: the ministry's own FR/EN text. Road warnings: **our own FR/EN labels** for the kind (*Route fermée / Road closed*, *Une voie sur deux fermée / One of two lanes closed*, *Circulation en alternance / Alternating traffic*, else *Avertissement routier / Road warning*); place names as given; the ministry's `localisation`, `cause`, `duree`, `detour` shown as written under "Disponible en français seulement / Available in French only". Town items: FR and EN pages, one-language items labelled as usual. | DESIGN §5: no machine translation presented as official. |
| D7 | **Push: when** | Opt-in only. Push when a **closure on our stretch first appears** (and, for a planned roadwork closure, again when it starts only if it wasn't already pushed as planned), and a quieter push when it **reopens** (removed or past its end). Same item re-posted within 6 h → no new push. Incidents, roadworks, winter conditions, Town work → **no push**. The first run after a deploy records without pushing. | "Notifications only when they earn it" (principle 5); mirrors fire bans. |
| D8 | **Push: wording, topics, channel** | Our templates, e.g. *"Route 101 fermée à Saint-Édouard-de-Fabre"* / *"Route 101 closed at Saint-Édouard-de-Fabre"*; *"Route 101 rouverte…"* / *"Route 101 reopened…"*. Topics **`roads-fr`, `roads-en`**. Android channel **`roads`** at **high** importance (pop-up): the only people getting it chose it, and a closure of the one road north changes plans now. | DESIGN §5 push rules. |
| D9 | **Opt-in** | New Settings toggle **"Route 101 closures"**, **off by default for everyone**, new installs included (the first-launch notification step doesn't turn it on). The Roads screen shows "Get notified when Route 101 closes" with a switch. | DESIGN §3: roads are opt-in only. |
| D10 | **Highway 63 until 7b** | The Roads screen has a Highway 63 section: "Ontario road information isn't in the app yet" + link to Ontario 511 (Highway 63). No data, no "nothing reported". | Principle 3: silence must never look like safety. |
| D11 | **Today** | Amber road card (red stays for boil water and fire bans) only when, on our stretch: a closure, an incident, roadworks *with a closure*, or winter conditions other than bare (dry or wet) or with visibility other than good. One line per problem, max 3, tap → Roads screen. If any MTMD layer is red: "Couldn't check Route 101 since …". Otherwise no card. Town work never appears on Today. | DESIGN §7: "road status if anything's wrong". Ordinary roadworks would sit on Today all summer. |
| D12 | **Roads screen** | Sections: **Route 101 · Témiscaming – Ville-Marie** (closures and incidents first, then winter conditions per segment with "since …", then roadworks), **Highway 63** (D10), **Town work** (Work Info items). Each item: kind, status, place, dates, source text, link (Québec 511 or the Town's page). "Nothing reported on this stretch" only after a successful check. Credit line "Source: Ministère des Transports et de la Mobilité durable (CC BY 4.0)". Health line per section. | Principle 2: relay, don't replace. |
| D13 | **More tab** | Fourth tab **More** (*Plus*): Roads, Fire, Weather, Pickup schedule, Settings. The Today cards keep opening their screens as now; the gear icon on Today stays. About comes later (Milestone 9). | Owner's choice (2026-10-22); DESIGN §7 tabs. |
| D14 | **Firestore shape** | `roads/{id}` one doc per item (`qc-warning-<identifiant>`, `qc-roadwork-<identifiant>`, `town-<id>`); `road_conditions/route-101` one doc with the segments. Public read on both. Items that disappear from the source are deleted (after a reopen push for closures). | Same pattern as alerts and events; one small doc for conditions. |

---

## 4. Files touched

```
functions/
  src/roads/corridor.ts      NEW — Route 101 line (from segments 3001+3011), "near our stretch" test (D1)
  src/roads/mtmd.ts          NEW — parse the three WFS layers (D3), classify kinds (D2), status (D5)
  src/roads/town.ts          NEW — parse Work Info list + item pages, FR/EN pairing by ID, dates
  src/roads/sync.ts          NEW — runRoadsPoll / runTownWorkInfoPoll: fetch, compare, save, push (D7)
  src/weather/geo.ts         + distance from a point to a line (km)
  src/push/templates.ts      + road templates (FR/EN)
  src/adapters.ts            + firestore stores for roads; channel ID roads
  src/index.ts               + pollRoads (15 min), pollTownWorkInfo (hourly)
  test/roads-*.test.ts       NEW — parse, corridor, status, whole runs
  test/fixtures/roads/       real captures (2026-10-22) + hand-made ones marked as such
firestore.rules              + public read on roads/{doc}, road_conditions/{doc}
lib/roads/                   NEW — road_data.dart, roads_repository.dart, roads_card.dart, roads_screen.dart
lib/home/home_shell.dart     + More tab
lib/more/more_screen.dart    NEW — list of Roads, Fire, Weather, Pickup schedule, Settings
lib/home/today_screen.dart   + road card (D11)
lib/push/push_service.dart   + roads-fr / roads-en topics
lib/settings/…, lib/settings_screen.dart  + "Route 101 closures" toggle (off by default)
android/…                    channel roads (name from ARB)
lib/l10n/app_fr.arb, app_en.arb  + all roads and More text
test/roads/…, test/more/…    NEW — widget tests, screenshot cases
README.md                    + Roads lines (fixtures, logs, test push)
```

---

## 5. Data shapes

`roads/{id}` (normalized item, DESIGN §4)
```
{ id, source: "mtmd-warnings" | "mtmd-roadworks" | "town-work-info",
  kind: "closure" | "incident" | "roadwork" | "town",
  route: "101" | null, place,                         // municipality or Town
  title_fr, title_en, body_fr, body_en, original_language,
  source_url, published_at, starts_at, ends_at,        // ends_at null for warnings
  status: "planned" | "in_effect",                     // D5, recomputed each run
  on_today: bool,                                      // D11
  pushed: { kind: "closed" | "reopened", at } | null } // backend only (D7)
```
`road_conditions/route-101`
```
{ segments: [ { number, from_fr, from_en, to_fr, to_en, surface_code, surface_fr, surface_en,
                visibility_code, visibility_fr, visibility_en, since } ],
  in_season: bool, checked_at }
```
Health docs: the usual fields; `last_item_count` = items on our stretch (0 is valid, D3).

---

## 6. Behaviour

### Backend
`pollRoads` (15 min): GET the three layers with the box (each in its own try/catch) → parse (D3) → keep our stretch (D1) → classify (D2) and status (D5) → save → push on closure changes (D7). Log `roads: warnings ok (0), roadworks ok (0), conditions ok (2 segments)`.
`pollTownWorkInfo` (hourly): both lists → each item's page in both languages, 2 s apart → save; delete items gone from the list.

### App
- **Today:** amber road card or the stale warning (D11).
- **More → Roads:** D12. Offline: Firestore cache plus the "last checked" lines.
- **Settings:** "Route 101 closures" toggle (D9).

---

## 7. Out of scope for this milestone
Highway 63 / Ontario 511 (7b); road cameras (Québec 511 has some, none on our stretch worth it yet; revisit in 7b); maps drawn in the app; Route 101 beyond Ville-Marie; Chemin Kipawa and other municipal roads except through the Town's Work Info; snow-removal and winter-parking notices (they're Town news); pushes for Town work; the About screen.

---

## 8. Verification ("done means")
1. Backend tests on fixtures: the real 2026-10-22 files → 0 warnings and 0 roadworks on our stretch (the Duhamel-Ouest roadwork and the Rouyn-Noranda warning both left out), 2 winter segments "bare and dry"; Town list → item 1019 paired FR/EN, in effect 1–31 Oct; hand-made fixtures (marked as such): a *Fermeture* on Route 101 at Saint-Édouard-de-Fabre with blank `numeroRoute` → closure on our stretch; *Fermeture de 1 voie sur 2* → incident, not closure; a roadwork closure planned next week → "planned"; winter segment "Glacée" → on Today; empty conditions in season → failure, in summer → not published; bad JSON / HTML error page → failure, previous items kept; whole runs: closure appears → one push per language, re-post within 6 h → none, removed → one "reopened" push, first run after deploy → none.
2. App analyze + tests + iOS build green on CI; screenshots reviewed in both languages (nothing reported, closure, icy road, Town work, stale, summer, More tab, 200% text).
3. On the Android emulator: backend deployed and logging ok; the Roads screen matches Québec 511's map and the Town's Work Info page; a test push to `roads-fr` / `roads-en` arrives on the `roads` channel.
4. When the first real closure or icy report on Route 101 happens: capture it as a fixture and compare with the hand-made ones.

---

## 9. DESIGN.md changes on approval
§6.7 split into 7a/7b, sources (three MTMD layers, latitude-first box, Town Work Info), our stretch, closure rule, opt-in push; §4 stack (`pollRoads`, `pollTownWorkInfo`, `roads` and `road_conditions` collections, `roads-fr/en` topics, `roads` channel, health thresholds); §7 More tab and Today road card; §9 Milestone 7 split; §10 Ontario 511 key (requested / not yet).
