// The real implementations of the ports in alerts/sync.ts: Firestore,
// the web, and Firebase Cloud Messaging. Kept thin — the logic is in sync.ts,
// where it's tested.
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { Messaging } from "firebase-admin/messaging";

import {
  Fetcher, Messenger, SOURCE_ID, SourceHealth, Store, StoredAlert,
} from "./alerts/sync";
import {
  CalendarHealth, CollectionStore, SOURCE_ID as CALENDAR_SOURCE_ID, StoredPickup,
} from "./collection/sync";

const USER_AGENT =
  "AlloTemis/1.0 (independent community app for Témiscaming; https://github.com/Petenid/temiscaming-app)";

/** Firestore Timestamps → Dates, recursively one level deep (enough for our documents). */
function toDates<T>(data: Record<string, unknown>): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    if (v instanceof Timestamp) out[k] = v.toDate();
    else if (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date)) {
      out[k] = toDates(v as Record<string, unknown>);
    } else out[k] = v;
  }
  return out as T;
}

export function firestoreStore(db: Firestore): Store {
  const alerts = db.collection("alerts");
  const health = db.collection("sources").doc(SOURCE_ID);
  return {
    async loadAlerts() {
      const snap = await alerts.where("source", "==", SOURCE_ID).get();
      return snap.docs.map((d) => toDates<StoredAlert>(d.data()));
    },
    async saveAlerts(docs) {
      // Firestore batches hold up to 500 writes.
      for (let i = 0; i < docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of docs.slice(i, i + 400)) {
          // pushed_at belongs to claimPush; never overwrite it here.
          const { pushed_at: _ignored, ...rest } = doc;
          batch.set(alerts.doc(doc.id), rest, { merge: true });
        }
        await batch.commit();
      }
    },
    async claimPush(id, at) {
      return db.runTransaction(async (tx) => {
        const ref = alerts.doc(id);
        const snap = await tx.get(ref);
        if (!snap.exists || snap.get("pushed_at")) return false;
        tx.update(ref, { pushed_at: at });
        return true;
      });
    },
    async releasePush(id) {
      await alerts.doc(id).update({ pushed_at: null });
    },
    async loadHealth() {
      const snap = await health.get();
      return snap.exists ? toDates<SourceHealth>(snap.data()!) : null;
    },
    async saveHealth(h) {
      await health.set(h);
    },
  };
}

export const webFetcher: Fetcher = {
  async get(url) {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT },
      signal: AbortSignal.timeout(30_000),
      redirect: "follow",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
    return new Uint8Array(await res.arrayBuffer());
  },
};

export function fcmMessenger(messaging: Messaging): Messenger {
  return {
    async send(m) {
      await messaging.send({
        topic: m.topic,
        notification: { title: m.title, body: m.body },
        data: m.data ?? { alert_id: m.alertId ?? "" },
        android: {
          priority: "high",
          notification: { channelId: m.channel ?? (m.urgent ? "water_urgent" : "water_updates") },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });
    },
  };
}

// --- Collection day (Milestone 2): Firestore `collections` + `sources/town-calendar` ---

export function firestoreCollectionStore(db: Firestore): CollectionStore {
  const pickups = db.collection("collections");
  const health = db.collection("sources").doc(CALENDAR_SOURCE_ID);
  return {
    async loadPickups(fromDate) {
      const snap = await pickups.where("date", ">=", fromDate).get();
      return snap.docs.map((d) => toDates<StoredPickup>(d.data()));
    },
    async savePickups(docs) {
      for (let i = 0; i < docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of docs.slice(i, i + 400)) {
          // pushed_at belongs to claimPush; only a new change resets it to null.
          const { pushed_at, ...rest } = doc;
          batch.set(pickups.doc(doc.id), pushed_at === null ? { ...rest, pushed_at: null } : rest, { merge: true });
        }
        await batch.commit();
      }
    },
    async deletePickups(ids) {
      for (let i = 0; i < ids.length; i += 400) {
        const batch = db.batch();
        for (const id of ids.slice(i, i + 400)) batch.delete(pickups.doc(id));
        await batch.commit();
      }
    },
    async claimPush(id, at) {
      return db.runTransaction(async (tx) => {
        const ref = pickups.doc(id);
        const snap = await tx.get(ref);
        if (!snap.exists || snap.get("pushed_at")) return false;
        tx.update(ref, { pushed_at: at });
        return true;
      });
    },
    async releasePush(id) {
      await pickups.doc(id).update({ pushed_at: null });
    },
    async loadHealth() {
      const snap = await health.get();
      return snap.exists ? toDates<CalendarHealth>(snap.data()!) : null;
    },
    async saveHealth(h) {
      await health.set(h);
    },
  };
}
