#!/usr/bin/env python3
"""
Generate data/abilities/ability_NNNN.tres files for Milestone 8 abilities.

Usage (from project root):
    python3 scripts/gen_abilities.py

One file per ability, path: data/abilities/ability_NNNN.tres where NNNN is the
canonical ability ID (zero-padded to 4 digits), matching
include/constants/abilities.h in pokeemerald_expansion.

Sources:
    pokeemerald_expansion/include/constants/abilities.h  (canonical IDs)
    pokeemerald_expansion/src/data/abilities.h            (names, AI ratings)
    pokeemerald_expansion/src/battle_util.c               (effect implementations)
"""

import pathlib

# ── Ability table ─────────────────────────────────────────────────────────────
#
# M8 abilities implemented:
#   Tier 1 (passive stat modifiers):
#     Huge Power (37)   — doubles Physical Attack
#     Pure Power (141)  — doubles Physical Attack (same effect, different ability)
#     Levitate  (26)    — immunity to Ground-type moves
#     Thick Fat (47)    — halves Fire- and Ice-type damage taken
#   Tier 2 (switch-in effects):
#     Intimidate (22)   — lowers opponent's Attack by 1 on switch-in
#     Drizzle    (2)    — sets Rain weather (stubbed; weather is M9+ scope)
#     Drought    (70)   — sets Sun weather (stubbed; weather is M9+ scope)
#     Speed Boost (3)   — raises holder's Speed by 1 at end of each turn
#   Tier 3 (contact / trigger-based):
#     Static     (9)    — 30% chance to paralyze attacker on contact
#     Flame Body (49)   — 30% chance to burn attacker on contact
#     Rough Skin (24)   — deals maxHP/8 to attacker on contact (Gen 4+)
#     Synchronize (28)  — passes status (burn/para/poison/toxic) back to inflicting Pokémon
#
# Source: include/constants/abilities.h (IDs), src/data/abilities.h (names/descriptions)

ABILITIES = [
    # ── Tier 1: passive stat modifiers ───────────────────────────────────────
    # Source: battle_util.c :: GetAttackStatModifier (L6800) — ×2.0 Physical Attack
    {"id":  37, "name": "Huge Power",
     "description": "Doubles the Pokémon's Attack stat.",
     "ai_rating": 10},

    # Source: same handler as Huge Power (case ABILITY_HUGE_POWER / ABILITY_PURE_POWER)
    {"id":  74, "name": "Pure Power",
     "description": "Doubles the Pokémon's Attack stat.",
     "ai_rating": 10},

    # Source: battle_util.c CalcTypeEffectivenessMultiplierInternal (L8257):
    #   TYPE_GROUND && ABILITY_LEVITATE && !gravity → modifier 0.0
    {"id":  26, "name": "Levitate",
     "description": "Gives immunity to Ground-type moves.",
     "ai_rating": 7},

    # Source: battle_util.c :: GetDefenseStatModifier — target switch (L6933–6941):
    #   ABILITY_THICK_FAT: (TYPE_FIRE || TYPE_ICE) → modifier ×0.5
    {"id":  47, "name": "Thick Fat",
     "description": "Halves the damage taken from Fire- and Ice-type moves.",
     "ai_rating": 6},

    # ── Tier 2: switch-in effects ──────────────────────────────────────────────
    # Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (L3310):
    #   ABILITY_INTIMIDATE → SetStatChange(all opponents, STAT_ATK, -1)
    {"id":  22, "name": "Intimidate",
     "description": "Lowers the opposing Pokémon's Attack by one stage on switch-in.",
     "ai_rating": 8},

    # Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) — weather setter.
    # Weather system not yet implemented (M9+ scope). Stubbed: ability_id present,
    # no effect until weather is added. Noted in docs/decisions.md.
    {"id":   2, "name": "Drizzle",
     "description": "Summons rain when the Pokémon enters battle. (weather stub — M9+ scope)",
     "ai_rating": 9},

    {"id":  70, "name": "Drought",
     "description": "Summons harsh sunlight when the Pokémon enters battle. (weather stub — M9+ scope)",
     "ai_rating": 9},

    # Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (L3605):
    #   ABILITY_SPEED_BOOST: !BattlerJustSwitchedIn && speed < MAX → +1 Speed
    {"id":   3, "name": "Speed Boost",
     "description": "Gradually boosts Speed at the end of each turn.",
     "ai_rating": 8},

    # ── Tier 3: contact / trigger-based ──────────────────────────────────────
    # Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...) (L4091):
    #   ABILITY_STATIC: 30% (B_ABILITY_TRIGGER_CHANCE >= GEN_4) → paralyze attacker if CanBeParalyzed
    {"id":   9, "name": "Static",
     "description": "May paralyze Pokémon that make direct contact.",
     "ai_rating": 5},

    # Source: L4114: ABILITY_FLAME_BODY: 30% → burn attacker if CanBeBurned
    {"id":  49, "name": "Flame Body",
     "description": "May burn Pokémon that make direct contact.",
     "ai_rating": 5},

    # Source: L3965: ABILITY_ROUGH_SKIN: maxHP / 8 damage on contact (B_ROUGH_SKIN_DMG >= GEN_4)
    {"id":  24, "name": "Rough Skin",
     "description": "Damages Pokémon that make direct contact.",
     "ai_rating": 6},

    # Source: battle_script_commands.c :: TrySynchronizeActivation (L2130–2162):
    #   BURN, PARALYSIS, POISON, TOXIC applied to holder → back-apply same status to attacker
    {"id":  28, "name": "Synchronize",
     "description": "Passes burn, paralysis, or poisoning to the Pokémon that inflicted it.",
     "ai_rating": 5},
]

HEADER = """\
[gd_resource type="Resource" script_class="AbilityData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/ability_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""

DEFAULTS = {
    "description": "",
    "ai_rating": 0,
    "cant_be_copied": False,
    "cant_be_swapped": False,
    "cant_be_traced": False,
    "cant_be_suppressed": False,
    "cant_be_overwritten": False,
    "breakable": False,
}

FIELD_ORDER = [
    "ability_id", "ability_name", "description", "ai_rating",
    "cant_be_copied", "cant_be_swapped", "cant_be_traced",
    "cant_be_suppressed", "cant_be_overwritten", "breakable",
]


def _gdscript_bool(v: bool) -> str:
    return "true" if v else "false"


def render(ability: dict) -> str:
    lines = [HEADER.rstrip(), ""]
    lines.append(f'ability_id = {ability["id"]}')
    lines.append(f'ability_name = "{ability["name"]}"')

    for field in FIELD_ORDER:
        if field in ("ability_id", "ability_name"):
            continue
        value = ability.get(field, DEFAULTS.get(field))
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
    out_dir = project_root / "data" / "abilities"
    out_dir.mkdir(parents=True, exist_ok=True)

    for ability in ABILITIES:
        content = render(ability)
        path = out_dir / f"ability_{ability['id']:04d}.tres"
        path.write_text(content, encoding="utf-8")
        print(f"  wrote {path.name}")

    print(f"Done — {len(ABILITIES)} files in {out_dir}")


if __name__ == "__main__":
    main()
