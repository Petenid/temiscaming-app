// Runs whole calendar runs (bin pickups, then events from the same pages)
// against the saved pages, with in-memory databases: spec events-calendar §8,
// step 2. Town edits are simulated by editing the real HTML.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { Fetcher } from "../src/alerts/sync";
import { MrcCalendar } from "../src/collection/merge";
import {
  CalendarDownload, CalendarHealth, CollectionStore, StoredPickup, runCollectionPoll,
} from "../src/collection/sync";
import { EventsHealth, EventsStore, StoredEvent, runEventsPoll } from "../src/events/sync";

const DIR = join(__dirname, "fixtures/calendar/2026-10-19");
const MRC_2026: MrcCalendar = JSON.parse(readFileSync(join(__dirname, "../data/mrc-2026.json"), "utf-8"));

function page(lang: "fr" | "en", year: number, month: number): string {
  const name = `${lang}-${year}-${String(month).padStart(2, "0")}.html`;
  try {
    return readFileSync(join(DIR, name), "utf-8");
  } catch {
    return readFileSync(join(DIR, `${lang}-2027-01.html`), "utf-8"); // nothing posted
  }
}

/** Serves the saved pages, after an optional edit (applied to both languages). */
function fetcher(edit: (html: string) => string = (h) => h): Fetcher {
  return {
    async get(url) {
      const lang = url.includes("/fr/") ? "fr" : "en";
      const year = Number(url.match(/year=(\d+)/)![1]);
      const month = Number(url.match(/month=(\d+)/)![1]);
      return new TextEncoder().encode(edit(page(lang, year, month)));
    },
  };
}

const anchors = /<a class="calendar-widget__item" href="[^"]*">[\s\S]*?<\/a>/g;
/** Removes one event from the agenda list. */
const removeEvent = (eventId: string) => (html: string) =>
  html.replace(anchors, (a) => (a.includes(`/${eventId}/`) ? "" : a));
/** Removes every agenda entry that isn't a pickup: a layout change hiding events. */
const removeAllEvents = (html: string) =>
  html.replace(anchors, (a) => (/pm-[a-z]+-bin|pm-fir/.test(a) ? a : ""));

// --- Fakes ---

class FakePickupStore implements CollectionStore {
  docs = new Map<string, StoredPickup>();
  health: CalendarHealth | null = null;
  async loadPickups(from: string) { return [...this.docs.values()].filter((d) => d.date >= from); }
  async savePickups(docs: StoredPickup[]) { docs.forEach((d) => this.docs.set(d.id, { ...d })); }
  async deletePickups(ids: string[]) { ids.forEach((id) => this.docs.delete(id)); }
  async claimPush() { return true; }
  async releasePush() {}
  async loadHealth() { return this.health; }
  async saveHealth(h: CalendarHealth) { this.health = h; }
}

class FakeEventsStore implements EventsStore {
  docs = new Map<string, StoredEvent>();
  health: EventsHealth | null = null;
  saves = 0;
  async loadEvents() { return [...this.docs.values()].map((d) => ({ ...d })); }
  async saveEvents(docs: StoredEvent[]) { this.saves += docs.length; docs.forEach((d) => this.docs.set(d.id, { ...d })); }
  async deleteEvents(ids: string[]) { ids.forEach((id) => this.docs.delete(id)); }
  async loadHealth() { return this.health; }
  async saveHealth(h: EventsHealth) { this.health = h; }
}

/** Noon in Témiscaming on a given day. */
const at = (date: string) => new Date(`${date}T16:00:00Z`);

/** One calendar run as the scheduled function does it: pickups, then events. */
async function calendarRun(
  events: FakeEventsStore, date: string, edit?: (html: string) => string,
  pickups = new FakePickupStore(),
) {
  const now = () => at(date);
  const result = await runCollectionPoll({
    store: pickups, fetcher: fetcher(edit), messenger: { async send() {} }, mrc: [MRC_2026], now,
  });
  const download: CalendarDownload | { error: string } = result.download ?? { error: result.error ?? "?" };
  return { pickups: result, events: await runEventsPoll({ store: events, now }, download) };
}

