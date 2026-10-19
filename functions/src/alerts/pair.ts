// Joins the French and English list pages into one bilingual alert each.
import {
  Category, WATER_CATEGORIES, categoryFromIcon, hasLiftedPrefix,
  isLiftingNotice, stripLiftedPrefix,
} from "./classify";
import { ListItem } from "./parse";

export type Status = "active" | "lifted" | "expired";
export type Kind = "advisory" | "lifting-notice";

/** One alert, both languages, before full texts are fetched. */
export interface Alert {
  id: string;
  /** Key used to recognise an alert once it's archived and loses its id. */
  matchKey: string;
  kind: Kind;
  category: Category;
  categoryKnown: boolean;
  icon: string | null;
  status: Status;
  severity: "urgent" | "info";
  titleFr: string;
  titleEn: string;
  /** List-page excerpts; replaced by full text from the detail pages. */
  excerptFr: string;
  excerptEn: string;
  sourceUrlFr: string;
  sourceUrlEn: string;
  publishedAt: Date;
}

/** "2026-10-12T18:32" — minute precision is what the site shows. */
const minuteKey = (d: Date) => d.toISOString().slice(0, 16);

/** The path after /alertes/ or /alerts/, e.g. "2026/10/12/avis-d-ebullition-preventif". */
function pathOf(url: string): string {
  return url.replace(/^.*?\/(alertes|alerts)\//, "");
}

export function matchKeyFor(frUrl: string, publishedAt: Date): string {
  return `${pathOf(frUrl)}@${minuteKey(publishedAt)}`;
}

export function pairItems(fr: ListItem[], en: ListItem[]): Alert[] {
  const enById = new Map(en.filter((i) => i.platformId).map((i) => [i.platformId!, i]));
  // Archived items have no id: pair them by publish minute instead.
  const enArchivedByMinute = new Map<string, ListItem[]>();
  for (const i of en.filter((i) => i.archived)) {
    const k = minuteKey(i.publishedAt);
    enArchivedByMinute.set(k, [...(enArchivedByMinute.get(k) ?? []), i]);
  }

  const alerts: Alert[] = [];
  for (const f of fr) {
    let e: ListItem | undefined;
    if (f.platformId) {
      e = enById.get(f.platformId);
    } else {
      e = enArchivedByMinute.get(minuteKey(f.publishedAt))?.shift();
    }
    alerts.push(build(f, e));
  }
  // English-only alerts (no French version) are kept too.
  const usedEnIds = new Set(fr.map((f) => f.platformId).filter(Boolean));
  for (const e of en) {
    if (e.platformId && !usedEnIds.has(e.platformId)) alerts.push(build(undefined, e));
  }
  return alerts;
}

function build(fr: ListItem | undefined, en: ListItem | undefined): Alert {
  const base = (fr ?? en)!;
  const { category, known } = categoryFromIcon(base.icon);
  const titles = [fr?.title, en?.title].filter((t): t is string => !!t);
  const kind: Kind = titles.some(isLiftingNotice) ? "lifting-notice" : "advisory";
  const status: Status = base.archived
    ? "expired"
    : titles.some(hasLiftedPrefix) ? "lifted" : "active";
  const matchKey = matchKeyFor(fr?.url ?? en!.url, base.publishedAt);
  return {
    id: base.platformId ?? `a-${matchKey.replace(/[\/@:]/g, "-")}`,
    matchKey,
    kind,
    category,
    categoryKnown: known,
    icon: base.icon,
    status,
    // Urgent = a water advisory. A notice that one is over is good news, not urgent.
    severity: kind === "advisory" && WATER_CATEGORIES.has(category) ? "urgent" : "info",
    titleFr: fr ? stripLiftedPrefix(fr.title) : "",
    titleEn: en ? stripLiftedPrefix(en.title) : "",
    excerptFr: fr?.excerpt ?? "",
    excerptEn: en?.excerpt ?? "",
    sourceUrlFr: fr?.url ?? "",
    sourceUrlEn: en?.url ?? "",
    publishedAt: base.publishedAt,
  };
}
