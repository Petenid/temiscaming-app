// ECCC city page → current conditions (spec weather §2, D7). Only the
// "currentConditions" part is read: the forecast in this page is for the
// Ville-Marie area, so it comes from Open-Meteo instead (spec D1).
//
// The page gives every text in both languages side by side:
// {"en": "Clear", "fr": "Dégagé"}. Numbers come the same way, with the same
// value twice. Any value can be missing: at night the station sends no
// condition text and no pressure (fixture 2026-10-21-0025).

export interface Conditions {
  observed_at: Date;
  temperature_c: number | null;
  condition_fr: string | null;
  condition_en: string | null;
  /** ECCC's own icon code (00–48); the app maps it to our icons (spec D6). */
  eccc_icon: number | null;
  wind_kmh: number | null;
  /** "SE", "NNW", "VR" (variable)… as ECCC sends it. */
  wind_dir: string | null;
  gust_kmh: number | null;
  wind_chill: number | null;
  humidex: number | null;
  humidity_pct: number | null;
}

export interface CityPage {
  site_id: string;
  station_fr: string | null;
  station_en: string | null;
  eccc_url_fr: string | null;
  eccc_url_en: string | null;
  conditions: Conditions;
}

type Json = Record<string, unknown>;

const obj = (v: unknown): Json | null =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Json) : null;

/** Follows a path of keys; null as soon as one is missing. */
function at(root: unknown, ...keys: string[]): unknown {
  let cur: unknown = root;
  for (const k of keys) {
    const o = obj(cur);
    if (!o || !(k in o)) return null;
    cur = o[k];
  }
  return cur;
}

function text(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

function num(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() && Number.isFinite(Number(v))) return Number(v);
  return null;
}

/** A bilingual number: both languages carry the same value; take English's. */
const biNum = (root: unknown, ...keys: string[]) =>
  num(at(root, ...keys, "en")) ?? num(at(root, ...keys, "fr"));

/** Throws with a short reason when the page isn't usable (the caller records it). */
export function parseCityPage(json: unknown): CityPage {
  const props = obj(at(json, "properties"));
  if (!props) throw new Error("city page: no properties (not a city page?)");
  const cc = obj(props.currentConditions);
  if (!cc || Object.keys(cc).length === 0) throw new Error("city page: no current conditions");

  const ts = text(at(cc, "timestamp", "en")) ?? text(at(cc, "timestamp", "fr"));
  const observedAt = ts ? new Date(ts) : null;
  if (!observedAt || Number.isNaN(observedAt.getTime())) {
    throw new Error("city page: current conditions have no observation time");
  }

  // Units are checked, not assumed: a change to imperial would be a silent lie.
  const tempUnits = text(at(cc, "temperature", "units", "en"));
  if (tempUnits && tempUnits !== "C") throw new Error(`city page: temperature in ${tempUnits}, expected C`);
  const windUnits = text(at(cc, "wind", "speed", "units", "en"));
  if (windUnits && windUnits !== "km/h") throw new Error(`city page: wind in ${windUnits}, expected km/h`);

  return {
    site_id: text(props.identifier) ?? text(at(json, "id")) ?? "",
    station_fr: text(at(cc, "station", "value", "fr")),
    station_en: text(at(cc, "station", "value", "en")),
    eccc_url_fr: text(at(props, "url", "fr")),
    eccc_url_en: text(at(props, "url", "en")),
    conditions: {
      observed_at: observedAt,
      temperature_c: biNum(cc, "temperature", "value"),
      condition_fr: text(at(cc, "condition", "fr")),
      condition_en: text(at(cc, "condition", "en")),
      eccc_icon: num(at(cc, "iconCode", "value")),
      wind_kmh: biNum(cc, "wind", "speed", "value"),
      wind_dir: text(at(cc, "wind", "direction", "value", "en")),
      gust_kmh: biNum(cc, "wind", "gust", "value"),
      wind_chill: biNum(cc, "windChill", "value"),
      humidex: biNum(cc, "humidex", "value"),
      humidity_pct: biNum(cc, "relativeHumidity", "value"),
    },
  };
}
