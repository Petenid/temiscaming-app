// Runs whole calendar polls against the saved pages, with an in-memory
// database and a fake push service (spec §8, steps 3 and 3b). Changes by the
// Town are simulated by editing the real HTML: moving, removing or adding one
// event.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { PushMessage } from "../src/alerts/sync";
import { MrcCalendar } from "../src/collection/merge";
import {
  CalendarHealth, CollectionDeps, CollectionStore, StoredPickup, runCollectionPoll,
} from "../src/collection/sync";

const DIR = join(__dirname, "fixtures/calendar/2026-10-19");
const MRC_2026: MrcCalendar = JSON.parse(readFileSync(join(__dirname, "../data/mrc-2026.json"), "utf-8"));

/** Page text per language and month, from the fixtures; unknown months are empty. */
function page(lang: "fr" | "en", year: number, month: number): string {
  const name = `${lang}-${year}-${String(month).padStart(2, "0")}.html`;
  try {
    return readFileSync(join(DIR, name), "utf-8");
  } catch {
    return readFileSync(join(DIR, `${lang}-2027-01.html`), "utf-8"); // nothing posted
  }
}

// --- Simulated edits to a month page (both languages get the same edit) ---

const anchorRe = (eventId: string) =>
  new RegExp(`<a class="calendar-widget__item" href="[^"]*/${eventId}/[^"]*">[\\s\\S]*?</a>`);

/** The agenda <li> start for a day, in either language. */
const dayLiRe = (day: number) =>
  new RegExp(`<li>\\s*<h6><strong>(?:(?!</h6>)[\\s\\S])*?<span class="day">${day}(?:<sup>er</sup>)?</span>`);

/** Removes one event from the agenda list. */
const removeEvent = (html: string, eventId: string) => html.replace(anchorRe(eventId), "");

/** Puts an event (moved or new) under another day. */
function putUnderDay(html: string, anchor: string, day: number, beforeDay: number): string {
  const li = `<li><h6><strong>Day, <span class="day">${day}</span></strong></h6>${anchor}</li>`;
  return html.replace(dayLiRe(beforeDay), (m) => li + m);
}

function moveEvent(html: string, eventId: string, toDay: number, beforeDay: number): string {
  const anchor = html.match(anchorRe(eventId))![0];
  return putUnderDay(removeEvent(html, eventId), anchor, toDay, beforeDay);
}

/** Adds a copy of an existing event under another day, with a new event number. */
function copyEvent(html: string, eventId: string, newId: string, day: number, beforeDay: number): string {
  const anchor = html.match(anchorRe(eventId))![0].replace(`/${eventId}/`, `/${newId}/`);
  return putUnderDay(html, anchor, day, beforeDay);
}

// --- Fakes ---

class FakeStore implements CollectionStore {
  docs = new Map<string, StoredPickup>();
  health: CalendarHealth | null = null;
  async loadPickups(fromDate: string) {
    return [...this.docs.values()].filter((d) => d.date >= fromDate).map((d) => ({ ...d }));
  }
  async savePickups(docs: StoredPickup[]) {
    for (const doc of docs) {
      const { pushed_at, ...rest } = doc;
      const before = this.docs.get(doc.id);
      this.docs.set(doc.id, {
        ...before, ...rest,
        pushed_at: pushed_at === null ? null : before?.pushed_at ?? null,
      } as StoredPickup);
    }
  }
  async deletePickups(ids: string[]) { ids.forEach((id) => this.docs.delete(id)); }
  async claimPush(id: string, at: Date) {
    const d = this.docs.get(id);
    if (!d || d.pushed_at) return false;
    d.pushed_at = at;
    return true;
  }
  async releasePush(id: string) { const d = this.docs.get(id); if (d) d.pushed_at = null; }
  async loadHealth() { return this.health; }
  async saveHealth(h: CalendarHealth) { this.health = h; }
}

type Edit = (html: string, lang: "fr" | "en", year: number, month: number) => string;

