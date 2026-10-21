// Reads one layer of Quebec's forest-fire preventive measures (spec fire-bans §2, D3):
// a GeoJSON FeatureCollection from the ministry's WFS. Pure: text in, data out.
//
// Two things the source does that matter:
// - "No measure" is NOT an empty file. The ministry serves one placeholder
//   feature whose name starts with "AUCUNE -" and whose date is when the last
//   measure was lifted (e.g. 2026-07-20 12h). We read that as "none since…".
// - An empty file, or a feature we can't read, is a failure: we'd rather say
//   "couldn't check" than guess "no ban" (DESIGN principle 3).
import { torontoToUtc } from "../alerts/dates";
import { Geometry } from "../weather/geo";

export type LayerId = "ifco" | "icaf";

export const LAYER_TYPENAME: Record<LayerId, string> = {
  ifco: "msp_interdiction_feu_ciel_ouvert_ifco",
  icaf: "msp_interdiction_circuler_foret_icaf",
};

const WFS = "https://geoegl.msp.gouv.qc.ca/apis/wss/complet.fcgi";
export const LAYER_URL: Record<LayerId, string> = {
  ifco: `${WFS}?service=wfs&version=1.1.0&request=getfeature&typename=${LAYER_TYPENAME.ifco}&outputformat=geojson&srsName=epsg:4326`,
  icaf: `${WFS}?service=wfs&version=1.1.0&request=getfeature&typename=${LAYER_TYPENAME.icaf}&outputformat=geojson&srsName=epsg:4326`,
};

/** One measure in effect (or announced) somewhere in Quebec. */
export interface Measure {
  /** The ministry's own name for it (French only; kept for logs, never shown). */
  name: string;
  /** date_eff + heure_eff, in Témiscaming's time zone. May be in the future. */
  startsAt: Date;
  geometry: Geometry;
}

export interface ParsedLayer {
  measures: Measure[];
  /** From the "AUCUNE" placeholder: when the last measure was lifted. */
  noneSince: Date | null;
  featureCount: number;
  warnings: string[];
}

/** "AUCUNE - Interdiction…", with any accents or case. */
function isPlaceholder(name: string): boolean {
  return /^\s*aucune?\b/i.test(name.normalize("NFD").replace(/[̀-ͯ]/g, ""));
}

/** "2026-07-20" + "12h" / "8h" / "8 h 30" / "18h00" → Date (Toronto time). */
export function parseEffective(date: unknown, hour: unknown): Date | null {
  const d = typeof date === "string" ? /^(\d{4})-(\d{2})-(\d{2})/.exec(date.trim()) : null;
  if (!d) return null;
  let h = 0, min = 0;
  if (hour !== undefined && hour !== null && hour !== "") {
    const t = typeof hour === "string" ? /^(\d{1,2})\s*h\s*(\d{2})?$/i.exec(hour.trim()) : null;
    if (!t) return null;
    h = +t[1];
    min = t[2] ? +t[2] : 0;
    if (h > 23 || min > 59) return null;
  }
  return torontoToUtc(+d[1], +d[2], +d[3], h, min);
}

function isArea(g: unknown): g is Geometry {
  if (!g || typeof g !== "object") return false;
  const { type, coordinates } = g as Geometry;
  return (type === "Polygon" || type === "MultiPolygon") && Array.isArray(coordinates) && coordinates.length > 0;
}

/** Throws on anything we can't trust (spec D3); the caller records the failure. */
export function parseLayer(layer: LayerId, json: unknown): ParsedLayer {
  const root = json as { type?: unknown; name?: unknown; features?: unknown };
  if (!root || root.type !== "FeatureCollection" || !Array.isArray(root.features)) {
    throw new Error(`${layer}: not a GeoJSON FeatureCollection`);
  }
  if (typeof root.name === "string" && root.name !== LAYER_TYPENAME[layer]) {
    throw new Error(`${layer}: got layer "${root.name}"`);
  }
  // The ministry always serves at least the placeholder. Empty = something changed.
  if (root.features.length === 0) throw new Error(`${layer}: no features at all (not even the "AUCUNE" placeholder)`);

  const measures: Measure[] = [];
  const warnings: string[] = [];
  let noneSince: Date | null = null;

  root.features.forEach((f, i) => {
    const props = ((f as { properties?: unknown })?.properties ?? {}) as Record<string, unknown>;
    const name = typeof props.mes_prev === "string" ? props.mes_prev.trim() : "";
    if (!name) throw new Error(`${layer}: feature ${i} has no mes_prev`);
    const startsAt = parseEffective(props.date_eff, props.heure_eff);
    if (!startsAt) {
      throw new Error(`${layer}: feature ${i} has an unreadable date (${String(props.date_eff)} ${String(props.heure_eff)})`);
    }
    if (isPlaceholder(name)) {
      noneSince = startsAt;
      return;
    }
    const geometry = (f as { geometry?: unknown }).geometry;
    if (!isArea(geometry)) throw new Error(`${layer}: feature ${i} ("${name}") has no polygon`);
    measures.push({ name, startsAt, geometry });
  });

  if (measures.length && noneSince) {
    warnings.push(`${layer}: "AUCUNE" placeholder served next to ${measures.length} real measure(s); using the measures`);
    noneSince = null;
  }
  return { measures, noneSince, featureCount: root.features.length, warnings };
}
