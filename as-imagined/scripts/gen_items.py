#!/usr/bin/env python3
"""
Generate data/items/item_NNNN.tres files for implemented held items.

Usage (from project root):
    python3 scripts/gen_items.py

One file per item, path: data/items/item_NNNN.tres where NNNN is the item's
canonical ID (zero-padded to 4 digits), matching include/constants/items.h in
pokeemerald_expansion — same convention as gen_moves.py/gen_abilities.py.

Scope (as of this session): only the 40 items M18a actually implemented and
tested (scenes/battle/m18a_test.gd, 160/160 assertions) — the Charcoal family,
Silk Scarf, Fairy Feather, 5 Incenses, and 17 Plates, all sharing ItemManager's
single HOLD_EFFECT_TYPE_POWER/HOLD_EFFECT_PLATE dispatch
(move_power_modifier_uq412). Every entry below was re-derived directly from
M18a's actual GDScript implementation and its own Step 0 source verification
(docs/decisions.md's [M18a] entry) — NOT copied from docs/m18_subtier_plan.md,
which predates M18a's own corrections. Every future M18 sub-tier (M18b onward)
must add its items here and regenerate, rather than wiring item data inline
into ItemManager or a test file — see docs/decisions.md's item-data-
infrastructure entry for the full rationale.

Why no uid= in [ext_resource]: same reasoning as gen_moves.py — Godot resolves
ext_resource references by UID via uid_cache.bin, populated by the editor at
import time. A handwritten UID the cache hasn't seen yet produces "invalid
UID" warnings; path-only references always work with no cache entry needed.

Sources for item data:
    pokeemerald_expansion/include/constants/items.h       (canonical IDs)
    pokeemerald_expansion/include/constants/hold_effects.h (HOLD_EFFECT_* enum)
    pokeemerald_expansion/src/data/items.h                 (holdEffectParam / secondaryId)
    pokeemerald_expansion/include/config/item.h            (I_TYPE_BOOST_POWER = GEN_LATEST)
"""

import pathlib

# ── HOLD_EFFECT_* constants (must match scripts/battle/core/item_manager.gd) ──
HOLD_EFFECT_TYPE_POWER = 43
HOLD_EFFECT_PLATE      = 89

# ── TYPE_* constants (must match scripts/data/type_chart.gd) ──────────────────
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

# ── Item table ──────────────────────────────────────────────────────────────
#
# All 40 M18a items share the exact same mechanism: ItemManager.move_power_modifier_uq412
# applies ×1.2 (UQ_4_12(1.2)=4915) to a move whose type matches hold_effect_param,
# when hold_effect is HOLD_EFFECT_TYPE_POWER or HOLD_EFFECT_PLATE. Confirmed via
# direct source read (docs/decisions.md [M18a]) that every one of these 40 items'
# real holdEffectParam resolves to 20 under this project's GEN_LATEST config — the
# 20% isn't itemized per-item, so it is NOT stored here; hold_effect_param is
# reused to carry the TYPE instead (the same deviation [M17n-4] established for
# HOLD_EFFECT_PLATE's Multitype read, extended uniformly to HOLD_EFFECT_TYPE_POWER
# too — see item_data.gd and item_manager.gd's own doc comments).

