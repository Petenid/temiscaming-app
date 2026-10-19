// Entry point: the Cloud Functions Firebase deploys.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { fcmMessenger, firestoreStore, webFetcher } from "./adapters";
import { runPoll } from "./alerts/sync";

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
