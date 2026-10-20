// Our own push texts, in both languages (DESIGN §5): an English speaker
// gets an understandable notice even when the Town posted in French only,
// and vice versa. The Town's full text is one tap away in the app.
import { Category } from "../alerts/classify";

export type Lang = "fr" | "en";

export interface PushText {
  title: string;
  body: string;
}

/** Which template an alert uses. Also the key for the duplicate-push cooldown. */
export type TemplateKey =
  | "boil-water"
  | "water-notice"
  | "lifted";

const WATER_NOTICE_LABEL: Record<Lang, Partial<Record<Category, string>>> = {
  fr: {
    "water-interruption": "Interruption d'eau",
    "water-main-break": "Bris d'aqueduc",
    "cloudy-water": "Eau brouillée",
    "water-restriction": "Restriction d'eau",
  },
  en: {
    "water-interruption": "Water interruption",
    "water-main-break": "Water main break",
    "cloudy-water": "Cloudy water",
    "water-restriction": "Water-use restriction",
  },
};

export function pushText(key: TemplateKey, category: Category, lang: Lang): PushText {
  const fr = lang === "fr";
  switch (key) {
    case "boil-water":
      return fr
        ? { title: "Avis d'ébullition à Témiscaming", body: "Faites bouillir l'eau du robinet avant de la boire. Touchez pour les détails." }
        : { title: "Boil-water advisory in Témiscaming", body: "Boil tap water before drinking it. Tap for details." };
    case "water-notice": {
      const label = WATER_NOTICE_LABEL[lang][category] ?? (fr ? "Avis sur l'eau" : "Water notice");
      return fr
        ? { title: "Avis sur l'eau à Témiscaming", body: `${label}. Touchez pour les détails.` }
        : { title: "Water notice in Témiscaming", body: `${label}. Tap for details.` };
    }
    case "lifted":
      return fr
        ? { title: "Avis levé", body: "L'avis sur l'eau est levé. Touchez pour les détails." }
        : { title: "Advisory lifted", body: "The water advisory has been lifted. Tap for details." };
  }
}

// --- Collection change notices (Milestone 2, spec §6) ---

export type CollectionChange = "moved" | "cancelled" | "added";
export type BinMaterial = "compost" | "recycling" | "garbage";

const BIN_NAME: Record<Lang, Record<BinMaterial, string>> = {
  fr: { compost: "bac vert", recycling: "bac bleu", garbage: "bac noir" },
  en: { compost: "green bin", recycling: "blue bin", garbage: "black bin" },
};

/** "jeudi 25 juin" / "Thursday, June 25" for a "YYYY-MM-DD" date. */
export function formatPickupDate(date: string, lang: Lang): string {
  const [y, m, d] = date.split("-").map(Number);
  return new Intl.DateTimeFormat(lang === "fr" ? "fr-CA" : "en-CA", {
    weekday: "long", month: "long", day: "numeric", timeZone: "UTC",
  }).format(new Date(Date.UTC(y, m - 1, d)));
}

/** "Bac bleu", "Bac bleu et bac vert" / "Blue bin", "Blue and green bins". */
export function binsLabel(materials: BinMaterial[], lang: Lang): string {
  // Always the same order: green, blue, black (like the bins themselves).
  const order: BinMaterial[] = ["compost", "recycling", "garbage"];
  const names = order.filter((m) => materials.includes(m)).map((m) => BIN_NAME[lang][m]);
  let label: string;
  if (lang === "fr") {
    label = names.length > 1 ? `${names.slice(0, -1).join(", ")} et ${names.at(-1)}` : names[0];
  } else {
    const colours = names.map((n) => n.replace(" bin", ""));
    label = names.length > 1
      ? `${colours.slice(0, -1).join(", ")} and ${colours.at(-1)} bins`
      : names[0];
  }
  return label.charAt(0).toUpperCase() + label.slice(1);
}

export function collectionChangeText(
  change: CollectionChange, materials: BinMaterial[], date: string,
  previousDate: string | null, lang: Lang,
): PushText {
  const bins = binsLabel(materials, lang);
  const when = formatPickupDate(date, lang);
  const fr = lang === "fr";
  switch (change) {
    case "moved": {
      const before = previousDate ? formatPickupDate(previousDate, lang) : "";
      return fr
        ? { title: "Collecte déplacée", body: `${bins} : ${when} (au lieu du ${before}).` }
        : { title: "Pickup moved", body: `${bins}: ${when} (instead of ${before}).` };
    }
    case "cancelled":
      return fr
        ? { title: "Collecte annulée", body: `${bins} du ${when}. Touchez pour les détails.` }
        : { title: "Pickup cancelled", body: `${bins} on ${when}. Tap for details.` };
    case "added":
      return fr
        ? { title: "Collecte ajoutée", body: `${bins} : ${when}.` }
        : { title: "Pickup added", body: `${bins}: ${when}.` };
  }
}
