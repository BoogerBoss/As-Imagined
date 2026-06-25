#!/usr/bin/env python3
"""
Generate data/moves/move_NNNN.tres files for Tier 1 and Tier 2 moves.

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

# ── Category constants (MoveData.category) ───────────────────────────────────
PHYS = 0
SPEC = 1
STAT = 2

# ── Type constants (TypeChart TYPE_* values, matches type_chart.gd) ──────────
TYPE_NONE     = 0
TYPE_NORMAL   = 1
TYPE_FIGHTING = 2
TYPE_FLYING   = 3
TYPE_POISON   = 4
TYPE_GROUND   = 5
TYPE_ROCK     = 6
TYPE_BUG      = 7
TYPE_GHOST    = 8
TYPE_STEEL    = 9
TYPE_FIRE     = 11
TYPE_WATER    = 12
TYPE_GRASS    = 13
TYPE_ELECTRIC = 14
TYPE_PSYCHIC  = 15
TYPE_ICE      = 16
TYPE_DRAGON   = 17
TYPE_DARK     = 18
TYPE_FAIRY    = 19

# ── Secondary effect constants (MoveData.SE_* values) ────────────────────────
SE_NONE      = 0
SE_BURN      = 1
SE_FREEZE    = 2
SE_PARALYSIS = 3
SE_SLEEP     = 4
SE_TOXIC     = 5
SE_CONFUSION = 6
SE_FLINCH    = 7

# ── Stat stage index constants (BattlePokemon.STAGE_* values) ────────────────
STAGE_ATK      = 0
STAGE_DEF      = 1
STAGE_SPATK    = 2
STAGE_SPDEF    = 3
STAGE_SPEED    = 4
STAGE_ACCURACY = 5
STAGE_EVASION  = 6

# ── Move table (dict-based) ───────────────────────────────────────────────────
#
# Required keys: id, name
# Optional keys (omitted = MoveData default):
#   type (default=0=NONE)          accuracy (default=100)
#   category (default=PHYS)        pp (default=5)
#   power (default=0)              makes_contact (default=False)
#   priority (default=0)           critical_hit_stage (default=0)
#   thaws_user (default=False)     powder_move (default=False)
#   sound_move (default=False)
#   secondary_effect (default=SE_NONE)
#   secondary_chance (default=0)    # 0 = guaranteed (used for primary-effect status moves)
#   stat_change_stat (default=-1)   # -1 = no stat change
#   stat_change_amount (default=0)
#   stat_change_self (default=False)
#
# Sources per move (moves_info.h approximate line in pokeemerald_expansion):
#   Pound(1)            L67     Normal/Phys/40/100/35, contact
#   Karate Chop(2)      L75     Fighting/Phys/50/100/25, contact, crit=1
#   Scratch(10)         L131    Normal/Phys/40/100/35, contact
#   Swords Dance(14)    L166    Normal/Status/0/20, +2 Atk self
#   Wing Attack(17)     L218    Flying/Phys/60/100/35, contact
#   Vine Whip(22)       L614    Grass/Phys/45/100/25, contact (B_UPDATED>=GEN_6)
#   Sand Attack(28)     L699    Ground/Status/100/15, -1 Acc foe (type=Ground since Gen2)
#   Tackle(33)          L893    Normal/Phys/40/100/35, contact (B_UPDATED>=GEN_7)
#   Body Slam(34)       L901    Normal/Phys/85/100/15, contact; 30% para
#   Tail Whip(39)       L1000   Normal/Status/100/30, -1 Def foe
#   Leer(43)            L1073   Normal/Status/100/30, -1 Def foe
#   Growl(45)           L1090   Normal/Status/100/40, -1 Atk foe, sound_move
#   Ember(52)           L1422   Fire/Spec/40/100/25; 10% burn
#   Flamethrower(53)    L1438   Fire/Spec/90/100/15; 10% burn
#   Water Gun(55)       L1468   Water/Spec/40/100/25
#   Surf(57)            L1536   Water/Spec/90/100/15 (B_UPDATED>=GEN_6)
#   Ice Beam(58)        L1553   Ice/Spec/90/100/10; 10% freeze
#   Psybeam(60)         L1589   Psychic/Spec/65/100/20; 10% confusion
#   Strength(70)        L1728   Normal/Phys/80/100/15, contact
#   Sleep Powder(79)    L1890   Grass/Status/75/15, sleep, powder_move
#   Thunder Shock(84)   L1924   Electric/Spec/40/100/30; 10% para
#   Thunder Wave(86)    L1946   Electric/Status/90/20, paralysis
#   Rock Throw(88)      L1983   Rock/Phys/50/90/15
#   Toxic(92)           L2045   Poison/Status/90/10, bad poison
#   Quick Attack(98)    L2102   Normal/Phys/40/100/30, contact, priority=1
#   Confuse Ray(109)    L2296   Ghost/Status/100/10, confusion
#   Swift(129)          L3508   Normal/Spec/60/always/20
#   Rock Slide(157)     L4232   Rock/Phys/75/90/10; 30% flinch
#   Flame Wheel(172)    L4621   Fire/Phys/60/100/25, contact, thaws_user; 10% burn
#   Will-O-Wisp(261)    L6962   Fire/Status/85/15, burn
#   Aerial Ace(332)     L9062   Flying/Phys/60/always/20, contact

MOVES = [
    # ── Tier 1: simple damaging moves ────────────────────────────────────────
    {"id":   1, "name": "Pound",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 35,
     "makes_contact": True},

    {"id":   2, "name": "Karate Chop",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 50, "accuracy": 100, "pp": 25,
     "makes_contact": True, "critical_hit_stage": 1},

    {"id":  10, "name": "Scratch",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 35,
     "makes_contact": True},

    {"id":  17, "name": "Wing Attack",
     "type": TYPE_FLYING, "category": PHYS, "power": 60, "accuracy": 100, "pp": 35,
     "makes_contact": True},

    {"id":  22, "name": "Vine Whip",
     "type": TYPE_GRASS, "category": PHYS, "power": 45, "accuracy": 100, "pp": 25,
     "makes_contact": True},

    {"id":  33, "name": "Tackle",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 35,
     "makes_contact": True},

    # Body Slam: 30% paralysis secondary
    {"id":  34, "name": "Body Slam",
     "type": TYPE_NORMAL, "category": PHYS, "power": 85, "accuracy": 100, "pp": 15,
     "makes_contact": True,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 30},

    # Ember: 10% burn secondary
    {"id":  52, "name": "Ember",
     "type": TYPE_FIRE, "category": SPEC, "power": 40, "accuracy": 100, "pp": 25,
     "secondary_effect": SE_BURN, "secondary_chance": 10},

    # Flamethrower: 10% burn secondary
    {"id":  53, "name": "Flamethrower",
     "type": TYPE_FIRE, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15,
     "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id":  55, "name": "Water Gun",
     "type": TYPE_WATER, "category": SPEC, "power": 40, "accuracy": 100, "pp": 25},

    {"id":  57, "name": "Surf",
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15},

    # Ice Beam: 10% freeze secondary
    {"id":  58, "name": "Ice Beam",
     "type": TYPE_ICE, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_FREEZE, "secondary_chance": 10},

    # Psybeam: 10% confusion secondary
    {"id":  60, "name": "Psybeam",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 65, "accuracy": 100, "pp": 20,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 10},

    {"id":  70, "name": "Strength",
     "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True},

    # Thunder Shock: 10% paralysis secondary
    {"id":  84, "name": "Thunder Shock",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 40, "accuracy": 100, "pp": 30,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 10},

    {"id":  88, "name": "Rock Throw",
     "type": TYPE_ROCK, "category": PHYS, "power": 50, "accuracy": 90, "pp": 15},

    {"id":  98, "name": "Quick Attack",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 30,
     "makes_contact": True, "priority": 1},

    {"id": 129, "name": "Swift",
     "type": TYPE_NORMAL, "category": SPEC, "power": 60, "accuracy": 0, "pp": 20},

    # Rock Slide: 30% flinch secondary
    {"id": 157, "name": "Rock Slide",
     "type": TYPE_ROCK, "category": PHYS, "power": 75, "accuracy": 90, "pp": 10,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 332, "name": "Aerial Ace",
     "type": TYPE_FLYING, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20,
     "makes_contact": True},

    # ── Tier 2: stat-changing moves ───────────────────────────────────────────

    # Swords Dance: +2 Atk self (source: STAT_CHANGE_EFFECT_PLUS(STAT_ATK, 2))
    {"id":  14, "name": "Swords Dance",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 2, "stat_change_self": True},

    # Sand Attack: -1 Acc foe (source: STAT_CHANGE_EFFECT_MINUS(STAT_ACC, 1))
    {"id":  28, "name": "Sand Attack",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 100, "pp": 15,
     "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1},

    # Tail Whip: -1 Def foe
    {"id":  39, "name": "Tail Whip",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1},

    # Leer: -1 Def foe
    {"id":  43, "name": "Leer",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1},

    # Growl: -1 Atk foe, sound_move=true (source: struct MoveInfo.soundMove)
    {"id":  45, "name": "Growl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 40,
     "sound_move": True,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": -1},

    # ── Tier 2: status-inflicting moves ──────────────────────────────────────

    # Sleep Powder: primary sleep (guaranteed), powder_move=true
    {"id":  79, "name": "Sleep Powder",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 75, "pp": 15,
     "powder_move": True,
     "secondary_effect": SE_SLEEP, "secondary_chance": 0},

    # Thunder Wave: primary paralysis (guaranteed), Electric type (blocks vs Ground)
    {"id":  86, "name": "Thunder Wave",
     "type": TYPE_ELECTRIC, "category": STAT, "accuracy": 90, "pp": 20,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 0},

    # Toxic: primary bad poison (guaranteed)
    {"id":  92, "name": "Toxic",
     "type": TYPE_POISON, "category": STAT, "accuracy": 90, "pp": 10,
     "secondary_effect": SE_TOXIC, "secondary_chance": 0},

    # Confuse Ray: primary confusion (guaranteed), Ghost type (blocks vs Normal)
    {"id": 109, "name": "Confuse Ray",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 0},

    # Will-O-Wisp: primary burn (guaranteed), Fire type
    {"id": 261, "name": "Will-O-Wisp",
     "type": TYPE_FIRE, "category": STAT, "accuracy": 85, "pp": 15,
     "secondary_effect": SE_BURN, "secondary_chance": 0},

    # ── Tier 2 + closes M4 gap: Flame Wheel ──────────────────────────────────
    # Flame Wheel: Fire/Phys/60/100/25, contact, thaws_user, 10% burn secondary.
    # Added to close M4 T3d gap: a frozen attacker using a thawsUser move
    # must thaw and act. Flame Wheel is the canonical Fire move with thaws_user.
    {"id": 172, "name": "Flame Wheel",
     "type": TYPE_FIRE, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "thaws_user": True,
     "secondary_effect": SE_BURN, "secondary_chance": 10},
]

# ── MoveData field defaults (fields at default value are omitted from .tres) ──
DEFAULTS = {
    "type":                TYPE_NONE,
    "category":            PHYS,
    "power":               0,
    "accuracy":            100,
    "pp":                  5,
    "makes_contact":       False,
    "priority":            0,
    "critical_hit_stage":  0,
    "thaws_user":          False,
    "powder_move":         False,
    "sound_move":          False,
    "secondary_effect":    SE_NONE,
    "secondary_chance":    0,
    "stat_change_stat":    -1,
    "stat_change_amount":  0,
    "stat_change_self":    False,
}

HEADER = """\
[gd_resource type="Resource" script_class="MoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/move_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""

# Fields to emit in .tres, in canonical order.
FIELD_ORDER = [
    "type", "category", "power", "accuracy", "pp",
    "makes_contact", "priority", "critical_hit_stage",
    "thaws_user", "powder_move", "sound_move",
    "secondary_effect", "secondary_chance",
    "stat_change_stat", "stat_change_amount", "stat_change_self",
]


def _gdscript_bool(v: bool) -> str:
    return "true" if v else "false"


def render(move: dict) -> str:
    lines = [HEADER.rstrip(), ""]
    lines.append(f'move_name = "{move["name"]}"')

    for field in FIELD_ORDER:
        value = move.get(field, DEFAULTS.get(field))
        default = DEFAULTS.get(field)
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

    for move in MOVES:
        content = render(move)
        path = out_dir / f"move_{move['id']:04d}.tres"
        path.write_text(content, encoding="utf-8")
        print(f"  wrote {path.name}")

    print(f"Done — {len(MOVES)} files in {out_dir}")


if __name__ == "__main__":
    main()
