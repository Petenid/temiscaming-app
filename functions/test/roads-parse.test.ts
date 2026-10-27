// Roads parsers on real captures (2026-10-22 Quebec + Town, 2026-10-23
// Ontario) and hand-made files for what wasn't happening that day (roads spec
// §8 step 1). Hand-made files are in fixtures/roads/hand-made (see its README).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { HIGHWAY_63, ROUTE_101, stretchOf } from "../src/roads/corridor";
import { inWinterSeason, isCurrent, isQuebecClosure, onToday, quebecLabel, statusOf } from "../src/roads/model";
import {
  decodePolyline, isHighway63, ontarioUrl, ontarioUrlForLog, parseCameras, parseOntarioConditions, parseOntarioItems,
} from "../src/roads/ontario";
import { parseConditions, parseRoadworks, parseWarnings, QUEBEC_URL } from "../src/roads/quebec";
import { buildTownItems, parseEndDate, parseTownDetail, parseTownList } from "../src/roads/town";

const FIX = join(__dirname, "fixtures/roads");
const text = (p: string) => readFileSync(join(FIX, p), "utf-8");
const json = (p: string) => JSON.parse(text(p));
const QC = "2026-10-22";
const ON = "2026-10-23";
const OCT22 = new Date("2026-10-22T16:00:00Z");
const NOV3 = new Date("2026-11-03T15:00:00Z");

describe("our stretches (spec D1)", () => {
  it("Route 101 runs from Témiscaming to Ville-Marie; Highway 63 from Thorne to North Bay", () => {
    expect(ROUTE_101[0]).toEqual([-79.10081, 46.71153]);
    expect(ROUTE_101.at(-1)).toEqual([-79.43687, 47.33182]);
    expect(HIGHWAY_63[0][1]).toBeCloseTo(46.708, 2); // Thorne, at the bridge
    expect(HIGHWAY_63.at(-1)![1]).toBeCloseTo(46.331, 2); // North Bay
  });

  it("near the line counts, far doesn't; near town counts whatever the road", () => {
    expect(stretchOf([[-79.3673, 47.1962]], ["101"])).toBe("101"); // Saint-Édouard-de-Fabre
    expect(stretchOf([[-79.2557, 48.0995]], ["101"])).toBeNull(); // Route 101 at Rouyn-Noranda
    expect(stretchOf([[-79.08, 46.73]], ["101"])).toBe("101"); // in town, off the line
    expect(stretchOf([[-79.1569, 46.5428]], ["63"])).toBe("63"); // Highway 63 at Highway 533
    expect(stretchOf([[-79.40075, 46.272175]], ["63"])).toBeNull(); // Highway 11 in North Bay
  });
});

describe("Quebec (real files, 2026-10-22)", () => {
  it("asks for the area latitude first (longitude first silently returns nothing)", () => {
    expect(QUEBEC_URL.roadworks).toContain("bbox=46.2,-80.0,47.5,-78.5,urn:ogc:def:crs:EPSG::4326");
    expect(QUEBEC_URL.warnings).toContain("typename=ms:evenements");
    expect(QUEBEC_URL.conditions).toContain("typename=ms:conditions_routieres");
  });

  it("road warnings: none on our stretch (the Route 101 one at Rouyn-Noranda is left out)", () => {
    const { items } = parseWarnings(json(`${QC}/qc-evenements-province.json`));
    expect(items).toEqual([]);
    expect(parseWarnings(json(`${QC}/qc-evenements-bbox.json`)).items).toEqual([]);
  });

  it("roadworks: none on our stretch (Duhamel-Ouest, 1.17 km past Ville-Marie, is left out)", () => {
    expect(parseRoadworks(json(`${QC}/qc-chantiers_mtmdet-bbox.json`)).items).toEqual([]);
  });

  it("winter conditions: segments 3001 and 3011, bare and dry, in both languages", () => {
    const { conditions } = parseConditions(json(`${QC}/qc-conditions_routieres-bbox.json`), OCT22);
    expect(conditions.in_season).toBe(true);
    expect(conditions.segments.map((s) => [s.from_en, s.to_en])).toEqual([
      ["Témiscaming", "Saint-Édouard-de-Fabre"],
      ["Saint-Édouard-de-Fabre", "Ville-Marie"],
    ]);
    const s = conditions.segments[0];
    expect([s.surface_fr, s.surface_en, s.surface_ok]).toEqual(["Dégagée et sèche", "Bare and Dry", true]);
    expect([s.visibility_fr, s.visibility_en, s.visibility_ok]).toEqual(["Bonne", "Good", true]);
    expect(s.drifting).toBe(false);
    expect(s.since).toEqual(new Date("2026-10-22T08:11:00Z")); // 04:11 in Témiscaming
  });

  it("an empty answer is valid for warnings; for conditions it fails in season, not in summer", () => {
    expect(parseWarnings(json("hand-made/qc-warnings-empty.json")).items).toEqual([]);
    expect(() => parseConditions(json("hand-made/qc-conditions-empty.json"), OCT22)).toThrow(/in season/);
    const summer = parseConditions(json("hand-made/qc-conditions-empty.json"), new Date("2026-07-01T12:00:00Z"));
    expect(summer.conditions).toEqual({ segments: [], in_season: false });
  });

  it("anything that isn't a FeatureCollection is a failure", () => {
    expect(() => parseWarnings({ error: "x" })).toThrow(/FeatureCollection/);
    expect(() => parseWarnings({ type: "FeatureCollection", features: [{ properties: {}, geometry: null }] })).toThrow(/geometry/);
  });
});

