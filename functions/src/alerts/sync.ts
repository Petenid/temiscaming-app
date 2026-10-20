// One polling run: download both list pages, work out what changed, save
// it, record source health, and send pushes for new water alerts.
//
// Network, database and push are passed in as small interfaces ("ports"),
// so the tests can swap in fakes and run the whole thing against fixtures.
import { WATER_CATEGORIES, mentionsWater } from "./classify";
import { EffectRule, effectOf } from "./effect";
import { Alert, Kind, Status, pairItems } from "./pair";
import { decodePage, parseDetail, parseList } from "./parse";
import { Lang, TemplateKey, pushText } from "../push/templates";

export const SOURCE_ID = "alertes-municipales";
export const BASE_URL = "https://temiscaming.alertesmunicipales.com";
export const LIST_URLS: Record<Lang, string> = {
  fr: `${BASE_URL}/alertes`,
  en: `${BASE_URL}/alerts`,
};
export const TOPICS: Record<Lang, string> = { fr: "water-fr", en: "water-en" };

/** At most this many detail pages per run (being gentle with the Town's server). */
export const MAX_DETAIL_FETCHES = 10;
/** Never push about something published longer ago than this. */
export const PUSH_MAX_AGE_MS = 24 * 3600_000;
/** A second alert with the same push template within this window is treated as a re-post. */
export const PUSH_COOLDOWN_MS = 6 * 3600_000;

/** An alert as stored in Firestore `alerts/{id}` (spec §5). */
export interface StoredAlert {
  id: string;
  source: string;
  type: "town-alert";
  match_key: string;
  kind: Kind;
  category: string;
  status: Status;
  severity: "urgent" | "info";
  title_fr: string;
  title_en: string;
  body_fr: string;
  body_en: string;
  /** True when the body is only the list excerpt (full text not fetched, or not available). */
  body_is_excerpt: boolean;
  /** Internal: the detail pages were read successfully (no need to fetch again). */
  detail_fetched: boolean;
  original_language: "fr" | "en" | "both";
  source_url_fr: string;
  source_url_en: string;
  published_at: Date;
  updated_at: Date;
  pushed_at?: Date | null;
  push_skipped?: string | null;
  /** Which "in effect" rule applies (spec §5b): lifted-only, dated or undated. */
  in_effect_rule: EffectRule;
  /** If the Town never marks it lifted, it stops being "in effect" at this moment. */
  in_effect_until: Date;
  /** A manual correction copied from `overrides/{id}` (spec §5c); wins over everything. */
  override: Override | null;
}

/** A manual correction: "over" (not in effect) or "in-effect" (still in effect). */
export type Override = "over" | "in-effect";

/** Firestore `sources/alertes-municipales` (DESIGN §4 source health). */
export interface SourceHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  last_item_count: number;
  last_error: string;
  /** When each push template last went out, for the re-post cooldown. */
  last_push_at: Partial<Record<TemplateKey, Date>>;
}

export interface Store {
  loadAlerts(): Promise<StoredAlert[]>;
  saveAlerts(docs: StoredAlert[]): Promise<void>;
  /** Atomically sets pushed_at if not already set; false if someone else already did. */
  claimPush(id: string, at: Date): Promise<boolean>;
  releasePush(id: string): Promise<void>;
  loadHealth(): Promise<SourceHealth | null>;
  saveHealth(h: SourceHealth): Promise<void>;
  /** Firestore `overrides`, as written by hand in the Firebase console: id → document. */
  loadOverrides(): Promise<Map<string, Record<string, unknown>>>;
}

export interface Fetcher {
  /** Returns the page bytes, or throws on network/HTTP errors. */
  get(url: string): Promise<Uint8Array>;
}

export interface PushMessage {
  topic: string;
  title: string;
  body: string;
  /** The alert to open on tap (water alerts). */
  alertId?: string;
  urgent: boolean;
  /** Android channel; defaults to the water channels (urgent / updates). */
  channel?: string;
  /** Data the app reads on tap; defaults to { alert_id }. */
  data?: Record<string, string>;
}

export interface Messenger {
  send(message: PushMessage): Promise<void>;
}

export interface Deps {
  store: Store;
  fetcher: Fetcher;
  messenger: Messenger;
  now: () => Date;
  log?: (message: string) => void;
}

export interface RunResult {
  ok: boolean;
  error?: string;
  itemCount: number;
  written: number;
  pushed: string[];
}

