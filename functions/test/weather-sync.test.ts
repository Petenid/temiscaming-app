// Whole weather runs against the saved data, with an in-memory database
// (spec weather §8 step 1): each step saves only its own fields and health,
// and a failure in one leaves the others alone.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { Fetcher } from "../src/alerts/sync";
import {
  ALERTS_URL, CITY_PAGE_URL, runForecastPoll, runWeatherPoll, WeatherHealth, WeatherSourceId, WeatherStore,
} from "../src/weather/sync";
import { FORECAST_URL } from "../src/weather/forecast";

const DIR = join(__dirname, "fixtures/weather/2026-10-21-0025");
const file = (name: string) => readFileSync(join(DIR, name), "utf-8");

/** Serves the saved files by URL; `override` replaces a response or makes it fail. */
function fetcher(override: Record<string, string | Error> = {}): Fetcher {
  const files: Record<string, string> = {
    [CITY_PAGE_URL]: file("qc-139.json"),
    [ALERTS_URL]: file("alerts-town.json"),
    [FORECAST_URL]: file("forecast.json"),
  };
  return {
    async get(url) {
      const r = url in override ? override[url] : files[url];
      if (r === undefined) throw new Error(`unexpected URL ${url}`);
      if (r instanceof Error) throw r;
      return new TextEncoder().encode(r);
    },
  };
}

class FakeWeatherStore implements WeatherStore {
  doc: Record<string, unknown> = {};
  health = new Map<WeatherSourceId, WeatherHealth>();
  failSave = false;
  async saveWeather(fields: object) {
    if (this.failSave) throw new Error("Firestore unavailable");
    this.doc = { ...this.doc, ...structuredClone(fields) };
  }
  async loadHealth(id: WeatherSourceId) { return this.health.get(id) ?? null; }
  async saveHealth(id: WeatherSourceId, h: WeatherHealth) { this.health.set(id, h); }
}

const at = (iso: string) => () => new Date(iso);
const RUN = "2026-10-21T04:30:00Z";

