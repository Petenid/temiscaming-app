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

// --- Fire bans (Milestone 6, spec fire-bans D6) ---

export type FireLayer = "ifco" | "icaf";
export type FirePushKind = "announced" | "started" | "lifted";

/** "jeudi 22 octobre à 8 h" / "Thursday, October 22 at 8 a.m." (Témiscaming time). */
export function formatFireStart(at: Date, lang: Lang): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto", hourCycle: "h23", hour: "2-digit", minute: "2-digit",
  }).formatToParts(at);
  const h = +parts.find((p) => p.type === "hour")!.value;
  const m = +parts.find((p) => p.type === "minute")!.value;
  const day = new Intl.DateTimeFormat(lang === "fr" ? "fr-CA" : "en-CA", {
    timeZone: "America/Toronto", weekday: "long", month: "long", day: "numeric",
  }).format(at);
  if (lang === "fr") return `${day} à ${h} h${m ? ` ${String(m).padStart(2, "0")}` : ""}`;
  const h12 = h % 12 === 0 ? 12 : h % 12;
  const clock = m ? `${h12}:${String(m).padStart(2, "0")}` : `${h12}`;
  return `${day} at ${clock} ${h < 12 ? "a.m." : "p.m."}`;
}

const FIRE_TITLE: Record<Lang, Record<FireLayer, string>> = {
  fr: { ifco: "Interdiction de faire des feux à ciel ouvert", icaf: "Interdiction d'accès en forêt" },
  en: { ifco: "Open-fire ban", icaf: "Forest access ban" },
};

const FIRE_LIFTED_FR: Record<FireLayer, string> = {
  ifco: "Fin de l'interdiction de feux à ciel ouvert",
  icaf: "Fin de l'interdiction d'accès en forêt",
};

export function firePushText(layer: FireLayer, kind: FirePushKind, startsAt: Date | null, lang: Lang): PushText {
  const fr = lang === "fr";
  const title = FIRE_TITLE[lang][layer];
  const where = layer === "ifco"
    ? (fr ? "à Témiscaming" : "for Témiscaming")
    : (fr ? "autour de Témiscaming" : "around Témiscaming");
  const tap = fr ? "Touchez pour les détails." : "Tap for details.";
  switch (kind) {
    case "announced": {
      const when = startsAt ? formatFireStart(startsAt, lang) : "";
      return fr
        ? { title, body: `En vigueur ${where} à partir de ${when}. ${tap}` }
        : { title, body: `In effect ${where} starting ${when}${when.endsWith(".") ? "" : "."} ${tap}` };
    }
    case "started": {
      const what = layer === "ifco"
        ? (fr ? "Pas de feux de camp ni de brûlage." : "No campfires or brush burning.")
        : (fr ? "N'allez pas en forêt." : "Stay out of the forest.");
      return fr
        ? { title, body: `En vigueur ${where}. ${what} ${tap}` }
        : { title, body: `Now in effect ${where}. ${what} ${tap}` };
    }
    case "lifted":
      return fr
        ? { title: FIRE_LIFTED_FR[layer], body: `L'interdiction est levée ${where}. ${tap}` }
        : { title: `${title} lifted`, body: `The ban ${where} has been lifted. ${tap}` };
  }
}

// --- Road closures (Milestone 7, spec roads D7, D8) ---

export type RoadPushKind = "closed" | "reopened";
export type RoadName = "101" | "63";

/** "Route 101" in both; Highway 63 is "route 63" in Ontario's French. */
function roadTitle(road: RoadName, lang: Lang): string {
  if (road === "101") return "Route 101";
  return lang === "fr" ? "Route 63 (Ontario)" : "Highway 63 (Ontario)";
}

/**
 * "Route 101 fermée à Saint-Édouard-de-Fabre" / "Route 101 closed at …";
 * a closure that hasn't started yet says from when (spec D7).
 */
export function roadPushText(
  road: RoadName, kind: RoadPushKind, place: string, startsAt: Date | null, now: Date, lang: Lang,
): PushText {
  const fr = lang === "fr";
  const name = roadTitle(road, lang);
  const at = place ? (fr ? ` à ${place}` : ` at ${place}`) : "";
  const tap = fr ? "Touchez pour les détails." : "Tap for details.";
  if (kind === "reopened") {
    return fr
      ? { title: `${name} rouverte${at}`, body: `La fermeture est terminée. ${tap}` }
      : { title: `${name} reopened${at}`, body: `The closure is over. ${tap}` };
  }
  if (startsAt && startsAt > now) {
    const when = formatFireStart(startsAt, lang);
    return fr
      ? { title: `${name} fermée${at}`, body: `Fermeture prévue à partir de ${when}. ${tap}` }
      : { title: `${name} closed${at}`, body: `Closure planned starting ${when}${when.endsWith(".") ? "" : "."} ${tap}` };
  }
  return fr
    ? { title: `${name} fermée${at}`, body: `La route est fermée. ${tap}` }
    : { title: `${name} closed${at}`, body: `The road is closed. ${tap}` };
}

// --- Power outages (Milestone 8, spec power-outages D5, D6) ---

export type PowerPushKind = "out" | "restored";
export type PowerArea = "temiscaming" | "lac_tee";

/**
 * "Panne de courant à Témiscaming — 120 clients touchés" / "Power outage in
 * Témiscaming — 120 customers affected"; "Courant rétabli …" / "Power restored …".
 * The place is Témiscaming unless every outage is at Lac Tee.
 */
export function powerPushText(kind: PowerPushKind, customers: number, areas: PowerArea[], lang: Lang): PushText {
  const fr = lang === "fr";
  const lacTeeOnly = areas.length > 0 && areas.every((a) => a === "lac_tee");
  const where = lacTeeOnly ? (fr ? "au lac Tee" : "at Lac Tee") : (fr ? "à Témiscaming" : "in Témiscaming");
  const tap = fr ? "Touchez pour les détails." : "Tap for details.";
  if (kind === "restored") {
    return fr
      ? { title: `Courant rétabli ${where}`, body: `Hydro-Québec ne signale plus de panne ${where}. ${tap}` }
      : { title: `Power restored ${where}`, body: `Hydro-Québec no longer reports an outage ${where}. ${tap}` };
  }
  const count = fr
    ? `${customers.toLocaleString("fr-CA")} client${customers > 1 ? "s" : ""} touché${customers > 1 ? "s" : ""}`
    : `${customers.toLocaleString("en-CA")} customer${customers === 1 ? "" : "s"} affected`;
  return fr
    ? { title: `Panne de courant ${where}`, body: `${count}. ${tap}` }
    : { title: `Power outage ${where}`, body: `${count}. ${tap}` };
}
