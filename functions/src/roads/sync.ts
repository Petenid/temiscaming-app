// The roads runs (roads spec §6):
//   - runRoadsPoll, every 15 minutes: Quebec's three MTMD layers, then Ontario
//     511 (paced under its 10-calls-per-minute limit, D4) → items on our
//     stretches, Route 101 / Highway 63 conditions, Highway 63 cameras (once a
//     day) → save → push when a road closes or reopens (D7).
//   - runTownWorkInfoPoll, every hour: the Town's Work Info pages.
// Each source is read and recorded on its own: one failing never stops the
// others, and a failed source's items are left exactly as they were (D3).
//
// Closure pushes. We remember, per closure "key" (road + place), the last
// thing we TOLD people: "closed" or "reopened". A closure on our stretch that
// people haven't been told about → push "closed" (planned ones say from
// when). A closure we told people about that has been gone for at least
// REOPEN_AFTER_MS, with every source that reported it read successfully since
// → push "reopened". Waiting a little before "reopened" means an item the
// ministry deletes and re-posts (it happens) sends nothing at all. A failed
// push is simply tried again next run, if still true. The first run ever
// records what's there without pushing.
import { Fetcher, Messenger } from "../alerts/sync";
import { fold } from "../alerts/dates";
import { Lang, roadPushText, RoadPushKind } from "../push/templates";
import { Road } from "./corridor";
import { isCurrent, onToday, RoadItem, RoadSource, Status, statusOf } from "./model";
import {
  Camera, OntarioCall, ontarioUrl, ontarioUrlForLog, parseCameras, parseOntarioConditions, parseOntarioItems,
} from "./ontario";
import { parseConditions, parseRoadworks, parseWarnings, QUEBEC_URL, QuebecLayer, Segment } from "./quebec";
import { buildTownItems, parseTownDetail, parseTownList, TOWN_LIST_URL, TownListItem } from "./town";

export const ROAD_TOPICS: Record<Lang, string> = { fr: "roads-fr", en: "roads-en" };
export const ROAD_CHANNEL = "roads";

/** Health records (`sources/{id}`), spec D4. */
export type RoadsHealthId = RoadSource | "mtmd-conditions" | "on511-conditions";

/** Pause between Ontario 511 calls: 7 s keeps any 60 s window under 10 calls (spec D4). */
export const ONTARIO_PAUSE_MS = 7_000;
/** Pause between calls to the same Quebec or Town server (being gentle, principle 4). */
export const POLITE_PAUSE_MS = 2_000;
/** A closure must be gone this long before "reopened" goes out (see top of file). */
export const REOPEN_AFTER_MS = 25 * 60_000;
/** Reopened closures are forgotten after this. */
const FORGET_AFTER_MS = 7 * 24 * 3600_000;

export interface StoredRoadItem extends RoadItem {
  status: Status;
  on_today: boolean;
  first_seen_at: Date;
  updated_at: Date;
}

export interface StoredConditions {
  segments: Segment[];
  /** Quebec only: inside the 15 Oct – 15 Apr publishing season. */
  in_season: boolean | null;
  checked_at: Date;
}

export interface StoredCameras {
  cameras: Camera[];
  checked_at: Date;
}

export interface ClosureRecord {
  told: RoadPushKind;
  told_at: Date | null;
  last_seen_at: Date;
  road: Road | null;
  place: string;
  sources: RoadSource[];
}

/** Backend-only `roads_state/pushes`: what people were last told, per closure. */
export interface PushState {
  closures: Record<string, ClosureRecord>;
  created_at: Date;
}

export interface RoadsHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  last_item_count: number;
  last_error: string;
  warnings: string[];
}

export interface RoadsStore {
  loadItems(): Promise<StoredRoadItem[]>;
  saveItems(docs: StoredRoadItem[]): Promise<void>;
  deleteItems(ids: string[]): Promise<void>;
  saveConditions(id: "route-101" | "highway-63", doc: StoredConditions): Promise<void>;
  loadCameras(): Promise<StoredCameras | null>;
  saveCameras(doc: StoredCameras): Promise<void>;
  loadPushState(): Promise<PushState | null>;
  savePushState(state: PushState): Promise<void>;
  loadHealth(id: RoadsHealthId): Promise<RoadsHealth | null>;
  saveHealth(id: RoadsHealthId, h: RoadsHealth): Promise<void>;
}