describe("runWeatherPoll", () => {
  it("saves the station reading and an empty alert list, both healthy", async () => {
    const store = new FakeWeatherStore();
    const log: string[] = [];
    const r = await runWeatherPoll({ store, fetcher: fetcher(), now: at(RUN), log: (m) => log.push(m) });
    expect(r.conditions.ok).toBe(true);
    expect(r.alerts).toMatchObject({ ok: true, count: 0 });
    expect(store.doc).toMatchObject({
      site_id: "qc-139",
      station_fr: "Barrage Témiscaming",
      conditions: { temperature_c: 1.9, observed_at: new Date("2026-10-21T04:00:00Z") },
      conditions_checked_at: new Date(RUN),
      alerts: [],
      alerts_checked_at: new Date(RUN),
    });
    expect(store.health.get("eccc-conditions")).toMatchObject({ last_success_at: new Date(RUN), last_error: "" });
    expect(store.health.get("eccc-alerts")).toMatchObject({ last_success_at: new Date(RUN), last_item_count: 0 });
    expect(log).toEqual([
      "weather conditions: ok — 1.9 °C at Temiskaming Dam, read 30 min ago",
      "weather alerts: ok — 0 for Témiscaming (0 areas nearby)",
    ]);
  });

  it("stores an alert covering town with links to ECCC", async () => {
    const zones = JSON.parse(file("zones-town.json")).features;
    const qc = JSON.parse(file("alerts-qc.json"));
    const feature = { ...qc.features[0], geometry: zones.find((z: { properties: { NAME: string } }) => z.properties.NAME === "Témiscamingue").geometry };
    const body = JSON.stringify({ type: "FeatureCollection", features: [feature], numberMatched: 1, numberReturned: 1 });
    const store = new FakeWeatherStore();
    const r = await runWeatherPoll({ store, fetcher: fetcher({ [ALERTS_URL]: body }), now: at(RUN) });
    expect(r.alerts.count).toBe(1);
    expect(store.doc.alerts).toMatchObject([{
      type: "advisory", title_en: "Frost (advisory)",
      source_url_fr: expect.stringMatching(/^https:\/\/meteo\.gc\.ca/),
      source_url_en: expect.stringMatching(/^https:\/\/weather\.gc\.ca/),
    }]);
    expect(store.health.get("eccc-alerts")!.last_item_count).toBe(1);
  });

  it("a failed alerts download keeps the last alerts and their time, and marks only alerts unhealthy", async () => {
    const store = new FakeWeatherStore();
    await runWeatherPoll({ store, fetcher: fetcher(), now: at(RUN) });
    const later = "2026-10-21T04:45:00Z";
    const r = await runWeatherPoll({ store, fetcher: fetcher({ [ALERTS_URL]: new Error("HTTP 503") }), now: at(later) });

    expect(r.conditions.ok).toBe(true);
    expect(r.alerts).toMatchObject({ ok: false, error: "HTTP 503" });
    // The app sees alerts_checked_at grow old and says "couldn't check" (spec D5).
    expect(store.doc.alerts_checked_at).toEqual(new Date(RUN));
    expect(store.doc.conditions_checked_at).toEqual(new Date(later));
    expect(store.health.get("eccc-alerts")).toMatchObject({
      last_attempt_at: new Date(later), last_success_at: new Date(RUN), last_error: "HTTP 503",
    });
  });

  it("a broken city page doesn't stop the alerts step", async () => {
    const store = new FakeWeatherStore();
    const r = await runWeatherPoll({ store, fetcher: fetcher({ [CITY_PAGE_URL]: "<html>maintenance</html>" }), now: at(RUN) });
    expect(r.conditions).toMatchObject({ ok: false, error: expect.stringMatching(/^not JSON/) });
    expect(r.alerts.ok).toBe(true);
    expect(store.doc.conditions).toBeUndefined();
    expect(store.health.get("eccc-conditions")).toMatchObject({ last_success_at: null });
  });

  it("an alert list cut short is a failure, never an all-clear", async () => {
    const cut = JSON.stringify({ type: "FeatureCollection", features: [], numberMatched: 3, numberReturned: 0 });
    const store = new FakeWeatherStore();
    const r = await runWeatherPoll({ store, fetcher: fetcher({ [ALERTS_URL]: cut }), now: at(RUN) });
    expect(r.alerts.ok).toBe(false);
    expect(store.doc.alerts).toBeUndefined();
  });

  it("records a database failure instead of crashing", async () => {
    const store = new FakeWeatherStore();
    store.failSave = true;
    const r = await runWeatherPoll({ store, fetcher: fetcher(), now: at(RUN) });
    expect(r.conditions).toMatchObject({ ok: false, error: "Firestore unavailable" });
    expect(r.alerts).toMatchObject({ ok: false, error: "Firestore unavailable" });
    expect(store.health.get("eccc-alerts")!.last_error).toBe("Firestore unavailable");
  });

  it("warns when the station reading is over 3 hours old", async () => {
    const store = new FakeWeatherStore();
    const r = await runWeatherPoll({ store, fetcher: fetcher(), now: at("2026-10-21T08:00:00Z") });
    expect(r.conditions.ok).toBe(true);
    expect(r.conditions.warnings).toEqual(["station reading is 240 min old (app hides it, spec D7)"]);
  });
});

describe("runForecastPoll", () => {
  it("saves 7 days without touching the ECCC fields", async () => {
    const store = new FakeWeatherStore();
    await runWeatherPoll({ store, fetcher: fetcher(), now: at(RUN) });
    const r = await runForecastPoll({ store, fetcher: fetcher(), now: at(RUN) });
    expect(r).toMatchObject({ ok: true, count: 7 });
    expect((store.doc.days as unknown[]).length).toBe(7);
    expect(store.doc.forecast_checked_at).toEqual(new Date(RUN));
    expect(store.doc.station_en).toBe("Temiskaming Dam");
    expect(store.health.get("open-meteo-forecast")).toMatchObject({ last_item_count: 7, last_error: "" });
  });

  it("keeps yesterday's forecast when Open-Meteo fails", async () => {
    const store = new FakeWeatherStore();
    await runForecastPoll({ store, fetcher: fetcher(), now: at(RUN) });
    const r = await runForecastPoll({
      store, fetcher: fetcher({ [FORECAST_URL]: new Error("HTTP 429") }), now: at("2026-10-21T05:30:00Z"),
    });
    expect(r).toMatchObject({ ok: false, error: "HTTP 429" });
    expect((store.doc.days as unknown[]).length).toBe(7);
    expect(store.doc.forecast_checked_at).toEqual(new Date(RUN));
    expect(store.health.get("open-meteo-forecast")).toMatchObject({ last_success_at: new Date(RUN), last_error: "HTTP 429" });
  });
});
