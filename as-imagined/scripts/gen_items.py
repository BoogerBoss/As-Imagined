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

# M18-patch-1: Pocket enum id (must match scripts/battle/core/item_manager.gd's
# ItemManager.POCKET_BERRIES). Source: include/constants/item.h. Only
# POCKET_BERRIES is modeled; set on every real berry entry below so
# Cheek Pouch/Harvest/Cud Chew can gate on it correctly (battle_manager.gd's
# _consume_item) — previously this field existed in the schema but was never
# populated for any item.
POCKET_BERRIES = 3

# ── HOLD_EFFECT_* constants (must match scripts/battle/core/item_manager.gd) ──
HOLD_EFFECT_RESTORE_HP      = 1   # Oran Berry — flat heal (M18b)
HOLD_EFFECT_CURE_PAR        = 2   # Cheri Berry (M18b)
HOLD_EFFECT_CURE_SLP        = 3   # Chesto Berry (M18b)
HOLD_EFFECT_CURE_PSN        = 4   # Pecha Berry — cures Poison AND Toxic (M18b)
HOLD_EFFECT_CURE_BRN        = 5   # Rawst Berry (M18b)
HOLD_EFFECT_CURE_FRZ        = 6   # Aspear Berry (M18b)
HOLD_EFFECT_CURE_CONFUSION  = 8   # Persim Berry — clears confusion_turns, not .status (M18b)
HOLD_EFFECT_RESIST_BERRY    = 80  # type-resist berry, generic (M18b; Occa/Chilan precedent)

# [M18-cleanup]: the 15 M12-era legacy items' own hold_effect constants,
# copied unchanged from item_manager.gd (pure migration, not re-derived).
HOLD_EFFECT_CURE_STATUS       = 9    # Lum Berry -- onStatusChange flag set
HOLD_EFFECT_CHOICE_BAND       = 29
HOLD_EFFECT_RESTORE_PCT_HP    = 82   # Sitrus Berry -- param=25 (25%)
HOLD_EFFECT_LEFTOVERS         = 41
HOLD_EFFECT_CHOICE_SCARF      = 49
HOLD_EFFECT_CHOICE_SPECS      = 50
HOLD_EFFECT_DAMP_ROCK         = 51   # Rain -> 8 turns
HOLD_EFFECT_HEAT_ROCK         = 53   # Sun -> 8 turns
HOLD_EFFECT_ICY_ROCK          = 54   # Hail -> 8 turns
HOLD_EFFECT_SMOOTH_ROCK       = 56   # Sandstorm -> 8 turns
HOLD_EFFECT_LIFE_ORB          = 60
HOLD_EFFECT_UTILITY_UMBRELLA  = 115
HOLD_EFFECT_HEAVY_DUTY_BOOTS  = 119  # full immunity to entry hazards on switch-in

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
HOLD_EFFECT_RESTORE_PP = 7       # M18d: Leppa Berry — 10 PP to first zero-PP move
HOLD_EFFECT_JABOCA_BERRY = 85    # M18d: 1/8 max HP retaliation on ANY physical hit,
                                  #       not contact-gated (a real correction)
HOLD_EFFECT_ROWAP_BERRY = 86     # M18d: same as Jaboca but special-category
HOLD_EFFECT_SOUL_DEW = 33        # M18g: Latios/Latias — type-boost ONLY (GEN_LATEST)
HOLD_EFFECT_DEEP_SEA_TOOTH = 34  # M18g: Clamperl — x2.0 SpAtk, special-only
HOLD_EFFECT_DEEP_SEA_SCALE = 35  # M18g: Clamperl — x2.0 SpDef, special-only
HOLD_EFFECT_LIGHT_BALL = 42      # M18g: Pikachu — x2.0 Atk AND SpAtk
HOLD_EFFECT_LUCKY_PUNCH = 45     # M18g: Chansey ONLY — +2 crit stage
HOLD_EFFECT_METAL_POWDER = 46    # M18g: Ditto — x2.0 DEFENSE (not SpDef), physical-only
HOLD_EFFECT_THICK_CLUB = 47      # M18g: Cubone OR Marowak — x2.0 Atk, physical-only
HOLD_EFFECT_LEEK = 48            # M18g: Farfetch'd — +2 crit stage
HOLD_EFFECT_QUICK_POWDER = 75    # M18g: Ditto — x2.0 SPEED (not Defense)

