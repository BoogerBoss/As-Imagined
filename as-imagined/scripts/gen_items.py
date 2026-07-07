#!/usr/bin/env python3
"""
Generate data/items/item_NNNN.tres files for implemented held items.

Usage (from project root):
    python3 scripts/gen_items.py

One file per item, path: data/items/item_NNNN.tres where NNNN is the item's
canonical ID (zero-padded to 4 digits), matching include/constants/items.h in
pokeemerald_expansion — same convention as gen_moves.py/gen_abilities.py.

Scope: M18a's 40 type-boost items (Charcoal family, Silk Scarf, Fairy Feather,
5 Incenses, 17 Plates — ItemManager.move_power_modifier_uq412) plus M18b's 23
berry/misc items (16 type-resist berries + 6 status-cure berries + Oran Berry —
ItemManager.defender_item_modifier_uq412 / status_cure_berry_cures /
confusion_cure_berry_cures / hp_threshold_berry_heal). Every entry was
re-derived directly from source (include/constants/items.h, src/data/items.h)
during each tier's own Step 0 — NOT copied from docs/m18_subtier_plan.md, which
predates every tier's own corrections. Every future M18 sub-tier must add its
items here and regenerate, rather than wiring item data inline into
ItemManager or a test file — see docs/decisions.md's item-data-infrastructure
entry for the full rationale.

NOTE (found during M18b, not fixed — out of scope): the 15 items M12 already
implemented (Leftovers, Lum Berry, Choice Band, Sitrus Berry, Choice Specs,
Choice Scarf, the 4 Weather Rocks, Life Orb, Chilan Berry, Occa Berry,
Heavy-Duty Boots, Utility Umbrella) predate this whole pipeline and are still
purely inline-constructed in scenes/battle/item_test.gd, with no entry here and
no .tres file — this is a real, flagged inconsistency (the resist-berry and
status-cure-berry dispatches now have BOTH pipeline-backed items (M18b's 22)
and inline-only items (Occa/Chilan/Lum) feeding the exact same mechanism).
Recommend a future cleanup pass migrate those 15 into this file too, but doing
so now was judged out of scope for M18b — those items already ship via M12's
own tested, working implementation and touching them risks an unrelated
regression.

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
HOLD_EFFECT_RESTORE_HP      = 1   # Oran Berry — flat heal (M18b)
HOLD_EFFECT_CURE_PAR        = 2   # Cheri Berry (M18b)
HOLD_EFFECT_CURE_SLP        = 3   # Chesto Berry (M18b)
HOLD_EFFECT_CURE_PSN        = 4   # Pecha Berry — cures Poison AND Toxic (M18b)
HOLD_EFFECT_CURE_BRN        = 5   # Rawst Berry (M18b)
HOLD_EFFECT_CURE_FRZ        = 6   # Aspear Berry (M18b)
HOLD_EFFECT_CURE_CONFUSION  = 8   # Persim Berry — clears confusion_turns, not .status (M18b)
HOLD_EFFECT_RESIST_BERRY    = 80  # type-resist berry, generic (M18b; Occa/Chilan precedent)
HOLD_EFFECT_TYPE_POWER = 43
HOLD_EFFECT_PLATE      = 89
HOLD_EFFECT_SCOPE_LENS = 40  # Scope Lens AND Razor Claw — same holdEffect in source (M18e)
HOLD_EFFECT_QUICK_CLAW = 26  # M18l: 20% act-first, param=20 read dynamically
HOLD_EFFECT_LAGGING_TAIL = 66  # M18l: Full Incense AND Lagging Tail — same holdEffect in source
HOLD_EFFECT_ATTACK_UP = 15       # M18c: Liechi Berry
HOLD_EFFECT_DEFENSE_UP = 16      # M18c: Ganlon Berry
HOLD_EFFECT_SPEED_UP = 17        # M18c: Salac Berry
HOLD_EFFECT_SP_ATTACK_UP = 18    # M18c: Petaya Berry
HOLD_EFFECT_SP_DEFENSE_UP = 19   # M18c: Apicot Berry
HOLD_EFFECT_CRITICAL_UP = 20     # M18c: Lansat Berry — sets focus_energy, not crit_stage_bonus()
HOLD_EFFECT_RANDOM_STAT_UP = 21  # M18c: Starf Berry
HOLD_EFFECT_ENIGMA_BERRY = 79    # M18c: super-effective-hit heal, not an HP threshold
HOLD_EFFECT_MICLE_BERRY = 83     # M18c: one-shot next-move accuracy boost
HOLD_EFFECT_CUSTAP_BERRY = 84    # M18c: HP-gated act-first, bypasses Unnerve

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

    # ── M18b: status-cure berries (6) — each its OWN HOLD_EFFECT_CURE_* constant,
    #    NOT HOLD_EFFECT_CURE_STATUS (that one is Lum Berry-exclusive). No
    #    hold_effect_param needed — the hold_effect itself fully specifies which
    #    status is cured (confirmed via src/data/items.h: none of these 6 set
    #    .holdEffectParam at all, unlike the type-keyed resist berries below).
    {"id": 514, "name": "Cheri Berry",    "hold_effect": HOLD_EFFECT_CURE_PAR},
    {"id": 515, "name": "Chesto Berry",   "hold_effect": HOLD_EFFECT_CURE_SLP},
    {"id": 516, "name": "Pecha Berry",    "hold_effect": HOLD_EFFECT_CURE_PSN},
    {"id": 517, "name": "Rawst Berry",    "hold_effect": HOLD_EFFECT_CURE_BRN},
    {"id": 518, "name": "Aspear Berry",   "hold_effect": HOLD_EFFECT_CURE_FRZ},
    {"id": 521, "name": "Persim Berry",   "hold_effect": HOLD_EFFECT_CURE_CONFUSION},

    # ── M18b: Oran Berry — flat 10 HP heal, same <=50%-max-HP threshold as Sitrus
    #    Berry (HasEnoughHpToEatBerry(..., 2, ...) in source, shared by both), but
    #    a DISTINCT hold_effect from Sitrus's HOLD_EFFECT_RESTORE_PCT_HP(82) — this
    #    one is HOLD_EFFECT_RESTORE_HP(1), param=10 is a flat HP amount not a percent.
    {"id": 520, "name": "Oran Berry",     "hold_effect": HOLD_EFFECT_RESTORE_HP, "hold_effect_param": 10},

    # ── M18b: type-resist berries (16) — HOLD_EFFECT_RESIST_BERRY, the exact same
    #    generic dispatch Occa Berry(Fire)/Chilan Berry(Normal) already use (those
    #    two remain inline-only in item_test.gd, per the NOTE above — not migrated
    #    here this session, out of scope).
    {"id": 551, "name": "Passho Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_WATER},
    {"id": 552, "name": "Wacan Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ELECTRIC},
    {"id": 553, "name": "Rindo Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GRASS},
    {"id": 554, "name": "Yache Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ICE},
    {"id": 555, "name": "Chople Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FIGHTING},
    {"id": 556, "name": "Kebia Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_POISON},
    {"id": 557, "name": "Shuca Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GROUND},
    {"id": 558, "name": "Coba Berry",     "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FLYING},
    {"id": 559, "name": "Payapa Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_PSYCHIC},
    {"id": 560, "name": "Tanga Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_BUG},
    {"id": 561, "name": "Charti Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ROCK},
    {"id": 562, "name": "Kasib Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GHOST},
    {"id": 563, "name": "Haban Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_DRAGON},
    {"id": 564, "name": "Colbur Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_DARK},
    {"id": 565, "name": "Babiri Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_STEEL},
    {"id": 566, "name": "Roseli Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FAIRY},

    # ── M18e: crit-stage item bonus (2) — Scope Lens and Razor Claw share the
    #    exact same HOLD_EFFECT_SCOPE_LENS value in source (src/data/items.h); not
    #    two separate constants, not conditioned on move category. Both +1 crit
    #    stage, unconditional. No hold_effect_param needed.
    {"id": 471, "name": "Scope Lens",     "hold_effect": HOLD_EFFECT_SCOPE_LENS},
    {"id": 492, "name": "Razor Claw",     "hold_effect": HOLD_EFFECT_SCOPE_LENS},

    # ── M18l: turn-order items (3) — Quick Claw (item equivalent of Quick Draw,
    #    NOT move-category-gated unlike the ability); Full Incense and Lagging Tail
    #    share the exact same HOLD_EFFECT_LAGGING_TAIL value in source, unconditional
    #    always-last (matches Stall's shape, not Mycelium Might's narrower one).
    {"id": 462, "name": "Quick Claw",     "hold_effect": HOLD_EFFECT_QUICK_CLAW, "hold_effect_param": 20},
    {"id": 408, "name": "Full Incense",   "hold_effect": HOLD_EFFECT_LAGGING_TAIL},
    {"id": 485, "name": "Lagging Tail",   "hold_effect": HOLD_EFFECT_LAGGING_TAIL},

    # ── M18c: berry HP-threshold effects (10) — all 8 of the 25%-threshold items
    #    below (5 flat-stat + Lansat + Starf + Custap) confirmed holdEffectParam=4
    #    individually via src/data/items.h, not assumed uniform. Micle/Enigma need
    #    no hold_effect_param (their thresholds are hardcoded in source; Enigma has
    #    no HP threshold at all).
    {"id": 567, "name": "Liechi Berry",   "hold_effect": HOLD_EFFECT_ATTACK_UP, "hold_effect_param": 4},
    {"id": 568, "name": "Ganlon Berry",   "hold_effect": HOLD_EFFECT_DEFENSE_UP, "hold_effect_param": 4},
    {"id": 569, "name": "Salac Berry",    "hold_effect": HOLD_EFFECT_SPEED_UP, "hold_effect_param": 4},
    {"id": 570, "name": "Petaya Berry",   "hold_effect": HOLD_EFFECT_SP_ATTACK_UP, "hold_effect_param": 4},
    {"id": 571, "name": "Apicot Berry",   "hold_effect": HOLD_EFFECT_SP_DEFENSE_UP, "hold_effect_param": 4},
    {"id": 572, "name": "Lansat Berry",   "hold_effect": HOLD_EFFECT_CRITICAL_UP, "hold_effect_param": 4},
    {"id": 573, "name": "Starf Berry",    "hold_effect": HOLD_EFFECT_RANDOM_STAT_UP, "hold_effect_param": 4},
    {"id": 574, "name": "Enigma Berry",   "hold_effect": HOLD_EFFECT_ENIGMA_BERRY},
    {"id": 575, "name": "Micle Berry",    "hold_effect": HOLD_EFFECT_MICLE_BERRY, "hold_effect_param": 4},
    {"id": 576, "name": "Custap Berry",   "hold_effect": HOLD_EFFECT_CUSTAP_BERRY, "hold_effect_param": 4},
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
