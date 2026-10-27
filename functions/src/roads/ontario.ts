// Ontario 511 answers → road items, Highway 63 conditions and cameras (roads
// spec §2, D1–D6, D10). No network here: these take the parsed JSON, one array
// per language. Ontario writes its own French, so both languages are official.
import { Point } from "../weather/geo";
import { stretchOf } from "./corridor";
import { fromUnix, ONTARIO_511, plainText, RoadItem } from "./model";
import { Segment } from "./quebec";

export type OntarioCall = "events" | "construction" | "conditions" | "cameras";

const PATH: Record<OntarioCall, string> = {
  events: "v2/get/event",
  construction: "v2/get/constructionprojects",
  conditions: "v3/get/roadconditions",
  cameras: "v2/get/cameras",
};

/** The request URL. Contains the key: never log it (use `ontarioUrlForLog`). */
export function ontarioUrl(call: OntarioCall, lang: "fr" | "en", key: string): string {
  return `https://511on.ca/api/${PATH[call]}?format=json&lang=${lang}&key=${encodeURIComponent(key)}`;
}

/** Same URL with the key hidden (spec D15). */
export function ontarioUrlForLog(call: OntarioCall, lang: "fr" | "en"): string {
  return `https://511on.ca/api/${PATH[call]}?format=json&lang=${lang}&key=***`;
}

type Obj = Record<string, unknown>;

/** Spec D3: a valid answer is a JSON array (empty is fine). */
export function arrayOf(json: unknown, what: string): Obj[] {
  if (!Array.isArray(json)) throw new Error(`${what}: not a JSON array`);
  return json.filter((x): x is Obj => !!x && typeof x === "object");
}

const str = (v: unknown) => (typeof v === "string" ? v.trim() : typeof v === "number" ? String(v) : "");

/** "HWY 63", "RTE 63", "63", "Highway 63" — but not 630 or 163. */
export function isHighway63(name: unknown): boolean {
  return /(?<!\d)63(?!\d)/.test(str(name));
}

/** Google's encoded-polyline format → [lon, lat] points. */
export function decodePolyline(encoded: string): Point[] {
  const points: Point[] = [];
  let i = 0, lat = 0, lng = 0;
  while (i < encoded.length) {
    const next = () => {
      let shift = 0, result = 0, b: number;
      do {
        b = encoded.charCodeAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && i < encoded.length);
      return result & 1 ? ~(result >> 1) : result >> 1;
    };
    lat += next();
    lng += next();
    points.push([lng / 1e5, lat / 1e5]);
  }
  return points;
}

function pointsOfEvent(e: Obj): Point[] {
  const pts: Point[] = [];
  for (const [la, lo] of [["Latitude", "Longitude"], ["LatitudeSecondary", "LongitudeSecondary"]]) {
    if (typeof e[la] === "number" && typeof e[lo] === "number") pts.push([e[lo] as number, e[la] as number]);
  }
  const poly = e.EncodedPolyline;
  for (const s of Array.isArray(poly) ? poly : [poly]) {
    if (typeof s === "string" && s) pts.push(...decodePolyline(s));
  }
  return pts;
}

function eventLabel(call: "events" | "construction", e: Obj): { kind: RoadItem["kind"]; fr: string; en: string } {
  if (e.IsFullClosure === true) return { kind: "closure", fr: "Route fermée", en: "Road closed" };
  const type = str(e.EventType);
  if (call === "construction" || type === "roadwork") return { kind: "roadwork", fr: "Travaux routiers", en: "Roadwork" };
  if (type === "closures") return { kind: "incident", fr: "Fermeture partielle", en: "Partial closure" };
  if (type === "accidentsAndIncidents") return { kind: "incident", fr: "Incident", en: "Incident" };
  return { kind: "incident", fr: "Avertissement routier", en: "Road warning" };
}

function bodyOf(e: Obj | undefined): string {
  if (!e) return "";
  return [plainText(e.Description), plainText(e.Comment)].filter(Boolean).join("\n");
}

/**
 * Events or construction projects on our stretch of Highway 63, the two
 * languages paired by ID. An item listed in only one language keeps that one.
 */
export function parseOntarioItems(
  call: "events" | "construction", en: unknown, fr: unknown,
): { items: RoadItem[]; warnings: string[] } {
  const enList = arrayOf(en, `${call} (en)`);
  const frList = arrayOf(fr, `${call} (fr)`);
  const frById = new Map(frList.map((e) => [str(e.ID), e]));
  const enById = new Map(enList.map((e) => [str(e.ID), e]));
  const ids = [...new Set([...enById.keys(), ...frById.keys()])].filter(Boolean);
  const items: RoadItem[] = [];
  const warnings: string[] = [];
  for (const id of ids) {
    const e = enById.get(id) ?? frById.get(id)!;
    const onName = isHighway63(e.RoadwayName);
    const road = onName ? "63" : stretchOf(pointsOfEvent(e), ["63"]);
    if (!road) continue;
    const label = eventLabel(call, e);
    const bodyEn = bodyOf(enById.get(id));
    const bodyFr = bodyOf(frById.get(id));
    const start = fromUnix(e.StartDate);
    if (!start) warnings.push(`${call} ${id}: no StartDate`);
    items.push({
      id: `on-${call === "events" ? "event" : "construction"}-${id}`,
      source: call === "events" ? "on511-events" : "on511-construction",
      kind: label.kind,
      road,
      place: "",
      title_fr: label.fr,
      title_en: label.en,
      body_fr: bodyFr,
      body_en: bodyEn,
      original_language: bodyFr && bodyEn ? "both" : bodyFr ? "fr" : "en",
      source_url_fr: ONTARIO_511.fr,
      source_url_en: ONTARIO_511.en,
      published_at: fromUnix(e.LastUpdated) ?? fromUnix(e.Reported) ?? start ?? new Date(0),
      starts_at: start,
      ends_at: fromUnix(e.PlannedEndDate),
    });
  }
  return { items, warnings };
}

