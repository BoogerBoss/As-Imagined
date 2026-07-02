#!/usr/bin/env python3
"""
Generate name-only placeholder data/abilities/ability_NNNN.tres files for any
canonical ability ID (per include/constants/abilities.h) that doesn't already
have a .tres file.

The original 313-file bulk placeholder pass (M15, commit d9bbc89b) was done by
a script that was never committed to this repo. Reconstructed here because it
silently skipped 6 ability IDs whose enum values are defined symbolically
(`= ABILITIES_COUNT_GENx`) rather than as literal numbers in abilities.h —
whatever regex/parser produced the original 313 files only matched literal
`ABILITY_FOO = NNN,` lines. Confirmed via M17 recon (docs/m17_recon.md) that
ALL SIX symbolic-value IDs were missing, not just the two (Tangled Feet,
Pickpocket) found in the first recon pass: Aroma Veil (165), Stamina (192),
Intrepid Sword (234), and Lingering Aroma (268) were missing too.

This script only fills gaps — it does not touch any of the 313 existing files
(including the 12 mechanic-bearing ones gen_abilities.py owns).

Usage (from project root):
    python3 scripts/gen_ability_placeholders.py
"""

import pathlib
import re

REPO_ROOT = pathlib.Path(__file__).parent.parent
ABILITIES_H = REPO_ROOT.parent / "reference" / "pokeemerald_expansion" / "include" / "constants" / "abilities.h"
NAMES_H = REPO_ROOT.parent / "reference" / "pokeemerald_expansion" / "src" / "data" / "abilities.h"
OUT_DIR = REPO_ROOT / "data" / "abilities"

HEADER = """\
[gd_resource type="Resource" script_class="AbilityData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/ability_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""


def parse_ability_ids() -> dict[str, int]:
    """Return {ENUM_CONST_NAME: resolved int value}, resolving symbolic refs
    and plain C-enum auto-increment (a bare `NAME,` takes previous value + 1)."""
    text = ABILITIES_H.read_text(encoding="utf-8")
    ids: dict[str, int] = {}
    next_value = 0
    for line in text.splitlines():
        m = re.match(r"\s*(ABILITY_\w+|ABILITIES_COUNT\w*)\s*(?:=\s*(.+?))?,", line)
        if not m:
            continue
        const_name, rhs = m.group(1), (m.group(2) or "").strip()
        if not rhs:
            value = next_value
        elif rhs.isdigit():
            value = int(rhs)
        else:
            # Symbolic reference to an earlier-defined constant (e.g. ABILITIES_COUNT_GEN3).
            value = ids[rhs]
        ids[const_name] = value
        next_value = value + 1
    return ids


def parse_display_names() -> dict[int, str]:
    """Return {ability_id: display_name} by cross-referencing src/data/abilities.h."""
    ability_ids = parse_ability_ids()
    id_to_const = {v: k for k, v in ability_ids.items() if k.startswith("ABILITY_") and not k.startswith("ABILITIES_")}

    text = NAMES_H.read_text(encoding="utf-8")
    names: dict[int, str] = {}
    current_const = None
    for line in text.splitlines():
        m_bracket = re.search(r"\[(ABILITY_\w+)\]\s*=", line)
        if m_bracket:
            current_const = m_bracket.group(1)
            continue
        m_name = re.search(r'\.name\s*=\s*_\("(.+?)"\)', line)
        if m_name and current_const is not None:
            const_id = ability_ids.get(current_const)
            if const_id is not None:
                names[const_id] = m_name.group(1)
            current_const = None
    return names


def render(ability_id: int, name: str) -> str:
    lines = [HEADER.rstrip(), ""]
    lines.append(f"ability_id = {ability_id}")
    lines.append(f'ability_name = "{name}"')
    lines.append('description = ""')
    lines.append("ai_rating = 0")
    return "\n".join(lines) + "\n"


def main():
    ability_ids = parse_ability_ids()
    names = parse_display_names()

    max_id = max(v for k, v in ability_ids.items() if k.startswith("ABILITY_") and not k.startswith("ABILITIES_"))

    written = []
    for ability_id in range(0, max_id + 1):
        path = OUT_DIR / f"ability_{ability_id:04d}.tres"
        if path.exists():
            continue
        name = names.get(ability_id)
        if name is None:
            print(f"  WARNING: no name found for ability id {ability_id}, skipping")
            continue
        path.write_text(render(ability_id, name), encoding="utf-8")
        written.append(path.name)
        print(f"  wrote {path.name} ({name})")

    print(f"Done — {len(written)} placeholder file(s) written in {OUT_DIR}")


if __name__ == "__main__":
    main()