# ── SPECIES_* national_dex_num values (must match data/pokemon.json) ─────────
SPECIES_PIKACHU = 25
SPECIES_FARFETCHD = 83
SPECIES_CUBONE = 104
SPECIES_MAROWAK = 105
SPECIES_CHANSEY = 113
SPECIES_DITTO = 132
SPECIES_CLAMPERL = 366
SPECIES_LATIAS = 380
SPECIES_LATIOS = 381
SPECIES_KYOGRE = 382   # M18w: Blue Orb
SPECIES_GROUDON = 383  # M18w: Red Orb

HOLD_EFFECT_MACHO_BRACE = 24  # M18h: own constant, same halve-Speed effect as below
HOLD_EFFECT_POWER_ITEM = 81   # M18h: Power Weight/Bracer/Belt/Lens/Band/Anklet (6 items)
HOLD_EFFECT_FLAME_ORB = 68    # M18i: self-inflicts STATUS_BURN, checked every end of turn
HOLD_EFFECT_TOXIC_ORB = 69    # M18i: self-inflicts STATUS_TOXIC (badly poisoned)
HOLD_EFFECT_MUSCLE_BAND = 62   # M18j: physical power x1.1, FLOORED rounding
HOLD_EFFECT_WISE_GLASSES = 64  # M18j: special power x1.1, FLOORED rounding
HOLD_EFFECT_EXPERT_BELT = 59   # M18j: flat x1.2 when effectiveness>=2.0 (different
                                #       pipeline stage than Muscle Band/Wise Glasses)
HOLD_EFFECT_WIDE_LENS = 63     # M18j: attacker accuracy x1.10, unconditional
HOLD_EFFECT_ZOOM_LENS = 65     # M18j: attacker accuracy x1.20, target-already-acted only
HOLD_EFFECT_EVASION_UP = 22    # M18j: Bright Powder AND Lax Incense, x0.90 defender-side
HOLD_EFFECT_FLINCH = 30        # M18k: King's Rock AND Razor Fang, both param=10,
                                #       genuinely identical (adds flinch to a move
                                #       with no native flinch effect of its own)
HOLD_EFFECT_RED_CARD = 97      # M18n: forces the ATTACKER to switch
HOLD_EFFECT_EJECT_BUTTON = 100 # M18n: forces the HOLDER itself to switch
HOLD_EFFECT_FOCUS_BAND = 38    # M18o: probabilistic (10%) survive-lethal, no HP gate
HOLD_EFFECT_SHELL_BELL = 44    # M18q: heals 1/8 of final damage dealt
HOLD_EFFECT_BIG_ROOT = 58      # M18q: +30% move-drain healing
HOLD_EFFECT_FOCUS_SASH = 67    # M18o: full-HP-gated survive-lethal, single-use

# M18r: Standalone reuses (7 items, 7 different existing mechanisms). Values
# re-derived programmatically from include/constants/hold_effects.h's enum
# position, cross-validated against 8 pre-existing constants above with zero
# mismatches (see item_manager.gd's own doc comment for the full list).
HOLD_EFFECT_LIGHT_CLAY = 55       # M18r: Reflect/Light Screen/Aurora Veil -> 8 turns
HOLD_EFFECT_POWER_HERB = 57       # M18r: skips a two-turn move's charge turn once
HOLD_EFFECT_BLACK_SLUDGE = 72     # M18r: Poison heal 1/16 / non-Poison damage 1/8
                                   #       (NOT 1/16 -- a correction, see decisions.md)
HOLD_EFFECT_SHED_SHELL = 74       # M18r: bypasses ability-based trapping (voluntary
                                   #       switch only)
HOLD_EFFECT_SAFETY_GOGGLES = 104  # M18r: weather-chip immunity + powder-move immunity
HOLD_EFFECT_ROOM_SERVICE = 117    # M18r: -1 Speed on Trick Room set OR switch-in
                                   #       while active (TWO triggers -- a correction,
                                   #       see decisions.md)
HOLD_EFFECT_BLUNDER_POLICY = 118  # M18r: +2 Speed when the holder's own move misses
                                   #       (non-OHKO), consumed only if Speed rose

# M18s/M18u/M18w combined session (6 items). Values re-derived programmatically,
# cross-validated against 7 pre-existing constants above with zero mismatches.
HOLD_EFFECT_EVIOLITE = 91        # M18s: +50% Def AND SpDef if CanEvolve(species)
HOLD_EFFECT_ASSAULT_VEST = 92    # M18s: +50% SpDef only + status-move restriction
HOLD_EFFECT_BERSERK_GENE = 129   # M18u: +2 Atk + infinite self-confusion, switch-in only
HOLD_EFFECT_METRONOME = 61       # M18u: +20%/consecutive same-move use, capped at 5 uses
HOLD_EFFECT_PRIMAL_ORB = 108     # M18w: Red Orb AND Blue Orb share this exact value --
                                  #       species-differentiated via required_species

