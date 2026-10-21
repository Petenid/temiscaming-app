// Is a point inside an alert's area? (spec weather D2)
// Témiscaming sits right on the border between ECCC's Quebec "Témiscamingue"
// zone and Ontario's "North Bay - West Nipissing" zone, so "the alert's box
// touches town" isn't good enough: we test our exact points against the
// alert's outline.

/** [longitude, latitude], the order GeoJSON uses. */
export type Point = [number, number];

/** The two places that matter: one per collection sector (DESIGN §6.2). */
export const TOWN_POINTS: { name: string; point: Point }[] = [
  { name: "town centre", point: [-79.0975, 46.7213] },
  { name: "Lumsden", point: [-79.0505, 46.735] },
];

type Ring = number[][];

export interface Geometry {
  type: string;
  coordinates: unknown;
}

/**
 * Ray casting: count how many edges a line going east from the point
 * crosses. Odd = inside. Fine for areas this small (no curvature to worry about).
 */
function inRing([x, y]: Point, ring: Ring): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** A polygon is an outer ring plus optional holes (e.g. a lake left out). */
function inPolygon(p: Point, rings: Ring[]): boolean {
  if (!rings.length || !inRing(p, rings[0])) return false;
  return !rings.slice(1).some((hole) => inRing(p, hole));
}

/** True if `p` is inside a Polygon or MultiPolygon. Any other shape: false. */
export function contains(geometry: Geometry | null | undefined, p: Point): boolean {
  if (!geometry || !Array.isArray(geometry.coordinates)) return false;
  if (geometry.type === "Polygon") return inPolygon(p, geometry.coordinates as Ring[]);
  if (geometry.type === "MultiPolygon") {
    return (geometry.coordinates as Ring[][]).some((poly) => inPolygon(p, poly));
  }
  return false;
}

/** True if the area covers the town centre or Lumsden. */
export function coversTown(geometry: Geometry | null | undefined): boolean {
  return TOWN_POINTS.some(({ point }) => contains(geometry, point));
}
