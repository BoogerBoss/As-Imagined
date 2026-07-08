#!/usr/bin/env python3
"""
[M19-pre1] Adds a per-species weight field (hectograms, matching source's own
u16 .weight unit exactly) to data/pokemon.json — needed by Low Kick/Grass
Knot (target-weight-only power) and Heavy Slam/Heat Crash (attacker/target
weight-ratio power).

Usage (from project root):
    python3 scripts/gen_weight_data.py

Source: reference/pokeemerald_expansion/src/data/pokemon/species_info/
gen_{1,2,3}_families.h (the same 3 files [M15]'s own decisions.md entry
cites as the original extraction source for base_hp/gender_ratio/etc — no
rerunnable extractor for these exists in this repo, per [M18.5d Phase 1]'s
own finding, so this parses source directly rather than depending on a
missing tool).

Resolves each species block's `.natDexNum = NATIONAL_DEX_X` against
include/constants/pokedex.h's own NationalDexOrder enum (a plain sequential
enum, NATIONAL_DEX_NONE=0) to get the numeric dex number, then reads that
same block's `.weight = N` (hectograms). First occurrence per dex number
wins (base form only), matching [M15]'s own "deduped by natDexNum" dedup
rule for every other field.

Unown (#201) is hardcoded (weight=50) — its species block uses the
UNOWN_MISC_INFO macro instead of a plain struct literal, the same
extractor blind spot [M15]'s own decisions.md entry already documented for
every other field ("Unown (#201) hardcoded: uses UNOWN_MISC_INFO macro not
parseable by block extractor").

Idempotent: overwrites any existing "weight" field with the freshly
re-parsed value, so reruns are safe.
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
POKEMON_JSON = os.path.join(ROOT, "data", "pokemon.json")

UNOWN_DEX = 201
UNOWN_WEIGHT = 50  # UNOWN_MISC_INFO macro, gen_2_families.h -- not block-parseable


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


def extract_weights(dex_ordinal):
    dex_to_weight = {UNOWN_DEX: UNOWN_WEIGHT}
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        block_starts = [m.start() for m in re.finditer(r"\n    \[SPECIES_\w+\]\s*=\s*\n    \{", content)]
        for i, start in enumerate(block_starts):
            end = block_starts[i + 1] if i + 1 < len(block_starts) else len(content)
            block = content[start:end]
            ndm = re.search(r"\.natDexNum\s*=\s*(NATIONAL_DEX_\w+)", block)
            wm = re.search(r"\.weight\s*=\s*(\d+)", block)
            if not ndm or not wm:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386):
                continue
            if dex not in dex_to_weight:
                dex_to_weight[dex] = int(wm.group(1))
    return dex_to_weight


def main():
    dex_ordinal = build_dex_ordinal_map()
    dex_to_weight = extract_weights(dex_ordinal)

    missing = set(range(1, 387)) - set(dex_to_weight.keys())
    if missing:
        raise SystemExit(f"ERROR: missing weight for dex numbers: {sorted(missing)}")

    with open(POKEMON_JSON, encoding="utf-8") as f:
        pokemon = json.load(f)

    changed = 0
    for entry in pokemon:
        dex = entry["dex"]
        w = dex_to_weight[dex]
        if entry.get("weight") != w:
            entry["weight"] = w
            changed += 1

    with open(POKEMON_JSON, "w", encoding="utf-8") as f:
        json.dump(pokemon, f, indent=2)
        f.write("\n")

    print(f"weight: {changed} entries updated ({len(pokemon) - changed} already correct), "
          f"{len(dex_to_weight)} dex numbers resolved from source")


if __name__ == "__main__":
    main()