ITEMS = [
    # ── Charcoal family (16, Gen II) — HOLD_EFFECT_TYPE_POWER ────────────────
    {"id": 426, "name": "Charcoal",       "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_FIRE},
    {"id": 427, "name": "Mystic Water",   "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_WATER},
    {"id": 428, "name": "Magnet",         "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_ELECTRIC},
    {"id": 429, "name": "Miracle Seed",   "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_GRASS},
    {"id": 430, "name": "Never-Melt Ice", "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_ICE},
    {"id": 431, "name": "Black Belt",     "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_FIGHTING},
    {"id": 432, "name": "Poison Barb",    "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_POISON},
    {"id": 433, "name": "Soft Sand",      "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_GROUND},
    {"id": 434, "name": "Sharp Beak",     "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_FLYING},
    {"id": 435, "name": "Twisted Spoon",  "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_PSYCHIC},
    {"id": 436, "name": "Silver Powder",  "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_BUG},
    {"id": 437, "name": "Hard Stone",     "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_ROCK},
    {"id": 438, "name": "Spell Tag",      "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_GHOST},
    {"id": 439, "name": "Dragon Fang",    "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_DRAGON},
    {"id": 440, "name": "Black Glasses",  "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_DARK},
    {"id": 441, "name": "Metal Coat",     "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_STEEL},

    # ── Silk Scarf (Gen III) / Fairy Feather (Gen IX override) ───────────────
    {"id": 425, "name": "Silk Scarf",     "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_NORMAL},
    {"id": 799, "name": "Fairy Feather",  "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_FAIRY},

    # ── Incenses (5, Gen III/IV) — HOLD_EFFECT_TYPE_POWER ─────────────────────
    # Wave Incense (409) confirmed a genuine duplicate of Sea Incense (404) —
    # identical holdEffect/secondaryId in source, not a data-entry error.
    {"id": 404, "name": "Sea Incense",    "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_WATER},
    {"id": 406, "name": "Odd Incense",    "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_PSYCHIC},
    {"id": 407, "name": "Rock Incense",   "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_ROCK},
    {"id": 410, "name": "Rose Incense",   "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_GRASS},
    {"id": 409, "name": "Wave Incense",   "hold_effect": HOLD_EFFECT_TYPE_POWER, "hold_effect_param": TYPE_WATER},

    # ── Plates (17, Gen IV + Pixie Plate Gen VI override) — HOLD_EFFECT_PLATE ─
    {"id": 250, "name": "Flame Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_FIRE},
    {"id": 251, "name": "Splash Plate",   "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_WATER},
    {"id": 252, "name": "Zap Plate",      "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_ELECTRIC},
    {"id": 253, "name": "Meadow Plate",   "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_GRASS},
    {"id": 254, "name": "Icicle Plate",   "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_ICE},
    {"id": 255, "name": "Fist Plate",     "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_FIGHTING},
    {"id": 256, "name": "Toxic Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_POISON},
    {"id": 257, "name": "Earth Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_GROUND},
    {"id": 258, "name": "Sky Plate",      "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_FLYING},
    {"id": 259, "name": "Mind Plate",     "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_PSYCHIC},
    {"id": 260, "name": "Insect Plate",   "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_BUG},
    {"id": 261, "name": "Stone Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_ROCK},
    {"id": 262, "name": "Spooky Plate",   "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_GHOST},
    {"id": 263, "name": "Draco Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_DRAGON},
    {"id": 264, "name": "Dread Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_DARK},
    {"id": 265, "name": "Iron Plate",     "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_STEEL},
    {"id": 266, "name": "Pixie Plate",    "hold_effect": HOLD_EFFECT_PLATE, "hold_effect_param": TYPE_FAIRY},
]

HEADER = """\
[gd_resource type="Resource" script_class="ItemData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/item_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""

# Fields whose class default should be skipped in the emitted .tres — keeps
# each file lean (same convention as gen_moves.py/gen_abilities.py's DEFAULTS).
DEFAULTS = {
    "description":       "",
    "hold_effect":        0,
    "hold_effect_param":  0,
    "pocket":             0,
    "importance":         0,
    "not_consumed":       False,
    "battle_usage":       0,
    "fling_power":        0,
    "price":              0,
}

# Fields to emit in .tres, in canonical order. item_id/item_name are always
# emitted (see render()); everything else is skipped when it equals its
# class default. Only hold_effect/hold_effect_param are populated for M18a —
# description/pocket/importance/not_consumed/battle_usage/fling_power/price
# are dormant fields (confirmed unread anywhere in scripts/battle/ during this
# session's context-gathering) carried from ItemData's original M12 schema;
# left unpopulated here rather than backfilled, per this session's explicit
# "keep it lean" scope — a future tier can populate them if one actually needs
# to read one.
FIELD_ORDER = [
    "hold_effect", "hold_effect_param",
    "description", "pocket", "importance", "not_consumed", "battle_usage",
    "fling_power", "price",
]


def _gdscript_bool(v: bool) -> str:
    return "true" if v else "false"


def render(item: dict) -> str:
    lines = [HEADER.rstrip(), ""]
    lines.append(f'item_id = {item["id"]}')
    lines.append(f'item_name = "{item["name"]}"')

    for field in FIELD_ORDER:
        value = item.get(field, DEFAULTS.get(field))
        default = DEFAULTS.get(field)
        if value == default:
            continue
        if isinstance(value, bool):
            lines.append(f"{field} = {_gdscript_bool(value)}")
        elif isinstance(value, str):
            lines.append(f'{field} = "{value}"')
        else:
            lines.append(f"{field} = {value}")

    return "\n".join(lines) + "\n"


def main():
    project_root = pathlib.Path(__file__).parent.parent
    out_dir = project_root / "data" / "items"
    out_dir.mkdir(parents=True, exist_ok=True)

    for item in ITEMS:
        content = render(item)
        path = out_dir / f"item_{item['id']:04d}.tres"
        path.write_text(content, encoding="utf-8")
        print(f"  wrote {path.name}")

    print(f"Done — {len(ITEMS)} files in {out_dir}")


if __name__ == "__main__":
    main()
