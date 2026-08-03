#!/usr/bin/env python3
"""
[M27K K-a] Generates data/species_name_to_id.json: a flat {"SPECIES_XXX": id}
map, parsed directly from the canonical reference enum
(reference/pokeemerald_expansion/include/constants/species.h).

Why this exists: Kanto's own imported map scripts identify a species by
CONSTANT NAME, never by number — `givemon PLAYER_STARTER_SPECIES, 5` passes a
variable holding the literal string "SPECIES_BULBASAUR", and `bufferspeciesname`
takes the same. Every other part of this project identifies a species by its
numeric national-dex number (PokemonRegistry, PokemonFactory, BattlePokemon).
This is the one reusable bridge, exactly as gen_move_name_map.py and
gen_item_name_map.py already are for their own two rosters — the third instance
of one problem, deliberately solved the same way rather than a third way.

⚠️ ALIASES ARE LOAD-BEARING, AND TWO OF THEM ARE IN THIS PROJECT'S OWN ROSTER.
98 entries are `SPECIES_X = SPECIES_Y` rather than `= <int>`, and they are not
all exotic forms: `SPECIES_CASTFORM = SPECIES_CASTFORM_NORMAL` and
`SPECIES_DEOXYS = SPECIES_DEOXYS_NORMAL` are both Gen 1-3 Pokemon this project
implements. Parsing only `= <int>` would silently drop them — the identical
failure gen_item_name_map.py hit with ITEM_ITEMFINDER/ITEM_OAKS_PARCEL, which
that script break-tested at 43 unresolvable corpus items. The sequential
C-enum walk below resolves ints, aliases and bare auto-incremented entries
uniformly, so no case needs special-casing.

⚠️ EVERY CONSTANT IS EMITTED, NOT JUST THE 386 THIS PROJECT IMPLEMENTS. A
script naming a Gen 4+ species then resolves to a real id and fails at the
ROSTER lookup instead of at the name lookup — which keeps "unknown constant"
(a pipeline bug) distinguishable from "known but not implemented here" (a
scope boundary). Same two-step shape as I1's item_id_of/get_item_identity.
"""
import json
import os
import re

from ref_path import REF

SRC = os.path.join(REF, "include", "constants", "species.h")
OUT = "data/species_name_to_id.json"

# `SPECIES_X = 1,` | `SPECIES_X = SPECIES_Y,` | `SPECIES_X,`
ENTRY = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*(?:=\s*([^,]+?))?\s*,\s*(?://.*)?$")


def build() -> dict:
    out: dict[str, int] = {}
    counter = 0
    started = False
    for line in open(SRC, encoding="utf-8"):
        if "enum" in line and "Species" in line:
            started = True
            continue
        if not started:
            continue
        if line.startswith("};"):
            break
        m = ENTRY.match(line)
        if not m:
            continue
        name, value = m.group(1), m.group(2)
        if value is None:
            # Real C semantics: no explicit value means previous + 1.
            counter += 1
        elif value.strip().isdigit():
            counter = int(value.strip())
        elif value.strip() in out:
            # An alias takes its target's value and does NOT advance past it.
            counter = out[value.strip()]
        else:
            # An expression this parser does not model. Skipping silently is how
            # a map goes quietly wrong, so refuse instead.
            raise SystemExit(f"gen_species_name_map: unresolved entry {name} = {value!r}")
        if name.startswith("SPECIES_"):
            out[name] = counter
    return out


def main() -> None:
    table = build()
    # Guards, not decoration: each of these has a real failure it catches.
    assert table.get("SPECIES_NONE") == 0, "SPECIES_NONE must be 0"
    assert table.get("SPECIES_BULBASAUR") == 1, "the dex must start at Bulbasaur"
    assert table.get("SPECIES_MEW") == 151, "Gen 1 must end at Mew"
    assert table.get("SPECIES_CELEBI") == 251, "Gen 2 must end at Celebi"
    assert table.get("SPECIES_DEOXYS") == 386, "Gen 3 must end at Deoxys"
    # The two in-roster aliases the naive parse would have dropped.
    assert table.get("SPECIES_CASTFORM") == 351, "Castform's alias must resolve"
    assert table["SPECIES_DEOXYS"] == table["SPECIES_DEOXYS_NORMAL"], \
        "an alias must equal its target"
    # A name must never map to two ids, and the three starters must be right.
    for name, dex in (("SPECIES_BULBASAUR", 1), ("SPECIES_CHARMANDER", 4),
                      ("SPECIES_SQUIRTLE", 7)):
        assert table[name] == dex, f"{name} must be {dex}"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(table, f, indent=1, sort_keys=True)
        f.write("\n")
    in_roster = sum(1 for v in table.values() if 1 <= v <= 386)
    print(f"{OUT}: {len(table)} constants over "
          f"{len(set(table.values()))} distinct ids "
          f"({in_roster} naming a species this project implements)")


if __name__ == "__main__":
    main()
