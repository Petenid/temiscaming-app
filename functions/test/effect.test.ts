// "Until when is this alert in effect?" (spec §5b), checked against the real
// alerts saved on 2026-10-19 and against the cases that must never go wrong.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { torontoToUtc } from "../src/alerts/dates";
import { effectOf } from "../src/alerts/effect";
import { Alert, pairItems } from "../src/alerts/pair";
import { parseList } from "../src/alerts/parse";

const dir = join(__dirname, "fixtures/2026-10-19");
const list = (lang: string) => parseList(readFileSync(join(dir, `list-${lang}.html`), "utf8"));
const alerts = pairItems(list("fr"), list("en"));

const find = (title: RegExp): Alert => {
  const a = alerts.find((x) => title.test(x.titleFr));
  if (!a) throw new Error(`no fixture alert matching ${title}`);
  return a;
};
const effect = (a: Alert) => effectOf({
  category: a.category, title_fr: a.titleFr, title_en: a.titleEn,
  body_fr: a.excerptFr, body_en: a.excerptEn, published_at: a.publishedAt,
});
const days = (n: number) => n * 24 * 3600_000;
const sample = (over: Partial<Parameters<typeof effectOf>[0]>) => effectOf({
  category: "other", title_fr: "", title_en: "", body_fr: "", body_en: "",
  published_at: torontoToUtc(2026, 9, 20, 15, 0), ...over,
});

describe("dated notices end after their last date", () => {
  it("the low-pressure notice of Monday 21 September ends at midnight that night", () => {
    const e = effect(find(/^BAISSE DE PRESSION D'EAU - LUNDI 21 SEPTEMBRE/));
    expect(e.rule).toBe("dated");
    expect(e.until).toEqual(torontoToUtc(2026, 9, 22, 0, 0));
  });

  it("a range uses its last day, in French and in English", () => {
    expect(sample({ body_fr: "Travaux du 21 au 24 septembre" }).until).toEqual(torontoToUtc(2026, 9, 25, 0, 0));
    expect(sample({ body_en: "Work from September 22 to 25" }).until).toEqual(torontoToUtc(2026, 9, 26, 0, 0));
    expect(sample({ body_en: "Drilling on July 24 and 25", published_at: torontoToUtc(2026, 7, 20, 9, 0) }).until)
      .toEqual(torontoToUtc(2026, 7, 26, 0, 0));
    expect(sample({ body_fr: "Les 24 et 25 juillet", published_at: torontoToUtc(2026, 7, 20, 9, 0) }).until)
      .toEqual(torontoToUtc(2026, 7, 26, 0, 0));
  });

  it("the latest date in either language wins", () => {
    const e = sample({ body_fr: "le 21 septembre", body_en: "until September 23" });
    expect(e.until).toEqual(torontoToUtc(2026, 9, 24, 0, 0));
  });

  it("a date without a year near New Year belongs to the closest year", () => {
    const e = sample({ body_fr: "Collecte le 2 janvier", published_at: torontoToUtc(2026, 12, 29, 10, 0) });
    expect(e.until).toEqual(torontoToUtc(2027, 1, 3, 0, 0));
  });

  it("dates before the notice was posted are background, not end dates", () => {
    const e = sample({ body_fr: "À la suite des travaux du lundi 14 septembre, l'eau est jaunâtre." });
    expect(e.rule).toBe("undated");
  });

  it("ISO dates count too", () => {
    expect(sample({ body_fr: "Travaux - 2026-09-21 au 2026-10-30" }).until).toEqual(torontoToUtc(2026, 10, 31, 0, 0));
  });

  it("street numbers and times aren't mistaken for dates", () => {
    expect(sample({ body_fr: "1560 à 1631, chemin Kipawa, de 13 h 30 à 17 h" }).rule).toBe("undated");
  });
});

describe("undated notices last 7 days", () => {
  it("'Avis aux propriétaires - avenue Murer' of 28 May", () => {
    const a = find(/^AVIS AUX PROPRIÉTAIRES - AVENUE MURER/);
    const e = effect(a);
    expect(e.rule).toBe("undated");
    expect(e.until.getTime() - a.publishedAt.getTime()).toBe(days(7));
  });
});

describe("only the Town can end water advisories (no false all-clear)", () => {
  it("every water-category alert in the fixtures is lifted-only, 30 days", () => {
    const water = alerts.filter((a) =>
      ["boil-water", "water-interruption", "water-main-break", "cloudy-water", "water-restriction"].includes(a.category));
    expect(water.length).toBeGreaterThan(10);
    for (const a of water) {
      const e = effect(a);
      expect(e.rule, a.titleFr).toBe("lifted-only");
      expect(e.until.getTime() - a.publishedAt.getTime()).toBe(days(30));
    }
  });

  it("the March 2025 boil advisory's 'Mise à jour | 21 mars 2025' does not end it", () => {
    const a = find(/^AVIS D'ÉBULLITION PRÉVENTIF - TOUS LES SECTEURS/);
    expect(a.excerptFr).toContain("21 mars 2025");
    expect(effect(a).rule).toBe("lifted-only");
  });

  it("boil-water notices filed under a general category are lifted-only", () => {
    expect(effect(find(/^MISE À JOUR - AVIS D'ÉBULLITION PRÉVENTIF EST TOUJOURS/)).rule).toBe("lifted-only");
    expect(sample({ title_en: "PRECAUTIONARY BOIL WATER ADVISORY - SEPTEMBER 21" }).rule).toBe("lifted-only");
  });

  it("'jusqu'à avis contraire' / 'until further notice' are lifted-only", () => {
    expect(effect(find(/^RÉDUCTION IMMÉDIATE DE LA CONSOMMATION/)).rule).toBe("lifted-only");
    expect(sample({ body_en: "Road closed from September 21 until further notice." }).rule).toBe("lifted-only");
    expect(sample({ body_fr: "Fermé le 21 septembre jusqu'à nouvel ordre." }).rule).toBe("lifted-only");
  });
});