function setup(nowIso: string) {
  const store = new FakeStore();
  const sent: PushMessage[] = [];
  let edit: Edit = (html) => html;
  let now = new Date(nowIso);
  let failing = false;
  const deps: CollectionDeps = {
    store,
    mrc: [MRC_2026],
    now: () => now,
    messenger: { send: async (m) => { if (failing) throw new Error("FCM down"); sent.push(m); } },
    fetcher: {
      async get(url) {
        const u = new URL(url);
        const lang = u.pathname.startsWith("/fr") ? "fr" : "en";
        const year = +u.searchParams.get("year")!;
        const month = +u.searchParams.get("month")!;
        return new TextEncoder().encode(edit(page(lang, year, month), lang, year, month));
      },
    },
  };
  return {
    store, sent,
    run: () => runCollectionPoll(deps),
    setEdit: (e: Edit) => { edit = e; },
    setNow: (iso: string) => { now = new Date(iso); },
    failSends: (on: boolean) => { failing = on; },
  };
}

/** Applies an edit to one month only. */
const inMonth = (y: number, m: number, f: (html: string) => string): Edit =>
  (html, _lang, year, month) => (year === y && month === m ? f(html) : html);

// 19 Oct 2026, noon in Témiscaming.
const OCT_19 = "2026-10-19T16:00:00Z";

describe("first run and quiet runs", () => {
  it("store October to December, push nothing on the first run, then do nothing", async () => {
    const t = setup(OCT_19);
    const first = await t.run();
    expect(first).toMatchObject({ ok: true, townCount: 26, pushed: [], warnings: [] });
    expect(t.sent).toEqual([]);
    expect(t.store.docs.get("2026-10-21_lumsden_garbage")).toMatchObject({
      origin: "town", event_id: "141948", status: "scheduled", change: null, irregular: false,
    });
    expect(t.store.health).toMatchObject({
      last_error: "", posted_through: "2026-12-23", known_through: "2026-12-23", mrc_through: "2026-12-31",
      month_counts: { "2026-10": 8, "2026-11": 8, "2026-12": 10 },
    });

    const second = await t.run();
    expect(second).toMatchObject({ ok: true, written: 0, deleted: 0, pushed: [] });
  });
});

