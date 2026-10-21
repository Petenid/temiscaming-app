// Open-Meteo → 7 days for Témiscaming (spec weather D1). Open-Meteo's GEM
// endpoint blends Environment Canada's own models (HRDPS 2.5 km, RDPS, GEM
// global) for one point. It gives numbers and a WMO weather code per day,
// no text: the app shows our own French and English label for each code.

export const FORECAST_POINT = { latitude: 46.7213, longitude: -79.0975 };

const DAILY = [
  "weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_sum",
  "rain_sum", "snowfall_sum", "wind_speed_10m_max", "wind_gusts_10m_max",
  "wind_direction_10m_dominant", "sunrise", "sunset",
] as const;

export const FORECAST_URL =
  "https://api.open-meteo.com/v1/gem" +
  `?latitude=${FORECAST_POINT.latitude}&longitude=${FORECAST_POINT.longitude}` +
  "&timezone=America%2FToronto&forecast_days=7" +
  `&daily=${DAILY.join(",")}`;

/** Units we show. Anything else means the request or the API changed. */
const UNITS: Record<string, string> = {
  time: "iso8601",
  weather_code: "wmo code",
  temperature_2m_max: "°C",
  temperature_2m_min: "°C",
  precipitation_sum: "mm",
  rain_sum: "mm",
  snowfall_sum: "cm",
  wind_speed_10m_max: "km/h",
  wind_gusts_10m_max: "km/h",
  wind_direction_10m_dominant: "°",
  sunrise: "iso8601",
  sunset: "iso8601",
};

/** WMO codes Open-Meteo documents. The app has a label for each (spec D6). */
export const WMO_CODES = [
  0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77,
  80, 81, 82, 85, 86, 95, 96, 99,
];

export interface ForecastDay {
  /** Local date in Témiscaming, "2026-10-21". */
  date: string;
  wmo_code: number;
  high_c: number;
  low_c: number;
  precip_mm: number | null;
  rain_mm: number | null;
  snow_cm: number | null;
  wind_max_kmh: number | null;
  gust_max_kmh: number | null;
  wind_dir_deg: number | null;
  /** Local time, "2026-10-21T07:42". */
  sunrise: string | null;
  sunset: string | null;
}

export interface ForecastResult {
  days: ForecastDay[];
  warnings: string[];
}

type Json = Record<string, unknown>;
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);
const str = (v: unknown) => (typeof v === "string" && v ? v : null);

/** Throws with a short reason when the forecast isn't usable (the caller records it). */
export function parseForecast(json: unknown): ForecastResult {
  const root = json as Json | null;
  if (!root || typeof root !== "object") throw new Error("forecast: not JSON");
  if (root.error) throw new Error(`forecast: Open-Meteo says "${String(root.reason ?? "error")}"`);

  // The grid cell must be ours; a typo in the coordinates would give another town's weather.
  const lat = num(root.latitude);
  const lon = num(root.longitude);
  if (lat === null || lon === null ||
      Math.abs(lat - FORECAST_POINT.latitude) > 0.1 || Math.abs(lon - FORECAST_POINT.longitude) > 0.1) {
    throw new Error(`forecast: for ${lat}, ${lon}, not Témiscaming`);
  }
  if (root.timezone !== "America/Toronto") throw new Error(`forecast: timezone ${String(root.timezone)}`);

  const units = (root.daily_units ?? {}) as Json;
  for (const [k, want] of Object.entries(UNITS)) {
    if (units[k] !== want) throw new Error(`forecast: ${k} in "${String(units[k])}", expected "${want}"`);
  }

  const daily = (root.daily ?? {}) as Record<string, unknown[]>;
  const time = daily.time;
  if (!Array.isArray(time) || time.length < 7) {
    throw new Error(`forecast: ${Array.isArray(time) ? time.length : 0} days, expected 7`);
  }
  for (const k of DAILY) {
    if (!Array.isArray(daily[k]) || daily[k].length !== time.length) {
      throw new Error(`forecast: "${k}" doesn't have one value per day`);
    }
  }

  const warnings: string[] = [];
  const days: ForecastDay[] = time.map((t, i) => {
    const date = str(t);
    const code = num(daily.weather_code[i]);
    const high = num(daily.temperature_2m_max[i]);
    const low = num(daily.temperature_2m_min[i]);
    // Code, high and low are what every row shows: without them the day is unusable.
    if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date) || code === null || high === null || low === null) {
      throw new Error(`forecast: day ${i + 1} is missing its date, code or temperatures`);
    }
    if (!WMO_CODES.includes(code)) warnings.push(`forecast ${date}: unknown weather code ${code}`);
    return {
      date,
      wmo_code: code,
      high_c: high,
      low_c: low,
      precip_mm: num(daily.precipitation_sum[i]),
      rain_mm: num(daily.rain_sum[i]),
      snow_cm: num(daily.snowfall_sum[i]),
      wind_max_kmh: num(daily.wind_speed_10m_max[i]),
      gust_max_kmh: num(daily.wind_gusts_10m_max[i]),
      wind_dir_deg: num(daily.wind_direction_10m_dominant[i]),
      sunrise: str(daily.sunrise[i]),
      sunset: str(daily.sunset[i]),
    };
  });
  return { days: days.slice(0, 7), warnings };
}