export interface RoadsDeps {
  store: RoadsStore;
  fetcher: Fetcher;
  messenger: Messenger;
  now: () => Date;
  /** Waits (real: setTimeout; tests: moves a fake clock). */
  sleep: (ms: number) => Promise<void>;
  /** The Ontario 511 developer key (Firebase secret, spec D15); missing → Ontario fails. */
  ontarioKey?: string;
  log?: (message: string) => void;
}

/** One source's outcome in a run. */
interface Outcome<T> {
  ok: boolean;
  value?: T;
  error?: string;
  warnings: string[];
  count: number;
}

export interface RoadsRunResult {
  ok: boolean;
  sources: Partial<Record<RoadsHealthId, { ok: boolean; error?: string; count: number }>>;
  pushed: { key: string; kind: RoadPushKind }[];
}

const decode = (bytes: Uint8Array) => new TextDecoder("utf-8", { fatal: false }).decode(bytes);

function parseJson(bytes: Uint8Array, what: string): unknown {
  try {
    return JSON.parse(decode(bytes));
  } catch {
    throw new Error(`${what}: not JSON`);
  }
}

/** Error text with the Ontario key hidden (spec D15). */
function safeError(e: unknown, key: string | undefined): string {
  let msg = (e as Error)?.message ?? String(e);
  if (key) msg = msg.split(key).join("***").split(encodeURIComponent(key)).join("***");
  return msg.slice(0, 300);
}

async function recordHealth(
  deps: RoadsDeps, id: RoadsHealthId, startedAt: Date, outcome: Outcome<unknown>,
): Promise<void> {
  try {
    const prev = await deps.store.loadHealth(id);
    await deps.store.saveHealth(id, outcome.ok
      ? { last_attempt_at: startedAt, last_success_at: startedAt, last_item_count: outcome.count, last_error: "", warnings: outcome.warnings.slice(0, 20) }
      : {
        last_attempt_at: startedAt,
        last_success_at: prev?.last_success_at ?? null,
        last_item_count: prev?.last_item_count ?? 0,
        last_error: outcome.error ?? "failed",
        warnings: prev?.warnings ?? [],
      });
  } catch (e) {
    deps.log?.(`roads ${id}: could not record health — ${(e as Error).message}`);
  }
}

/** Saves the items of the sources read OK; deletes theirs that are gone or no longer current. */
async function syncItems(
  deps: RoadsDeps, fresh: Map<RoadSource, RoadItem[]>, now: Date,
): Promise<{ written: number; deleted: number }> {
  const stored = await deps.store.loadItems();
  const byId = new Map(stored.map((s) => [s.id, s]));
  const keep = new Set<string>();
  const docs: StoredRoadItem[] = [];
  for (const items of fresh.values()) {
    for (const item of items) {
      if (!isCurrent(item, now)) continue;
      keep.add(item.id);
      docs.push({
        ...item,
        status: statusOf(item, now),
        on_today: onToday(item, now),
        first_seen_at: byId.get(item.id)?.first_seen_at ?? now,
        updated_at: now,
      });
    }
  }
  const gone = stored.filter((s) => fresh.has(s.source) && !keep.has(s.id)).map((s) => s.id);
  // Items of sources NOT read this run keep their old fields, but their status
  // can still move from "planned" to "in effect" with the clock.
  for (const s of stored) {
    if (fresh.has(s.source)) continue;
    const status = statusOf(s, now);
    const today = onToday(s, now);
    if (status !== s.status || today !== s.on_today) docs.push({ ...s, status, on_today: today });
  }
  if (docs.length) await deps.store.saveItems(docs);
  if (gone.length) await deps.store.deleteItems(gone);
  return { written: docs.length, deleted: gone.length };
}

const closureKey = (item: { road: Road | null; place: string }) => `${item.road ?? "town"}|${fold(item.place)}`;

