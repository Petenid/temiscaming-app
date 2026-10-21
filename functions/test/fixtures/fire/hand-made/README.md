# Hand-made fire-ban fixtures

No ban was in effect in Quebec when Milestone 6 was built (the last one was
lifted on 2026-07-20), so these files are **made by hand**. They copy the real
files' structure and property names (`mes_prev`, `date_eff`, `heure_eff`, see
`../2026-10-21/`), but the polygons are rough boxes, not real territories:

| File | Shape | Expected state |
|---|---|---|
| `ifco-temiscamingue.json` | box around the MRC de Témiscamingue, starts 2026-10-22 8h | `town` |
| `ifco-rouyn-abitibi.json` | Rouyn-Noranda + Abitibi (like the July 2026 ban) | `region` |
| `ifco-cote-nord.json` | Côte-Nord only | `none` |
| `icaf-east-of-town.json` | forest east of town, 4–7 km away | `around` |
| `ifco-empty.json` | no features (the publisher's documented "none" case) | failure |

Next time a real ban is issued anywhere in Quebec, run the *Capture fixtures*
workflow with `fire` and compare (spec fire-bans §8 step 4).