# M18m: Stat-change-reactive consumed items (4 items). Values re-derived
# programmatically, cross-validated against 7 pre-existing constants above.
HOLD_EFFECT_WEAKNESS_POLICY = 107  # +2 Atk AND +2 SpAtk on a super-effective hit
HOLD_EFFECT_WHITE_HERB = 23        # resets ALL negative stat stages to 0
HOLD_EFFECT_EJECT_PACK = 116       # forces the holder to switch on any stat drop
HOLD_EFFECT_MIRROR_HERB = 123      # copies an opponent's move-driven stat raise

# M18p: Contact-reactive damage family (4 items). Values re-derived
# programmatically, cross-validated against 6 pre-existing constants plus
# RED_CARD=97/EJECT_BUTTON=100 landing at their already-established values.
HOLD_EFFECT_STICKY_BARB = 70       # TWO independent triggers (contact-gated
                                    # item-transfer to attacker, bypassing
                                    # Sticky Hold + unconditional maxHP/8 EOT
                                    # self-damage) — see item_manager.gd's
                                    # own doc comment for the full citation.
HOLD_EFFECT_ROCKY_HELMET = 95      # Contact-gated ONLY — maxHP/6 retaliation
                                    # to the attacker, not consumed.
HOLD_EFFECT_PROTECTIVE_PADS = 109  # Narrow gate above move_makes_contact,
                                    # retaliation-effects only — see
                                    # item_manager.gd's doc comment.
HOLD_EFFECT_PUNCHING_GLOVE = 124   # x1.1 punching-move power + universal
                                    # contact-flag strip (same level as
                                    # Long Reach) for the holder's own
                                    # punching moves.

# M18t: Iron Ball / Air Balloon. Values re-derived programmatically,
# cross-validated against 6 pre-existing constants, zero mismatches.
HOLD_EFFECT_IRON_BALL = 71     # Grounds the holder (highest-priority
                                # override) + halves Speed, two independent
                                # effects sharing no code path.
HOLD_EFFECT_AIR_BALLOON = 96   # Ground-move immunity; pops on ANY damaging
                                # hit landing (not specifically a blocked
                                # Ground hit) -- see item_manager.gd's own
                                # doc comment.

# M18v: Mental Herb. Value re-derived programmatically, cross-validated
# against 6 pre-existing constants, zero mismatches.
HOLD_EFFECT_MENTAL_HERB = 28   # Cures Disable + Encore (this project's
                                # confirmed scope out of source's real 6-
                                # condition list) -- see item_manager.gd's
                                # own doc comment.

# M18x: Covert Cloak. Value re-derived programmatically, cross-validated
# against 7 pre-existing constants, zero mismatches.
HOLD_EFFECT_COVERT_CLOAK = 125  # The exact same gate as Shield Dust
                                 # (ABILITY_SHIELD_DUST), item-based instead
                                 # of ability-based -- see item_manager.gd's
                                 # own doc comment for the full scope
                                 # citation (including the confirmed-but-
                                 # unfixed Poison Touch gap).

# [M18.5i]: Grip Claw -- unblocked by [M18.5f]'s binding-move mechanic.
HOLD_EFFECT_GRIP_CLAW = 52    # Fixes binding-move duration to 7 turns instead
                              # of the random 4-5 roll -- see item_manager.gd's
                              # own doc comment for the full source citation.

