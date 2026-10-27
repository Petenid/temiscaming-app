// What every road item looks like once read, whatever its source (roads spec
// §5), plus the rules shared by the parsers: what counts as a closure (D2),
// our own FR/EN labels (D6), and "planned" vs "in effect" (D5).
import { torontoToUtc } from "../alerts/dates";
import { Road } from "./corridor";

export type Kind = "closure" | "incident" | "roadwork" | "town";
export type RoadSource =
  | "mtmd-warnings" | "mtmd-roadworks"
  | "on511-events" | "on511-construction"
  | "town-work-info";

/** One item as a parser produces it. */
export interface RoadItem {
  id: string;
  source: RoadSource;
  kind: Kind;
  road: Road | null;
  /** Municipality or place name as the source gives it ("" if none). */
  place: string;
  title_fr: string;
  title_en: string;
  body_fr: string;
  body_en: string;
  original_language: "fr" | "en" | "both";
  source_url_fr: string;
  source_url_en: string;
  published_at: Date;
  starts_at: Date | null;
  /** Planned end. Null when the source gives none (Quebec road warnings). */
  ends_at: Date | null;
}

/** Links to the official maps (roads spec D12). */
export const QUEBEC_511 = { fr: "https://www.quebec511.info/fr/", en: "https://www.quebec511.info/en/" };
export const ONTARIO_511 = { fr: "https://511on.ca/fr/", en: "https://511on.ca/" };

/** Items starting further ahead than this aren't shown (spec D5). */
export const MAX_AHEAD_MS = 14 * 24 * 3600_000;

export type Status = "planned" | "in_effect";

/** Spec D5: "planned" before the start, "in effect" from it. */
export function statusOf(item: RoadItem, now: Date): Status {
  return item.starts_at && item.starts_at > now ? "planned" : "in_effect";
}

/** Spec D5: should this item be shown (and kept) at all right now? */
export function isCurrent(item: RoadItem, now: Date): boolean {
  if (item.starts_at && item.starts_at.getTime() - now.getTime() > MAX_AHEAD_MS) return false;
  // Only the Town's items are hidden after their end date; the ministries keep
  // items open past their planned end, and we follow what they still list.
  if (item.source === "town-work-info" && item.ends_at && item.ends_at <= now) return false;
  return true;
}

/** Spec D11: closures (planned or in effect) and incidents in effect go on Today. */
export function onToday(item: RoadItem, now: Date): boolean {
  if (item.kind === "closure") return true;
  return item.kind === "incident" && statusOf(item, now) === "in_effect";
}

// --- Quebec's "entrave" phrases (spec D2, D6) ---

const LANE_OR_PART = /\b(voies?|accotements?|bretelles?|stationnement)\b/i;

/** First line of an "entrave", trimmed ("Circulation en alternance \nMardi…" → "Circulation en alternance"). */
export function entraveHead(entrave: string): string {
  return entrave.split(/\r?\n/)[0].replace(/\s+/g, " ").trim();
}

/** A full closure: "Fermeture…" that isn't about a lane, shoulder, ramp or parking. */
export function isQuebecClosure(entrave: string): boolean {
  const head = entraveHead(entrave);
  return /^fermeture\b/i.test(head) && !LANE_OR_PART.test(head);
}

/** Our own label for a Quebec obstruction phrase (spec D6). Null when we have none. */
export function quebecLabel(entrave: string): { fr: string; en: string } | null {
  const head = entraveHead(entrave);
  if (isQuebecClosure(head)) return { fr: "Route fermée", en: "Road closed" };
  if (/^fermeture de 1 voie sur 2\b/i.test(head)) return { fr: "Une voie sur deux fermée", en: "One of two lanes closed" };
  if (/^fermeture\b.*\bvoies?\b/i.test(head)) return { fr: "Voie fermée", en: "Lane closed" };
  if (/^circulation en alternance\b/i.test(head)) return { fr: "Circulation en alternance", en: "Alternating traffic" };
  if (/^circulation interdite aux v[ée]hicules lourds\b/i.test(head)) {
    return { fr: "Interdit aux véhicules lourds", en: "Closed to heavy vehicles" };
  }
  if (/^circulation à contresens\b/i.test(head)) return { fr: "Circulation à contresens", en: "Contraflow traffic" };
  return null;
}

// --- Dates ---

/**
 * "2026/10/21 07:00:00", "2026-10-22T04:11:52", "2026-10-22 15:30" — a wall-clock
 * time in Témiscaming (the ministry's files carry no time zone) → Date.
 */
export function parseLocalDateTime(text: unknown): Date | null {
  if (typeof text !== "string") return null;
  const m = text.trim().match(/^(\d{4})[-/](\d{2})[-/](\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2})?)?$/);
  if (!m) return null;
  const [, y, mo, d, h, mi] = m;
  return torontoToUtc(+y, +mo, +d, h ? +h : 0, mi ? +mi : 0);
}

/** Unix seconds → Date (Ontario 511). */
export function fromUnix(value: unknown): Date | null {
  return typeof value === "number" && value > 0 ? new Date(value * 1000) : null;
}

/** "MM-DD" in Témiscaming for a moment. */
function monthDay(at: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Toronto", month: "2-digit", day: "2-digit" })
    .format(at).replace("/", "-");
}

/** Quebec publishes all winter conditions from 15 October to 15 April (spec D3). */
export function inWinterSeason(at: Date): boolean {
  const md = monthDay(at);
  return md >= "10-15" || md <= "04-15";
}

/** Text from HTML-ish source fields: `<br/>` → new line, other tags dropped, spaces tidied. */
export function plainText(text: unknown): string {
  if (typeof text !== "string") return "";
  return text
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\r/g, "")
    .split("\n").map((l) => l.replace(/[ \t]+/g, " ").trim()).join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
