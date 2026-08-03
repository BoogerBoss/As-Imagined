#!/usr/bin/env python3
"""
[M27O O1] Generates data/heal_locations.json: the respawn table `setrespawn`
addresses, with map names already resolved to this project's own.

`setrespawn HEAL_LOCATION_PEWTER_CITY` stores WHERE the player wakes up after a
whiteout. 47 corpus uses across 39 distinct locations; 4 in the corridor
(Pallet, Viridian, Pewter, Route 10).

⚠️ THERE ARE TWO POINTS PER ENTRY AND THEY ARE DIFFERENT PLACES.
`heal_locations.json`'s `map`/`x`/`y` is the HEAL POINT — the outdoor tile the
town's Pokémon Centre sits on, used by Teleport and by "fly here". The
`respawn_map`/`respawn_x`/`respawn_y` is where a WHITEOUT actually puts you:
inside the Centre, or for Pallet inside the player's own house. Source keeps
them in two separate tables (`sHealLocations` and
`sWhiteoutRespawnHealCenterMapIdxs`) for exactly this reason. Collapsing them
would drop the player outdoors after a whiteout instead of in front of a nurse.

⚠️ `respawn_x`/`respawn_y` ARE OPTIONAL AND THEIR DEFAULT IS REAL.
The template applies `DEFAULT_POKEMON_CENTER_X 7` / `_Y 4` when an entry omits
them — which most do, because every Pokémon Centre has the same interior
layout. Treating a missing coordinate as 0 would put the player in the wall.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REFERENCE = os.path.join(os.path.dirname(PROJECT), "reference", "pokeemerald_expansion")
SRC = os.path.join(REFERENCE, "src", "data", "heal_locations.json")
TEMPLATE = os.path.join(REFERENCE, "src", "data", "heal_locations.json.txt")
MAP_CONSTANTS = os.path.join(PROJECT, "scripts", "overworld", "map_constants.gd")
OUT = os.path.join(PROJECT, "data", "heal_locations.json")


def pokemon_center_defaults():
    """Read the two defaults out of the template rather than hardcoding them."""
    text = open(TEMPLATE, encoding="utf-8").read()
    x = re.search(r"#define\s+DEFAULT_POKEMON_CENTER_X\s+(\d+)", text)
    y = re.search(r"#define\s+DEFAULT_POKEMON_CENTER_Y\s+(\d+)", text)
    if not x or not y:
        sys.exit("DEFAULT_POKEMON_CENTER_X/Y not found in the template")
    return int(x.group(1)), int(y.group(1))


def map_table():
    """MAP_* -> this project's own map name, from the generated table."""
    text = open(MAP_CONSTANTS, encoding="utf-8").read()
    return dict(re.findall(r'"(MAP_[A-Z0-9_]+)":\s*"([^"]+)"', text))


def main():
    default_x, default_y = pokemon_center_defaults()
    maps = map_table()
    entries = json.load(open(SRC, encoding="utf-8"))["heal_locations"]

    out, unresolved = {}, []
    for e in entries:
        heal_map = maps.get(e["map"], "")
        resp_const = e.get("respawn_map", e["map"])
        resp_map = maps.get(resp_const, "")
        if heal_map == "" or resp_map == "":
            # A constant the map table does not know means the importer and the
            # headers disagree — a build problem, not a missing feature.
            unresolved.append((e["id"], e["map"], resp_const))
            continue
        out[e["id"]] = {
            "map": heal_map,
            "x": int(e["x"]),
            "y": int(e["y"]),
            "respawn_map": resp_map,
            "respawn_x": int(e.get("respawn_x", default_x)),
            "respawn_y": int(e.get("respawn_y", default_y)),
        }

    if unresolved:
        sys.exit("unresolvable map constant(s): %r" % unresolved[:5])

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(out.items())), f, indent="\t", sort_keys=True)
        f.write("\n")

    # How many land on a map this project has actually baked — the difference
    # between "the table is complete" and "a whiteout here would work".
    baked = set()
    scenes = os.path.join(PROJECT, "scenes", "maps")
    if os.path.isdir(scenes):
        baked = {n[:-5] for n in os.listdir(scenes) if n.endswith(".tscn")}
    usable = sum(1 for v in out.values() if v["respawn_map"] in baked)

    print("heal locations : %s" % os.path.relpath(OUT, PROJECT))
    print("  entries      : %d" % len(out))
    print("  pokecentre default coords: (%d, %d)" % (default_x, default_y))
    print("  respawn map baked        : %d of %d" % (usable, len(out)))


if __name__ == "__main__":
    main()
