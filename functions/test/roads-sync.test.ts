// Whole roads runs with an in-memory database, a fake push service and a fake
// clock (roads spec §8 step 1): what's saved, what's pushed (exactly one per
// language per change), Ontario's rate limit, and the key never leaking.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { Fetcher, Messenger, PushMessage } from "../src/alerts/sync";
import { QUEBEC_URL, QuebecLayer } from "../src/roads/quebec";
import {
  PushState, RoadsHealth, RoadsHealthId, RoadsStore, runRoadsPoll, runTownWorkInfoPoll, StoredCameras,
  StoredConditions, StoredRoadItem,
} from "../src/roads/sync";
import { TOWN_LIST_URL } from "../src/roads/town";

const FIX = join(__dirname, "fixtures/roads");
const KEY = "TEST-KEY-123";

/** Which file each request gets. Ontario keys: "events-en", "conditions-fr"… */
type Files = Partial<Record<QuebecLayer | `${"events" | "construction" | "conditions" | "cameras"}-${"en" | "fr"}` | string, string | Error>>;

const REAL: Files = {
  warnings: "2026-10-22/qc-evenements-bbox.json",
  roadworks: "2026-10-22/qc-chantiers_mtmdet-bbox.json",
  conditions: "2026-10-22/qc-conditions_routieres-bbox.json",
  "events-en": "2026-10-23/on-event-en.json",
  "events-fr": "2026-10-23/on-event-fr.json",
  "construction-en": "2026-10-23/on-constructionprojects-en.json",
  "construction-fr": "2026-10-23/on-constructionprojects-fr.json",
  "conditions-en": "2026-10-23/on-roadconditions-en.json",
  "conditions-fr": "2026-10-23/on-roadconditions-fr.json",
  "cameras-en": "2026-10-23/on-cameras-en.json",
};

const ONTARIO_CALL: Record<string, string> = {
  "v2/get/event": "events", "v2/get/constructionprojects": "construction",
  "v3/get/roadconditions": "conditions", "v2/get/cameras": "cameras",
};

class Clock {
  constructor(public t: number) {}
  now = () => new Date(this.t);
  sleep = async (ms: number) => { this.t += ms; };
  set(iso: string) { this.t = Date.parse(iso); }
}

