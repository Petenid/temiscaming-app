// Point-in-polygon on ECCC's real forecast-zone outlines around town
// (spec weather §2: the town sits on the Quebec–Ontario zone border).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { contains, coversTown, Geometry, Point, TOWN_POINTS } from "../src/weather/geo";

const DIR = join(__dirname, "fixtures/weather/2026-10-21-0025");
const zones: { properties: { NAME: string }; geometry: Geometry }[] =
  JSON.parse(readFileSync(join(DIR, "zones-town.json"), "utf-8")).features;
const zone = (name: string) => zones.find((z) => z.properties.NAME === name)!.geometry;

const temiscamingue = zone("Témiscamingue");
const northBay = zone("North Bay - West Nipissing");
const kirkland = zone("Kirkland Lake - Temiskaming Shores - Temagami");

describe("ECCC zones around Témiscaming", () => {
  it("puts the town centre and Lumsden in Témiscamingue only", () => {
    for (const { point } of TOWN_POINTS) {
      expect(contains(temiscamingue, point)).toBe(true);
      expect(contains(northBay, point)).toBe(false);
      expect(contains(kirkland, point)).toBe(false);
    }
    expect(coversTown(temiscamingue)).toBe(true);
    expect(coversTown(northBay)).toBe(false);
  });

  it("puts the dam station's rounded position on the Ontario side (why a box isn't enough)", () => {
    const dam: Point = [-79.1, 46.71];
    expect(contains(northBay, dam)).toBe(true);
    expect(contains(temiscamingue, dam)).toBe(false);
  });
});

describe("contains", () => {
  const square = (x0: number, y0: number, x1: number, y1: number) =>
    [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]];

  it("leaves out holes", () => {
    const withHole: Geometry = { type: "Polygon", coordinates: [square(0, 0, 10, 10), square(4, 4, 6, 6)] };
    expect(contains(withHole, [2, 2])).toBe(true);
    expect(contains(withHole, [5, 5])).toBe(false);
  });

  it("checks every part of a MultiPolygon", () => {
    const two: Geometry = { type: "MultiPolygon", coordinates: [[square(0, 0, 1, 1)], [square(5, 5, 6, 6)]] };
    expect(contains(two, [5.5, 5.5])).toBe(true);
    expect(contains(two, [3, 3])).toBe(false);
  });

  it("says no for other shapes and missing geometry", () => {
    expect(contains({ type: "Point", coordinates: [-79.0975, 46.7213] }, [-79.0975, 46.7213])).toBe(false);
    expect(contains(null, [0, 0])).toBe(false);
    expect(contains({ type: "Polygon", coordinates: [] }, [0, 0])).toBe(false);
  });
});
