# Spec — Milestone 7: Roads

Status: **agreed 2026-10-27** (owner agreed all of §3) · backend built · app built · first draft 2026-10-22; Highway 63 added once the Ontario 511 key arrived
Reads with: `DESIGN.md` (§2 principles, §4 architecture and source health, §5 language, §6.7 roads, §7 app structure), `research/roads-sources.md` (project docs)

---

## 1. Goal

1. Every 15 minutes the backend knows what's happening on **Route 101 from Témiscaming to Ville-Marie** (Quebec) and **Highway 63 from Thorne to North Bay** (Ontario): closures and incidents, roadworks, and road conditions.
2. Every hour it reads the **Town's Work Info** list (street work, water-system work, local road disruptions).
3. A **Roads screen** shows all of it, with sources and "last checked" times. It lives in a new **More** tab.
4. **Today** shows a road card only when something's wrong on either road (closure, incident, poor conditions) or a check is failing.
5. People who opt in get a push when either road is **fully closed** on our stretch, and when it reopens.

---

## 2. What the sources actually look like (captured 2026-10-22 and 2026-10-23, `functions/test/fixtures/roads/`)

### Quebec — transport ministry (MTMD), CC-BY 4.0, real time
One WFS: `ws.mapserver.transports.gouv.qc.ca/swtq`, `version=2.0.0`, `outputformat=geojson`, `srsname=EPSG:4326`.

