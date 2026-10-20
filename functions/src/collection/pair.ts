// Joins the French and English calendars and turns pickup entries into one
// clean pickup per sector (spec §2, §5).
import { CalendarEntry } from "./parse";
import { classify, isIrregular, Material, SectorId, Special } from "./classify";

/** One pickup for one sector, from the Town's calendar. */
export interface Pickup {
  /** "2026-10-06_town_compost": date + sector + what's picked up (spec D3). */
  id: string;
  date: string;
  sector: SectorId;
  material: Material | null;
  special: Special | null;
  /** The Town's event number ("" when the pickup didn't come from the Town). */
  eventId: string;
  titleFr: string;
  titleEn: string;
  urlFr: string;
  urlEn: string;
  /** True when a bin pickup isn't on the sector's usual weekday. */
  irregular: boolean;
}

export interface PairResult {
  pickups: Pickup[];
  warnings: string[];
}

export function pickupId(date: string, sector: SectorId, what: Material | Special): string {
  return `${date}_${sector}_${what}`;
}

/**
 * French and English entries share event numbers, and the same event can be
 * listed under several days, so entries are matched on date + event number.
 * Duplicates (the same bin for the same sector on the same day, even under
 * different event numbers) are kept once.
 */
export function buildPickups(fr: CalendarEntry[], en: CalendarEntry[]): PairResult {
  const key = (e: CalendarEntry) => `${e.date}/${e.eventId}`;
  const english = new Map(en.map((e) => [key(e), e]));
  const french = new Map(fr.map((e) => [key(e), e]));
  // Every entry once: French first, then any English-only ones.
  const keys = [...new Set([...french.keys(), ...english.keys()])];

  const byId = new Map<string, Pickup>();
  const warnings = new Set<string>();

  for (const k of keys) {
    const f = french.get(k);
    const e = english.get(k);
    const entry = (f ?? e)!;
    const result = classify(entry);
    if (!result) continue; // not a pickup
    result.warnings.forEach((w) => warnings.add(w));
    const what = result.material ?? result.special;
    if (!what) continue;

    for (const sector of result.sectors) {
      const id = pickupId(entry.date, sector, what);
      if (byId.has(id)) continue; // duplicate entry
      const irregular = result.material !== null && isIrregular(entry.date, sector);
      if (irregular) {
        warnings.add(`${sector} ${result.material} pickup on an unusual day: ${entry.date} "${entry.title}"`);
      }
      byId.set(id, {
        id,
        date: entry.date,
        sector,
        material: result.material,
        special: result.special,
        eventId: entry.eventId,
        titleFr: f?.title ?? "",
        titleEn: e?.title ?? "",
        urlFr: f?.url ?? "",
        urlEn: e?.url ?? "",
        irregular,
      });
    }
  }

  const pickups = [...byId.values()].sort(
    (a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id),
  );
  return { pickups, warnings: [...warnings] };
}
