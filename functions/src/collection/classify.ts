// Decides whether a calendar entry is a pickup and, if so, which bin and
// which sector (spec §2). Also the "schedule check" (D5): anything odd is
// reported as a warning instead of being guessed at.

export type SectorId = "town" | "lumsden";
export const SECTORS: SectorId[] = ["town", "lumsden"];

/** Usual pickup day per sector, as JavaScript numbers it (Sunday = 0). */
export const SECTOR_WEEKDAY: Record<SectorId, number> = { town: 2, lumsden: 3 };

export type Material = "compost" | "recycling" | "garbage";
export type Special = "christmas-trees";

export interface Classified {
  material: Material | null;
  special: Special | null;
  /** Sectors the title names; empty means the title names an area we don't know. */
  sectors: SectorId[];
  /** Short texts for the schedule check; empty when everything looks normal. */
  warnings: string[];
}

/** Upper case without accents, so "Témiscaming" and "TEMISCAMING" match. */
export function normalize(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
}

const ICON_MATERIAL: Record<string, Material> = {
  "compost-bin": "compost",
  "recycling-bin": "recycling",
  "trash-bin": "garbage",
};

/** What the title says the material is, to cross-check the icon. */
function titleMaterial(title: string): Material | null {
  const t = normalize(title);
  if (/COMPOST/.test(t)) return "compost";
  if (/RECYCL/.test(t)) return "recycling";
  if (/ORDURES|WASTE|GARBAGE|DECHETS/.test(t)) return "garbage";
  return null;
}

/** Sectors named in the title's area part (after the dash). */
function titleSectors(title: string): { sectors: SectorId[]; area: string | null } {
  // "COLLECTE DES … -- TÉMISCAMING, LAC TEE …": the area follows "-" or "--".
  const dash = title.search(/\s-{1,2}\s/);
  if (dash < 0) return { sectors: [...SECTORS], area: null }; // no area: everyone
  const area = title.slice(dash).replace(/^\s*-{1,2}\s*/, "");
  const a = normalize(area);
  const sectors: SectorId[] = [];
  if (/TEMISCAMING|LAC TEE|CHALETS|COTTAGE/.test(a)) sectors.push("town");
  if (/LUMSDEN|LETANG/.test(a)) sectors.push("lumsden");
  return { sectors, area };
}

/**
 * Classifies one entry. Returns null when it isn't a pickup at all (council
 * meetings, shows…). Pickups are recognised by their bin or fir icon, not by
 * words in the title: a "waste management conference" is not a pickup.
 */
export function classify(entry: { icon: string | null; title: string; date: string }): Classified | null {
  const icon = entry.icon ?? "";
  const warnings: string[] = [];
  const where = `${entry.date} "${entry.title}"`;

  let material: Material | null = null;
  let special: Special | null = null;
  let variant: "a" | "b" | null = null;

  if (icon === "pm-fir") {
    special = "christmas-trees";
  } else {
    const bin = icon.match(/^pm-(.+-bin)(?:-([ab]))?$/);
    if (!bin) return null;
    material = ICON_MATERIAL[bin[1]] ?? null;
    variant = (bin[2] as "a" | "b" | undefined) ?? null;
    if (!material) {
      warnings.push(`unknown bin icon ${icon}: ${where}`);
      return { material: null, special: null, sectors: [], warnings };
    }
    const said = titleMaterial(entry.title);
    if (said && said !== material) {
      warnings.push(`icon says ${material} but title says ${said}: ${where}`);
    }
  }

  const { sectors, area } = titleSectors(entry.title);
  if (sectors.length === 0) {
    warnings.push(`unfamiliar area "${area}": ${where}`);
  }
  // Icons "a" and "b" have always meant town and Lumsden/Letang (spec §2).
  if (variant && sectors.length === 1) {
    const iconSector: SectorId = variant === "a" ? "town" : "lumsden";
    if (iconSector !== sectors[0]) {
      warnings.push(`icon ${icon} doesn't match the area in the title: ${where}`);
    }
  }
  return { material, special, sectors, warnings };
}

/** True when a bin pickup falls on a day other than the sector's usual one. */
export function isIrregular(date: string, sector: SectorId): boolean {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay() !== SECTOR_WEEKDAY[sector];
}
