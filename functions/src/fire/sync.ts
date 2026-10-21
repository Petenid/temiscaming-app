// The fire-ban run, every 30 minutes (spec fire-bans D4, D5, §6):
// for each layer (IFCO, then ICAF) — download, parse, work out the state for
// Témiscaming, save it, and push when that state changes for the town.
//
// How "changes" is decided: each layer remembers the last thing we TOLD people
// (`pushed.kind`: announced / started / lifted). A push goes out when what's
// true now disagrees with that:
//   - a ban applies here, and the last word was "lifted" (or nothing) → push it
//     ("announced" if it starts later, "started" if already in effect);
//   - no ban applies here, and the last word was "announced"/"started" → "lifted".
// So: a boundary change that leaves the town's state alone sends nothing; an
// announced ban starting sends nothing more; and if a push fails it's simply
// tried again next run — but only if it's still true then.
//
// The very first run records the current state without pushing, so deploying
// never sends a surprise notification.
import { Fetcher, Messenger } from "../alerts/sync";
import { FirePushKind, firePushText, Lang } from "../push/templates";
import { LAYER_URL, LayerId, parseLayer } from "./parse";
import { isHere, LayerState, layerStatus, LayerStatus } from "./status";

export const FIRE_TOPICS: Record<Lang, string> = { fr: "fire-fr", en: "fire-en" };
export const FIRE_SOURCE_ID: Record<LayerId, string> = { ifco: "msi-ifco", icaf: "msi-icaf" };

/** Links the app shows (spec D9). The Québec.ca page exists in French only. */
export const FIRE_LINKS = {
  official_url_fr:
    "https://www.quebec.ca/agriculture-environnement-et-ressources-naturelles/forets/protection-forets/gestion-feux/mesures-prevention",
  map_url: "https://www.carte-igo.donneesquebec.ca/igo2/apercu-qc/?pos=@-79.1,46.9,8&ctx=msp_feu_mesure_preventive",
  sopfeu_url_fr: "https://www.sopfeu.qc.ca/situation-actuelle/abitibi-temiscamingue/",
  sopfeu_url_en: "https://www.sopfeu.qc.ca/en/current-situation/abitibi-temiscamingue/",
} as const;

export interface PushedRecord {
  kind: FirePushKind;
  at: Date;
  /** True when the first run recorded the state without sending anything. */
  baseline: boolean;
}

/** One layer's fields in Firestore `fire/temiscaming` (spec §5). */
export interface StoredLayer extends LayerStatus {
  checked_at: Date;
  pushed: PushedRecord;
}

export interface FireHealth {
  last_attempt_at: Date;
  last_success_at: Date | null;
  last_item_count: number;
  last_error: string;
  warnings: string[];
}

export interface FireStore {
  /** The stored layers; a layer never read before is missing. */
  loadFire(): Promise<Partial<Record<LayerId, StoredLayer>>>;
  /** Replaces this layer's field (and refreshes the links); the other layer is untouched. */
  saveLayer(layer: LayerId, fields: StoredLayer): Promise<void>;
  loadHealth(layer: LayerId): Promise<FireHealth | null>;
  saveHealth(layer: LayerId, h: FireHealth): Promise<void>;
}

export interface FireDeps {
  store: FireStore;
  fetcher: Fetcher;
  messenger: Messenger;
  now: () => Date;
  log?: (message: string) => void;
}

export interface LayerResult {
  ok: boolean;
  error?: string;
  state?: LayerState;
  pushed?: FirePushKind;
}

/** What should people have been told, given the state now? */
function wantedKind(layer: LayerId, status: LayerStatus, now: Date): FirePushKind {
  if (!isHere(layer, status.state)) return "lifted";
  return status.starts_at && status.starts_at > now ? "announced" : "started";
}

/** Should we push `wanted`, given the last thing pushed? (see top of file) */
function needsPush(last: FirePushKind, wanted: FirePushKind): boolean {
  if (wanted === "lifted") return last !== "lifted";
  return last === "lifted";
}

async function sendBoth(deps: FireDeps, layer: LayerId, kind: FirePushKind, startsAt: Date | null): Promise<number> {
  let sent = 0;
  for (const lang of ["fr", "en"] as Lang[]) {
    const text = firePushText(layer, kind, startsAt, lang);
    try {
      await deps.messenger.send({
        topic: FIRE_TOPICS[lang],
        ...text,
        urgent: kind !== "lifted",
        channel: kind === "lifted" ? "fire_updates" : "fire_urgent",
        data: { screen: "fire", layer },
      });
      sent++;
    } catch (e) {
      deps.log?.(`fire ${layer}: push to ${FIRE_TOPICS[lang]} FAILED — ${(e as Error).message}`);
    }
  }
  return sent;
}

