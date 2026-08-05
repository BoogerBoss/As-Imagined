#!/usr/bin/env python3
"""[M27H H1] Land wild-encounter tables, keyed by this project's own map names.

`data/wild_encounters.json` is the RAW reference dump — 1.0 MB, 388 entries across
240 maps, keyed by `MAP_*` constants, carrying land/water/rock-smash/fishing tables
together. It has been in the tree since M15 with NO consumer, and the M27/M29 roadmap
rows describing Kanto's encounters as "imported" refer to that file sitting there.
This is the generator that turns it into something readable at runtime, the same shape
`gen_heal_locations.py` produced for heal points.

LAND ONLY, deliberately. Water/rock-smash/fishing all need M27E (surfing, Rock Smash,
a fishing rod), and none has a consumer in the 32-map corridor. Measured: of the 7
corridor maps carrying any table, only 5 carry a LAND one — Pallet Town and Viridian
City are water-only.

⚠️ **NOTED FOR WHEN WATER/FISHING ARE BUILT — Rob's own design call, 2026-08-04**:
same as `land_mons`, he wants to change the water and fishing encounter-rate
percentages away from source's own tables (`60,30,5,4,1` for water; the rod-split
`70,30 / 60,20,20 / 40,40,15,4,1` for fishing — both still just the raw reference
values in `data/wild_encounters.json` today, untouched). Follow the LAND_SLOT_RATES
pattern above when this lands: leave the raw dump alone, layer the override + a
documented species-fill scheme for any added slots in a WATER_SLOT_RATES /
FISHING_SLOT_RATES override here, and get the actual target numbers from Rob first
rather than guessing a curve — same as land's own 15-slot table wasn't picked by us.

SPECIES RESOLUTION IS IMPORTED FROM `gen_trainer_data.py`, NOT REIMPLEMENTED. That
module already owns `normalize()`, the Nidoran gendered-form aliases, and
`_assert_no_normalize_collisions` — and `[M27B Step 4]` is the record of what a second
spelling costs: `Nidoran-female` and `Nidoran-male` both collapsed to `NIDORAN` and one
silently overwrote the other, invisible until a Kanto roster used them. One home for
the rule.

Idempotent: re-running writes byte-identical output.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# Reuse, never re-derive — see the module docstring.
from gen_trainer_data import load_species_map, normalize, clean_token  # noqa: E402

RAW = os.path.join(PROJECT, "data", "wild_encounters.json")
MAP_CONSTANTS = os.path.join(PROJECT, "scripts", "overworld", "map_constants.gd")
OUT = os.path.join(PROJECT, "data", "land_encounters.json")

# `LAND_WILD_COUNT` — source's own slot count, still exactly what the raw dump
# carries per map. Asserted against the raw data rather than trusted, because a
# mismatch would silently drop or duplicate a slot.
RAW_LAND_SLOT_COUNT = 12

# [Widened 2026-08-04, Rob's own design call — NOT reference-derived.] This
# project's own land-slot count and percentage curve, deliberately past source's
# 12/[20,20,10,10,10,10,5,5,4,4,1,1]. `data/wild_encounters.json` (the raw dump)
# is left untouched — it stays the real reference data; the divergence lives here
# instead, the same way other `gen_*.py` scripts layer an explicit override on
# top of extracted source data rather than hand-editing the "raw" file.
#
# The 3 new slots per map are filled by REPEATING each map's own 3 rarest
# reference slots (its last 3 entries — same species, same level range) rather
# than inventing new species. This is a documented PLACEHOLDER, not a permanent
# design decision: a future pass can hand-author real species per map for these
# slots instead of duplicating the existing rare tier into them.
LAND_SLOT_COUNT = 15
LAND_SLOT_RATES = [15, 15, 15, 10, 10, 10, 5, 5, 4, 4, 2, 2, 1, 1, 1]
assert len(LAND_SLOT_RATES) == LAND_SLOT_COUNT, (
    "LAND_SLOT_RATES has %d entries, LAND_SLOT_COUNT says %d"
    % (len(LAND_SLOT_RATES), LAND_SLOT_COUNT))
assert sum(LAND_SLOT_RATES) == 100, (
    "LAND_SLOT_RATES sums to %d, not 100" % sum(LAND_SLOT_RATES))
EXTRA_SLOT_COUNT = LAND_SLOT_COUNT - RAW_LAND_SLOT_COUNT


def map_table():
    """MAP_* -> this project's own map name, from the generated table.

    Same accessor `gen_heal_locations.py` uses. The two are NOT related by a string
    transform (`MAP_SSANNE_EXTERIOR` -> `SSAnne_Exterior_Frlg`), which is why the
    table is generated rather than derived.
    """
    text = open(MAP_CONSTANTS, encoding="utf-8").read()
    return dict(re.findall(r'"(MAP_[A-Z0-9_]+)":\s*"([^"]+)"', text))


def main():
    raw = json.load(open(RAW, encoding="utf-8"))
    group = raw["wild_encounter_groups"][0]

    raw_rates = None
    for field in group["fields"]:
        if field["type"] == "land_mons":
            raw_rates = list(field["encounter_rates"])
    assert raw_rates is not None, "no land_mons field in the raw dump"
    # Drift detection only — confirms the raw dump still looks like what this
    # override was written against. `slot_rates` (below) is this project's own
    # widened table, not the raw dump's; see the LAND_SLOT_RATES comment above.
    assert len(raw_rates) == RAW_LAND_SLOT_COUNT, (
        "raw dump's land_mons now has %d slots, expected %d — LAND_SLOT_RATES's "
        "own override was written against the old shape, re-check it"
        % (len(raw_rates), RAW_LAND_SLOT_COUNT))

    slot_rates = LAND_SLOT_RATES

    species = load_species_map()
    maps = map_table()

    out_maps = {}
    unresolved_species = set()
    unresolved_maps = set()
    skipped_water_only = []

    for entry in group.get("encounters", []):
        const = entry.get("map")
        if not const:
            continue
        land = entry.get("land_mons")
        if not land:
            if entry.get("water_mons") or entry.get("fishing_mons"):
                skipped_water_only.append(const)
            continue
        name = maps.get(const)
        if name is None:
            # A destination the importer's own table does not know is a real
            # disagreement between two generated files, not a missing map — same
            # distinction `[M27C C1]` drew for connection destinations.
            unresolved_maps.add(const)
            continue

        mons = land.get("mons", [])
        assert len(mons) == RAW_LAND_SLOT_COUNT, (
            "%s has %d land slots, expected %d" % (const, len(mons), RAW_LAND_SLOT_COUNT))
        # Pad to LAND_SLOT_COUNT — see the LAND_SLOT_RATES comment above for why
        # this duplicates the map's own 3 rarest entries rather than inventing
        # new ones.
        mons = mons + mons[-EXTRA_SLOT_COUNT:]

        slots = []
        for m in mons:
            key = clean_token(m["species"], "SPECIES_")
            dex = species.get(key)
            if dex is None:
                unresolved_species.add(m["species"])
                continue
            slots.append({
                "dex": int(dex),
                "min": int(m["min_level"]),
                "max": int(m["max_level"]),
            })
        if len(slots) != LAND_SLOT_COUNT:
            # Refuse a partial table rather than emit one: a short slot list would
            # make the rate table's own indices point at the wrong mon.
            continue
        out_maps[name] = {
            "encounter_rate": int(land["encounter_rate"]),
            "slots": slots,
        }

    payload = {"slot_rates": slot_rates, "maps": out_maps}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent="\t", sort_keys=True, ensure_ascii=False)
        f.write("\n")

    print("gen_wild_encounters: %d map(s) with a land table -> %s"
          % (len(out_maps), os.path.relpath(OUT, PROJECT)))
    print("  slot rates: %s (sum %d)" % (slot_rates, sum(slot_rates)))
    print("  water/fishing-only maps skipped (M27E): %d" % len(skipped_water_only))
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
