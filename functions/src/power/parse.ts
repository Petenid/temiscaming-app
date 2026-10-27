// Reading Hydro-Québec's open outage data (spec power-outages §2, D3).
//
// Each list takes two requests: a "version" file holding a timestamp, then the
// list named after it. Rows are plain arrays, not objects, so each field is
// read by its position (documented on donnees.hydroquebec.com, checked against
// the live files on 2026-10-27).
//
// This file only checks shape and turns text into dates and numbers. Which
// rows are about Témiscaming is decided in filter.ts.
import { torontoToUtc } from "../alerts/dates";

const BASE = "https://pannes.hydroquebec.com/pannes/donnees/v3_0";

export const POWER_URLS = {
  ongoingVersion: `${BASE}/bisversion.json`,
  ongoing: (version: string) => `${BASE}/bismarkers${version}.json`,
  plannedVersion: `${BASE}/aipversion.json`,
  planned: (version: string) => `${BASE}/aipmarkers${version}.json`,
} as const;

/** "2026-10-27 13:34:28" — Montréal wall-clock time, seconds kept — → Date. */
export function parseLocalDateTime(text: unknown): Date | null {
  if (typeof text !== "string") return null;
  const m = text.trim().match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return null;
  const [, y, mo, d, h, mi, sec] = m.map(Number);
  return new Date(torontoToUtc(y, mo, d, h, mi).getTime() + sec * 1000);
}

/** `"20261027134010"` → the version string and the time it stands for (Montréal time). */
export interface Version {
  id: string;
  at: Date;
}

export function parseVersion(text: string): Version {
  const m = text.trim().match(/^"?(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})"?$/);
  if (!m) throw new Error(`version: unexpected answer "${text.trim().slice(0, 40)}"`);
  const at = parseLocalDateTime(`${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}:${m[6]}`);
  if (!at) throw new Error(`version: not a date "${m[0]}"`);
  return { id: m.slice(1).join(""), at };
}

/** `"[-79.38, 47.36]"` → [longitude, latitude]. */
function parsePoint(value: unknown, what: string): [number, number] {
  let p: unknown;
  try {
    p = typeof value === "string" ? JSON.parse(value) : value;
  } catch {
    throw new Error(`${what}: coordinates aren't readable`);
  }
  if (!Array.isArray(p) || p.length !== 2 || !p.every((n) => typeof n === "number" && Number.isFinite(n))) {
    throw new Error(`${what}: coordinates aren't [longitude, latitude]`);
  }
  const [lon, lat] = p as number[];
  if (lon < -90 || lon > -55 || lat < 40 || lat > 63) throw new Error(`${what}: coordinates outside Quebec`);
  return [lon, lat];
}

function customersOf(value: unknown, what: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new Error(`${what}: customer count isn't a whole number`);
  }
  return value;
}

/** A date that may be blank (""); anything else unreadable is a shape problem. */
function optionalDate(value: unknown, what: string): Date | null {
  if (value === "" || value === null || value === undefined) return null;
  const d = parseLocalDateTime(value);
  if (!d) throw new Error(`${what}: unreadable date "${String(value).slice(0, 30)}"`);
  return d;
}

const str = (v: unknown) => (typeof v === "string" ? v.trim() : typeof v === "number" ? String(v) : "");

// --- Ongoing interruptions ("bismarkers") ---

/**
 * One row: [customers, start, estimated end, type, "[lon, lat]", status,
 * (unused), cause, locality, message id].
 */
export interface OngoingRow {
  customers: number;
  startedAt: Date;
  /** Hydro-Québec's estimate; often blank on a new outage. */
  estimatedEndAt: Date | null;
  /** "P" outage, "I" planned interruption in progress (seen live, not documented). */
  type: string;
  point: [number, number];
  /** "A" work assigned, "R" crew on the way, "L" crew at work; "N" and "" also seen. */
  status: string;
  cause: string;
  /** Hydro-Québec's own 4-digit locality ID (not the government code): Témiscaming = "9130". */
  locality: string;
}

export function parseOngoing(json: unknown): OngoingRow[] {
  if (!json || typeof json !== "object" || !Array.isArray((json as { pannes?: unknown }).pannes)) {
    throw new Error("ongoing: no \"pannes\" list");
  }
  const rows = (json as { pannes: unknown[] }).pannes;
  // Hydro-Québec always has some interruption somewhere in Quebec (105 on a
  // quiet Tuesday), so an empty list is more likely a broken file (spec D3).
  if (rows.length === 0) throw new Error("ongoing: empty list for all of Quebec");
  return rows.map((row, i) => {
    const what = `ongoing row ${i + 1}`;
    if (!Array.isArray(row) || row.length !== 10) throw new Error(`${what}: expected 10 fields`);
    const startedAt = optionalDate(row[1], what);
    if (!startedAt) throw new Error(`${what}: no start time`);
    return {
      customers: customersOf(row[0], what),
      startedAt,
      estimatedEndAt: optionalDate(row[2], what),
      type: str(row[3]),
      point: parsePoint(row[4], what),
      status: str(row[5]),
      cause: str(row[7]),
      locality: str(row[8]),
    };
  });
}

// --- Planned interruptions ("aipmarkers") ---

/**
 * One row: [customers, notice no., planned start, planned end, "actual" start,
 * "actual" end, postponed start, postponed end, shifted start, shifted end,
 * cause, equipment, remark, municipality, status, "[lon, lat]"].
 *
 * Read from the live file: the "actual" pair is the date currently scheduled
 * (it equals the planned date until the work is moved); the "postponed" pair,
 * when present and different, is the backup date Hydro-Québec gives in case
 * the work can't go ahead (e.g. weather). The "shifted" pair was always empty.
 */
export interface PlannedRow {
  customers: number;
  notice: string;
  plannedStart: Date;
  plannedEnd: Date;
  actualStart: Date | null;
  actualEnd: Date | null;
  postponedStart: Date | null;
  postponedEnd: Date | null;
  shiftedStart: Date | null;
  shiftedEnd: Date | null;
  cause: string;
  /** The government's 5-digit municipality code: Témiscaming (V) = "85005". */
  municipality: string;
  point: [number, number];
}

export function parsePlanned(json: unknown): PlannedRow[] {
  if (!Array.isArray(json)) throw new Error("planned: not a list");
  if (json.length === 0) throw new Error("planned: empty list for all of Quebec");
  return json.map((row, i) => {
    const what = `planned row ${i + 1}`;
    if (!Array.isArray(row) || row.length !== 16) throw new Error(`${what}: expected 16 fields`);
    const plannedStart = optionalDate(row[2], what);
    const plannedEnd = optionalDate(row[3], what);
    if (!plannedStart || !plannedEnd) throw new Error(`${what}: no planned dates`);
    return {
      customers: customersOf(row[0], what),
      notice: str(row[1]),
      plannedStart,
      plannedEnd,
      actualStart: optionalDate(row[4], what),
      actualEnd: optionalDate(row[5], what),
      postponedStart: optionalDate(row[6], what),
      postponedEnd: optionalDate(row[7], what),
      shiftedStart: optionalDate(row[8], what),
      shiftedEnd: optionalDate(row[9], what),
      cause: str(row[10]),
      municipality: str(row[13]),
      point: parsePoint(row[15], what),
    };
  });
}