# [M18.5i]: Loaded Dice -- unblocked by [M18.5g]'s multi-hit mechanism.
HOLD_EFFECT_LOADED_DICE = 126  # Re-rolls multi-hit count within [4,5] instead
                                # of the standard weighted [2,5] distribution --
                                # see item_manager.gd's own doc comment for the
                                # full source citation.

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
    {"id": 514, "name": "Cheri Berry",    "hold_effect": HOLD_EFFECT_CURE_PAR, "pocket": POCKET_BERRIES},
    {"id": 515, "name": "Chesto Berry",   "hold_effect": HOLD_EFFECT_CURE_SLP, "pocket": POCKET_BERRIES},
    {"id": 516, "name": "Pecha Berry",    "hold_effect": HOLD_EFFECT_CURE_PSN, "pocket": POCKET_BERRIES},
    {"id": 517, "name": "Rawst Berry",    "hold_effect": HOLD_EFFECT_CURE_BRN, "pocket": POCKET_BERRIES},
    {"id": 518, "name": "Aspear Berry",   "hold_effect": HOLD_EFFECT_CURE_FRZ, "pocket": POCKET_BERRIES},
    {"id": 521, "name": "Persim Berry",   "hold_effect": HOLD_EFFECT_CURE_CONFUSION, "pocket": POCKET_BERRIES},

    # ── M18b: Oran Berry — flat 10 HP heal, same <=50%-max-HP threshold as Sitrus
    #    Berry (HasEnoughHpToEatBerry(..., 2, ...) in source, shared by both), but
    #    a DISTINCT hold_effect from Sitrus's HOLD_EFFECT_RESTORE_PCT_HP(82) — this
    #    one is HOLD_EFFECT_RESTORE_HP(1), param=10 is a flat HP amount not a percent.
    {"id": 520, "name": "Oran Berry",     "hold_effect": HOLD_EFFECT_RESTORE_HP, "hold_effect_param": 10, "pocket": POCKET_BERRIES},

    # ── M18b: type-resist berries (16) — HOLD_EFFECT_RESIST_BERRY, the exact same
    #    generic dispatch Occa Berry(Fire)/Chilan Berry(Normal) already use (those
    #    two remain inline-only in item_test.gd, per the NOTE above — not migrated
    #    here this session, out of scope).
    {"id": 551, "name": "Passho Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_WATER, "pocket": POCKET_BERRIES},
    {"id": 552, "name": "Wacan Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ELECTRIC, "pocket": POCKET_BERRIES},
    {"id": 553, "name": "Rindo Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GRASS, "pocket": POCKET_BERRIES},
    {"id": 554, "name": "Yache Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ICE, "pocket": POCKET_BERRIES},
    {"id": 555, "name": "Chople Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FIGHTING, "pocket": POCKET_BERRIES},
    {"id": 556, "name": "Kebia Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_POISON, "pocket": POCKET_BERRIES},
    {"id": 557, "name": "Shuca Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GROUND, "pocket": POCKET_BERRIES},
    {"id": 558, "name": "Coba Berry",     "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FLYING, "pocket": POCKET_BERRIES},
    {"id": 559, "name": "Payapa Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_PSYCHIC, "pocket": POCKET_BERRIES},
    {"id": 560, "name": "Tanga Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_BUG, "pocket": POCKET_BERRIES},
    {"id": 561, "name": "Charti Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_ROCK, "pocket": POCKET_BERRIES},
    {"id": 562, "name": "Kasib Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_GHOST, "pocket": POCKET_BERRIES},
    {"id": 563, "name": "Haban Berry",    "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_DRAGON, "pocket": POCKET_BERRIES},
    {"id": 564, "name": "Colbur Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_DARK, "pocket": POCKET_BERRIES},
    {"id": 565, "name": "Babiri Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_STEEL, "pocket": POCKET_BERRIES},
    {"id": 566, "name": "Roseli Berry",   "hold_effect": HOLD_EFFECT_RESIST_BERRY, "hold_effect_param": TYPE_FAIRY, "pocket": POCKET_BERRIES},

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
    {"id": 567, "name": "Liechi Berry",   "hold_effect": HOLD_EFFECT_ATTACK_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 568, "name": "Ganlon Berry",   "hold_effect": HOLD_EFFECT_DEFENSE_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 569, "name": "Salac Berry",    "hold_effect": HOLD_EFFECT_SPEED_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 570, "name": "Petaya Berry",   "hold_effect": HOLD_EFFECT_SP_ATTACK_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 571, "name": "Apicot Berry",   "hold_effect": HOLD_EFFECT_SP_DEFENSE_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 572, "name": "Lansat Berry",   "hold_effect": HOLD_EFFECT_CRITICAL_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 573, "name": "Starf Berry",    "hold_effect": HOLD_EFFECT_RANDOM_STAT_UP, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 574, "name": "Enigma Berry",   "hold_effect": HOLD_EFFECT_ENIGMA_BERRY, "pocket": POCKET_BERRIES},
    {"id": 575, "name": "Micle Berry",    "hold_effect": HOLD_EFFECT_MICLE_BERRY, "hold_effect_param": 4, "pocket": POCKET_BERRIES},
    {"id": 576, "name": "Custap Berry",   "hold_effect": HOLD_EFFECT_CUSTAP_BERRY, "hold_effect_param": 4, "pocket": POCKET_BERRIES},

    # ── M18d: Leppa Berry + contact-retaliation-family berries (3) — Jaboca/Rowap
    #    are NOT contact-gated despite the family resemblance to Rough Skin/Iron
    #    Barbs (a real correction found at Step 0, see item_manager.gd's own doc
    #    comment) — they trigger on ANY hit of the matching move category.
    {"id": 519, "name": "Leppa Berry",    "hold_effect": HOLD_EFFECT_RESTORE_PP, "hold_effect_param": 10, "pocket": POCKET_BERRIES},
    {"id": 577, "name": "Jaboca Berry",   "hold_effect": HOLD_EFFECT_JABOCA_BERRY, "pocket": POCKET_BERRIES},
    {"id": 578, "name": "Rowap Berry",    "hold_effect": HOLD_EFFECT_ROWAP_BERRY, "pocket": POCKET_BERRIES},

    # ── M18g: species-gated stat/crit items + Soul Dew (9) — no prior species-
    #    gate precedent existed in this codebase (confirmed at Step 0: [M17n-4]'s
    #    Multitype is a Plate-TYPE check, not a species check). Metal Powder
    #    (Defense) and Quick Powder (Speed) are NOT the same stat, confirmed via
    #    source, despite the superficial "Ditto powder pair" resemblance.
    {"id": 392, "name": "Light Ball",     "hold_effect": HOLD_EFFECT_LIGHT_BALL,
        "required_species": SPECIES_PIKACHU},
    {"id": 393, "name": "Leek",           "hold_effect": HOLD_EFFECT_LEEK,
        "required_species": SPECIES_FARFETCHD},
    {"id": 394, "name": "Thick Club",     "hold_effect": HOLD_EFFECT_THICK_CLUB,
        "required_species": SPECIES_CUBONE, "required_species2": SPECIES_MAROWAK},
    {"id": 395, "name": "Lucky Punch",    "hold_effect": HOLD_EFFECT_LUCKY_PUNCH,
        "required_species": SPECIES_CHANSEY},
    {"id": 396, "name": "Metal Powder",   "hold_effect": HOLD_EFFECT_METAL_POWDER,
        "required_species": SPECIES_DITTO},
    {"id": 397, "name": "Quick Powder",   "hold_effect": HOLD_EFFECT_QUICK_POWDER,
        "required_species": SPECIES_DITTO},
    {"id": 398, "name": "Deep Sea Scale", "hold_effect": HOLD_EFFECT_DEEP_SEA_SCALE,
        "required_species": SPECIES_CLAMPERL},
    {"id": 399, "name": "Deep Sea Tooth", "hold_effect": HOLD_EFFECT_DEEP_SEA_TOOTH,
        "required_species": SPECIES_CLAMPERL},
    {"id": 400, "name": "Soul Dew",       "hold_effect": HOLD_EFFECT_SOUL_DEW,
        "required_species": SPECIES_LATIAS, "required_species2": SPECIES_LATIOS},

    # ── M18h: EV/Power-item Speed-halving family (7) — Macho Brace has its OWN
    #    hold_effect constant (not HOLD_EFFECT_POWER_ITEM), but the actual effect
    #    is identical to the 6 Power items — source dispatches both through one
    #    shared OR'd condition. EV-doubling half confirmed permanently moot for
    #    all 7 (no EV-gain mechanism exists anywhere in this project's battle logic).
    # [M20c] ev_boost_stat matches BattlePokemon.STAT_* order (HP=0/ATK=1/
    # DEF=2/SPATK=3/SPDEF=4/SPEED=5), NOT source's raw `secondaryId` enum
    # order (which places Speed before SpAtk/SpDef) — each mapped by NAME,
    # not transcribed index-for-index from src/data/items.h:8731-8853.
    {"id": 418, "name": "Macho Brace",    "hold_effect": HOLD_EFFECT_MACHO_BRACE},
    {"id": 419, "name": "Power Weight",   "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 0},
    {"id": 420, "name": "Power Bracer",   "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 1},
    {"id": 421, "name": "Power Belt",     "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 2},
    {"id": 422, "name": "Power Lens",     "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 3},
    {"id": 423, "name": "Power Band",     "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 4},
    {"id": 424, "name": "Power Anklet",   "hold_effect": HOLD_EFFECT_POWER_ITEM, "ev_boost_stat": 5},

    # ── M18i: Status Orbs (2) — checked every end of turn (no turn-counter
    #    mechanic exists in source), NOT Unnerve-gated (POCKET_ITEMS, not
    #    POCKET_BERRIES — confirmed via IsUnnerveBlocked's own pocket check).
    {"id": 445, "name": "Flame Orb",      "hold_effect": HOLD_EFFECT_FLAME_ORB},
    {"id": 446, "name": "Toxic Orb",      "hold_effect": HOLD_EFFECT_TOXIC_ORB},

    # ── M18j: Power/accuracy flat-modifier misc (7) — Expert Belt is NOT the
    #    same pipeline stage as Muscle Band/Wise Glasses despite the plan's
    #    "power items" grouping (see item_manager.gd's own doc comments).
    #    Expert Belt's hold_effect_param=20 is stored for data fidelity with
    #    source but NOT actually read (the dispatch hardcodes x1.2).
    {"id": 475, "name": "Muscle Band",    "hold_effect": HOLD_EFFECT_MUSCLE_BAND, "hold_effect_param": 10},
    {"id": 476, "name": "Wise Glasses",   "hold_effect": HOLD_EFFECT_WISE_GLASSES, "hold_effect_param": 10},
    {"id": 477, "name": "Expert Belt",    "hold_effect": HOLD_EFFECT_EXPERT_BELT, "hold_effect_param": 20},
    {"id": 474, "name": "Wide Lens",      "hold_effect": HOLD_EFFECT_WIDE_LENS, "hold_effect_param": 10},
    {"id": 482, "name": "Zoom Lens",      "hold_effect": HOLD_EFFECT_ZOOM_LENS, "hold_effect_param": 20},
    {"id": 459, "name": "Bright Powder",  "hold_effect": HOLD_EFFECT_EVASION_UP, "hold_effect_param": 10},
    {"id": 405, "name": "Lax Incense",    "hold_effect": HOLD_EFFECT_EVASION_UP, "hold_effect_param": 10},

    # ── M18k: Flinch-on-hit items (2) — genuinely identical, verified independently
    #    despite the project's now-standing "never assume symmetry" discipline.
    {"id": 465, "name": "King's Rock",    "hold_effect": HOLD_EFFECT_FLINCH, "hold_effect_param": 10},
    {"id": 493, "name": "Razor Fang",     "hold_effect": HOLD_EFFECT_FLINCH, "hold_effect_param": 10},

    # ── M18n: Forced-switch items (2) — genuinely different mechanics (Red Card
    #    forces the ATTACKER out, Eject Button forces the HOLDER out), despite
    #    being grouped together as "forced-switch items."
    {"id": 498, "name": "Red Card",       "hold_effect": HOLD_EFFECT_RED_CARD, "hold_effect_param": 0},
    {"id": 501, "name": "Eject Button",   "hold_effect": HOLD_EFFECT_EJECT_BUTTON, "hold_effect_param": 0},

    # ── M18o: Survive-lethal-hit items (2) — Focus Band (probabilistic, no HP
    #    gate, NOT consumed) and Focus Sash (full-HP-gated, unconditional given
    #    that, SINGLE-USE) are genuinely different trigger shapes despite the
    #    similar name.
    {"id": 469, "name": "Focus Band",     "hold_effect": HOLD_EFFECT_FOCUS_BAND, "hold_effect_param": 10},
    {"id": 481, "name": "Focus Sash",     "hold_effect": HOLD_EFFECT_FOCUS_SASH, "hold_effect_param": 0},

    # ── M18q: Big Root (+30% move-drain healing) / Shell Bell (heals 1/8 of
    #    final damage dealt) — unrelated mechanics sharing this tier only for
    #    scheduling efficiency.
    {"id": 491, "name": "Big Root",       "hold_effect": HOLD_EFFECT_BIG_ROOT, "hold_effect_param": 30},
    {"id": 473, "name": "Shell Bell",     "hold_effect": HOLD_EFFECT_SHELL_BELL, "hold_effect_param": 8},

    # ── M18r: Standalone reuses (7) — 7 different existing mechanisms, grouped only
    #    for scheduling convenience. None of the 7 set a holdEffectParam in source
    #    (confirmed individually, not assumed) -- every effect magnitude is a fixed
    #    constant (8 turns, 1/16 vs 1/8, +2/-1 stage), not itemized per-item.
    {"id": 480, "name": "Power Herb",     "hold_effect": HOLD_EFFECT_POWER_HERB},
    {"id": 478, "name": "Light Clay",     "hold_effect": HOLD_EFFECT_LIGHT_CLAY},
    {"id": 487, "name": "Black Sludge",   "hold_effect": HOLD_EFFECT_BLACK_SLUDGE},
    {"id": 511, "name": "Blunder Policy", "hold_effect": HOLD_EFFECT_BLUNDER_POLICY},
    {"id": 512, "name": "Room Service",   "hold_effect": HOLD_EFFECT_ROOM_SERVICE},
    {"id": 490, "name": "Shed Shell",     "hold_effect": HOLD_EFFECT_SHED_SHELL},
    {"id": 504, "name": "Safety Goggles", "hold_effect": HOLD_EFFECT_SAFETY_GOGGLES},

    # ── M18s: Eviolite + Assault Vest (2) — both live in CalcDefenseStat, the SAME
    #    function Deep Sea Scale/Metal Powder (M18g) already occupy. No
    #    hold_effect_param needed -- both are fixed 1.5x, no per-item magnitude.
    {"id": 494, "name": "Eviolite",       "hold_effect": HOLD_EFFECT_EVIOLITE},
    {"id": 503, "name": "Assault Vest",   "hold_effect": HOLD_EFFECT_ASSAULT_VEST},

    # ── M18u: Berserk Gene + Metronome item (2) — unrelated mechanics sharing this
    #    tier only for scheduling efficiency. Metronome's hold_effect_param=20
    #    confirmed individually via src/data/items.h (not assumed from the plan).
    {"id": 798, "name": "Berserk Gene",   "hold_effect": HOLD_EFFECT_BERSERK_GENE},
    {"id": 483, "name": "Metronome",      "hold_effect": HOLD_EFFECT_METRONOME, "hold_effect_param": 20},

    # ── M18w: Red Orb / Blue Orb (2) — share the exact same HOLD_EFFECT_PRIMAL_ORB
    #    value in source; species-differentiated via required_species (the SAME
    #    per-item species gate M18g's Light Ball/Thick Club/etc. already use), NOT
    #    a per-item holdEffect split.
    {"id": 290, "name": "Red Orb",        "hold_effect": HOLD_EFFECT_PRIMAL_ORB,
        "required_species": SPECIES_GROUDON},
    {"id": 291, "name": "Blue Orb",       "hold_effect": HOLD_EFFECT_PRIMAL_ORB,
        "required_species": SPECIES_KYOGRE},

    # ── M18m: Stat-change-reactive consumed items (4) — despite the tier's own
    #    grouping, these are NOT all the same trigger shape (verified individually).
    #    No hold_effect_param needed for any of the 4.
    {"id": 502, "name": "Weakness Policy", "hold_effect": HOLD_EFFECT_WEAKNESS_POLICY},
    {"id": 460, "name": "White Herb",      "hold_effect": HOLD_EFFECT_WHITE_HERB},
    {"id": 509, "name": "Eject Pack",      "hold_effect": HOLD_EFFECT_EJECT_PACK},
    {"id": 769, "name": "Mirror Herb",     "hold_effect": HOLD_EFFECT_MIRROR_HERB},

    # ── M18p: Contact-reactive damage family (4) — Protective Pads and Punching
    #    Glove sit at two different levels of the same source function pair
    #    despite the "contact-reactive family" grouping (see item_manager.gd's
    #    own doc comment for the full citation). No hold_effect_param needed
    #    for any of the 4.
    {"id": 496, "name": "Rocky Helmet",     "hold_effect": HOLD_EFFECT_ROCKY_HELMET},
    {"id": 489, "name": "Sticky Barb",      "hold_effect": HOLD_EFFECT_STICKY_BARB},
    {"id": 507, "name": "Protective Pads",  "hold_effect": HOLD_EFFECT_PROTECTIVE_PADS},
    {"id": 760, "name": "Punching Glove",   "hold_effect": HOLD_EFFECT_PUNCHING_GLOVE},

    # ── M18t: Iron Ball + Air Balloon (2) — grouped only by thematic pairing
    #    ("Iron Ball grounds, Air Balloon ungrounds"), NOT mechanical opposites
    #    on one shared toggle -- verified individually, no hold_effect_param
    #    needed for either.
    {"id": 484, "name": "Iron Ball",   "hold_effect": HOLD_EFFECT_IRON_BALL},
    {"id": 497, "name": "Air Balloon", "hold_effect": HOLD_EFFECT_AIR_BALLOON},

    # ── M18v: Mental Herb (1) -- narrowed scope confirmed: cures Disable +
    #    Encore only, of source's real 6-condition list (Infatuation/Torment/
    #    Disable/Heal Block/Encore/Taunt), since this project implements only
    #    those two. No hold_effect_param needed.
    {"id": 464, "name": "Mental Herb", "hold_effect": HOLD_EFFECT_MENTAL_HERB},

    # ── M18x: Covert Cloak (1) -- the last M18 implementation tier. Same gate
    #    as Shield Dust (the literal same source function, ability vs. item),
    #    scoped to match this project's CURRENT Shield Dust behavior exactly
    #    (a pre-existing Poison Touch gap is flagged, not silently fixed here).
    #    No hold_effect_param needed.
    {"id": 761, "name": "Covert Cloak", "hold_effect": HOLD_EFFECT_COVERT_CLOAK},

    # ── [M18-cleanup]: Legacy item pipeline migration (15) -- these items were
    #    already implemented ad hoc (M12-era and earlier), before gen_items.py/
    #    .tres/ItemRegistry existed. PURE DATA MIGRATION -- every hold_effect/
    #    hold_effect_param value below is copied unchanged from ItemManager's
    #    own existing dispatch code (item_manager.gd), not re-derived from
    #    source, per this task's own explicit "reproduce identical values"
    #    scope. No dispatch logic touched; confirmed via grep no hardcoded
    #    pre-pipeline name/ID check exists anywhere for any of these 15.
    #    Lum Berry/Sitrus Berry: confirmed via direct file check that neither
    #    had a .tres entry before this migration ([M18-patch-1]'s finding was
    #    accurate and still true) -- both are fully functional today via
    #    HOLD_EFFECT_CURE_STATUS/HOLD_EFFECT_RESTORE_PCT_HP, just never given
    #    a .tres entry until now.
    {"id": 472, "name": "Leftovers",          "hold_effect": HOLD_EFFECT_LEFTOVERS},
    {"id": 522, "name": "Lum Berry",          "hold_effect": HOLD_EFFECT_CURE_STATUS,
        "pocket": POCKET_BERRIES},
    {"id": 442, "name": "Choice Band",        "hold_effect": HOLD_EFFECT_CHOICE_BAND},
    {"id": 523, "name": "Sitrus Berry",       "hold_effect": HOLD_EFFECT_RESTORE_PCT_HP,
        "hold_effect_param": 25, "pocket": POCKET_BERRIES},
    {"id": 443, "name": "Choice Specs",       "hold_effect": HOLD_EFFECT_CHOICE_SPECS},
    {"id": 444, "name": "Choice Scarf",       "hold_effect": HOLD_EFFECT_CHOICE_SCARF},
    {"id": 447, "name": "Damp Rock",          "hold_effect": HOLD_EFFECT_DAMP_ROCK},
    {"id": 448, "name": "Heat Rock",          "hold_effect": HOLD_EFFECT_HEAT_ROCK},
    {"id": 450, "name": "Icy Rock",           "hold_effect": HOLD_EFFECT_ICY_ROCK},
    {"id": 449, "name": "Smooth Rock",        "hold_effect": HOLD_EFFECT_SMOOTH_ROCK},
    {"id": 479, "name": "Life Orb",           "hold_effect": HOLD_EFFECT_LIFE_ORB},
    {"id": 549, "name": "Chilan Berry",       "hold_effect": HOLD_EFFECT_RESIST_BERRY,
        "hold_effect_param": TYPE_NORMAL, "pocket": POCKET_BERRIES},
    {"id": 550, "name": "Occa Berry",         "hold_effect": HOLD_EFFECT_RESIST_BERRY,
        "hold_effect_param": TYPE_FIRE, "pocket": POCKET_BERRIES},
    {"id": 510, "name": "Heavy-Duty Boots",   "hold_effect": HOLD_EFFECT_HEAVY_DUTY_BOOTS},
    {"id": 513, "name": "Utility Umbrella",   "hold_effect": HOLD_EFFECT_UTILITY_UMBRELLA},

    # ── [M18.5i]: Reconsideration pass, Group B (2) -- both unblocked by
    #    [M18.5f]'s binding-move mechanic and [M18.5g]'s multi-hit mechanism
    #    respectively, deferred from those tiers per their own scope lines.
    #    No hold_effect_param needed for either.
    {"id": 488, "name": "Grip Claw",   "hold_effect": HOLD_EFFECT_GRIP_CLAW},
    {"id": 762, "name": "Loaded Dice", "hold_effect": HOLD_EFFECT_LOADED_DICE},
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
    "required_species":   0,  # M18g: species-gated items — 0 = unrestricted
    "required_species2":  0,  # M18g: matched-pair second species — 0 = none
    "ev_boost_stat":     -1,  # M20c: which stat a Power item boosts — -1 = N/A
}

# Fields to emit in .tres, in canonical order. item_id/item_name are always
# emitted (see render()); everything else is skipped when it equals its
# class default. Only hold_effect/hold_effect_param are populated for M18a —
# description/importance/not_consumed/battle_usage/fling_power/price remain
# dormant fields (confirmed unread anywhere in scripts/battle/) carried from
# ItemData's original M12 schema, left unpopulated per M18a's original "keep it
# lean" scope. `pocket` was the same story until [M18-patch-1] populated it on
# every real berry entry — the first of these dormant fields to actually be
# needed by a real mechanic (Cheek Pouch/Harvest/Cud Chew's berry gate).
FIELD_ORDER = [
    "hold_effect", "hold_effect_param",
    "description", "pocket", "importance", "not_consumed", "battle_usage",
    "fling_power", "price", "required_species", "required_species2",
    "ev_boost_stat",
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
