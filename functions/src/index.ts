// Entry point: the Cloud Functions Firebase deploys.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import {
  fcmMessenger, firestoreCollectionStore, firestoreEventsStore, firestoreFireStore, firestoreStore,
  firestoreRoadsStore, firestoreWeatherStore, webFetcher,
} from "./adapters";
import { runPoll } from "./alerts/sync";
import { MrcCalendar } from "./collection/merge";
import { CalendarDownload, runCollectionPoll } from "./collection/sync";
import { runEventsPoll } from "./events/sync";
import { runFireBanPoll } from "./fire/sync";
import { runRoadsPoll, runTownWorkInfoPoll } from "./roads/sync";
import { runForecastPoll, runWeatherPoll } from "./weather/sync";

initializeApp();

/** Checks the Town's alert site every 10 minutes (spec §3 D3). */
export const pollTownAlerts = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1", // Montréal, next to the database
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 0, // the next scheduled run is the retry
    maxInstances: 1, // never two runs at once
  },
  async () => {
    const result = await runPoll({
      store: firestoreStore(getFirestore()),
      fetcher: webFetcher,
      messenger: fcmMessenger(getMessaging()),
      now: () => new Date(),
      log: (message) => logger.info(message),
    });
    if (!result.ok) logger.warn("town alerts poll failed", { error: result.error });
  },
);

/** The MRC calendars shipped with the code (functions/data/mrc-<year>.json, spec D4). */
function loadMrcCalendars(): MrcCalendar[] {
  const dir = join(__dirname, "..", "data");
  return readdirSync(dir)
    .filter((f) => /^mrc-\d{4}\.json$/.test(f))
    .map((f) => JSON.parse(readFileSync(join(dir, f), "utf-8")) as MrcCalendar);
}

/**
 * Reads the Town's calendar every 2 hours: bin pickups (Milestone 2, spec D2),
 * then events from the same pages (Milestone 3, events spec D1). Each step
 * records its own health, and a problem in one never stops the other.
 */
export const pollTownCalendar = onSchedule(
  {
    schedule: "every 2 hours",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 180,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
  },
  async () => {
    const log = (message: string) => logger.info(message);
    let download: CalendarDownload | { error: string } = { error: "calendar run stopped before downloading" };
    try {
      const result = await runCollectionPoll({
        store: firestoreCollectionStore(getFirestore()),
        fetcher: webFetcher,
        messenger: fcmMessenger(getMessaging()),
        mrc: loadMrcCalendars(),
        now: () => new Date(),
        log,
      });
      if (!result.ok) logger.warn("calendar poll failed", { error: result.error });
      download = result.download ?? { error: result.error ?? "download failed" };
    } catch (e) {
      logger.error("calendar poll crashed", { error: (e as Error).message });
    }
    try {
      const events = await runEventsPoll({ store: firestoreEventsStore(getFirestore()), now: () => new Date(), log }, download);
      if (!events.ok) logger.warn("events step failed", { error: events.error });
    } catch (e) {
      logger.error("events step crashed", { error: (e as Error).message });
    }
  },
);

/**
 * Environment Canada every 15 minutes (weather spec D3): conditions at the
 * Barrage Témiscaming station, then weather alerts covering the town. Each
 * step records its own health; one failing never stops the other.
 */
export const pollWeather = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
  },
  async () => {
    const r = await runWeatherPoll({
      store: firestoreWeatherStore(getFirestore()),
      fetcher: webFetcher,
      now: () => new Date(),
      log: (message) => logger.info(message),
    });
    if (!r.conditions.ok) logger.warn("weather conditions failed", { error: r.conditions.error });
    if (!r.alerts.ok) logger.warn("weather alerts failed", { error: r.alerts.error });
  },
);

/** The Open-Meteo forecast for Témiscaming, every hour (weather spec D1, D3). */
export const pollForecast = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 60,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
  },
  async () => {
    const r = await runForecastPoll({
      store: firestoreWeatherStore(getFirestore()),
      fetcher: webFetcher,
      now: () => new Date(),
      log: (message) => logger.info(message),
    });
    if (!r.ok) logger.warn("forecast failed", { error: r.error });
  },
);

/**
 * Quebec's open-fire ban (IFCO) and forest access ban (ICAF), every 30 minutes
 * (fire-bans spec D4). Pushes when a ban starts, is announced or lifts for
 * Témiscaming (D5). Each layer records its own health.
 */
export const pollFireBans = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
  },
  async () => {
    const r = await runFireBanPoll({
      store: firestoreFireStore(getFirestore()),
      fetcher: webFetcher,
      messenger: fcmMessenger(getMessaging()),
      now: () => new Date(),
      log: (message) => logger.info(message),
    });
    if (!r.ifco.ok) logger.warn("fire ban (IFCO) failed", { error: r.ifco.error });
    if (!r.icaf.ok) logger.warn("forest access ban (ICAF) failed", { error: r.icaf.error });
  },
);

/** The Ontario 511 developer key (roads spec D15): `firebase functions:secrets:set ONTARIO_511_KEY`. */
const ontario511Key = defineSecret("ONTARIO_511_KEY");

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * Route 101 (Quebec) and Highway 63 (Ontario), every 15 minutes (roads spec
 * D4): closures, incidents, roadworks, conditions, cameras once a day. Pushes
 * when a road on our stretch closes or reopens (D7). Ontario calls are paced
 * 7 s apart, so a run takes about a minute.
 */
export const pollRoads = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 180,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
    secrets: [ontario511Key],
  },
  async () => {
    const r = await runRoadsPoll({
      store: firestoreRoadsStore(getFirestore()),
      fetcher: webFetcher,
      messenger: fcmMessenger(getMessaging()),
      now: () => new Date(),
      sleep,
      ontarioKey: ontario511Key.value(),
      log: (message) => logger.info(message),
    });
    if (!r.ok) logger.warn("roads poll had failures", { sources: r.sources });
  },
);

/** The Town's Work Info pages, every hour (roads spec D4). No pushes. */
export const pollTownWorkInfo = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "America/Toronto",
    region: "northamerica-northeast1",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 0,
    maxInstances: 1,
  },
  async () => {
    const r = await runTownWorkInfoPoll({
      store: firestoreRoadsStore(getFirestore()),
      fetcher: webFetcher,
      now: () => new Date(),
      sleep,
      log: (message) => logger.info(message),
    });
    if (!r.ok) logger.warn("town work info failed", { error: r.error });
  },
);
