// The three weather readers on the saved data (spec weather §8 step 1).
// Fixture captured 2026-10-21 00:25 in Témiscaming (04:25 UTC).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { parseAlerts } from "../src/weather/alerts";
import { parseCityPage } from "../src/weather/conditions";
import { parseForecast } from "../src/weather/forecast";

const DIR = join(__dirname, "fixtures/weather/2026-10-21-0025");
const load = (name: string) => JSON.parse(readFileSync(join(DIR, name), "utf-8"));
const NOW = new Date("2026-10-21T04:30:00Z");

describe("parseCityPage (qc-139)", () => {
  it("reads the Barrage Témiscaming station in both languages", () => {
    const p = parseCityPage(load("qc-139.json"));
    expect(p.site_id).toBe("qc-139");
    expect(p.station_fr).toBe("Barrage Témiscaming");
    expect(p.station_en).toBe("Temiskaming Dam");
    expect(p.eccc_url_fr).toMatch(/^https:\/\/meteo\.gc\.ca\//);
    expect(p.eccc_url_en).toMatch(/^https:\/\/weather\.gc\.ca\//);
    expect(p.conditions).toEqual({
      observed_at: new Date("2026-10-21T04:00:00Z"),
      temperature_c: 1.9,
      // At night the station sends no condition text and no icon: null, never a guess.
      condition_fr: null,
      condition_en: null,
      eccc_icon: null,
      wind_kmh: 3,
      wind_dir: "SE",
      gust_kmh: 27,
      wind_chill: -4,
      humidex: null,
      humidity_pct: 92,
    });
  });

  it("reads the condition text when the station sends it", () => {
    const page = load("qc-139.json");
    page.properties.currentConditions.condition = { en: "Mostly Cloudy", fr: "Généralement nuageux" };
    page.properties.currentConditions.iconCode.value = 3;
    const c = parseCityPage(page).conditions;
    expect([c.condition_fr, c.condition_en, c.eccc_icon]).toEqual(["Généralement nuageux", "Mostly Cloudy", 3]);
  });

  it("fails on a page without current conditions or an observation time", () => {
    const empty = load("qc-139.json");
    empty.properties.currentConditions = {};
    expect(() => parseCityPage(empty)).toThrow(/no current conditions/);
    const noTime = load("qc-139.json");
    delete noTime.properties.currentConditions.timestamp;
    expect(() => parseCityPage(noTime)).toThrow(/no observation time/);
    expect(() => parseCityPage({ type: "FeatureCollection" })).toThrow(/no properties/);
  });

  it("fails rather than show Fahrenheit as Celsius", () => {
    const page = load("qc-139.json");
    page.properties.currentConditions.temperature.units = { en: "F", fr: "F" };
    expect(() => parseCityPage(page)).toThrow(/expected C/);
  });
});

describe("parseForecast (Open-Meteo)", () => {
  it("reads 7 days for Témiscaming", () => {
    const { days, warnings } = parseForecast(load("forecast.json"));
    expect(warnings).toEqual([]);
    expect(days.map((d) => d.date)).toEqual([
      "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27",
    ]);
    expect(days[0]).toEqual({
      date: "2026-10-21", wmo_code: 3, high_c: 16.3, low_c: -0.9,
      precip_mm: 0, rain_mm: 0, snow_cm: 0,
      wind_max_kmh: 10.1, gust_max_kmh: 31.3, wind_dir_deg: 203,
      sunrise: "2026-10-21T07:42", sunset: "2026-10-21T18:18",
    });
  });

  it("fails on changed units, another place, or missing days", () => {
    const units = load("forecast.json");
    units.daily_units.temperature_2m_max = "°F";
    expect(() => parseForecast(units)).toThrow(/expected "°C"/);

    const elsewhere = load("forecast.json");
    elsewhere.latitude = 47.39; // Ville-Marie
    expect(() => parseForecast(elsewhere)).toThrow(/not Témiscaming/);

    const short = load("forecast.json");
    for (const k of Object.keys(short.daily)) short.daily[k] = short.daily[k].slice(0, 3);
    expect(() => parseForecast(short)).toThrow(/3 days, expected 7/);

    const uneven = load("forecast.json");
    uneven.daily.rain_sum.pop();
    expect(() => parseForecast(uneven)).toThrow(/rain_sum/);

    const hole = load("forecast.json");
    hole.daily.temperature_2m_min[4] = null;
    expect(() => parseForecast(hole)).toThrow(/day 5/);

    expect(() => parseForecast({ error: true, reason: "Cannot initialize WeatherVariable" }))
      .toThrow(/Cannot initialize/);
  });

  it("keeps the day but warns on an unknown weather code", () => {
    const f = load("forecast.json");
    f.daily.weather_code[2] = 42;
    const { days, warnings } = parseForecast(f);
    expect(days[2].wmo_code).toBe(42);
    expect(warnings).toEqual(["forecast 2026-10-23: unknown weather code 42"]);
  });
});

describe("parseAlerts (ECCC)", () => {
  const zones = load("zones-town.json").features;
  const zone = (name: string) => zones.find((z: { properties: { NAME: string } }) => z.properties.NAME === name).geometry;
  /** A real frost advisory from tonight, moved onto a zone near town. */
  const qcAlerts = load("alerts-qc.json").features;
  const realAlert = (geometry: unknown, patch: Record<string, unknown> = {}, idSuffix = "fea1-922") => ({
    ...qcAlerts[0],
    id: `${qcAlerts[0].id.split("_")[0]}_${idSuffix}`,
    geometry,
    properties: { ...qcAlerts[0].properties, ...patch },
  });
  const collection = (features: unknown[]) => ({
    type: "FeatureCollection", features, numberMatched: features.length, numberReturned: features.length,
  });

  it("finds nothing for town tonight, and keeps none of Quebec's 22 advisories", () => {
    expect(parseAlerts(load("alerts-town.json"), NOW).alerts).toEqual([]);
    expect(parseAlerts(load("alerts-border.json"), NOW).alerts).toEqual([]);
    const qc = parseAlerts(load("alerts-qc.json"), NOW);
    expect(qc.areasNearby).toBe(22);
    expect(qc.alerts).toEqual([]);
  });

  it("keeps an alert whose area covers town, with ECCC's own text in both languages", () => {
    const { alerts, warnings } = parseAlerts(collection([realAlert(zone("Témiscamingue"))]), NOW);
    expect(warnings).toEqual([]);
    expect(alerts).toHaveLength(1);
    const a = alerts[0];
    expect(a.id).toBe("165538168887825634202610190504");
    expect(a.type).toBe("advisory");
    expect(a.colour).toBe("yellow");
    expect([a.title_fr, a.title_en]).toEqual(["Gel (avis)", "Frost (advisory)"]);
    expect(a.body_fr).toMatch(/^Les températures chuteront/);
    expect(a.body_en).toMatch(/^Temperatures will drop/);
    expect(a.expires_at).toEqual(new Date("2026-10-21T14:05:50.619Z"));
  });

  it("drops North Bay's alerts, ended ones and expired ones", () => {
    const tem = zone("Témiscamingue");
    const cases = [
      realAlert(zone("North Bay - West Nipissing")),
      realAlert(tem, { status_en: "ended", status_fr: "terminé" }),
      realAlert(tem, { status_en: "cancelled", status_fr: "annulé" }),
      realAlert(tem, { expiration_datetime: "2026-10-21T04:00:00.000Z" }),
    ];
    for (const c of cases) expect(parseAlerts(collection([c]), NOW).alerts).toEqual([]);
  });

  it("shows one alert once even when two areas both cover us", () => {
    const tem = zone("Témiscamingue");
    const { alerts } = parseAlerts(collection([realAlert(tem, {}, "fea1-922"), realAlert(tem, {}, "fea1-999")]), NOW);
    expect(alerts).toHaveLength(1);
  });

  it("puts warnings before advisories, and an unknown type in the banner with a warning", () => {
    const tem = zone("Témiscamingue");
    const warning = { ...realAlert(tem, { alert_type: "warning", alert_short_name_en: "Rainfall (warning)" }), id: "2_x" };
    // Issued later than tonight's frost advisory: among advisories, newest first.
    const odd = { ...realAlert(tem, { alert_type: "emergency", publication_datetime: "2026-10-21T04:20:00.000Z" }), id: "3_x" };
    const { alerts, warnings } = parseAlerts(collection([realAlert(tem), odd, warning]), NOW);
    expect(alerts.map((a) => [a.id, a.type])).toEqual([
      ["2", "warning"], ["3", "advisory"], ["165538168887825634202610190504", "advisory"],
    ]);
    expect(warnings).toEqual(['alert 3: unknown type "emergency", shown as an advisory']);
  });

  it("fails on a cut-short page or something that isn't a list of alerts", () => {
    const cut = { ...collection([realAlert(zone("Témiscamingue"))]), numberMatched: 600 };
    expect(() => parseAlerts(cut, NOW)).toThrow(/only 1 of 600/);
    expect(() => parseAlerts({ type: "Feature" }, NOW)).toThrow(/not a FeatureCollection/);
    expect(() => parseAlerts(null, NOW)).toThrow(/not a FeatureCollection/);
  });
});
