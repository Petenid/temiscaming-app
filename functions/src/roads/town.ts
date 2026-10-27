// The Town's "Info-Travaux" / "Work Info" pages (roads spec §2, D3, D5).
// The list gives each item's ID (shared by both languages), title and
// "in effect from … to …" dates; the full text is on each item's own page.
// No network here: these take page text.
import * as cheerio from "cheerio";

import { torontoToUtc } from "../alerts/dates";
import { RoadItem } from "./model";

export const TOWN_LIST_URL = {
  fr: "https://www.temiscaming.net/fr/info-travaux",
  en: "https://www.temiscaming.net/en/work-info",
};

export interface TownListItem {
  id: string;
  url: string;
  title: string;
  /** Start of the first day (Témiscaming time). */
  starts_at: Date | null;
  /** End of the last day: midnight after it (Témiscaming time). Null if not stated. */
  ends_at: Date | null;
}

const MONTHS: Record<string, number> = {
  janvier: 1, fevrier: 2, mars: 3, avril: 4, mai: 5, juin: 6, juillet: 7, aout: 8, septembre: 9,
  octobre: 10, novembre: 11, decembre: 12,
  january: 1, february: 2, march: 3, april: 4, may: 5, june: 6, july: 7, august: 8, september: 9,
  october: 10, november: 11, december: 12,
};

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const clean = (s: string) => s.replace(/\s+/g, " ").trim();

/** Midnight after a day, Témiscaming time. */
function dayEnd(y: number, m: number, d: number): Date {
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return torontoToUtc(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate(), 0, 0);
}

/**
 * The end date in "En vigueur du jeudi 1 octobre 2026 au samedi 31 octobre 2026."
 * or "In effect from Thursday October 1, 2026 to Saturday October 31, 2026."
 */
export function parseEndDate(text: string): Date | null {
  const t = fold(clean(text));
  const fr = t.match(/\bau (?:\w+ )?(\d{1,2})(?:er)? ([a-z]+) (\d{4})/);
  if (fr && MONTHS[fr[2]]) return dayEnd(+fr[3], MONTHS[fr[2]], +fr[1]);
  const en = t.match(/\bto (?:\w+ )?([a-z]+) (\d{1,2}),? (\d{4})/);
  if (en && MONTHS[en[1]]) return dayEnd(+en[3], MONTHS[en[1]], +en[2]);
  return null;
}

/** `datetime="2026-10-01 00:00:00"` → start of that day. */
function parseStart(datetime: string | undefined): Date | null {
  const m = datetime?.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? torontoToUtc(+m[1], +m[2], +m[3], 0, 0) : null;
}

const ITEM_LINK = /\/(?:info-travaux|work-info)\/(\d+)\//;

/**
 * A list page. Throws when it isn't the Work Info list (spec D3), or when the
 * page links to items we couldn't read (the layout changed).
 */
export function parseTownList(html: string): TownListItem[] {
  const $ = cheerio.load(html);
  const heading = fold(clean($("h1.page-title").first().text()));
  if (heading !== "info-travaux" && heading !== "work info") {
    throw new Error(`town work info: unexpected page title "${heading}"`);
  }
  const items: TownListItem[] = [];
  $("article").each((_, el) => {
    const a = $(el).find("h1 a[href], h2 a[href]").first();
    const url = a.attr("href") ?? "";
    const id = url.match(ITEM_LINK)?.[1];
    if (!id) return;
    const time = $(el).find("time").first();
    items.push({
      id,
      url,
      title: clean(a.text()),
      starts_at: parseStart(time.attr("datetime")),
      ends_at: parseEndDate(time.text()),
    });
  });
  const linked = new Set(
    $("a[href]").map((_, a) => $(a).attr("href")?.match(ITEM_LINK)?.[1]).get().filter(Boolean),
  );
  const read = new Set(items.map((i) => i.id));
  const missed = [...linked].filter((id) => !read.has(id));
  if (missed.length) throw new Error(`town work info: couldn't read listed items ${missed.join(", ")}`);
  return items;
}

/** An item's own page: its full text, with paragraphs kept. */
export function parseTownDetail(html: string): { title: string; body: string } {
  const $ = cheerio.load(html);
  const h = $("h1.h2").first();
  if (!h.length) throw new Error("town work info: item page without a title");
  const col = h.parent().clone();
  col.find("h1, time, script, style, .side-widget, .share").remove();
  col.find("br").replaceWith("\n");
  col.find("div, p, li").each((_, e) => { $(e).append("\n"); });
  const body = col.text()
    .split("\n").map((l) => l.replace(/[ \t ]+/g, " ").trim()).join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return { title: clean(h.text()), body };
}

/** Both languages' list items and pages → road items paired by ID. */
export function buildTownItems(
  lists: Record<"fr" | "en", TownListItem[]>,
  details: Record<"fr" | "en", Map<string, { title: string; body: string }>>,
): RoadItem[] {
  const ids = [...new Set([...lists.fr, ...lists.en].map((i) => i.id))];
  return ids.map((id) => {
    const fr = lists.fr.find((i) => i.id === id);
    const en = lists.en.find((i) => i.id === id);
    const base = (fr ?? en)!;
    const dFr = details.fr.get(id);
    const dEn = details.en.get(id);
    return {
      id: `town-${id}`,
      source: "town-work-info",
      kind: "town",
      road: null,
      place: "Témiscaming",
      title_fr: fr ? (dFr?.title || fr.title) : "",
      title_en: en ? (dEn?.title || en.title) : "",
      body_fr: dFr?.body ?? "",
      body_en: dEn?.body ?? "",
      original_language: fr && en ? "both" : fr ? "fr" : "en",
      source_url_fr: fr?.url ?? "",
      source_url_en: en?.url ?? "",
      published_at: base.starts_at ?? new Date(0),
      starts_at: base.starts_at,
      ends_at: base.ends_at ?? en?.ends_at ?? null,
    } satisfies RoadItem;
  });
}
