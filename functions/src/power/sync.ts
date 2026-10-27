// The power-outage run, every 15 minutes (spec power-outages D3–D5, §6):
//   1. current interruptions: version file → list → what's in Témiscaming;
//   2. planned interruptions, once an hour: the same two steps;
//   3. save `power/temiscaming`, then push if needed.
// Each part has its own health record, and a part that fails keeps what was
// stored before (silence must never look like safety).
//
// Pushes (opt-in, topics power-fr / power-en) remember the last thing we TOLD
// people (`pushed`: "out" or "restored"), like fire bans:
//   - unplanned outages here add up to at least 25 customers, and the last
//     word wasn't "out" → push "out";
//   - the last word was "out", and no unplanned outage has been listed here
//     for 20 minutes (of successful checks) → push "restored".
// So a second outage during the first sends nothing, and an outage that
// flickers off the list for one run doesn't send "restored" then "out" again.
// Planned interruptions never push: Hydro-Québec tells its customers itself.
// The first run records the state without pushing (no surprise on deploy).
import { Fetcher, Messenger } from "../alerts/sync";
import { Lang, PowerArea, PowerPushKind, powerPushText } from "../push/templates";
import { ongoingHere, Outage, Planned, plannedHere } from "./filter";
import { parseOngoing, parsePlanned, parseVersion, POWER_URLS, Version } from "./parse";

export const POWER_TOPICS: Record<Lang, string> = { fr: "power-fr", en: "power-en" };
export const POWER_SOURCE_ID = { ongoing: "hq-outages", planned: "hq-planned" } as const;
export type PowerPart = keyof typeof POWER_SOURCE_ID;

/** Unplanned outages here must add up to this many customers to push (spec D5, agreed). */
export const PUSH_MIN_CUSTOMERS = 25;
/** "Restored" waits until no outage has been listed for this long (spec D5). */
export const RESTORED_AFTER_MS = 20 * 60_000;
/** A version older than this is a frozen file, not "nothing happening" (spec D3). */
export const MAX_VERSION_AGE_MS: Record<PowerPart, number> = { ongoing: 45 * 60_000, planned: 6 * 3600_000 };
/** Planned interruptions are read about once an hour (spec D4). */
export const PLANNED_EVERY_MS = 55 * 60_000;

/** Links the app shows (spec D10), kept here so they can be fixed without an app release. */
export const POWER_LINKS = {
  map_url_fr: "https://infopannes.solutions.hydroquebec.com/info-pannes?langue=fr",
  map_url_en: "https://infopannes.solutions.hydroquebec.com/info-pannes?langue=en",
} as const;

/** Firestore `power/temiscaming` (spec §5): public. */
export interface PowerDoc {
  outages: Outage[];
  planned: Planned[];
  version_ongoing: string;
  version_planned: string;
  outages_checked_at: Date | null;
  planned_checked_at: Date | null;
}

/** Firestore `power_state/temiscaming` (spec §5): backend only. */
export interface PowerPushState {
  pushed: PowerPushKind;
  pushed_at: Date;
  /** True when the first run recorded the state without sending anything. */
  baseline: boolean;
  /** Last successful check that listed an unplanned outage here. */
  last_seen_outage_at: Date | null;
}

export interface PowerHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  last_item_count: number;
  last_error: string;
  warnings: string[];
}

export interface PowerStore {
  loadPower(): Promise<PowerDoc | null>;
  savePower(doc: PowerDoc): Promise<void>;
  loadPushState(): Promise<PowerPushState | null>;
  savePushState(state: PowerPushState): Promise<void>;
  loadHealth(part: PowerPart): Promise<PowerHealth | null>;
  saveHealth(part: PowerPart, h: PowerHealth): Promise<void>;
}

export interface PowerDeps {
  store: PowerStore;
  fetcher: Fetcher;
  messenger: Messenger;
  now: () => Date;
  log?: (message: string) => void;
}

export interface PartResult {
  ok: boolean;
  skipped?: boolean;
  error?: string;
  here?: number;
}

export interface PowerResult {
  ongoing: PartResult;
  planned: PartResult;
  pushed?: PowerPushKind;
}

const decode = (bytes: Uint8Array) => new TextDecoder().decode(bytes);

function json(bytes: Uint8Array, what: string): unknown {
  try {
    return JSON.parse(decode(bytes));
  } catch {
    throw new Error(`${what}: not JSON`);
  }
}

