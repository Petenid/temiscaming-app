// Which of Hydro-Québec's rows are about Témiscaming, and what they mean
// (spec power-outages D1, D2, D8).
//
// The two files name places differently, both checked by name against
// Hydro-Québec's own list of places (fixtures/power/<date>/places-temiscamingue.json):
//   - current interruptions: Hydro-Québec's 4-digit locality ID.
//     Témiscaming "9130" (the whole Ville, Lumsden and Letang included);
//     Tee Lake "9124", which Hydro-Québec files under Kipawa.
//   - planned interruptions: the government's 5-digit municipality code.
//     Témiscaming (V) "85005"; Kipawa (M) "85010", which holds both Lac Tee
//     and Kipawa village, so there we keep only what's near Lac Tee.
import { distanceToLineKm } from "../weather/geo";
import { OngoingRow, PlannedRow } from "./parse";

export type Area = "temiscaming" | "lac_tee";

export const ONGOING_LOCALITIES: Record<string, Area> = { "9130": "temiscaming", "9124": "lac_tee" };
export const PLANNED_TEMISCAMING = "85005";
export const PLANNED_KIPAWA = "85010";

/** Lac Tee, from the Commission de toponymie (fiche 61924). Kipawa village is ~4 km east. */
export const LAC_TEE: [number, number] = [-79.03534, 46.78098];
export const LAC_TEE_RADIUS_KM = 3;

/** Planned interruptions further ahead than this aren't shown (spec D2). */
export const PLANNED_AHEAD_MS = 14 * 24 * 3600_000;

export type OutageKind = "outage" | "planned_in_progress";
export type CrewStatus = "assigned" | "on_the_way" | "at_work";
export type Cause = "equipment" | "weather" | "accident" | "vegetation" | "animal" | "planned_work";

/** One current interruption here, as stored in `power/temiscaming` (spec §5). */
export interface Outage {
  kind: OutageKind;
  customers: number;
  started_at: Date;
  estimated_end_at: Date | null;
  status: CrewStatus | null;
  cause: Cause | null;
  area: Area;
}

/** One upcoming planned interruption here (spec §5). */
export interface Planned {
  notice: string;
  customers: number;
  /** The window currently scheduled. */
  starts_at: Date;
  ends_at: Date;
  /** Set when the work was moved from its original date. */
  original_starts_at: Date | null;
  change: "postponed" | null;
  /** Hydro-Québec's backup date, in case the work can't go ahead. */
  alternate_starts_at: Date | null;
  alternate_ends_at: Date | null;
  area: Area;
}

const STATUS: Record<string, CrewStatus> = { A: "assigned", R: "on_the_way", L: "at_work" };

// Cause codes as documented by Hydro-Québec. 61–63 and 77 aren't documented;
// they're only seen on planned interruptions in progress ("I" rows).
const CAUSE_CODES: [Cause, string[]][] = [
  ["equipment", ["11", "12", "13", "14", "15", "58", "70", "72", "73", "74", "79"]],
  ["weather", ["21", "22", "24", "25", "26"]],
  ["accident", ["31", "32", "33", "34", "41", "42", "43", "44", "54", "55", "56", "57"]],
  ["vegetation", ["51"]],
  ["animal", ["52", "53"]],
];

export function causeOf(code: string, kind: OutageKind): Cause | null {
  if (kind === "planned_in_progress") return "planned_work";
  for (const [cause, codes] of CAUSE_CODES) if (codes.includes(code)) return cause;
  return null; // unknown or not yet known: show nothing rather than guess (spec D8)
}

export interface Filtered<T> {
  items: T[];
  warnings: string[];
}

/** Current interruptions in Témiscaming and at Lac Tee, biggest first. */
export function ongoingHere(rows: OngoingRow[]): Filtered<Outage> {
  const warnings: string[] = [];
  const items: Outage[] = [];
  for (const r of rows) {
    const area = ONGOING_LOCALITIES[r.locality];
    if (!area) continue;
    let kind: OutageKind;
    if (r.type === "I") kind = "planned_in_progress";
    else {
      // "P" is an outage. Anything else is new to us: the power is still out,
      // so it's shown (and counted) as an outage rather than hidden.
      if (r.type !== "P") warnings.push(`unknown interruption type "${r.type}" in ${r.locality}: shown as an outage`);
      kind = "outage";
    }
    items.push({
      kind,
      customers: r.customers,
      started_at: r.startedAt,
      estimated_end_at: r.estimatedEndAt,
      status: STATUS[r.status] ?? null,
      cause: causeOf(r.cause, kind),
      area,
    });
  }
  items.sort((a, b) => b.customers - a.customers || a.started_at.getTime() - b.started_at.getTime());
  return { items, warnings };
}

function plannedArea(r: PlannedRow): Area | null {
  if (r.municipality === PLANNED_TEMISCAMING) return "temiscaming";
  if (r.municipality === PLANNED_KIPAWA && distanceToLineKm([LAC_TEE], r.point) <= LAC_TEE_RADIUS_KM) return "lac_tee";
  return null;
}

/**
 * Upcoming planned interruptions here: not started yet, starting within 14
 * days, soonest first. Ones already under way show up in the current list as
 * "I" rows instead.
 */
export function plannedHere(rows: PlannedRow[], now: Date): Filtered<Planned> {
  const warnings: string[] = [];
  const items: Planned[] = [];
  for (const r of rows) {
    const area = plannedArea(r);
    if (!area) continue;
    if (r.shiftedStart || r.shiftedEnd) warnings.push(`notice ${r.notice}: "shifted" dates present (not used)`);
    const starts = r.actualStart ?? r.plannedStart;
    const ends = r.actualEnd ?? r.plannedEnd;
    if (starts <= now || starts.getTime() - now.getTime() > PLANNED_AHEAD_MS) continue;
    const moved = starts.getTime() !== r.plannedStart.getTime();
    const hasAlternate = r.postponedStart && r.postponedEnd && r.postponedStart.getTime() !== starts.getTime();
    items.push({
      notice: r.notice,
      customers: r.customers,
      starts_at: starts,
      ends_at: ends,
      original_starts_at: moved ? r.plannedStart : null,
      change: moved ? "postponed" : null,
      alternate_starts_at: hasAlternate ? r.postponedStart : null,
      alternate_ends_at: hasAlternate ? r.postponedEnd : null,
      area,
    });
  }
  items.sort((a, b) => a.starts_at.getTime() - b.starts_at.getTime());
  return { items, warnings };
}
