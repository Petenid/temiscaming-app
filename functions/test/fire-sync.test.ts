// Whole fire-ban runs with an in-memory database and a fake push service
// (spec fire-bans D5, §8 step 1): the town's state is saved, and exactly one
// push per language goes out when it changes — never more.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { Fetcher, Messenger, PushMessage } from "../src/alerts/sync";
import { LAYER_URL, LayerId } from "../src/fire/parse";
import { FireHealth, FireStore, runFireBanPoll, StoredLayer } from "../src/fire/sync";

const FIX = join(__dirname, "fixtures/fire");
const file = (path: string) => readFileSync(join(FIX, path), "utf-8");
const NONE = { ifco: "2026-10-21/ifco.json", icaf: "2026-10-21/icaf.json" };

/** Serves a fixture per layer, or an Error. */
function fetcher(files: Partial<Record<LayerId, string | Error>> = {}): Fetcher {
  return {
    async get(url) {
      const layer = (Object.keys(LAYER_URL) as LayerId[]).find((l) => LAYER_URL[l] === url);
      if (!layer) throw new Error(`unexpected URL ${url}`);
      const f = files[layer] ?? NONE[layer];
      if (f instanceof Error) throw f;
      return new TextEncoder().encode(file(f));
    },
  };
}

class FakeFireStore implements FireStore {
  layers: Partial<Record<LayerId, StoredLayer>> = {};
  health = new Map<LayerId, FireHealth>();
  async loadFire() { return structuredClone(this.layers); }
  async saveLayer(layer: LayerId, fields: StoredLayer) { this.layers[layer] = structuredClone(fields); }
  async loadHealth(layer: LayerId) { return this.health.get(layer) ?? null; }
  async saveHealth(layer: LayerId, h: FireHealth) { this.health.set(layer, h); }
}

class FakeMessenger implements Messenger {
  sent: PushMessage[] = [];
  failTopics = new Set<string>();
  async send(m: PushMessage) {
    if (this.failTopics.has(m.topic)) throw new Error("FCM unavailable");
    this.sent.push(m);
  }
}

function setup() {
  const store = new FakeFireStore();
  const messenger = new FakeMessenger();
  const log: string[] = [];
  const run = (iso: string, files: Partial<Record<LayerId, string | Error>> = {}) =>
    runFireBanPoll({ store, messenger, fetcher: fetcher(files), now: () => new Date(iso), log: (m) => log.push(m) });
  return { store, messenger, log, run };
}

const BAN_HERE = { ifco: "hand-made/ifco-temiscamingue.json" }; // starts 2026-10-22 8h (12:00Z)

