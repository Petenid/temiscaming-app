# Spec — Milestone 4: Weather

Status: **agreed** · 2026-10-21 (owner agreed all of §3). Rev. 2 · 2026-10-20 (forecast from Open-Meteo, owner request — "Ville-Marie's weather just isn't our weather")
Reads with: `DESIGN.md` (§2 principles, §4 architecture and source health, §5 language, §6.4 weather, §7 app structure)

---

## 1. Goal

1. The backend stores, for Témiscaming:
   - **current conditions** measured at the Barrage Témiscaming station, in town (Environment Canada, ECCC);
   - a **7-day forecast for Témiscaming's own coordinates** (Open-Meteo, computed from ECCC's weather models);
   - any **weather alerts** in effect for the town (ECCC: warnings, watches, advisories, statements).
2. **Today** shows a weather card (now + today's high/low) and, above it, a banner when an alert covers Témiscaming.
3. A **Weather screen** (opened from the card) shows conditions, the 7 days and the full text of each alert.
4. **Nothing pushes** (DESIGN §3).

---

## 2. What the sources actually look like (checked live 2026-10-20, 23:10–23:58)

### ECCC (MSC GeoMet OGC API, `api.weather.gc.ca`) — conditions and alerts
| Finding | Consequence |
|---|---|
| **ECCC writes no forecast for Témiscaming.** The nearest city page, `qc-139` "Témiscamingue", carries the forecast for the **"secteur de Ville-Marie / Ville-Marie area"** (~1 h 30 north). ECCC's own "Témiscaming, QC" web page shows that same text (identical wording and issue time). | Forecast comes from Open-Meteo instead (D1). |
| `qc-139`'s **current conditions come from "Barrage Témiscaming / Temiskaming Dam"** (46.71 N, 79.10 W, ~1 km from town). ECCC's Témiscaming page lists the same station first. | Keep ECCC for "right now": a real thermometer in town beats a model estimate. |
| The city-page JSON is bilingual side by side (`{"en": "Clear", "fr": "Dégagé"}`) and marked **"[experimental]"**. | Only `currentConditions` is read. Health catches a format change; Datamart XML is the fallback. |
| **Alerts** (`weather-alerts`, not experimental): each is a polygon with bilingual name, short name, full text, type (`warning` / `watch` / `advisory` / `statement`), colour, status (new / continued / ended…), issued, event end, **expiry**. | Alerts come from here (D2). |
| **The town sits on a zone border.** Town centre (46.721 N, 79.098 W) and Lumsden (46.735 N, 79.051 W) fall in the Quebec "Témiscamingue" zone; the dam station point falls in **"North Bay – West Nipissing" (Ontario)**. A rough box query returns both. | Exact point-in-polygon test on our two points (D2). |
| No alert covers Témiscaming tonight, so our alert area's name ("secteur de …") isn't confirmed yet. | Shown as ECCC gives it; check with the first real alert (§8). |

### Open-Meteo (`api.open-meteo.com/v1/gem`) — forecast
| Finding | Consequence |
|---|---|
| The GEM endpoint blends **ECCC's own models**: HRDPS 2.5 km (2 days, every 6 h), RDPS 10 km (3.5 days), GEM Global (10 days), into one series for any point. | A forecast for Témiscaming's coordinates, from Environment Canada's science, at 2.5 km for the next 2 days. |
| Daily values: high/low, precipitation, rain and snow amounts, max wind and gusts, sunrise/sunset, and a **WMO weather code** (the day's worst condition). No forecast text. The GEM page lists **no precipitation probability**. | We write our own FR/EN labels for the WMO codes (allowed by DESIGN §5, like the road codes). Show amounts ("5 mm", "3 cm of snow"), not a %. |
| **It's an unreviewed computer forecast**, unlike ECCC's forecaster-written text. Models update every 6 h. | Label it plainly: "Prévision automatique pour Témiscaming" / "Computer forecast for Témiscaming" (D1). |
| Terms: free for **non-commercial** use (non-profit apps without ads or subscriptions qualify), < 10,000 calls/day, **CC BY 4.0 attribution required**, no warranty or uptime promise. Limits count per IP, and shared cloud hosts can hit them sooner. | 24 calls/day is trivial. Attribution line on the Weather screen and in About. Revisit if the app ever earns money (§10 open question). |
| No weather warnings of any kind. | ECCC stays the only alert source. |

---

## 3. Decisions to confirm

| # | Decision | Proposal | Why |
|---|---|---|---|
| D1 | **Forecast source** | Open-Meteo GEM endpoint at **46.7213, −79.0975**, `timezone=America/Toronto`, 7 days, daily: `weather_code`, `temperature_2m_max/min`, `precipitation_sum`, `rain_sum`, `snowfall_sum`, `wind_speed_10m_max`, `wind_gusts_10m_max`, `wind_direction_10m_dominant`, `sunrise`, `sunset`. Shown as **"Computer forecast for Témiscaming · Open-Meteo, Environment Canada models (CC BY 4.0)"**, with a link to ECCC's page for the official regional text. | A forecast for here, not Ville-Marie, still from ECCC's models. Honest about being automatic (principles 2 and 3). |
| D2 | **Which alerts count as ours** | Query `weather-alerts` with a small box around town, keep an alert only if its polygon **contains the town centre or Lumsden** (exact point-in-polygon, holes handled). Drop ended/cancelled and anything past `expiration_datetime`. All four types kept. | Precise at the Ontario border both ways; covers both collection sectors. |
| D3 | **Schedules** | Two functions. `pollWeather` **every 15 min**: ECCC conditions then alerts, each in its own try/catch with health `sources/eccc-conditions` and `sources/eccc-alerts`. `pollForecast` **every hour**: Open-Meteo, health `sources/open-meteo-forecast`. Red after **1 h** (alerts), **3 h** (conditions), **8 h** (forecast; models update every 6 h). | Alerts change fastest; the forecast changes 4×/day. A failure in one never hides the others. Gentle on both servers (principle 4). |
| D4 | **Banner on Today** | When ≥ 1 warning, watch or advisory: a banner above the bin card with the type and ECCC's short name in the user's language ("Avertissement de pluie verglaçante" / "Freezing rain warning"), "+1 more" if several; tap → Weather screen. **Amber, not the urgent red**, with an icon and the type written out. Statements show on the Weather screen only. | Red is reserved for boil water and fire bans (DESIGN §7). Statements would make the banner cry wolf. |
| D5 | **Silence ≠ safety** | If the alerts source is stale, Today shows "Couldn't check weather alerts since [time]". "No weather alerts" appears only on the Weather screen, and only after a successful check within the hour. | Principle 3; DESIGN §8 "Nothing here is a claim too". |
| D6 | **Labels and icons** | One tested table maps codes to our own label + Material icon: WMO codes (forecast, ~28 codes → ~15 labels in the ARB files, e.g. 71 "Faible neige" / "Light snow"), and ECCC icon codes (conditions; ECCC's own condition text is shown). | Our bilingual wording for codes; avoids ECCC's icon terms; text always beside the icon. |
| D7 | **Old observations** | Observation **older than 3 h** → hide the temperature, say "No recent reading from the station". | A frozen value looks like the present. |
| D8 | **Units and formatting** | °C, km/h, mm and cm; times in America/Toronto, formatted fr-CA / en-CA. | DESIGN §5. |
| D9 | **Firestore shape** | One document `weather/temiscaming`; each function updates only its own fields (merge). Public read. | One read for the app, offline cache, nothing to clean up. |
| D10 | **Forecast vs. ECCC's text** | The ECCC regional forecast is **not** shown in the app, only linked ("Environment Canada's official forecast for the region"). | Two different forecasts side by side would confuse; the link keeps the official one a tap away (principle 2). |

---

## 4. Files touched

```
functions/
  src/weather/conditions.ts  NEW — ECCC city page → Conditions (pure)
  src/weather/alerts.ts      NEW — ECCC alert features → Alert[], filtered by geo.ts (pure)
  src/weather/geo.ts         NEW — point-in-polygon (Polygon + MultiPolygon, holes), our two points
  src/weather/forecast.ts    NEW — Open-Meteo JSON → Day[] (pure; checks units and array lengths)
  src/weather/sync.ts        NEW — runWeatherPoll (conditions + alerts), runForecastPoll
  src/adapters.ts            + firestoreWeatherStore; fetcher gets a JSON helper
  src/index.ts               + pollWeather (15 min), pollForecast (hourly), Montréal region
  test/weather-*.test.ts     NEW — parse, geo, whole runs (ok, alert in/out of town, ended/expired, stale station, failures)
  test/fixtures/weather/<date>/  NEW — saved by the capture workflow
firestore.rules              + public read on weather/{doc}
.github/workflows/capture-fixtures.yml  + "weather": qc-139, alerts around town, all current QC alerts (real polygons), Open-Meteo forecast
lib/weather/                 NEW — weather_data.dart, weather_repository.dart, weather_card.dart,
                                   weather_alert_banner.dart, weather_screen.dart, weather_codes.dart
lib/home/today_screen.dart   + banner and card
lib/l10n/app_fr.arb, app_en.arb  + labels, WMO-code labels, attribution
test/weather/...             NEW — widget tests, code-table test (every WMO code has FR+EN), screenshot cases
README.md                    + "Weather" troubleshooting lines
```

---

## 5. Data shapes

`weather/temiscaming`
```
{
  // ECCC conditions (pollWeather)
  station_fr: "Barrage Témiscaming", station_en: "Temiskaming Dam",
  conditions: { observed_at, temperature_c, condition_fr, condition_en, eccc_icon,
                wind_kmh, wind_dir, gust_kmh, wind_chill, humidex, humidity_pct } | null,
  conditions_checked_at, eccc_url_fr, eccc_url_en,
  // ECCC alerts (pollWeather)
  alerts: [ { id, type: "warning"|"watch"|"advisory"|"statement", colour,
              title_fr, title_en, area_fr, area_en, body_fr, body_en,
              published_at, ends_at, expires_at, source_url } ],
  alerts_checked_at,
  // Open-Meteo forecast (pollForecast)
  forecast_model_run_at,   // when Open-Meteo generated it
  days: [ { date: "2026-10-21", wmo_code, high_c, low_c, precip_mm, rain_mm, snow_cm,
            wind_max_kmh, gust_max_kmh, wind_dir_deg, sunrise, sunset } ],   // 7
  forecast_checked_at
}
```
Health docs: the usual `last_success_at`, `last_attempt_at`, `last_item_count`.

Failure rules: conditions with no `currentConditions` block → failure; a station that's present but old → success with D7 applied. Alerts: **zero is normal**; failure = download/JSON error or not a FeatureCollection. Forecast: fewer than 7 days, mismatched array lengths, or units other than °C/mm/cm/km/h → failure (previous forecast kept). One step's failure never touches another step's fields.

---

## 6. Behaviour

### Backend
- `pollWeather` (15 min): GET `qc-139` → conditions; GET alerts in box (−79.20, 46.65, −78.95, 46.80) → filter (D2). Log `weather: conditions ok, alerts ok (0)`.
- `pollForecast` (hourly): GET Open-Meteo (D1) → 7 days. Log `forecast: ok (7 days)`.

### App
- **Today:** alert banner (D4) or stale-alerts warning (D5) at the top; weather card: icon, temperature, ECCC condition, "Feels like" when wind chill/humidex, then "Today: high 14°, low 7°" with our label. Tap → Weather screen.
- **Weather screen:** alerts (full ECCC text, area, times, link) → now (station name, reading time) → 7 days (label, icon, high/low, rain/snow amounts, wind if strong) → sources (station; "Computer forecast for Témiscaming" + Open-Meteo attribution; link to ECCC's official regional forecast; "last checked" times).
- Offline: last cached document with its times.

---

## 7. Out of scope for this milestone
Hourly forecast, radar/maps, air quality, UV, displaying ECCC's regional text forecast, push for weather, imperial units, other locations, a Weather tab (DESIGN §7 tabs unchanged).

---

## 8. Verification ("done means")
1. Backend tests on saved fixtures: conditions parse in both languages; Open-Meteo parses to 7 days; an alert covering town is kept, a North Bay–only one dropped, ended/expired dropped; an old station reading is flagged; failures keep previous data and mark health.
2. App analyze + tests + iOS build green on CI; screenshots reviewed in both languages, with and without an alert, stale sources, 200% text; every WMO code has a French and English label.
3. On the Android emulator: both functions deployed and logging ok; the card's temperature matches ECCC's Témiscaming page; the 7 days match Open-Meteo's page for the same coordinates.
4. Next time ECCC issues an alert for our area: it appears within 15 minutes; save it as a fixture and confirm the area name.

---

## 9. DESIGN.md changes on approval
§6.4 source and behaviour; §4 stack (two weather functions, `weather` collection); §10 open question: Open-Meteo's non-commercial terms if the app ever earns money or the Town takes it over commercially.