function fetcher(clock: Clock, files: () => Files, calls: { at: number; url: string }[]): Fetcher {
  return {
    async get(url) {
      calls.push({ at: clock.t, url });
      let slot: string | undefined;
      const qc = (Object.keys(QUEBEC_URL) as QuebecLayer[]).find((l) => QUEBEC_URL[l] === url);
      if (qc) slot = qc;
      const on = url.match(/^https:\/\/511on\.ca\/api\/(v\d\/get\/\w+)\?format=json&lang=(en|fr)&key=/);
      if (on) slot = `${ONTARIO_CALL[on[1]]}-${on[2]}`;
      if (url === TOWN_LIST_URL.fr) slot = "town-fr";
      if (url === TOWN_LIST_URL.en) slot = "town-en";
      if (url.includes("/info-travaux/1019/")) slot = "town-detail-fr";
      if (url.includes("/work-info/1019/")) slot = "town-detail-en";
      if (!slot) throw new Error(`unexpected URL ${url}`);
      const f = { ...REAL, ...files() }[slot];
      if (f instanceof Error) throw f;
      if (!f) throw new Error(`no fixture for ${slot}`);
      const inline = /^[{[<]/.test(f); // inline content rather than a fixture path
      return new TextEncoder().encode(inline ? f : readFileSync(join(FIX, f), "utf-8"));
    },
  };
}

class FakeStore implements RoadsStore {
  items = new Map<string, StoredRoadItem>();
  conditions = new Map<string, StoredConditions>();
  cameras: StoredCameras | null = null;
  pushState: PushState | null = null;
  health = new Map<RoadsHealthId, RoadsHealth>();
  async loadItems() { return [...this.items.values()].map((i) => structuredClone(i)); }
  async saveItems(docs: StoredRoadItem[]) { docs.forEach((d) => this.items.set(d.id, structuredClone(d))); }
  async deleteItems(ids: string[]) { ids.forEach((id) => this.items.delete(id)); }
  async saveConditions(id: string, doc: StoredConditions) { this.conditions.set(id, structuredClone(doc)); }
  async loadCameras() { return structuredClone(this.cameras); }
  async saveCameras(doc: StoredCameras) { this.cameras = structuredClone(doc); }
  async loadPushState() { return structuredClone(this.pushState); }
  async savePushState(s: PushState) { this.pushState = structuredClone(s); }
  async loadHealth(id: RoadsHealthId) { return this.health.get(id) ?? null; }
  async saveHealth(id: RoadsHealthId, h: RoadsHealth) { this.health.set(id, structuredClone(h)); }
}

class FakeMessenger implements Messenger {
  sent: PushMessage[] = [];
  async send(m: PushMessage) { this.sent.push(m); }
}

function setup(start = "2026-11-03T15:00:00Z", key: string | null = KEY) {
  const clock = new Clock(Date.parse(start));
  const store = new FakeStore();
  const messenger = new FakeMessenger();
  const calls: { at: number; url: string }[] = [];
  const log: string[] = [];
  let files: Files = {};
  const deps = () => ({
    store, messenger, now: clock.now, sleep: clock.sleep, ontarioKey: key ?? undefined,
    fetcher: fetcher(clock, () => files, calls), log: (m: string) => log.push(m),
  });
  const run = (f: Files = {}) => { files = f; return runRoadsPoll(deps()); };
  const runTown = (f: Files = {}) => { files = f; return runTownWorkInfoPoll(deps()); };
  return { clock, store, messenger, calls, log, run, runTown };
}

const CLOSURE_101: Files = { warnings: "hand-made/qc-warnings-closure-101.json" };
const CLOSURE_63: Files = {
  "events-en": "hand-made/on-event-63-closure-en.json",
  "events-fr": "hand-made/on-event-63-closure-fr.json",
};
const EMPTY_FC = '{"type":"FeatureCollection","numberMatched":0,"features":[]}';

describe("runRoadsPoll — what's saved", () => {
  it("first run on the real files: every source ok, conditions and cameras saved, no push", async () => {
    const { store, messenger, log, run } = setup("2026-10-23T16:00:00Z");
    const r = await run();
    expect(r.ok).toBe(true);
    expect(Object.keys(r.sources).sort()).toEqual([
      "mtmd-conditions", "mtmd-roadworks", "mtmd-warnings", "on511-conditions", "on511-construction", "on511-events",
    ]);
    expect(store.items.size).toBe(0);
    expect(store.conditions.get("route-101")!.segments).toHaveLength(2);
    expect(store.conditions.get("route-101")!.in_season).toBe(true);
    expect(store.conditions.get("highway-63")!.segments[0].surface_en).toBe("Bare and dry road");
    expect(store.cameras!.cameras).toHaveLength(2);
    expect(store.health.get("on511-events")).toMatchObject({ last_item_count: 0, last_error: "" });
    expect(messenger.sent).toEqual([]);
    expect(store.pushState).not.toBeNull();
    expect(log.at(-1)).toMatch(/^roads: mtmd-warnings ok \(0\), mtmd-roadworks ok \(0\), mtmd-conditions ok \(2\), on511-events ok \(0\)/);
  });

  it("a closure, an incident and a planned roadwork closure are saved with status and Today flags", async () => {
    const { store, run } = setup();
    await run({ ...CLOSURE_101, roadworks: "hand-made/qc-roadworks-planned-closure.json" });
    const get = (id: string) => store.items.get(id)!;
    expect([get("qc-warning-900001").status, get("qc-warning-900001").on_today]).toEqual(["in_effect", true]);
    expect([get("qc-warning-900002").kind, get("qc-warning-900002").on_today]).toEqual(["incident", true]);
    expect([get("qc-roadwork-900010").status, get("qc-roadwork-900010").on_today]).toEqual(["planned", true]);
    expect(store.items.has("qc-warning-900003")).toBe(false); // Rouyn-Noranda
  });

  it("items the source no longer lists are deleted; a failed source's items are kept", async () => {
    const { store, run } = setup();
    await run({ ...CLOSURE_101, ...CLOSURE_63 });
    expect(store.items.has("qc-warning-900001")).toBe(true);
    expect(store.items.has("on-event-900100")).toBe(true);
    // Ontario events fail; Quebec says nothing anymore.
    await run({ warnings: EMPTY_FC, "events-en": new Error("HTTP 503") });
    expect(store.items.has("qc-warning-900001")).toBe(false);
    expect(store.items.has("on-event-900100")).toBe(true);
  });

  it("empty Quebec conditions in season: a failure, the previous conditions stay", async () => {
    const { store, run } = setup();
    await run();
    const before = store.conditions.get("route-101");
    const r = await run({ conditions: "hand-made/qc-conditions-empty.json" });
    expect(r.sources["mtmd-conditions"]).toMatchObject({ ok: false });
    expect(store.health.get("mtmd-conditions")!.last_error).toMatch(/no Route 101 segment/);
    expect(store.conditions.get("route-101")).toEqual(before);
    expect(r.sources["mtmd-warnings"]!.ok).toBe(true); // the others carry on
  });

  it("bad JSON or an error page is a failure; Highway 63 missing from Ontario's conditions too", async () => {
    const { store, run } = setup();
    const r = await run({ roadworks: "<html>Service indisponible</html>", "conditions-en": "hand-made/on-conditions-no63-en.json" });
    expect(r.sources["mtmd-roadworks"]).toMatchObject({ ok: false, error: "roadworks: not JSON" });
    expect(r.sources["on511-conditions"]!.error).toMatch(/no Highway 63 entry/);
    expect(store.health.get("mtmd-roadworks")!.last_success_at).toBeNull();
  });
});

describe("runRoadsPoll — Ontario key and rate limit (spec D4, D15)", () => {
  it("never more than 9 Ontario calls in any 60 seconds, cameras once a day", async () => {
    const { clock, calls, run } = setup("2026-11-03T15:00:00Z");
    for (let i = 0; i < 4; i++) {
      await run();
      clock.t += 15 * 60_000;
    }
    const ontario = calls.filter((c) => c.url.startsWith("https://511on.ca/")).map((c) => c.at);
    expect(ontario).toHaveLength(7 + 6 * 3); // cameras only on the first run
    for (const t of ontario) expect(ontario.filter((u) => u >= t && u < t + 60_000).length).toBeLessThanOrEqual(9);
    // And a single run's calls are at least 7 s apart.
    const first = ontario.slice(0, 7);
    first.slice(1).forEach((t, i) => expect(t - first[i]).toBeGreaterThanOrEqual(7_000));
  });

  it("without a key: Ontario is a failure that says so, no Ontario request is made, Quebec carries on", async () => {
    const { calls, store, run } = setup("2026-11-03T15:00:00Z", null);
    const r = await run();
    expect(calls.some((c) => c.url.includes("511on.ca"))).toBe(false);
    expect(r.sources["on511-events"]!.error).toMatch(/no Ontario 511 key/);
    expect(store.health.get("on511-conditions")!.last_error).toMatch(/no Ontario 511 key/);
    expect(r.sources["mtmd-conditions"]!.ok).toBe(true);
  });

  it("the key never reaches health records or logs, even when the error repeats the URL", async () => {
    const { store, log, run } = setup();
    const r = await run({ "events-en": new Error(`HTTP 401 https://511on.ca/api/v2/get/event?format=json&lang=en&key=${KEY}`) });
    const everything = JSON.stringify([...store.health.values()]) + log.join("\n") + JSON.stringify(r);
    expect(everything).not.toContain(KEY);
    expect(store.health.get("on511-events")!.last_error).toContain("key=***");
  });
});

describe("runRoadsPoll — closure pushes (spec D7, D8)", () => {
  it("a Route 101 closure: one push per language; nothing more while it lasts", async () => {
    const { clock, messenger, run } = setup();
    await run(); // first run: baseline
    clock.t += 15 * 60_000;
    await run(CLOSURE_101);
    expect(messenger.sent.map((m) => [m.topic, m.title, m.channel, m.urgent])).toEqual([
      ["roads-fr", "Route 101 fermée à Saint-Édouard-de-Fabre", "roads", true],
      ["roads-en", "Route 101 closed at Saint-Édouard-de-Fabre", "roads", true],
    ]);
    expect(messenger.sent[1].body).toBe("The road is closed. Tap for details.");
    expect(messenger.sent[0].data).toEqual({ screen: "roads", road: "101" });
    clock.t += 15 * 60_000;
    await run(CLOSURE_101);
    expect(messenger.sent).toHaveLength(2);
  });

  it("reopened: once it's been gone 25 minutes, one quieter push per language", async () => {
    const { clock, messenger, run } = setup();
    await run();
    clock.t += 15 * 60_000;
    await run(CLOSURE_101);
    messenger.sent = [];
    clock.t += 15 * 60_000;
    await run(); // gone for 15 min: wait
    expect(messenger.sent).toEqual([]);
    clock.t += 15 * 60_000;
    await run(); // gone for 30 min
    expect(messenger.sent.map((m) => [m.title, m.urgent])).toEqual([
      ["Route 101 rouverte à Saint-Édouard-de-Fabre", false],
      ["Route 101 reopened at Saint-Édouard-de-Fabre", false],
    ]);
    clock.t += 15 * 60_000;
    await run();
    expect(messenger.sent).toHaveLength(2);
  });

  it("deleted and re-posted between two runs: no push at all", async () => {
    const { clock, messenger, run } = setup();
    await run();
    clock.t += 15 * 60_000;
    await run(CLOSURE_101);
    messenger.sent = [];
    clock.t += 15 * 60_000;
    await run(); // briefly gone
    clock.t += 15 * 60_000;
    await run(CLOSURE_101); // back
    clock.t += 30 * 60_000;
    await run(CLOSURE_101);
    expect(messenger.sent).toEqual([]);
  });

  it("a Highway 63 closure; no 'reopened' while Ontario can't be read", async () => {
    const { clock, messenger, run } = setup();
    await run();
    clock.t += 15 * 60_000;
    await run(CLOSURE_63);
    expect(messenger.sent.map((m) => m.title)).toEqual(["Route 63 (Ontario) fermée", "Highway 63 (Ontario) closed"]);
    messenger.sent = [];
    for (let i = 0; i < 3; i++) {
      clock.t += 15 * 60_000;
      await run({ "events-en": new Error("HTTP 503") });
    }
    expect(messenger.sent).toEqual([]);
    clock.t += 15 * 60_000;
    await run(); // Ontario readable again, closure gone for 60 min
    expect(messenger.sent.map((m) => m.title)).toEqual(["Route 63 (Ontario) rouverte", "Highway 63 (Ontario) reopened"]);
  });

  it("a planned closure says from when, once; its start sends nothing", async () => {
    const { clock, messenger, run } = setup();
    const planned = { roadworks: "hand-made/qc-roadworks-planned-closure.json" };
    await run();
    clock.t += 15 * 60_000;
    await run(planned);
    expect(messenger.sent.map((m) => m.body)).toEqual([
      "Fermeture prévue à partir de mardi 10 novembre à 19 h. Touchez pour les détails.",
      "Closure planned starting Tuesday, November 10 at 7 p.m. Tap for details.",
    ]);
    clock.set("2026-11-10T23:30:00Z"); // started
    await run(planned);
    expect(messenger.sent).toHaveLength(2);
  });

  it("first run ever with a closure already there: recorded, not pushed", async () => {
    const { messenger, store, log, run } = setup();
    await run(CLOSURE_101);
    expect(messenger.sent).toEqual([]);
    expect(Object.values(store.pushState!.closures).map((c) => c.told)).toEqual(["closed"]);
    expect(log).toContain("roads: first run, recording closures without pushing");
  });

  it("incidents, roadworks and bad conditions never push", async () => {
    const { clock, messenger, run } = setup();
    await run();
    clock.t += 15 * 60_000;
    await run({
      warnings: '{"type":"FeatureCollection","numberMatched":0,"features":[]}',
      conditions: "hand-made/qc-conditions-icy.json",
      "conditions-en": "hand-made/on-conditions-snow-en.json",
      "conditions-fr": "hand-made/on-conditions-snow-fr.json",
    });
    expect(messenger.sent).toEqual([]);
  });
});

describe("runTownWorkInfoPoll", () => {
  const TOWN: Files = {
    "town-fr": "2026-10-22/town-list-fr.html",
    "town-en": "2026-10-22/town-list-en.html",
    "town-detail-fr": "2026-10-22/town-detail-fr-1019.html",
    "town-detail-en": "2026-10-22/town-detail-en-1019.html",
  };

  it("saves item 1019 in both languages, gently (2 s between requests)", async () => {
    const { store, calls, runTown } = setup("2026-10-22T16:00:00Z");
    const r = await runTown(TOWN);
    expect(r).toEqual({ ok: true, error: undefined, count: 1 });
    const item = store.items.get("town-1019")!;
    expect([item.kind, item.status, item.on_today, item.original_language]).toEqual(["town", "in_effect", false, "both"]);
    expect(calls).toHaveLength(4);
    calls.slice(1).forEach((c, i) => expect(c.at - calls[i].at).toBeGreaterThanOrEqual(2_000));
    expect(store.health.get("town-work-info")).toMatchObject({ last_item_count: 1, last_error: "" });
  });

  it("an item page that can't be read keeps the text we had", async () => {
    const { store, log, runTown } = setup("2026-10-22T16:00:00Z");
    await runTown(TOWN);
    await runTown({ ...TOWN, "town-detail-en": new Error("HTTP 500") });
    expect(store.items.get("town-1019")!.body_en).toMatch(/^Throughout the month of October/);
    expect(log.some((l) => l.includes("item 1019 (en): page not read"))).toBe(true);
  });

  it("a list that can't be read: failure, items kept", async () => {
    const { store, runTown } = setup("2026-10-22T16:00:00Z");
    await runTown(TOWN);
    const r = await runTown({ ...TOWN, "town-en": new Error("HTTP 502") });
    expect(r.ok).toBe(false);
    expect(store.items.has("town-1019")).toBe(true);
    expect(store.health.get("town-work-info")!.last_error).toBe("HTTP 502");
  });

  it("after its end date the item is removed", async () => {
    const { clock, store, runTown } = setup("2026-10-22T16:00:00Z");
    await runTown(TOWN);
    clock.set("2026-11-01T12:00:00Z");
    await runTown(TOWN); // still listed, but past 31 October
    expect(store.items.has("town-1019")).toBe(false);
  });
});
