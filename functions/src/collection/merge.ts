// Combines the Town's calendar with the MRC's printed calendar (spec D4, D11).
//
// For each sector and week (Monday to Sunday):
//   - the Town posted bin pickups that week → the Town's pickups, and if the
//     MRC disagrees, a warning (D11: the Town wins);
//   - the Town never posted that week → the MRC's pickups, marked "mrc";
//   - the Town had posted that week before, but nothing now → nothing: the
//     Town cancelled it, and the MRC must not quietly bring it back.
import { Material, SectorId, SECTORS } from "./classify";
import { Pickup, pickupId } from "./pair";

export type Origin = "town" | "mrc";

export interface MergedPickup extends Pickup {
  origin: Origin;
}

/** The MRC calendar as written by tools/mrc_calendar.py (functions/data/mrc-<year>.json). */
export interface MrcCalendar {
  year: number;
  sectors: Record<SectorId, { date: string; materials: Material[] }[]>;
}

/** Monday of the week containing `date`, as "YYYY-MM-DD". */
export function weekOf(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  const day = new Date(Date.UTC(y, m - 1, d));
  day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7));
  return day.toISOString().slice(0, 10);
}

/** "town 2026-01-05": one sector's week. */
export const weekKey = (sector: SectorId, date: string) => `${sector} ${weekOf(date)}`;

/** The MRC calendars as pickups, for dates in [from, to]. */
export function mrcPickups(calendars: MrcCalendar[], from: string, to: string): Pickup[] {
  const out: Pickup[] = [];
  for (const cal of calendars) {
    for (const sector of SECTORS) {
      for (const entry of cal.sectors[sector] ?? []) {
        if (entry.date < from || entry.date > to) continue;
        for (const material of entry.materials) {
          out.push({
            id: pickupId(entry.date, sector, material),
            date: entry.date, sector, material, special: null,
            eventId: "", titleFr: "", titleEn: "", urlFr: "", urlEn: "",
            irregular: false,
          });
        }
      }
    }
  }
  return out;
}

/** Last date the MRC calendars cover (31 Dec of the latest year), or null. */
export function mrcThrough(calendars: MrcCalendar[]): string | null {
  if (!calendars.length) return null;
  return `${Math.max(...calendars.map((c) => c.year))}-12-31`;
}

/**
 * @param town  the Town's pickups for the months fetched
 * @param mrc   the MRC's pickups for the same dates
 * @param townSeenWeeks  sector-weeks (weekKey) the Town had posted on earlier runs
 * @param mrcCovers  last date the MRC data covers (null: no MRC data); weeks
 *                   after it aren't compared
 */
export function mergeSchedules(
  town: Pickup[], mrc: Pickup[], townSeenWeeks: Set<string>, mrcCovers: string | null,
): { pickups: MergedPickup[]; warnings: string[] } {
  const group = (ps: Pickup[]) => {
    const m = new Map<string, Pickup[]>();
    for (const p of ps) {
      const k = weekKey(p.sector, p.date);
      if (!m.has(k)) m.set(k, []);
      m.get(k)!.push(p);
    }
    return m;
  };
  const townWeeks = group(town.filter((p) => p.material));
  const mrcWeeks = group(mrc);
  const describe = (ps: Pickup[]) =>
    ps.map((p) => `${p.date} ${p.material}`).sort().join(", ") || "nothing";

  const pickups: MergedPickup[] = [];
  const warnings: string[] = [];

  // Every Town pickup is kept, including special collections (Christmas trees).
  for (const p of town) pickups.push({ ...p, origin: "town" });

  for (const [k, fromMrc] of mrcWeeks) {
    const fromTown = townWeeks.get(k);
    if (fromTown) {
      if (describe(fromTown) !== describe(fromMrc)) {
        warnings.push(`Town and MRC differ for ${k}: Town ${describe(fromTown)}; MRC ${describe(fromMrc)}`);
      }
    } else if (!townSeenWeeks.has(k)) {
      for (const p of fromMrc) pickups.push({ ...p, origin: "mrc" });
    }
  }
  // Weeks the Town posted that the MRC has nothing for (e.g. 28-31 Dec).
  for (const [k, fromTown] of townWeeks) {
    const covered = mrcCovers !== null && fromTown.every((p) => p.date <= mrcCovers);
    if (!mrcWeeks.has(k) && covered) {
      warnings.push(`Town and MRC differ for ${k}: Town ${describe(fromTown)}; MRC nothing`);
    }
  }

  pickups.sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id));
  return { pickups, warnings };
}
