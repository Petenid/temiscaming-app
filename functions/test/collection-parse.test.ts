// Tests the calendar parser on real pages saved on 2026-10-19 (all of 2026
// and January 2027, French and English), and checks the result against the
// MRC's printed calendar, an independent source (spec §8, step 2).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { decodePage } from "../src/alerts/parse";
import { classify, SectorId } from "../src/collection/classify";
import { buildPickups, Pickup } from "../src/collection/pair";
import { CalendarEntry, monthUrl, parseMonth } from "../src/collection/parse";

const DIR = join(__dirname, "fixtures/calendar/2026-10-19");
const pad = (n: number) => String(n).padStart(2, "0");

function month(lang: "fr" | "en", year: number, m: number): CalendarEntry[] {
  const html = decodePage(readFileSync(join(DIR, `${lang}-${year}-${pad(m)}.html`)));
  return parseMonth(html, year, m);
}

const MONTHS_2026 = Array.from({ length: 12 }, (_, i) => i + 1);
const fr2026 = MONTHS_2026.flatMap((m) => month("fr", 2026, m));
const en2026 = MONTHS_2026.flatMap((m) => month("en", 2026, m));
const { pickups, warnings } = buildPickups(fr2026, en2026);
const of = (sector: SectorId) => pickups.filter((p) => p.sector === sector);
const find = (id: string) => pickups.find((p) => p.id === id);

describe("month pages", () => {
  it("read every event under its day heading", () => {
    const october = month("fr", 2026, 10);
    expect(october).toHaveLength(14);
    expect(october.find((e) => e.eventId === "141942")).toEqual({
      date: "2026-10-06",
      eventId: "141942",
      url: "https://www.temiscaming.net/fr/evenements/2026/10/6/141942/collecte-des-matieres-compostables-temiscaming-lac-tee-et-chemins-des-chalets",
      icon: "pm-compost-bin-a",
      title: "COLLECTE DES MATIÈRES COMPOSTABLES -- TÉMISCAMING, LAC TEE ET CHEMINS DES CHALETS",
      place: "",
      linkDate: "2026-10-06",
    });
  });

  it("read the first of the month, written 1er in French", () => {
    expect(month("fr", 2026, 12).find((e) => e.eventId === "141960")?.date).toBe("2026-12-01");
  });

  it("give the same dates and events in English (month-first headings) as in French", () => {
    for (const m of MONTHS_2026) {
      const keys = (es: CalendarEntry[]) => es.map((e) => `${e.date}/${e.eventId}`).sort();
      // One English-only event exists (a conference on 25 March); compare pickups only.
      const pickupsOnly = (es: CalendarEntry[]) => es.filter((e) => /-bin|fir/.test(e.icon ?? ""));
      expect(keys(pickupsOnly(month("en", 2026, m)))).toEqual(keys(pickupsOnly(month("fr", 2026, m))));
    }
  });

  it("date a multi-day event by each day heading, not by its link", () => {
    const trees = month("fr", 2026, 1).filter((e) => e.eventId === "135106");
    expect(trees.map((e) => e.date)).toEqual(["2026-01-05", "2026-01-06", "2026-01-07", "2026-01-08"]);
  });

  it("find nothing (and don't crash) in a month the Town hasn't posted", () => {
    expect(month("fr", 2027, 1)).toEqual([]);
    expect(month("en", 2027, 1)).toEqual([]);
  });

  it("build month addresses", () => {
    expect(monthUrl("fr", 2026, 11)).toBe("https://www.temiscaming.net/fr/calendrier?year=2026&month=11");
    expect(monthUrl("en", 2027, 1)).toBe("https://www.temiscaming.net/en/calendar?year=2027&month=1");
  });
});