describe("Quebec (hand-made)", () => {
  it("a Fermeture with a blank route number is a closure on Route 101; one lane of two is an incident", () => {
    const { items } = parseWarnings(json("hand-made/qc-warnings-closure-101.json"));
    expect(items.map((i) => [i.id, i.kind, i.road, i.place])).toEqual([
      ["qc-warning-900001", "closure", "101", "Saint-Édouard-de-Fabre"],
      ["qc-warning-900002", "incident", "101", "Témiscaming"],
    ]);
    const closure = items[0];
    expect([closure.title_fr, closure.title_en, closure.original_language]).toEqual(["Route fermée", "Road closed", "fr"]);
    expect(closure.body_en).toBe(""); // French only, never machine-translated (D6)
    expect(closure.body_fr).toContain("R-101 à la hauteur de Saint-Édouard-de-Fabre\n\nDétails à venir.");
    expect(closure.body_fr).toContain("Détour : Aucun détour possible");
    expect(closure.starts_at).toEqual(new Date("2026-11-03T11:40:00Z"));
    expect(closure.ends_at).toBeNull();
    expect([items[1].title_fr, items[1].title_en]).toEqual(["Une voie sur deux fermée", "One of two lanes closed"]);
  });

  it("a roadwork closure planned next week is a closure, 'planned', on Today", () => {
    const { items } = parseRoadworks(json("hand-made/qc-roadworks-planned-closure.json"));
    expect(items).toHaveLength(1);
    const w = items[0];
    expect([w.kind, w.title_en, w.original_language]).toEqual(["closure", "Road closed (roadwork)", "both"]);
    expect(w.body_en).toContain("Complete closure");
    expect(statusOf(w, NOV3)).toBe("planned");
    expect(isCurrent(w, NOV3)).toBe(true);
    expect(onToday(w, NOV3)).toBe(true);
    expect(isCurrent(w, new Date("2026-10-20T12:00:00Z"))).toBe(false); // more than 14 days ahead
  });

  it("icy road, poor visibility and drifts are flagged", () => {
    const { conditions } = parseConditions(json("hand-made/qc-conditions-icy.json"), NOV3);
    const s = conditions.segments[0];
    expect([s.surface_en, s.surface_ok, s.visibility_ok, s.drifting]).toEqual(["Ice Covered", false, false, true]);
    expect(conditions.segments[1].surface_ok).toBe(true);
  });

  it("the closure rule (D2) and our labels (D6)", () => {
    expect(isQuebecClosure("Fermeture")).toBe(true);
    expect(isQuebecClosure("Fermeture complète\nNuit seulement")).toBe(true);
    expect(isQuebecClosure("Fermeture de 1 voie sur 2")).toBe(false);
    expect(isQuebecClosure("Fermeture de l'accotement")).toBe(false);
    expect(isQuebecClosure("Fermeture de la bretelle")).toBe(false);
    expect(isQuebecClosure("Stationnement des véhicules lourds fermé")).toBe(false);
    expect(isQuebecClosure("Circulation en alternance")).toBe(false);
    expect(quebecLabel("Circulation en alternance \nMardi à vendredi")).toEqual({ fr: "Circulation en alternance", en: "Alternating traffic" });
    expect(quebecLabel("Circulation interdite aux véhicules lourds")?.en).toBe("Closed to heavy vehicles");
    expect(quebecLabel("Pour les mises à jour sur l'état du service de traversier…")).toBeNull();
  });

  it("winter season is 15 October to 15 April", () => {
    expect(inWinterSeason(new Date("2026-10-15T12:00:00Z"))).toBe(true);
    expect(inWinterSeason(new Date("2026-10-14T12:00:00Z"))).toBe(false);
    expect(inWinterSeason(new Date("2027-04-15T12:00:00Z"))).toBe(true);
    expect(inWinterSeason(new Date("2027-04-16T12:00:00Z"))).toBe(false);
  });
});

