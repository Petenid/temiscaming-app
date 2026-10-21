// The two weather runs (spec weather D3, §6):
//   runWeatherPoll  — every 15 min: ECCC station conditions, then ECCC alerts
//   runForecastPoll — every hour:   Open-Meteo 7-day forecast
// Each step has its own health record and its own fields in the one
// `weather/temiscaming` document, so a failure in one never touches, or
// hides, the others. Network and database come in as small interfaces, so
// tests run whole runs against the saved fixtures.
import { Fetcher } from "../alerts/sync";
import { ECCC_ALERTS_URL_EN, ECCC_ALERTS_URL_FR, parseAlerts, WeatherAlert } from "./alerts";
import { Conditions, parseCityPage } from "./conditions";
import { FORECAST_URL, ForecastDay, parseForecast } from "./forecast";

const ECCC = "https://api.weather.gc.ca/collections";
/** City page "Témiscamingue": readings from the Barrage Témiscaming station. */
export const CITY_PAGE_URL = `${ECCC}/citypageweather-realtime/items/qc-139?f=json`;
/** A small box around town; coversTown() then decides exactly (spec D2). */
export const ALERTS_URL = `${ECCC}/weather-alerts/items?f=json&bbox=-79.20,46.65,-78.95,46.80&limit=500`;

export type WeatherSourceId = "eccc-conditions" | "eccc-alerts" | "open-meteo-forecast";

/** Fields of Firestore `weather/temiscaming` (spec §5). Each step writes only its own. */
export interface ConditionsFields {
  site_id: string;
  station_fr: string | null;
  station_en: string | null;
  eccc_url_fr: string | null;
  eccc_url_en: string | null;
  conditions: Conditions;
  conditions_checked_at: Date;
}
export interface AlertsFields {
  alerts: (WeatherAlert & { source_url_fr: string; source_url_en: string })[];
  alerts_checked_at: Date;
}
export interface ForecastFields {
  days: ForecastDay[];
  forecast_checked_at: Date;
}

/** Firestore `sources/{id}` (DESIGN §4 source health). */
export interface WeatherHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  last_item_count: number;
  last_error: string;
  warnings: string[];
}

export interface WeatherStore {
  /** Merges these fields into `weather/temiscaming`; other fields are left as they are. */
  saveWeather(fields: ConditionsFields | AlertsFields | ForecastFields): Promise<void>;
  loadHealth(id: WeatherSourceId): Promise<WeatherHealth | null>;
  saveHealth(id: WeatherSourceId, h: WeatherHealth): Promise<void>;
}

export interface WeatherDeps {
  store: WeatherStore;
  fetcher: Fetcher;
  now: () => Date;
  log?: (message: string) => void;
}

export interface StepResult {
  ok: boolean;
  error?: string;
  count: number;
  warnings: string[];
}

async function getJson(fetcher: Fetcher, url: string): Promise<unknown> {
  const bytes = await fetcher.get(url);
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error(`not JSON: ${url}`);
  }
}

/**
 * Runs one step: fetch + parse + save, then health. Any error (download,
 * parse, database) is caught here and recorded, so the next step still runs.
 */
async function step(
  deps: WeatherDeps,
  id: WeatherSourceId,
  label: string,
  work: (startedAt: Date) => Promise<{ count: number; warnings: string[]; summary: string }>,
): Promise<StepResult> {
  const { store, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  let health: WeatherHealth | null = null;
  try {
    health = await store.loadHealth(id);
    const { count, warnings, summary } = await work(startedAt);
    warnings.forEach((w) => log(`${label}: warning — ${w}`));
    await store.saveHealth(id, {
      last_attempt_at: startedAt,
      last_success_at: startedAt,
      last_item_count: count,
      last_error: "",
      warnings: warnings.slice(0, 20),
    });
    log(`${label}: ok — ${summary}`);
    return { ok: true, count, warnings };
  } catch (e) {
    const error = (e as Error).message ?? String(e);
    log(`${label}: FAILED — ${error}`);
    try {
      await store.saveHealth(id, {
        last_attempt_at: startedAt,
        last_success_at: health?.last_success_at ?? null,
        last_item_count: health?.last_item_count ?? 0,
        last_error: error.slice(0, 300),
        warnings: health?.warnings ?? [],
      });
    } catch (e2) {
      log(`${label}: could not record the failure — ${(e2 as Error).message}`);
    }
    return { ok: false, error, count: 0, warnings: [] };
  }
}

/** Every 15 minutes: station conditions, then alerts (spec D3). */
export async function runWeatherPoll(deps: WeatherDeps): Promise<{ conditions: StepResult; alerts: StepResult }> {
  const conditions = await step(deps, "eccc-conditions", "weather conditions", async (startedAt) => {
    const page = parseCityPage(await getJson(deps.fetcher, CITY_PAGE_URL));
    await deps.store.saveWeather({ ...page, conditions_checked_at: startedAt });
    const c = page.conditions;
    const ageMin = Math.round((startedAt.getTime() - c.observed_at.getTime()) / 60_000);
    const warnings = ageMin > 180 ? [`station reading is ${ageMin} min old (app hides it, spec D7)`] : [];
    return {
      count: 1,
      warnings,
      summary: `${c.temperature_c ?? "no"} °C at ${page.station_en ?? "station"}, read ${ageMin} min ago`,
    };
  });

  const alerts = await step(deps, "eccc-alerts", "weather alerts", async (startedAt) => {
    const parsed = parseAlerts(await getJson(deps.fetcher, ALERTS_URL), startedAt);
    await deps.store.saveWeather({
      alerts: parsed.alerts.map((a) => ({ ...a, source_url_fr: ECCC_ALERTS_URL_FR, source_url_en: ECCC_ALERTS_URL_EN })),
      alerts_checked_at: startedAt,
    });
    return {
      // Zero alerts is normal, not a failure (spec §5).
      count: parsed.alerts.length,
      warnings: parsed.warnings,
      summary: `${parsed.alerts.length} for Témiscaming (${parsed.areasNearby} areas nearby)`,
    };
  });

  return { conditions, alerts };
}

/** Every hour: the Open-Meteo forecast (spec D1, D3). */
export async function runForecastPoll(deps: WeatherDeps): Promise<StepResult> {
  return step(deps, "open-meteo-forecast", "forecast", async (startedAt) => {
    const { days, warnings } = parseForecast(await getJson(deps.fetcher, FORECAST_URL));
    await deps.store.saveWeather({ days, forecast_checked_at: startedAt });
    return { count: days.length, warnings, summary: `${days.length} days from ${days[0].date}` };
  });
}
