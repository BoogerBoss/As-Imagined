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
SE_WRAP      = 8  # [M18.5f] Bind/Wrap-family trap — see move_data.gd's own doc comment
SE_POISON    = 9  # [M18.5g] regular (non-toxic) poison — see move_data.gd's own doc comment

# ── Semi-invulnerable state constants (MoveData.SEMI_INV_* values) ───────────
SEMI_INV_NONE        = 0
SEMI_INV_UNDERGROUND = 1  # Dig
SEMI_INV_ON_AIR      = 2  # Fly, Bounce
SEMI_INV_UNDERWATER  = 3  # Dive

# ── Stat stage index constants (BattlePokemon.STAGE_* values) ────────────────
STAGE_ATK      = 0
STAGE_DEF      = 1
STAGE_SPATK    = 2
STAGE_SPDEF    = 3
STAGE_SPEED    = 4
STAGE_ACCURACY = 5
STAGE_EVASION  = 6

# ── Ban flag bitmask constants (MoveData.BAN_*) ───────────────────────────────
BAN_GRAVITY       = 1 << 0
BAN_MIRROR_MOVE   = 1 << 1
BAN_ME_FIRST      = 1 << 2
BAN_MIMIC         = 1 << 3
BAN_METRONOME     = 1 << 4   # = 16
BAN_COPYCAT       = 1 << 5
BAN_ASSIST        = 1 << 6
BAN_SLEEP_TALK    = 1 << 7
BAN_INSTRUCT      = 1 << 8
BAN_ENCORE        = 1 << 9   # = 512

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
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15,
     "damages_underwater": True},

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
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  28, "name": "Sand Attack",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 100, "pp": 15,
     "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "bounceable": True},

    # Tail Whip: -1 Def foe
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  39, "name": "Tail Whip",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "bounceable": True},

    # Leer: -1 Def foe
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  43, "name": "Leer",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "bounceable": True},

    # Growl: -1 Atk foe, sound_move=true (source: struct MoveInfo.soundMove)
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  45, "name": "Growl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 40,
     "sound_move": True, "bounceable": True,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": -1},

    # ── Tier 2: status-inflicting moves ──────────────────────────────────────

    # Sleep Powder: primary sleep (guaranteed), powder_move=true
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  79, "name": "Sleep Powder",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 75, "pp": 15,
     "powder_move": True, "bounceable": True,
     "secondary_effect": SE_SLEEP, "secondary_chance": 0},

    # Thunder Wave: primary paralysis (guaranteed), Electric type (blocks vs Ground)
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  86, "name": "Thunder Wave",
     "type": TYPE_ELECTRIC, "category": STAT, "accuracy": 90, "pp": 20,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 0, "bounceable": True},

    # Toxic: primary bad poison (guaranteed)
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  92, "name": "Toxic",
     "type": TYPE_POISON, "category": STAT, "accuracy": 90, "pp": 10,
     "secondary_effect": SE_TOXIC, "secondary_chance": 0, "bounceable": True},

    # Confuse Ray: primary confusion (guaranteed), Ghost type (blocks vs Normal)
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id": 109, "name": "Confuse Ray",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 0, "bounceable": True},

    # Will-O-Wisp: primary burn (guaranteed), Fire type
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id": 261, "name": "Will-O-Wisp",
     "type": TYPE_FIRE, "category": STAT, "accuracy": 85, "pp": 15,
     "secondary_effect": SE_BURN, "secondary_chance": 0, "bounceable": True},

    # ── Tier 2 + closes M4 gap: Flame Wheel ──────────────────────────────────
    # Flame Wheel: Fire/Phys/60/100/25, contact, thaws_user, 10% burn secondary.
    # Added to close M4 T3d gap: a frozen attacker using a thawsUser move
    # must thaw and act. Flame Wheel is the canonical Fire move with thaws_user.
    {"id": 172, "name": "Flame Wheel",
     "type": TYPE_FIRE, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "thaws_user": True,
     "secondary_effect": SE_BURN, "secondary_chance": 10},

    # ── Tier 3: two-turn charge moves (no semi-invulnerability) ──────────────
    #
    # Razor Wind(13)   L344   Normal/Spec/80/100/10, two-turn, crit=1
    #   Source: .effect=EFFECT_TWO_TURNS_ATTACK; B_UPDATED>=GEN_4 → critStage=1
    {"id":  13, "name": "Razor Wind",
     "type": TYPE_NORMAL, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "critical_hit_stage": 1, "two_turn": True},

    # Solar Beam(76)   L2052  Grass/Spec/120/100/10, two-turn
    #   is_solar_beam=True: fires immediately in harsh sun (M15 Task5).
    #   Source: .effect=EFFECT_SOLAR_BEAM; CanTwoTurnMoveFireThisTurn returns TRUE when sun.
    {"id":  76, "name": "Solar Beam",
     "type": TYPE_GRASS, "category": SPEC, "power": 120, "accuracy": 100, "pp": 10,
     "two_turn": True, "is_solar_beam": True},

    # Sky Attack(143)  L3887  Flying/Phys/140/90/5, two-turn, crit=1, 30% flinch
    #   Source: .effect=EFFECT_TWO_TURNS_ATTACK; critStage=1; 30% flinch secondary (GEN_3+)
    {"id": 143, "name": "Sky Attack",
     "type": TYPE_FLYING, "category": PHYS, "power": 140, "accuracy": 90, "pp": 5,
     "critical_hit_stage": 1, "two_turn": True,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    # Skull Bash(130) L3556  Normal/Phys/130/100/10, contact, two-turn
    #   Source: .effect=EFFECT_TWO_TURNS_ATTACK; additionalEffects {MOVE_EFFECT_STAT_PLUS,
    #   .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE} (M15 Task5).
    #   Power=130 (B_UPDATED>=GEN_2).
    {"id": 130, "name": "Skull Bash",
     "type": TYPE_NORMAL, "category": PHYS, "power": 130, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "charge_turn_defense_boost": 1},

    # ── Tier 3: semi-invulnerable two-turn moves ──────────────────────────────
    #
    # Fly(19)          L522   Flying/Phys/90/95/15, contact, two-turn, STATE_ON_AIR
    #   Source: .effect=EFFECT_SEMI_INVULNERABLE; .argument.twoTurnAttack.status=STATE_ON_AIR
    #   Power=90 (B_UPDATED>=GEN_4); gravityBanned.
    {"id":  19, "name": "Fly",
     "type": TYPE_FLYING, "category": PHYS, "power": 90, "accuracy": 95, "pp": 15,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_ON_AIR},

    # Dig(91)          L2441  Ground/Phys/80/100/10, contact, two-turn, STATE_UNDERGROUND
    #   Source: .effect=EFFECT_SEMI_INVULNERABLE; .argument.twoTurnAttack.status=STATE_UNDERGROUND
    #   Power=80 (B_UPDATED>=GEN_4).
    {"id":  91, "name": "Dig",
     "type": TYPE_GROUND, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_UNDERGROUND},

    # ── Tier 3: recoil moves ──────────────────────────────────────────────────
    #
    # Take Down(36)    L972   Normal/Phys/90/85/20, contact, 25% recoil
    #   Source: .effect=EFFECT_RECOIL; .argument.recoilPercentage=25
    {"id":  36, "name": "Take Down",
     "type": TYPE_NORMAL, "category": PHYS, "power": 90, "accuracy": 85, "pp": 20,
     "makes_contact": True, "recoil_percent": 25},

    # Double-Edge(38)  L1024  Normal/Phys/120/100/15, contact, 33% recoil
    #   Source: .effect=EFFECT_RECOIL; .argument.recoilPercentage=33 (B_UPDATED>=GEN_3)
    #   Power=120 (B_UPDATED>=GEN_2).
    {"id":  38, "name": "Double-Edge",
     "type": TYPE_NORMAL, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 33},

    # Brave Bird(413)  L11116 Flying/Phys/120/100/15, contact, 33% recoil
    #   Source: .effect=EFFECT_RECOIL; .argument.recoilPercentage=33
    {"id": 413, "name": "Brave Bird",
     "type": TYPE_FLYING, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 33},

    # ── Tier 3: drain (absorb) moves ─────────────────────────────────────────
    #
    # Absorb(71)       L1919  Grass/Spec/20/100/25, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50; pp=25 (B_UPDATED>=GEN_4)
    {"id":  71, "name": "Absorb",
     "type": TYPE_GRASS, "category": SPEC, "power": 20, "accuracy": 100, "pp": 25,
     "drain_percent": 50},

    # Mega Drain(72)   L1943  Grass/Spec/40/100/15, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50; pp=15 (B_UPDATED>=GEN_4)
    {"id":  72, "name": "Mega Drain",
     "type": TYPE_GRASS, "category": SPEC, "power": 40, "accuracy": 100, "pp": 15,
     "drain_percent": 50},

    # Giga Drain(202)  L5530  Grass/Spec/75/100/10, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50
    #   Power=75 (B_UPDATED>=GEN_5); pp=10 (B_UPDATED>=GEN_4).
    {"id": 202, "name": "Giga Drain",
     "type": TYPE_GRASS, "category": SPEC, "power": 75, "accuracy": 100, "pp": 10,
     "drain_percent": 50},

    # Drain Punch(409) L11016 Fighting/Phys/75/100/10, contact, punching, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50
    #   Power=75 (B_UPDATED>=GEN_5); pp=10 (B_UPDATED>=GEN_5); makesContact, punchingMove.
    {"id": 409, "name": "Drain Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 75, "accuracy": 100, "pp": 10,
     "makes_contact": True, "punching_move": True, "drain_percent": 50},

    # ── Tier 3: fixed-damage moves ────────────────────────────────────────────
    #
    # Sonic Boom(49)   L1322  Normal/Spec/1/90/20, fixed 20 HP
    #   Source: .effect=EFFECT_FIXED_HP_DAMAGE; .argument.fixedDamage=20; power=1 (placeholder)
    {"id":  49, "name": "Sonic Boom",
     "type": TYPE_NORMAL, "category": SPEC, "power": 1, "accuracy": 90, "pp": 20,
     "fixed_damage": 20},

    # Dragon Rage(82)  L2217  Dragon/Spec/1/100/10, fixed 40 HP
    #   Source: .effect=EFFECT_FIXED_HP_DAMAGE; .argument.fixedDamage=40; power=1 (placeholder)
    {"id":  82, "name": "Dragon Rage",
     "type": TYPE_DRAGON, "category": SPEC, "power": 1, "accuracy": 100, "pp": 10,
     "fixed_damage": 40},

    # Seismic Toss(69) L1872  Fighting/Phys/1/100/20, damage=level, contact
    #   Source: .effect=EFFECT_LEVEL_DAMAGE; power=1 (placeholder); makesContact
    {"id":  69, "name": "Seismic Toss",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 1, "accuracy": 100, "pp": 20,
     "makes_contact": True, "level_damage": True},

    # Night Shade(101) L2719  Ghost/Spec/1/100/15, damage=level
    #   Source: .effect=EFFECT_LEVEL_DAMAGE; power=1 (placeholder)
    {"id": 101, "name": "Night Shade",
     "type": TYPE_GHOST, "category": SPEC, "power": 1, "accuracy": 100, "pp": 15,
     "level_damage": True},

    # ── Tier 3: semi-invulnerable bypass move ─────────────────────────────────
    #
    # Earthquake(89)   L2394  Ground/Phys/100/100/10, damages_underground
    #   Source: .effect=EFFECT_EARTHQUAKE; .damagesUnderground=TRUE (B_UPDATED>=GEN_2)
    #   Hits Dig users on their charge turn; deals double damage (M8+ scope).
    {"id":  89, "name": "Earthquake",
     "type": TYPE_GROUND, "category": PHYS, "power": 100, "accuracy": 100, "pp": 10,
     "damages_underground": True},

    # ── Tier 4: unique / one-off mechanics ────────────────────────────────────
    #
    # Disable(50)      L1264  Normal/Status/100/20
    #   Source: moves_info.h MOVE_DISABLE: .effect=EFFECT_DISABLE, .accuracy=100,
    #   .pp=20 (B_UPDATED>=GEN_5), .ignoresSubstitute=TRUE
    #   Not metronomeBanned in source; can be called by Metronome.
    {"id":  50, "name": "Disable",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 20,
     "ignores_substitute": True, "is_disable": True,
     "blocked_by_aroma_veil": True},

    # Counter(68)      L1736  Fighting/Phys/1/100/20, priority=-5
    #   Source: moves_info.h MOVE_COUNTER: .effect=EFFECT_COUNTER, .power=1,
    #   .type=TYPE_FIGHTING, .priority=-5, .category=PHYS, .makesContact=TRUE,
    #   .metronomeBanned=TRUE (Gen 5+)
    {"id":  68, "name": "Counter",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 1, "accuracy": 100, "pp": 20,
     "priority": -5, "makes_contact": True,
     "ban_flags": BAN_METRONOME, "counter": True},

    # Bide(117)        L2992  Normal/Phys/0/—/10, priority=1
    #   Source: moves_info.h MOVE_BIDE: .effect=EFFECT_BIDE, .power=0,
    #   .accuracy=0 (always executes), .pp=10, .priority=1 (B_UPDATED>=GEN_4),
    #   .category=PHYS, .metronomeBanned=TRUE (Gen 5+; B_METRONOME_BIDE check)
    {"id": 117, "name": "Bide",
     "type": TYPE_NORMAL, "category": PHYS, "power": 0, "accuracy": 0, "pp": 10,
     "priority": 1,
     "ban_flags": BAN_METRONOME, "is_bide": True},

    # Metronome(118)   L3020  Normal/Status/0/—/10
    #   Source: moves_info.h MOVE_METRONOME: .effect=EFFECT_METRONOME, .pp=10,
    #   .category=STATUS, .accuracy=0 (always executes), .metronomeBanned=TRUE (self-ban)
    {"id": 118, "name": "Metronome",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": BAN_METRONOME, "is_metronome": True},

    # Substitute(164)  L4299  Normal/Status/0/—/10
    #   Source: moves_info.h MOVE_SUBSTITUTE: .effect=EFFECT_SUBSTITUTE, .pp=10,
    #   .category=STATUS, .metronomeBanned=TRUE
    {"id": 164, "name": "Substitute",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": BAN_METRONOME, "creates_substitute": True},

    # Protect(182)     L4788  Normal/Status/0/—/10, priority=4
    #   Source: moves_info.h MOVE_PROTECT: .effect=EFFECT_PROTECT,
    #   .priority=4 (GEN_LATEST), .pp=10, .category=STATUS,
    #   .metronomeBanned=TRUE (confirmed in moves_info.h)
    {"id": 182, "name": "Protect",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "priority": 4,
     "ban_flags": BAN_METRONOME, "is_protect": True},

    # Destiny Bond(194) L5092  Ghost/Status/0/—/5
    #   Source: moves_info.h MOVE_DESTINY_BOND: .effect=EFFECT_DESTINY_BOND,
    #   .type=TYPE_GHOST, .pp=5, .category=STATUS, .metronomeBanned=TRUE
    {"id": 194, "name": "Destiny Bond",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 0, "pp": 5,
     "ban_flags": BAN_METRONOME, "destiny_bond": True},

    # Detect(197)      L5167  Fighting/Status/0/—/5, priority=4
    #   Source: moves_info.h MOVE_DETECT: .effect=EFFECT_PROTECT (same handler),
    #   .type=TYPE_FIGHTING, .priority=4, .pp=5, .category=STATUS,
    #   .metronomeBanned=TRUE.  Shares protect_consecutive with Protect.
    {"id": 197, "name": "Detect",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 0, "pp": 5,
     "priority": 4,
     "ban_flags": BAN_METRONOME, "is_protect": True},

    # Encore(227)      L5978  Normal/Status/100/5
    #   Source: moves_info.h MOVE_ENCORE: .effect=EFFECT_ENCORE, .accuracy=100,
    #   .pp=5 (B_UPDATED>=GEN_5), .category=STATUS, .metronomeBanned=TRUE,
    #   .encoreBanned=TRUE (can't Encore an Encored move).
    {"id": 227, "name": "Encore",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 5,
     "ban_flags": BAN_METRONOME | BAN_ENCORE, "is_encore": True,
     "blocked_by_aroma_veil": True},

    # Mirror Coat(243) L6450  Psychic/Spec/1/100/20, priority=-5
    #   Source: moves_info.h MOVE_MIRROR_COAT: .effect=EFFECT_MIRROR_COAT,
    #   .type=TYPE_PSYCHIC, .power=1, .accuracy=100, .pp=20, .priority=-5,
    #   .category=SPEC, .metronomeBanned=TRUE (Gen 5+)
    {"id": 243, "name": "Mirror Coat",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 1, "accuracy": 100, "pp": 20,
     "priority": -5,
     "ban_flags": BAN_METRONOME, "mirror_coat": True},

    # ── M9: Switching mechanics ───────────────────────────────────────────────
    #
    # Whirlwind(18)  L482  Normal/Status/0/priority=-6/pp=20
    #   Source: moves_info.h MOVE_WHIRLWIND: .effect=EFFECT_ROAR, .accuracy=0
    #   (B_UPDATED_MOVE_DATA>=GEN_6), .priority=-6 (B_UPDATED_MOVE_DATA>=GEN_3),
    #   .pp=20, .ignoresProtect=B_UPDATED_MOVE_FLAGS>=GEN_6 (TRUE),
    #   .ignoresSubstitute=B_UPDATED_MOVE_FLAGS>=GEN_6 (TRUE), .soundMove=TRUE
    {"id":  18, "name": "Whirlwind",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "priority": -6,
     "ignores_protect": True, "ignores_substitute": True, "sound_move": True,
     "is_roar": True},

    # Roar(46)       L1234 Normal/Status/0/priority=-6/pp=20
    #   Source: moves_info.h MOVE_ROAR: .effect=EFFECT_ROAR, .accuracy=0
    #   (B_UPDATED_MOVE_DATA>=GEN_6), .priority=-6 (B_UPDATED_MOVE_DATA>=GEN_3),
    #   .pp=20, .ignoresProtect=B_UPDATED_MOVE_FLAGS>=GEN_6 (TRUE),
    #   .ignoresSubstitute=B_UPDATED_MOVE_FLAGS>=GEN_6 (TRUE), .soundMove=TRUE
    {"id":  46, "name": "Roar",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "priority": -6,
     "ignores_protect": True, "ignores_substitute": True, "sound_move": True,
     "is_roar": True},

    # Baton Pass(226) L6164 Normal/Status/0/pp=40
    #   Source: moves_info.h MOVE_BATON_PASS: .effect=EFFECT_BATON_PASS,
    #   .accuracy=0, .pp=40, .ignoresProtect=TRUE, .mirrorMoveBanned=TRUE
    {"id": 226, "name": "Baton Pass",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_protect": True,
     "is_baton_pass": True},

    # ── M16a: Tier A move effects ─────────────────────────────────────────────

    # Guillotine(12)  L295  Normal/Phys/1/30/5, contact, OHKO
    #   Source: moves_info.h MOVE_GUILLOTINE: .effect=EFFECT_OHKO, .power=1 (placeholder),
    #   .accuracy=30, .pp=5, .makesContact=TRUE. Level check + custom acc in battle_util.c.
    {"id":  12, "name": "Guillotine",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 30, "pp": 5,
     "makes_contact": True, "is_ohko": True},

    # Horn Drill(32)  L838  Normal/Phys/1/30/5, contact, OHKO
    #   Source: moves_info.h MOVE_HORN_DRILL: .effect=EFFECT_OHKO, .power=1 (placeholder),
    #   .accuracy=30, .pp=5, .makesContact=TRUE.
    {"id":  32, "name": "Horn Drill",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 30, "pp": 5,
     "makes_contact": True, "is_ohko": True},

    # Growth(74)      L2003  Normal/Status/0/0/20
    #   Source: moves_info.h MOVE_GROWTH: .effect=EFFECT_GROWTH, .pp=20 (B_UPDATED>=GEN_6),
    #   .accuracy=0, .ignoresProtect=TRUE.
    #   Raises ATK +1 AND SpATK +1 (GEN_5+); +2 each in harsh sun.
    {"id":  74, "name": "Growth",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_growth": True},

    # Fissure(90)     L2381  Ground/Phys/1/30/5, OHKO, damages_underground
    #   Source: moves_info.h MOVE_FISSURE: .effect=EFFECT_OHKO, .power=1, .type=TYPE_GROUND,
    #   .accuracy=30, .pp=5, .damagesUnderground=TRUE (hits Dig users).
    {"id":  90, "name": "Fissure",
     "type": TYPE_GROUND, "category": PHYS, "power": 1, "accuracy": 30, "pp": 5,
     "damages_underground": True, "is_ohko": True},

    # Recover(105)    L2799  Normal/Status/0/0/5
    #   Source: moves_info.h MOVE_RECOVER: .effect=EFFECT_RESTORE_HP, .pp=5 (B_UPDATED>=GEN_9),
    #   .accuracy=0, .ignoresProtect=TRUE, .healingMove=TRUE.
    {"id": 105, "name": "Recover",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True},

    # Focus Energy(116) L3008  Normal/Status/0/0/30
    #   Source: moves_info.h MOVE_FOCUS_ENERGY: .effect=EFFECT_FOCUS_ENERGY, .pp=30,
    #   .accuracy=0, .ignoresProtect=TRUE. Raises crit stage +2 (Gen3+).
    {"id": 116, "name": "Focus Energy",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "is_focus_energy": True},

    # Slack Off(303)  L8253  Normal/Status/0/0/5
    #   Source: moves_info.h MOVE_SLACK_OFF: .effect=EFFECT_RESTORE_HP, .pp=5 (B_UPDATED>=GEN_9),
    #   .accuracy=0, .ignoresProtect=TRUE, .healingMove=TRUE.
    {"id": 303, "name": "Slack Off",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True},

    # Sheer Cold(329) L8977  Ice/Spec/1/30/5, OHKO
    #   Source: moves_info.h MOVE_SHEER_COLD: .effect=EFFECT_OHKO, .power=1, .type=TYPE_ICE,
    #   .accuracy=30, .pp=5, .category=DAMAGE_CATEGORY_SPECIAL.
    #   Note: Ice-type targets immune (B_SHEER_COLD_IMMUNITY >= GEN_7) — deferred M16b.
    {"id": 329, "name": "Sheer Cold",
     "type": TYPE_ICE, "category": SPEC, "power": 1, "accuracy": 30, "pp": 5,
     "is_ohko": True},

    # Heal Order(456) L12362  Bug/Status/0/0/10
    #   Source: moves_info.h MOVE_HEAL_ORDER: .effect=EFFECT_RESTORE_HP, .pp=10,
    #   .type=TYPE_BUG, .accuracy=0, .ignoresProtect=TRUE, .healingMove=TRUE.
    {"id": 456, "name": "Heal Order",
     "type": TYPE_BUG, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True},

    # ── M16b: Tier B move effects ─────────────────────────────────────────────

    # Stomp(23)  L630  Normal/Phys/65/100/20, contact, 30% flinch, double dmg vs minimized
    #   Source: moves_info.h MOVE_STOMP: .effect=EFFECT_HIT, .power=65, .makesContact=TRUE,
    #   .minimizeDoubleDamage=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_2), 30% flinch secondary.
    #   NOTE: canonical ID is 23 (constants/moves.h), not 31 (that's Fury Attack) —
    #   corrected from the initial task spec after checking source; see decisions.md.
    {"id":  23, "name": "Stomp",
     "type": TYPE_NORMAL, "category": PHYS, "power": 65, "accuracy": 100, "pp": 20,
     "makes_contact": True, "double_power_on_minimized": True,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    # Minimize(107)  L2895  Normal/Status/0/0/10, self, +2 evasion, ignoresProtect
    #   Source: moves_info.h MOVE_MINIMIZE: .effect=EFFECT_MINIMIZE, .accuracy=0,
    #   .pp=10 (B_UPDATED_MOVE_DATA>=GEN_6), .target=TARGET_USER, .ignoresProtect=TRUE.
    #   additionalEffects {STAT_CHANGE_EFFECT_PLUS, .evasion=2} (B_MINIMIZE_EVASION>=GEN_5).
    {"id": 107, "name": "Minimize",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_minimize": True},

    # Defense Curl(111)  L3011  Normal/Status/0/0/40, self, +1 Defense, ignoresProtect
    #   Source: moves_info.h MOVE_DEFENSE_CURL: .effect=EFFECT_DEFENSE_CURL, .accuracy=0,
    #   .pp=40, .target=TARGET_USER, .ignoresProtect=TRUE.
    #   additionalEffects {STAT_CHANGE_EFFECT_PLUS, .defense=1}.
    {"id": 111, "name": "Defense Curl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "is_defense_curl": True},

    # Rollout(205)  L5618  Rock/Phys/30/90/20, contact, 5-turn power-doubling
    #   Source: moves_info.h MOVE_ROLLOUT: .effect=EFFECT_ROLLOUT, .power=30, .accuracy=90,
    #   .pp=20, .makesContact=TRUE.
    {"id": 205, "name": "Rollout",
     "type": TYPE_ROCK, "category": PHYS, "power": 30, "accuracy": 90, "pp": 20,
     "makes_contact": True, "is_rollout": True},

    # Ice Ball(301)  L8228  Ice/Phys/30/90/20, contact, ballistic, 5-turn power-doubling
    #   Source: moves_info.h MOVE_ICE_BALL: .effect=EFFECT_ROLLOUT (same handler as Rollout),
    #   .power=30, .accuracy=90, .pp=20, .makesContact=TRUE, .ballisticMove=TRUE.
    #   M17n-1: `ballistic_move` was cited in this comment since M16b but never actually
    #   set on the dict below — a real pre-existing gap, harmless until Bulletproof
    #   existed to consume it. Fixed now, retroactively, while adding Bulletproof.
    {"id": 301, "name": "Ice Ball",
     "type": TYPE_ICE, "category": PHYS, "power": 30, "accuracy": 90, "pp": 20,
     "makes_contact": True, "is_rollout": True, "ballistic_move": True},

    # Magnitude(222)  L6063  Ground/Phys/1/100/30, spread, damages_underground, variable power
    #   Source: moves_info.h MOVE_MAGNITUDE: .effect=EFFECT_MAGNITUDE, .power=1 (placeholder;
    #   overridden every use), .accuracy=100, .pp=30, .target=TARGET_FOES_AND_ALLY,
    #   .damagesUnderground=TRUE. Power table rolled in CalculateMagnitudeDamage.
    {"id": 222, "name": "Magnitude",
     "type": TYPE_GROUND, "category": PHYS, "power": 1, "accuracy": 100, "pp": 30,
     "damages_underground": True, "is_spread": True, "is_magnitude": True},

    # ── M16c: Tier C move effects (screens) ───────────────────────────────────

    # Light Screen(113)  L3071  Psychic/Status/0/0/30, self, ignoresProtect, halves Special dmg
    #   Source: moves_info.h MOVE_LIGHT_SCREEN: .effect=EFFECT_LIGHT_SCREEN, .accuracy=0,
    #   .pp=30, .target=TARGET_USER, .ignoresProtect=TRUE.
    {"id": 113, "name": "Light Screen",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "is_light_screen": True},

    # Reflect(115)  L3123  Psychic/Status/0/0/20, self, ignoresProtect, halves Physical dmg
    #   Source: moves_info.h MOVE_REFLECT: .effect=EFFECT_REFLECT, .accuracy=0, .pp=20,
    #   .target=TARGET_USER, .ignoresProtect=TRUE.
    {"id": 115, "name": "Reflect",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_reflect": True},

    # Brick Break(280)  L7672  Fighting/Phys/75/100/15, contact, breaks target's screens
    #   Source: moves_info.h MOVE_BRICK_BREAK: .effect=EFFECT_HIT, .power=75, .accuracy=100,
    #   .pp=15, .makesContact=TRUE. additionalEffects {MOVE_EFFECT_BREAK_SCREEN,
    #   .preAttackEffect=TRUE}.
    {"id": 280, "name": "Brick Break",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 75, "accuracy": 100, "pp": 15,
     "makes_contact": True, "breaks_screens": True},

    # Aurora Veil(657)  L17392  Ice/Status/0/0/20, self, ignoresProtect, hail-gated,
    #   halves both Physical and Special dmg (combines Reflect + Light Screen)
    #   Source: moves_info.h MOVE_AURORA_VEIL: .effect=EFFECT_AURORA_VEIL, .accuracy=0,
    #   .pp=20, .target=TARGET_USER, .ignoresProtect=TRUE. Fails unless
    #   GetWeather() & B_WEATHER_ICY_ANY (this project only models Hail).
    {"id": 657, "name": "Aurora Veil",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_aurora_veil": True},

    # ── M16d: Tier D move effects (hazards + Trick Room) ──────────────────────

    # Spikes(191)  L5232  Ground/Status/0/0/20, opponent's field, ignoresProtect, layered (max 3)
    #   Source: moves_info.h MOVE_SPIKES: .effect=EFFECT_SPIKES, .accuracy=0, .pp=20,
    #   .target=TARGET_OPPONENTS_FIELD, .ignoresProtect=TRUE.
    {"id": 191, "name": "Spikes",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_spikes": True},

    # Rapid Spin(229)  L6247  Normal/Phys/50/100/40, contact, clears one hazard on own side
    #   Source: moves_info.h MOVE_RAPID_SPIN: .effect=EFFECT_RAPID_SPIN,
    #   .power=50 (B_UPDATED_MOVE_DATA>=GEN_8), .accuracy=100, .pp=40, .makesContact=TRUE.
    {"id": 229, "name": "Rapid Spin",
     "type": TYPE_NORMAL, "category": PHYS, "power": 50, "accuracy": 100, "pp": 40,
     "makes_contact": True, "is_rapid_spin": True},

    # Toxic Spikes(390)  L10542  Poison/Status/0/0/20, opponent's field, ignoresProtect,
    #   layered (max 2)
    #   Source: moves_info.h MOVE_TOXIC_SPIKES: .effect=EFFECT_TOXIC_SPIKES, .accuracy=0,
    #   .pp=20, .target=TARGET_OPPONENTS_FIELD, .ignoresProtect=TRUE.
    {"id": 390, "name": "Toxic Spikes",
     "type": TYPE_POISON, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_toxic_spikes": True},

    # Trick Room(433)  L11641  Psychic/Status/0/0/5, field, priority=-7, ignoresProtect,
    #   toggles a 5-turn speed-order reversal
    #   Source: moves_info.h MOVE_TRICK_ROOM: .effect=EFFECT_TRICK_ROOM, .accuracy=0,
    #   .pp=5, .target=TARGET_FIELD, .priority=-7, .ignoresProtect=TRUE.
    {"id": 433, "name": "Trick Room",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 5,
     "priority": -7, "ignores_protect": True, "is_trick_room": True},

    # Stealth Rock(446)  L11969  Rock/Status/0/0/20, opponent's field, ignoresProtect,
    #   single application (no layers), type-effectiveness-based damage
    #   Source: moves_info.h MOVE_STEALTH_ROCK: .effect=EFFECT_STEALTH_ROCK, .accuracy=0,
    #   .pp=20, .target=TARGET_OPPONENTS_FIELD, .ignoresProtect=TRUE.
    {"id": 446, "name": "Stealth Rock",
     "type": TYPE_ROCK, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_stealth_rock": True},

    # ── M16e: Tier E move effects ──────────────────────────────────────────────

    # Pursuit(228)  L6223  Dark/Phys/40/100/20, contact, doubles power vs a switching target
    #   Source: moves_info.h MOVE_PURSUIT: .effect=EFFECT_PURSUIT, .power=40,
    #   .accuracy=100, .pp=20, .makesContact=TRUE.
    {"id": 228, "name": "Pursuit",
     "type": TYPE_DARK, "category": PHYS, "power": 40, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_pursuit": True},

    # Pain Split(220)  L6013  Normal/Status/0/0/20, selected target, averages current HP
    #   Source: moves_info.h MOVE_PAIN_SPLIT: .effect=EFFECT_PAIN_SPLIT, .accuracy=0,
    #   .pp=20, .target=TARGET_SELECTED.
    {"id": 220, "name": "Pain Split",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "is_pain_split": True},

    # Conversion(160)  L4358  Normal/Status/0/0/30, self, ignoresProtect, type = first move's type
    #   Source: moves_info.h MOVE_CONVERSION: .effect=EFFECT_CONVERSION, .accuracy=0,
    #   .pp=30, .target=TARGET_USER, .ignoresProtect=TRUE.
    {"id": 160, "name": "Conversion",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "is_conversion": True},

    # Conversion 2(176)  L4822  Normal/Status/0/0/30, selected target, ignoresProtect,
    #   ignoresSubstitute, type = a random type resisting the target's last move
    #   Source: moves_info.h MOVE_CONVERSION_2: .effect=EFFECT_CONVERSION_2, .accuracy=0,
    #   .pp=30, .target=TARGET_SELECTED (Gen5+), .ignoresProtect=TRUE,
    #   .ignoresSubstitute=TRUE (B_UPDATED_MOVE_FLAGS >= GEN_5).
    {"id": 176, "name": "Conversion 2",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "ignores_substitute": True, "is_conversion2": True},

    # Psych Up(244)  L6673  Normal/Status/0/0/10, selected target, ignoresProtect,
    #   ignoresSubstitute, copies target's stat stages + focus energy
    #   Source: moves_info.h MOVE_PSYCH_UP: .effect=EFFECT_PSYCH_UP, .accuracy=0, .pp=10,
    #   .target=TARGET_SELECTED, .ignoresProtect=TRUE, .ignoresSubstitute=TRUE.
    {"id": 244, "name": "Psych Up",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True, "is_psych_up": True},

    # Attract(213)  L?  Normal/Status/0/100/15, selected target, ignoresSubstitute
    #   Source: moves_info.h MOVE_ATTRACT: .effect=EFFECT_ATTRACT, .power=0,
    #   .accuracy=100, .pp=15, .target=TARGET_SELECTED, .ignoresSubstitute=TRUE.
    #   Data cross-checked against data/moves.json's own already-extracted entry
    #   ([M15]'s bulk pass already had this move; only the curated .tres/is_attract
    #   dispatch flag were missing before [M18.5d-2]).
    {"id": 213, "name": "Attract",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 15,
     "ignores_substitute": True, "is_attract": True},

    # [M18.5f] Bind/Wrap-family (10 moves) — all share the identical real-source
    # MOVE_EFFECT_WRAP additional effect (battle_script_commands.c L2465-2477),
    # unconditional on a hit landing (secondary_chance=0 — not a "true secondary",
    # confirmed absent from moves_info.h's .chance field for all 10). Per-move
    # power/accuracy/pp/category/type/makesContact all confirmed individually
    # from moves_info.h (this project targets B_UPDATED_MOVE_DATA >= GEN_5 values
    # throughout, matching every other move in this file). Jaw Lock (748) is
    # deliberately excluded — MOVE_EFFECT_TRAP_BOTH, a different mechanic (see
    # move_data.gd's SE_WRAP doc comment).
    {"id": 20, "name": "Bind",
     "type": TYPE_NORMAL, "category": PHYS, "power": 15, "accuracy": 85, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_WRAP},
    {"id": 35, "name": "Wrap",
     "type": TYPE_NORMAL, "category": PHYS, "power": 15, "accuracy": 90, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_WRAP},
    {"id": 83, "name": "Fire Spin",
     "type": TYPE_FIRE, "category": SPEC, "power": 35, "accuracy": 85, "pp": 15,
     "secondary_effect": SE_WRAP},
    {"id": 128, "name": "Clamp",
     "type": TYPE_WATER, "category": PHYS, "power": 35, "accuracy": 85, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_WRAP},
    {"id": 250, "name": "Whirlpool",
     "type": TYPE_WATER, "category": SPEC, "power": 35, "accuracy": 85, "pp": 15,
     "secondary_effect": SE_WRAP},
    {"id": 328, "name": "Sand Tomb",
     "type": TYPE_GROUND, "category": PHYS, "power": 35, "accuracy": 85, "pp": 15,
     "secondary_effect": SE_WRAP},
    {"id": 463, "name": "Magma Storm",
     "type": TYPE_FIRE, "category": SPEC, "power": 100, "accuracy": 75, "pp": 5,
     "secondary_effect": SE_WRAP},
    {"id": 611, "name": "Infestation",
     "type": TYPE_BUG, "category": SPEC, "power": 20, "accuracy": 100, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_WRAP},
    {"id": 707, "name": "Snap Trap",
     "type": TYPE_GRASS, "category": PHYS, "power": 35, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_WRAP},
    {"id": 747, "name": "Thunder Cage",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 80, "accuracy": 90, "pp": 15,
     "secondary_effect": SE_WRAP},

    # [M18.5g] Multi-hit family (30 of the 31 real-source strikeCount/multiHit
    # moves — Population Bomb(880) EXCLUDED, see move_data.gd's strike_count doc
    # comment for why). Per-move power/accuracy/pp/category/type/makesContact all
    # confirmed individually from moves_info.h (this project targets
    # B_UPDATED_MOVE_DATA >= GEN_7 values throughout, matching every other move
    # in this file). The 15 multi_hit=True moves roll a shared 2/3/4/5-hit
    # distribution at use time (see MoveData.multi_hit's own doc comment); the
    # 16 strike_count moves (Population Bomb aside) hit a fixed number of times.
    {"id": 3, "name": "Double Slap",
     "type": TYPE_NORMAL, "category": PHYS, "power": 15, "accuracy": 85, "pp": 10,
     "makes_contact": True, "multi_hit": True},
    {"id": 4, "name": "Comet Punch",
     "type": TYPE_NORMAL, "category": PHYS, "power": 18, "accuracy": 85, "pp": 15,
     "makes_contact": True, "punching_move": True, "multi_hit": True},
    {"id": 24, "name": "Double Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 30, "accuracy": 100, "pp": 30,
     "makes_contact": True, "strike_count": 2},
    {"id": 31, "name": "Fury Attack",
     "type": TYPE_NORMAL, "category": PHYS, "power": 15, "accuracy": 85, "pp": 20,
     "makes_contact": True, "multi_hit": True},
    # Twineedle: NOT makesContact in this reference clone's own data (confirmed
    # by direct inspection, not assumed from the flavor text or real-game
    # expectations). 20% chance per hit to inflict regular Poison — reuses the
    # newly-added SE_POISON, rolling independently on each hit via the same
    # generic per-hit secondary_effect dispatch every other move already uses.
    {"id": 41, "name": "Twineedle",
     "type": TYPE_BUG, "category": PHYS, "power": 25, "accuracy": 100, "pp": 20,
     "strike_count": 2, "secondary_effect": SE_POISON, "secondary_chance": 20},
    {"id": 42, "name": "Pin Missile",
     "type": TYPE_BUG, "category": PHYS, "power": 25, "accuracy": 95, "pp": 20,
     "multi_hit": True},
    {"id": 131, "name": "Spike Cannon",
     "type": TYPE_NORMAL, "category": PHYS, "power": 20, "accuracy": 100, "pp": 15,
     "multi_hit": True},
    {"id": 140, "name": "Barrage",
     "type": TYPE_NORMAL, "category": PHYS, "power": 15, "accuracy": 85, "pp": 20,
     "ballistic_move": True, "multi_hit": True},
    {"id": 154, "name": "Fury Swipes",
     "type": TYPE_NORMAL, "category": PHYS, "power": 18, "accuracy": 80, "pp": 15,
     "makes_contact": True, "multi_hit": True},
    {"id": 155, "name": "Bonemerang",
     "type": TYPE_GROUND, "category": PHYS, "power": 50, "accuracy": 90, "pp": 10,
     "strike_count": 2},
    # Triple Kick: fixed 3-hit MAXIMUM, but each hit independently rolls
    # accuracy (90%) and hits with escalating power (×1/×2/×3) — is_triple_kick
    # dispatches both halves in BattleManager._do_multi_hit_sequence.
    {"id": 167, "name": "Triple Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 10, "accuracy": 90, "pp": 10,
     "makes_contact": True, "strike_count": 3, "is_triple_kick": True},
    {"id": 198, "name": "Bone Rush",
     "type": TYPE_GROUND, "category": PHYS, "power": 25, "accuracy": 90, "pp": 10,
     "multi_hit": True},
    {"id": 292, "name": "Arm Thrust",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 15, "accuracy": 100, "pp": 20,
     "makes_contact": True, "multi_hit": True},
    {"id": 331, "name": "Bullet Seed",
     "type": TYPE_GRASS, "category": PHYS, "power": 25, "accuracy": 100, "pp": 30,
     "ballistic_move": True, "multi_hit": True},
    {"id": 333, "name": "Icicle Spear",
     "type": TYPE_ICE, "category": PHYS, "power": 25, "accuracy": 100, "pp": 30,
     "multi_hit": True},
    {"id": 350, "name": "Rock Blast",
     "type": TYPE_ROCK, "category": PHYS, "power": 25, "accuracy": 90, "pp": 10,
     "ballistic_move": True, "multi_hit": True},
    {"id": 458, "name": "Double Hit",
     "type": TYPE_NORMAL, "category": PHYS, "power": 35, "accuracy": 90, "pp": 10,
     "makes_contact": True, "strike_count": 2},
    {"id": 530, "name": "Dual Chop",
     "type": TYPE_DRAGON, "category": PHYS, "power": 40, "accuracy": 90, "pp": 15,
     "makes_contact": True, "strike_count": 2},
    {"id": 541, "name": "Tail Slap",
     "type": TYPE_NORMAL, "category": PHYS, "power": 25, "accuracy": 85, "pp": 10,
     "makes_contact": True, "multi_hit": True},
    {"id": 544, "name": "Gear Grind",
     "type": TYPE_STEEL, "category": PHYS, "power": 50, "accuracy": 85, "pp": 15,
     "makes_contact": True, "strike_count": 2},
    # Water Shuriken: real source's Greninja-Ash/Battle-Bond species+numOfHits
    # override (EFFECT_SPECIES_POWER_OVERRIDE) is a form-change mechanic this
    # project has no infrastructure for (no Battle Bond, no Ash-Greninja form) —
    # flagged, not built, matching this project's established "flag doubles/
    # form-only gaps" precedent. The GENERAL case (any other species) is a plain
    # multi_hit move: power=15, priority=+1, Special category under this
    # project's default B_UPDATED_MOVE_DATA >= GEN_7 config.
    {"id": 594, "name": "Water Shuriken",
     "type": TYPE_WATER, "category": SPEC, "power": 15, "accuracy": 100, "pp": 20,
     "priority": 1, "multi_hit": True},
    # Double Iron Bash: 30% per-hit flinch chance — reuses the existing SE_FLINCH
    # dispatch, rolling independently on each hit for free via the same generic
    # per-hit secondary_effect mechanism Twineedle's poison chance uses above.
    {"id": 689, "name": "Double Iron Bash",
     "type": TYPE_STEEL, "category": PHYS, "power": 60, "accuracy": 100, "pp": 5,
     "makes_contact": True, "punching_move": True, "strike_count": 2,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},
    # Dragon Darts: real source's TARGET_SMART doubles-redirect (its second hit
    # can retarget to the ally if the first target is unaffected) is a doubles-
    # only nuance, flagged not built, matching Shell Bell's own established
    # precedent — in singles (this project's current test scope) both hits
    # simply land on the one opponent, which TARGET_SELECTED already produces.
    {"id": 697, "name": "Dragon Darts",
     "type": TYPE_DRAGON, "category": PHYS, "power": 50, "accuracy": 100, "pp": 10,
     "strike_count": 2},
    # Scale Shot: -1 Defense / +1 Speed to the user ONCE after the sequence,
    # gated on at least one hit landing — is_scale_shot dispatches this in
    # BattleManager._do_multi_hit_sequence, matching Shell Bell's own
    # once-at-the-end pattern.
    {"id": 727, "name": "Scale Shot",
     "type": TYPE_DRAGON, "category": PHYS, "power": 25, "accuracy": 90, "pp": 20,
     "multi_hit": True, "is_scale_shot": True},
    {"id": 741, "name": "Triple Axel",
     "type": TYPE_ICE, "category": PHYS, "power": 20, "accuracy": 90, "pp": 10,
     "makes_contact": True, "strike_count": 3, "is_triple_kick": True},
    {"id": 742, "name": "Dual Wingbeat",
     "type": TYPE_FLYING, "category": PHYS, "power": 40, "accuracy": 90, "pp": 10,
     "makes_contact": True, "strike_count": 2},
    {"id": 746, "name": "Surging Strikes",
     "type": TYPE_WATER, "category": PHYS, "power": 25, "accuracy": 100, "pp": 5,
     "makes_contact": True, "punching_move": True, "strike_count": 3,
     "always_critical_hit": True},
    {"id": 793, "name": "Triple Dive",
     "type": TYPE_WATER, "category": PHYS, "power": 30, "accuracy": 95, "pp": 10,
     "makes_contact": True, "strike_count": 3},
    {"id": 814, "name": "Twin Beam",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 40, "accuracy": 100, "pp": 10,
     "strike_count": 2},
    # Tachyon Cutter: source's .accuracy = 0 means ALWAYS HITS (this project's
    # own convention, matching every other always-hits move in this file), not
    # "0% accuracy" — confirmed against move_data.gd's accuracy field comment.
    {"id": 839, "name": "Tachyon Cutter",
     "type": TYPE_STEEL, "category": SPEC, "power": 50, "accuracy": 0, "pp": 10,
     "slicing_move": True, "strike_count": 2},

    # ── M19-pre1: weight-based and friendship-based dynamic power ───────────
    # power=1 in every entry below is source's own placeholder value
    # (.power = 1 in moves_info.h for all 8) — completely overridden at
    # runtime by BattleManager's is_low_kick_power/is_heat_crash_power/
    # is_return_power/is_frustration_power dispatch, per that field's own
    # doc comment in move_data.gd.

    # Low Kick(67) L1804  Fighting/Phys/1/100/20, contact
    #   Source: moves_info.h MOVE_LOW_KICK (GEN_3+ branch): .effect=EFFECT_LOW_KICK,
    #   .power=1, .accuracy=100 (B_UPDATED_MOVE_DATA>=GEN_3), .makesContact=TRUE.
    {"id": 67, "name": "Low Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 1, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_low_kick_power": True},

    # Grass Knot(447) L11995  Grass/Spec/1/100/20, contact
    #   Source: moves_info.h MOVE_GRASS_KNOT: .effect=EFFECT_LOW_KICK, .power=1,
    #   .accuracy=100, .category=DAMAGE_CATEGORY_SPECIAL, .makesContact=TRUE.
    {"id": 447, "name": "Grass Knot",
     "type": TYPE_GRASS, "category": SPEC, "power": 1, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_low_kick_power": True},

    # Heavy Slam(484) L12936  Steel/Phys/1/100/10, contact
    #   Source: moves_info.h MOVE_HEAVY_SLAM: .effect=EFFECT_HEAT_CRASH, .power=1,
    #   .accuracy=100, .makesContact=TRUE.
    {"id": 484, "name": "Heavy Slam",
     "type": TYPE_STEEL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_heat_crash_power": True},

    # Heat Crash(535) L14224  Fire/Phys/1/100/10, contact
    #   Source: moves_info.h MOVE_HEAT_CRASH: .effect=EFFECT_HEAT_CRASH, .power=1,
    #   .accuracy=100, .makesContact=TRUE.
    {"id": 535, "name": "Heat Crash",
     "type": TYPE_FIRE, "category": PHYS, "power": 1, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_heat_crash_power": True},

    # Return(216) L5918  Normal/Phys/1/100/20, contact
    #   Source: moves_info.h MOVE_RETURN: .effect=EFFECT_RETURN, .power=1,
    #   .accuracy=100, .makesContact=TRUE.
    {"id": 216, "name": "Return",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_return_power": True},

    # Frustration(218) L5964  Normal/Phys/1/100/20, contact
    #   Source: moves_info.h MOVE_FRUSTRATION: .effect=EFFECT_FRUSTRATION, .power=1,
    #   .accuracy=100, .makesContact=TRUE.
    {"id": 218, "name": "Frustration",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_frustration_power": True},

    # Pika Papow(679) L17958  Electric/Spec/1/0(always hits)/20, no contact
    #   Source: moves_info.h MOVE_PIKA_PAPOW: .effect=EFFECT_RETURN (the exact
    #   SAME formula as Return, confirmed — not a separate/similar effect),
    #   .power=1, .accuracy=0, .category=DAMAGE_CATEGORY_SPECIAL, no makesContact.
    {"id": 679, "name": "Pika Papow",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 1, "accuracy": 0, "pp": 20,
     "is_return_power": True},

    # Veevee Volley(688) L18162  Normal/Phys/1/0(always hits)/20, contact
    #   Source: moves_info.h MOVE_VEEVEE_VOLLEY: .effect=EFFECT_RETURN (same
    #   formula as Return/Pika Papow), .power=1, .accuracy=0, .makesContact=TRUE.
    {"id": 688, "name": "Veevee Volley",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 0, "pp": 20,
     "makes_contact": True, "is_return_power": True},

    # ── M19a-gen1: Tier 1 pure-damage data-entry, Generation I ────────────────
    # 7 of Gen I's 22 not-yet-implemented Tier-1 moves were found to need a
    # mechanism this project doesn't have (Thrash/Petal Dance rampage lock-in,
    # Rage's hit-triggered Attack boost, Hyper Beam's recharge, Self-Destruct/
    # Explosion's unconditional self-faint + Damp block, Tri Attack's random
    # burn/paralysis/freeze choice) — excluded from this tier, flagged for a
    # future session rather than built here. The 15 below are confirmed pure
    # EFFECT_HIT with only already-wired generic flags (no additionalEffects
    # in source beyond Pay Day's cosmetic-only MOVE_EFFECT_PAYDAY, which has
    # zero battle-mechanical effect and is not modeled).

    # Mega Punch(5) L189  Normal/Phys/80/85/20, contact
    {"id": 5, "name": "Mega Punch",
     "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 85, "pp": 20,
     "makes_contact": True},

    # Pay Day(6) L165  Normal/Phys/40/100/20 — MOVE_EFFECT_PAYDAY is a cosmetic
    #   money-scatter with zero battle-mechanical effect, not modeled.
    {"id": 6, "name": "Pay Day",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 20},

    # Vise Grip(11) L299  Normal/Phys/55/100/30, contact
    {"id": 11, "name": "Vise Grip",
     "type": TYPE_NORMAL, "category": PHYS, "power": 55, "accuracy": 100, "pp": 30,
     "makes_contact": True},

    # Cut(15) L413  Normal/Phys/50/95/30, contact, slicing
    {"id": 15, "name": "Cut",
     "type": TYPE_NORMAL, "category": PHYS, "power": 50, "accuracy": 95, "pp": 30,
     "makes_contact": True, "slicing_move": True},

    # Gust(16) L436  Flying/Spec/40/100/35 — type is TYPE_FLYING at GEN_LATEST
    #   (B_UPDATED_MOVE_TYPES >= GEN_2); damagesAirborneDoubleDamage -> damages_airborne.
    {"id": 16, "name": "Gust",
     "type": TYPE_FLYING, "category": SPEC, "power": 40, "accuracy": 100, "pp": 35,
     "damages_airborne": True},

    # Slam(21) L578  Normal/Phys/80/75/20, contact
    {"id": 21, "name": "Slam",
     "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 75, "pp": 20,
     "makes_contact": True},

    # Mega Kick(25) L683  Normal/Phys/120/75/5, contact
    {"id": 25, "name": "Mega Kick",
     "type": TYPE_NORMAL, "category": PHYS, "power": 120, "accuracy": 75, "pp": 5,
     "makes_contact": True},

    # Horn Attack(30) L819  Normal/Phys/65/100/25, contact
    {"id": 30, "name": "Horn Attack",
     "type": TYPE_NORMAL, "category": PHYS, "power": 65, "accuracy": 100, "pp": 25,
     "makes_contact": True},

    # Hydro Pump(56) L1511  Water/Spec/110/80/5 — power=110 at GEN_LATEST
    #   (B_UPDATED_MOVE_DATA >= GEN_6), not the pre-Gen-6 120.
    {"id": 56, "name": "Hydro Pump",
     "type": TYPE_WATER, "category": SPEC, "power": 110, "accuracy": 80, "pp": 5},

    # Peck(64) L1735  Flying/Phys/35/100/35, contact
    {"id": 64, "name": "Peck",
     "type": TYPE_FLYING, "category": PHYS, "power": 35, "accuracy": 100, "pp": 35,
     "makes_contact": True},

    # Drill Peck(65) L1757  Flying/Phys/80/100/20, contact
    {"id": 65, "name": "Drill Peck",
     "type": TYPE_FLYING, "category": PHYS, "power": 80, "accuracy": 100, "pp": 20,
     "makes_contact": True},

    # Razor Leaf(75) L2028  Grass/Phys/55/95/25, slicing, +1 crit stage
    #   (criticalHitStage: B_UPDATED_MOVE_DATA >= GEN_3 ? 1 : 2 -> 1 at
    #   GEN_LATEST), TARGET_BOTH -> is_spread (Earthquake/Surf precedent).
    {"id": 75, "name": "Razor Leaf",
     "type": TYPE_GRASS, "category": PHYS, "power": 55, "accuracy": 95, "pp": 25,
     "slicing_move": True, "critical_hit_stage": 1, "is_spread": True},

    # Egg Bomb(121) L3297  Normal/Phys/100/75/10, ballistic
    {"id": 121, "name": "Egg Bomb",
     "type": TYPE_NORMAL, "category": PHYS, "power": 100, "accuracy": 75, "pp": 10,
     "ballistic_move": True},

    # Crabhammer(152) L4144  Water/Phys/100/90/10, contact, +1 crit stage
    #   (power/accuracy both GEN_LATEST branches: 100 not 90, 90 not 85;
    #   criticalHitStage: B_UPDATED_MOVE_DATA >= GEN_3 ? 1 : 2 -> 1).
    {"id": 152, "name": "Crabhammer",
     "type": TYPE_WATER, "category": PHYS, "power": 100, "accuracy": 90, "pp": 10,
     "makes_contact": True, "critical_hit_stage": 1},

    # Slash(163) L4451  Normal/Phys/70/100/20, contact, slicing, +1 crit stage
    {"id": 163, "name": "Slash",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "makes_contact": True, "slicing_move": True, "critical_hit_stage": 1},

    # ── Bucket 1: pure damage, no additional effect (M19-bucket1) ─────────────

    # Aeroblast(177)  Flying/Spec/100/95/5, critical_hit_stage
    {"id": 177, "name": "Aeroblast",
     "type": TYPE_FLYING, "category": SPEC, "power": 100, "accuracy": 95, "pp": 5,
     "critical_hit_stage": 1},

    # Mach Punch(183)  Fighting/Phys/40/100/30, makes_contact, punching_move, priority
    {"id": 183, "name": "Mach Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 40, "accuracy": 100, "pp": 30,
     "makes_contact": True, "punching_move": True, "priority": 1},

    # Feint Attack(185)  Dark/Phys/60/0/20, no flags
    {"id": 185, "name": "Feint Attack",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20},

    # Megahorn(224)  Bug/Phys/120/85/10, makes_contact
    {"id": 224, "name": "Megahorn",
     "type": TYPE_BUG, "category": PHYS, "power": 120, "accuracy": 85, "pp": 10,
     "makes_contact": True},

    # Vital Throw(233)  Fighting/Phys/70/0/10, makes_contact, priority
    {"id": 233, "name": "Vital Throw",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 70, "accuracy": 0, "pp": 10,
     "makes_contact": True, "priority": -1},

    # Cross Chop(238)  Fighting/Phys/100/80/5, makes_contact, critical_hit_stage
    {"id": 238, "name": "Cross Chop",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 100, "accuracy": 80, "pp": 5,
     "makes_contact": True, "critical_hit_stage": 1},

    # Extreme Speed(245)  Normal/Phys/80/100/5, makes_contact, priority
    #   priority: B_UPDATED_MOVE_DATA >= GEN_5 ? 2 : 1 -> 2 at GEN_LATEST
    {"id": 245, "name": "Extreme Speed",
     "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 100, "pp": 5,
     "makes_contact": True, "priority": 2},

    # Hyper Voice(304)  Normal/Spec/90/100/10, sound_move, is_spread
    {"id": 304, "name": "Hyper Voice",
     "type": TYPE_NORMAL, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True},

    # Air Cutter(314)  Flying/Spec/60/95/25, slicing_move, is_spread, critical_hit_stage
    {"id": 314, "name": "Air Cutter",
     "type": TYPE_FLYING, "category": SPEC, "power": 60, "accuracy": 95, "pp": 25,
     "slicing_move": True, "is_spread": True, "critical_hit_stage": 1},

    # Shadow Punch(325)  Ghost/Phys/60/0/20, makes_contact, punching_move
    {"id": 325, "name": "Shadow Punch",
     "type": TYPE_GHOST, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20,
     "makes_contact": True, "punching_move": True},

    # Sky Uppercut(327)  Fighting/Phys/85/90/15, makes_contact, punching_move, damages_airborne
    #   damagesAirborne(plain, not DoubleDamage) -> damages_airborne per this project's unified-field convention (status_manager.gd:764)
    {"id": 327, "name": "Sky Uppercut",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 85, "accuracy": 90, "pp": 15,
     "makes_contact": True, "punching_move": True, "damages_airborne": True},

    # Dragon Claw(337)  Dragon/Phys/80/100/15, makes_contact
    {"id": 337, "name": "Dragon Claw",
     "type": TYPE_DRAGON, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True},

    # Magical Leaf(345)  Grass/Spec/60/0/20, no flags
    {"id": 345, "name": "Magical Leaf",
     "type": TYPE_GRASS, "category": SPEC, "power": 60, "accuracy": 0, "pp": 20},

    # Leaf Blade(348)  Grass/Phys/90/100/15, makes_contact, slicing_move, critical_hit_stage
    {"id": 348, "name": "Leaf Blade",
     "type": TYPE_GRASS, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "makes_contact": True, "slicing_move": True, "critical_hit_stage": 1},

    # Shock Wave(351)  Electric/Spec/60/0/20, no flags
    {"id": 351, "name": "Shock Wave",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 60, "accuracy": 0, "pp": 20},

    # Aura Sphere(396)  Fighting/Spec/80/0/20, ballistic_move, pulse_move
    #   pulseMove=TRUE -> pulse_move (wired to Mega Launcher, ability_manager.gd:1794)
    {"id": 396, "name": "Aura Sphere",
     "type": TYPE_FIGHTING, "category": SPEC, "power": 80, "accuracy": 0, "pp": 20,
     "ballistic_move": True, "pulse_move": True},

    # Night Slash(400)  Dark/Phys/70/100/15, makes_contact, slicing_move, critical_hit_stage
    {"id": 400, "name": "Night Slash",
     "type": TYPE_DARK, "category": PHYS, "power": 70, "accuracy": 100, "pp": 15,
     "makes_contact": True, "slicing_move": True, "critical_hit_stage": 1},

    # Aqua Tail(401)  Water/Phys/90/90/10, makes_contact
    {"id": 401, "name": "Aqua Tail",
     "type": TYPE_WATER, "category": PHYS, "power": 90, "accuracy": 90, "pp": 10,
     "makes_contact": True},

    # Seed Bomb(402)  Grass/Phys/80/100/15, ballistic_move
    {"id": 402, "name": "Seed Bomb",
     "type": TYPE_GRASS, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "ballistic_move": True},

    # X-Scissor(404)  Bug/Phys/80/100/15, makes_contact, slicing_move
    {"id": 404, "name": "X-Scissor",
     "type": TYPE_BUG, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True, "slicing_move": True},

    # Dragon Pulse(406)  Dragon/Spec/85/100/10, pulse_move
    #   pulseMove=TRUE -> pulse_move
    {"id": 406, "name": "Dragon Pulse",
     "type": TYPE_DRAGON, "category": SPEC, "power": 85, "accuracy": 100, "pp": 10,
     "pulse_move": True},

    # Power Gem(408)  Rock/Spec/80/100/20, no flags
    {"id": 408, "name": "Power Gem",
     "type": TYPE_ROCK, "category": SPEC, "power": 80, "accuracy": 100, "pp": 20},

    # Vacuum Wave(410)  Fighting/Spec/40/100/30, priority
    {"id": 410, "name": "Vacuum Wave",
     "type": TYPE_FIGHTING, "category": SPEC, "power": 40, "accuracy": 100, "pp": 30,
     "priority": 1},

    # Bullet Punch(418)  Steel/Phys/40/100/30, makes_contact, punching_move, priority
    {"id": 418, "name": "Bullet Punch",
     "type": TYPE_STEEL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 30,
     "makes_contact": True, "punching_move": True, "priority": 1},

    # Ice Shard(420)  Ice/Phys/40/100/30, priority
    {"id": 420, "name": "Ice Shard",
     "type": TYPE_ICE, "category": PHYS, "power": 40, "accuracy": 100, "pp": 30,
     "priority": 1},

    # Shadow Claw(421)  Ghost/Phys/70/100/15, makes_contact, critical_hit_stage
    {"id": 421, "name": "Shadow Claw",
     "type": TYPE_GHOST, "category": PHYS, "power": 70, "accuracy": 100, "pp": 15,
     "makes_contact": True, "critical_hit_stage": 1},

    # Shadow Sneak(425)  Ghost/Phys/40/100/30, makes_contact, priority
    {"id": 425, "name": "Shadow Sneak",
     "type": TYPE_GHOST, "category": PHYS, "power": 40, "accuracy": 100, "pp": 30,
     "makes_contact": True, "priority": 1},

    # Psycho Cut(427)  Psychic/Phys/70/100/20, slicing_move, critical_hit_stage
    {"id": 427, "name": "Psycho Cut",
     "type": TYPE_PSYCHIC, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "slicing_move": True, "critical_hit_stage": 1},

    # Power Whip(438)  Grass/Phys/120/85/10, makes_contact
    {"id": 438, "name": "Power Whip",
     "type": TYPE_GRASS, "category": PHYS, "power": 120, "accuracy": 85, "pp": 10,
     "makes_contact": True},

    # Magnet Bomb(443)  Steel/Phys/60/0/20, ballistic_move
    {"id": 443, "name": "Magnet Bomb",
     "type": TYPE_STEEL, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20,
     "ballistic_move": True},

    # Stone Edge(444)  Rock/Phys/100/80/5, critical_hit_stage
    {"id": 444, "name": "Stone Edge",
     "type": TYPE_ROCK, "category": PHYS, "power": 100, "accuracy": 80, "pp": 5,
     "critical_hit_stage": 1},

    # Aqua Jet(453)  Water/Phys/40/100/20, makes_contact, priority
    {"id": 453, "name": "Aqua Jet",
     "type": TYPE_WATER, "category": PHYS, "power": 40, "accuracy": 100, "pp": 20,
     "makes_contact": True, "priority": 1},

    # Spacial Rend(460)  Dragon/Spec/100/95/5, critical_hit_stage
    {"id": 460, "name": "Spacial Rend",
     "type": TYPE_DRAGON, "category": SPEC, "power": 100, "accuracy": 95, "pp": 5,
     "critical_hit_stage": 1},

    # Storm Throw(480)  Fighting/Phys/60/100/10, makes_contact, always_critical_hit
    #   alwaysCriticalHit=TRUE -> always_critical_hit (existing field, M18.5g precedent)
    {"id": 480, "name": "Storm Throw",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "makes_contact": True, "always_critical_hit": True},

    # Frost Breath(524)  Ice/Spec/60/90/10, always_critical_hit
    #   alwaysCriticalHit=TRUE -> always_critical_hit
    {"id": 524, "name": "Frost Breath",
     "type": TYPE_ICE, "category": SPEC, "power": 60, "accuracy": 90, "pp": 10,
     "always_critical_hit": True},

    # Drill Run(529)  Ground/Phys/80/95/10, makes_contact, critical_hit_stage
    {"id": 529, "name": "Drill Run",
     "type": TYPE_GROUND, "category": PHYS, "power": 80, "accuracy": 95, "pp": 10,
     "makes_contact": True, "critical_hit_stage": 1},

    # Petal Blizzard(572)  Grass/Phys/90/100/15, is_spread
    {"id": 572, "name": "Petal Blizzard",
     "type": TYPE_GRASS, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "is_spread": True},

    # Disarming Voice(574)  Fairy/Spec/40/0/15, sound_move, is_spread
    {"id": 574, "name": "Disarming Voice",
     "type": TYPE_FAIRY, "category": SPEC, "power": 40, "accuracy": 0, "pp": 15,
     "sound_move": True, "is_spread": True},

    # Fairy Wind(584)  Fairy/Spec/40/100/30, no flags
    {"id": 584, "name": "Fairy Wind",
     "type": TYPE_FAIRY, "category": SPEC, "power": 40, "accuracy": 100, "pp": 30},

    # Boomburst(586)  Normal/Spec/140/100/10, sound_move, is_spread
    {"id": 586, "name": "Boomburst",
     "type": TYPE_NORMAL, "category": SPEC, "power": 140, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True},

    # Dazzling Gleam(605)  Fairy/Spec/80/100/10, is_spread
    {"id": 605, "name": "Dazzling Gleam",
     "type": TYPE_FAIRY, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "is_spread": True},

    # Land's Wrath(616)  Ground/Phys/90/100/10, is_spread
    {"id": 616, "name": "Land's Wrath",
     "type": TYPE_GROUND, "category": PHYS, "power": 90, "accuracy": 100, "pp": 10,
     "is_spread": True},

    # Origin Pulse(618)  Water/Spec/110/85/10, is_spread, pulse_move
    #   pulseMove=TRUE -> pulse_move; TARGET_FOES_AND_ALLY -> is_spread
    {"id": 618, "name": "Origin Pulse",
     "type": TYPE_WATER, "category": SPEC, "power": 110, "accuracy": 85, "pp": 10,
     "is_spread": True, "pulse_move": True},

    # Precipice Blades(619)  Ground/Phys/120/85/10, is_spread
    {"id": 619, "name": "Precipice Blades",
     "type": TYPE_GROUND, "category": PHYS, "power": 120, "accuracy": 85, "pp": 10,
     "is_spread": True},

    # High Horsepower(630)  Ground/Phys/95/95/10, makes_contact
    {"id": 630, "name": "High Horsepower",
     "type": TYPE_GROUND, "category": PHYS, "power": 95, "accuracy": 95, "pp": 10,
     "makes_contact": True},

    # Leafage(633)  Grass/Phys/40/100/40, no flags
    {"id": 633, "name": "Leafage",
     "type": TYPE_GRASS, "category": PHYS, "power": 40, "accuracy": 100, "pp": 40},

    # Smart Strike(647)  Steel/Phys/70/0/10, makes_contact
    {"id": 647, "name": "Smart Strike",
     "type": TYPE_STEEL, "category": PHYS, "power": 70, "accuracy": 0, "pp": 10,
     "makes_contact": True},

    # Dragon Hammer(655)  Dragon/Phys/90/100/15, makes_contact
    {"id": 655, "name": "Dragon Hammer",
     "type": TYPE_DRAGON, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "makes_contact": True},

    # Brutal Swing(656)  Dark/Phys/60/100/20, makes_contact, is_spread
    {"id": 656, "name": "Brutal Swing",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_spread": True},

    # Accelerock(663)  Rock/Phys/40/100/20, makes_contact, priority
    {"id": 663, "name": "Accelerock",
     "type": TYPE_ROCK, "category": PHYS, "power": 40, "accuracy": 100, "pp": 20,
     "makes_contact": True, "priority": 1},

    # Branch Poke(713)  Grass/Phys/40/100/40, makes_contact
    {"id": 713, "name": "Branch Poke",
     "type": TYPE_GRASS, "category": PHYS, "power": 40, "accuracy": 100, "pp": 40,
     "makes_contact": True},

    # Overdrive(714)  Electric/Spec/80/100/10, sound_move, is_spread
    {"id": 714, "name": "Overdrive",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True},

    # False Surrender(721)  Dark/Phys/80/0/10, makes_contact
    {"id": 721, "name": "False Surrender",
     "type": TYPE_DARK, "category": PHYS, "power": 80, "accuracy": 0, "pp": 10,
     "makes_contact": True},

    # Wicked Blow(745)  Dark/Phys/75/100/5, makes_contact, punching_move, always_critical_hit
    #   alwaysCriticalHit=TRUE -> always_critical_hit
    {"id": 745, "name": "Wicked Blow",
     "type": TYPE_DARK, "category": PHYS, "power": 75, "accuracy": 100, "pp": 5,
     "makes_contact": True, "punching_move": True, "always_critical_hit": True},

    # Glacial Lance(752)  Ice/Phys/120/100/5, is_spread
    {"id": 752, "name": "Glacial Lance",
     "type": TYPE_ICE, "category": PHYS, "power": 120, "accuracy": 100, "pp": 5,
     "is_spread": True},

    # Astral Barrage(753)  Ghost/Spec/120/100/5, is_spread
    {"id": 753, "name": "Astral Barrage",
     "type": TYPE_GHOST, "category": SPEC, "power": 120, "accuracy": 100, "pp": 5,
     "is_spread": True},

    # Jet Punch(785)  Water/Phys/60/100/15, makes_contact, punching_move, priority
    {"id": 785, "name": "Jet Punch",
     "type": TYPE_WATER, "category": PHYS, "power": 60, "accuracy": 100, "pp": 15,
     "makes_contact": True, "punching_move": True, "priority": 1},

    # Kowtow Cleave(797)  Dark/Phys/85/0/10, makes_contact, slicing_move
    {"id": 797, "name": "Kowtow Cleave",
     "type": TYPE_DARK, "category": PHYS, "power": 85, "accuracy": 0, "pp": 10,
     "makes_contact": True, "slicing_move": True},

    # Flower Trick(798)  Grass/Phys/70/0/10, always_critical_hit
    #   alwaysCriticalHit=TRUE -> always_critical_hit
    {"id": 798, "name": "Flower Trick",
     "type": TYPE_GRASS, "category": PHYS, "power": 70, "accuracy": 0, "pp": 10,
     "always_critical_hit": True},

    # Hyper Drill(813)  Normal/Phys/100/100/5, makes_contact
    {"id": 813, "name": "Hyper Drill",
     "type": TYPE_NORMAL, "category": PHYS, "power": 100, "accuracy": 100, "pp": 5,
     "makes_contact": True},

    # Aqua Cutter(821)  Water/Phys/70/100/20, slicing_move, critical_hit_stage
    {"id": 821, "name": "Aqua Cutter",
     "type": TYPE_WATER, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "slicing_move": True, "critical_hit_stage": 1},
]

# ── MoveData field defaults (fields at default value are omitted from .tres) ──
DEFAULTS = {
    "type":                TYPE_NONE,
    "category":            PHYS,
    "power":               0,
    "accuracy":            100,
    "pp":                  5,
    "makes_contact":       False,
    "punching_move":       False,
    "priority":            0,
    "critical_hit_stage":  0,
    # [M18.5g] always_critical_hit: a genuine second pre-existing gap in the same
    # shape as strike_count/multi_hit — the MoveData schema field already existed
    # (M16a-era), but was never added to this generator's own DEFAULTS/FIELD_ORDER
    # at all, confirmed via direct grep. Surging Strikes (this tier's own move,
    # always_critical_hit=True) is the first move in this project's roster to
    # actually need it, surfacing the gap.
    "always_critical_hit": False,
    "thaws_user":          False,
    "powder_move":         False,
    "sound_move":          False,
    "secondary_effect":    SE_NONE,
    "secondary_chance":    0,
    "stat_change_stat":    -1,
    "stat_change_amount":  0,
    "stat_change_self":    False,
    # M6 fields
    "two_turn":            False,
    "semi_inv_state":      SEMI_INV_NONE,
    "damages_underground": False,
    "damages_airborne":    False,
    "damages_underwater":  False,
    "recoil_percent":      0,
    "drain_percent":       0,
    "fixed_damage":        0,
    "level_damage":        False,
    # M7 fields
    "ban_flags":           0,
    "ignores_substitute":  False,
    "ignores_protect":     False,
    "creates_substitute":  False,
    "is_protect":          False,
    "counter":             False,
    "mirror_coat":         False,
    "destiny_bond":        False,
    "is_disable":          False,
    "is_encore":           False,
    "is_bide":             False,
    "is_metronome":        False,
    # M9 fields
    "is_roar":             False,
    "is_baton_pass":       False,
    # M14b fields
    "is_spread":           False,
    "is_helping_hand":     False,
    "is_follow_me":        False,
    # M15 fields
    "is_solar_beam":       False,
    "charge_turn_defense_boost": 0,
    "is_struggle":         False,
    # M16a fields
    "is_restore_hp":       False,
    "is_focus_energy":     False,
    "is_growth":           False,
    "is_ohko":             False,
    # M16b fields
    "is_minimize":              False,
    "is_defense_curl":          False,
    "double_power_on_minimized": False,
    "is_rollout":                False,
    "is_magnitude":              False,
    # M16c fields
    "is_reflect":                False,
    "is_light_screen":           False,
    "is_aurora_veil":            False,
    "breaks_screens":            False,
    # M16d fields
    "is_spikes":                 False,
    "is_toxic_spikes":           False,
    "is_stealth_rock":           False,
    "is_rapid_spin":             False,
    "is_trick_room":             False,
    # M16e fields
    "is_pursuit":                False,
    "is_pain_split":             False,
    "is_conversion":             False,
    "is_conversion2":            False,
    "is_psych_up":               False,
    # M17n-1 fields
    "ballistic_move":            False,
    "blocked_by_aroma_veil":     False,
    # M17n-3 fields
    "healing_move":              False,
    # M17n-5 fields — biting_move/slicing_move were already dormant MoveData schema
    # fields (never wired into this generator until now, same "already there, just
    # unwired" gap [M17n-3] closed for healing_move); pulse_move is a genuinely new
    # schema field added this tier (confirmed absent, unlike the other two).
    "biting_move":                False,
    "slicing_move":               False,
    "pulse_move":                 False,
    # M17n-9 field: bounceable (Magic Bounce's magicCoatAffected-derived subset).
    "bounceable":                 False,
    # M18.5d-2 field: is_attract (Attract's own dedicated dispatch — deliberately
    # NOT added to blocked_by_aroma_veil's list, see that field's own doc comment
    # in move_data.gd for why).
    "is_attract":                 False,
    # M18.5g fields. strike_count/multi_hit are a genuine second gap beyond the
    # dormant MoveData schema fields themselves: confirmed via direct grep that
    # NEITHER was ever present in this generator's own DEFAULTS/FIELD_ORDER at
    # all — meaning even a hand-authored MOVES entry setting strike_count=3 would
    # have been silently dropped by render()'s `value == default` skip (comparing
    # against Python's own implicit None-default) before this fix. is_triple_kick
    # (Triple Kick/Triple Axel's per-hit accuracy + escalating power) and
    # is_scale_shot (Scale Shot's once-after-the-sequence self stat change) are
    # newly-added fields with no such pre-existing gap.
    "strike_count":               1,
    "multi_hit":                  False,
    "is_triple_kick":             False,
    "is_scale_shot":              False,

    # [M19-pre1] weight-based and friendship-based dynamic power.
    "is_low_kick_power":          False,
    "is_heat_crash_power":        False,
    "is_return_power":            False,
    "is_frustration_power":       False,
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
    "makes_contact", "punching_move", "priority", "critical_hit_stage",
    "always_critical_hit",
    "thaws_user", "powder_move", "sound_move",
    "secondary_effect", "secondary_chance",
    "stat_change_stat", "stat_change_amount", "stat_change_self",
    # M6 fields
    "two_turn", "semi_inv_state",
    "damages_underground", "damages_airborne", "damages_underwater",
    "recoil_percent", "drain_percent", "fixed_damage", "level_damage",
    # M7 fields
    "ban_flags", "ignores_substitute", "ignores_protect",
    "creates_substitute", "is_protect", "counter", "mirror_coat",
    "destiny_bond", "is_disable", "is_encore", "is_bide", "is_metronome",
    # M9 fields
    "is_roar", "is_baton_pass",
    # M14b fields
    "is_spread", "is_helping_hand", "is_follow_me",
    # M15 fields
    "is_solar_beam", "charge_turn_defense_boost", "is_struggle",
    # M16a fields
    "is_restore_hp", "is_focus_energy", "is_growth", "is_ohko",
    # M16b fields
    "is_minimize", "is_defense_curl", "double_power_on_minimized",
    "is_rollout", "is_magnitude",
    # M16c fields
    "is_reflect", "is_light_screen", "is_aurora_veil", "breaks_screens",
    # M16d fields
    "is_spikes", "is_toxic_spikes", "is_stealth_rock", "is_rapid_spin", "is_trick_room",
    # M16e fields
    "is_pursuit", "is_pain_split", "is_conversion", "is_conversion2", "is_psych_up",
    # M17n-1 fields
    "ballistic_move", "blocked_by_aroma_veil",
    # M17n-3 fields
    "healing_move",
    # M17n-5 fields
    "biting_move", "slicing_move", "pulse_move",
    # M17n-9 fields
    "bounceable",
    # M18.5d-2 fields
    "is_attract",
    # M18.5g fields
    "strike_count", "multi_hit", "is_triple_kick", "is_scale_shot",
    # M19-pre1 fields
    "is_low_kick_power", "is_heat_crash_power", "is_return_power", "is_frustration_power",
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
