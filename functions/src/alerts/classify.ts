// Decides what kind of alert something is: its category (from the site's
// own category icon), whether it's a lifting notice, and its status.
import { fold } from "./dates";

export type Category =
  | "boil-water"
  | "water-interruption"
  | "water-main-break"
  | "cloudy-water"
  | "water-restriction"
  | "traffic"
  | "other";

/** The site's category icons (spec §2). Anything else is "other". */
const ICONS: Record<string, Category> = {
  "am-ebullition": "boil-water",
  "am-interruption": "water-interruption",
  "am-brisaqueduc": "water-main-break",
  "am-eaubrouillee": "cloudy-water",
  "am-restrictioneaupotable": "water-restriction",
  "am-circulation": "traffic",
  "am-autres": "other",
  "am-avisimportant": "other",
};

export const WATER_CATEGORIES: ReadonlySet<Category> = new Set([
  "boil-water", "water-interruption", "water-main-break", "cloudy-water", "water-restriction",
]);

export function categoryFromIcon(icon: string | null): { category: Category; known: boolean } {
  const category = icon ? ICONS[icon] : undefined;
  return category ? { category, known: true } : { category: "other", known: false };
}

// "(Alerte levée)" means "alert lifted". The English site mistranslates it
// as "(Alert raised)" — same meaning here, despite the words.
const LIFTED_PREFIX = /^\s*\(\s*(alerte levee|alert raised)\s*\)\s*/i;

/** True when the Town has marked this alert as over. */
export function hasLiftedPrefix(title: string): boolean {
  return LIFTED_PREFIX.test(fold(title));
}

/** The title without the "(Alerte levée)" / "(Alert raised)" prefix. */
export function stripLiftedPrefix(title: string): string {
  // Measure the prefix on the folded text; accents don't change its length
  // in characters once recomposed, so cut the original at the same place.
  const m = fold(title.normalize("NFC")).match(LIFTED_PREFIX);
  return m ? title.normalize("NFC").slice(m[0].length) : title;
}

/**
 * True for a notice announcing that an advisory is over, e.g.
 * "LEVÉE DE L'AVIS D'ÉBULLITION", "BOIL WATER ADVISORY LIFTED",
 * "Lifting of Preventive Boil Water Advisory".
 * Word boundaries keep "élevé" (high, as in water level) from matching.
 */
export function isLiftingNotice(title: string): boolean {
  const t = fold(stripLiftedPrefix(title));
  return /\b(levee|levees|leve|lifted|lifting)\b/.test(t);
}

/** True if a title is about drinking water (used for lifting notices filed under a general category). */
export function mentionsWater(title: string): boolean {
  return /\b(ebullition|bouillir|eau|aqueduc|boil|boil-water|water)\b/.test(fold(title));
}
