#!/usr/bin/env python3
"""[M27H H1, rebuilt by M27T piece 2] Kanto wild-encounter tables, keyed by this
project's own map names.

Reads the reference's own `src/data/wild_encounters.json` — 388 entries across
240 maps, keyed by `MAP_*` constants, carrying land/water/rock-smash/fishing
tables together — and emits one readable per-field table per map, the same shape
`gen_heal_locations.py` produced for heal points.

⚠️ **FOUR RULINGS FROM ROB, 2026-08-12, ARE BAKED INTO THIS FILE. Scope of
record: `docs/m27t_encounter_authoring_scope.md`.** Each one closed a defect or
an unmade decision, and each is guarded here rather than left to convention:

1. **LEAFGREEN, DELIBERATELY** (§2.2). Every FRLG map ships TWO entries whose
   only distinguishing mark is the string `FireRed` / `LeafGreen` in
   `base_label` — nothing structural. This generator previously never read
   `base_label` at all and assigned straight into a dict keyed on map, so **the
   last entry in file order silently won**, which is LeafGreen. The shipped game
   was already LeafGreen by accident; it is now LeafGreen by decision.
   90 of the 124 pairs genuinely differ (Psyduck/Slowpoke alone covers 84 maps).

2. **FIRST TABLE PER MAP** (§2.3). Same defect, worse consequence, on the one
   map with more than two entries: Six Island Altering Cave ships **9 tables x 2
   versions**, and last-wins picked table 9 — so the game shipped an all-Smeargle
   Altering Cave nobody chose. Only table 1 (Zubat) is reachable in unmodified
   play; the 2-9 rotation needs e-Reader/Mystery Gift infrastructure, a standing
   exclusion here. ⚠️ **THIS NEEDS NO SPECIAL CASE** — "first entry per map per
   version" produces Zubat for free, which is why Altering Cave has no mention
   in the code below.

3. **KANTO SCOPE** (§2.4). ⚠️ **A GUARD, NOT A FILTER — today.** All 124
   LeafGreen-labelled maps are already `REGION_KANTO`, zero exceptions, so this
   changes nothing now and catches the day it would. It reads the `region` field
   out of each `map.json` — the same test `gen_map_import.py` uses — rather than
   inferring Kanto from the version label, so the two can disagree LOUDLY
   instead of silently agreeing. It also drops the 87 Hoenn maps this Kanto
   project was carrying tables for.

4. **THE CANONICAL CLONE, NOT THE COMMITTED SNAPSHOT** (§2.5). This read
   `data/wild_encounters.json` — an in-project copy — making it the only
   generator in the tree not going through `ref_path`. Byte-identical to the
   clone today, and the drift was recorded nowhere.
   ⚠️ **`data/wild_encounters.json` NOW HAS NO CONSUMER AT ALL.** 1.0 MB, still
   tracked. Flagged for Rob rather than deleted.

⚠️ **ALL FOUR FIELDS ARE CONVERTED NOW** (land/water/rock-smash/fishing), where
this was land-only. Water and fishing still have no runtime consumer — surfing
encounters and a fishing rod are M27E — but the data is no longer the blocker,
and converting all four in one pass is what keeps the version pick and the Kanto
scope from having to be re-decided per field later.

SPECIES RESOLUTION IS IMPORTED FROM `gen_trainer_data.py`, NOT REIMPLEMENTED.
That module already owns `normalize()`, the Nidoran gendered-form aliases, and
`_assert_no_normalize_collisions` — and `[M27B Step 4]` is the record of what a
second spelling costs: `Nidoran-female` and `Nidoran-male` both collapsed to
`NIDORAN` and one silently overwrote the other, invisible until a Kanto roster
used them. One home for the rule.

Idempotent: re-running writes byte-identical output.
"""

import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# Reuse, never re-derive — see the module docstring.
from gen_trainer_data import load_species_map, normalize, clean_token  # noqa: E402
from ref_path import REF  # noqa: E402

