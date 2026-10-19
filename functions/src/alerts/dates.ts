// Turns the alert site's publish lines into real dates.
//
// The site writes them in local Témiscaming time, in several spellings:
//   list FR:   "Publié le lundi 19 octobre 2026 à 13h58"
//   list EN:   "Published on monday 19 october 2026 in 13h58"
//   detail FR: "Publié le lundi 12 octobre 2026 à 14 h 32"
//   detail EN: "Published on monday 19 october 2026 in 13:58"

const MONTHS: Record<string, number> = {
  janvier: 1, fevrier: 2, mars: 3, avril: 4, mai: 5, juin: 6,
  juillet: 7, aout: 8, septembre: 9, octobre: 10, novembre: 11, decembre: 12,
  january: 1, february: 2, march: 3, april: 4, may: 5, june: 6,
  july: 7, august: 8, september: 9, october: 10, november: 11, december: 12,
};

/** Lower-case, no accents, no-break spaces as plain spaces: "Février" → "fevrier". */
export function fold(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[  ]/g, " ")
    .toLowerCase();
}

/** Returns the moment (UTC) described by a publish line, or null if it can't be read. */
export function parsePublished(line: string): Date | null {
  const m = fold(line).match(
    /(\d{1,2})\s+([a-z]+)\s+(\d{4})\D+?(\d{1,2})\s*[h:]\s*(\d{2})/,
  );
  if (!m) return null;
  const month = MONTHS[m[2]];
  if (!month) return null;
  return torontoToUtc(+m[3], month, +m[1], +m[4], +m[5]);
}

/**
 * Converts a wall-clock time in Témiscaming (same time zone as Toronto,
 * including daylight saving) to a UTC Date, using the system's time-zone data.
 */
export function torontoToUtc(
  year: number, month: number, day: number, hour: number, minute: number,
): Date {
  const asIfUtc = Date.UTC(year, month - 1, day, hour, minute);
  // How far Toronto is from UTC at (roughly) that moment, e.g. -4 h in summer.
  const offsetMs = (at: number) => {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Toronto",
      hourCycle: "h23",
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit",
    }).formatToParts(new Date(at));
    const get = (t: string) => +parts.find((p) => p.type === t)!.value;
    return Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute")) - at;
  };
  // Two passes handle the hours around a daylight-saving change.
  let utc = asIfUtc - offsetMs(asIfUtc);
  utc = asIfUtc - offsetMs(utc);
  return new Date(utc);
}