describe("runFireBanPoll", () => {
  it("first run: records 'none since 20 July' for both layers, healthy, no push", async () => {
    const { store, messenger, log, run } = setup();
    const r = await run("2026-10-21T17:00:00Z");
    expect(r.ifco).toEqual({ ok: true, state: "none", pushed: undefined });
    expect(r.icaf.ok).toBe(true);
    expect(store.layers.ifco).toMatchObject({
      state: "none", none_since: new Date("2026-07-20T16:00:00Z"),
      checked_at: new Date("2026-10-21T17:00:00Z"),
      pushed: { kind: "lifted", baseline: true },
    });
    expect(store.health.get("ifco")).toMatchObject({ last_item_count: 1, last_error: "" });
    expect(messenger.sent).toEqual([]);
    expect(log).toContain("fire ifco: ok — none since 2026-07-20T16:00:00.000Z");
  });

  it("first run during a ban: records it without pushing (no surprise on deploy)", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-22T15:00:00Z", BAN_HERE);
    expect(store.layers.ifco).toMatchObject({ state: "town", pushed: { kind: "started", baseline: true } });
    expect(messenger.sent).toEqual([]);
  });

  it("announced → started → amended → lifted: one push per step that matters, per language", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-21T17:00:00Z"); // baseline: none

    // Published the day before it starts.
    let r = await run("2026-10-21T19:30:00Z", BAN_HERE);
    expect(r.ifco.pushed).toBe("announced");
    expect(messenger.sent.map((m) => [m.topic, m.channel, m.urgent])).toEqual([
      ["fire-fr", "fire_urgent", true], ["fire-en", "fire_urgent", true],
    ]);
    expect(messenger.sent[0]).toMatchObject({
      title: "Interdiction de faire des feux à ciel ouvert",
      body: "En vigueur à Témiscaming à partir de jeudi 22 octobre à 8 h. Touchez pour les détails.",
      data: { screen: "fire", layer: "ifco" },
    });
    expect(messenger.sent[1]).toMatchObject({
      title: "Open-fire ban",
      body: "In effect for Témiscaming starting Thursday, October 22 at 8 a.m. Tap for details.",
    });

    // It starts: people already know, so nothing more.
    messenger.sent = [];
    r = await run("2026-10-22T12:30:00Z", BAN_HERE);
    expect(r.ifco).toMatchObject({ ok: true, state: "town", pushed: undefined });
    expect(messenger.sent).toEqual([]);

    // The ministry redraws the area; the town is still inside: nothing.
    await run("2026-10-23T12:30:00Z", { ifco: "hand-made/ifco-temiscamingue.json" });
    expect(messenger.sent).toEqual([]);

    // Lifted (the placeholder comes back).
    r = await run("2026-10-25T16:30:00Z");
    expect(r.ifco.pushed).toBe("lifted");
    expect(messenger.sent.map((m) => [m.topic, m.channel, m.urgent, m.title])).toEqual([
      ["fire-fr", "fire_updates", false, "Fin de l'interdiction de feux à ciel ouvert"],
      ["fire-en", "fire_updates", false, "Open-fire ban lifted"],
    ]);

    // And stays lifted: nothing more.
    messenger.sent = [];
    await run("2026-10-25T17:00:00Z");
    expect(messenger.sent).toEqual([]);
    expect(store.layers.ifco?.pushed.kind).toBe("lifted");
  });

  it("a ban that's already in effect when first seen pushes 'started'", async () => {
    const { messenger, run } = setup();
    await run("2026-10-21T17:00:00Z");
    await run("2026-10-22T12:30:00Z", BAN_HERE);
    expect(messenger.sent[1]).toMatchObject({
      title: "Open-fire ban",
      body: "Now in effect for Témiscaming. No campfires or brush burning. Tap for details.",
    });
  });

  it("a ban lifted then re-imposed pushes again: 'lifted' must never be the last word during a ban", async () => {
    const { messenger, run } = setup();
    await run("2026-10-21T17:00:00Z");
    await run("2026-10-22T12:30:00Z", BAN_HERE); // started
    await run("2026-10-22T14:00:00Z"); // lifted
    await run("2026-10-22T15:00:00Z", BAN_HERE); // back an hour later
    expect(messenger.sent.filter((m) => m.topic === "fire-en").map((m) => m.title)).toEqual([
      "Open-fire ban", "Open-fire ban lifted", "Open-fire ban",
    ]);
  });

  it("a ban elsewhere in the region (July 2026 style) shows as region, never pushes", async () => {
    const { store, messenger, run } = setup();
    await run("2026-07-01T12:00:00Z");
    const r = await run("2026-07-02T13:00:00Z", { ifco: "hand-made/ifco-rouyn-abitibi.json" });
    expect(r.ifco).toEqual({ ok: true, state: "region", pushed: undefined });
    expect(store.layers.ifco).toMatchObject({ state: "region", starts_at: null, none_since: null });
    expect(messenger.sent).toEqual([]);
  });

  it("forest access ban around town pushes with its own wording", async () => {
    const { messenger, run } = setup();
    await run("2026-10-21T15:00:00Z");
    const r = await run("2026-10-21T17:00:00Z", { icaf: "hand-made/icaf-east-of-town.json" });
    expect(r.icaf).toMatchObject({ state: "around", pushed: "started" });
    expect(messenger.sent.map((m) => m.body)).toEqual([
      "En vigueur autour de Témiscaming. N'allez pas en forêt. Touchez pour les détails.",
      "Now in effect around Témiscaming. Stay out of the forest. Tap for details.",
    ]);
    expect(messenger.sent[0].data).toEqual({ screen: "fire", layer: "icaf" });
  });

  it("a failed read keeps the last state and goes to health; the other layer still runs", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-21T17:00:00Z");
    await run("2026-10-22T12:30:00Z", BAN_HERE);
    const before = structuredClone(store.layers.ifco);
    messenger.sent = [];

    for (const bad of [new Error("HTTP 503"), "hand-made/ifco-empty.json"]) {
      const r = await run("2026-10-22T13:00:00Z", { ifco: bad });
      expect(r.ifco.ok).toBe(false);
      expect(r.icaf.ok).toBe(true);
    }
    expect(store.layers.ifco).toEqual(before); // still "town": no false all-clear
    expect(messenger.sent).toEqual([]); // and certainly no "lifted"
    expect(store.health.get("ifco")).toMatchObject({
      last_success_at: new Date("2026-10-22T12:30:00Z"),
      last_attempt_at: new Date("2026-10-22T13:00:00Z"),
      last_error: expect.stringMatching(/no features/),
    });
    expect(store.health.get("icaf")?.last_success_at).toEqual(new Date("2026-10-22T13:00:00Z"));
  });

  it("not JSON is a failure", async () => {
    const r = await runFireBanPoll({
      store: new FakeFireStore(), messenger: new FakeMessenger(), now: () => new Date(),
      fetcher: { async get() { return new TextEncoder().encode("<html>maintenance</html>"); } },
    });
    expect(r.ifco).toMatchObject({ ok: false, error: "ifco: not JSON" });
  });

  it("if every push fails, it's tried again next run — and only while still true", async () => {
    const { store, messenger, run } = setup();
    await run("2026-10-21T17:00:00Z");
    messenger.failTopics = new Set(["fire-fr", "fire-en"]);
    await run("2026-10-22T12:30:00Z", BAN_HERE);
    expect(store.layers.ifco).toMatchObject({ state: "town", pushed: { kind: "lifted" } });

    messenger.failTopics.clear();
    await run("2026-10-22T13:00:00Z", BAN_HERE);
    expect(messenger.sent.map((m) => m.topic)).toEqual(["fire-fr", "fire-en"]);
    expect(store.layers.ifco?.pushed.kind).toBe("started");
  });

  it("a failed push that's no longer true is never sent late", async () => {
    const { messenger, run } = setup();
    await run("2026-10-21T17:00:00Z");
    messenger.failTopics = new Set(["fire-fr", "fire-en"]);
    await run("2026-10-22T12:30:00Z", BAN_HERE); // push fails
    messenger.failTopics.clear();
    await run("2026-10-22T13:00:00Z"); // ban already gone
    expect(messenger.sent).toEqual([]);
  });

  it("one language failing doesn't make the other repeat every 30 minutes", async () => {
    const { messenger, log, run } = setup();
    await run("2026-10-21T17:00:00Z");
    messenger.failTopics = new Set(["fire-en"]);
    await run("2026-10-22T12:30:00Z", BAN_HERE);
    await run("2026-10-22T13:00:00Z", BAN_HERE);
    expect(messenger.sent.map((m) => m.topic)).toEqual(["fire-fr"]);
    expect(log.some((l) => /fire-en FAILED/.test(l))).toBe(true);
  });

  it("can't load the stored state: skips the run without pushing", async () => {
    const store = new FakeFireStore();
    store.loadFire = async () => { throw new Error("Firestore unavailable"); };
    const messenger = new FakeMessenger();
    const r = await runFireBanPoll({ store, messenger, fetcher: fetcher(BAN_HERE), now: () => new Date("2026-10-22T13:00:00Z") });
    expect(r.ifco.ok).toBe(false);
    expect(messenger.sent).toEqual([]);
  });
});
