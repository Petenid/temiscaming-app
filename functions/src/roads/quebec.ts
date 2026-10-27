// Quebec's transport ministry (MTMD) layers → road items and conditions
// (roads spec §2, D1–D6). No network here: these take the parsed JSON.
import { liesAlong, pointsOf, stretchOf } from "./corridor";
import {
  entraveHead, inWinterSeason, isQuebecClosure, parseLocalDateTime, plainText, QUEBEC_511, quebecLabel,
  RoadItem,
} from "./model";

export type QuebecLayer = "warnings" | "roadworks" | "conditions";

const WFS = "https://ws.mapserver.transports.gouv.qc.ca/swtq";
const TYPENAME: Record<QuebecLayer, string> = {
  warnings: "ms:evenements",
  roadworks: "ms:chantiers_mtmdet",
  conditions: "ms:conditions_routieres",
};
/**
 * The area around the corridor (lat 46.2–47.5, lon -80.0 to -78.5). WFS 2.0
 * with this CRS name wants LATITUDE FIRST: written longitude-first, the server
 * silently answers "nothing" (spec §2).
 */
export const QUEBEC_BBOX = "46.2,-80.0,47.5,-78.5,urn:ogc:def:crs:EPSG::4326";

export const QUEBEC_URL: Record<QuebecLayer, string> = Object.fromEntries(
  (Object.keys(TYPENAME) as QuebecLayer[]).map((layer) => [
    layer,
    `${WFS}?service=wfs&version=2.0.0&request=getfeature&typename=${TYPENAME[layer]}` +
      `&srsname=EPSG:4326&outputformat=geojson&bbox=${QUEBEC_BBOX}`,
  ]),
) as Record<QuebecLayer, string>;

interface Feature {
  properties: Record<string, unknown>;
  geometry: unknown;
}

/**
 * Checks the answer is a real GeoJSON FeatureCollection (spec D3). An empty
 * one is valid ("nothing near us"); anything else throws.
 */
export function featuresOf(json: unknown, layer: QuebecLayer): Feature[] {
  const fc = json as { type?: unknown; features?: unknown; numberMatched?: unknown } | null;
  if (!fc || fc.type !== "FeatureCollection" || !Array.isArray(fc.features)) {
    throw new Error(`${layer}: not a GeoJSON FeatureCollection`);
  }
  if (fc.numberMatched !== undefined && typeof fc.numberMatched !== "number") {
    throw new Error(`${layer}: odd numberMatched`);
  }
  const features = fc.features as Feature[];
  features.forEach((f, i) => {
    if (!f || typeof f.properties !== "object" || !f.properties || !pointsOf(f.geometry).length) {
      throw new Error(`${layer}: feature ${i} has no properties or no geometry`);
    }
  });
  return features;
}

const str = (v: unknown) => (typeof v === "string" ? v.trim() : typeof v === "number" ? String(v) : "");

// --- Road warnings ("Avertissement routier"): French only (spec D6) ---

function warningBody(p: Record<string, unknown>): string {
  const lines = [plainText(p.localisation)];
  const add = (label: string, v: unknown) => {
    const t = plainText(v);
    if (t) lines.push(`${label} : ${t}`);
  };
  add("Entrave", p.entrave && !quebecLabel(str(p.entrave)) ? p.entrave : "");
  add("Direction", p.direction);
  add("Cause", p.cause);
  add("Conséquence", p.consequence);
  add("Durée", p.duree);
  add("Détour", p.detour);
  return lines.filter(Boolean).join("\n");
}

export function parseWarnings(json: unknown): { items: RoadItem[]; warnings: string[] } {
  const items: RoadItem[] = [];
  const warnings: string[] = [];
  for (const f of featuresOf(json, "warnings")) {
    const p = f.properties;
    const id = str(p.identifiant);
    if (!id) {
      warnings.push("road warning without identifiant skipped");
      continue;
    }
    const road = stretchOf(pointsOf(f.geometry), ["101"]);
    if (!road) continue;
    const entrave = str(p.entrave);
    const label = quebecLabel(entrave) ?? { fr: "Avertissement routier", en: "Road warning" };
    const since = parseLocalDateTime(p.enVigueurDepuis);
    if (!since) warnings.push(`road warning ${id}: unreadable enVigueurDepuis "${str(p.enVigueurDepuis)}"`);
    items.push({
      id: `qc-warning-${id}`,
      source: "mtmd-warnings",
      kind: isQuebecClosure(entrave) ? "closure" : "incident",
      road,
      place: str(p.municipalite),
      title_fr: label.fr,
      title_en: label.en,
      body_fr: warningBody(p),
      body_en: "",
      original_language: "fr",
      source_url_fr: QUEBEC_511.fr,
      source_url_en: QUEBEC_511.en,
      published_at: since ?? new Date(0),
      starts_at: since,
      ends_at: null,
    });
  }
  return { items, warnings };
}

