// Reads the alert site's HTML pages into plain data. No network here:
// these functions take the page text and return what they found, which is
// what lets the tests run against saved copies of real pages (fixtures).
import * as cheerio from "cheerio";

import { parsePublished } from "./dates";

/** One alert as it appears on one language's list page. */
export interface ListItem {
  /** The platform's own number (data-id). Missing on archived items. */
  platformId: string | null;
  url: string;
  title: string;
  publishedAt: Date;
  excerpt: string;
  /** Category icon class, e.g. "am-ebullition". */
  icon: string | null;
  /** True for items under "This alert is no longer valid". */
  archived: boolean;
}

export interface DetailPage {
  title: string;
  publishedAt: Date | null;
  body: string;
}

/** Decodes page bytes as UTF-8, replacing the odd invalid byte instead of failing. */
export function decodePage(bytes: Uint8Array): string {
  return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
}

const clean = (s: string) => s.replace(/\s+/g, " ").trim();

/** Parses a list page (/alertes or /alerts): current alerts, then archived ones. */
export function parseList(html: string): ListItem[] {
  const $ = cheerio.load(html);
  const items: ListItem[] = [];

  const read = (el: cheerio.Cheerio<any>, archived: boolean) => {
    const link = el.find(".txt_alerte h4 a").first();
    const url = link.attr("href")?.trim();
    const publishedAt = parsePublished(el.find(".txt_alerte h5").first().text());
    if (!url || !publishedAt) return; // malformed block: skip rather than guess
    const icon =
      el.find(".menu_alerte i[class*='am-']").first().attr("class")
        ?.split(/\s+/).find((c) => c.startsWith("am-")) ?? null;
    // The excerpt is the last plain paragraph (archived items have a
    // "no longer valid" paragraph first).
    const excerpt = clean(el.find(".txt_alerte > p").last().text());
    items.push({
      platformId: el.find("[data-id]").first().attr("data-id")?.trim() || null,
      url,
      title: clean(link.text()),
      publishedAt,
      excerpt,
      icon,
      archived,
    });
  };

  $("#alertes .alerte").each((_, el) => read($(el), false));
  $("#archives .alerte").each((_, el) => read($(el), true));
  return items;
}

/** Parses one alert's own page for its full text. */
export function parseDetail(html: string): DetailPage {
  const $ = cheerio.load(html);
  const box = $("#alertes.txt_alerte").first();
  // Keep paragraph breaks: one line per block element.
  const bodyEl = box.find("div.h4").first();
  bodyEl.find("br").replaceWith("\n");
  bodyEl.find("p, div, li").each((_, el) => {
    $(el).prepend("\n");
  });
  const body = bodyEl
    .text()
    .split("\n")
    .map(clean)
    .filter((line) => line.length > 0)
    .join("\n\n");
  return {
    title: clean(box.find("#titreAlerte h2").first().text()),
    publishedAt: parsePublished(box.find("h3").first().text()),
    body,
  };
}