/** Version file, freshness check (spec D3), then the list it names. */
async function download(deps: PowerDeps, part: PowerPart, now: Date): Promise<{ version: Version; body: unknown }> {
  const versionUrl = part === "ongoing" ? POWER_URLS.ongoingVersion : POWER_URLS.plannedVersion;
  const version = parseVersion(decode(await deps.fetcher.get(versionUrl)));
  const age = now.getTime() - version.at.getTime();
  if (age > MAX_VERSION_AGE_MS[part]) {
    throw new Error(`${part}: Hydro-Québec's file hasn't changed since ${version.id} (${Math.round(age / 60_000)} min)`);
  }
  const listUrl = part === "ongoing" ? POWER_URLS.ongoing(version.id) : POWER_URLS.planned(version.id);
  return { version, body: json(await deps.fetcher.get(listUrl), part) };
}

async function recordFailure(deps: PowerDeps, part: PowerPart, at: Date, prev: PowerHealth | null, error: string) {
  deps.log?.(`power ${part}: FAILED — ${error}`);
  try {
    await deps.store.saveHealth(part, {
      last_attempt_at: at,
      last_success_at: prev?.last_success_at ?? null,
      last_item_count: prev?.last_item_count ?? 0,
      last_error: error.slice(0, 300),
      warnings: prev?.warnings ?? [],
    });
  } catch (e) {
    deps.log?.(`power ${part}: could not record the failure — ${(e as Error).message}`);
  }
}

async function sendBoth(deps: PowerDeps, kind: PowerPushKind, customers: number, areas: PowerArea[]): Promise<number> {
  let sent = 0;
  for (const lang of ["fr", "en"] as Lang[]) {
    try {
      await deps.messenger.send({
        topic: POWER_TOPICS[lang],
        ...powerPushText(kind, customers, areas, lang),
        urgent: kind === "out",
        channel: "power",
        data: { screen: "power" },
      });
      sent++;
    } catch (e) {
      deps.log?.(`power: push to ${POWER_TOPICS[lang]} FAILED — ${(e as Error).message}`);
    }
  }
  return sent;
}

/** Works out the push (if any) and the new push state, after a successful check of current outages. */
async function decidePush(
  deps: PowerDeps, prev: PowerPushState | null, outages: Outage[], now: Date,
): Promise<{ state: PowerPushState; pushed?: PowerPushKind }> {
  const unplanned = outages.filter((o) => o.kind === "outage");
  const customers = unplanned.reduce((n, o) => n + o.customers, 0);
  const lastSeen = unplanned.length > 0 ? now : prev?.last_seen_outage_at ?? null;

  if (!prev) {
    const kind: PowerPushKind = customers >= PUSH_MIN_CUSTOMERS ? "out" : "restored";
    deps.log?.(`power: first run, recording "${kind}" without pushing`);
    return { state: { pushed: kind, pushed_at: now, baseline: true, last_seen_outage_at: lastSeen } };
  }

  let wanted: PowerPushKind | null = null;
  if (prev.pushed !== "out" && customers >= PUSH_MIN_CUSTOMERS) wanted = "out";
  else if (
    prev.pushed === "out" && unplanned.length === 0
    && (!lastSeen || now.getTime() - lastSeen.getTime() >= RESTORED_AFTER_MS)
  ) wanted = "restored";

  const kept = { ...prev, last_seen_outage_at: lastSeen };
  if (!wanted) return { state: kept };
  const areas = wanted === "out" ? unplanned.map((o) => o.area) : [];
  const sent = await sendBoth(deps, wanted, customers, areas);
  // Nothing went out: try again next run, if still true. If one language
  // failed, the other was told: re-sending every 15 minutes would be worse.
  if (sent === 0) return { state: kept };
  return { state: { pushed: wanted, pushed_at: now, baseline: false, last_seen_outage_at: lastSeen }, pushed: wanted };
}

