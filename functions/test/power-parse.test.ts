// Reading Hydro-Québec's files and picking out Témiscaming (spec power-outages
// §2, D1–D3, §8 step 1), on the real files saved by Capture fixtures → power.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { LORRAINVILLE_P, ongoingRow, plannedRow, REAL, realJson } from "./power-helpers";

import { causeOf, ongoingHere, plannedHere } from "../src/power/filter";
import { parseOngoing, parsePlanned, parseVersion, POWER_URLS } from "../src/power/parse";

describe("parseVersion", () => {
  it("reads the quoted timestamp as Montréal time", () => {
    expect(parseVersion('"20261027134010"')).toEqual({ id: "20261027134010", at: new Date("2026-10-27T17:40:10Z") });
    expect(parseVersion("20261227134010\n").at).toEqual(new Date("2026-12-27T18:40:10Z")); // winter: UTC-5
  });

  it("refuses anything else", () => {
    expect(() => parseVersion("<html>Service unavailable</html>")).toThrow(/version/);
    expect(() => parseVersion('"2026102713"')).toThrow(/version/);
  });

  it("builds the list URLs from the version", () => {
    expect(POWER_URLS.ongoing("20261027134010"))
      .toBe("https://pannes.hydroquebec.com/pannes/donnees/v3_0/bismarkers20261027134010.json");
    expect(POWER_URLS.planned("20261027132005"))
      .toBe("https://pannes.hydroquebec.com/pannes/donnees/v3_0/aipmarkers20261027132005.json");
  });
});

describe("the real files (2026-10-27)", () => {
  it("version files are readable", () => {
    for (const f of ["bisversion.json", "aipversion.json"]) {
      expect(parseVersion(readFileSync(join(REAL, f), "utf-8")).id).toMatch(/^20261027\d{6}$/);
    }
  });

  it("every current interruption in Quebec parses; nothing in Témiscaming that day", () => {
    const rows = parseOngoing(realJson("bismarkers.json"));
    expect(rows.length).toBe(29); // a quiet afternoon (105 at 13:40)
    expect(rows.every((r) => r.locality.length === 4)).toBe(true);
    expect(rows.some((r) => r.type === "P")).toBe(true);
    expect(ongoingHere(rows).items).toEqual([]);
  });

  it("every planned interruption in Quebec parses; municipality codes are 5 digits", () => {
    const rows = parsePlanned(realJson("aipmarkers.json"));
    expect(rows.length).toBe(197);
    expect(rows.every((r) => /^\d{5}$/.test(r.municipality))).toBe(true);
  });

  it("Hydro-Québec's own list ties our IDs to their names (spec D1)", () => {
    const places: { id: string; nom: string; parentId: string }[] = JSON.parse(readFileSync(join(__dirname, "fixtures/power/hand-copied/places-temiscamingue-2026-10-27.json"), "utf-8"));
    const byId = new Map(places.map((p) => [p.id, p]));
    expect(byId.get("85005")?.nom).toBe("Témiscaming (V)");
    expect(byId.get("85010")?.nom).toBe("Kipawa (M)");
    expect(byId.get("9130")).toMatchObject({ nom: "Témiscaming", parentId: "85005" });
    expect(byId.get("9124")).toMatchObject({ nom: "Tee Lake", parentId: "85010" });
    // Témiscaming is one locality: Lumsden and Letang aren't listed separately.
    expect(places.filter((p) => p.parentId === "85005").map((p) => p.id)).toEqual(["9130"]);
  });
});

describe("parseOngoing", () => {
  it("reads every field of a real row", () => {
    expect(parseOngoing({ messages: {}, pannes: [LORRAINVILLE_P] })).toEqual([{
      customers: 29,
      startedAt: new Date("2026-10-27T17:34:28Z"),
      estimatedEndAt: new Date("2026-10-27T20:15:00Z"),
      type: "P",
      point: [-79.38738470629734, 47.361124583378896],
      status: "L",
      cause: "11",
      locality: "4434",
    }]);
  });

  it("a blank estimate is 'no estimate yet', not an error", () => {
    expect(parseOngoing({ pannes: [ongoingRow({ locality: "9130", end: "" })] })[0].estimatedEndAt).toBeNull();
  });

  it("silence ≠ safety: empty, wrong shape or unreadable rows are failures (spec D3)", () => {
    expect(() => parseOngoing({ messages: {}, pannes: [] })).toThrow(/empty/);
    expect(() => parseOngoing([])).toThrow(/pannes/);
    expect(() => parseOngoing({ pannes: [LORRAINVILLE_P.slice(0, 9)] })).toThrow(/10 fields/);
    expect(() => parseOngoing({ pannes: [ongoingRow({ locality: "9130", start: "" })] })).toThrow(/start/);
    const badPoint = [...LORRAINVILLE_P];
    badPoint[4] = "[2.35, 48.85]";
    expect(() => parseOngoing({ pannes: [badPoint] })).toThrow(/outside Quebec/);
    const badCount = [...LORRAINVILLE_P];
    badCount[0] = "29";
    expect(() => parseOngoing({ pannes: [badCount] })).toThrow(/customer/);
  });
});

