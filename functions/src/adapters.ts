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
import { EVENTS_SOURCE_ID, EventsHealth, EventsStore, StoredEvent } from "./events/sync";
import { FIRE_LINKS, FIRE_SOURCE_ID, FireHealth, FireStore, StoredLayer } from "./fire/sync";
import {
  PushState, RoadsHealth, RoadsStore, StoredCameras, StoredRoadItem,
} from "./roads/sync";
import { WeatherHealth, WeatherStore } from "./weather/sync";

// Plain ASCII only: an accented letter in a request header isn't valid HTTP,
// and strict servers (Quebec's transport map server) refuse the request (403).
const USER_AGENT =
  "AlloTemis/1.0 (independent community app for Temiscaming, Quebec; https://github.com/Petenid/temiscaming-app)";

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
    async loadOverrides() {
      // Written by hand in the Firebase console (spec §5c); a handful at most.
      const snap = await db.collection("overrides").get();
      return new Map(snap.docs.map((d) => [d.id, d.data()]));
    },
  };
}

/** True when a header value is plain printable ASCII (tested). */
export function isAsciiHeader(value: string): boolean {
  return /^[\x20-\x7e]*$/.test(value);
}

export const USER_AGENT_FOR_TESTS = USER_AGENT;

export const webFetcher: Fetcher = {
  async get(url) {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT },
      signal: AbortSignal.timeout(30_000),
      redirect: "follow",
    });
    if (!res.ok) {
      // Say what the server answered, not just the code: a refusal page
      // (firewall, rate limit) usually names who refused and why. The
      // status and answer come first, since error messages are cut at 300.
      let answer = "";
      try {
        answer = (await res.text()).replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim().slice(0, 160);
      } catch {
        // no readable body
      }
      const server = res.headers.get("server") ?? "?";
      throw new Error(`HTTP ${res.status} (server: ${server}; "${answer}") ${url}`);
    }
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

// --- Events calendar (Milestone 3): Firestore `events` + `sources/town-events` ---

export function firestoreEventsStore(db: Firestore): EventsStore {
  const events = db.collection("events");
  const health = db.collection("sources").doc(EVENTS_SOURCE_ID);
  return {
    async loadEvents() {
      // The backend keeps only upcoming events: a few dozen documents.
      const snap = await events.get();
      return snap.docs.map((d) => toDates<StoredEvent>(d.data()));
    },
    async saveEvents(docs) {
      for (let i = 0; i < docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of docs.slice(i, i + 400)) batch.set(events.doc(doc.id), doc);
        await batch.commit();
      }
    },
    async deleteEvents(ids) {
      for (let i = 0; i < ids.length; i += 400) {
        const batch = db.batch();
        for (const id of ids.slice(i, i + 400)) batch.delete(events.doc(id));
        await batch.commit();
      }
    },
    async loadHealth() {
      const snap = await health.get();
      return snap.exists ? toDates<EventsHealth>(snap.data()!) : null;
    },
    async saveHealth(h) {
      await health.set(h);
    },
  };
}

// --- Weather (Milestone 4): Firestore `weather/temiscaming` + three `sources/…` ---

export function firestoreWeatherStore(db: Firestore): WeatherStore {
  const doc = db.collection("weather").doc("temiscaming");
  const sources = db.collection("sources");
  return {
    async saveWeather(fields) {
      // merge: each step writes only its own fields (spec D9). Every field it
      // owns is always written (null when absent), so nothing stale survives.
      await doc.set(fields, { merge: true });
    },
    async loadHealth(id) {
      const snap = await sources.doc(id).get();
      return snap.exists ? toDates<WeatherHealth>(snap.data()!) : null;
    },
    async saveHealth(id, h) {
      await sources.doc(id).set(h);
    },
  };
}

// --- Fire bans (Milestone 6): Firestore `fire/temiscaming` + `sources/msi-ifco`, `sources/msi-icaf` ---

export function firestoreFireStore(db: Firestore): FireStore {
  const doc = db.collection("fire").doc("temiscaming");
  const sources = db.collection("sources");
  return {
    async loadFire() {
      const snap = await doc.get();
      if (!snap.exists) return {};
      const data = snap.data()!;
      const out: { ifco?: StoredLayer; icaf?: StoredLayer } = {};
      for (const layer of ["ifco", "icaf"] as const) {
        if (data[layer]) out[layer] = toDates<StoredLayer>(data[layer]);
      }
      return out;
    },
    async saveLayer(layer, fields) {
      // mergeFields replaces this layer's whole map (nothing stale survives
      // inside it) and leaves the other layer alone (spec D11).
      const links = Object.keys(FIRE_LINKS);
      await doc.set({ [layer]: fields, ...FIRE_LINKS }, { mergeFields: [layer, ...links] });
    },
    async loadHealth(layer) {
      const snap = await sources.doc(FIRE_SOURCE_ID[layer]).get();
      return snap.exists ? toDates<FireHealth>(snap.data()!) : null;
    },
    async saveHealth(layer, h) {
      await sources.doc(FIRE_SOURCE_ID[layer]).set(h);
    },
  };
}

// --- Roads (Milestone 7): `roads`, `road_conditions`, `road_cameras`, backend-only `roads_state/pushes` ---

export function firestoreRoadsStore(db: Firestore): RoadsStore {
  const items = db.collection("roads");
  const sources = db.collection("sources");
  const pushes = db.collection("roads_state").doc("pushes");
  const cameras = db.collection("road_cameras").doc("highway-63");
  return {
    async loadItems() {
      // Only what's on our stretches plus the Town's work: a handful of documents.
      const snap = await items.get();
      return snap.docs.map((d) => toDates<StoredRoadItem>(d.data()));
    },
    async saveItems(docs) {
      for (let i = 0; i < docs.length; i += 400) {
        const batch = db.batch();
        for (const doc of docs.slice(i, i + 400)) batch.set(items.doc(doc.id), doc);
        await batch.commit();
      }
    },
    async deleteItems(ids) {
      for (let i = 0; i < ids.length; i += 400) {
        const batch = db.batch();
        for (const id of ids.slice(i, i + 400)) batch.delete(items.doc(id));
        await batch.commit();
      }
    },
    async saveConditions(id, doc) {
      await db.collection("road_conditions").doc(id).set(doc);
    },
    async loadCameras() {
      const snap = await cameras.get();
      return snap.exists ? toDates<StoredCameras>(snap.data()!) : null;
    },
    async saveCameras(doc) {
      await cameras.set(doc);
    },
    async loadPushState() {
      const snap = await pushes.get();
      return snap.exists ? toDates<PushState>(snap.data()!) : null;
    },
    async savePushState(state) {
      await pushes.set(state);
    },
    async loadHealth(id) {
      const snap = await sources.doc(id).get();
      return snap.exists ? toDates<RoadsHealth>(snap.data()!) : null;
    },
    async saveHealth(id, h) {
      await sources.doc(id).set(h);
    },
  };
}
