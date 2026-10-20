// One calendar polling run (spec §6): download this month and the next two
// in both languages, merge with the MRC calendar, work out what changed,
// save it, record source health, and send change notices.
//
// Like the alerts poll, network, database and push are passed in as small
// interfaces, so tests run whole polls against fixtures with fakes.
import { decodePage } from "../alerts/parse";
import { Fetcher, Messenger } from "../alerts/sync";
import { BinMaterial, CollectionChange, collectionChangeText } from "../push/templates";
import { Material, SectorId, Special } from "./classify";
import {
  MergedPickup, MrcCalendar, Origin, mergeSchedules, mrcPickups, mrcThrough, weekKey,
} from "./merge";
import { buildPickups } from "./pair";
import { CalendarEntry, monthUrl, parseMonth } from "./parse";

export const SOURCE_ID = "town-calendar";
/** Months fetched after the current one (spec D2). */
export const MONTHS_AHEAD = 2;
/** Change notices only for pickups within this many days (spec D3). */
export const PUSH_WINDOW_DAYS = 14;
/** A pickup that disappears and reappears within this many days has moved. */
export const MOVE_WINDOW_DAYS = 7;
/** Android notification channel for bins (spec D10). */
export const COLLECTION_CHANNEL = "collection";

export const topicFor = (sector: SectorId, lang: "fr" | "en") => `collection-${sector}-${lang}`;

/** Firestore `collections/{id}` (spec §5). */
export interface StoredPickup {
  id: string;
  origin: Origin;
  event_id: string;
  source: typeof SOURCE_ID;
  type: "collection";
  date: string;
  sector: SectorId;
  material: Material | null;
  special: Special | null;
  title_fr: string;
  title_en: string;
  source_url_fr: string;
  source_url_en: string;
  irregular: boolean;
  status: "scheduled" | "cancelled";
  /** Set when the pickup moved here from another date. */
  previous_date: string | null;
  /** The latest change the app should point out, if any. */
  change: CollectionChange | null;
  change_at: Date | null;
  first_seen_at: Date;
  updated_at: Date;
  pushed_at?: Date | null;
  push_skipped?: string | null;
}

/** Firestore `sources/town-calendar` (DESIGN §4 source health, spec §5). */
export interface CalendarHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  /** Town bin pickups found in the months fetched. */
  last_item_count: number;
  last_error: string;
  /** Town bin pickups per month ("2026-10": 14), to notice a page that suddenly shrinks. */
  month_counts: Record<string, number>;
  /** Last date the Town has posted a bin pickup for. */
  posted_through: string | null;
  /** Last date with any known bin pickup (Town or MRC): the app's "not posted yet" line. */
  known_through: string | null;
  /** Last date the MRC data covers. */
  mrc_through: string | null;
  /** Schedule-check notes from the latest successful run (spec D5). */
  warnings: string[];
}

export interface CollectionStore {
  /** Pickups dated on or after `fromDate`. */
  loadPickups(fromDate: string): Promise<StoredPickup[]>;
  /** Writes documents. pushed_at is only written when it's null (a new change resets it). */
  savePickups(docs: StoredPickup[]): Promise<void>;
  deletePickups(ids: string[]): Promise<void>;
  claimPush(id: string, at: Date): Promise<boolean>;
  releasePush(id: string): Promise<void>;
  loadHealth(): Promise<CalendarHealth | null>;
  saveHealth(h: CalendarHealth): Promise<void>;
}

export interface CollectionDeps {
  store: CollectionStore;
  fetcher: Fetcher;
  messenger: Messenger;
  /** The MRC calendars we have (functions/data/mrc-<year>.json). */
  mrc: MrcCalendar[];
  now: () => Date;
  log?: (message: string) => void;
}

export interface CollectionRunResult {
  ok: boolean;
  error?: string;
  townCount: number;
  written: number;
  deleted: number;
  /** One line per notice sent, e.g. "moved lumsden 2026-06-25". */
  pushed: string[];
  warnings: string[];
}

const pad = (n: number) => String(n).padStart(2, "0");

