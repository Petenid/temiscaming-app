// Is a measure in effect for Témiscaming? (spec fire-bans D2)
//   IFCO (open-fire ban): "town" when an area contains the town centre or Lumsden.
//     Bans are drawn by whole territories (MRCs), so the point test is exact.
//   ICAF (forest access ban): "around" when an area comes within 15 km. It covers
//     public forest land and may leave the town itself out.
//   Either: "region" when farther, but within 150 km (all of Abitibi-
//     Témiscamingue's nearer half: Ville-Marie ~90 km, Rouyn-Noranda ~130 km).
//     Shown on the Fire screen only — no banner, no push.
import { distanceFromTownKm } from "../weather/geo";
import { LayerId, ParsedLayer } from "./parse";

export const AROUND_KM = 15;
export const REGION_KM = 150;

export type LayerState = "town" | "around" | "region" | "none";

/** The state that means "here" for each layer: banner and push. */
export const HERE: Record<LayerId, LayerState> = { ifco: "town", icaf: "around" };

export interface LayerStatus {
  state: LayerState;
  /** When the measure that applies here starts (earliest if several); may be future. */
  starts_at: Date | null;
  /** When the last measure was lifted (only when nothing is in effect anywhere). */
  none_since: Date | null;
  /** Distance from town to the nearest measure, rounded to the km; null if none. */
  nearest_km: number | null;
}

export function layerStatus(layer: LayerId, parsed: ParsedLayer): LayerStatus {
  const withDistance = parsed.measures.map((m) => ({ m, km: distanceFromTownKm(m.geometry) }));
  const hereLimit = layer === "ifco" ? 0 : AROUND_KM;
  const here = withDistance.filter(({ km }) => km <= hereLimit);
  const nearest = withDistance.length ? Math.min(...withDistance.map(({ km }) => km)) : null;

  let state: LayerState = "none";
  if (here.length) state = HERE[layer];
  else if (nearest !== null && nearest <= REGION_KM) state = "region";

  const starts = here.map(({ m }) => m.startsAt.getTime());
  return {
    state,
    starts_at: starts.length ? new Date(Math.min(...starts)) : null,
    none_since: parsed.measures.length ? null : parsed.noneSince,
    nearest_km: nearest === null ? null : Math.round(nearest),
  };
}

export const isHere = (layer: LayerId, s: LayerState) => s === HERE[layer];
