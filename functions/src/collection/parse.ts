// Reads one month of the Town's events calendar into plain data. No network
// here, so the tests can run on saved pages (spec §2).
//
// We read the agenda list under the month grid: one <li> per day, an <h6>
// heading with the day, then one link per event. The day comes from the
// heading, not from the link, because an event spanning several days (the
// Christmas-tree pickup) links to its first day under every heading.
import * as cheerio from "cheerio";

export const CALENDAR_SITE = "https://www.temiscaming.net";

/** One event under one day heading, as the page shows it. */
export interface CalendarEntry {
  /** Local calendar date, "YYYY-MM-DD". */
  date: string;
  /** The Town's event number, shared by the French and English sites. */
  eventId: string;
  /** Full link to the event page. */
  url: string;
  /** Icon class, e.g. "pm-recycling-bin-a"; null if the event has none. */
  icon: string | null;
  title: string;
}

const clean = (s: string) => s.replace(/\s+/g, " ").trim();
const pad = (n: number) => String(n).padStart(2, "0");

/** Address of a month page in one language. */
export function monthUrl(lang: "fr" | "en", year: number, month: number): string {
  const path = lang === "fr" ? "/fr/calendrier" : "/en/calendar";
  return `${CALENDAR_SITE}${path}?year=${year}&month=${month}`;
}

/**
 * Parses a month page. `year` and `month` are the month we asked for: the
 * headings only need to give the day, which avoids reading French and
 * English month names (and "1er").
 */
export function parseMonth(html: string, year: number, month: number): CalendarEntry[] {
  const $ = cheerio.load(html);
  const entries: CalendarEntry[] = [];

  $("h6").each((_, heading) => {
    // Digits only: the first of the month is written 1<sup>er</sup> in French.
    const day = Number($(heading).find("span.day").first().text().match(/\d+/)?.[0]);
    if (!day) return;
    const date = `${year}-${pad(month)}-${pad(day)}`;

    $(heading).parent().find("a.calendar-widget__item").each((_, link) => {
      const href = $(link).attr("href") ?? "";
      // /fr/evenements/2026/10/6/141942/slug — the numeric part before the slug.
      const eventId = href.match(/\/\d{4}\/\d{1,2}\/\d{1,2}\/(\d+)\//)?.[1];
      if (!eventId) return; // month-level "banner" items have no day: not ours
      const icon = ($(link).find("i").first().attr("class") ?? "")
        .split(/\s+/).find((c) => c.startsWith("pm-") && c !== "pm") ?? null;
      // The subtitle may hold a place name in a small <span>; keep only the title.
      const subtitle = $(link).find(".calendar-widget__subtitle").first().clone();
      subtitle.find("span").remove();
      entries.push({
        date,
        eventId,
        url: href.startsWith("http") ? href : CALENDAR_SITE + href,
        icon,
        title: clean(subtitle.text()),
      });
    });
  });
  return entries;
}