export async function runPoll(deps: Deps): Promise<RunResult> {
  const { store, fetcher, messenger, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  const health = await store.loadHealth();

  const fail = async (error: string): Promise<RunResult> => {
    log(`town alerts: FAILED — ${error}`);
    await store.saveHealth({
      last_attempt_at: startedAt,
      last_success_at: health?.last_success_at ?? null,
      last_item_count: health?.last_item_count ?? 0,
      last_error: error.slice(0, 300),
      last_push_at: health?.last_push_at ?? {},
    });
    return { ok: false, error, itemCount: 0, written: 0, pushed: [] };
  };

  // 1. Download and parse both list pages.
  let alerts: Alert[];
  try {
    const [frHtml, enHtml] = await Promise.all([
      fetcher.get(LIST_URLS.fr).then(decodePage),
      fetcher.get(LIST_URLS.en).then(decodePage),
    ]);
    alerts = pairItems(parseList(frHtml), parseList(enHtml));
  } catch (e) {
    return fail(`download: ${(e as Error).message}`);
  }

  // 2. Silence must never look like safety: an empty or shrunken list means
  //    the page changed or broke, not that alerts disappeared.
  const expected = health?.last_item_count ?? 0;
  if (alerts.length === 0 || alerts.length < expected / 2) {
    return fail(`parsed ${alerts.length} alerts, expected about ${expected}`);
  }
  for (const a of alerts) {
    if (!a.categoryKnown) log(`town alerts: unknown category icon "${a.icon}" on ${a.id}`);
  }

  // 3. Match with what we already have.
  const existing = await store.loadAlerts();
  const firstRun = existing.length === 0;
  const byId = new Map(existing.map((d) => [d.id, d]));
  const byMatchKey = new Map(existing.map((d) => [d.match_key, d]));
  const matched = alerts.map((alert) => {
    const prev = byId.get(alert.id) ?? byMatchKey.get(alert.matchKey);
    // An alert that moved to the archive keeps the id it had.
    if (prev) alert.id = prev.id;
    return { alert, prev };
  });

  // 4. Full texts, for new or retitled alerts (and leftovers from earlier runs), newest first.
  const wantsDetail = matched
    .filter(({ alert, prev }) =>
      !prev || !prev.detail_fetched ||
      prev.title_fr !== alert.titleFr || prev.title_en !== alert.titleEn)
    .sort((a, b) => b.alert.publishedAt.getTime() - a.alert.publishedAt.getTime());
  const bodies = new Map<string, { fr?: string; en?: string; complete: boolean }>();
  let fetches = 0;
  for (const { alert } of wantsDetail) {
    if (fetches >= MAX_DETAIL_FETCHES) break;
    const got: { fr?: string; en?: string; complete: boolean } = { complete: true };
    for (const lang of ["fr", "en"] as const) {
      const url = lang === "fr" ? alert.sourceUrlFr : alert.sourceUrlEn;
      if (!url) continue;
      fetches++;
      try {
        const detail = parseDetail(decodePage(await fetcher.get(url)));
        // Two alerts can share a URL; only use the page if it's this one.
        const same = detail.publishedAt?.getTime() === alert.publishedAt.getTime();
        if (same && detail.body) got[lang] = detail.body;
        // A shared URL showing the other alert: the excerpt is the best we can do.
      } catch (e) {
        log(`town alerts: detail ${url}: ${(e as Error).message}`);
        got.complete = false; // try again next run
      }
    }
    bodies.set(alert.id, got);
  }

  // 5. Manual corrections (spec §5c). A typo shouldn't stop the poll, so bad
  //    entries are logged and ignored.
  const overrides = new Map<string, Override>();
  try {
    const known = new Set(matched.map(({ alert }) => alert.id));
    for (const [id, data] of await store.loadOverrides()) {
      const status = typeof data.status === "string" ? data.status.trim().toLowerCase() : "";
      if (status !== "over" && status !== "in-effect") {
        log(`town alerts: override ${id} ignored — status must be "over" or "in-effect", got ${JSON.stringify(data.status)}`);
      } else if (!known.has(id)) {
        log(`town alerts: override ${id} ignored — no alert with that id`);
      } else {
        overrides.set(id, status);
      }
    }
  } catch (e) {
    // Keep the overrides already saved on each alert rather than drop them.
    log(`town alerts: could not read overrides: ${(e as Error).message}`);
    for (const d of existing) if (d.override) overrides.set(d.id, d.override);
  }

  // 6. Build the stored documents and save the ones that changed.
  const toSave: StoredAlert[] = [];
  const all: StoredAlert[] = [];
  for (const { alert, prev } of matched) {
    const fetched = bodies.get(alert.id);
    const bodyFr = fetched?.fr ?? (fetched || !prev ? alert.excerptFr : prev.body_fr);
    const bodyEn = fetched?.en ?? (fetched || !prev ? alert.excerptEn : prev.body_en);
    // Full text missing for a language that exists (e.g. a shared URL showing
    // the other alert) → we keep the excerpt and say so in the app.
    const isExcerpt = fetched
      ? (!!alert.sourceUrlFr && !fetched.fr) || (!!alert.sourceUrlEn && !fetched.en)
      : prev?.body_is_excerpt ?? true;
    const doc: StoredAlert = {
      id: alert.id,
      source: SOURCE_ID,
      type: "town-alert",
      match_key: alert.matchKey,
      kind: alert.kind,
      category: alert.category,
      status: alert.status,
      severity: alert.severity,
      title_fr: alert.titleFr,
      title_en: alert.titleEn,
      body_fr: bodyFr,
      body_en: bodyEn,
      body_is_excerpt: isExcerpt,
      detail_fetched: fetched ? fetched.complete : prev?.detail_fetched ?? false,
      original_language: alert.titleFr && alert.titleEn ? "both" : alert.titleFr ? "fr" : "en",
      source_url_fr: alert.sourceUrlFr,
      source_url_en: alert.sourceUrlEn,
      published_at: alert.publishedAt,
      updated_at: prev?.updated_at ?? startedAt,
      pushed_at: prev?.pushed_at ?? null,
      push_skipped: prev?.push_skipped ?? null,
      in_effect_rule: "undated",
      in_effect_until: alert.publishedAt,
      override: overrides.get(alert.id) ?? null,
    };
    const effect = effectOf(doc);
    doc.in_effect_rule = effect.rule;
    doc.in_effect_until = effect.until;
    all.push(doc);
    if (!prev) {
      toSave.push(doc);
    } else if (contentChanged(prev, doc)) {
      doc.updated_at = startedAt;
      toSave.push(doc);
    }
  }

  // 7. Decide pushes. Every alert ends up either sent (pushed_at) or with a
  //    reason it wasn't (push_skipped). One with neither is still owed a push
  //    (say the last attempt failed) and is retried while it's fresh.
  const lastPushAt: Partial<Record<TemplateKey, Date>> = { ...(health?.last_push_at ?? {}) };
  const toSend: { doc: StoredAlert; key: TemplateKey; previous?: Date }[] = [];
  const skip = (doc: StoredAlert, reason: string) => {
    doc.push_skipped = reason;
    if (!toSave.includes(doc)) toSave.push(doc);
  };
  for (const doc of all.sort((a, b) => a.published_at.getTime() - b.published_at.getTime())) {
    if (doc.pushed_at || doc.push_skipped) continue;
    const key = templateFor(doc);
    if (firstRun) { skip(doc, "first-run"); continue; }
    if (!key) { skip(doc, "not-notifiable"); continue; }
    if (doc.status !== "active") { skip(doc, "not-active"); continue; }
    if (startedAt.getTime() - doc.published_at.getTime() > PUSH_MAX_AGE_MS) { skip(doc, "too-old"); continue; }
    // The Town sometimes re-posts (two lifting notices 20 minutes apart on
    // 2026-10-19). Same template within the cooldown → don't push again.
    const last = lastPushAt[key];
    if (last && startedAt.getTime() - last.getTime() < PUSH_COOLDOWN_MS) { skip(doc, "duplicate"); continue; }
    toSend.push({ doc, key, previous: last });
    lastPushAt[key] = startedAt;
  }

  if (toSave.length) await store.saveAlerts(toSave);

  // 8. Send. The claim stops two overlapping runs from pushing the same alert twice.
  const pushed: string[] = [];
  for (const { doc, key, previous } of toSend) {
    if (!(await store.claimPush(doc.id, startedAt))) continue;
    try {
      for (const lang of ["fr", "en"] as const) {
        const text = pushText(key, doc.category as never, lang);
        await messenger.send({
          topic: TOPICS[lang], title: text.title, body: text.body,
          alertId: doc.id, urgent: key !== "lifted",
        });
      }
      pushed.push(doc.id);
      log(`town alerts: pushed ${key} for ${doc.id}`);
    } catch (e) {
      // Let the next run try again rather than miss a boil-water push.
      log(`town alerts: push for ${doc.id} failed: ${(e as Error).message}`);
      await store.releasePush(doc.id);
      if (previous) lastPushAt[key] = previous; else delete lastPushAt[key];
    }
  }

  await store.saveHealth({
    last_attempt_at: startedAt,
    last_success_at: startedAt,
    last_item_count: alerts.length,
    last_error: "",
    last_push_at: lastPushAt,
  });
  log(`town alerts: ok — ${alerts.length} alerts, ${toSave.length} saved, ${fetches} detail pages, ${pushed.length} pushed${firstRun ? " (first run: no pushes)" : ""}`);
  return { ok: true, itemCount: alerts.length, written: toSave.length, pushed };
}

/** Which push an alert gets, or null for none (spec §3 D4). */
export function templateFor(doc: Pick<StoredAlert, "kind" | "category" | "title_fr" | "title_en">): TemplateKey | null {
  const water = WATER_CATEGORIES.has(doc.category as never);
  if (doc.kind === "lifting-notice") {
    return water || mentionsWater(doc.title_fr) || mentionsWater(doc.title_en) ? "lifted" : null;
  }
  if (doc.category === "boil-water") return "boil-water";
  return water ? "water-notice" : null;
}

const COMPARED: (keyof StoredAlert)[] = [
  "kind", "category", "status", "severity", "title_fr", "title_en", "body_fr", "body_en",
  "body_is_excerpt", "detail_fetched", "original_language", "source_url_fr", "source_url_en", "match_key",
  "in_effect_rule", "override",
];

function contentChanged(a: StoredAlert, b: StoredAlert): boolean {
  // Missing on documents saved before spec §5b/§5c: undefined ≠ value, so
  // the first poll after deploying fills them in.
  return COMPARED.some((k) => (a[k] ?? null) !== (b[k] ?? null)) ||
    a.published_at.getTime() !== b.published_at.getTime() ||
    a.in_effect_until?.getTime() !== b.in_effect_until.getTime();
}