async function sendBoth(
  deps: RoadsDeps, rec: { road: Road | null; place: string }, kind: RoadPushKind, startsAt: Date | null, now: Date,
): Promise<number> {
  const road = rec.road ?? "101";
  let sent = 0;
  for (const lang of ["fr", "en"] as Lang[]) {
    try {
      await deps.messenger.send({
        topic: ROAD_TOPICS[lang],
        ...roadPushText(road, kind, rec.place, startsAt, now, lang),
        urgent: kind === "closed",
        channel: ROAD_CHANNEL,
        data: { screen: "roads", road },
      });
      sent++;
    } catch (e) {
      deps.log?.(`roads: push to ${ROAD_TOPICS[lang]} FAILED — ${(e as Error).message}`);
    }
  }
  return sent;
}

/** Spec D7 (see top of file). Mutates and returns the state; lists what was pushed. */
async function closurePushes(
  deps: RoadsDeps, state: PushState | null, fresh: Map<RoadSource, RoadItem[]>, now: Date,
): Promise<{ state: PushState; pushed: { key: string; kind: RoadPushKind }[] }> {
  const baseline = !state;
  const next: PushState = state ?? { closures: {}, created_at: now };
  const pushed: { key: string; kind: RoadPushKind }[] = [];

  // Closures on our stretches right now, from the sources read OK.
  const current = new Map<string, RoadItem[]>();
  for (const items of fresh.values()) {
    for (const item of items) {
      if (item.kind !== "closure" || !isCurrent(item, now)) continue;
      const key = closureKey(item);
      current.set(key, [...(current.get(key) ?? []), item]);
    }
  }

  for (const [key, items] of current) {
    const rec = next.closures[key];
    const sources = [...new Set([...(rec?.sources ?? []), ...items.map((i) => i.source)])];
    const entry: ClosureRecord = rec
      ? { ...rec, last_seen_at: now, sources }
      : { told: "reopened", told_at: null, last_seen_at: now, road: items[0].road, place: items[0].place, sources };
    if (entry.told !== "closed") {
      if (baseline) {
        entry.told = "closed";
      } else {
        // The earliest start among this key's items: "planned from …" if still ahead.
        const starts = items.map((i) => i.starts_at).filter((d): d is Date => !!d).sort((a, b) => +a - +b)[0] ?? null;
        if (await sendBoth(deps, entry, "closed", starts, now)) {
          entry.told = "closed";
          entry.told_at = now;
          pushed.push({ key, kind: "closed" });
        }
      }
    }
    next.closures[key] = entry;
  }

  for (const [key, rec] of Object.entries(next.closures)) {
    if (current.has(key)) continue;
    if (rec.told === "closed") {
      const allRead = rec.sources.every((s) => fresh.has(s));
      if (allRead && now.getTime() - rec.last_seen_at.getTime() >= REOPEN_AFTER_MS) {
        if (await sendBoth(deps, rec, "reopened", null, now)) {
          next.closures[key] = { ...rec, told: "reopened", told_at: now };
          pushed.push({ key, kind: "reopened" });
        }
      }
    } else if (now.getTime() - rec.last_seen_at.getTime() > FORGET_AFTER_MS) {
      delete next.closures[key];
    }
  }
  return { state: next, pushed };
}

