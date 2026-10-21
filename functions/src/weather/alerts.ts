// ECCC weather alerts → the ones that cover Témiscaming (spec weather D2).
// The API returns one feature per alert *area*; one alert spread over several
// areas has the same id before the underscore
// ("165538168887825634202610190504_fea1-978"). We keep an area only if its
// outline contains the town centre or Lumsden, then merge areas of the same
// alert so it appears once.
import { coversTown, Geometry } from "./geo";

export type AlertType = "warning" | "watch" | "advisory" | "statement";

export interface WeatherAlert {
  id: string;
  type: AlertType;
  /** "yellow" | "orange" | "red", as ECCC gives it. */
  colour: string | null;
  /** ECCC's short name: "Gel (avis)" / "Frost (advisory)". */
  title_fr: string;
  title_en: string;
  /** "secteur de …" / "… area" */
  area_fr: string;
  area_en: string;
  body_fr: string;
  body_en: string;
  published_at: Date | null;
  ends_at: Date | null;
  expires_at: Date | null;
}

export interface AlertsResult {
  alerts: WeatherAlert[];
  /** Areas in the response before the point test (for the log). */
  areasNearby: number;
  warnings: string[];
}

const TYPES: AlertType[] = ["warning", "watch", "advisory", "statement"];

/** ECCC's alert pages for our location: the "source" link (alerts carry no URL). */
export const ECCC_ALERTS_URL_FR = "https://meteo.gc.ca/fr/location/index.html?coords=46.722,-79.093";
export const ECCC_ALERTS_URL_EN = "https://weather.gc.ca/en/location/index.html?coords=46.722,-79.093";

type Json = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
function date(v: unknown): Date | null {
  const d = typeof v === "string" ? new Date(v) : null;
  return d && !Number.isNaN(d.getTime()) ? d : null;
}

/** Throws when the response isn't a complete list of alerts (the caller records it). */
export function parseAlerts(json: unknown, now: Date): AlertsResult {
  const fc = json as Json | null;
  if (!fc || fc.type !== "FeatureCollection" || !Array.isArray(fc.features)) {
    throw new Error("alerts: response is not a FeatureCollection");
  }
  // A page cut short could hide the one alert that covers us (principle 3).
  const matched = typeof fc.numberMatched === "number" ? fc.numberMatched : null;
  if (matched !== null && matched > fc.features.length) {
    throw new Error(`alerts: only ${fc.features.length} of ${matched} alerts returned`);
  }

  const warnings: string[] = [];
  const byId = new Map<string, WeatherAlert>();
  for (const raw of fc.features as Json[]) {
    const p = (raw.properties ?? {}) as Json;
    if (!coversTown(raw.geometry as Geometry)) continue;

    const status = str(p.status_en).toLowerCase();
    if (/ended|cancel/.test(status)) continue;
    const expiresAt = date(p.expiration_datetime);
    if (expiresAt && expiresAt <= now) continue;

    const id = str(raw.id).split("_")[0] || str(raw.id);
    if (byId.has(id)) continue; // same alert, second area (town and Lumsden in different areas)

    let type = str(p.alert_type).toLowerCase() as AlertType;
    if (!TYPES.includes(type)) {
      // Better shown too loudly than hidden: an unknown type goes in the banner.
      warnings.push(`alert ${id}: unknown type "${p.alert_type}", shown as an advisory`);
      type = "advisory";
    }
    byId.set(id, {
      id,
      type,
      colour: str(p.risk_colour_en) || null,
      title_fr: str(p.alert_short_name_fr) || str(p.alert_name_fr),
      title_en: str(p.alert_short_name_en) || str(p.alert_name_en),
      area_fr: str(p.feature_name_fr),
      area_en: str(p.feature_name_en),
      body_fr: str(p.alert_text_fr),
      body_en: str(p.alert_text_en),
      published_at: date(p.publication_datetime),
      ends_at: date(p.event_end_datetime),
      expires_at: expiresAt,
    });
  }

  const alerts = [...byId.values()].sort(
    (a, b) =>
      TYPES.indexOf(a.type) - TYPES.indexOf(b.type) ||
      (b.published_at?.getTime() ?? 0) - (a.published_at?.getTime() ?? 0),
  );
  for (const a of alerts) {
    if (!a.title_fr || !a.title_en) warnings.push(`alert ${a.id}: title missing in one language`);
  }
  return { alerts, areasNearby: fc.features.length, warnings };
}
