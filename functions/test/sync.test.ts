// Runs whole polling runs against the real fixtures, with a fake database,
// fake network and fake push service. Covers the "done means" of DESIGN §6.1
// and spec §8.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import * as cheerio from "cheerio";
import { beforeEach, describe, expect, it } from "vitest";

import {
  Deps, LIST_URLS, MAX_DETAIL_FETCHES, PushMessage, SourceHealth, Store, StoredAlert, runPoll,
} from "../src/alerts/sync";

const dir = join(__dirname, "fixtures/2026-10-19");
const read = (name: string) => readFileSync(join(dir, name), "utf8");

/**
 * Edits a real list page to recreate an earlier moment:
 * drop some alerts, and/or remove the "(Alerte levée)" mark from others.
 */
function listAsOf(name: string, opts: { drop?: string[]; unlift?: string[] }): string {
  const $ = cheerio.load(read(name));
  for (const id of opts.drop ?? []) $(`#alertes .alerte:has([data-id="${id}"])`).remove();
  for (const id of opts.unlift ?? []) {
    const a = $(`#alertes .alerte:has([data-id="${id}"]) h4 a`);
    a.text(a.text().replace(/\((Alerte levée|Alert raised)\)\s*/, ""));
  }
  return $.html();
}

class FakeStore implements Store {
  alerts = new Map<string, StoredAlert>();
  health: SourceHealth | null = null;
  async loadAlerts() { return [...this.alerts.values()].map((d) => ({ ...d })); }
  async saveAlerts(docs: StoredAlert[]) {
    // Like the real adapter: saving never touches pushed_at (claimPush owns it).
    for (const d of docs) this.alerts.set(d.id, { ...d, pushed_at: this.alerts.get(d.id)?.pushed_at ?? null });
  }
  async claimPush(id: string, at: Date) {
    const d = this.alerts.get(id)!;
    if (d.pushed_at) return false;
    d.pushed_at = at;
    return true;
  }
  async releasePush(id: string) { this.alerts.get(id)!.pushed_at = null; }
  async loadHealth() { return this.health && { ...this.health }; }
  async saveHealth(h: SourceHealth) { this.health = { ...h }; }
}

let store: FakeStore;
let sent: PushMessage[];
let pages: Record<string, string>;
let fetched: string[];
let failPush: boolean;

function deps(at: string): Deps {
  return {
    store,
    now: () => new Date(at),
    fetcher: {
      async get(url) {
        fetched.push(url);
        const page = pages[url];
        if (page === undefined) throw new Error(`HTTP 404 ${url}`);
        return new TextEncoder().encode(page);
      },
    },
    messenger: {
      async send(m) {
        if (failPush) throw new Error("FCM unavailable");
        sent.push(m);
      },
    },
  };
}

const B = "https://temiscaming.alertesmunicipales.com";
const DETAILS: Record<string, string> = {
  [`${B}/alertes/2026/10/12/avis-d-ebullition-preventif`]: "detail-fr-boil.html",
  [`${B}/alerts/2026/10/12/precautionary-boil-water-advisory`]: "detail-en-boil.html",
  [`${B}/alertes/2026/10/19/levee-de-l-avis-d-ebullition-preventif`]: "detail-fr-lifted.html",
  [`${B}/alerts/2026/10/19/precautionary-boil-water-advisory-lifted`]: "detail-en-lifted.html",
};

/** Sets what the "site" shows: list pages as of a moment, plus the saved detail pages. */
function site(opts: { drop?: string[]; unlift?: string[] } = {}) {
  pages = {
    [LIST_URLS.fr]: listAsOf("list-fr.html", opts),
    [LIST_URLS.en]: listAsOf("list-en.html", opts),
  };
  for (const [url, file] of Object.entries(DETAILS)) pages[url] = read(file);
}

beforeEach(() => {
  store = new FakeStore();
  sent = [];
  fetched = [];
  failPush = false;
});

// Timeline of the real October 2026 advisory:
//   12 Oct 14h32  boil-water advisory 8344 posted
//   19 Oct 13h38  lifting notice 8376 posted; 13h58 re-posted as 8377; 8344 marked "(Alerte levée)"
const BEFORE_ADVISORY = { drop: ["8344", "8376", "8377"] };
const DURING_ADVISORY = { drop: ["8376", "8377"], unlift: ["8344"] };

describe("first run", () => {
  it("stores every alert and pushes nothing", async () => {
    site();
    const r = await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(r).toMatchObject({ ok: true, itemCount: 94, pushed: [] });
    expect(store.alerts.size).toBe(94);
    expect(sent).toEqual([]);
    expect([...store.alerts.values()].every((d) => d.push_skipped === "first-run")).toBe(true);
  });

  it("is gentle: two list pages plus at most 10 detail pages", async () => {
    site();
    await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(fetched.slice(0, 2).sort()).toEqual([LIST_URLS.fr, LIST_URLS.en].sort());
    expect(fetched.length).toBeLessThanOrEqual(2 + MAX_DETAIL_FETCHES);
  });
});

