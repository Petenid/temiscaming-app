# Hand-made road fixtures (not real captures)

Made from the real files in `../2026-10-22/` and `../2026-10-23/` by editing a few
fields, to test situations that weren't happening on capture day (roads spec §8).
Each file's IDs start with 9001… so they can't be mistaken for real items.

- `qc-warnings-closure-101.json` — a *Fermeture* on Route 101 at Saint-Édouard-de-Fabre
  with a blank `numeroRoute`; *Fermeture de 1 voie sur 2* in Témiscaming; a *Fermeture*
  on Route 101 at Rouyn-Noranda (not our stretch).
- `qc-warnings-empty.json`, `qc-conditions-empty.json` — valid, empty answers.
- `qc-roadworks-planned-closure.json` — a night closure on Route 101 starting 10 Nov 2026,
  plus the real Duhamel-Ouest roadwork (just past our stretch).
- `qc-conditions-icy.json` — the real segments with 3001 icy, poor visibility, drifts.
- `on-event-63-closure-{en,fr}.json` — the real events plus a full closure on Highway 63
  near Highway 533, and a closure on Highway 630 (must be left out).
- `on-conditions-snow-{en,fr}.json` — Highway 63 snow packed, poor visibility, drifting.
- `on-conditions-noreport-{en,fr}.json` — Highway 63 "No Report".
- `on-conditions-no63-{en,fr}.json` — Highway 63 missing (must be a failure).