// --- Highway 63 road conditions ---

const BARE_EN = new Set(["bare and dry road", "bare and wet road"]);

/** "From North Bay to Thorne" / "De North Bay à Thorne" → [from, to]. */
function fromTo(text: string, lang: "fr" | "en"): [string, string] {
  const m = lang === "en" ? text.match(/^From (.+?) to (.+)$/i) : text.match(/^De (.+?) à (.+)$/i);
  return m ? [m[1].trim(), m[2].trim()] : [text, ""];
}

/**
 * Highway 63 stretches, paired FR/EN by their line (same road, same polyline).
 * No Highway 63 entry at all → failure (spec D3).
 */
export function parseOntarioConditions(en: unknown, fr: unknown): Segment[] {
  const enList = arrayOf(en, "conditions (en)").filter((c) => isHighway63(c.RoadwayName) && /^\s*63\s*$/.test(str(c.RoadwayName)));
  const frList = arrayOf(fr, "conditions (fr)").filter((c) => isHighway63(c.RoadwayName) && /^\s*63\s*$/.test(str(c.RoadwayName)));
  if (!enList.length) throw new Error("conditions: no Highway 63 entry");
  const lineKey = (c: Obj) => JSON.stringify(c.EncodedPolyline ?? "");
  return enList.map((e, i) => {
    const f = frList.find((x) => lineKey(x) === lineKey(e)) ?? frList[i];
    const condEn = (Array.isArray(e.Condition) ? e.Condition : [e.Condition]).map(str).filter(Boolean);
    const condFr = f ? (Array.isArray(f.Condition) ? f.Condition : [f.Condition]).map(str).filter(Boolean) : [];
    const noReport = !condEn.length || condEn.every((c) => /^no report$/i.test(c));
    const [fromEn, toEn] = fromTo(str(e.LocationDescription), "en");
    const [fromFr, toFr] = f ? fromTo(str(f.LocationDescription), "fr") : [fromEn, toEn];
    const drift = str(e.Drifting).toLowerCase();
    const vis = str(e.Visibility);
    return {
      from_fr: fromFr,
      from_en: fromEn,
      to_fr: toFr,
      to_en: toEn,
      surface_fr: condFr.join(", "),
      surface_en: condEn.join(", "),
      surface_ok: noReport || condEn.every((c) => BARE_EN.has(c.toLowerCase())),
      visibility_fr: f ? str(f.Visibility) : "",
      visibility_en: vis,
      visibility_ok: !vis || /^good$/i.test(vis),
      drifting: drift === "yes" ? true : drift === "no" ? false : null,
      no_report: noReport,
      since: fromUnix(e.LastUpdated),
    };
  });
}

// --- Highway 63 cameras (spec D10) ---

export interface CameraView {
  image_url: string;
  direction_fr: string;
  direction_en: string;
}

export interface Camera {
  location: string;
  lat: number;
  lon: number;
  views: CameraView[];
}

const DIRECTION_FR: Record<string, string> = {
  north: "Vers le nord", south: "Vers le sud", east: "Vers l'est", west: "Vers l'ouest",
};

function directionFr(en: string): string {
  const m = en.match(/^looking (north|south|east|west)$/i);
  return m ? DIRECTION_FR[m[1].toLowerCase()] : en;
}

/** Cameras on Highway 63, in Ontario's order (south to north by their SortOrder). */
export function parseCameras(json: unknown): Camera[] {
  return arrayOf(json, "cameras")
    .filter((c) => isHighway63(c.Roadway) && typeof c.Latitude === "number" && typeof c.Longitude === "number")
    .sort((a, b) => (Number(a.SortOrder) || 0) - (Number(b.SortOrder) || 0))
    .map((c) => ({
      location: str(c.Location),
      lat: c.Latitude as number,
      lon: c.Longitude as number,
      views: (Array.isArray(c.Views) ? (c.Views as Obj[]) : [])
        .filter((v) => str(v.Status) === "Enabled" && /^https:\/\//.test(str(v.Url)))
        .map((v) => ({ image_url: str(v.Url), direction_en: str(v.Description), direction_fr: directionFr(str(v.Description)) })),
    }))
    .filter((c) => c.views.length > 0);
}
