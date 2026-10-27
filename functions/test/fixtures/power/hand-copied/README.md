# Copied by hand, not downloaded byte for byte

`places-temiscamingue-2026-10-27.json` — Hydro-Québec's own list of places
(`infopannes.solutions.hydroquebec.com/assets/data/bilan-par-region.json`),
trimmed to the MRC de Témiscamingue: its municipalities (level 2, the
government's 5-digit codes used in the planned-interruption file) and the
localities under them (level 3, Hydro-Québec's 4-digit IDs used in the
current-outage file). Only `id`, `parentId`, `level` and `nom` are kept.

It was read in the Claude desktop app's browser on 2026-10-27 and copied
here, checked with a SHA-256 of the text. *Capture fixtures* → `power` tries
to save the same thing, but that step failed from GitHub on
2026-10-27, so this copy is what the tests use to tie our IDs to their names.