| Layer (`typename`) | What it is | Language | On 2026-10-22 near us |
|---|---|---|---|
| `ms:evenements` ("Avertissement routier") | Closures and incidents: `identifiant`, `entrave` (*Fermeture*, *Fermeture de 1 voie sur 2*, *Circulation en alternance*…), `numeroRoute`, `localisation`, `municipalite`, `duree` (free text or *Indéterminée*), `cause`, `detour`, `enVigueurDepuis`. No end date: an item lasts until it's removed. | **French only.** Some fields are empty, `localisation` can contain `<br/>`, `numeroRoute` is sometimes blank even on a numbered route. | 0 near us; 16 in Quebec (one on Route 101 at Rouyn-Noranda, outside our stretch). |
| `ms:chantiers_mtmdet` ("Travaux routiers") | Roadworks: `identifiant`, `routeAutoroute`, `entraveType` (*Mineure (semaine)*, *Majeure…*), `entrave`, `debut`, `fin`, `localisation`, `direction`, **`descriptionFrancais` and `descriptionAnglais`**. | **Both languages** (the ministry's own English). | 2: Route 101 at Duhamel-Ouest / Saint-Bruno-de-Guigues (21–23 Oct, alternating traffic, *just north of Ville-Marie*), Route 382 at Belleterre. |
| `ms:conditions_routieres` (winter conditions) | One line per segment: `NumeroSegment`, `NumeroRoute`, start/end place names in FR and EN, `CodeEtatChaussee` + FR/EN description, `CodeVisibilite` + FR/EN description, `IndicateurPresenceLamesNeige`, `EnVigueurDepuis`. | **Both languages.** | Route 101: segment **3001** Témiscaming → Saint-Édouard-de-Fabre, **3011** → Ville-Marie, 3021 → Notre-Dame-du-Nord. All "Bare and dry", visibility good. |

### Ontario — Ontario 511 API (Ministry of Transportation), Open Government Licence – Ontario
`https://511on.ca/api/…?format=json&lang=en|fr&key=…`. Key required; **10 calls per 60 s**. Province-wide answers (no area filter); we keep what's ours.

| Endpoint | What it is | Language | On 2026-10-23 near us |
|---|---|---|---|
| `v2/get/event` | Closures, incidents, short roadwork: `ID`, `RoadwayName` (`HWY 63`; French `RTE 63`), `EventType` (`roadwork`, `closures`, `accidentsAndIncidents`), **`IsFullClosure`**, `Description`, `LanesAffected`, `StartDate`, `PlannedEndDate` (Unix time), `Latitude/Longitude` (+ secondary), `EncodedPolyline`. | **Both languages** from Ontario (`lang=fr` gives its own French, e.g. "Inspection technique continue sur RTE 533…"). | Nothing on 63. Seven items on Highways 11, 17 and 533 around North Bay and Mattawa (left out). |
| `v2/get/constructionprojects` | Longer construction projects: same fields minus severity; `RoadwayName` is just the number (`"64"`). | Both. | Nothing on 63 (projects on 11 and 64). |
| `v3/get/roadconditions` | One line per stretch: `RoadwayName` `"63"`, `LocationDescription` **"From North Bay to Thorne"** / "De North Bay à Thorne", `Condition` (list: "Bare and dry road" / "Dégagée et sèche"; elsewhere "No Report"), `Visibility`, `Drifting`, `LastUpdated`, `EncodedPolyline` (the route's line). | Both. | Highway 63: bare and dry, visibility good, no drifting. |
| `v2/get/cameras` | Camera list: `Roadway`, `Location`, lat/lon, `Views` (image URL `511on.ca/map/Cctv/<id>`, direction). | English labels. | **Highway 63 at Wyse Road** (Thorne, across the bridge from town: looking north, looking south) and **Highway 63 at Highway 533** (looking east). |
| `v2/get/alerts` | Province-wide messages by region. | Both. | Empty. |

### Town — Work Info pages
| Finding | Consequence |
|---|---|
| `/fr/info-travaux`, `/en/work-info`: each item has a numeric ID shared by both languages, a title, `<time datetime="2026-10-01 00:00:00">` and "En vigueur du jeudi 1 octobre 2026 au samedi 31 octobre 2026." / "In effect from Thursday October 1, 2026 to Saturday October 31, 2026." The list's text is cut off ("…"); the full text is on each item's page. Past items drop off the list. One item (1019, water-system flushing). Some items have a map point (757, Kipawa Road, 2024). | Read both lists, then each listed item's page in both languages. Not all items are about roads; we show them all, as the Town's own category. |

### Findings that shape the design
| Finding | Consequence |
|---|---|
| The Quebec box filter must be written **latitude first** (`bbox=46.2,-80.0,47.5,-78.5,urn:ogc:def:crs:EPSG::4326`). Longitude first returns nothing, silently. | The parser test checks the request URL; a valid empty answer is never trusted on its own (D3). |
| "Nothing near us" is the normal answer for closures and roadworks in both provinces. | An empty list is **not** a failure for those (unlike fire bans). Missing road conditions for our roads are (D3). |
| The first Quebec capture got an HTTP 400 from one layer; the next run worked. | Each request is recorded separately; one failure doesn't block the others. |
| Ontario's "full closure" is a yes/no field; Quebec's is a phrase. | D2. |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **What counts as "our stretch"** | **Route 101:** a fixed line from Témiscaming to Ville-Marie, taken once from the ministry's segments 3001 + 3011 (simplified, stored in code). A Quebec item counts when any point is **within 1 km of that line**, or **within 10 km of the town centre**. Winter conditions: route-101 segments on that line (today 3001, 3011). **Highway 63:** an Ontario item counts when its road is 63 (`HWY 63`, `RTE 63`, `63`; not 630 or 163), or any point is within 1 km of Highway 63's line (from Ontario's own road-conditions line, stored in code), or within 10 km of the town centre. Highways 11 and 17 inside North Bay are left out. | Matching by location works even when Quebec leaves the route number blank. The roadwork just north of Ville-Marie (1.17 km from the line) stays out: the owner chose "to Ville-Marie". It is a test case, being close to the limit. |
| D2 | **Kinds of item** | **Closure:** Quebec `entrave` starting with "Fermeture" without *voie, accotement, bretelle, stationnement* (lane, shoulder, ramp, parking); Ontario `IsFullClosure: true`. **Incident:** any other Quebec road warning; Ontario `closures` / `accidentsAndIncidents` that aren't full. **Roadwork:** other roadworks and construction projects. **Town work:** Work Info items. | Only a full closure pushes (DESIGN §6.7). "One of two lanes closed" is not a closure. |
| D3 | **Reading the answers (silence ≠ safety)** | Quebec: a GeoJSON FeatureCollection with `numberMatched`; Ontario: a JSON array. Anything else (bad JSON, an error page, HTTP error, missing geometry) → **failure**: previous items kept, health goes red. **Quebec winter conditions, 15 Oct–15 Apr:** no route-101 segment on our line → failure; outside that season → "not published in summer" (neither a failure nor "clear"). **Ontario road conditions:** no Highway 63 line → failure; "No Report" is shown as "No report", never as "clear". Town list: page title and list container present; zero items is valid. | Same principle as every source, adjusted to roads, where "nothing" is the normal state. |
| D4 | **Schedule, health, rate limit** | `pollRoads` **every 15 min**: 3 Quebec requests + 6 Ontario requests (events, construction, conditions × FR/EN) spaced **7 s apart** (about 40 s per run; never more than 9 Ontario calls in 60 s). Camera list once a day (1 call). Health: `sources/mtmd-warnings`, `mtmd-roadworks`, `mtmd-conditions`, `on511-events`, `on511-construction`, `on511-conditions`; red after **1 h**. `pollTownWorkInfo` **hourly**: 2 lists + 2 pages per listed item, 2 s apart; `sources/town-work-info`, red after **3 h**. | Closures matter within the hour; the Town posts work a day or more ahead. Respecting Ontario's limit is a "done means" item (DESIGN §6.7). |
| D5 | **"In effect" (a safety claim)** | Quebec warnings: from `enVigueurDepuis` until removed (no end date exists; `duree` is shown as written, never parsed). Quebec roadworks, Ontario events and projects: "Planned" before their start, "In effect" from start until they're removed; their planned end is shown as "expected until …" but an item still listed after it stays shown. Items starting more than **14 days** ahead aren't shown. Town items: "Planned" before their start date, "In effect" until their end date, hidden after it. | DESIGN §8: never "in effect" or "all clear" on a guess; "announced isn't in effect". Ontario keeps long projects open past their planned end. |
| D6 | **Language** | Quebec winter conditions and roadworks, all Ontario text: the ministries' own FR/EN. Quebec road warnings: **our own FR/EN labels** for the kind (*Route fermée / Road closed*, *Une voie sur deux fermée / One of two lanes closed*, *Circulation en alternance / Alternating traffic*, else *Avertissement routier / Road warning*); place names as given; the ministry's `localisation`, `cause`, `duree`, `detour` under "Disponible en français seulement / Available in French only". Town items: FR and EN pages, one-language items labelled as usual. Road names: *Route 101* in both; *route 63* (FR) / *Highway 63* (EN). | DESIGN §5: no machine translation presented as official. |
| D7 | **Push: when** | Opt-in only. Push when a **closure on our stretch first appears**, and a quieter push when it **reopens** (removed, or a planned closure's end has passed and it's gone). A closure first seen as planned pushes once ("closed from Tuesday 7 p.m."), not again when it starts. Same closure re-posted within 6 h → no new push. Incidents, roadworks, conditions, Town work → **no push**. The first run after a deploy records without pushing. | "Notifications only when they earn it" (principle 5); mirrors fire bans. |
| D8 | **Push: wording, topics, channel** | Our templates, e.g. *"Route 101 fermée à Saint-Édouard-de-Fabre"* / *"Route 101 closed at Saint-Édouard-de-Fabre"*; *"Route 63 fermée (Ontario)"* / *"Highway 63 closed (Ontario)"*; *"… rouverte"* / *"… reopened"*. Topics **`roads-fr`, `roads-en`**. Android channel **`roads`** at **high** importance (pop-up). | DESIGN §5. Only people who chose it get it, and a closure of one of the two roads out of town changes plans now. |
| D9 | **Opt-in** | One Settings toggle **"Road closures (Route 101 and Highway 63)"**, **off by default for everyone**, new installs included (the first-launch notification step doesn't turn it on). The Roads screen shows "Get notified when Route 101 or Highway 63 closes" with a switch. | DESIGN §3: roads are opt-in only. |
| D10 | **Highway 63 cameras** | On the Roads screen, the two Highway 63 cameras (Wyse Road: north and south views; Highway 533: east view) as images, credited "Ontario 511". The phone loads each image **only when the Roads screen is open**, straight from Ontario 511 (images can't sensibly go through our backend), with a "Tap to refresh" and the time the image was loaded. If an image fails: "Camera not available" + link. Quebec cameras: not now. | The Wyse Road camera shows the road right across the bridge; useful in a snowstorm. One image request per view, only on demand, is far lighter than a browser visit to 511on.ca. |
| D11 | **Today** | Amber road card (red stays for boil water and fire bans) only when, on our stretch: a closure, an incident, or conditions that aren't fine. Not fine = Quebec surface other than bare (dry or wet) or visibility other than good; Ontario condition other than "Bare and dry road" / "Bare and wet road" / "No Report", visibility other than good, or drifting. One line per problem, max 3, tap → Roads screen. If any road check is red: "Couldn't check roads since …". Otherwise no card. Town work and plain roadworks never appear on Today. | DESIGN §7: "road status if anything's wrong". Ordinary roadworks would sit on Today all summer. |
| D12 | **Roads screen** | Sections: **Route 101 · Témiscaming – Ville-Marie** and **Highway 63 · Thorne – North Bay**, each with closures and incidents first, then conditions ("since …"), then roadworks; cameras under Highway 63 (D10). Then **Town work** (Work Info). Each item: kind, status, place, dates, source text, link (Québec 511, Ontario 511 or the Town's page). "Nothing reported on this stretch" only after a successful check. Credits: "Ministère des Transports et de la Mobilité durable (CC BY 4.0)", "Contains information licensed under the Open Government Licence – Ontario; Ontario 511, provided as is". Health line per section. | Principle 2: relay, don't replace. Ontario asks that its as-is disclaimer be passed on. |
| D13 | **More tab** | Fourth tab **More** (*Plus*): Roads, Fire, Weather, Pickup schedule, Settings. The Today cards keep opening their screens as now; the gear icon on Today stays. About comes later (Milestone 9). | Owner's choice (2026-10-22); DESIGN §7 tabs. |
| D14 | **Firestore shape** | `roads/{id}` one doc per item (`qc-warning-<id>`, `qc-roadwork-<id>`, `on-event-<ID>`, `on-construction-<ID>`, `town-<id>`); `road_conditions/route-101` and `road_conditions/highway-63`; `road_cameras/highway-63` (camera list). Public read on all three. Items that disappear from the source are deleted (after a reopen push for closures). | Same pattern as alerts and events. |
| D15 | **The Ontario key** | Stored as a **Firebase secret** `ONTARIO_511_KEY` (`firebase functions:secrets:set ONTARIO_511_KEY`), read only by `pollRoads`; never in the repo, the app, logs or Firestore (error messages have it replaced by `***`). The capture workflow uses the GitHub secret of the same name. | The repo is public; the key is tied to the owner's account. |

---

## 4. Files touched

```
functions/
  src/roads/corridor.ts      NEW — Route 101 and Highway 63 lines, "on our stretch" tests (D1)
  src/roads/quebec.ts        NEW — parse the three MTMD layers (D3), kinds (D2), status (D5)
  src/roads/ontario.ts       NEW — parse Ontario 511 events, projects, conditions, cameras; FR/EN pairing by ID; polyline decoding
  src/roads/town.ts          NEW — parse Work Info list + item pages, FR/EN pairing by ID, dates
  src/roads/sync.ts          NEW — runRoadsPoll (paced Ontario calls, D4) / runTownWorkInfoPoll: fetch, compare, save, push (D7)
  src/weather/geo.ts         + distance from a point to a line (km)
  src/push/templates.ts      + road templates (FR/EN)
  src/adapters.ts            + Firestore stores for roads; channel ID roads
  src/index.ts               + pollRoads (15 min, secret ONTARIO_511_KEY), pollTownWorkInfo (hourly)
  test/roads-*.test.ts       NEW — parse, corridor, status, rate limit, whole runs
  test/fixtures/roads/       real captures (2026-10-22, 2026-10-23) + hand-made ones marked as such
firestore.rules              + public read on roads/, road_conditions/, road_cameras/
lib/roads/                   NEW — road_data.dart, roads_repository.dart, roads_card.dart, roads_screen.dart, road_camera.dart
lib/home/home_shell.dart     + More tab
lib/more/more_screen.dart    NEW — Roads, Fire, Weather, Pickup schedule, Settings
lib/home/today_screen.dart   + road card (D11)
lib/push/push_service.dart   + roads-fr / roads-en topics
lib/settings/…, lib/settings_screen.dart  + "Road closures" toggle (off by default)
android/…                    channel roads (name from ARB)
lib/l10n/app_fr.arb, app_en.arb  + all roads and More text
test/roads/…, test/more/…    NEW — widget tests, screenshot cases
README.md                    + Roads lines (Ontario key as a Firebase secret, fixtures, logs, test push)
```

---

## 5. Data shapes

`roads/{id}` (normalized item, DESIGN §4)
```
{ id, source: "mtmd-warnings" | "mtmd-roadworks" | "on511-events" | "on511-construction" | "town-work-info",
  kind: "closure" | "incident" | "roadwork" | "town",
  road: "101" | "63" | null, place,
  title_fr, title_en, body_fr, body_en, original_language,
  source_url, published_at, starts_at, ends_at,        // ends_at = planned end; null for Quebec warnings
  status: "planned" | "in_effect",                     // D5, recomputed each run
  on_today: bool,                                      // D11
  pushed: { kind: "closed" | "reopened", at } | null } // backend only (D7)
```
`road_conditions/route-101`, `road_conditions/highway-63`
```
{ segments: [ { from_fr, from_en, to_fr, to_en,              // Ontario: from its LocationDescription
                surface_fr, surface_en, surface_ok: bool,
                visibility_fr, visibility_en, visibility_ok: bool,
                drifting: bool | null, no_report: bool, since } ],
  in_season: bool,                                          // Quebec only
  checked_at }
```
`road_cameras/highway-63`: `{ cameras: [ { location, lat, lon, views: [ { image_url, direction_fr, direction_en } ] } ], checked_at }`
Health docs: the usual fields; `last_item_count` = items on our stretch (0 is valid, D3).

---

## 6. Behaviour

### Backend
`pollRoads` (15 min): Quebec layers with the box, then Ontario calls 7 s apart (each request in its own try/catch) → parse (D3) → keep our stretch (D1) → kinds (D2), status (D5) → save → push on closure changes (D7). Camera list refreshed on the first run after 3 a.m. Log `roads: qc warnings ok (0), qc roadworks ok (0), qc conditions ok (2), on events ok (0), on construction ok (0), on conditions ok (1)`.
`pollTownWorkInfo` (hourly): both lists → each item's page in both languages, 2 s apart → save; delete items gone from the list.

### App
- **Today:** amber road card or the stale warning (D11).
- **More → Roads:** D12, with cameras (D10). Offline: Firestore cache plus the "last checked" lines; camera images say they need a connection.
- **Settings:** "Road closures" toggle (D9).

---

## 7. Out of scope for this milestone
Quebec road cameras; maps drawn in the app; Route 101 beyond Ville-Marie; Highways 11 and 17 in and around North Bay; Ontario's province-wide alerts; Chemin Kipawa and other municipal roads except through the Town's Work Info; snow-removal and winter-parking notices (they're Town news); pushes for Town work; the About screen.

---

## 8. Verification ("done means")
1. Backend tests on fixtures:
   - Real files: Quebec 2026-10-22 → 0 warnings and 0 roadworks on our stretch (the Duhamel-Ouest roadwork and the Rouyn-Noranda warning both left out), 2 winter segments "bare and dry". Ontario 2026-10-23 → 0 events and 0 projects on Highway 63 (the Highway 11, 17, 533 and 64 items left out), Highway 63 "bare and dry" in both languages, 2 cameras / 3 views on Highway 63. Town → item 1019 paired FR/EN, in effect 1–31 Oct.
   - Hand-made (marked as such): a Quebec *Fermeture* on Route 101 at Saint-Édouard-de-Fabre with blank `numeroRoute` → closure; *Fermeture de 1 voie sur 2* → incident; a Quebec roadwork closure planned next week → "planned"; segment "Glacée" → on Today; an Ontario `HWY 63` event with `IsFullClosure: true` → closure; an Ontario Highway 630 event → left out; Ontario "Snow packed" with drifting → on Today; "No Report" → not on Today, not "clear"; empty Quebec conditions in season → failure, in summer → not published; Ontario conditions without 63 → failure; bad JSON / error page / HTTP 401 → failure, previous items kept, key not in the error.
   - Whole runs: a closure appears → one push per language; re-post within 6 h → none; removed → one "reopened" push; first run after deploy → none. **Rate limit:** with a fake clock, a run never makes more than 9 Ontario calls in any 60 s.
2. App analyze + tests + iOS build green on CI; screenshots reviewed in both languages (nothing reported, closure on each road, icy road, Ontario "No report", cameras, Town work, stale, summer, More tab, 200% text).
3. On the Android emulator: backend deployed with the key as a Firebase secret and logging ok; the Roads screen matches Québec 511's and Ontario 511's maps and the Town's Work Info page; cameras show; a test push to `roads-fr` / `roads-en` arrives on the `roads` channel.
4. When the first real closure or bad-weather report on either road happens: capture it as a fixture and compare with the hand-made ones.

---

## 9. DESIGN.md changes on approval
§6.7 sources (three MTMD layers, latitude-first box, Ontario 511 endpoints and key, Town Work Info), our stretches, closure rule, cameras, opt-in push; §4 stack (`pollRoads`, `pollTownWorkInfo`, `roads` / `road_conditions` / `road_cameras` collections, `roads-fr/en` topics, `roads` channel, health thresholds, Firebase secret); §7 More tab and Today road card; §10 Ontario 511 key (obtained 2026-10).

---

## 10. Implementation notes (2026-10-27, backend)

- **"Reopened" waits 25 minutes instead of the 6-hour re-post rule (changes D7).** Each closure is tracked by road + place, with what people were last told. "Reopened" goes out only once the closure has been gone for 25 minutes (two runs) and every source that reported it was read successfully since. So a closure the ministry deletes and re-posts sends nothing at all, and a real re-closure after a reopening always pushes. The 6-hour rule would have silenced a genuine second closure on the same day: on a safety feature, a missed "closed" is worse than an extra push.
- What people were last told lives in a backend-only document, `roads_state/pushes` (not on each item, as §5 had it), so items can be deleted as soon as the source drops them.
- Ontario events have no place field (it's buried in the description), so Highway 63 pushes say "Highway 63 (Ontario) closed" without a place; the description is in the app.
- Road lines for D1 are in `functions/src/roads/corridor.ts`, simplified to within 50 m of the ministries' own lines.
- Tests: 44 new (199 backend tests in all): real captures from both provinces and the Town, 14 hand-made files (`test/fixtures/roads/hand-made/`, see its README), whole runs with a fake clock (pushes, 25-minute reopen, Ontario failing, rate limit, key never in logs or health records).

## 11. Implementation notes (2026-10-27, app)

- `lib/roads/`: `road_data.dart` (items, segments, cameras as stored), `roads_repository.dart` (Firestore listeners for `roads`, `road_conditions`, `road_cameras/highway-63` and the seven `sources/…` health docs; health = never checked / recent / failing per D4), `roads_widgets.dart` (Today card, item cards, condition lines, camera tiles), `roads_screen.dart` (Roads screen, item screen). `lib/more/more_screen.dart`: the More tab.
- Today's card shows only when D11 says so; on a failing check without problems it's a plain card with the red "Couldn't check roads since …" line. Up to 3 lines, then "+N".
- "Nothing reported on this stretch" needs a recent read of that road's *item* sources (warnings and roadworks, or Ontario events and construction); a stale conditions source only shows in the health line.
- Conditions with missing flags count as "worth a look", never as fine; Ontario "No Report" shows as "No report for this stretch".
- Camera images load straight from Ontario 511 only while the Roads screen is open; tapping a camera refreshes it (the cached picture is dropped first). Tests and screenshots use a stand-in image.
- Road closures: `AppSettings.roadClosuresEnabled` (saved as `road_closures`), off by default and never turned on by the notifications question; topics `roads-fr` / `roads-en`; Android channel `roads` (high importance). A tap on a road push (`screen: roads`) opens the Roads screen.
- The Today placeholder now says only power outages are still to come; the notifications question mentions that road closures are opt-in.