describe("classifying entries", () => {
  const entry = (icon: string | null, title: string) => ({ icon, title, date: "2026-10-06" });

  it("ignore events without a bin icon, even with 'waste' in the title", () => {
    expect(classify(entry("pm-group-hands-up", "5 TO 7 | WASTE MANAGEMENT CONFERENCE"))).toBeNull();
    expect(classify(entry("pm-gavel", "Séance ordinaire du conseil"))).toBeNull();
  });

  it("read material from the icon and sector from the title", () => {
    expect(classify(entry("pm-trash-bin-b", "HOUSEHOLD WASTE DISPOSAL -- LETANG AND LUMSDEN SECTORS")))
      .toEqual({ material: "garbage", special: null, sectors: ["lumsden"], warnings: [] });
  });

  it("give an event with no area (Christmas trees) to both sectors", () => {
    expect(classify(entry("pm-fir", "COLLECTE DES SAPINS DE NOËL")))
      .toEqual({ material: null, special: "christmas-trees", sectors: ["town", "lumsden"], warnings: [] });
  });

  it("warn about an unfamiliar area and give it to no one (schedule check)", () => {
    const r = classify(entry("pm-recycling-bin-a", "COLLECTE DES MATIÈRES RECYCLABLES -- HAUT DE LA VILLE"))!;
    expect(r.sectors).toEqual([]);
    expect(r.warnings.join()).toMatch(/unfamiliar area "HAUT DE LA VILLE"/);
  });

  it("warn when the icon and the title disagree", () => {
    expect(classify(entry("pm-compost-bin-a", "COLLECTE DES MATIÈRES RECYCLABLES -- TÉMISCAMING"))!.warnings.join())
      .toMatch(/icon says compost but title says recycling/);
    expect(classify(entry("pm-compost-bin-b", "COLLECTE DES MATIÈRES COMPOSTABLES -- TÉMISCAMING"))!.warnings.join())
      .toMatch(/doesn't match the area/);
  });
});

describe("pickups for 2026", () => {
  it("have French and English titles and links for every pickup", () => {
    for (const p of pickups) {
      expect(p.titleFr, p.id).not.toBe("");
      expect(p.titleEn, p.id).not.toBe("");
      expect(p.urlEn, p.id).toMatch(/^https:\/\/www\.temiscaming\.net\/en\/events\//);
    }
  });

  it("collapse duplicates posted under different event numbers", () => {
    expect(fr2026.filter((e) => e.date === "2026-12-02" && e.icon === "pm-compost-bin-b")).toHaveLength(2);
    expect(pickups.filter((p) => p.id === "2026-12-02_lumsden_compost")).toHaveLength(1);
  });

  it("handle two bins on one day (22 December, town)", () => {
    expect(of("town").filter((p) => p.date === "2026-12-22").map((p) => p.material).sort())
      .toEqual(["compost", "recycling"]);
  });

  it("flag the June shift and the odd 27 January pickup as irregular", () => {
    expect(find("2026-06-25_lumsden_recycling")?.irregular).toBe(true);
    expect(find("2026-01-27_lumsden_garbage")?.irregular).toBe(true);
    expect(pickups.filter((p) => p.irregular).map((p) => p.id).sort())
      .toEqual(["2026-01-27_lumsden_garbage", "2026-06-25_lumsden_recycling"]);
    expect(warnings.filter((w) => /unusual day/.test(w))).toHaveLength(2);
  });

  it("give the Christmas-tree pickup to both sectors on each of its four days", () => {
    expect(pickups.filter((p) => p.special === "christmas-trees")).toHaveLength(8);
  });

  it("raise no other warnings on real data", () => {
    expect(warnings.filter((w) => !/unusual day/.test(w))).toEqual([]);
  });
});

// The MRC calendar, read from its printed PDF by tools/mrc_calendar.py.
interface MrcData { sectors: Record<SectorId, { date: string; materials: string[] }[]> }
const mrc: MrcData = JSON.parse(readFileSync(join(__dirname, "../data/mrc-2026.json"), "utf-8"));

/** Monday of the week containing `date`, as "YYYY-MM-DD". */
function weekOf(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  const day = new Date(Date.UTC(y, m - 1, d));
  day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7));
  return day.toISOString().slice(0, 10);
}

describe("Town calendar vs MRC calendar, every week of 2026", () => {
  const disagreements: string[] = [];
  for (const sector of ["town", "lumsden"] as SectorId[]) {
    const weeks = new Map<string, { town: string[]; mrc: string[] }>();
    const week = (date: string) => {
      const k = weekOf(date);
      if (!weeks.has(k)) weeks.set(k, { town: [], mrc: [] });
      return weeks.get(k)!;
    };
    for (const p of of(sector).filter((p: Pickup) => p.material)) week(p.date).town.push(`${p.date} ${p.material}`);
    for (const p of mrc.sectors[sector]) for (const m of p.materials) week(p.date).mrc.push(`${p.date} ${m}`);
    for (const [k, w] of [...weeks].sort()) {
      if (w.town.sort().join() !== w.mrc.sort().join()) disagreements.push(`${sector} ${k}`);
    }
  }

  it("agree from February to December", () => {
    expect(disagreements.filter((d) => d.split(" ")[1] >= "2026-02-01")).toEqual([]);
  });

  it("disagree only in the known January weeks (Town missing 6–21 Jan; extra Lumsden garbage 27 Jan)", () => {
    expect(disagreements.sort()).toEqual([
      "lumsden 2026-01-05", "lumsden 2026-01-12", "lumsden 2026-01-19", "lumsden 2026-01-26",
      "town 2026-01-05", "town 2026-01-12", "town 2026-01-19",
    ]);
  });
});
