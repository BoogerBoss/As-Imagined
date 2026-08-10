#!/usr/bin/env python3
"""
Extracts the real per-species `.frontPicYOffset` AND `.backPicYOffset`
fields (source's own doc comment on the back field, include/pokemon.h:459:
"The number of pixels between the drawn pixel area and the bottom edge")
from reference/pokeemerald_expansion, matching the exact mechanism the real
games use to make every Pokémon's sprite appear to stand at a consistent
height on the battlefield despite wildly varying sprite content (a tiny
Diglett vs. a huge Wailord) -- confirmed via direct pixel inspection to
match this project's own already-pulled GBA-style sprites pixel-for-pixel
(Bulbasaur: frontPicYOffset=14 GBA-style branch, measured pixel padding=14;
Pikachu: frontPicYOffset=9, measured padding=9).

Usage (from project root):
    python3 scripts/gen_sprite_y_offsets.py

Source: reference/pokeemerald_expansion/src/data/pokemon/species_info/
gen_{1,2,3}_families.h -- same 3 files gen_weight_data.py already extracts
from, same NationalDexOrder resolution, same first-occurrence-per-dex-wins
dedup rule. Front and back are pulled from the SAME block in the SAME pass
-- they are two fields of one struct literal, not two separate sources.

This project pulls GBA-style sprite art (not the Gen4/5-style default this
reference repo's own P_GBA_STYLE_SPECIES_GFX config defaults to) -- so
wherever a species' own offset field is a `P_GBA_STYLE_SPECIES_GFX ? X : Y`
ternary, the GBA-style branch (X) is the one that matches this project's
real pulled assets, and is the one used here, for BOTH fields.

Unown (#201) hardcoded -- its species blocks route through the
UNOWN_MISC_INFO macro (not a plain struct literal), the same extractor
blind spot gen_weight_data.py already documents for weight. Front is
`.frontPicYOffset = 16` inside the macro body, identical for every Unown
letter form. Back is DIFFERENT: `.backPicYOffset = backYOffset`, a macro
PARAMETER that genuinely varies per letter (A=8, B=9, C=6, ...) -- since
this project tracks Unown as one dex entry (not per-letter forms), the
base/first entry's own value is used: `[SPECIES_UNOWN] = UNOWN_MISC_INFO(A,
FALSE, 24, 40, 24, 48, 8)` -> backYOffset=8 for letter A.

Output: data/sprite_y_offsets.json (front, unchanged shape/path -- existing
readers untouched) and data/sprite_back_y_offsets.json (back, new), each a
flat {"<dex>": offset} map (386 entries) -- kept as two small files rather
than one merged shape or folded into data/pokemon.json, since these are
pure display-positioning values with no battle-mechanics consumer (unlike
weight/gender_ratio/base_friendship, which PokemonSpecies already has
schema fields for), and merging front+back would force a shape change onto
every already-existing front-offset reader for no benefit.

Idempotent: overwrites both files with freshly re-parsed values, so reruns
are safe.
"""

import json
import os
import re

from ref_path import REF

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POKEDEX_H = os.path.join(REF, "include", "constants", "pokedex.h")
FAMILY_FILES = [
    os.path.join(REF, "src", "data", "pokemon", "species_info", f"gen_{n}_families.h")
    for n in (1, 2, 3)
]
FRONT_OUT_PATH = os.path.join(ROOT, "data", "sprite_y_offsets.json")
BACK_OUT_PATH = os.path.join(ROOT, "data", "sprite_back_y_offsets.json")

UNOWN_DEX = 201
UNOWN_FRONT_Y_OFFSET = 16  # UNOWN_MISC_INFO macro body -- fixed for every letter form
UNOWN_BACK_Y_OFFSET = 8    # UNOWN_MISC_INFO's own backYOffset param, letter A (base entry)


def build_dex_ordinal_map():
    with open(POKEDEX_H, encoding="utf-8") as f:
        content = f.read()
    enum_m = re.search(r"enum NationalDexOrder\s*\{(.*?)\n\};", content, re.DOTALL)
    ordinal = 0
    mapping = {}
    for line in enum_m.group(1).split("\n"):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        m = re.match(r"(NATIONAL_DEX_\w+)\s*,?", line)
        if m:
            mapping[m.group(1)] = ordinal
            ordinal += 1
    return mapping


def _extract_field(block, field_name):
    # Real ternary form: `P_GBA_STYLE_SPECIES_GFX ? X : Y` -- GBA-style
    # branch (X) is the one matching this project's real pulled assets.
    m = re.search(r"\.%s\s*=\s*P_GBA_STYLE_SPECIES_GFX\s*\?\s*(\d+)\s*:\s*\d+" % field_name, block)
    if not m:
        m = re.search(r"\.%s\s*=\s*(\d+)\s*," % field_name, block)
    return int(m.group(1)) if m else None


def extract_y_offsets(dex_ordinal):
    dex_to_front = {UNOWN_DEX: UNOWN_FRONT_Y_OFFSET}
    dex_to_back = {UNOWN_DEX: UNOWN_BACK_Y_OFFSET}
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        block_starts = [m.start() for m in re.finditer(r"\n    \[SPECIES_\w+\]\s*=\s*\n    \{", content)]
        for i, start in enumerate(block_starts):
            end = block_starts[i + 1] if i + 1 < len(block_starts) else len(content)
            block = content[start:end]
            ndm = re.search(r"\.natDexNum\s*=\s*(NATIONAL_DEX_\w+)", block)
            if not ndm:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386):
                continue
            front = _extract_field(block, "frontPicYOffset")
            back = _extract_field(block, "backPicYOffset")
            if front is not None and dex not in dex_to_front:
                dex_to_front[dex] = front
            if back is not None and dex not in dex_to_back:
                dex_to_back[dex] = back
    return dex_to_front, dex_to_back


def _write(path, dex_to_offset, field_label):
    missing = set(range(1, 387)) - set(dex_to_offset.keys())
    if missing:
        raise SystemExit(f"ERROR: missing {field_label} for dex numbers: {sorted(missing)}")
    out = {str(dex): dex_to_offset[dex] for dex in sorted(dex_to_offset)}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    print(f"{field_label}: {len(dex_to_offset)} dex numbers resolved and written to {path}")


def main():
    dex_ordinal = build_dex_ordinal_map()
    dex_to_front, dex_to_back = extract_y_offsets(dex_ordinal)
    _write(FRONT_OUT_PATH, dex_to_front, "frontPicYOffset")
    _write(BACK_OUT_PATH, dex_to_back, "backPicYOffset")


if __name__ == "__main__":
    main()
