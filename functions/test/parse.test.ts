// Tests the parser against real pages saved from the Town's alert site on
// 2026-10-19 (see .github/workflows/capture-fixtures.yml).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { parsePublished, torontoToUtc } from "../src/alerts/dates";
import { isLiftingNotice, stripLiftedPrefix } from "../src/alerts/classify";
import { decodePage, parseDetail, parseList } from "../src/alerts/parse";
import { pairItems } from "../src/alerts/pair";

const fixture = (name: string) =>
  decodePage(readFileSync(join(__dirname, "fixtures/2026-10-19", name)));

const fr = parseList(fixture("list-fr.html"));
const en = parseList(fixture("list-en.html"));
const alerts = pairItems(fr, en);
const byId = new Map(alerts.map((a) => [a.id, a]));

describe("list pages", () => {
  it("find every alert in both languages: 72 current + 22 archived", () => {
    for (const items of [fr, en]) {
      expect(items.filter((i) => !i.archived)).toHaveLength(72);
      expect(items.filter((i) => i.archived)).toHaveLength(22);
    }
  });

  it("read the newest French alert correctly", () => {
    expect(fr[0]).toMatchObject({
      platformId: "8377",
      url: "https://temiscaming.alertesmunicipales.com/alertes/2026/10/19/levee-de-l-avis-d-ebullition-preventif",
      title: "LEVÉE DE L'AVIS D'ÉBULLITION PRÉVENTIF.",
      icon: "am-avisimportant",
      archived: false,
    });
    // 13h58 in Témiscaming (EDT, UTC−4) = 17:58 UTC
    expect(fr[0].publishedAt.toISOString()).toBe("2026-10-19T17:58:00.000Z");
    expect(fr[0].excerpt).toMatch(/^La Ville de Témiscaming informe/);
  });

  it("archived items have no id but keep their category icon", () => {
    const archived = fr.find((i) => i.archived)!;
    expect(archived.platformId).toBeNull();
    expect(archived.icon).toMatch(/^am-/);
    expect(archived.excerpt).not.toMatch(/n'est plus valide/);
  });

  it("every item has a known category icon", () => {
    const unknown = [...fr, ...en].filter(
      (i) => !/^am-(ebullition|interruption|brisaqueduc|eaubrouillee|restrictioneaupotable|circulation|autres|avisimportant)$/.test(i.icon ?? ""),
    );
    expect(unknown.map((i) => i.icon)).toEqual([]);
  });
});

describe("pairing French and English", () => {
  it("pairs all 94 alerts, none left in one language only", () => {
    expect(alerts).toHaveLength(94);
    expect(alerts.filter((a) => !a.titleFr || !a.titleEn)).toEqual([]);
  });

  it("gives the two alerts sharing one URL different ids", () => {
    const a = byId.get("8377")!;
    const b = byId.get("8376")!;
    expect(a.sourceUrlFr).toBe(b.sourceUrlFr);
    expect(a.id).not.toBe(b.id);
    expect(new Set(alerts.map((x) => x.id)).size).toBe(94);
  });

  it("reads '(Alert raised)' as lifted and removes the prefix", () => {
    const boil = byId.get("8344")!;
    expect(boil).toMatchObject({
      kind: "advisory",
      category: "boil-water",
      status: "lifted",
      severity: "urgent",
      titleFr: "AVIS D'ÉBULLITION PRÉVENTIF",
      titleEn: "PRECAUTIONARY BOIL WATER ADVISORY",
    });
  });

  it("treats lifting notices as lifts, even when filed as boil-water", () => {
    // 8376 is in the boil-water category; 8377 in "important notice".
    for (const id of ["8376", "8377"]) {
      expect(byId.get(id)).toMatchObject({ kind: "lifting-notice", status: "active", severity: "info" });
    }
    expect(byId.get("8376")!.category).toBe("boil-water");
  });

  it("marks archived alerts expired, paired across languages", () => {
    const expired = alerts.filter((a) => a.status === "expired");
    expect(expired).toHaveLength(22);
    expect(expired[0].id).toMatch(/^a-2026-09-08-/);
    expect(expired[0].titleEn).toMatch(/Water Use Reduction/);
  });
});

describe("detail pages", () => {
  it("read title, time and full body (French)", () => {
    const d = parseDetail(fixture("detail-fr-boil.html"));
    expect(d.title).toBe("(Alerte levée) AVIS D'ÉBULLITION PRÉVENTIF");
    expect(d.publishedAt?.toISOString()).toBe("2026-10-12T18:32:00.000Z");
    expect(d.body).toMatch(/^La Ville de Témiscaming informe la population/);
    expect(d.body).toContain("au moins une minute");
    expect(d.body).toMatch(/Merci de votre compréhension!$/);
    expect(d.body).not.toContain("<");
  });

  it("read title, time and full body (English)", () => {
    const d = parseDetail(fixture("detail-en-lifted.html"));
    expect(d.title).toBe("PRECAUTIONARY BOIL WATER ADVISORY LIFTED.");
    expect(d.publishedAt?.toISOString()).toBe("2026-10-19T17:58:00.000Z");
    expect(d.body.split("\n\n")).toHaveLength(5);
    expect(d.body).toMatch(/Thank you for your patience and cooperation!$/);
  });
});

describe("dates and words", () => {
  it("reads every publish-line spelling", () => {
    const want = "2026-10-12T18:32:00.000Z";
    expect(parsePublished("Publié le lundi 12 octobre 2026 à 14h32")?.toISOString()).toBe(want);
    expect(parsePublished("Published on monday 12 october 2026 in 14h32")?.toISOString()).toBe(want);
    expect(parsePublished("Publié le lundi 12 octobre 2026 à 14 h 32")?.toISOString()).toBe(want);
    expect(parsePublished("Published on monday 12 october 2026 in 14:32")?.toISOString()).toBe(want);
    expect(parsePublished("nothing here")).toBeNull();
  });

  it("handles winter time (EST, UTC−5)", () => {
    expect(torontoToUtc(2025, 12, 23, 9, 0).toISOString()).toBe("2025-12-23T14:00:00.000Z");
    expect(parsePublished("Publié le mardi 3 février 2026 à 8h05")?.toISOString()).toBe("2026-02-03T13:05:00.000Z");
  });

  it("spots lifting notices without false alarms", () => {
    for (const t of [
      "LEVÉE DE L'AVIS D'ÉBULLITION PRÉVENTIF", "BOIL-WATER NOTICE LIFTED",
      "Lifting of Preventive Boil Water Advisory", "Avis d'ébullition levé",
    ]) expect(isLiftingNotice(t), t).toBe(true);
    for (const t of [
      "(Alerte levée) AVIS D'ÉBULLITION PRÉVENTIF", "(Alert raised) PRECAUTIONARY BOIL WATER ADVISORY",
      "NIVEAU D'EAU ÉLEVÉ - LAC TÉMISCAMINGUE", "Relevé des compteurs d'eau",
    ]) expect(isLiftingNotice(t), t).toBe(false);
    expect(stripLiftedPrefix("(Alerte levée) AVIS D'ÉBULLITION")).toBe("AVIS D'ÉBULLITION");
  });
});