/** One full roads run (every 15 minutes). */
export async function runRoadsPoll(deps: RoadsDeps): Promise<RoadsRunResult> {
  const { fetcher, now } = deps;
  const log = deps.log ?? (() => {});
  const key = deps.ontarioKey?.trim() || undefined;
  const startedAt = now();
  const result: RoadsRunResult = { ok: true, sources: {}, pushed: [] };

  let state: PushState | null;
  try {
    state = await deps.store.loadPushState();
  } catch (e) {
    const error = `could not load roads_state/pushes — ${(e as Error).message}`;
    log(`roads: FAILED — ${error}`);
    // Without it we can't tell what people were told; skip this run.
    return { ok: false, sources: {}, pushed: [] };
  }

  const fresh = new Map<RoadSource, RoadItem[]>();
  const outcomes = new Map<RoadsHealthId, Outcome<unknown>>();
  const fail = (e: unknown): Outcome<never> => ({ ok: false, error: safeError(e, key), warnings: [], count: 0 });

  // 1. Quebec (one server, gently paced).
  const quebec: QuebecLayer[] = ["warnings", "roadworks", "conditions"];
  const qcBytes = new Map<QuebecLayer, Uint8Array | Error>();
  for (const [i, layer] of quebec.entries()) {
    if (i) await deps.sleep(POLITE_PAUSE_MS);
    try {
      qcBytes.set(layer, await fetcher.get(QUEBEC_URL[layer]));
    } catch (e) {
      qcBytes.set(layer, e as Error);
    }
  }
  const qcRead = <T>(layer: QuebecLayer, parse: (json: unknown) => T): T => {
    const b = qcBytes.get(layer)!;
    if (b instanceof Error) throw b;
    return parse(parseJson(b, layer));
  };
  for (const [layer, source] of [["warnings", "mtmd-warnings"], ["roadworks", "mtmd-roadworks"]] as const) {
    try {
      const r = qcRead(layer, layer === "warnings" ? parseWarnings : parseRoadworks);
      fresh.set(source, r.items);
      outcomes.set(source, { ok: true, warnings: r.warnings, count: r.items.length });
    } catch (e) {
      outcomes.set(source, fail(e));
    }
  }
  let qcConditions: StoredConditions | null = null;
  try {
    const r = qcRead("conditions", (json) => parseConditions(json, startedAt));
    qcConditions = { segments: r.conditions.segments, in_season: r.conditions.in_season, checked_at: startedAt };
    outcomes.set("mtmd-conditions", { ok: true, warnings: r.warnings, count: r.conditions.segments.length });
  } catch (e) {
    outcomes.set("mtmd-conditions", fail(e));
  }

  // 2. Ontario 511, never more than one call per ONTARIO_PAUSE_MS (spec D4).
  let onConditions: StoredConditions | null = null;
  let cameras: StoredCameras | null = null;
  if (!key) {
    for (const id of ["on511-events", "on511-construction", "on511-conditions"] as const) {
      outcomes.set(id, fail(new Error("no Ontario 511 key (Firebase secret ONTARIO_511_KEY)")));
    }
  } else {
    let calls = 0;
    const get = async (call: OntarioCall, lang: "fr" | "en"): Promise<unknown> => {
      if (calls++) await deps.sleep(ONTARIO_PAUSE_MS);
      let bytes: Uint8Array;
      try {
        bytes = await fetcher.get(ontarioUrl(call, lang, key));
      } catch (e) {
        throw new Error(`${ontarioUrlForLog(call, lang)}: ${safeError(e, key)}`);
      }
      return parseJson(bytes, `${call} (${lang})`);
    };
    for (const [call, source] of [["events", "on511-events"], ["construction", "on511-construction"]] as const) {
      try {
        const en = await get(call, "en");
        const fr = await get(call, "fr");
        const r = parseOntarioItems(call, en, fr);
        fresh.set(source, r.items);
        outcomes.set(source, { ok: true, warnings: r.warnings, count: r.items.length });
      } catch (e) {
        outcomes.set(source, fail(e));
      }
    }
    try {
      const en = await get("conditions", "en");
      const fr = await get("conditions", "fr");
      const segments = parseOntarioConditions(en, fr);
      onConditions = { segments, in_season: null, checked_at: startedAt };
      outcomes.set("on511-conditions", { ok: true, warnings: [], count: segments.length });
    } catch (e) {
      outcomes.set("on511-conditions", fail(e));
    }
    // Cameras: the list rarely changes; refresh once a day, after 3 a.m.
    try {
      const prev = await deps.store.loadCameras();
      if (camerasDue(prev?.checked_at ?? null, startedAt)) {
        const list = parseCameras(await get("cameras", "en"));
        cameras = { cameras: list, checked_at: startedAt };
      }
    } catch (e) {
      log(`roads: cameras not refreshed — ${safeError(e, key)}`);
    }
  }

  // 3. Save what was read, push, record health.
  try {
    await syncItems(deps, fresh, startedAt);
    if (qcConditions) await deps.store.saveConditions("route-101", qcConditions);
    if (onConditions) await deps.store.saveConditions("highway-63", onConditions);
    if (cameras) await deps.store.saveCameras(cameras);
    const pushes = await closurePushes(deps, state, fresh, startedAt);
    await deps.store.savePushState(pushes.state);
    result.pushed = pushes.pushed;
    if (!state) log("roads: first run, recording closures without pushing");
  } catch (e) {
    const error = `could not save — ${safeError(e, key)}`;
    log(`roads: FAILED — ${error}`);
    for (const id of outcomes.keys()) outcomes.set(id, { ok: false, error, warnings: [], count: 0 });
  }

  for (const [id, outcome] of outcomes) {
    await recordHealth(deps, id, startedAt, outcome);
    result.sources[id] = { ok: outcome.ok, error: outcome.error, count: outcome.count };
    if (!outcome.ok) result.ok = false;
    outcome.warnings.forEach((w) => log(`roads ${id}: warning — ${w}`));
  }
  const summary = [...outcomes].map(([id, o]) => `${id} ${o.ok ? `ok (${o.count})` : `FAILED — ${o.error}`}`).join(", ");
  log(`roads: ${summary}${result.pushed.length ? `; pushed ${result.pushed.map((p) => `${p.kind} ${p.key}`).join(", ")}` : ""}`);
  return result;
}

