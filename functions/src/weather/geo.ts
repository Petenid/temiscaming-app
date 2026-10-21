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

// --- Distance (fire bans spec D2) ---
// The forest access ban covers public forest land and may leave the town
// itself out, so for it we ask "how close does the area come?" instead.

/** Kilometres per degree of latitude (the Earth's mean radius × π / 180). */
const KM_PER_DEG = 6371.0088 * (Math.PI / 180);

/**
 * Shortest distance (km) from `p` to the segment a–b, on a flat map centred on
 * `p`. Degrees of longitude are shrunk by cos(latitude): accurate to well under
 * 1% at the distances we care about (up to ~150 km).
 */
function segmentKm([px, py]: Point, a: number[], b: number[]): number {
  const kx = KM_PER_DEG * Math.cos((py * Math.PI) / 180);
  const ky = KM_PER_DEG;
  const ax = (a[0] - px) * kx, ay = (a[1] - py) * ky;
  const bx = (b[0] - px) * kx, by = (b[1] - py) * ky;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  // Where along a–b the closest point is (0 = a, 1 = b), kept on the segment.
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2));
  return Math.hypot(ax + t * dx, ay + t * dy);
}

function polygonsOf(geometry: Geometry | null | undefined): Ring[][] {
  if (!geometry || !Array.isArray(geometry.coordinates)) return [];
  if (geometry.type === "Polygon") return [geometry.coordinates as Ring[]];
  if (geometry.type === "MultiPolygon") return geometry.coordinates as Ring[][];
  return [];
}

/**
 * Distance (km) from `p` to an area: 0 if inside, otherwise to its nearest
 * edge (holes count as edges, so a point in a hole gets the distance to the
 * hole's border). Infinity for anything that isn't a Polygon/MultiPolygon.
 */
export function distanceKm(geometry: Geometry | null | undefined, p: Point): number {
  if (contains(geometry, p)) return 0;
  let best = Infinity;
  for (const rings of polygonsOf(geometry)) {
    for (const ring of rings) {
      for (let i = 1; i < ring.length; i++) best = Math.min(best, segmentKm(p, ring[i - 1], ring[i]));
    }
  }
  return best;
}

/** Distance (km) from the nearer of the town centre and Lumsden. */
export function distanceFromTownKm(geometry: Geometry | null | undefined): number {
  return Math.min(...TOWN_POINTS.map(({ point }) => distanceKm(geometry, point)));
}
