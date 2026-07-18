#!/usr/bin/env python3
"""
[M18.5j] Wrap data/learnsets.json and data/evolutions.json's dex-number-keyed
arrays with a human-readable species_name field, mirroring the existing
move_id/move_name pattern already present inside each learnset entry.

Usage (from project root):
    python3 scripts/gen_species_names.py

Purely additive/readability: the dex-number string key remains the canonical
lookup identifier. species_name is sourced from data/pokemon.json's own
"name" field for that dex number and is not read by any production logic
(debug-only, matching move_name's own precedent).

Idempotent: if an entry is already wrapped (has a "species_name" key), it is
left untouched, so reruns are safe.

No rerunnable extractor produced these two files originally (tools/
convert_pokedata.py, per [M15]'s decisions.md entry, does not exist in this
repo — same gap [M18.5d Phase 1] already found for pokemon.json itself), so
this script operates directly on the existing JSON as the source of truth
rather than regenerating from pokeemerald_expansion source.
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def save(name, data):
    with open(os.path.join(DATA, name), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def dex_to_name():
    pokemon = load("pokemon.json")
    return {str(entry["dex"]): entry["name"] for entry in pokemon}


def wrap(filename, inner_key):
    names = dex_to_name()
    data = load(filename)
    changed = 0
    for dex_key, value in data.items():
        if isinstance(value, dict) and "species_name" in value:
            continue  # already wrapped
        data[dex_key] = {
            "species_name": names.get(dex_key, ""),
            inner_key: value,
        }
        changed += 1
    save(filename, data)
    print(f"{filename}: wrapped {changed} entries ({len(data)} total)")


if __name__ == "__main__":
    wrap("learnsets.json", "moves")
    wrap("evolutions.json", "evolutions")