RAW = os.path.join(REF, "src", "data", "wild_encounters.json")
MAP_CONSTANTS = os.path.join(PROJECT, "scripts", "overworld", "map_constants.gd")
OUT_DIR = os.path.join(PROJECT, "data")

# Ruling 1: which of the two version strings in `base_label` wins.
#
# ⚠️ THE PROJECT IS LEAFGREEN IN THREE OTHER PLACES ALREADY — `[M27K K-b]`'s
# name presets, `[M27G G3a]`'s in-game trades taking the `#else LEAFGREEN`
# branch, and Leaf as the player character. This is the fourth, and the first
# one that was previously being decided by file order.
VERSION_TAG = "LeafGreen"
OTHER_VERSION_TAG = "FireRed"

# `LAND_WILD_COUNT` — source's own slot count, still exactly what the raw dump
# carries per map. Asserted against the raw data rather than trusted, because a
# mismatch would silently drop or duplicate a slot.
RAW_LAND_SLOT_COUNT = 12

# [Widened 2026-08-04, Rob's own design call — NOT reference-derived, and
# RATIFIED AS FINAL 2026-08-12 (ruling 7).] This project's own land-slot count
# and percentage curve, deliberately past source's
# 12/[20,20,10,10,10,10,5,5,4,4,1,1]. The reference clone is left untouched; the
# divergence lives here, the same way other `gen_*.py` scripts layer an explicit
# override on top of extracted source data.
#
# The 3 new slots per map are filled by REPEATING each map's own 3 rarest
# reference slots (its last 3 entries — same species, same level range) rather
# than inventing new species.
#
# ⚠️ **THE RATES ARE FINAL; THE PADDING RULE IS STILL A PLACEHOLDER.** Measured
# effect of the duplication, per map: the commonest two species drop 20% -> 15%,
# the third rises 10% -> 15%, and **the two rarest are TRIPLED, 1% -> 3%**. A
# future pass can hand-author real species into slots 12-14 instead — and under
# M27T's authored-table layer that becomes a per-map edit in the Inspector
# rather than a decision that has to be made for all 105 maps at once.
LAND_SLOT_COUNT = 15
LAND_SLOT_RATES = [15, 15, 15, 10, 10, 10, 5, 5, 4, 4, 2, 2, 1, 1, 1]
assert len(LAND_SLOT_RATES) == LAND_SLOT_COUNT, (
    "LAND_SLOT_RATES has %d entries, LAND_SLOT_COUNT says %d"
    % (len(LAND_SLOT_RATES), LAND_SLOT_COUNT))
assert sum(LAND_SLOT_RATES) == 100, (
    "LAND_SLOT_RATES sums to %d, not 100" % sum(LAND_SLOT_RATES))

# (raw field key, output filename, this project's own rate override or None).
#
# ⚠️ **ONLY LAND IS OVERRIDDEN, AND THAT IS DELIBERATE — Rob's own standing note
# from 2026-08-04, unchanged by the 2026-08-12 rulings.** He wants water and
# fishing moved off source's curves too, and was explicit that the target
# numbers come from him rather than being guessed here — the same way land's own
# 15-slot table was not picked by us. So water/rock-smash/fishing emit SOURCE's
# counts and SOURCE's rates until those numbers exist. `None` means "read the
# rates out of the reference dump", which also means they cannot go stale.
#
# Each output file is a separate sibling rather than one combined table, because
# each field gets its runtime consumer at a different time (land has one now;
# water and fishing wait on M27E) and because keeping `land_encounters.json`'s
# shape untouched is what let this rebuild land with ZERO runtime changes.
FIELDS = [
    ("land_mons", "land_encounters.json", LAND_SLOT_RATES),
    ("water_mons", "water_encounters.json", None),
    ("rock_smash_mons", "rock_smash_encounters.json", None),
    ("fishing_mons", "fishing_encounters.json", None),
]