/** Today's date in Témiscaming, "YYYY-MM-DD". */
export function torontoDate(at: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(at);
}

/** `date` plus `days` days, both "YYYY-MM-DD". */
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

function daysBetween(a: string, b: string): number {
  const t = (s: string) => Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10));
  return Math.round((t(b) - t(a)) / 86_400_000);
}

/** The months to fetch: this month and the next MONTHS_AHEAD. */
export function windowMonths(today: string): { year: number; month: number }[] {
  const y = +today.slice(0, 4);
  const m = +today.slice(5, 7);
  return Array.from({ length: MONTHS_AHEAD + 1 }, (_, i) => {
    const n = m - 1 + i;
    return { year: y + Math.floor(n / 12), month: (n % 12) + 1 };
  });
}

export async function runCollectionPoll(deps: CollectionDeps): Promise<CollectionRunResult> {
  const { store, fetcher, messenger, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  const today = torontoDate(startedAt);
  const health = await store.loadHealth();
  const firstRun = !health?.last_success_at;

  const fail = async (error: string): Promise<CollectionRunResult> => {
    log(`calendar: FAILED — ${error}`);
    await store.saveHealth({
      ...(health ?? emptyHealth()),
      last_attempt_at: startedAt,
      last_success_at: health?.last_success_at ?? null,
      last_error: error.slice(0, 300),
    });
    return { ok: false, error, townCount: 0, written: 0, deleted: 0, pushed: [], warnings: [] };
  };

  // 1. Download and parse the months, French and English.
  const months = windowMonths(today);
  const from = `${months[0].year}-${pad(months[0].month)}-01`;
  const last = months[months.length - 1];
  const to = addDays(`${last.year + (last.month === 12 ? 1 : 0)}-${pad((last.month % 12) + 1)}-01`, -1);
  const fr: CalendarEntry[] = [];
  const en: CalendarEntry[] = [];
  try {
    for (const { year, month } of months) {
      fr.push(...parseMonth(decodePage(await fetcher.get(monthUrl("fr", year, month))), year, month));
      en.push(...parseMonth(decodePage(await fetcher.get(monthUrl("en", year, month))), year, month));
    }
  } catch (e) {
    return fail(`download: ${(e as Error).message}`);
  }
  const { pickups: town, warnings: checkWarnings } = buildPickups(fr, en);

  // 2. Silence must never look like safety: nothing at all, or a month that
  //    suddenly has far fewer pickups than last time, means the page broke.
  const counts: Record<string, number> = {};
  for (const { year, month } of months) counts[`${year}-${pad(month)}`] = 0;
  for (const p of town) if (p.material) counts[p.date.slice(0, 7)] = (counts[p.date.slice(0, 7)] ?? 0) + 1;
  const townCount = Object.values(counts).reduce((a, b) => a + b, 0);
  if (townCount === 0) return fail("parsed no pickups in the months fetched");
  for (const [m, n] of Object.entries(counts)) {
    const before = health?.month_counts?.[m] ?? 0;
    if (before >= 4 && n < before / 2) return fail(`parsed ${n} pickups for ${m}, expected about ${before}`);
  }

  // 3. Merge with the MRC calendar (D4, D11).
  const stored = await store.loadPickups(addDays(from, -7));
  const townSeenWeeks = new Set(stored.filter((d) => d.origin === "town").map((d) => weekKey(d.sector, d.date)));
  const mrcCovers = mrcThrough(deps.mrc);
  const { pickups: merged, warnings: mergeWarnings } =
    mergeSchedules(town, mrcPickups(deps.mrc, from, to), townSeenWeeks, mrcCovers);
  const warnings = [...checkWarnings, ...mergeWarnings];
  warnings.forEach((w) => log(`calendar: warning — ${w}`));

  // 4. Compare with what we stored (D3). Only today and later can change:
  //    the past is left alone.
  const prevById = new Map(stored.map((d) => [d.id, d]));
  const current = new Map(merged.map((p) => [p.id, p]));
  const docs = new Map<string, StoredPickup>();
  const appeared: StoredPickup[] = [];
  const toDelete: string[] = [];

  for (const p of merged) {
    const prev = prevById.get(p.id);
    const doc = toDoc(p, prev, startedAt);
    docs.set(doc.id, doc);
    if (p.origin !== "town" || p.date < today) continue;
    if (!prev || prev.status === "cancelled") appeared.push(doc);
  }

  const disappeared: StoredPickup[] = [];
  for (const prev of stored) {
    if (current.has(prev.id) || prev.date < today || prev.date > to) continue;
    if (prev.origin === "mrc") toDelete.push(prev.id); // the Town took this week over
    else if (prev.status === "scheduled") disappeared.push(prev);
  }

  const changed: StoredPickup[] = [];
  const mark = (doc: StoredPickup, change: CollectionChange, previousDate: string | null) => {
    doc.change = change;
    doc.change_at = startedAt;
    doc.previous_date = previousDate;
    doc.updated_at = startedAt;
    doc.pushed_at = null; // a new change deserves its own notice
    doc.push_skipped = null;
    changed.push(doc);
  };

  // Moved: the same bin for the same sector reappears within a week.
  for (const old of disappeared.sort((a, b) => a.date.localeCompare(b.date))) {
    const what = old.material ?? old.special;
    const match = appeared
      .filter((a) => a.sector === old.sector && (a.material ?? a.special) === what &&
        Math.abs(daysBetween(old.date, a.date)) <= MOVE_WINDOW_DAYS && !changed.includes(a))
      .sort((a, b) => Math.abs(daysBetween(old.date, a.date)) - Math.abs(daysBetween(old.date, b.date)))[0];
    if (match) {
      mark(match, "moved", old.date);
      toDelete.push(old.id);
    } else {
      const doc: StoredPickup = { ...old, status: "cancelled" };
      mark(doc, "cancelled", null);
      docs.set(doc.id, doc);
    }
  }
  // Added: a new Town pickup in a sector-week the Town had already posted.
  // (A week posted for the first time is just the Town publishing.)
  for (const doc of appeared) {
    if (changed.includes(doc)) continue;
    if (!firstRun && townSeenWeeks.has(weekKey(doc.sector, doc.date))) mark(doc, "added", null);
  }

  // 5. Decide which changes push (D3, D9): Town bin pickups, today to 14
  //    days ahead, never on the first run. The rest record why not. A change
  //    from an earlier run that is still owed a notice (its push failed) is
  //    tried again, like the alerts poll does.
  const owed = [
    ...docs.values(),
    ...stored.filter((d) => d.status === "cancelled" && !current.has(d.id)),
  ].filter((d) => d.change && !d.pushed_at && !d.push_skipped && !changed.includes(d) && !toDelete.includes(d.id));
  const lastPushDay = addDays(today, PUSH_WINDOW_DAYS);
  const toSend: StoredPickup[] = [];
  const decided: StoredPickup[] = [];
  for (const doc of [...changed, ...owed]) {
    if (firstRun) doc.push_skipped = "first-run";
    else if (!doc.material) doc.push_skipped = "special-collection";
    else if (doc.date < today) doc.push_skipped = "past";
    else if (doc.date > lastPushDay) doc.push_skipped = "too-far-ahead";
    else toSend.push(doc);
    if (doc.push_skipped) decided.push(doc);
  }

  // 6. Save what's new or different; delete what moved away or was replaced.
  const toSave = [...docs.values()].filter((d) => {
    const prev = prevById.get(d.id);
    return !prev || changed.includes(d) || decided.includes(d) || contentChanged(prev, d);
  });
  // Owed cancelled pickups that were skipped this time live only in `stored`.
  for (const d of decided) if (!toSave.includes(d) && !docs.has(d.id)) toSave.push(d);
  for (const d of toSave) {
    const prev = prevById.get(d.id);
    if (prev && !changed.includes(d) && contentChanged(prev, d)) d.updated_at = startedAt;
  }
  if (toSave.length) await store.savePickups(toSave);
  if (toDelete.length) await store.deletePickups(toDelete);

  // 7. Send: one notice per sector, change and date (two bins moved together
  //    make one notice). The claim stops overlapping runs pushing twice.
  const pushed: string[] = [];
  const groups = new Map<string, StoredPickup[]>();
  for (const d of toSend) {
    const k = `${d.sector}|${d.change}|${d.date}|${d.previous_date ?? ""}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k)!.push(d);
  }
  for (const group of groups.values()) {
    const claimed: StoredPickup[] = [];
    for (const d of group) if (await store.claimPush(d.id, startedAt)) claimed.push(d);
    if (!claimed.length) continue;
    const first = claimed[0];
    const materials = claimed.map((d) => d.material as BinMaterial);
    try {
      for (const lang of ["fr", "en"] as const) {
        const text = collectionChangeText(first.change!, materials, first.date, first.previous_date, lang);
        await messenger.send({
          topic: topicFor(first.sector, lang),
          title: text.title,
          body: text.body,
          urgent: false,
          channel: COLLECTION_CHANNEL,
          data: { type: "collection", pickup_id: first.id, sector: first.sector },
        });
      }
      const line = `${first.change} ${first.sector} ${first.date}`;
      pushed.push(line);
      log(`calendar: pushed ${line}`);
    } catch (e) {
      log(`calendar: push for ${first.id} failed: ${(e as Error).message}`);
      for (const d of claimed) await store.releasePush(d.id);
    }
  }

  // 8. Source health.
  const binDates = (ps: MergedPickup[]) => ps.filter((p) => p.material).map((p) => p.date).sort();
  await store.saveHealth({
    last_attempt_at: startedAt,
    last_success_at: startedAt,
    last_item_count: townCount,
    last_error: "",
    month_counts: counts,
    posted_through: binDates(merged.filter((p) => p.origin === "town")).at(-1) ?? null,
    known_through: binDates(merged).at(-1) ?? null,
    mrc_through: mrcCovers,
    warnings: warnings.slice(0, 20),
  });
  log(`calendar: ok — ${townCount} Town pickups, ${merged.length} after merge, ${toSave.length} saved, ${toDelete.length} deleted, ${pushed.length} notices${firstRun ? " (first run: no notices)" : ""}`);
  return { ok: true, townCount, written: toSave.length, deleted: toDelete.length, pushed, warnings };
}

function emptyHealth(): CalendarHealth {
  return {
    last_attempt_at: new Date(0), last_success_at: null, last_item_count: 0, last_error: "",
    month_counts: {}, posted_through: null, known_through: null, mrc_through: null, warnings: [],
  };
}

/** A merged pickup as a stored document, keeping what we knew before. */
function toDoc(p: MergedPickup, prev: StoredPickup | undefined, at: Date): StoredPickup {
  const reappeared = prev?.status === "cancelled";
  return {
    id: p.id,
    origin: p.origin,
    event_id: p.eventId,
    source: SOURCE_ID,
    type: "collection",
    date: p.date,
    sector: p.sector,
    material: p.material,
    special: p.special,
    title_fr: p.titleFr,
    title_en: p.titleEn,
    source_url_fr: p.urlFr,
    source_url_en: p.urlEn,
    irregular: p.irregular,
    status: "scheduled",
    previous_date: reappeared ? null : prev?.previous_date ?? null,
    change: reappeared ? null : prev?.change ?? null,
    change_at: reappeared ? null : prev?.change_at ?? null,
    first_seen_at: prev?.first_seen_at ?? at,
    updated_at: prev?.updated_at ?? at,
    pushed_at: prev?.pushed_at ?? null,
    push_skipped: prev?.push_skipped ?? null,
  };
}

const COMPARED: (keyof StoredPickup)[] = [
  "origin", "event_id", "material", "special", "title_fr", "title_en",
  "source_url_fr", "source_url_en", "irregular", "status", "previous_date", "change",
];

function contentChanged(a: StoredPickup, b: StoredPickup): boolean {
  return COMPARED.some((k) => a[k] !== b[k]);
}
