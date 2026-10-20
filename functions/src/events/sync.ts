// The events step of the calendar run (spec events-calendar §6). It gets the
// pages the bin-pickup step already downloaded, so the Town's server sees no
// extra requests (spec D1). Database access comes in as a small interface,
// so tests run whole steps with a fake.
import { CalendarDownload, torontoDate } from "../collection/sync";
import { buildEvents, EventCategory, TownEvent } from "./build";

export const EVENTS_SOURCE_ID = "town-events";

/** Firestore `events/{id}` (spec §5). */
export interface StoredEvent {
  id: string;
  source: "town-calendar";
  type: "event";
  category: EventCategory;
  title_fr: string;
  title_en: string;
  original_language: TownEvent["originalLanguage"];
  place_fr: string;
  place_en: string;
  starts_on: string;
  ends_on: string;
  source_url_fr: string;
  source_url_en: string;
  first_seen_at: Date;
  updated_at: Date;
}

/** Firestore `sources/town-events` (DESIGN §4 source health). */
export interface EventsHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  /** Events found in the months fetched (past ones included). */
  last_item_count: number;
  last_error: string;
  /** Last day of the last month fetched: the app's "not posted yet" line (spec D8). */
  listed_through: string | null;
  warnings: string[];
}

export interface EventsStore {
  loadEvents(): Promise<StoredEvent[]>;
  saveEvents(docs: StoredEvent[]): Promise<void>;
  deleteEvents(ids: string[]): Promise<void>;
  loadHealth(): Promise<EventsHealth | null>;
  saveHealth(h: EventsHealth): Promise<void>;
}

export interface EventsDeps {
  store: EventsStore;
  now: () => Date;
  log?: (message: string) => void;
}

export interface EventsRunResult {
  ok: boolean;
  error?: string;
  /** Events in the pages, past ones included. */
  found: number;
  /** Events ending today or later: what's stored after the run. */
  upcoming: number;
  written: number;
  deleted: number;
  warnings: string[];
}

/**
 * One events step. `download` is the calendar run's pages, or the reason
 * they couldn't be downloaded (recorded as this source's failure too).
 */
export async function runEventsPoll(
  deps: EventsDeps,
  download: CalendarDownload | { error: string },
): Promise<EventsRunResult> {
  const { store, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  const today = torontoDate(startedAt);
  const health = await store.loadHealth();

  const fail = async (error: string): Promise<EventsRunResult> => {
    log(`events: FAILED — ${error}`);
    await store.saveHealth({
      last_attempt_at: startedAt,
      last_success_at: health?.last_success_at ?? null,
      last_item_count: health?.last_item_count ?? 0,
      last_error: error.slice(0, 300),
      listed_through: health?.listed_through ?? null,
      warnings: health?.warnings ?? [],
    });
    return { ok: false, error, found: 0, upcoming: 0, written: 0, deleted: 0, warnings: [] };
  };

  if ("error" in download) return fail(download.error);

  const { events, warnings } = buildEvents(download.fr, download.en);
  warnings.forEach((w) => log(`events: warning — ${w}`));
  // Three months without a single event means the page layout changed, not
  // that the town went quiet (spec D9). One empty month is normal.
  if (events.length === 0) return fail("parsed no events in the months fetched");

  // Keep what hasn't ended; drop past events and ones the Town removed (D7).
  const upcoming = events.filter((e) => e.endsOn >= today);
  const stored = await store.loadEvents();
  const prevById = new Map(stored.map((d) => [d.id, d]));
  const keep = new Set(upcoming.map((e) => e.id));

  const toSave: StoredEvent[] = [];
  for (const e of upcoming) {
    const prev = prevById.get(e.id);
    const doc = toDoc(e, prev, startedAt);
    if (!prev || contentChanged(prev, doc)) toSave.push(doc);
  }
  const toDelete = stored.filter((d) => !keep.has(d.id)).map((d) => d.id);

  if (toSave.length) await store.saveEvents(toSave);
  if (toDelete.length) await store.deleteEvents(toDelete);

  await store.saveHealth({
    last_attempt_at: startedAt,
    last_success_at: startedAt,
    last_item_count: events.length,
    last_error: "",
    listed_through: download.to,
    warnings: warnings.slice(0, 20),
  });
  log(`events: ok — ${events.length} found, ${upcoming.length} upcoming, ${toSave.length} saved, ${toDelete.length} deleted`);
  return {
    ok: true, found: events.length, upcoming: upcoming.length,
    written: toSave.length, deleted: toDelete.length, warnings,
  };
}

function toDoc(e: TownEvent, prev: StoredEvent | undefined, at: Date): StoredEvent {
  const doc: StoredEvent = {
    id: e.id,
    source: "town-calendar",
    type: "event",
    category: e.category,
    title_fr: e.titleFr,
    title_en: e.titleEn,
    original_language: e.originalLanguage,
    place_fr: e.placeFr,
    place_en: e.placeEn,
    starts_on: e.startsOn,
    ends_on: e.endsOn,
    source_url_fr: e.urlFr,
    source_url_en: e.urlEn,
    first_seen_at: prev?.first_seen_at ?? at,
    updated_at: prev?.updated_at ?? at,
  };
  if (prev && contentChanged(prev, doc)) doc.updated_at = at;
  return doc;
}

const COMPARED: (keyof StoredEvent)[] = [
  "category", "title_fr", "title_en", "original_language", "place_fr", "place_en",
  "starts_on", "ends_on", "source_url_fr", "source_url_en",
];

function contentChanged(a: StoredEvent, b: StoredEvent): boolean {
  return COMPARED.some((k) => a[k] !== b[k]);
}