describe("change notices", () => {
  async function afterFirstRun() {
    const t = setup(OCT_19);
    await t.run();
    return t;
  }

  it("a moved pickup → one notice per language, only to that sector, then never again", async () => {
    const t = await afterFirstRun();
    // Lumsden garbage moves from Wednesday 21 to Thursday 22 October.
    t.setEdit(inMonth(2026, 10, (h) => moveEvent(h, "141948", 22, 27)));
    const r = await t.run();
    expect(r.pushed).toEqual(["moved lumsden 2026-10-22"]);
    expect(t.sent.map((m) => m.topic)).toEqual(["collection-lumsden-fr", "collection-lumsden-en"]);
    expect(t.sent[0]).toMatchObject({
      title: "Collecte déplacée",
      body: "Bac noir : jeudi 22 octobre (au lieu du mercredi 21 octobre).",
      channel: "collection",
      data: { type: "collection", pickup_id: "2026-10-22_lumsden_garbage", sector: "lumsden" },
    });
    expect(t.sent[1].body).toBe("Black bin: Thursday, October 22 (instead of Wednesday, October 21).");
    expect(t.store.docs.has("2026-10-21_lumsden_garbage")).toBe(false);
    expect(t.store.docs.get("2026-10-22_lumsden_garbage")).toMatchObject({
      change: "moved", previous_date: "2026-10-21", irregular: true,
    });

    expect((await t.run()).pushed).toEqual([]);
    expect(t.sent).toHaveLength(2);
  });

  it("a cancelled pickup → a notice, and the MRC doesn't bring it back", async () => {
    const t = await afterFirstRun();
    t.setEdit(inMonth(2026, 10, (h) => removeEvent(h, "141949"))); // town recycling, Tue 27 Oct
    const r = await t.run();
    expect(r.pushed).toEqual(["cancelled town 2026-10-27"]);
    expect(t.sent[0].body).toBe("Bac bleu du mardi 27 octobre. Touchez pour les détails.");
    expect(t.sent[1]).toMatchObject({ title: "Pickup cancelled", body: "Blue bin on Tuesday, October 27. Tap for details." });
    expect(t.store.docs.get("2026-10-27_town_recycling")).toMatchObject({ status: "cancelled", change: "cancelled", origin: "town" });

    expect((await t.run()).pushed).toEqual([]);
    expect(t.store.docs.get("2026-10-27_town_recycling")?.status).toBe("cancelled");
  });

  it("an added pickup in a week the Town had posted → a notice", async () => {
    const t = await afterFirstRun();
    // An extra compost pickup for the town on Tuesday 27 October.
    t.setEdit(inMonth(2026, 10, (h) => copyEvent(h, "141942", "999001", 27, 27)));
    const r = await t.run();
    expect(r.pushed).toEqual(["added town 2026-10-27"]);
    expect(t.sent.map((m) => m.body)).toEqual(["Bac vert : mardi 27 octobre.", "Green bin: Tuesday, October 27."]);
  });

  it("two bins moved together → one notice naming both", async () => {
    const t = setup("2026-12-15T16:00:00Z");
    await t.run();
    // Town's 22 December recycling and compost both move to Monday 21.
    t.setEdit(inMonth(2026, 12, (h) => {
      let out = h;
      for (const id of ["141967", "141968", "141969"]) {
        if (anchorRe(id).test(out)) out = moveEvent(out, id, 21, 22);
      }
      return out;
    }));
    const r = await t.run();
    expect(r.pushed).toEqual(["moved town 2026-12-21"]);
    expect(t.sent[0].body).toBe("Bac vert et bac bleu : lundi 21 décembre (au lieu du mardi 22 décembre).");
    expect(t.sent[1].body).toBe("Green and blue bins: Monday, December 21 (instead of Tuesday, December 22).");
  });

  it("a change more than 14 days ahead → stored, but no notice", async () => {
    const t = await afterFirstRun();
    t.setEdit(inMonth(2026, 12, (h) => removeEvent(h, "141963"))); // town recycling, Tue 8 Dec
    const r = await t.run();
    expect(r.pushed).toEqual([]);
    expect(t.store.docs.get("2026-12-08_town_recycling")).toMatchObject({
      status: "cancelled", push_skipped: "too-far-ahead",
    });
  });

  it("a push that fails is retried on the next run", async () => {
    const t = await afterFirstRun();
    t.setEdit(inMonth(2026, 10, (h) => removeEvent(h, "141949")));
    t.failSends(true);
    expect((await t.run()).pushed).toEqual([]);
    expect(t.store.docs.get("2026-10-27_town_recycling")).toMatchObject({ change: "cancelled", pushed_at: null, push_skipped: null });
    t.failSends(false);
    expect((await t.run()).pushed).toEqual(["cancelled town 2026-10-27"]);
    expect((await t.run()).pushed).toEqual([]);
    expect(t.sent).toHaveLength(2);
  });
});

describe("source failures (silence must never look like safety)", () => {
  it("pages with no pickups at all → failure recorded, data untouched", async () => {
    const t = setup(OCT_19);
    await t.run();
    const before = new Map(t.store.docs);
    const lastSuccess = t.store.health!.last_success_at;
    t.setEdit((_h, lang) => page(lang, 2027, 1));
    const r = await t.run();
    expect(r).toMatchObject({ ok: false, error: "parsed no pickups in the months fetched" });
    expect(t.store.docs).toEqual(before);
    expect(t.store.health).toMatchObject({ last_success_at: lastSuccess });
    expect(t.store.health!.last_error).toMatch(/no pickups/);
    expect(t.sent).toEqual([]);
  });

  it("a month that suddenly shrinks → failure, not a wave of cancellations", async () => {
    const t = setup(OCT_19);
    await t.run();
    t.setEdit(inMonth(2026, 11, (h) =>
      ["141951", "141952", "141953", "141954", "141955", "141956"].reduce(removeEvent, h)));
    const r = await t.run();
    expect(r.ok).toBe(false);
    expect(r.error).toMatch(/parsed 2 pickups for 2026-11, expected about 8/);
    expect([...t.store.docs.values()].filter((d) => d.status === "cancelled")).toEqual([]);
  });

  it("a download error → failure recorded", async () => {
    const t = setup(OCT_19);
    t.setEdit(() => { throw new Error("HTTP 503"); });
    const r = await t.run();
    expect(r).toMatchObject({ ok: false, error: "download: HTTP 503" });
    expect(t.store.health).toMatchObject({ last_success_at: null, last_error: "download: HTTP 503" });
  });
});

