#!/usr/bin/env python3
"""
Generate data/moves/move_NNNN.tres files for Tier-1 moves.

Usage (from project root):
    python3 scripts/gen_moves.py

One file per move, path: data/moves/move_NNNN.tres where NNNN is the move's
canonical ID (zero-padded to 4 digits), matching include/constants/moves.h in
pokeemerald_expansion.

Why no uid= in [ext_resource]:
    Godot resolves ext_resource references by UID at runtime via uid_cache.bin,
    a binary populated by the editor during project import. Handwritten files
    that embed a UID the cache hasn't seen yet produce "invalid UID" warnings.
    Path-only references always work without a cache entry and produce no
    warnings. Add a move = drop a file; nothing else to update.

Sources for move data:
    pokeemerald_expansion/src/data/moves_info.h   (GEN_LATEST config values)
    pokeemerald_expansion/include/constants/moves.h (canonical IDs)
"""

import os
import pathlib

# category constants (matches MoveData.category field)
PHYS = 0
SPEC = 1
STAT = 2

# Each entry: (id, name, type, category, power, accuracy, pp,
#              makes_contact, priority, critical_hit_stage)
#
# accuracy=100 is the MoveData default (omitted from .tres when unchanged).
# accuracy=0 means always hits (moves like Swift, Aerial Ace).
# Moves with secondary effects (Body Slam 30% para, Ember 10% burn, etc.)
# are included here; the effect field stays 0 until M5 wires secondaries.
#
# Source per move (moves_info.h line approx):
#   Pound(1)        L67    Normal/Phys/40/100/35, contact
#   Karate Chop(2)  L75    Fighting/Phys/50/100/25, contact, crit_stage=1
#   Scratch(10)     L131   Normal/Phys/40/100/35, contact
#   Wing Attack(17) L218   Flying/Phys/60/100/35, contact
#   Vine Whip(22)   L614   Grass/Phys/45/100/25, contact (B_UPDATED>=GEN_6)
#   Tackle(33)      L893   Normal/Phys/40/100/35, contact (B_UPDATED>=GEN_7)
#   Body Slam(34)   L901   Normal/Phys/85/100/15, contact
#   Ember(52)       L1422  Fire/Spec/40/100/25
#   Flamethrower(53)L1438  Fire/Spec/90/100/15
#   Water Gun(55)   L1468  Water/Spec/40/100/25
#   Surf(57)        L1536  Water/Spec/90/100/15 (B_UPDATED>=GEN_6)
#   Ice Beam(58)    L1553  Ice/Spec/90/100/10
#   Psybeam(60)     L1589  Psychic/Spec/65/100/20
#   Strength(70)    L1728  Normal/Phys/80/100/15, contact
#   Thunder Shock(84)L1924 Electric/Spec/40/100/30
#   Rock Throw(88)  L1983  Rock/Phys/50/90/15
#   Quick Attack(98)L2102  Normal/Phys/40/100/30, contact, priority=1
#   Swift(129)      L3508  Normal/Spec/60/always/20
#   Rock Slide(157) L4232  Rock/Phys/75/90/10
#   Aerial Ace(332) L9062  Flying/Phys/60/always/20, contact
MOVES = [
    #  id   name              type cat  pwr  acc  pp  con pri crit
    (  1, "Pound",              1, PHYS,  40, 100, 35, True,  0, 0),
    (  2, "Karate Chop",        2, PHYS,  50, 100, 25, True,  0, 1),
    ( 10, "Scratch",            1, PHYS,  40, 100, 35, True,  0, 0),
    ( 17, "Wing Attack",        3, PHYS,  60, 100, 35, True,  0, 0),
    ( 22, "Vine Whip",         13, PHYS,  45, 100, 25, True,  0, 0),
    ( 33, "Tackle",             1, PHYS,  40, 100, 35, True,  0, 0),
    ( 34, "Body Slam",          1, PHYS,  85, 100, 15, True,  0, 0),
    ( 52, "Ember",             11, SPEC,  40, 100, 25, False, 0, 0),
    ( 53, "Flamethrower",      11, SPEC,  90, 100, 15, False, 0, 0),
    ( 55, "Water Gun",         12, SPEC,  40, 100, 25, False, 0, 0),
    ( 57, "Surf",              12, SPEC,  90, 100, 15, False, 0, 0),
    ( 58, "Ice Beam",          16, SPEC,  90, 100, 10, False, 0, 0),
    ( 60, "Psybeam",           15, SPEC,  65, 100, 20, False, 0, 0),
    ( 70, "Strength",           1, PHYS,  80, 100, 15, True,  0, 0),
    ( 84, "Thunder Shock",     14, SPEC,  40, 100, 30, False, 0, 0),
    ( 88, "Rock Throw",         6, PHYS,  50,  90, 15, False, 0, 0),
    ( 98, "Quick Attack",       1, PHYS,  40, 100, 30, True,  1, 0),
    (129, "Swift",              1, SPEC,  60,   0, 20, False, 0, 0),
    (157, "Rock Slide",         6, PHYS,  75,  90, 10, False, 0, 0),
    (332, "Aerial Ace",         3, PHYS,  60,   0, 20, True,  0, 0),
]

# MoveData field defaults — fields at their default value are omitted.
DEFAULTS = {
    "type":               0,
    "category":           0,    # Physical
    "power":              0,
    "accuracy":         100,
    "pp":                 5,
    "makes_contact":  False,
    "priority":           0,
    "critical_hit_stage": 0,
}

HEADER = """\
[gd_resource type="Resource" script_class="MoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/move_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""


def _gdscript_bool(v: bool) -> str:
    return "true" if v else "false"


def render(move_id, name, type_, category, power, accuracy, pp,
           makes_contact, priority, critical_hit_stage) -> str:
    lines = [HEADER.rstrip(), ""]
    lines.append(f'move_name = "{name}"')

    fields = [
        ("type",               type_),
        ("category",           category),
        ("power",              power),
        ("accuracy",           accuracy),
        ("pp",                 pp),
        ("makes_contact",      makes_contact),
        ("priority",           priority),
        ("critical_hit_stage", critical_hit_stage),
    ]

    for field, value in fields:
        default = DEFAULTS[field]
        if value == default:
            continue
        if isinstance(value, bool):
            lines.append(f"{field} = {_gdscript_bool(value)}")
        else:
            lines.append(f"{field} = {value}")

    return "\n".join(lines) + "\n"


def main():
    project_root = pathlib.Path(__file__).parent.parent
    out_dir = project_root / "data" / "moves"
    out_dir.mkdir(parents=True, exist_ok=True)

    for row in MOVES:
        move_id, name, type_, category, power, accuracy, pp, \
            makes_contact, priority, critical_hit_stage = row

        content = render(move_id, name, type_, category, power, accuracy, pp,
                         makes_contact, priority, critical_hit_stage)
        path = out_dir / f"move_{move_id:04d}.tres"
        path.write_text(content, encoding="utf-8")
        print(f"  wrote {path.name}")

    print(f"Done — {len(MOVES)} files in {out_dir}")


if __name__ == "__main__":
    main()
