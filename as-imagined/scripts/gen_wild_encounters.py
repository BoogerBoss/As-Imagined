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

# `LAND_WILD_COUNT` — source's own slot count. Asserted against the data rather than
# trusted, because a mismatch would silently drop or duplicate a slot.
LAND_SLOT_COUNT = 12


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

    slot_rates = None
    for field in group["fields"]:
        if field["type"] == "land_mons":
            slot_rates = list(field["encounter_rates"])
    assert slot_rates is not None, "no land_mons field in the raw dump"
    assert len(slot_rates) == LAND_SLOT_COUNT, (
        "expected %d land slots, got %d" % (LAND_SLOT_COUNT, len(slot_rates)))
    # Source picks a slot with `Random() % ENCOUNTER_CHANCE_LAND_MONS_TOTAL`, and the
    # per-slot chances are these. They sum to 100 in the data; asserted rather than
    # assumed, because a table that did not sum would make the last slot unreachable.
    assert sum(slot_rates) == 100, "land slot rates sum to %d, not 100" % sum(slot_rates)

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
        assert len(mons) == LAND_SLOT_COUNT, (
            "%s has %d land slots, expected %d" % (const, len(mons), LAND_SLOT_COUNT))

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
