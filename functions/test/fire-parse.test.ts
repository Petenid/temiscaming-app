// Reading the ministry's fire-ban layers and deciding what they mean for
// Témiscaming (spec fire-bans D2, D3, §8 step 1).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { parseEffective, parseLayer } from "../src/fire/parse";
import { layerStatus } from "../src/fire/status";
import { distanceFromTownKm, distanceKm, Point } from "../src/weather/geo";

const FIX = join(__dirname, "fixtures/fire");
const load = (path: string) => JSON.parse(readFileSync(join(FIX, path), "utf-8"));

describe("parseLayer — the real files (no ban in Quebec, 2026-10-21)", () => {
  it.each(["ifco", "icaf"] as const)("%s: the AUCUNE placeholder means none since 20 July, noon", (layer) => {
    const parsed = parseLayer(layer, load(`2026-10-21/${layer}.json`));
    expect(parsed.measures).toEqual([]);
    expect(parsed.featureCount).toBe(1);
    expect(parsed.noneSince).toEqual(new Date("2026-07-20T16:00:00Z")); // 12h EDT
    expect(layerStatus(layer, parsed)).toEqual({
      state: "none", starts_at: null, none_since: new Date("2026-07-20T16:00:00Z"), nearest_km: null,
    });
  });
});

describe("parseLayer — refuses what it can't trust (spec D3)", () => {
  it("an empty collection is a failure, not 'no ban'", () => {
    expect(() => parseLayer("ifco", load("hand-made/ifco-empty.json"))).toThrow(/no features/);
  });
  it("not GeoJSON", () => {
    expect(() => parseLayer("ifco", { error: "service unavailable" })).toThrow(/FeatureCollection/);
    expect(() => parseLayer("ifco", null)).toThrow(/FeatureCollection/);
  });
  it("the wrong layer", () => {
    expect(() => parseLayer("icaf", load("2026-10-21/ifco.json"))).toThrow(/got layer/);
  });
  it("a real measure without a polygon", () => {
    const json = load("hand-made/ifco-temiscamingue.json");
    json.features[0].geometry = null;
    expect(() => parseLayer("ifco", json)).toThrow(/no polygon/);
  });
  it("an unreadable date", () => {
    const json = load("hand-made/ifco-temiscamingue.json");
    json.features[0].properties.date_eff = "22 octobre";
    expect(() => parseLayer("ifco", json)).toThrow(/unreadable date/);
  });
  it("a measure next to the placeholder: the measure wins, with a warning", () => {
    const json = load("hand-made/ifco-temiscamingue.json");
    json.features.push(load("2026-10-21/ifco.json").features[0]);
    const parsed = parseLayer("ifco", json);
    expect(parsed.measures).toHaveLength(1);
    expect(parsed.noneSince).toBeNull();
    expect(parsed.warnings[0]).toMatch(/placeholder/);
  });
});

describe("parseEffective", () => {
  it("reads the hour forms the ministry uses", () => {
    expect(parseEffective("2026-07-02", "8h")).toEqual(new Date("2026-07-02T12:00:00Z"));
    expect(parseEffective("2026-07-02", "18h")).toEqual(new Date("2026-07-02T22:00:00Z"));
    expect(parseEffective("2026-07-02", "8 h 30")).toEqual(new Date("2026-07-02T12:30:00Z"));
    expect(parseEffective("2026-12-01", "8h")).toEqual(new Date("2026-12-01T13:00:00Z")); // EST in winter
    expect(parseEffective("2026-07-02", "")).toEqual(new Date("2026-07-02T04:00:00Z")); // midnight
  });
  it("rejects nonsense", () => {
    expect(parseEffective("2026-07-02", "midi")).toBeNull();
    expect(parseEffective("2026-07-02", "25h")).toBeNull();
    expect(parseEffective(undefined, "8h")).toBeNull();
  });
});

describe("layerStatus — what it means for Témiscaming (spec D2)", () => {
  it("open-fire ban over the MRC de Témiscamingue → town, with its start", () => {
    const s = layerStatus("ifco", parseLayer("ifco", load("hand-made/ifco-temiscamingue.json")));
    expect(s).toEqual({ state: "town", starts_at: new Date("2026-10-22T12:00:00Z"), none_since: null, nearest_km: 0 });
  });
  it("a July-2026-style ban over Rouyn-Noranda and Abitibi → region only", () => {
    const s = layerStatus("ifco", parseLayer("ifco", load("hand-made/ifco-rouyn-abitibi.json")));
    expect(s.state).toBe("region");
    expect(s.starts_at).toBeNull();
    expect(s.nearest_km).toBeGreaterThan(120);
    expect(s.nearest_km).toBeLessThan(150);
  });
  it("a ban on the Côte-Nord only → none, and no 'since' date (a ban exists elsewhere)", () => {
    const s = layerStatus("ifco", parseLayer("ifco", load("hand-made/ifco-cote-nord.json")));
    expect(s).toMatchObject({ state: "none", none_since: null, starts_at: null });
  });
  it("forest access ban that leaves the town out but comes within 15 km → around", () => {
    const s = layerStatus("icaf", parseLayer("icaf", load("hand-made/icaf-east-of-town.json")));
    expect(s.state).toBe("around");
    expect(s.starts_at).toEqual(new Date("2026-10-21T16:00:00Z"));
    expect(s.nearest_km).toBe(4);
  });
  it("the same area as an open-fire ban is NOT 'town' (the point test is exact)", () => {
    const json = load("hand-made/icaf-east-of-town.json");
    json.name = "msp_interdiction_feu_ciel_ouvert_ifco";
    expect(layerStatus("ifco", parseLayer("ifco", json)).state).toBe("region");
  });
  it("forest access ban with the town cut out as a hole → around", () => {
    const json = load("hand-made/icaf-east-of-town.json");
    json.features[0].geometry = {
      type: "Polygon",
      coordinates: [
        [[-80, 46], [-78, 46], [-78, 48], [-80, 48], [-80, 46]],
        [[-79.15, 46.69], [-79.02, 46.69], [-79.02, 46.76], [-79.15, 46.76], [-79.15, 46.69]], // the town
      ],
    };
    expect(layerStatus("icaf", parseLayer("icaf", json)).state).toBe("around");
  });
});

describe("distanceKm", () => {
  const town: Point = [-79.0975, 46.7213];
  const square = (x1: number, y1: number, x2: number, y2: number) => ({
    type: "Polygon", coordinates: [[[x1, y1], [x2, y1], [x2, y2], [x1, y2], [x1, y1]]],
  });
  it("is 0 inside", () => {
    expect(distanceKm(square(-80, 46, -78, 47), town)).toBe(0);
  });
  it("matches a known distance: 0.1° of latitude due north ≈ 11.1 km", () => {
    expect(distanceKm(square(-80, 46.8213, -78, 47), town)).toBeCloseTo(11.12, 1);
  });
  it("shrinks longitude with latitude: 0.1° east at 46.7° N ≈ 7.6 km", () => {
    expect(distanceKm(square(-78.9975, 46, -78, 47), town)).toBeCloseTo(7.63, 1);
  });
  it("is Infinity for shapes that aren't areas", () => {
    expect(distanceKm({ type: "Point", coordinates: [-79, 46] }, town)).toBe(Infinity);
    expect(distanceKm(null, town)).toBe(Infinity);
  });
  it("uses the nearer of town and Lumsden", () => {
    const eastOnly = square(-79.0, 46.5, -78.3, 47.2);
    expect(distanceFromTownKm(eastOnly)).toBeCloseTo(distanceKm(eastOnly, [-79.0505, 46.735]), 5);
  });
});