describe("ongoingHere (spec D1, D2, D8)", () => {
  const rows = parseOngoing({
    pannes: [
      LORRAINVILLE_P,
      ongoingRow({ locality: "9130", customers: 120, status: "R", cause: "21" }),
      ongoingRow({ locality: "9124", customers: 14, type: "I", status: "L", cause: "62" }),
      ongoingRow({ locality: "1000", customers: 3000 }),
      ongoingRow({ locality: "9130", customers: 2, status: "N", cause: "" }),
    ],
  });

  it("keeps Témiscaming (9130) and Lac Tee (9124) only, biggest first", () => {
    const { items } = ongoingHere(rows);
    expect(items.map((o) => [o.area, o.customers])).toEqual([["temiscaming", 120], ["lac_tee", 14], ["temiscaming", 2]]);
  });

  it("labels kind, crew status and cause; unknown codes stay blank", () => {
    const [big, lacTee, small] = ongoingHere(rows).items;
    expect(big).toMatchObject({ kind: "outage", status: "on_the_way", cause: "weather", estimated_end_at: null });
    expect(lacTee).toMatchObject({ kind: "planned_in_progress", status: "at_work", cause: "planned_work" });
    expect(small).toMatchObject({ kind: "outage", status: null, cause: null });
  });

  it("an unknown type is still shown as an outage, with a warning", () => {
    const r = ongoingHere(parseOngoing({ pannes: [ongoingRow({ locality: "9130", type: "X" })] }));
    expect(r.items[0].kind).toBe("outage");
    expect(r.warnings[0]).toMatch(/unknown interruption type "X"/);
  });

  it("cause groups follow Hydro-Québec's documentation", () => {
    expect(causeOf("11", "outage")).toBe("equipment");
    expect(causeOf("34", "outage")).toBe("accident");
    expect(causeOf("51", "outage")).toBe("vegetation");
    expect(causeOf("53", "outage")).toBe("animal");
    expect(causeOf("62", "outage")).toBeNull(); // only documented for planned work
  });
});

describe("parsePlanned + plannedHere (spec D1, D2)", () => {
  const NOW = new Date("2026-10-27T18:00:00Z");
  const KIPAWA_VILLAGE = "[-78.9833, 46.7833]";
  const NEAR_LAC_TEE = "[-79.04, 46.775]";

  it("reads a real row (a postponed one: planned 25 Oct, now 4 Nov)", () => {
    const [r] = parsePlanned([[
      2, "189040", "2026-10-25 06:00:00", "2026-10-26 19:00:00", "2026-11-04 06:00:00", "2026-11-05 19:00:00",
      "2026-11-04 06:00:00", "2026-11-05 19:00:00", "", "", "71", "99", "60", "99060", "R",
      "[-77.50711665479473, 53.59927961569264]",
    ]]);
    expect(r).toMatchObject({
      notice: "189040", municipality: "99060",
      plannedStart: new Date("2026-10-25T10:00:00Z"), actualStart: new Date("2026-11-04T11:00:00Z"),
      shiftedStart: null,
    });
  });

  it("silence ≠ safety: empty or wrong shape is a failure", () => {
    expect(() => parsePlanned([])).toThrow(/empty/);
    expect(() => parsePlanned({ pannes: [] })).toThrow(/not a list/);
    expect(() => parsePlanned([plannedRow({ start: "2026-10-29 07:30:00", end: "x", municipality: "85005" })])).toThrow(/date/);
  });

  it("keeps Témiscaming, and Kipawa only near Lac Tee; upcoming within 14 days; soonest first", () => {
    const rows = parsePlanned([
      plannedRow({ notice: "a", start: "2026-11-03 08:30:00", end: "2026-11-03 12:00:00", municipality: "85005" }),
      plannedRow({ notice: "b", start: "2026-10-29 08:30:00", end: "2026-10-29 10:30:00", municipality: "85010", point: NEAR_LAC_TEE }),
      plannedRow({ notice: "c", start: "2026-10-29 08:30:00", end: "2026-10-29 10:30:00", municipality: "85010", point: KIPAWA_VILLAGE }),
      plannedRow({ notice: "d", start: "2026-10-28 08:30:00", end: "2026-10-28 10:30:00", municipality: "85085" }),
      plannedRow({ notice: "e", start: "2026-10-27 13:00:00", end: "2026-10-27 16:00:00", municipality: "85005" }), // under way
      plannedRow({ notice: "f", start: "2026-11-20 08:30:00", end: "2026-11-20 12:00:00", municipality: "85005" }), // > 14 days
    ]);
    const { items } = plannedHere(rows, NOW);
    expect(items.map((p) => [p.notice, p.area])).toEqual([["b", "lac_tee"], ["a", "temiscaming"]]);
    expect(items[1]).toMatchObject({
      starts_at: new Date("2026-11-03T13:30:00Z"), ends_at: new Date("2026-11-03T17:00:00Z"),
      change: null, original_starts_at: null, alternate_starts_at: null,
    });
  });

  it("a moved interruption shows its new date, the original, and the backup date", () => {
    const rows = parsePlanned([
      plannedRow({
        notice: "m", municipality: "85005", start: "2026-10-28 08:30:00", end: "2026-10-28 14:30:00",
        actual: ["2026-10-29 08:30:00", "2026-10-29 14:30:00"], backup: ["2026-11-05 08:30:00", "2026-11-05 14:30:00"],
      }),
    ]);
    expect(plannedHere(rows, NOW).items[0]).toMatchObject({
      starts_at: new Date("2026-10-29T12:30:00Z"),
      change: "postponed", original_starts_at: new Date("2026-10-28T12:30:00Z"),
      alternate_starts_at: new Date("2026-11-05T13:30:00Z"), alternate_ends_at: new Date("2026-11-05T19:30:00Z"),
    });
  });
});
