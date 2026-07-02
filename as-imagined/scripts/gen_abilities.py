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

    # ── M17a: Tier A move effects — damage-pipeline modifiers, no new infrastructure ──
    # Source: docs/m17_recon.md Sections 4/5 (original) and 9 (addendum) Bucket A;
    # final list cross-checked against Section 13's exclusions in docs/decisions.md [M17a].

    # Source: battle_util.c :: GetAttackStatModifier (L6821-6836): matching move type
    #   AND hp <= maxHP/3 → ×1.5 (attacker's own Attack/Sp.Atk stat, either category).
    {"id":  65, "name": "Overgrow",
     "description": "Powers up Grass-type moves when the Pokémon's HP is low.",
     "ai_rating": 6},
    {"id":  66, "name": "Blaze",
     "description": "Powers up Fire-type moves when the Pokémon's HP is low.",
     "ai_rating": 6},
    {"id":  67, "name": "Torrent",
     "description": "Powers up Water-type moves when the Pokémon's HP is low.",
     "ai_rating": 6},
    {"id":  68, "name": "Swarm",
     "description": "Powers up Bug-type moves when the Pokémon's HP is low.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetDefenseStatModifier (L7089-7095, usesDefStat-gated =
    #   physical only): statused AND physical → ×1.5 Defense.
    {"id":  63, "name": "Marvel Scale",
     "description": "Boosts the Defense stat if the Pokémon has a status condition.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetTotalAccuracy (L10285-10287): unconditional ×1.30.
    {"id":  14, "name": "Compound Eyes",
     "description": "Raises the Pokémon's accuracy.",
     "ai_rating": 7},

    # Source: battle_util.c :: CalcCritChanceStage (L7848-7859): blocks critical hits
    #   against the holder outright, overriding even an always-crit effect.
    {"id":   4, "name": "Battle Armor",
     "description": "Hard armor protects the Pokémon from critical hits.",
     "ai_rating": 4},
    {"id":  75, "name": "Shell Armor",
     "description": "A hard shell protects the Pokémon from critical hits.",
     "ai_rating": 4},

    # Source: battle_util.c :: GetDefenderAbilitiesModifier (L7407-7412): defender at
    #   max HP → ×0.5 damage taken.
    {"id": 136, "name": "Multiscale",
     "description": "Reduces the amount of damage the Pokémon takes while its HP is full.",
     "ai_rating": 7},

    # Source: battle_util.c :: GetDefenderAbilitiesModifier (L7414-7420): super-effective
    #   hit (typeEffectivenessModifier >= 2.0) → ×0.75 damage taken.
    {"id": 111, "name": "Filter",
     "description": "Reduces the power of supereffective attacks taken.",
     "ai_rating": 7},
    {"id": 116, "name": "Solid Rock",
     "description": "Reduces the power of supereffective attacks taken.",
     "ai_rating": 7},

    # Source: battle_util.c :: GetAttackerAbilitiesModifier (L7392-7395): not-very-effective
    #   hit (typeEffectivenessModifier <= 0.5) → ×2.0 damage dealt.
    {"id": 110, "name": "Tinted Lens",
     "description": "Powers up 'not very effective' moves to deal regular damage.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetSameTypeAttackBonusModifier (L7244/L7247): STAB ×2.0
    #   instead of ×1.5.
    {"id":  91, "name": "Adaptability",
     "description": "Powers up moves of the same type as the Pokémon.",
     "ai_rating": 8},

    # Source: battle_move_resolution.c (L3373-3396): blocks standard move recoil damage
    #   entirely (not Struggle recoil, not Life Orb).
    {"id":  69, "name": "Rock Head",
     "description": "Protects the Pokémon from recoil damage.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetAttackerAbilitiesModifier (L7386-7388): critical hit →
    #   ×1.5 damage dealt (stacks with the normal crit multiplier).
    {"id":  97, "name": "Sniper",
     "description": "Powers up moves if they become critical hits.",
     "ai_rating": 6},

    # Source: battle_util.c (L10182-10193): moves from/against this Pokémon always hit.
    {"id":  99, "name": "No Guard",
     "description": "The Pokémon and its target are always hit by attacks.",
     "ai_rating": 5},

    # Source: battle_util.c :: GetAttackStatModifier (L6868-6870): statused AND physical
    #   → ×1.5 Attack. Also exempts the holder from burn's physical-damage halving
    #   (GetBurnOrFrostBiteModifier, L7285).
    {"id":  62, "name": "Guts",
     "description": "Boosts Attack if the Pokémon has a status condition.",
     "ai_rating": 7},

    # Source: battle_util.c :: GetAttackStatModifier (L6860-6862): physical → ×1.5 Attack.
    #   Also GetTotalAccuracy (L10291-10293): physical → ×0.80 accuracy.
    {"id":  55, "name": "Hustle",
     "description": "Boosts Attack, but lowers accuracy for physical moves.",
     "ai_rating": 6},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers, "target's abilities"
    #   block (L6607-6611): moveType == Fire → ×0.5 base power (folded into
    #   defense_damage_modifier_uq412 alongside Thick Fat's equivalent simplification).
    {"id":  85, "name": "Heatproof",
     "description": "Halves the damage from Fire-type moves that hit the Pokémon.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetAttackStatModifier (L6812-6813): hp <= maxHP/2 → ×0.5
    #   Attack/Sp.Atk (either category).
    {"id": 129, "name": "Defeatist",
     "description": "Lowers stats when HP becomes half or less.",
     "ai_rating": 3},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6469-6471): poisoned
    #   (incl. toxic) AND physical → ×1.5 base power.
    {"id": 137, "name": "Toxic Boost",
     "description": "Powers up physical attacks when the Pokémon is poisoned.",
     "ai_rating": 6},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6465-6467): burned AND
    #   special → ×1.5 base power.
    {"id": 138, "name": "Flare Boost",
     "description": "Powers up special attacks when the Pokémon is burned.",
     "ai_rating": 6},

    # Source: battle_util.c (L3965-3966, same case block as Rough Skin): contact →
    #   attacker.maxHP / 8 damage.
    {"id": 160, "name": "Iron Barbs",
     "description": "Inflicts damage on the attacker for making direct contact.",
     "ai_rating": 6},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6486-6490): moveType in
    #   {Steel, Rock, Ground} AND sandstorm active → ×1.3 base power.
    {"id": 159, "name": "Sand Force",
     "description": "Boosts the power of Rock-, Ground-, and Steel-type moves in a sandstorm.",
     "ai_rating": 5},

    # Source: battle_util.c :: GetDefenseStatModifier (L7099-7103, usesDefStat-gated =
    #   physical only): physical → ×2.0 Defense stat (equivalent to ×0.5 damage taken).
    {"id": 169, "name": "Fur Coat",
     "description": "Halves the damage from physical moves.",
     "ai_rating": 8},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6510-6512): move makes
    #   contact → ×1.3 base power.
    {"id": 181, "name": "Tough Claws",
     "description": "Powers up moves that make direct contact.",
     "ai_rating": 7},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6526-6528): moveType ==
    #   Steel → ×1.5 base power.
    {"id": 200, "name": "Steelworker",
     "description": "Powers up Steel-type moves.",
     "ai_rating": 6},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers, "attacker partner's
    #   abilities" block (L6588-6591): ally has Battery AND move is special → ×1.3
    #   base power. Doubles-only.
    {"id": 217, "name": "Battery",
     "description": "Powers up its ally's special moves.",
     "ai_rating": 4},

    # Source: battle_util.c :: GetDefenderAbilitiesModifier (L7441-7444): move is
    #   Special → ×0.5 damage taken.
    {"id": 246, "name": "Ice Scales",
     "description": "Halves the damage from special moves.",
     "ai_rating": 7},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers, "attacker partner's
    #   abilities" block (L6592-6593): ally has Power Spot → ×1.3 base power,
    #   unconditional. Doubles-only.
    {"id": 249, "name": "Power Spot",
     "description": "Just being next to the Pokémon powers up moves.",
     "ai_rating": 4},

    # Source: battle_util.c :: CalcMoveBasePowerAfterModifiers (L6558-6560, self) and
    #   the "attacker partner's abilities" block (L6595-6597, ally): moveType == Steel →
    #   ×1.5 base power, checked independently for self and ally.
    {"id": 252, "name": "Steely Spirit",
     "description": "Powers up allies' and the user's Steel-type moves.",
     "ai_rating": 6},

    # Source: battle_util.c :: GetAttackStatModifier (L6891-6893): moveType == Rock →
    #   ×1.5 Attack, no other condition.
    {"id": 276, "name": "Rocky Payload",
     "description": "Powers up Rock-type moves.",
     "ai_rating": 6},

    # ── M17b: Tier B move effects — stat-stage-system interactions ──────────────────
    # Source: docs/m17_recon.md Sections 4/5 (original) and 9 (addendum) Bucket B;
    # final list locked in docs/decisions.md [M17b].

    # Source: battle_stat_change.c :: AdjustStatStage (L813-815): stage = 2 * stage.
    {"id": 86, "name": "Simple",
     "description": "Doubles the effects of stat changes.",
     "ai_rating": 8},

    # Source: battle_stat_change.c :: AdjustStatStage (L808-810): stage = -1 * stage.
    {"id": 126, "name": "Contrary",
     "description": "Makes stat changes have an opposite effect.",
     "ai_rating": 8},

    # Source: battle_util.c L6785/L7072 (attacker/defender stage reset in damage calc),
    #   L10251/L10256 (accuracy/evasion stage reset) — 4 touch-points, all reset the
    #   relevant stage to neutral unconditionally.
    {"id": 109, "name": "Unaware",
     "description": "Ignores the target's stat changes.",
     "ai_rating": 7},

    # Source: battle_stat_change.c :: CanAbilityPreventStatLoss (L823-828): blocks ALL
    #   stat reductions from other Pokémon.
    {"id": 29, "name": "Clear Body",
     "description": "Prevents other Pokémon from lowering its stats.",
     "ai_rating": 6},
    {"id": 73, "name": "White Smoke",
     "description": "Prevents other Pokémon from lowering its stats.",
     "ai_rating": 6},

    # Source: battle_stat_change.c :: AbilityPreventsSpecificStatDrop (L843-850):
    #   blocks only the named stat's reduction from others.
    {"id": 52, "name": "Hyper Cutter",
     "description": "Prevents other Pokémon from lowering its Attack stat.",
     "ai_rating": 5},
    {"id": 51, "name": "Keen Eye",
     "description": "Prevents other Pokémon from lowering its accuracy; ignores the target's evasion boosts.",
     "ai_rating": 5},
    {"id": 145, "name": "Big Pecks",
     "description": "Prevents other Pokémon from lowering its Defense stat.",
     "ai_rating": 5},

    # Source: battle_script_commands.c :: BS_TryDefiantRattled (L13885-13905) +
    #   ShouldDefiantCompetitiveActivate (battle_util.c L1149-1168): a stat decrease
    #   from an opponent raises SpA (Competitive) or Atk (Defiant) by 2.
    {"id": 172, "name": "Competitive",
     "description": "Boosts Sp. Atk sharply when a stat is lowered by another Pokémon.",
     "ai_rating": 7},
    {"id": 128, "name": "Defiant",
     "description": "Boosts Attack sharply when a stat is lowered by another Pokémon.",
     "ai_rating": 7},

    # Source: battle_util.c :: ABILITY_WEAK_ARMOR case (L3826-3841): physical hit →
    #   Def -1, Spe +2 (B_WEAK_ARMOR_SPEED >= GEN_7).
    {"id": 133, "name": "Weak Armor",
     "description": "Physical hits lower its Defense but sharply raise its Speed.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_JUSTIFIED case (L3772-3783): Dark-type hit → Atk +1.
    {"id": 154, "name": "Justified",
     "description": "Being hit by a Dark-type move boosts Attack.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_RATTLED case (L3790-3801, hit-triggered half) +
    #   ABILITY_RATTLED in try_switch_in's Intimidate branch (being-Intimidated half):
    #   Bug/Dark/Ghost hit OR being Intimidated → Spe +1.
    {"id": 155, "name": "Rattled",
     "description": "Bug, Dark, or Ghost hits, or being intimidated, boost its Speed.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_ANGER_POINT case (L3911-3920): critical hit
    #   received → Atk set to +6 (max) stages.
    {"id": 83, "name": "Anger Point",
     "description": "Maximizes Attack after being hit by a critical hit.",
     "ai_rating": 4},

    # Source: battle_move_resolution.c :: CancelerFlinch (L303-307): flinched → Spe +1.
    {"id": 80, "name": "Steadfast",
     "description": "Raises Speed each time the Pokémon flinches.",
     "ai_rating": 4},

    # Source: battle_util.c :: ABILITY_DOWNLOAD case (L3151-3163) + GetDownloadStat
    #   (L10957-10979): compares opposing Def vs Sp. Def (summed, stage-adjusted) on
    #   switch-in, raises whichever of Atk/SpA corresponds to the opponents' weaker side.
    {"id": 88, "name": "Download",
     "description": "Compares opponents' stats before raising its own Attack or Sp. Atk.",
     "ai_rating": 7},

    # Source: battle_util.c :: ABILITY_MOODY case (L3613-3635): end of turn, +2 to one
    #   random non-maxed stat, -1 to a different random non-minned stat.
    {"id": 141, "name": "Moody",
     "description": "Raises one stat sharply and lowers another every turn.",
     "ai_rating": 9},

    # Source: battle_util.c (L4467-4472, shared dispatch case with excluded legendary/
    #   UB abilities): Attack +1 for the Pokémon that KO'd the opponent.
    {"id": 153, "name": "Moxie",
     "description": "Boosts Attack after knocking out any Pokémon.",
     "ai_rating": 8},

    # Source: battle_stat_change.c :: IsFlowerVeilBlocked/StatChange_IsFlowerVeilProtected
    #   (L601-634): blocks all stat reductions on a Grass-type ally (or self).
    {"id": 166, "name": "Flower Veil",
     "description": "Ally Grass-type Pokémon are protected from stat reduction.",
     "ai_rating": 5},

    # Source: battle_util.c :: IsAbilityOnSide(ABILITY_SWEET_VEIL) (L5322-5327): immune
    #   to sleep, self or ally.
    {"id": 175, "name": "Sweet Veil",
     "description": "Prevents itself and ally Pokémon from falling asleep.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_GOOEY/ABILITY_TANGLING_HAIR case (L3923-3958,
    #   shared): contact → attacker Speed -1, unconditional.
    {"id": 183, "name": "Gooey",
     "description": "Contact with the Pokémon lowers the attacker's Speed stat.",
     "ai_rating": 6},
    {"id": 221, "name": "Tangling Hair",
     "description": "Contact with the Pokémon lowers the attacker's Speed stat.",
     "ai_rating": 6},

    # Source: battle_util.c :: ABILITY_STAMINA case (L3814-3825): any damaging hit →
    #   Def +1.
    {"id": 192, "name": "Stamina",
     "description": "Boosts Defense when hit by an attack.",
     "ai_rating": 7},

    # Source: battle_util.c :: ABILITY_WATER_COMPACTION case (L3802-3813): Water-type
    #   hit → Def +2.
    {"id": 195, "name": "Water Compaction",
     "description": "Boosts Defense sharply when hit by a Water-type move.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_BERSERK case (L3732-3742): HP crosses from >50%
    #   to <=50% from this hit → SpA +1.
    {"id": 201, "name": "Berserk",
     "description": "Boosts Sp. Atk when HP drops to half or less from a hit.",
     "ai_rating": 6},

    # Source: battle_util.c :: ABILITY_COTTON_DOWN case (L4155-4165): any damaging hit →
    #   ALL other battlers' Speed -1.
    {"id": 238, "name": "Cotton Down",
     "description": "Being hit scatters cotton, lowering the Speed of all other Pokémon.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_STEAM_ENGINE case (L4169-4179): Fire/Water hit →
    #   Spe +6 (max).
    {"id": 243, "name": "Steam Engine",
     "description": "Maximizes Speed when hit by a Fire- or Water-type move.",
     "ai_rating": 6},

    # Source: battle_util.c :: ABILITY_PASTEL_VEIL case (L3073-3081, switch-in poison
    #   cure) + IsAbilityOnSide(ABILITY_PASTEL_VEIL) (L5254-5259, ally-wide immunity).
    {"id": 257, "name": "Pastel Veil",
     "description": "Protects itself and ally Pokémon from being poisoned.",
     "ai_rating": 6},

    # Source: battle_util.c :: ABILITY_THERMAL_EXCHANGE case (L4222-4231): Fire-type
    #   hit → Atk +1.
    {"id": 270, "name": "Thermal Exchange",
     "description": "Boosts Attack when hit by a Fire-type move.",
     "ai_rating": 5},

    # Source: battle_util.c :: ABILITY_ANGER_SHELL case (L3743-3766): HP crosses from
    #   >50% to <=50% from this hit → Def -1, SpDef -1, Atk +1, SpA +1, Spe +1.
    {"id": 271, "name": "Anger Shell",
     "description": "Lowers Defense and Sp. Def but raises Attack, Sp. Atk, and Speed when HP drops to half or less.",
     "ai_rating": 6},

    # Source: battle_util.c :: NonVolatileStatus block (L5359-5361, immune to all
    #   statuses) + CalcMoveBasePowerAfterModifiers "target's abilities" (L6941-6947,
    #   Ghost-type damage taken ×0.5).
    {"id": 272, "name": "Purifying Salt",
     "description": "Protects itself from status conditions and halves damage from Ghost-type moves.",
     "ai_rating": 8},

    # Source: battle_util.c :: ABILITY_SUPERSWEET_SYRUP case (L3324-3336): switch-in,
    #   ONE-TIME ONLY, lowers all opponents' Evasion by 1.
    {"id": 306, "name": "Supersweet Syrup",
     "description": "Releases a sweet scent once when it enters battle, lowering opponents' evasiveness.",
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