describe("filling gaps from the MRC calendar (D4, D11)", () => {
  it("January 2026: the weeks the Town never posted come from the MRC; 27 January keeps the Town's pickup", async () => {
    const t = setup("2026-01-02T16:00:00Z");
    const r = await t.run();
    expect(r.ok).toBe(true);
    const doc = (id: string) => t.store.docs.get(id);
    for (const id of [
      "2026-01-06_town_compost", "2026-01-06_town_recycling", "2026-01-13_town_garbage", "2026-01-20_town_recycling",
      "2026-01-07_lumsden_compost", "2026-01-07_lumsden_recycling", "2026-01-14_lumsden_garbage", "2026-01-21_lumsden_recycling",
    ]) {
      expect(doc(id), id).toMatchObject({ origin: "mrc", event_id: "", status: "scheduled" });
    }
    expect(doc("2026-01-27_lumsden_garbage")).toMatchObject({ origin: "town", irregular: true });
    expect(doc("2026-01-28_lumsden_compost")).toMatchObject({ origin: "town" });
    expect(r.warnings).toContain(
      "Town and MRC differ for lumsden 2026-01-26: Town 2026-01-27 garbage, 2026-01-28 compost; MRC 2026-01-28 compost");
    expect(doc("2026-01-05_town_christmas-trees")).toMatchObject({ origin: "town", special: "christmas-trees" });
  });

  it("when the Town later posts a week the MRC had filled, the Town's pickup replaces it without a notice", async () => {
    const t = setup("2026-01-02T16:00:00Z");
    await t.run();
    // The Town posts its town-sector garbage pickup for 13 January after all.
    t.setEdit(inMonth(2026, 1, (h) => copyEvent(h, "141852", "999002", 13, 27)
      .replace(/(\/999002\/[^"]*">[\s\S]*?)LETANG ET LUMSDEN/, "$1TÉMISCAMING, LAC TEE ET CHEMINS DES CHALETS")
      .replace(/(\/999002\/[^"]*">[\s\S]*?)LETANG AND LUMSDEN SECTORS/, "$1TEMISCAMING, LAC TEE, AND COTTAGES ROADS")
      .replace(/(\/999002\/[^"]*">\s*<i class="calendar-widget__icon pm )pm-trash-bin-b/, "$1pm-trash-bin-a")));
    const r = await t.run();
    expect(r.pushed).toEqual([]);
    expect(t.store.docs.get("2026-01-13_town_garbage")).toMatchObject({ origin: "town", event_id: "999002" });
    expect(t.store.docs.get("2026-01-14_lumsden_garbage")).toMatchObject({ origin: "mrc" });
  });

  it("when neither source has a week yet, known_through stops at the last pickup (the app says 'not posted yet')", async () => {
    const t = setup("2026-12-15T16:00:00Z");
    const r = await t.run();
    expect(r.ok).toBe(true);
    expect(t.store.health).toMatchObject({ posted_through: "2026-12-23", known_through: "2026-12-23", mrc_through: "2026-12-31" });
    expect([...t.store.docs.values()].filter((d) => d.date >= "2026-12-24")).toEqual([]);
    expect(r.warnings).toEqual([]);
  });
});
