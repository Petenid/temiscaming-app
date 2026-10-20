// Entry point: the Cloud Functions Firebase deploys.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

import { fcmMessenger, firestoreCollectionStore, firestoreStore, webFetcher } from "./adapters";
import { runPoll } from "./alerts/sync";
import { MrcCalendar } from "./collection/merge";
import { runCollectionPoll } from "./collection/sync";

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

/** Reads the Town's calendar every 2 hours for collection pickups (Milestone 2, spec D2). */
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
    const result = await runCollectionPoll({
      store: firestoreCollectionStore(getFirestore()),
      fetcher: webFetcher,
      messenger: fcmMessenger(getMessaging()),
      mrc: loadMrcCalendars(),
      now: () => new Date(),
      log: (message) => logger.info(message),
    });
    if (!result.ok) logger.warn("calendar poll failed", { error: result.error });
  },
);
