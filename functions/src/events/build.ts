// Turns the calendar entries that aren't pickups into one clean event per
// Town event (spec events-calendar §2, §5). Pure: no network, no database.
//
// The same month pages feed the bin schedule (collection/) and this file;
// isPickupIcon() decides which side each entry goes to.
import { isPickupIcon } from "../collection/classify";
import { CalendarEntry } from "../collection/parse";

export type EventCategory = "council" | "closure" | "service-canada" | "culture" | "community";

/** Icon → category (spec D4). Any other icon is "community", with a warning. */
const ICON_CATEGORY: Record<string, EventCategory> = {
  "pm-gavel": "council",
  "pm-circle-info": "closure",
  "pm-leaf-maple": "service-canada",
  "pm-microphone-stand": "culture",
  "pm-masks-theater": "culture",
  "pm-star-sharp": "community",
  "pm-group-hands-up": "community",
  "pm-family": "community",
  "pm-hockey-stick-puck": "community",
};

/** One Town event, both languages joined. */
export interface TownEvent {
  /** The Town's event number, shared by the French and English sites. */
  id: string;
  category: EventCategory;
  titleFr: string;
  titleEn: string;
  /** Which titles the Town gave: "both", one language, or "none" (spec D3). */
  originalLanguage: "both" | "fr" | "en" | "none";
  placeFr: string;
  placeEn: string;
  /** First day, "YYYY-MM-DD" (all-day: the Town gives no times). */
  startsOn: string;
  /** Last day; equal to startsOn for a one-day event. */
  endsOn: string;
  urlFr: string;
  urlEn: string;
}

export interface BuildResult {
  events: TownEvent[];
  warnings: string[];
}

/** The first non-empty value, or "". */
const firstText = (values: string[]) => values.find((v) => v !== "") ?? "";

/**
 * Groups entries by event number. A multi-day event is listed under each of
 * its days: it runs from its first day to its last. The link always points
 * to the real first day, which also catches an event that began in a month
 * we didn't fetch (Town hall closed from 29 December, listed from 1 January).
 */
export function buildEvents(fr: CalendarEntry[], en: CalendarEntry[]): BuildResult {
  const groups = new Map<string, { fr: CalendarEntry[]; en: CalendarEntry[] }>();
  const add = (e: CalendarEntry, lang: "fr" | "en") => {
    if (isPickupIcon(e.icon)) return; // a bin pickup: collection/ handles it
    if (!groups.has(e.eventId)) groups.set(e.eventId, { fr: [], en: [] });
    groups.get(e.eventId)![lang].push(e);
  };
  fr.forEach((e) => add(e, "fr"));
  en.forEach((e) => add(e, "en"));

  const warnings: string[] = [];
  const events: TownEvent[] = [];
  for (const [id, g] of groups) {
    const all = [...g.fr, ...g.en];
    const dates = all.flatMap((e) => [e.date, e.linkDate]).sort();
    const listed = all.map((e) => e.date).sort();
    const icon = all[0].icon;
    let category = icon ? ICON_CATEGORY[icon] : undefined;
    if (!category) {
      category = "community";
      warnings.push(`event ${id}: unfamiliar icon ${icon ?? "(none)"}, shown as community`);
    }
    const titleFr = firstText(g.fr.map((e) => e.title));
    const titleEn = firstText(g.en.map((e) => e.title));
    if (!titleFr && !titleEn) warnings.push(`event ${id} on ${listed[0]} has no title`);
    if (!g.fr.length || !g.en.length) {
      warnings.push(`event ${id} is only on the ${g.fr.length ? "French" : "English"} calendar`);
    }
    events.push({
      id,
      category,
      titleFr,
      titleEn,
      originalLanguage: titleFr && titleEn ? "both" : titleFr ? "fr" : titleEn ? "en" : "none",
      placeFr: firstText(g.fr.map((e) => e.place)),
      placeEn: firstText(g.en.map((e) => e.place)),
      startsOn: dates[0],
      endsOn: listed[listed.length - 1],
      urlFr: g.fr[0]?.url ?? "",
      urlEn: g.en[0]?.url ?? "",
    });
  }
  events.sort((a, b) => a.startsOn.localeCompare(b.startsOn) || a.id.localeCompare(b.id));
  return { events, warnings };
}
