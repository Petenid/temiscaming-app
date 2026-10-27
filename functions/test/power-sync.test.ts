// Whole power-outage runs with an in-memory database and a fake push service
// (spec power-outages D3–D5, §8 step 1). The files served are the real ones
// from 2026-10-27, with rows for Témiscaming added where a test needs them.
import { describe, expect, it } from "vitest";

import { Fetcher, Messenger, PushMessage } from "../src/alerts/sync";
import { POWER_URLS } from "../src/power/parse";
import {
  PowerDoc, PowerHealth, PowerPart, PowerPushState, PowerStore, runPowerPoll,
} from "../src/power/sync";
import { ongoingRow, plannedRow, realJson } from "./power-helpers";

class FakePowerStore implements PowerStore {
  doc: PowerDoc | null = null;
  state: PowerPushState | null = null;
  health = new Map<PowerPart, PowerHealth>();
  async loadPower() { return structuredClone(this.doc); }
  async savePower(d: PowerDoc) { this.doc = structuredClone(d); }
  async loadPushState() { return structuredClone(this.state); }
  async savePushState(s: PowerPushState) { this.state = structuredClone(s); }
  async loadHealth(p: PowerPart) { return structuredClone(this.health.get(p) ?? null); }
  async saveHealth(p: PowerPart, h: PowerHealth) { this.health.set(p, structuredClone(h)); }
}

class FakeMessenger implements Messenger {
  sent: PushMessage[] = [];
  failTopics = new Set<string>();
  async send(m: PushMessage) {
    if (this.failTopics.has(m.topic)) throw new Error("FCM unavailable");
    this.sent.push(m);
  }
}

/** "2026-10-27T18:00:00Z" → "20261027140000" (Montréal time), minus `ageMin`. */
function versionFor(iso: string, ageMin = 5): string {
  const d = new Date(new Date(iso).getTime() - ageMin * 60_000);
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(d).map((x) => [x.type, x.value]));
  return `${p.year}${p.month}${p.day}${p.hour}${p.minute}${p.second}`;
}

interface Serve {
  /** Rows added to the real list of current interruptions. */
  here?: unknown[][];
  /** Rows added to the real list of planned interruptions. */
  plannedHere?: unknown[][];
  ongoingAgeMin?: number;
  plannedAgeMin?: number;
  /** Replaces a whole answer (by part), e.g. an Error or a broken file. */
  ongoing?: Error | string;
  planned?: Error | string;
}

function fetcher(iso: string, s: Serve, calls: string[]): Fetcher {
  const vOn = versionFor(iso, s.ongoingAgeMin);
  const vPl = versionFor(iso, s.plannedAgeMin ?? 30);
  const enc = (x: unknown) => new TextEncoder().encode(typeof x === "string" ? x : JSON.stringify(x));
  return {
    async get(url) {
      calls.push(url);
      if (url === POWER_URLS.ongoingVersion) return enc(`"${vOn}"`);
      if (url === POWER_URLS.plannedVersion) return enc(`"${vPl}"`);
      if (url === POWER_URLS.ongoing(vOn)) {
        if (s.ongoing instanceof Error) throw s.ongoing;
        if (typeof s.ongoing === "string") return enc(s.ongoing);
        const real = realJson("bismarkers.json");
        return enc({ ...real, pannes: [...real.pannes, ...(s.here ?? [])] });
      }
      if (url === POWER_URLS.planned(vPl)) {
        if (s.planned instanceof Error) throw s.planned;
        if (typeof s.planned === "string") return enc(s.planned);
        return enc([...realJson("aipmarkers.json"), ...(s.plannedHere ?? [])]);
      }
      throw new Error(`unexpected URL ${url}`);
    },
  };
}

function setup() {
  const store = new FakePowerStore();
  const messenger = new FakeMessenger();
  const log: string[] = [];
  const calls: string[] = [];
  const run = (iso: string, s: Serve = {}) =>
    runPowerPoll({ store, messenger, fetcher: fetcher(iso, s, calls), now: () => new Date(iso), log: (m) => log.push(m) });
  return { store, messenger, log, calls, run };
}

const OUT_120 = [ongoingRow({ locality: "9130", customers: 120, start: "2026-10-27 14:05:00", status: "R" })];
const SMALL_3 = [ongoingRow({ locality: "9130", customers: 3, start: "2026-10-27 14:05:00" })];
const WORK_80 = [ongoingRow({ locality: "9130", customers: 80, type: "I", cause: "62" })];