export async function runPowerPoll(deps: PowerDeps): Promise<PowerResult> {
  const now = deps.now();
  const log = deps.log ?? (() => {});
  let stored: PowerDoc | null;
  let pushState: PowerPushState | null;
  const health: Record<PowerPart, PowerHealth | null> = { ongoing: null, planned: null };
  try {
    stored = await deps.store.loadPower();
    pushState = await deps.store.loadPushState();
    health.ongoing = await deps.store.loadHealth("ongoing");
    health.planned = await deps.store.loadHealth("planned");
  } catch (e) {
    // Without the previous state we can't tell what changed; skip this run.
    const error = `could not load the stored state — ${(e as Error).message}`;
    log(`power: FAILED — ${error}`);
    return { ongoing: { ok: false, error }, planned: { ok: false, error } };
  }

  const doc: PowerDoc = stored ?? {
    outages: [], planned: [], version_ongoing: "", version_planned: "",
    outages_checked_at: null, planned_checked_at: null,
  };
  const result: PowerResult = { ongoing: { ok: false }, planned: { ok: false, skipped: true } };
  const newHealth: Partial<Record<PowerPart, PowerHealth>> = {};

  // 1. Current interruptions.
  try {
    const { version, body } = await download(deps, "ongoing", now);
    const rows = parseOngoing(body);
    const here = ongoingHere(rows);
    doc.outages = here.items;
    doc.version_ongoing = version.id;
    doc.outages_checked_at = now;
    newHealth.ongoing = {
      last_attempt_at: now, last_success_at: now, last_item_count: rows.length, last_error: "",
      warnings: here.warnings.slice(0, 20),
    };
    result.ongoing = { ok: true, here: here.items.length };
    here.warnings.forEach((w) => log(`power ongoing: warning — ${w}`));
  } catch (e) {
    const error = (e as Error).message ?? String(e);
    result.ongoing = { ok: false, error };
    await recordFailure(deps, "ongoing", now, health.ongoing, error);
  }

  // 2. Planned interruptions, about once an hour (or while they've never worked).
  const lastTry = health.planned?.last_attempt_at;
  if (!lastTry || !health.planned?.last_success_at || now.getTime() - lastTry.getTime() >= PLANNED_EVERY_MS) {
    try {
      const { version, body } = await download(deps, "planned", now);
      const rows = parsePlanned(body);
      const here = plannedHere(rows, now);
      doc.planned = here.items;
      doc.version_planned = version.id;
      doc.planned_checked_at = now;
      newHealth.planned = {
        last_attempt_at: now, last_success_at: now, last_item_count: rows.length, last_error: "",
        warnings: here.warnings.slice(0, 20),
      };
      result.planned = { ok: true, here: here.items.length };
      here.warnings.forEach((w) => log(`power planned: warning — ${w}`));
    } catch (e) {
      const error = (e as Error).message ?? String(e);
      result.planned = { ok: false, error };
      await recordFailure(deps, "planned", now, health.planned, error);
    }
  } else {
    // Not read this run: drop planned interruptions that have started since
    // (they appear as "in progress" in the current list instead).
    doc.planned = doc.planned.filter((p) => p.starts_at > now);
    result.planned = { ok: true, skipped: true };
  }

  // 3. Push (only on a successful check of current outages), then save.
  let state = pushState;
  if (result.ongoing.ok) {
    const decided = await decidePush(deps, pushState, doc.outages, now);
    state = decided.state;
    result.pushed = decided.pushed;
  }
  try {
    if (result.ongoing.ok || (result.planned.ok && !result.planned.skipped) || !stored) {
      await deps.store.savePower(doc);
    }
    if (state && state !== pushState) await deps.store.savePushState(state);
    for (const part of ["ongoing", "planned"] as PowerPart[]) {
      const h = newHealth[part];
      if (h) await deps.store.saveHealth(part, h);
    }
  } catch (e) {
    const error = `FAILED to save — ${(e as Error).message}`;
    log(`power: ${error}`);
    return {
      ongoing: result.ongoing.ok ? { ok: false, error } : result.ongoing,
      planned: result.planned.ok && !result.planned.skipped ? { ok: false, error } : result.planned,
      pushed: result.pushed,
    };
  }

  const describe = (r: PartResult, version: string, extra = "") =>
    r.ok ? (r.skipped ? "not due" : `ok (v${version}, ${r.here} here${extra})`) : "FAILED";
  const rowsOngoing = newHealth.ongoing ? `, ${newHealth.ongoing.last_item_count} in Quebec` : "";
  const rowsPlanned = newHealth.planned ? `, ${newHealth.planned.last_item_count} in Quebec` : "";
  log(
    `power: ongoing ${describe(result.ongoing, doc.version_ongoing, rowsOngoing)}, `
    + `planned ${describe(result.planned, doc.version_planned, rowsPlanned)}`
    + `${result.pushed ? `; pushed "${result.pushed}"` : ""}`,
  );
  return result;
}
