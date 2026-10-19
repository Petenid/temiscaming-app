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
