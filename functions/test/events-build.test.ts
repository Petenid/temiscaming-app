// Tests the events step on the real calendar pages saved on 2026-10-19 (all
// of 2026 and January 2027, French and English): spec events-calendar §8,
// step 1.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { decodePage } from "../src/alerts/parse";
import { isPickupIcon } from "../src/collection/classify";
import { buildPickups } from "../src/collection/pair";
import { CalendarEntry, parseMonth } from "../src/collection/parse";
import { buildEvents, TownEvent } from "../src/events/build";

const DIR = join(__dirname, "fixtures/calendar/2026-10-19");
const pad = (n: number) => String(n).padStart(2, "0");

function month(lang: "fr" | "en", year: number, m: number): CalendarEntry[] {
  return parseMonth(decodePage(readFileSync(join(DIR, `${lang}-${year}-${pad(m)}.html`))), year, m);
}

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);
const fr = MONTHS.flatMap((m) => month("fr", 2026, m));
const en = MONTHS.flatMap((m) => month("en", 2026, m));
const { events, warnings } = buildEvents(fr, en);
const find = (id: string) => events.find((e) => e.id === id) as TownEvent;

describe("events from the 2026 calendar", () => {
  it("finds the 73 events, each in both languages", () => {
    expect(events).toHaveLength(73);
    expect(events.every((e) => e.urlFr.includes("/fr/evenements/") && e.urlEn.includes("/en/events/"))).toBe(true);
    expect(warnings.filter((w) => w.includes("only on the"))).toEqual([]);
  });

  it("never mixes pickups and events: every entry goes to exactly one side", () => {
    const pickups = buildPickups(fr, en).pickups;
    const eventIds = new Set(events.map((e) => e.id));
    for (const entry of [...fr, ...en]) {
      const where = `${entry.date} ${entry.title}`;
      if (isPickupIcon(entry.icon)) {
        // A pickup: never an event, and the bin schedule has it that day
        // (duplicates with another event number are collapsed there, spec §2).
        expect(eventIds.has(entry.eventId), where).toBe(false);
        expect(pickups.some((p) => p.date === entry.date), where).toBe(true);
      } else {
        // An event: never a pickup.
        expect(eventIds.has(entry.eventId), where).toBe(true);
        expect(pickups.some((p) => p.eventId === entry.eventId), where).toBe(false);
      }
    }
    // The waste-management conference has "waste" in its title but is an event.
    expect(find("143210").titleEn).toContain("WASTE MANAGEMENT CONFERENCE");
    expect(find("143210").category).toBe("community");
  });

  it("reads a show with its translated place", () => {
    expect(find("138263")).toEqual({
      id: "138263",
      category: "culture",
      titleFr: "ANTHONY KAVANAGH | HAPPY",
      titleEn: "ANTHONY KAVANAGH | HAPPY",
      originalLanguage: "both",
      placeFr: "Le Centre - Salle Dottori",
      placeEn: "The Centre - Dottori Hall",
      startsOn: "2026-03-21",
      endsOn: "2026-03-21",
      urlFr: expect.stringContaining("/fr/evenements/2026/3/21/138263/"),
      urlEn: expect.stringContaining("/en/events/2026/3/21/138263/"),
    });
  });

  it("gives each icon its category", () => {
    expect(find("140952")).toMatchObject({ category: "council", titleEn: "Regular session" });
    expect(find("135108")).toMatchObject({ category: "service-canada", titleFr: "SERVICE CANADA" });
    expect(find("143320")).toMatchObject({ category: "closure", titleFr: "HÔTEL DE VILLE FERMÉ", titleEn: "TOWN HALL CLOSED" });
    expect(find("145424").category).toBe("culture"); // museum expo (theatre masks)
    expect(find("140964").category).toBe("community"); // hockey tournament
    expect(warnings.filter((w) => w.includes("unfamiliar icon"))).toEqual([]);
    const counts: Record<string, number> = {};
    for (const e of events) counts[e.category] = (counts[e.category] ?? 0) + 1;
    expect(counts).toEqual({ closure: 24, council: 16, "service-canada": 12, culture: 10, community: 11 });
  });

  it("joins multi-day events into one, from first to last day", () => {
    expect(find("140964")).toMatchObject({ startsOn: "2026-01-23", endsOn: "2026-01-25" }); // hockey
    expect(find("145424")).toMatchObject({ startsOn: "2026-08-10", endsOn: "2026-08-13" }); // museum expo
    expect(find("143335")).toMatchObject({ startsOn: "2026-12-21", endsOn: "2026-12-25" }); // Town hall closed
    expect(find("143336")).toMatchObject({ startsOn: "2026-12-28", endsOn: "2026-12-31" });
  });

  it("takes the real first day from the link when it's in an earlier month", () => {
    // Town hall closed from 29 December 2025; January's page lists it from the 1st.
    expect(find("135102")).toMatchObject({ startsOn: "2025-12-29", endsOn: "2026-01-02" });
  });

  it("keeps the council meeting with no title, and says so (spec D3)", () => {
    expect(find("143095")).toMatchObject({
      category: "council", titleFr: "", titleEn: "", originalLanguage: "none",
      placeFr: "Le Centre - Salon Desjardins", startsOn: "2026-03-11",
    });
    expect(warnings).toContain("event 143095 on 2026-03-11 has no title");
  });

  it("finds nothing in a month the Town hasn't posted (January 2027)", () => {
    expect(buildEvents(month("fr", 2027, 1), month("en", 2027, 1)).events).toEqual([]);
  });
});

describe("one-language events", () => {
  it("keeps an event the English calendar doesn't have, labelled French", () => {
    const march = month("fr", 2026, 3);
    const { events: only, warnings: w } = buildEvents(march, []);
    const show = only.find((e) => e.id === "138263")!;
    expect(show).toMatchObject({ titleFr: "ANTHONY KAVANAGH | HAPPY", titleEn: "", originalLanguage: "fr", placeEn: "", urlEn: "" });
    expect(w).toContain("event 138263 is only on the French calendar");
  });
});
