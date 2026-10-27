// Shared by the power-outage tests: the real files, and rows built the way
// Hydro-Québec writes them (positions as documented, values as seen live).
import { readFileSync } from "node:fs";
import { join } from "node:path";

export const REAL = join(__dirname, "fixtures/power/2026-10-27");
export const realJson = (name: string) => JSON.parse(readFileSync(join(REAL, name), "utf-8"));

// Rows as they appear in the live files (the Lorrainville outage was real, 2026-10-27 13:40).
export const LORRAINVILLE_P = [
  29, "2026-10-27 13:34:28", "2026-10-27 16:15:00", "P", "[-79.38738470629734, 47.361124583378896]",
  "L", "1", "11", "4434", "",
];
export const ongoingRow = (o: { customers?: number; start?: string; end?: string; type?: string; status?: string; cause?: string; locality: string }) => [
  o.customers ?? 120, o.start ?? "2026-10-27 14:05:00", o.end ?? "", o.type ?? "P",
  "[-79.0975, 46.7213]", o.status ?? "", "", o.cause ?? "", o.locality, "",
];
export const plannedRow = (o: {
  notice?: string; start: string; end: string; actual?: [string, string]; backup?: [string, string];
  municipality: string; point?: string;
}) => [
  63, o.notice ?? "190001", o.start, o.end, o.actual?.[0] ?? o.start, o.actual?.[1] ?? o.end,
  o.backup?.[0] ?? "", o.backup?.[1] ?? "", "", "", "62", "32", "", o.municipality, "N",
  o.point ?? "[-79.0975, 46.7213]",
];
