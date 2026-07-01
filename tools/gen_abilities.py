#!/usr/bin/env python3
"""
tools/gen_abilities.py

Reads pokeemerald_expansion/include/constants/abilities.h and generates
one .tres file per ability into as-imagined/data/abilities/.

Skips any file that already exists (preserves hand-tuned entries).
"""

import re
import os

ABILITIES_H = os.path.join(
    os.path.dirname(__file__),
    "../reference/pokeemerald_expansion/include/constants/abilities.h",
)
OUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "../as-imagined/data/abilities",
)
TRES_TEMPLATE = """\
[gd_resource type="Resource" script_class="AbilityData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/ability_data.gd" id="1"]

[resource]
script = ExtResource("1")

ability_id = {ability_id}
ability_name = "{ability_name}"
description = ""
ai_rating = 0
"""


def screaming_to_title(name: str) -> str:
    """ABILITY_SPEED_BOOST -> 'Speed Boost'"""
    # Strip leading ABILITY_ prefix
    name = re.sub(r"^ABILITY_", "", name)
    words = name.split("_")
    # Special-case acronyms and single-letters that should stay upper
    result = []
    for w in words:
        result.append(w.capitalize())
    return " ".join(result)


def parse_abilities(path: str) -> dict[int, str]:
    abilities: dict[int, str] = {}
    pattern = re.compile(r"^\s*(ABILITY_\w+)\s*=\s*(\d+)\s*,?")
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line)
            if m:
                const_name = m.group(1)
                ability_id = int(m.group(2))
                # Skip duplicates (aliases) — keep first occurrence
                if ability_id not in abilities:
                    abilities[ability_id] = const_name
    return abilities


def main() -> None:
    abilities = parse_abilities(ABILITIES_H)
    os.makedirs(OUT_DIR, exist_ok=True)

    existed = 0
    created = 0

    for ability_id in sorted(abilities):
        filename = f"ability_{ability_id:04d}.tres"
        out_path = os.path.join(OUT_DIR, filename)

        if os.path.exists(out_path):
            existed += 1
            continue

        const_name = abilities[ability_id]
        ability_name = screaming_to_title(const_name)
        content = TRES_TEMPLATE.format(
            ability_id=ability_id,
            ability_name=ability_name,
        )
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(content)
        created += 1

    total = len(abilities)
    print(f"Ability IDs found : {total}")
    print(f"Already existed   : {existed}")
    print(f"Created           : {created}")
    print(f"Total in out dir  : {existed + created}")


if __name__ == "__main__":
    main()
