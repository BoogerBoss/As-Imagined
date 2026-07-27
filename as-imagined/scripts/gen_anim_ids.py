#!/usr/bin/env python3
"""
[M26B3-6c] Adds three per-species animation fields to data/pokemon.json:
`back_anim_id`, `front_anim_id`, `front_anim_delay`.

Usage (from project root):
    python3 scripts/gen_anim_ids.py

These drive the per-species entry animation that plays the instant a
Pokemon finishes emerging from its ball -- the left/right motion Rob
observed on the player's own Pokemon while it was still pink.

Source: reference/pokeemerald_expansion/src/data/pokemon/species_info/
gen_{1,2,3}_families.h, resolved against the two enums in
include/pokemon_animation.h:

  - `.backAnimId`  -> `enum BackAnim`         (0 = BACK_ANIM_NONE .. 25)
  - `.frontAnimId` -> `enum AnimFunctionIDs`  (0 .. ANIM_COUNT-1)
  - `.frontAnimDelay` -> plain u8, 0 for most species

Structurally a near-copy of `gen_weight_data.py` -- same
`NATIONAL_DEX_*`-against-`pokedex.h` ordinal resolution, same
first-occurrence-per-dex dedup (base form only), same 1..386 clamp, same
Unown special case. See that script's own docstring for why these fields
are parsed out of source directly rather than via a shared extractor
(there isn't one -- [M18.5d Phase 1]'s finding).

STORED AS INTEGERS, deliberately. `growth_rate` in this same file is
stored as a *string* with no int-enum mapping anywhere (see [M23.3]'s own
note), which is why `PokemonSpecies.growth_rate` has sat unpopulated. Both
anim enums here are dense sequential C enums with a real numeric identity
that the GDScript dispatch switches on directly, so the string detour
would only re-create that same dead-end.

TWO SOURCE QUIRKS HANDLED, both confirmed by direct inspection:

1. `P_GBA_STYLE_SPECIES_GFX ? A : B` ternaries. 111 species use one for
   `.frontAnimId` and 6 for `.backAnimId`. That config is FALSE in this
   reference tree, so the FALSE branch (B) is taken -- the same
   resolve-the-live-branch rule `gen_exp_ev_yield_data.py` already applies
   to its own `P_UPDATED_EXP_YIELDS`/`P_UPDATED_EVS` ternaries.

2. Unown (#201) is hardcoded, because its species block uses the
   `UNOWN_MISC_INFO` macro rather than a plain struct literal and is not
   block-parseable -- the identical blind spot `gen_weight_data.py`
   already documents. Values read directly out of that macro body
   (gen_2_families.h): frontAnimId = ANIM_ZIGZAG_FAST,
   backAnimId = BACK_ANIM_SHRINK_GROW_VIBRATE, no frontAnimDelay (0).

Idempotent: overwrites any existing values with freshly re-parsed ones,
so reruns are safe.
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "..", "reference", "pokeemerald_expansion")
POKEDEX_H = os.path.join(REF, "include", "constants", "pokedex.h")
ANIM_H = os.path.join(REF, "include", "pokemon_animation.h")
FAMILY_FILES = [
    os.path.join(REF, "src", "data", "pokemon", "species_info", f"gen_{n}_families.h")
    for n in (1, 2, 3)
]
POKEMON_JSON = os.path.join(ROOT, "data", "pokemon.json")

# UNOWN_MISC_INFO macro, gen_2_families.h -- not block-parseable.
UNOWN_DEX = 201
UNOWN_FRONT_ANIM = "ANIM_ZIGZAG_FAST"
UNOWN_BACK_ANIM = "BACK_ANIM_SHRINK_GROW_VIBRATE"
UNOWN_FRONT_DELAY = 0


def _parse_enum(content, enum_name):
    """Ordinal map for a plain sequential C enum (no explicit values)."""
    m = re.search(r"enum %s\s*\{(.*?)\n\};" % enum_name, content, re.DOTALL)
    if m is None:
        raise SystemExit("ERROR: enum %s not found" % enum_name)
    mapping = {}
    ordinal = 0
    for line in m.group(1).split("\n"):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        em = re.match(r"([A-Z_][A-Z_0-9]*)\s*,?", line)
        if not em:
            continue
        name = em.group(1)
        if name.endswith("_COUNT"):
            continue
        mapping[name] = ordinal
        ordinal += 1
    return mapping


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


def build_anim_maps():
    with open(ANIM_H, encoding="utf-8") as f:
        content = f.read()
    return _parse_enum(content, "BackAnim"), _parse_enum(content, "AnimFunctionIDs")


def _resolve_symbol(raw):
    """Take the live branch of a P_GBA_STYLE_SPECIES_GFX ternary, else the
    bare symbol. That config is FALSE here, so the ':' branch wins."""
    raw = raw.strip()
    tern = re.match(
        r"P_GBA_STYLE_SPECIES_GFX\s*\?\s*([A-Z_0-9]+)\s*:\s*([A-Z_0-9]+)", raw)
    if tern:
        return tern.group(2)
    m = re.match(r"([A-Z_][A-Z_0-9]*)", raw)
    return m.group(1) if m else None


def _resolve_delay(raw):
    """`.frontAnimDelay` carries the SAME ternary shape as the two anim-id
    fields, with numeric branches instead of symbolic ones -- e.g. Pikachu's
    `P_GBA_STYLE_SPECIES_GFX ? 0 : 25`. A numeric-only regex silently reads
    those as 0 (no match -> default), which is wrong at this config; the
    live value is the FALSE branch. Caught by a Pikachu spot-check against
    source, not by the extractor's own completeness check -- every species
    has *a* value, so nothing was reported missing."""
    raw = raw.strip()
    tern = re.match(r"P_GBA_STYLE_SPECIES_GFX\s*\?\s*(\d+)\s*:\s*(\d+)", raw)
    if tern:
        return int(tern.group(2))
    m = re.match(r"(\d+)", raw)
    return int(m.group(1)) if m else 0


def extract(dex_ordinal, back_map, front_map):
    out = {
        UNOWN_DEX: {
            "back_anim_id": back_map[UNOWN_BACK_ANIM],
            "front_anim_id": front_map[UNOWN_FRONT_ANIM],
            "front_anim_delay": UNOWN_FRONT_DELAY,
        }
    }
    for path in FAMILY_FILES:
        with open(path, encoding="utf-8") as f:
            content = f.read()
        starts = [m.start() for m in
                  re.finditer(r"\n    \[SPECIES_\w+\]\s*=\s*\n    \{", content)]
        for i, start in enumerate(starts):
            end = starts[i + 1] if i + 1 < len(starts) else len(content)
            block = content[start:end]
            ndm = re.search(r"\.natDexNum\s*=\s*(NATIONAL_DEX_\w+)", block)
            if not ndm:
                continue
            dex = dex_ordinal.get(ndm.group(1))
            if dex is None or not (1 <= dex <= 386) or dex in out:
                continue
            bam = re.search(r"\.backAnimId\s*=\s*([^,\n]+)", block)
            fam = re.search(r"\.frontAnimId\s*=\s*([^,\n]+)", block)
            if not bam or not fam:
                continue
            back_sym = _resolve_symbol(bam.group(1))
            front_sym = _resolve_symbol(fam.group(1))
            if back_sym not in back_map:
                raise SystemExit("ERROR: unknown BackAnim %r (dex %d)" % (back_sym, dex))
            if front_sym not in front_map:
                raise SystemExit("ERROR: unknown AnimFunctionID %r (dex %d)"
                                 % (front_sym, dex))
            dm = re.search(r"\.frontAnimDelay\s*=\s*([^,\n]+)", block)
            out[dex] = {
                "back_anim_id": back_map[back_sym],
                "front_anim_id": front_map[front_sym],
                "front_anim_delay": _resolve_delay(dm.group(1)) if dm else 0,
            }
    return out


def main():
    dex_ordinal = build_dex_ordinal_map()
    back_map, front_map = build_anim_maps()
    data = extract(dex_ordinal, back_map, front_map)

    missing = set(range(1, 387)) - set(data.keys())
    if missing:
        raise SystemExit("ERROR: missing anim ids for dex numbers: %s" % sorted(missing))

    with open(POKEMON_JSON, encoding="utf-8") as f:
        pokemon = json.load(f)

    changed = 0
    for entry in pokemon:
        vals = data[entry["dex"]]
        if any(entry.get(k) != v for k, v in vals.items()):
            entry.update(vals)
            changed += 1

    with open(POKEMON_JSON, "w", encoding="utf-8") as f:
        json.dump(pokemon, f, indent=2)
        f.write("\n")

    no_back = sum(1 for v in data.values() if v["back_anim_id"] == 0)
    delayed = sum(1 for v in data.values() if v["front_anim_delay"] != 0)
    print("anim ids: %d entries updated (%d already correct), %d dex numbers "
          "resolved from source" % (changed, len(pokemon) - changed, len(data)))
    print("  BACK_ANIM_NONE (no back animation): %d of %d species" % (no_back, len(data)))
    print("  nonzero frontAnimDelay:             %d of %d species" % (delayed, len(data)))
    print("  distinct back anim sets in use:     %d"
          % len({v["back_anim_id"] for v in data.values() if v["back_anim_id"]}))
    print("  distinct front anim ids in use:     %d"
          % len({v["front_anim_id"] for v in data.values()}))


if __name__ == "__main__":
    main()
