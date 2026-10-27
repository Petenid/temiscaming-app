// Which stretch of road is "ours" (roads spec D1): Route 101 from Témiscaming
// to Ville-Marie, and Highway 63 from Thorne (the Ontario end of the bridge)
// to North Bay.
//
// The two lines below were taken once from the ministries' own data and
// simplified to within 50 m of the original:
//   - Route 101: Quebec winter-conditions segments 3001 (Témiscaming →
//     Saint-Édouard-de-Fabre) + 3011 (→ Ville-Marie), captured 2026-10-22.
//   - Highway 63: Ontario 511's road-conditions line "From North Bay to
//     Thorne", captured 2026-10-23.
// An item counts when any of its points is within 1 km of the line, or within
// 10 km of the town centre (catches the interprovincial bridge and other
// provincial roads in town).
import { distanceToLineKm, Point, TOWN_POINTS } from "../weather/geo";

export type Road = "101" | "63";

/** How close (km) to the line an item must come. */
export const NEAR_LINE_KM = 1;
/** How close (km) to the town centre counts whatever the road. */
export const NEAR_TOWN_KM = 10;

export const ROUTE_101: Point[] = [
  [-79.10081, 46.71153], [-79.09971, 46.71195], [-79.10144, 46.71501], [-79.09275, 46.71625],
  [-79.08591, 46.71881], [-79.08125, 46.71907], [-79.06709, 46.72354], [-79.06515, 46.72501],
  [-79.06163, 46.73059], [-79.06205, 46.73293], [-79.06650, 46.73777], [-79.07138, 46.74688],
  [-79.07649, 46.75046], [-79.07781, 46.75288], [-79.07660, 46.75838], [-79.07812, 46.76729],
  [-79.07720, 46.78324], [-79.07447, 46.78794], [-79.07492, 46.79547], [-79.07096, 46.80250],
  [-79.07403, 46.82215], [-79.07694, 46.82555], [-79.08508, 46.83091], [-79.09175, 46.83326],
  [-79.10438, 46.83577], [-79.12590, 46.83736], [-79.13776, 46.83998], [-79.14791, 46.84123],
  [-79.15486, 46.84389], [-79.17118, 46.84549], [-79.17406, 46.84692], [-79.17667, 46.85111],
  [-79.18040, 46.85290], [-79.19248, 46.85395], [-79.20200, 46.85596], [-79.20748, 46.85600],
  [-79.24597, 46.88569], [-79.24730, 46.90109], [-79.25856, 46.92290], [-79.27276, 46.93829],
  [-79.27229, 46.94114], [-79.26370, 46.95383], [-79.25843, 46.95903], [-79.25592, 46.96330],
  [-79.25580, 46.96567], [-79.27455, 46.98875], [-79.27505, 46.99226], [-79.27200, 46.99796],
  [-79.27239, 47.00035], [-79.27724, 47.00384], [-79.28221, 47.00619], [-79.28358, 47.00820],
  [-79.28087, 47.01340], [-79.27548, 47.02028], [-79.27377, 47.02437], [-79.27532, 47.03600],
  [-79.27298, 47.04011], [-79.26943, 47.04346], [-79.26875, 47.04793], [-79.27038, 47.04945],
  [-79.27988, 47.05233], [-79.29201, 47.05996], [-79.30103, 47.06224], [-79.30902, 47.06902],
  [-79.31935, 47.07200], [-79.32125, 47.07401], [-79.32606, 47.08720], [-79.32798, 47.08975],
  [-79.34465, 47.10407], [-79.35898, 47.10897], [-79.37020, 47.11688], [-79.37443, 47.12779],
  [-79.37960, 47.13533], [-79.37700, 47.14348], [-79.37854, 47.15198], [-79.37789, 47.16022],
  [-79.37461, 47.16358], [-79.36160, 47.16777], [-79.35591, 47.17658], [-79.35692, 47.17887],
  [-79.36723, 47.18757], [-79.36744, 47.20413], [-79.37223, 47.21504], [-79.37016, 47.23272],
  [-79.37171, 47.23475], [-79.37405, 47.23561], [-79.38868, 47.23581], [-79.39170, 47.23669],
  [-79.40773, 47.25503], [-79.41132, 47.26431], [-79.41115, 47.28135], [-79.42185, 47.29399],
  [-79.43332, 47.29943], [-79.43663, 47.30316], [-79.43492, 47.31010], [-79.43613, 47.31980],
  [-79.44122, 47.32688], [-79.44076, 47.32821], [-79.43554, 47.33008], [-79.43687, 47.33182],
];
export const HIGHWAY_63: Point[] = [
  [-79.10247, 46.70820], [-79.10461, 46.70768], [-79.10457, 46.70639], [-79.09781, 46.69609],
  [-79.09601, 46.68787], [-79.08821, 46.68105], [-79.08610, 46.67709], [-79.08219, 46.67395],
  [-79.07708, 46.66648], [-79.07934, 46.65451], [-79.09264, 46.64666], [-79.09959, 46.64065],
  [-79.11078, 46.63448], [-79.12563, 46.63291], [-79.13405, 46.63432], [-79.13742, 46.63368],
  [-79.14455, 46.62708], [-79.14642, 46.62396], [-79.15289, 46.62279], [-79.16783, 46.61538],
  [-79.17201, 46.60674], [-79.17597, 46.60169], [-79.17570, 46.59955], [-79.15843, 46.56263],
  [-79.15850, 46.56071], [-79.16160, 46.55598], [-79.16184, 46.55395], [-79.15230, 46.53337],
  [-79.15223, 46.51929], [-79.15407, 46.51523], [-79.15385, 46.50568], [-79.16014, 46.49540],
  [-79.15981, 46.49358], [-79.15206, 46.48473], [-79.15311, 46.48230], [-79.17980, 46.46291],
  [-79.18044, 46.46095], [-79.17665, 46.44636], [-79.17940, 46.43787], [-79.18051, 46.43677],
  [-79.18696, 46.43443], [-79.19298, 46.42788], [-79.19907, 46.42406], [-79.20154, 46.41908],
  [-79.20572, 46.41537], [-79.22463, 46.40834], [-79.25825, 46.38526], [-79.26686, 46.38223],
  [-79.27267, 46.37900], [-79.29019, 46.37718], [-79.31052, 46.36676], [-79.32281, 46.36203],
  [-79.32423, 46.36067], [-79.32536, 46.35482], [-79.32974, 46.35240], [-79.33431, 46.34802],
  [-79.33993, 46.34506], [-79.34239, 46.33997], [-79.34667, 46.33714], [-79.37103, 46.32848],
  [-79.37607, 46.32912], [-79.38302, 46.33252], [-79.38865, 46.33236], [-79.39528, 46.33061],
  [-79.40090, 46.33160], [-79.40381, 46.33122],
];