describe("events step of the calendar run", () => {
  it("first run stores the upcoming events from the same pages as the pickups", async () => {
    const store = new FakeEventsStore();
    const run = await calendarRun(store, "2026-10-20");
    expect(run.pickups.ok).toBe(true);
    expect(run.events).toMatchObject({ ok: true, found: 16 });
    // October to December, minus what ended before 20 October.
    const ids = [...store.docs.keys()];
    expect(ids.length).toBe(run.events.upcoming);
    expect([...store.docs.values()].every((d) => d.ends_on >= "2026-10-20")).toBe(true);
    expect(store.docs.get("143335")).toMatchObject({ starts_on: "2026-12-21", ends_on: "2026-12-25", category: "closure" });
    expect(store.health).toMatchObject({ last_error: "", listed_through: "2026-12-31", last_item_count: 16 });
    expect(store.health!.last_success_at).toEqual(at("2026-10-20"));
  });

  it("the same pages again change nothing", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-10-20");
    const saves = store.saves;
    const before = JSON.stringify([...store.docs.values()]);
    const again = await calendarRun(store, "2026-10-20");
    expect(again.events).toMatchObject({ ok: true, written: 0, deleted: 0 });
    expect(store.saves).toBe(saves);
    expect(JSON.stringify([...store.docs.values()])).toBe(before);
  });

  it("an event the Town removes disappears (spec D7)", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-10-20");
    expect(store.docs.has("143335")).toBe(true);
    const run = await calendarRun(store, "2026-10-20", removeEvent("143335"));
    expect(run.events).toMatchObject({ ok: true, deleted: 1 });
    expect(store.docs.has("143335")).toBe(false);
  });

  it("an event the Town edits shows the new text, keeping when it was first seen", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-10-20");
    const first = store.docs.get("143335")!;
    const run = await calendarRun(store, "2026-10-21", (h) => h.replaceAll("HÔTEL DE VILLE FERMÉ", "HÔTEL DE VILLE FERMÉ (FÊTES)"));
    expect(run.events.ok).toBe(true);
    const edited = store.docs.get("143335")!;
    expect(edited.title_fr).toBe("HÔTEL DE VILLE FERMÉ (FÊTES)");
    expect(edited.first_seen_at).toEqual(first.first_seen_at);
    expect(edited.updated_at).toEqual(at("2026-10-21"));
  });

  it("drops events once they've ended, keeping one still running", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-12-20");
    expect(store.docs.has("143335")).toBe(true); // 21–25 Dec
    await calendarRun(store, "2026-12-25");
    expect(store.docs.has("143335")).toBe(true); // last day: still on
    await calendarRun(store, "2026-12-26");
    expect(store.docs.has("143335")).toBe(false);
    expect(store.docs.has("143336")).toBe(true); // 28–31 Dec
  });

  it("three months of pages with pickups but no events is a failure, data untouched (spec D9)", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-10-20");
    const before = JSON.stringify([...store.docs.values()]);
    const run = await calendarRun(store, "2026-10-20", removeAllEvents);
    expect(run.pickups.ok).toBe(true); // bins are unaffected
    expect(run.events).toMatchObject({ ok: false, error: "parsed no events in the months fetched" });
    expect(JSON.stringify([...store.docs.values()])).toBe(before);
    expect(store.health!.last_error).toBe("parsed no events in the months fetched");
    expect(store.health!.last_success_at).toEqual(at("2026-10-20")); // the earlier good run
  });

  it("a download failure is recorded for events too, data untouched", async () => {
    const store = new FakeEventsStore();
    await calendarRun(store, "2026-10-20");
    const count = store.docs.size;
    const result = await runCollectionPoll({
      store: new FakePickupStore(),
      fetcher: { async get() { throw new Error("HTTP 503"); } },
      messenger: { async send() {} }, mrc: [MRC_2026], now: () => at("2026-10-21"),
    });
    expect(result.download).toBeUndefined();
    const run = await runEventsPoll({ store, now: () => at("2026-10-21") }, { error: result.error! });
    expect(run.ok).toBe(false);
    expect(store.health!.last_error).toContain("HTTP 503");
    expect(store.docs.size).toBe(count);
  });

  it("events still get the pages when a pickup check fails after downloading", async () => {
    // A month with far fewer pickups than last time fails the pickup step (its
    // own safety check), but the pages downloaded fine.
    const pickups = new FakePickupStore();
    const events = new FakeEventsStore();
    await calendarRun(events, "2026-10-20", undefined, pickups);
    const noBins = (h: string) => h.replace(anchors, (a) => (/pm-[a-z]+-bin/.test(a) ? "" : a));
    const run = await calendarRun(events, "2026-10-20", noBins, pickups);
    expect(run.pickups.ok).toBe(false);
    expect(run.pickups.download).toBeDefined();
    expect(run.events.ok).toBe(true);
  });
});
