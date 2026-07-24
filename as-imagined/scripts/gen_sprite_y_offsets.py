#!/usr/bin/env python3
"""
Extracts the real per-species `.frontPicYOffset` field (source's own doc
comment: "The number of pixels between the drawn pixel area and the bottom
edge") from reference/pokeemerald_expansion, matching the exact mechanism
the real games use to make every Pokémon's front sprite appear to stand at
a consistent height on the battlefield despite wildly varying sprite
content (a tiny Diglett vs. a huge Wailord) -- confirmed via direct pixel
inspection to match this project's own already-pulled GBA-style sprites
pixel-for-pixel (Bulbasaur: frontPicYOffset=14 GBA-style branch, measured
pixel padding=14; Pikachu: frontPicYOffset=9, measured padding=9).

Usage (from project root):
    python3 scripts/gen_sprite_y_offsets.py

Source: reference/pokeemerald_expansion/src/data/pokemon/species_info/
gen_{1,2,3}_families.h -- same 3 files gen_weight_data.py already extracts
from, same NationalDexOrder resolution, same first-occurrence-per-dex-wins
dedup rule.

This project pulls GBA-style sprite art (not the Gen4/5-style default this
reference repo's own P_GBA_STYLE_SPECIES_GFX config defaults to) -- so
wherever a species' own .frontPicYOffset is a `P_GBA_STYLE_SPECIES_GFX ? X
: Y` ternary, the GBA-style branch (X) is the one that matches this
project's real pulled assets, and is the one used here.

Unown (#201) hardcoded to 16 -- its species blocks route through the
UNOWN_MISC_INFO macro (not a plain struct literal), the same
extractor blind spot gen_weight_data.py already documents for weight;
`.frontPicYOffset = 16` is hardcoded directly inside that macro's own body
for every Unown letter form.

Output: data/sprite_y_offsets.json, a flat {"<dex>": offset} map (386
entries) -- kept as its own small file rather than folded into
data/pokemon.json, since this is a pure display-positioning value with no
battle-mechanics consumer (unlike weight/gender_ratio/base_friendship,
which PokemonSpecies already has schema fields for).

Idempotent: overwrites the whole file with freshly re-parsed values, so
reruns are safe.
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "..", "reference", "pokeemerald_expansion")
POKEDEX_H = os.path.join(REF, "include", "constants", "pokedex.h")
FAMILY_FILES = [
    os.path.join(REF, "src", "data", "pokemon", "species_info", f"gen_{n}_families.h")
    for n in (1, 2, 3)
]
OUT_PATH = os.path.join(ROOT, "data", "sprite_y_offsets.json")

UNOWN_DEX = 201
UNOWN_Y_OFFSET = 16  # UNOWN_MISC_INFO macro body, gen_2_families.h -- not block-parseable


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


def extract_y_offsets(dex_ordinal):
    dex_to_offset = {UNOWN_DEX: UNOWN_Y_OFFSET}
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
            # Real ternary form: `P_GBA_STYLE_SPECIES_GFX ? X : Y` -- GBA-style
            # branch (X) is the one matching this project's real pulled assets.
            ym = re.search(r"\.frontPicYOffset\s*=\s*P_GBA_STYLE_SPECIES_GFX\s*\?\s*(\d+)\s*:\s*\d+", block)
            if not ym:
                ym = re.search(r"\.frontPicYOffset\s*=\s*(\d+)\s*,", block)
            if not ym:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386):
                continue
            if dex not in dex_to_offset:
                dex_to_offset[dex] = int(ym.group(1))
    return dex_to_offset


def main():
    dex_ordinal = build_dex_ordinal_map()
    dex_to_offset = extract_y_offsets(dex_ordinal)

    missing = set(range(1, 387)) - set(dex_to_offset.keys())
    if missing:
        raise SystemExit(f"ERROR: missing frontPicYOffset for dex numbers: {sorted(missing)}")

    out = {str(dex): dex_to_offset[dex] for dex in sorted(dex_to_offset)}
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
        f.write("\n")

    print(f"sprite_y_offsets: {len(dex_to_offset)} dex numbers resolved and written to {OUT_PATH}")


if __name__ == "__main__":
    main()