describe("Ontario 511 (real files, 2026-10-23)", () => {
  it("events and construction: nothing on Highway 63 (Highways 11, 17, 533, 64, 401 left out)", () => {
    expect(parseOntarioItems("events", json(`${ON}/on-event-en.json`), json(`${ON}/on-event-fr.json`)).items).toEqual([]);
    expect(parseOntarioItems("construction", json(`${ON}/on-constructionprojects-en.json`), json(`${ON}/on-constructionprojects-fr.json`)).items).toEqual([]);
  });

  it("Highway 63 conditions, North Bay to Thorne, in both languages", () => {
    const [s, ...rest] = parseOntarioConditions(json(`${ON}/on-roadconditions-en.json`), json(`${ON}/on-roadconditions-fr.json`));
    expect(rest).toEqual([]);
    expect([s.from_en, s.to_en, s.from_fr, s.to_fr]).toEqual(["North Bay", "Thorne", "North Bay", "Thorne"]);
    expect([s.surface_en, s.surface_fr, s.surface_ok]).toEqual(["Bare and dry road", "Dégagée et sèche", true]);
    expect([s.visibility_en, s.visibility_fr, s.visibility_ok, s.drifting, s.no_report]).toEqual(["Good", "Bonne", true, false, false]);
  });

  it("two cameras on Highway 63, three views", () => {
    const cams = parseCameras(json(`${ON}/on-cameras-en.json`));
    expect(cams.map((c) => c.location)).toEqual(["Highway 63 at Highway 533", "Highway 63 at Wyse Road"]);
    expect(cams[1].views).toEqual([
      { image_url: "https://511on.ca/map/Cctv/2720", direction_en: "Looking North", direction_fr: "Vers le nord" },
      { image_url: "https://511on.ca/map/Cctv/2721", direction_en: "Looking South", direction_fr: "Vers le sud" },
    ]);
  });

  it("the road-conditions line decodes to Highway 63 from North Bay to Thorne", () => {
    const rc = json(`${ON}/on-roadconditions-en.json`).find((r: { RoadwayName: string }) => r.RoadwayName === "63");
    const pts = (rc.EncodedPolyline as string[]).flatMap(decodePolyline);
    expect(pts[0][1]).toBeCloseTo(46.708, 2);
    expect(pts.at(-1)![1]).toBeCloseTo(46.331, 2);
  });

  it("Highway 63, not 630 or 163; the key never shows in the URL we log", () => {
    expect(["HWY 63", "RTE 63", "63", "Highway 63"].map(isHighway63)).toEqual([true, true, true, true]);
    expect(["HWY 630", "163", "HWY 11"].map(isHighway63)).toEqual([false, false, false]);
    expect(ontarioUrl("events", "fr", "abc")).toBe("https://511on.ca/api/v2/get/event?format=json&lang=fr&key=abc");
    expect(ontarioUrlForLog("events", "fr")).toBe("https://511on.ca/api/v2/get/event?format=json&lang=fr&key=***");
  });

  it("not an array → failure; no Highway 63 conditions → failure", () => {
    expect(() => parseOntarioItems("events", { Message: "Invalid key" }, [])).toThrow(/not a JSON array/);
    expect(() => parseOntarioConditions(json("hand-made/on-conditions-no63-en.json"), json("hand-made/on-conditions-no63-fr.json"))).toThrow(/Highway 63/);
  });
});

