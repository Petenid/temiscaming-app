// Decides until when an alert the Town hasn't marked lifted still counts as
// "in effect". The Town almost never closes its general notices, so without
// this a one-day low-pressure notice says "In effect" for a month.
//
// Three rules, safest first:
//   lifted-only — water advisories, anything about boil water, and anything
//                 "until further notice": only the Town can end them, so they
//                 stay in effect up to 30 days. Dates in their text are NOT
//                 trusted (the March 2025 boil advisory says "Mise à jour |
//                 21 mars 2025" while still in effect).
//   dated       — other notices that name a date: in effect until the end of
//                 the last date they mention (Témiscaming time).
//   undated     — other notices with no usable date: 7 days.
import { WATER_CATEGORIES } from "./classify";
import { fold, torontoToUtc } from "./dates";

export type EffectRule = "lifted-only" | "dated" | "undated";

export const LIFTED_ONLY_DAYS = 30;
export const UNDATED_DAYS = 7;

const DAY_MS = 24 * 3600_000;

const MONTHS: Record<string, number> = {
  janvier: 1, fevrier: 2, mars: 3, avril: 4, mai: 5, juin: 6,
  juillet: 7, aout: 8, septembre: 9, octobre: 10, novembre: 11, decembre: 12,
  january: 1, february: 2, march: 3, april: 4, may: 5, june: 6,
  july: 7, august: 8, september: 9, october: 10, november: 11, december: 12,
};
const MONTH = `(${Object.keys(MONTHS).join("|")})`;
const ORD = "(?:er|st|nd|rd|th)?";

// "21 septembre", "1er mai", "21 septembre 2026", "21st of September"
const DAY_MONTH = new RegExp(`\\b(\\d{1,2})${ORD}\\s+(?:of\\s+)?${MONTH}\\b(?:,?\\s+(\\d{4})\\b)?`, "g");
// "September 21", "September 21, 2026", "September 8 to 11", "July 24 and 25"
const MONTH_DAY = new RegExp(
  `\\b${MONTH}\\s+(\\d{1,2})${ORD}\\b(?:\\s*(?:-|–|to|and|&)\\s*(\\d{1,2})${ORD}\\b)?(?:,?\\s+(\\d{4})\\b)?`, "g");
// "2025-09-30"
const ISO = /\b(20\d\d)-(\d\d)-(\d\d)\b/g;

/** Words that mean only the Town can end it: boil water, or "until further notice". */
const LIFTED_ONLY_TEXT =
  /\b(ebullition|bouillir|boil|boil-water)\b|jusqu.{0,3}(a |au )?(nouvel (avis|ordre)|avis contraire)|until further notice/;

export interface EffectInput {
  category: string;
  title_fr: string;
  title_en: string;
  body_fr: string;
  body_en: string;
  published_at: Date;
}

export interface Effect {
  rule: EffectRule;
  until: Date;
}

/** A calendar day in Témiscaming. */
interface Day { y: number; m: number; d: number }

const dayNumber = (x: Day) => x.y * 10000 + x.m * 100 + x.d;

function localDay(at: Date): Day {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(at);
  const get = (t: string) => +parts.find((p) => p.type === t)!.value;
  return { y: get("year"), m: get("month"), d: get("day") };
}

function isRealDate(x: Day): boolean {
  const t = new Date(Date.UTC(x.y, x.m - 1, x.d));
  return t.getUTCFullYear() === x.y && t.getUTCMonth() === x.m - 1 && t.getUTCDate() === x.d;
}

/** A date written without a year: the year that puts it closest to the publish day. */
function withYear(m: number, d: number, year: string | undefined, published: Day): Day {
  if (year) return { y: +year, m, d };
  const pub = Date.UTC(published.y, published.m - 1, published.d);
  let best: Day = { y: published.y, m, d };
  for (const y of [published.y - 1, published.y + 1]) {
    if (Math.abs(Date.UTC(y, m - 1, d) - pub) < Math.abs(Date.UTC(best.y, m - 1, d) - pub)) {
      best = { y, m, d };
    }
  }
  return best;
}

/** Every calendar date written in [text] (French or English), in any order. */
export function datesIn(text: string, published: Day): Day[] {
  const t = fold(text);
  const found: Day[] = [];
  for (const x of t.matchAll(DAY_MONTH)) found.push(withYear(MONTHS[x[2]], +x[1], x[3], published));
  for (const x of t.matchAll(MONTH_DAY)) {
    // In a range ("September 8 to 11") the end is what matters.
    found.push(withYear(MONTHS[x[1]], +(x[3] ?? x[2]), x[4], published));
  }
  for (const x of t.matchAll(ISO)) found.push({ y: +x[1], m: +x[2], d: +x[3] });
  return found.filter(isRealDate);
}

/** Until when [alert] counts as in effect, if the Town never marks it lifted. */
export function effectOf(alert: EffectInput): Effect {
  const published = alert.published_at.getTime();
  const allText = [alert.title_fr, alert.title_en, alert.body_fr, alert.body_en].join("\n");

  if (WATER_CATEGORIES.has(alert.category as never) || LIFTED_ONLY_TEXT.test(fold(allText))) {
    return { rule: "lifted-only", until: new Date(published + LIFTED_ONLY_DAYS * DAY_MS) };
  }

  const pubDay = localDay(alert.published_at);
  const usable = datesIn(allText, pubDay).filter((x) =>
    // A date before the notice was posted is background ("the work of
    // 11 December"), not an end date. More than a year ahead is a typo.
    dayNumber(x) >= dayNumber(pubDay) &&
    Date.UTC(x.y, x.m - 1, x.d) - Date.UTC(pubDay.y, pubDay.m - 1, pubDay.d) <= 366 * DAY_MS);
  if (usable.length > 0) {
    const last = usable.reduce((a, b) => (dayNumber(b) > dayNumber(a) ? b : a));
    // Midnight at the end of that day, Témiscaming time.
    return { rule: "dated", until: torontoToUtc(last.y, last.m, last.d + 1, 0, 0) };
  }
  return { rule: "undated", until: new Date(published + UNDATED_DAYS * DAY_MS) };
}