describe("runPowerPoll", () => {
  it("first run on the real files: nothing here, both parts healthy, no push", async () => {
    const { store, messenger, log, run } = setup();
    const r = await run("2026-10-27T18:00:00Z");
    expect(r).toEqual({ ongoing: { ok: true, here: 0 }, planned: { ok: true, here: 0 }, pushed: undefined });
    expect(store.doc).toMatchObject({
      outages: [], planned: [], outages_checked_at: new Date("2026-10-27T18:00:00Z"),
      version_ongoing: "20261027135500",
    });
    expect(store.health.get("ongoing")).toMatchObject({ last_error: "", last_success_at: new Date("2026-10-27T18:00:00Z") });
    expect(store.health.get("ongoing")!.last_item_count).toBe(29);
    expect(store.health.get("planned")!.last_item_count).toBe(197);
    expect(store.state).toMatchObject({ pushed: "restored", baseline: true });
    expect(messenger.sent).toEqual([]);
    expect(log.at(-1)).toMatch(/^power: ongoing ok \(v20261027135500, 0 here, \d+ in Quebec\), planned ok/);
  });

  it("first run during an outage: records it without pushing (no surprise on deploy)", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    expect(store.doc!.outages).toHaveLength(1);
    expect(store.state).toMatchObject({ pushed: "out", baseline: true });
    expect(messenger.sent).toEqual([]);
  });

  it("out → still out → restored after 20 minutes: one push per step per language (spec D5)", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    const out = await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    expect(out.pushed).toBe("out");
    expect(messenger.sent.map((m) => [m.topic, m.title, m.body, m.channel, m.urgent])).toEqual([
      ["power-fr", "Panne de courant à Témiscaming", "120 clients touchés. Touchez pour les détails.", "power", true],
      ["power-en", "Power outage in Témiscaming", "120 customers affected. Tap for details.", "power", true],
    ]);
    expect(messenger.sent[0].data).toEqual({ screen: "power" });
    expect(store.doc!.outages[0]).toMatchObject({
      kind: "outage", customers: 120, status: "on_the_way", area: "temiscaming",
      started_at: new Date("2026-10-27T18:05:00Z"), estimated_end_at: null,
    });

    // A second outage during the first: nothing more.
    await run("2026-10-27T18:30:00Z", { here: [...OUT_120, ongoingRow({ locality: "9124", customers: 40 })] });
    expect(messenger.sent).toHaveLength(2);

    // Gone from the list, but not for 20 minutes yet.
    await run("2026-10-27T18:45:00Z");
    expect(store.doc!.outages).toEqual([]);
    expect(messenger.sent).toHaveLength(2);

    const restored = await run("2026-10-27T18:50:00Z");
    expect(restored.pushed).toBe("restored");
    expect(messenger.sent.slice(2).map((m) => [m.topic, m.title, m.urgent])).toEqual([
      ["power-fr", "Courant rétabli à Témiscaming", false],
      ["power-en", "Power restored in Témiscaming", false],
    ]);

    await run("2026-10-27T19:05:00Z");
    expect(messenger.sent).toHaveLength(4);
  });

  it("an outage that drops off the list for one run doesn't send 'restored' then 'out' again", async () => {
    const { messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    await run("2026-10-27T18:30:00Z");
    await run("2026-10-27T18:45:00Z", { here: OUT_120 });
    await run("2026-10-27T19:00:00Z", { here: OUT_120 });
    expect(messenger.sent.map((m) => m.topic)).toEqual(["power-fr", "power-en"]);
  });

  it("below 25 customers, or planned work in progress: shown, never pushed", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", { here: [...SMALL_3, ...WORK_80] });
    expect(store.doc!.outages.map((o) => [o.kind, o.customers])).toEqual([["planned_in_progress", 80], ["outage", 3]]);
    expect(messenger.sent).toEqual([]);
  });

  it("small outages add up: 15 + 12 customers here push", async () => {
    const { messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", {
      here: [ongoingRow({ locality: "9130", customers: 15 }), ongoingRow({ locality: "9124", customers: 12 })],
    });
    expect(messenger.sent.map((m) => m.body)).toEqual([
      "27 clients touchés. Touchez pour les détails.", "27 customers affected. Tap for details.",
    ]);
  });

  it("Lac Tee only: the push says Lac Tee", async () => {
    const { messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", { here: [ongoingRow({ locality: "9124", customers: 30 })] });
    expect(messenger.sent.map((m) => m.title)).toEqual(["Panne de courant au lac Tee", "Power outage at Lac Tee"]);
  });

  it("silence ≠ safety: a frozen version is a failure, the last outage stays (spec D3)", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    const r = await run("2026-10-27T18:30:00Z", { ongoingAgeMin: 50 });
    expect(r.ongoing).toMatchObject({ ok: false, error: expect.stringMatching(/hasn't changed since \d{14} \(50 min\)/) });
    expect(store.doc!.outages).toHaveLength(1); // last known, not "nothing here"
    expect(store.doc!.outages_checked_at).toEqual(new Date("2026-10-27T18:15:00Z"));
    expect(store.health.get("ongoing")).toMatchObject({
      last_attempt_at: new Date("2026-10-27T18:30:00Z"), last_success_at: new Date("2026-10-27T18:15:00Z"),
    });
    expect(messenger.sent).toHaveLength(2); // no "restored" from a failed check
  });

  it("silence ≠ safety: an empty list, bad JSON or an HTTP error are failures", async () => {
    for (const ongoing of ['{"messages": {}, "pannes": []}', "<html>oops</html>", new Error("HTTP 503")]) {
      const { store, run } = setup();
      await run("2026-10-27T18:00:00Z", { here: SMALL_3 });
      const r = await run("2026-10-27T18:15:00Z", { ongoing });
      expect(r.ongoing.ok).toBe(false);
      expect(store.doc!.outages).toHaveLength(1);
      expect(store.health.get("ongoing")!.last_error).not.toBe("");
    }
  });

  it("a failed check never sends 'restored', even past 20 minutes", async () => {
    const { messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    await run("2026-10-27T18:45:00Z", { ongoing: new Error("HTTP 503") });
    await run("2026-10-27T19:00:00Z", { ongoing: new Error("HTTP 503") });
    expect(messenger.sent).toHaveLength(2);
  });

  it("planned interruptions: read about once an hour; upcoming ones here are stored", async () => {
    const { store, calls, run } = setup();
    const plannedHere = [plannedRow({ notice: "777", start: "2026-10-29 08:30:00", end: "2026-10-29 12:00:00", municipality: "85005" })];
    await run("2026-10-27T18:00:00Z", { plannedHere });
    expect(store.doc!.planned).toMatchObject([{ notice: "777", starts_at: new Date("2026-10-29T12:30:00Z"), area: "temiscaming" }]);
    const before = calls.length;
    const r = await run("2026-10-27T18:15:00Z", { plannedHere });
    expect(r.planned).toEqual({ ok: true, skipped: true });
    expect(calls.slice(before).filter((u) => u.includes("aip"))).toEqual([]);
    expect(store.doc!.planned).toHaveLength(1);
    await run("2026-10-27T18:55:00Z", { plannedHere: [] });
    expect(store.doc!.planned).toEqual([]);
  });

  it("a planned interruption that has started drops off between hourly reads", async () => {
    const { store, run } = setup();
    const plannedHere = [plannedRow({ start: "2026-10-27 14:20:00", end: "2026-10-27 16:00:00", municipality: "85005" })];
    await run("2026-10-27T18:00:00Z", { plannedHere });
    expect(store.doc!.planned).toHaveLength(1);
    await run("2026-10-27T18:30:00Z", { plannedHere });
    expect(store.doc!.planned).toEqual([]);
  });

  it("planned failing doesn't stop current outages, and keeps the last planned list", async () => {
    const { store, run } = setup();
    const plannedHere = [plannedRow({ start: "2026-10-29 08:30:00", end: "2026-10-29 12:00:00", municipality: "85005" })];
    await run("2026-10-27T18:00:00Z", { plannedHere });
    const r = await run("2026-10-27T19:00:00Z", { planned: new Error("HTTP 500"), here: SMALL_3 });
    expect(r.ongoing.ok).toBe(true);
    expect(r.planned.ok).toBe(false);
    expect(store.doc!.planned).toHaveLength(1);
    expect(store.doc!.outages).toHaveLength(1);
    expect(store.health.get("planned")!.last_error).toMatch(/HTTP 500/);
  });

  it("planned is retried every run while it has never worked", async () => {
    const { calls, run } = setup();
    await run("2026-10-27T18:00:00Z", { planned: new Error("HTTP 500") });
    const before = calls.length;
    await run("2026-10-27T18:15:00Z");
    expect(calls.slice(before).some((u) => u.includes("aipmarkers"))).toBe(true);
  });

  it("a stale planned file (over 6 hours) is a failure", async () => {
    const { run } = setup();
    const r = await run("2026-10-27T18:00:00Z", { plannedAgeMin: 7 * 60 });
    expect(r.planned).toMatchObject({ ok: false, error: expect.stringMatching(/hasn't changed/) });
  });

  it("if both pushes fail, it's tried again next run; if one fails, it isn't", async () => {
    const { messenger, run } = setup();
    await run("2026-10-27T18:00:00Z");
    messenger.failTopics = new Set(["power-fr", "power-en"]);
    await run("2026-10-27T18:15:00Z", { here: OUT_120 });
    expect(messenger.sent).toEqual([]);
    messenger.failTopics = new Set(["power-fr"]);
    await run("2026-10-27T18:30:00Z", { here: OUT_120 });
    expect(messenger.sent.map((m) => m.topic)).toEqual(["power-en"]);
    await run("2026-10-27T18:45:00Z", { here: OUT_120 });
    expect(messenger.sent.map((m) => m.topic)).toEqual(["power-en"]);
  });
});