describe("Ontario 511 (hand-made)", () => {
  it("a full closure on HWY 63 is a closure in both languages; HWY 630 is left out", () => {
    const { items } = parseOntarioItems("events", json("hand-made/on-event-63-closure-en.json"), json("hand-made/on-event-63-closure-fr.json"));
    expect(items).toHaveLength(1);
    const c = items[0];
    expect([c.id, c.kind, c.road, c.title_en, c.title_fr, c.original_language]).toEqual(["on-event-900100", "closure", "63", "Road closed", "Route fermée", "both"]);
    expect(c.body_en).toContain("ALL LANES CLOSED");
    expect(c.body_fr).toContain("TOUTES LES VOIES FERMÉES");
    expect(c.starts_at).toEqual(new Date("2026-11-03T11:00:00Z"));
  });

  it("snow packed with drifting is flagged; 'No Report' is neither flagged nor 'clear'", () => {
    const [snow] = parseOntarioConditions(json("hand-made/on-conditions-snow-en.json"), json("hand-made/on-conditions-snow-fr.json"));
    expect([snow.surface_en, snow.surface_fr, snow.surface_ok, snow.visibility_ok, snow.drifting]).toEqual(
      ["Snow packed, Partly snow covered", "Neige durcie, Partiellement enneigée", false, false, true]);
    const [nr] = parseOntarioConditions(json("hand-made/on-conditions-noreport-en.json"), json("hand-made/on-conditions-noreport-fr.json"));
    expect([nr.no_report, nr.surface_ok, nr.surface_fr]).toEqual([true, true, "Aucun rapport"]);
  });
});

describe("Town Work Info (real files, 2026-10-22)", () => {
  it("item 1019 in both languages, in effect 1–31 October", () => {
    const fr = parseTownList(text(`${QC}/town-list-fr.html`));
    const en = parseTownList(text(`${QC}/town-list-en.html`));
    expect(fr.map((i) => i.id)).toEqual(["1019"]);
    expect(en[0].title).toBe("WATER SYSTEM FLUSHING | MONTH OF OCTOBER");
    expect(fr[0].starts_at).toEqual(new Date("2026-10-01T04:00:00Z"));
    expect(fr[0].ends_at).toEqual(new Date("2026-11-01T04:00:00Z")); // midnight after 31 Oct
    expect(en[0].ends_at).toEqual(fr[0].ends_at);
    const items = buildTownItems({ fr, en }, {
      fr: new Map([["1019", parseTownDetail(text(`${QC}/town-detail-fr-1019.html`))]]),
      en: new Map([["1019", parseTownDetail(text(`${QC}/town-detail-en-1019.html`))]]),
    });
    expect(items).toHaveLength(1);
    const t = items[0];
    expect([t.id, t.kind, t.original_language, t.title_fr]).toEqual(["town-1019", "town", "both", "RINÇAGE DU RÉSEAU D'AQUEDUC | MOIS D'OCTOBRE"]);
    expect(t.body_fr).toMatch(/^Au cours du mois d'octobre/);
    expect(t.body_en).toMatch(/^Throughout the month of October/);
    expect(t.source_url_en).toBe("https://www.temiscaming.net/en/work-info/1019/water-system-flushing-month-of-october");
    expect(isCurrent(t, new Date("2026-10-31T23:00:00Z"))).toBe(true);
    expect(isCurrent(t, new Date("2026-11-01T05:00:00Z"))).toBe(false); // hidden after its end date
    expect(onToday(t, OCT22)).toBe(false); // Town work never goes on Today
  });

  it("an item page keeps its paragraphs", () => {
    const d = parseTownDetail(text(`${QC}/town-detail-en-757.html`));
    expect(d.title).toBe("Kipawa Road disruption");
    expect(d.body).toBe(
      "Please note that Kipawa Road is currently closed this morning near Restoroute due to a damaged utility pole. " +
      "Authorities are awaiting intervention from Hydro-Québec to make the repairs.\n\n" +
      "We advise you to plan your travels accordingly and opt for an alternative route, Highway 101.\n\n" +
      "Thank you for your understanding.",
    );
  });

  it("a page that isn't the Work Info list is a failure", () => {
    expect(() => parseTownList("<html><h1 class='page-title'>Page introuvable</h1></html>")).toThrow(/unexpected page title/);
    expect(() => parseTownList(
      "<h1 class='page-title'>Work Info</h1><div><a href='https://x/en/work-info/55/new-layout'>New</a></div>",
    )).toThrow(/couldn't read listed items 55/);
  });

  it("end dates in both languages", () => {
    expect(parseEndDate("En vigueur du jeudi 1 octobre 2026 au samedi 31 octobre 2026.")).toEqual(new Date("2026-11-01T04:00:00Z"));
    expect(parseEndDate("In effect from Tuesday November 26, 2024 to Tuesday November 26, 2024.")).toEqual(new Date("2024-11-27T05:00:00Z"));
    expect(parseEndDate("En vigueur du 1er décembre 2026 au 1er décembre 2026")).toEqual(new Date("2026-12-02T05:00:00Z"));
    expect(parseEndDate("En vigueur dès maintenant")).toBeNull();
  });
});