/** Due when never fetched, or last fetched before 3 a.m. today (Témiscaming time) and it's now past 3. */
export function camerasDue(last: Date | null, now: Date): boolean {
  if (!last) return true;
  const fmt = (d: Date) => new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit",
  }).format(d);
  const [nowDay, nowHour] = fmt(now).split(", ");
  const [lastDay, lastHour] = fmt(last).split(", ");
  if (+nowHour < 3) return false;
  return lastDay < nowDay || +lastHour < 3;
}

// --- The Town's Work Info (hourly) ---

export interface TownRunResult {
  ok: boolean;
  error?: string;
  count: number;
}

export async function runTownWorkInfoPoll(deps: Omit<RoadsDeps, "messenger" | "ontarioKey">): Promise<TownRunResult> {
  const { fetcher, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  const warnings: string[] = [];
  let outcome: Outcome<unknown>;
  try {
    const lists = { fr: [] as TownListItem[], en: [] as TownListItem[] };
    lists.fr = parseTownList(decode(await fetcher.get(TOWN_LIST_URL.fr)));
    await deps.sleep(POLITE_PAUSE_MS);
    lists.en = parseTownList(decode(await fetcher.get(TOWN_LIST_URL.en)));
    const stored = new Map((await deps.store.loadItems()).filter((s) => s.source === "town-work-info").map((s) => [s.id, s]));
    const details = { fr: new Map<string, { title: string; body: string }>(), en: new Map<string, { title: string; body: string }>() };
    for (const lang of ["fr", "en"] as const) {
      for (const item of lists[lang]) {
        await deps.sleep(POLITE_PAUSE_MS);
        try {
          details[lang].set(item.id, parseTownDetail(decode(await fetcher.get(item.url))));
        } catch (e) {
          // Keep the text we had; the list still tells us the item and its dates.
          const prev = stored.get(`town-${item.id}`);
          const body = lang === "fr" ? prev?.body_fr : prev?.body_en;
          if (body) details[lang].set(item.id, { title: item.title, body });
          warnings.push(`item ${item.id} (${lang}): page not read — ${(e as Error).message}`);
        }
      }
    }
    const items = buildTownItems(lists, details);
    await syncItems({ ...deps, messenger: { send: async () => {} } }, new Map([["town-work-info", items]]), startedAt);
    outcome = { ok: true, warnings, count: items.length };
  } catch (e) {
    outcome = { ok: false, error: safeError(e, undefined), warnings, count: 0 };
  }
  await recordHealth({ ...deps, messenger: { send: async () => {} } }, "town-work-info", startedAt, outcome);
  warnings.forEach((w) => log(`town work info: warning — ${w}`));
  log(`town work info: ${outcome.ok ? `ok (${outcome.count})` : `FAILED — ${outcome.error}`}`);
  return { ok: outcome.ok, error: outcome.error, count: outcome.count };
}