def map_table():
    """MAP_* -> this project's own map name, from the generated table.

    Same accessor `gen_heal_locations.py` uses. The two are NOT related by a
    string transform (`MAP_SSANNE_EXTERIOR` -> `SSAnne_Exterior_Frlg`), which is
    why the table is generated rather than derived.
    """
    text = open(MAP_CONSTANTS, encoding="utf-8").read()
    return dict(re.findall(r'"(MAP_[A-Z0-9_]+)":\s*"([^"]+)"', text))


def kanto_constants():
    """The `MAP_*` ids whose own `map.json` says `REGION_KANTO` (ruling 3).

    ⚠️ Reads the REGION FIELD, not the version label. The two agree on all 124
    encounter maps today; a filter derived from `base_label` would make that
    agreement an assumption instead of something the guard below can check.
    """
    out = set()
    for path in glob.glob(os.path.join(REF, "data", "maps", "*", "map.json")):
        try:
            m = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        if m.get("region") == "REGION_KANTO" and m.get("id"):
            out.add(m["id"])
    assert out, "no REGION_KANTO maps found — has map.json's schema changed?"
    return out


def choose_entries(encounters, kanto):
    """Kanto maps only, `VERSION_TAG` only, first entry per map.

    Returns (chosen, dropped_extra, skipped_other_region) where `chosen` is
    MAP_* -> entry and `dropped_extra` is MAP_* -> how many further tables that
    map had (Altering Cave's 8, and nothing else in the corpus).
    """
    chosen = {}
    dropped_extra = {}
    skipped_other_region = set()
    kanto_with_any = set()

    for entry in encounters:
        const = entry.get("map")
        if not const:
            continue
        if const not in kanto:
            skipped_other_region.add(const)
            continue
        kanto_with_any.add(const)
        if VERSION_TAG not in entry.get("base_label", ""):
            continue
        if const in chosen:
            dropped_extra[const] = dropped_extra.get(const, 0) + 1
            continue
        chosen[const] = entry

    # ⚠️ A Kanto map with tables but no LeafGreen one would be silently dropped,
    # which is the exact failure mode ruling 1 exists to kill. Measured today:
    # all 124 have both versions, so this can only fire on a reference change.
    missing = sorted(kanto_with_any - set(chosen))
    assert not missing, (
        "%d Kanto map(s) have encounter tables but no %r variant: %s — the "
        "version split is a STRING CONVENTION in base_label, so this means "
        "either the convention changed or these maps are version-exclusive"
        % (len(missing), VERSION_TAG, missing[:8]))

    return chosen, dropped_extra, skipped_other_region


def build_slots(mons, out_count, species, const, field_key, unresolved_species):
    """Resolve one field's mons to dex numbers, padding to `out_count`.

    Returns None if any species failed to resolve — a partial slot list would
    make the rate table's own indices point at the wrong mon, so a table is
    emitted whole or not at all.
    """
    extra = out_count - len(mons)
    assert extra >= 0, (
        "%s %s: %d source slots but the output table only has %d"
        % (const, field_key, len(mons), out_count))
    if extra:
        # See LAND_SLOT_RATES — duplicates this map's own rarest entries rather
        # than inventing species. Only land has a nonzero `extra` today.
        mons = mons + mons[-extra:]

    slots = []
    for m in mons:
        lo, hi = int(m["min_level"]), int(m["max_level"])
        # ⚠️ A GUARD, NOT A REPAIR. Measured across all 388 entries: zero
        # inversions. Silently swapping them would hide a real reference defect,
        # and silently keeping them would make `min`/`max` meaningless
        # downstream, so this stops the build and names the entry.
        assert lo <= hi, (
            "%s %s: inverted level range %d-%d on %s — source data should never "
            "do this; do not 'fix' it here" % (const, field_key, lo, hi, m["species"]))
        key = clean_token(m["species"], "SPECIES_")
        dex = species.get(key)
        if dex is None:
            unresolved_species.add(m["species"])
            continue
        slots.append({"dex": int(dex), "min": lo, "max": hi})

    return slots if len(slots) == out_count else None