async function runLayer(deps: FireDeps, layer: LayerId, stored: StoredLayer | undefined): Promise<LayerResult> {
  const { store, now } = deps;
  const log = deps.log ?? (() => {});
  const startedAt = now();
  let health: FireHealth | null = null;

  // 1. Read the source. Any problem here leaves the stored state untouched (spec D3).
  let status: LayerStatus;
  let featureCount: number;
  let warnings: string[];
  try {
    health = await store.loadHealth(layer);
    const bytes = await deps.fetcher.get(LAYER_URL[layer]);
    let json: unknown;
    try {
      json = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw new Error(`${layer}: not JSON`);
    }
    const parsed = parseLayer(layer, json);
    status = layerStatus(layer, parsed);
    featureCount = parsed.featureCount;
    warnings = parsed.warnings;
  } catch (e) {
    const error = (e as Error).message ?? String(e);
    log(`fire ${layer}: FAILED — ${error}`);
    try {
      await store.saveHealth(layer, {
        last_attempt_at: startedAt,
        last_success_at: health?.last_success_at ?? null,
        last_item_count: health?.last_item_count ?? 0,
        last_error: error.slice(0, 300),
        warnings: health?.warnings ?? [],
      });
    } catch (e2) {
      log(`fire ${layer}: could not record the failure — ${(e2 as Error).message}`);
    }
    return { ok: false, error };
  }

  // 2. Push if what's true now differs from what we last told people.
  const wanted = wantedKind(layer, status, startedAt);
  let pushed: PushedRecord;
  let sentKind: FirePushKind | undefined;
  if (!stored) {
    pushed = { kind: wanted, at: startedAt, baseline: true };
    log(`fire ${layer}: first run, recording "${wanted}" without pushing`);
  } else if (needsPush(stored.pushed.kind, wanted)) {
    const sent = await sendBoth(deps, layer, wanted, status.starts_at);
    if (sent > 0) {
      // Even if one language failed: re-sending to the other every 30 min would be worse.
      pushed = { kind: wanted, at: startedAt, baseline: false };
      sentKind = wanted;
    } else {
      pushed = stored.pushed; // nothing went out: try again next run, if still true
    }
  } else {
    pushed = stored.pushed;
  }

  // 3. Save state and health.
  try {
    await store.saveLayer(layer, { ...status, checked_at: startedAt, pushed });
    await store.saveHealth(layer, {
      last_attempt_at: startedAt,
      last_success_at: startedAt,
      last_item_count: featureCount,
      last_error: "",
      warnings: warnings.slice(0, 20),
    });
  } catch (e) {
    const error = (e as Error).message ?? String(e);
    log(`fire ${layer}: FAILED to save — ${error}`);
    return { ok: false, error, state: status.state, pushed: sentKind };
  }
  warnings.forEach((w) => log(`fire ${layer}: warning — ${w}`));
  const detail = status.state === "none"
    ? `none${status.none_since ? ` since ${status.none_since.toISOString()}` : ""}`
    : `${status.state} (nearest ${status.nearest_km} km${status.starts_at ? `, starts ${status.starts_at.toISOString()}` : ""})`;
  log(`fire ${layer}: ok — ${detail}${sentKind ? `; pushed "${sentKind}"` : ""}`);
  return { ok: true, state: status.state, pushed: sentKind };
}

/** Both layers, each on its own: one failing never stops the other. */
export async function runFireBanPoll(deps: FireDeps): Promise<Record<LayerId, LayerResult>> {
  let stored: Partial<Record<LayerId, StoredLayer>> = {};
  try {
    stored = await deps.store.loadFire();
  } catch (e) {
    const error = `could not load fire/temiscaming — ${(e as Error).message}`;
    deps.log?.(`fire: FAILED — ${error}`);
    // Without the previous state we can't tell what changed; skip this run.
    return { ifco: { ok: false, error }, icaf: { ok: false, error } };
  }
  const ifco = await runLayer(deps, "ifco", stored.ifco);
  const icaf = await runLayer(deps, "icaf", stored.icaf);
  return { ifco, icaf };
}