describe("a new boil-water advisory", () => {
  beforeEach(async () => {
    site(BEFORE_ADVISORY);
    await runPoll(deps("2026-10-12T18:00:00Z")); // first run, before 14h32
    sent = [];
    site(DURING_ADVISORY);
  });

  it("sends exactly one urgent push per language", async () => {
    const r = await runPoll(deps("2026-10-12T18:40:00Z"));
    expect(r.pushed).toEqual(["8344"]);
    expect(sent).toEqual([
      expect.objectContaining({ topic: "water-fr", title: "Avis d'ébullition à Témiscaming", alertId: "8344", urgent: true }),
      expect.objectContaining({ topic: "water-en", title: "Boil-water advisory in Témiscaming", alertId: "8344", urgent: true }),
    ]);
  });

  it("stores it as an active urgent advisory with its full text", async () => {
    await runPoll(deps("2026-10-12T18:40:00Z"));
    expect(store.alerts.get("8344")).toMatchObject({
      status: "active", severity: "urgent", category: "boil-water", kind: "advisory",
      body_is_excerpt: false, original_language: "both",
    });
    expect(store.alerts.get("8344")!.body_fr).toContain("au moins une minute");
  });

  it("doesn't push again on the next run", async () => {
    await runPoll(deps("2026-10-12T18:40:00Z"));
    sent = [];
    const r = await runPoll(deps("2026-10-12T18:50:00Z"));
    expect(r.pushed).toEqual([]);
    expect(sent).toEqual([]);
  });

  it("retries on the next run if the push service fails", async () => {
    failPush = true;
    expect((await runPoll(deps("2026-10-12T18:40:00Z"))).pushed).toEqual([]);
    failPush = false;
    expect((await runPoll(deps("2026-10-12T18:50:00Z"))).pushed).toEqual(["8344"]);
    expect(sent).toHaveLength(2);
  });
});

describe("the advisory is lifted", () => {
  beforeEach(async () => {
    site(BEFORE_ADVISORY);
    await runPoll(deps("2026-10-12T18:00:00Z"));
    site(DURING_ADVISORY);
    await runPoll(deps("2026-10-12T18:40:00Z"));
    sent = [];
    site(); // the real page of 19 Oct, 17h05
  });

  it("updates the original advisory instead of duplicating it", async () => {
    const before = store.alerts.size;
    await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(store.alerts.get("8344")).toMatchObject({ status: "lifted", title_fr: "AVIS D'ÉBULLITION PRÉVENTIF" });
    expect(store.alerts.size).toBe(before + 2); // only the two lifting notices are new
  });

  it("sends one quieter 'lifted' push, not a boil-water push, despite two lifting notices", async () => {
    const r = await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(r.pushed).toEqual(["8376"]); // the first of the two
    expect(sent.map((m) => [m.topic, m.title, m.urgent])).toEqual([
      ["water-fr", "Avis levé", false],
      ["water-en", "Advisory lifted", false],
    ]);
    expect(store.alerts.get("8377")!.push_skipped).toBe("duplicate");
  });

  it("keeps the excerpt for the alert whose URL shows its twin", async () => {
    await runPoll(deps("2026-10-19T18:05:00Z"));
    // 8376 and 8377 share a URL; the page shows 8377 (13h58).
    expect(store.alerts.get("8377")).toMatchObject({ body_is_excerpt: false, detail_fetched: true });
    expect(store.alerts.get("8376")).toMatchObject({ body_is_excerpt: true, detail_fetched: true });
  });
});

describe("source health — silence must never look like safety", () => {
  it("records a failure and changes nothing when the page has no alerts", async () => {
    site();
    await runPoll(deps("2026-10-19T18:05:00Z"));
    const saved = new Map(store.alerts);
    pages[LIST_URLS.fr] = "<html><body>Maintenance</body></html>";
    pages[LIST_URLS.en] = "<html><body>Maintenance</body></html>";
    const r = await runPoll(deps("2026-10-19T18:15:00Z"));
    expect(r.ok).toBe(false);
    expect(store.health).toMatchObject({
      last_success_at: new Date("2026-10-19T18:05:00Z"),
      last_attempt_at: new Date("2026-10-19T18:15:00Z"),
      last_item_count: 94,
    });
    expect(store.health!.last_error).toMatch(/parsed 0 alerts, expected about 94/);
    expect(store.alerts).toEqual(saved);
  });

  it("records a failure when the site can't be reached", async () => {
    pages = {};
    const r = await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(r.ok).toBe(false);
    expect(store.health).toMatchObject({ last_success_at: null, last_error: expect.stringMatching(/download: HTTP 404/) });
  });

  it("records success with the item count", async () => {
    site();
    await runPoll(deps("2026-10-19T18:05:00Z"));
    expect(store.health).toMatchObject({ last_success_at: new Date("2026-10-19T18:05:00Z"), last_item_count: 94, last_error: "" });
  });
});

describe("old alerts", () => {
  it("never pushes an alert published more than 24 h before it was seen", async () => {
    site(BEFORE_ADVISORY);
    await runPoll(deps("2026-10-12T18:00:00Z"));
    site(DURING_ADVISORY);
    const r = await runPoll(deps("2026-10-14T12:00:00Z")); // ~2 days late
    expect(r.pushed).toEqual([]);
    expect(store.alerts.get("8344")!.push_skipped).toBe("too-old");
  });
});