def main():
    raw = json.load(open(RAW, encoding="utf-8"))
    group = raw["wild_encounter_groups"][0]
    assert group.get("for_maps"), (
        "the first encounter group is no longer the per-map one — the other two "
        "(Battle Pyramid, Battle Pike) are not keyed by map and must not be read")

    source_rates = {f["type"]: list(f["encounter_rates"]) for f in group["fields"]}
    source_groups = {f["type"]: f.get("groups") for f in group["fields"]}

    # Drift detection only — confirms the raw dump still looks like what the
    # land override was written against.
    assert len(source_rates.get("land_mons", [])) == RAW_LAND_SLOT_COUNT, (
        "the reference's land_mons now has %d slots, expected %d — "
        "LAND_SLOT_RATES's own override was written against the old shape, "
        "re-check it" % (len(source_rates.get("land_mons", [])), RAW_LAND_SLOT_COUNT))

    species = load_species_map()
    names = map_table()
    kanto = kanto_constants()

    chosen, dropped_extra, skipped_other_region = choose_entries(
        group.get("encounters", []), kanto)

    unresolved_species = set()
    unresolved_maps = set()
    written = []

    for field_key, filename, override in FIELDS:
        assert field_key in source_rates, (
            "no %s field in the reference dump" % field_key)
        rates = override if override is not None else source_rates[field_key]
        out_maps = {}

        for const, entry in sorted(chosen.items()):
            field = entry.get(field_key)
            if not field:
                continue
            name = names.get(const)
            if name is None:
                # A map the importer's own table does not know is a real
                # disagreement between two generated files, not a missing map —
                # the same distinction `[M27C C1]` drew for connection
                # destinations.
                unresolved_maps.add(const)
                continue
            slots = build_slots(field.get("mons", []), len(rates), species,
                                const, field_key, unresolved_species)
            if slots is None:
                continue
            out_maps[name] = {
                "encounter_rate": int(field["encounter_rate"]),
                "slots": slots,
            }

        payload = {"slot_rates": rates, "maps": out_maps}
        # Fishing's slots are grouped by rod (`old_rod` 0-1, `good_rod` 2-4,
        # `super_rod` 5-9). Carried through rather than hardcoded downstream:
        # the split is data in the reference, and a consumer that assumed it
        # would silently mis-band a changed table.
        if source_groups.get(field_key):
            payload["rod_groups"] = source_groups[field_key]

        out_path = os.path.join(OUT_DIR, filename)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent="\t", sort_keys=True, ensure_ascii=False)
            f.write("\n")
        written.append((field_key, filename, len(out_maps), rates,
                        override is not None))

    print("gen_wild_encounters: %d Kanto map(s) chosen (%s, first table per map)"
          % (len(chosen), VERSION_TAG))
    for field_key, filename, count, rates, overridden in written:
        print("  %-16s %3d map(s) -> data/%-28s %d slots%s"
              % (field_key, count, filename, len(rates),
                 "  [project override]" if overridden else "  [source rates]"))
    if dropped_extra:
        print("  extra %s tables dropped (first-per-map): %s"
              % (VERSION_TAG, {k: v for k, v in sorted(dropped_extra.items())}))
    print("  non-Kanto map constants skipped: %d" % len(skipped_other_region))
    if unresolved_maps:
        print("  UNRESOLVED map constants (%d): %s"
              % (len(unresolved_maps), sorted(unresolved_maps)[:6]))
    if unresolved_species:
        print("  UNRESOLVED species (%d): %s"
              % (len(unresolved_species), sorted(unresolved_species)[:8]))
    else:
        print("  every species resolved")


if __name__ == "__main__":
    main()