// --- Roadworks ("Travaux routiers"): the ministry's own FR and EN text ---

export function parseRoadworks(json: unknown): { items: RoadItem[]; warnings: string[] } {
  const items: RoadItem[] = [];
  const warnings: string[] = [];
  for (const f of featuresOf(json, "roadworks")) {
    const p = f.properties;
    const id = str(p.identifiant);
    if (!id) {
      warnings.push("roadwork without identifiant skipped");
      continue;
    }
    const road = stretchOf(pointsOf(f.geometry), ["101"]);
    if (!road) continue;
    const entrave = str(p.entrave);
    const closure = isQuebecClosure(entrave);
    const fr = plainText(p.descriptionFrancais) || [plainText(p.localisation), entraveHead(entrave)].filter(Boolean).join("\n");
    const en = plainText(p.descriptionAnglais);
    const start = parseLocalDateTime(p.debut);
    const end = parseLocalDateTime(p.fin);
    if (!start) warnings.push(`roadwork ${id}: unreadable debut "${str(p.debut)}"`);
    items.push({
      id: `qc-roadwork-${id}`,
      source: "mtmd-roadworks",
      kind: closure ? "closure" : "roadwork",
      road,
      place: "",
      title_fr: closure ? "Route fermée (travaux)" : "Travaux routiers",
      title_en: closure ? "Road closed (roadwork)" : "Roadwork",
      body_fr: fr,
      body_en: en,
      original_language: en ? "both" : "fr",
      source_url_fr: QUEBEC_511.fr,
      source_url_en: QUEBEC_511.en,
      published_at: parseLocalDateTime(p.miseAJour) ?? start ?? new Date(0),
      starts_at: start,
      ends_at: end,
    });
  }
  return { items, warnings };
}

// --- Winter road conditions: natively bilingual ---

export interface Segment {
  from_fr: string;
  from_en: string;
  to_fr: string;
  to_en: string;
  surface_fr: string;
  surface_en: string;
  /** Bare (dry or wet): nothing to flag on Today (spec D11). */
  surface_ok: boolean;
  visibility_fr: string;
  visibility_en: string;
  visibility_ok: boolean;
  /** Snow drifts across the road ("lames de neige"); null if not stated. */
  drifting: boolean | null;
  /** The source says it has no report for this stretch (Ontario's "No Report"). */
  no_report: boolean;
  since: Date | null;
}

const BARE = new Set(["Ds", "Dm"]);

export interface QuebecConditions {
  segments: Segment[];
  in_season: boolean;
}

/**
 * Route 101 segments along our stretch, in road order. In season (15 Oct –
 * 15 Apr) finding none is a failure; out of season it means "not published".
 */
export function parseConditions(json: unknown, now: Date): { conditions: QuebecConditions; warnings: string[] } {
  const warnings: string[] = [];
  const inSeason = inWinterSeason(now);
  const found: { n: number; s: Segment }[] = [];
  for (const f of featuresOf(json, "conditions")) {
    const p = f.properties;
    if (str(p.NumeroRoute) !== "101" || !liesAlong(pointsOf(f.geometry), "101")) continue;
    const code = str(p.CodeEtatChaussee);
    const vis = str(p.CodeVisibilite);
    const blades = str(p.IndicateurPresenceLamesNeige).toUpperCase();
    found.push({
      n: Number(p.NumeroSegment) || 0,
      s: {
        from_fr: str(p.LocalisationDebutFR),
        from_en: str(p.LocalisationDebutEN) || str(p.LocalisationDebutFR),
        to_fr: str(p.LocalisationFinFR),
        to_en: str(p.LocalisationFinEN) || str(p.LocalisationFinFR),
        surface_fr: str(p.DescriptionEtatChausseeFR),
        surface_en: str(p.DescriptionEtatChausseeEN),
        surface_ok: BARE.has(code),
        visibility_fr: str(p.DescriptionVisibiliteFR),
        visibility_en: str(p.DescriptionVisibiliteEN),
        visibility_ok: vis === "B",
        drifting: blades === "O" ? true : blades === "N" ? false : null,
        no_report: false,
        since: parseLocalDateTime(p.EnVigueurDepuis),
      },
    });
    if (!code) warnings.push(`segment ${str(p.NumeroSegment)}: no surface code`);
  }
  if (inSeason && !found.length) throw new Error("conditions: no Route 101 segment on our stretch (in season)");
  found.sort((a, b) => a.n - b.n);
  return { conditions: { segments: found.map((x) => x.s), in_season: inSeason }, warnings };
}