export const ROAD_LINES: Record<Road, Point[]> = { "101": ROUTE_101, "63": HIGHWAY_63 };

const TOWN_CENTRE = TOWN_POINTS[0].point;

/** Distance (km) from `p` to the town centre. */
export function townKm(p: Point): number {
  return distanceToLineKm([TOWN_CENTRE], p);
}

/**
 * Which of our roads an item is on, or null if it isn't on our stretch.
 * `candidates` limits the answer to the roads of that province's source (a
 * Quebec item is never "on Highway 63"). Near town but not near a line: the
 * candidate whose line is closest.
 */
export function stretchOf(points: Point[], candidates: Road[]): Road | null {
  if (!points.length || !candidates.length) return null;
  let best = { road: candidates[0], km: Infinity };
  for (const road of candidates) {
    const km = Math.min(...points.map((p) => distanceToLineKm(ROAD_LINES[road], p)));
    if (km < best.km) best = { road, km };
  }
  if (best.km <= NEAR_LINE_KM) return best.road;
  if (points.some((p) => townKm(p) <= NEAR_TOWN_KM)) return best.road;
  return null;
}

/** True when a line (a conditions segment) lies along our stretch: its middle point is on it. */
export function liesAlong(line: Point[], road: Road): boolean {
  if (!line.length) return false;
  const mid = line[Math.floor(line.length / 2)];
  return distanceToLineKm(ROAD_LINES[road], mid) <= NEAR_LINE_KM;
}

/** All points of a GeoJSON geometry (LineString, MultiLineString, Point…). */
export function pointsOf(geometry: unknown): Point[] {
  const g = geometry as { coordinates?: unknown } | null;
  if (!g || !Array.isArray(g.coordinates)) return [];
  const out: Point[] = [];
  const walk = (c: unknown) => {
    if (!Array.isArray(c)) return;
    if (typeof c[0] === "number" && typeof c[1] === "number") out.push([c[0], c[1]]);
    else c.forEach(walk);
  };
  walk(g.coordinates);
  return out;
}
