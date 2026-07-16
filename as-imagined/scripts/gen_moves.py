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

KNOWN NON-BUGS -- flags/fields correctly ABSENT from a move below because
their consumer mechanism is unreachable or deliberately excluded for this
project. Read this list FIRST before "fixing" one of these during a future
flag/field sweep -- each was already investigated and confirmed to have zero
current runtime effect if added. Full citations: docs/m21_5_scope.md's
"Bucket 1" section and docs/decisions.md's matching entries. This is an
index, not the reasoning itself -- do not duplicate the full writeup here.

  - dance_move (11 moves: Swords Dance/Petal Dance/Feather Dance/Teeter
    Dance/Dragon Dance/Lunar Dance/Quiver Dance/Fiery Dance/Clangorous
    Soul/Victory Dance/Aqua Step) -- zero consumers anywhere; Dancer (the
    only ability that would read it) is itself excluded from this project.
  - makes_contact on Bide(117) -- its damage path (_apply_fixed_dmg_to_
    target, shared with Counter/Mirror Coat) never reads makes_contact at
    all; no contact-reactive ability can currently fire off Bide regardless.
  - ignores_protect on Protect(182)/Detect(197)/Endure(203) -- their own
    is_protect dispatch returns unconditionally BEFORE the generic Protect-
    block gate (_is_protected_from) is ever reached.
  - bounceable on Whirlwind(18)/Roar(46) (is_roar), Disable(50)
    (is_disable), Encore(227) (is_encore), Attract(213) (is_attract), and
    Sappy Seed(685) (is_leech_seed_on_hit, a damaging-move dispatch) --
    each has its own dedicated early-return branch in _phase_move_
    execution that never reaches the generic Magic Bounce/Coat check.
  - bounceable on Spikes(191)/Toxic Spikes(390)/Stealth Rock(446) -- a
    genuinely different, PRE-EXISTING known limitation (not unreachable,
    just unbuilt): hazard-bounce needs a side-wide dispatch rework,
    flagged since [M17n-9] for a future tier, not silently dropped.
  - ignores_substitute on Haze(114)/Destiny Bond(194)/Heal Bell(215) --
    each dispatches purely against the whole field/self, never reading
    defender.substitute_hp at all.

All 10 of the above were verified with a REAL runtime-behavior test in
scenes/battle/bucket1_behavior_test.gd before this list was written (that
file also proves the 10 flags Bucket 1 DID fix each have a real, working
consumer) -- this index is for the fields that were checked and correctly
left alone, so a future sweep doesn't re-discover and re-investigate them.
"""

import os
import pathlib

# ── Target constants (MoveData.target) — only TARGET_ALL_BATTLERS is ever
# actually set by a move entry so far (Perish Song, the first move needing
# it); matches MoveData.TARGET_ALL_BATTLERS's own value exactly.
TARGET_ALL_BATTLERS = 14

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
SE_THROAT_CHOP = 10  # [Bucket 4 cheapest singles] — see move_data.gd's own doc comment
SE_EERIE_SPELL = 11  # [Bucket 4 cheapest singles] — see move_data.gd's own doc comment
SE_RANDOM_STATUS = 12  # [M19-random-status-choice] — see move_data.gd's own doc comment
SE_PREVENT_ESCAPE = 13  # [M19f] Spirit Shackle — see move_data.gd's own doc comment
SE_TRAP_BOTH = 14  # [M19f] Jaw Lock — see move_data.gd's own doc comment

# ── Protect-method constants (BattlePokemon.PROTECT_METHOD_* values) — for
#    protect_method ([M19c]) ─────────────────────────────────────────────────
PROTECT_METHOD_SPIKY_SHIELD   = 1
PROTECT_METHOD_BANEFUL_BUNKER = 2
PROTECT_METHOD_BURNING_BULWARK = 3
PROTECT_METHOD_OBSTRUCT       = 4
PROTECT_METHOD_SILK_TRAP      = 5
PROTECT_METHOD_WIDE_GUARD     = 6
PROTECT_METHOD_QUICK_GUARD    = 7
PROTECT_METHOD_ENDURE         = 8  # [D4 CHEAP bundle]

# ── Status constants (BattlePokemon.STATUS_* values) — for random_status_pool ─
STATUS_BURN      = 1
STATUS_FREEZE    = 2
STATUS_PARALYSIS = 3
STATUS_POISON    = 4
STATUS_TOXIC     = 5
STATUS_SLEEP     = 6

# ── Double-power-on-status argument sentinels (MoveData.STATUS_ARG_* values) ─
# double_power_status_arg is either a real STATUS_* value above (specific
# status, e.g. Smelling Salts/paralysis), or one of these two sentinels
# (never a valid BattlePokemon.STATUS_* value, both negative and distinct
# from -1's "N/A" default) — see move_data.gd's own doc comment.
STATUS_ARG_POISON_ANY = -2  # Venoshock/Barb Barrage: POISON or TOXIC
STATUS_ARG_ANY        = -3  # Hex/Infernal Parade: any non-volatile status

# ── Semi-invulnerable state constants (MoveData.SEMI_INV_* values) ───────────
SEMI_INV_NONE        = 0
SEMI_INV_UNDERGROUND = 1  # Dig
SEMI_INV_ON_AIR      = 2  # Fly, Bounce
SEMI_INV_UNDERWATER  = 3  # Dive
SEMI_INV_VANISH      = 4  # [M19-break-protect] Shadow Force, Phantom Force

# ── Stat stage index constants (BattlePokemon.STAGE_* values) ────────────────
STAGE_ATK      = 0
STAGE_DEF      = 1
STAGE_SPATK    = 2
STAGE_SPDEF    = 3
STAGE_SPEED    = 4
STAGE_ACCURACY = 5
STAGE_EVASION  = 6

# ── Weather constants (DamageCalculator.WEATHER_* values) — for
#    weather_heal_boost_type ([M19e]) / weather_type ([D1]) ──────────────────
WEATHER_RAIN      = 1
WEATHER_SUN       = 2
WEATHER_SANDSTORM = 3
WEATHER_HAIL      = 4

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
BAN_SKETCH        = 1 << 12  # matches MoveData.BAN_SKETCH (Struggle's own ban set)

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
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 30, "double_power_on_minimized": True,},

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

    # [NEW ITEM A] is_spread=True: real source .target=TARGET_FOES_AND_ALLY
    # (config-gated B_UPDATED_MOVE_DATA>=GEN_4, true here) — was missing
    # entirely since this move predates the M14a/M14b spread infrastructure.
    # [NEW ITEM C] target_includes_ally=True: the ally-hit half, closing the
    # gap the NEW ITEM A entry above originally deferred. See
    # docs/m21_recon.md's "Full-Roster Spread/Status-Target Audit" section.
    {"id":  57, "name": "Surf",
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15,
     "damages_underwater": True, "is_spread": True, "target_includes_ally": True},

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

    # [NEW ITEM A] is_spread=True: real source .target=TARGET_BOTH, was
    # missing entirely. See docs/m21_recon.md's "Full-Roster Spread/
    # Status-Target Audit" section.
    {"id": 129, "name": "Swift",
     "type": TYPE_NORMAL, "category": SPEC, "power": 60, "accuracy": 0, "pp": 20,
     "is_spread": True},

    # Rock Slide: 30% flinch secondary
    # [NEW ITEM A] is_spread=True: real source .target=TARGET_BOTH, was
    # missing entirely.
    {"id": 157, "name": "Rock Slide",
     "type": TYPE_ROCK, "category": PHYS, "power": 75, "accuracy": 90, "pp": 10,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30, "is_spread": True},

    {"id": 332, "name": "Aerial Ace",
     "type": TYPE_FLYING, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20,
     "makes_contact": True, "slicing_move": True,},

    # ── Tier 2: stat-changing moves ───────────────────────────────────────────

    # Swords Dance: +2 Atk self (source: STAT_CHANGE_EFFECT_PLUS(STAT_ATK, 2))
    {"id":  14, "name": "Swords Dance",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True, "ignores_protect": True,},

    # Sand Attack: -1 Acc foe (source: STAT_CHANGE_EFFECT_MINUS(STAT_ACC, 1))
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    {"id":  28, "name": "Sand Attack",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 100, "pp": 15,
     "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "bounceable": True,
     "stat_change_bypasses_type_gate": True},

    # Tail Whip: -1 Def foe
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    # [NEW ITEM B] is_spread=True: real source .target=TARGET_BOTH (hits both
    # opponents in doubles) — missing since this move predates the M14a/M14b
    # spread infrastructure; see docs/m21_recon.md's "Full-Roster Spread/
    # Status-Target Audit" section.
    {"id":  39, "name": "Tail Whip",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "bounceable": True,
     "stat_change_bypasses_type_gate": True, "is_spread": True},

    # Leer: -1 Def foe
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    # [NEW ITEM B] is_spread=True: real source .target=TARGET_BOTH.
    {"id":  43, "name": "Leer",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 30,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "bounceable": True,
     "stat_change_bypasses_type_gate": True, "is_spread": True},

    # Growl: -1 Atk foe, sound_move=true (source: struct MoveInfo.soundMove)
    # bounceable: magicCoatAffected=TRUE in source (M17n-9, Magic Bounce).
    # [NEW ITEM B] is_spread=True: real source .target=TARGET_BOTH.
    {"id":  45, "name": "Growl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 40,
     "sound_move": True, "bounceable": True,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True, "is_spread": True, "ignores_substitute": True,},

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
    # [NEW ITEM A] is_spread=True: real source .target=TARGET_BOTH, was
    # missing entirely — confirmed the two-turn charge is target-agnostic
    # (no targeting resolution during the charge turn) and the release
    # turn falls through the ordinary spread dispatch cleanly.
    {"id":  13, "name": "Razor Wind",
     "type": TYPE_NORMAL, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "critical_hit_stage": 1, "two_turn": True, "is_spread": True,
     "ban_flags": BAN_SLEEP_TALK},

    # Solar Beam(76)   L2052  Grass/Spec/120/100/10, two-turn
    #   is_solar_beam=True: fires immediately in harsh sun (M15 Task5).
    #   Source: .effect=EFFECT_SOLAR_BEAM; CanTwoTurnMoveFireThisTurn returns TRUE when sun.
    {"id":  76, "name": "Solar Beam",
     "type": TYPE_GRASS, "category": SPEC, "power": 120, "accuracy": 100, "pp": 10,
     "two_turn": True, "is_solar_beam": True,
     "ban_flags": BAN_SLEEP_TALK},

    # Sky Attack(143)  L3887  Flying/Phys/140/90/5, two-turn, crit=1, 30% flinch
    #   Source: .effect=EFFECT_TWO_TURNS_ATTACK; critStage=1; 30% flinch secondary (GEN_3+)
    {"id": 143, "name": "Sky Attack",
     "type": TYPE_FLYING, "category": PHYS, "power": 140, "accuracy": 90, "pp": 5,
     "critical_hit_stage": 1, "two_turn": True,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30,
     "ban_flags": BAN_SLEEP_TALK},

    # Skull Bash(130) L3556  Normal/Phys/130/100/10, contact, two-turn
    #   Source: .effect=EFFECT_TWO_TURNS_ATTACK; additionalEffects {MOVE_EFFECT_STAT_PLUS,
    #   .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE} (M15 Task5).
    #   Power=130 (B_UPDATED>=GEN_2).
    {"id": 130, "name": "Skull Bash",
     "type": TYPE_NORMAL, "category": PHYS, "power": 130, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "charge_turn_defense_boost": 1,
     "ban_flags": BAN_SLEEP_TALK},

    # ── Tier 3: semi-invulnerable two-turn moves ──────────────────────────────
    #
    # Fly(19)          L522   Flying/Phys/90/95/15, contact, two-turn, STATE_ON_AIR
    #   Source: .effect=EFFECT_SEMI_INVULNERABLE; .argument.twoTurnAttack.status=STATE_ON_AIR
    #   Power=90 (B_UPDATED>=GEN_4); gravityBanned.
    {"id":  19, "name": "Fly",
     "type": TYPE_FLYING, "category": PHYS, "power": 90, "accuracy": 95, "pp": 15,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_ON_AIR,
     # [D4 Bundle 4] assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6) — every
     # two-turn move in this same family carries the identical flag.
     "ban_flags": (BAN_ASSIST | BAN_SLEEP_TALK),},

    # Dig(91)          L2441  Ground/Phys/80/100/10, contact, two-turn, STATE_UNDERGROUND
    #   Source: .effect=EFFECT_SEMI_INVULNERABLE; .argument.twoTurnAttack.status=STATE_UNDERGROUND
    #   Power=80 (B_UPDATED>=GEN_4).
    {"id":  91, "name": "Dig",
     "type": TYPE_GROUND, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_UNDERGROUND,
     # [D4 Bundle 4] assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6).
     "ban_flags": (BAN_ASSIST | BAN_SLEEP_TALK),},

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
     "drain_percent": 50, "healing_move": True,},

    # Mega Drain(72)   L1943  Grass/Spec/40/100/15, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50; pp=15 (B_UPDATED>=GEN_4)
    {"id":  72, "name": "Mega Drain",
     "type": TYPE_GRASS, "category": SPEC, "power": 40, "accuracy": 100, "pp": 15,
     "drain_percent": 50, "healing_move": True,},

    # Giga Drain(202)  L5530  Grass/Spec/75/100/10, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50
    #   Power=75 (B_UPDATED>=GEN_5); pp=10 (B_UPDATED>=GEN_4).
    {"id": 202, "name": "Giga Drain",
     "type": TYPE_GRASS, "category": SPEC, "power": 75, "accuracy": 100, "pp": 10,
     "drain_percent": 50, "healing_move": True,},

    # Drain Punch(409) L11016 Fighting/Phys/75/100/10, contact, punching, 50% drain
    #   Source: .effect=EFFECT_ABSORB; .argument.absorbPercentage=50
    #   Power=75 (B_UPDATED>=GEN_5); pp=10 (B_UPDATED>=GEN_5); makesContact, punchingMove.
    {"id": 409, "name": "Drain Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 75, "accuracy": 100, "pp": 10,
     "makes_contact": True, "punching_move": True, "drain_percent": 50, "healing_move": True,},

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
    # [NEW ITEM A] is_spread=True: real source .target=TARGET_FOES_AND_ALLY,
    # was missing entirely.
    # [NEW ITEM C] target_includes_ally=True: the ally-hit half, closing the
    # gap the entry above originally deferred, same as Surf above.
    {"id":  89, "name": "Earthquake",
     "type": TYPE_GROUND, "category": PHYS, "power": 100, "accuracy": 100, "pp": 10,
     "damages_underground": True, "is_spread": True, "target_includes_ally": True},

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
     # [D4 Bundle 4] copycatBanned/assistBanned/meFirstBanned all TRUE — the
     # whole reflect-damage family (Counter/Mirror Coat/Metal Burst) is
     # excluded from all three call-a-different-move sources.
     "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST | BAN_ME_FIRST, "counter": True},

    # Bide(117)        L2992  Normal/Phys/0/—/10, priority=1
    #   Source: moves_info.h MOVE_BIDE: .effect=EFFECT_BIDE, .power=0,
    #   .accuracy=0 (always executes), .pp=10, .priority=1 (B_UPDATED>=GEN_4),
    #   .category=PHYS, .metronomeBanned=TRUE (Gen 5+; B_METRONOME_BIDE check)
    {"id": 117, "name": "Bide",
     "type": TYPE_NORMAL, "category": PHYS, "power": 0, "accuracy": 0, "pp": 10,
     "priority": 1,
     "ban_flags": BAN_SLEEP_TALK, "is_bide": True},

    # Metronome(118)   L3020  Normal/Status/0/—/10
    #   Source: moves_info.h MOVE_METRONOME: .effect=EFFECT_METRONOME, .pp=10,
    #   .category=STATUS, .accuracy=0 (always executes), .metronomeBanned=TRUE (self-ban)
    {"id": 118, "name": "Metronome",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     # [Mimic/Sketch] mimicBanned=TRUE added (was missing).
     "ban_flags": (BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST | BAN_MIMIC | BAN_SLEEP_TALK | BAN_ENCORE), "is_metronome": True, "ignores_protect": True,},

    # Substitute(164)  L4299  Normal/Status/0/—/10
    #   Source: moves_info.h MOVE_SUBSTITUTE: .effect=EFFECT_SUBSTITUTE, .pp=10,
    #   .category=STATUS, .metronomeBanned=TRUE
    {"id": 164, "name": "Substitute",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
      "creates_substitute": True, "snatch_affected": True, "ignores_protect": True,},

    # Protect(182)     L4788  Normal/Status/0/—/10, priority=4
    #   Source: moves_info.h MOVE_PROTECT: .effect=EFFECT_PROTECT,
    #   .priority=4 (GEN_LATEST), .pp=10, .category=STATUS,
    #   .metronomeBanned=TRUE (confirmed in moves_info.h)
    {"id": 182, "name": "Protect",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "priority": 4,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE — the whole Protect
     # family (Protect/Detect/Endure/Spiky Shield/Baneful Bunker/Burning
     # Bulwark) carries these two flags.
     "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST, "is_protect": True},

    # Destiny Bond(194) L5092  Ghost/Status/0/—/5
    #   Source: moves_info.h MOVE_DESTINY_BOND: .effect=EFFECT_DESTINY_BOND,
    #   .type=TYPE_GHOST, .pp=5, .category=STATUS, .metronomeBanned=TRUE
    {"id": 194, "name": "Destiny Bond",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 0, "pp": 5,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST, "destiny_bond": True, "ignores_protect": True,},

    # Detect(197)      L5167  Fighting/Status/0/—/5, priority=4
    #   Source: moves_info.h MOVE_DETECT: .effect=EFFECT_PROTECT (same handler),
    #   .type=TYPE_FIGHTING, .priority=4, .pp=5, .category=STATUS,
    #   .metronomeBanned=TRUE.  Shares protect_consecutive with Protect.
    {"id": 197, "name": "Detect",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 0, "pp": 5,
     "priority": 4,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST, "is_protect": True},

    # Encore(227)      L5978  Normal/Status/100/5
    #   Source: moves_info.h MOVE_ENCORE: .effect=EFFECT_ENCORE, .accuracy=100,
    #   .pp=5 (B_UPDATED>=GEN_5), .category=STATUS, .metronomeBanned=TRUE,
    #   .encoreBanned=TRUE (can't Encore an Encored move).
    {"id": 227, "name": "Encore",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 100, "pp": 5,
     "ban_flags": BAN_ENCORE, "is_encore": True,
     "blocked_by_aroma_veil": True, "ignores_substitute": True,},

    # Mirror Coat(243) L6450  Psychic/Spec/1/100/20, priority=-5
    #   Source: moves_info.h MOVE_MIRROR_COAT: .effect=EFFECT_MIRROR_COAT,
    #   .type=TYPE_PSYCHIC, .power=1, .accuracy=100, .pp=20, .priority=-5,
    #   .category=SPEC, .metronomeBanned=TRUE (Gen 5+)
    {"id": 243, "name": "Mirror Coat",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 1, "accuracy": 100, "pp": 20,
     "priority": -5,
     # [D4 Bundle 4] assistBanned/meFirstBanned=TRUE. NOT copycatBanned — its
     # source condition is `B_UPDATED_MOVE_FLAGS <= GEN_8`, which is FALSE at
     # this project's GEN_LATEST=GEN_9 config (confirmed via direct config
     # read, not assumed from the literal-TRUE pattern every other flag here
     # uses).
     "ban_flags": BAN_METRONOME | BAN_ASSIST | BAN_ME_FIRST, "mirror_coat": True},

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
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6).
     "ban_flags": BAN_COPYCAT | BAN_ASSIST,
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
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6).
     "ban_flags": BAN_COPYCAT | BAN_ASSIST,
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
     "ignores_protect": True, "is_growth": True, "snatch_affected": True},

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
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True, "snatch_affected": True},

    # Focus Energy(116) L3008  Normal/Status/0/0/30
    #   Source: moves_info.h MOVE_FOCUS_ENERGY: .effect=EFFECT_FOCUS_ENERGY, .pp=30,
    #   .accuracy=0, .ignoresProtect=TRUE. Raises crit stage +2 (Gen3+).
    {"id": 116, "name": "Focus Energy",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "is_focus_energy": True, "snatch_affected": True},

    # Slack Off(303)  L8253  Normal/Status/0/0/5
    #   Source: moves_info.h MOVE_SLACK_OFF: .effect=EFFECT_RESTORE_HP, .pp=5 (B_UPDATED>=GEN_9),
    #   .accuracy=0, .ignoresProtect=TRUE, .healingMove=TRUE.
    {"id": 303, "name": "Slack Off",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True, "snatch_affected": True},

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
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True, "snatch_affected": True},

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
     "ignores_protect": True, "is_minimize": True, "snatch_affected": True},

    # Defense Curl(111)  L3011  Normal/Status/0/0/40, self, +1 Defense, ignoresProtect
    #   Source: moves_info.h MOVE_DEFENSE_CURL: .effect=EFFECT_DEFENSE_CURL, .accuracy=0,
    #   .pp=40, .target=TARGET_USER, .ignoresProtect=TRUE.
    #   additionalEffects {STAT_CHANGE_EFFECT_PLUS, .defense=1}.
    {"id": 111, "name": "Defense Curl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "is_defense_curl": True, "snatch_affected": True},

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
    # [NEW ITEM C] target_includes_ally=True: real source .target=
    # TARGET_FOES_AND_ALLY, already is_spread but missing the ally-hit half.
    {"id": 222, "name": "Magnitude",
     "type": TYPE_GROUND, "category": PHYS, "power": 1, "accuracy": 100, "pp": 30,
     "damages_underground": True, "is_spread": True, "is_magnitude": True,
     "target_includes_ally": True},

    # ── M16c: Tier C move effects (screens) ───────────────────────────────────

    # Light Screen(113)  L3071  Psychic/Status/0/0/30, self, ignoresProtect, halves Special dmg
    #   Source: moves_info.h MOVE_LIGHT_SCREEN: .effect=EFFECT_LIGHT_SCREEN, .accuracy=0,
    #   .pp=30, .target=TARGET_USER, .ignoresProtect=TRUE.
    {"id": 113, "name": "Light Screen",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "is_light_screen": True, "snatch_affected": True},

    # Reflect(115)  L3123  Psychic/Status/0/0/20, self, ignoresProtect, halves Physical dmg
    #   Source: moves_info.h MOVE_REFLECT: .effect=EFFECT_REFLECT, .accuracy=0, .pp=20,
    #   .target=TARGET_USER, .ignoresProtect=TRUE.
    {"id": 115, "name": "Reflect",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_reflect": True, "snatch_affected": True},

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
     "ignores_protect": True, "is_aurora_veil": True, "snatch_affected": True},

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
    # [M21.5 Bucket 3] Rapid Spin's real source additionalEffects block
    # (gated `#if B_SPEED_BUFFING_RAPID_SPIN >= GEN_8`, TRUE at this
    # project's GEN_LATEST=GEN_9 config) is `MOVE_EFFECT_STAT_PLUS, .speed=1,
    # .self=TRUE, .chance=100` -- a guaranteed self Speed+1 on every hit that
    # was never wired at all (is_rapid_spin's own dispatch only clears
    # hazards). Reuses the existing [M19-secondary-stat-on-hit] generic
    # damaging-move stat-change mechanism (stat_change_stat/self set,
    # secondary_effect left at SE_NONE) -- the exact same shape Torch Song(799)
    # already uses for its own guaranteed self SpAtk+1, zero new dispatch code.
    {"id": 229, "name": "Rapid Spin",
     "type": TYPE_NORMAL, "category": PHYS, "power": 50, "accuracy": 100, "pp": 40,
     "makes_contact": True, "is_rapid_spin": True,
     "stat_change_stat": STAGE_SPEED, "stat_change_amount": 1, "stat_change_self": True,
     "secondary_chance": 100},

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
     "ignores_protect": True, "is_conversion": True, "snatch_affected": True,},

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
     "secondary_effect": SE_WRAP, "damages_underwater": True,},
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
     "makes_contact": True, "secondary_effect": SE_WRAP,
     "ban_flags": BAN_METRONOME},
    {"id": 747, "name": "Thunder Cage",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 80, "accuracy": 90, "pp": 15,
     "secondary_effect": SE_WRAP,
     "ban_flags": BAN_METRONOME},

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
     "secondary_effect": SE_FLINCH, "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},
    # [Turn-order-splice trio, item 5] Dragon Darts: TARGET_SMART doubles-
    # redirect now implemented — see MoveData.is_dragon_darts's own doc
    # comment for the full source citation and mechanism.
    {"id": 697, "name": "Dragon Darts",
     "type": TYPE_DRAGON, "category": PHYS, "power": 50, "accuracy": 100, "pp": 10,
     "strike_count": 2, "is_dragon_darts": True},
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
     "always_critical_hit": True,
     "ban_flags": BAN_METRONOME},
    {"id": 793, "name": "Triple Dive",
     "type": TYPE_WATER, "category": PHYS, "power": 30, "accuracy": 95, "pp": 10,
     "makes_contact": True, "strike_count": 3},
    {"id": 814, "name": "Twin Beam",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 40, "accuracy": 100, "pp": 10,
     "strike_count": 2,
     "ban_flags": BAN_METRONOME},
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
     "makes_contact": True, "is_heat_crash_power": True, "double_power_on_minimized": True,},

    # Heat Crash(535) L14224  Fire/Phys/1/100/10, contact
    #   Source: moves_info.h MOVE_HEAT_CRASH: .effect=EFFECT_HEAT_CRASH, .power=1,
    #   .accuracy=100, .makesContact=TRUE.
    {"id": 535, "name": "Heat Crash",
     "type": TYPE_FIRE, "category": PHYS, "power": 1, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_heat_crash_power": True, "double_power_on_minimized": True,},

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
     "is_return_power": True,
     "ban_flags": BAN_METRONOME},

    # Veevee Volley(688) L18162  Normal/Phys/1/0(always hits)/20, contact
    #   Source: moves_info.h MOVE_VEEVEE_VOLLEY: .effect=EFFECT_RETURN (same
    #   formula as Return/Pika Papow), .power=1, .accuracy=0, .makesContact=TRUE.
    {"id": 688, "name": "Veevee Volley",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 0, "pp": 20,
     "makes_contact": True, "is_return_power": True,
     "ban_flags": BAN_METRONOME},

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
     "makes_contact": True, "punching_move": True,},

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
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 0, "pp": 20, "makes_contact": True,},

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
     "sound_move": True, "is_spread": True, "ignores_substitute": True,},

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
    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 572, "name": "Petal Blizzard",
     "type": TYPE_GRASS, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "is_spread": True, "target_includes_ally": True},

    # Disarming Voice(574)  Fairy/Spec/40/0/15, sound_move, is_spread
    {"id": 574, "name": "Disarming Voice",
     "type": TYPE_FAIRY, "category": SPEC, "power": 40, "accuracy": 0, "pp": 15,
     "sound_move": True, "is_spread": True, "ignores_substitute": True,},

    # Fairy Wind(584)  Fairy/Spec/40/100/30, no flags
    {"id": 584, "name": "Fairy Wind",
     "type": TYPE_FAIRY, "category": SPEC, "power": 40, "accuracy": 100, "pp": 30},

    # Boomburst(586)  Normal/Spec/140/100/10, sound_move, is_spread
    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 586, "name": "Boomburst",
     "type": TYPE_NORMAL, "category": SPEC, "power": 140, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True, "target_includes_ally": True, "ignores_substitute": True,},

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
     "is_spread": True, "pulse_move": True,
     "ban_flags": BAN_METRONOME},

    # Precipice Blades(619)  Ground/Phys/120/85/10, is_spread
    {"id": 619, "name": "Precipice Blades",
     "type": TYPE_GROUND, "category": PHYS, "power": 120, "accuracy": 85, "pp": 10,
     "is_spread": True,
     "ban_flags": BAN_METRONOME},

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
    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 656, "name": "Brutal Swing",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_spread": True, "target_includes_ally": True},

    # Accelerock(663)  Rock/Phys/40/100/20, makes_contact, priority
    {"id": 663, "name": "Accelerock",
     "type": TYPE_ROCK, "category": PHYS, "power": 40, "accuracy": 100, "pp": 20,
     "makes_contact": True, "priority": 1},

    # Branch Poke(713)  Grass/Phys/40/100/40, makes_contact
    {"id": 713, "name": "Branch Poke",
     "type": TYPE_GRASS, "category": PHYS, "power": 40, "accuracy": 100, "pp": 40,
     "makes_contact": True,
     "ban_flags": BAN_METRONOME},

    # Overdrive(714)  Electric/Spec/80/100/10, sound_move, is_spread
    {"id": 714, "name": "Overdrive",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True,
     "ban_flags": BAN_METRONOME, "ignores_substitute": True,},

    # False Surrender(721)  Dark/Phys/80/0/10, makes_contact
    {"id": 721, "name": "False Surrender",
     "type": TYPE_DARK, "category": PHYS, "power": 80, "accuracy": 0, "pp": 10,
     "makes_contact": True,
     "ban_flags": BAN_METRONOME},

    # Wicked Blow(745)  Dark/Phys/75/100/5, makes_contact, punching_move, always_critical_hit
    #   alwaysCriticalHit=TRUE -> always_critical_hit
    {"id": 745, "name": "Wicked Blow",
     "type": TYPE_DARK, "category": PHYS, "power": 75, "accuracy": 100, "pp": 5,
     "makes_contact": True, "punching_move": True, "always_critical_hit": True,
     "ban_flags": BAN_METRONOME},

    # Glacial Lance(752)  Ice/Phys/120/100/5, is_spread
    {"id": 752, "name": "Glacial Lance",
     "type": TYPE_ICE, "category": PHYS, "power": 120, "accuracy": 100, "pp": 5,
     "is_spread": True,
     "ban_flags": BAN_METRONOME},

    # Astral Barrage(753)  Ghost/Spec/120/100/5, is_spread
    {"id": 753, "name": "Astral Barrage",
     "type": TYPE_GHOST, "category": SPEC, "power": 120, "accuracy": 100, "pp": 5,
     "is_spread": True,
     "ban_flags": BAN_METRONOME},

    # Jet Punch(785)  Water/Phys/60/100/15, makes_contact, punching_move, priority
    {"id": 785, "name": "Jet Punch",
     "type": TYPE_WATER, "category": PHYS, "power": 60, "accuracy": 100, "pp": 15,
     "makes_contact": True, "punching_move": True, "priority": 1,
     "ban_flags": BAN_METRONOME},

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
     "makes_contact": True,
     "ban_flags": BAN_METRONOME, "ignores_protect": True,},

    # Aqua Cutter(821)  Water/Phys/70/100/20, slicing_move, critical_hit_stage
    {"id": 821, "name": "Aqua Cutter",
     "type": TYPE_WATER, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "slicing_move": True, "critical_hit_stage": 1},

    # ── Bucket 2: reuses a single existing secondary mechanism (M19-bucket2) ──

    {"id": 7, "name": "Fire Punch",
     "type": TYPE_FIRE, "category": PHYS, "power": 75, "accuracy": 100, "pp": 15,
     "makes_contact": True, "punching_move": True, "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id": 8, "name": "Ice Punch",
     "type": TYPE_ICE, "category": PHYS, "power": 75, "accuracy": 100, "pp": 15,
     "makes_contact": True, "punching_move": True, "secondary_effect": SE_FREEZE, "secondary_chance": 10},

    {"id": 9, "name": "Thunder Punch",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 75, "accuracy": 100, "pp": 15,
     "makes_contact": True, "punching_move": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 10},

    {"id": 27, "name": "Rolling Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 60, "accuracy": 85, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 29, "name": "Headbutt",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 40, "name": "Poison Sting",
     "type": TYPE_POISON, "category": PHYS, "power": 15, "accuracy": 100, "pp": 35,
     "secondary_effect": SE_POISON, "secondary_chance": 30},

    {"id": 44, "name": "Bite",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "biting_move": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 47, "name": "Sing",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 55, "pp": 15,
     "sound_move": True, "bounceable": True, "secondary_effect": SE_SLEEP, "secondary_chance": 0, "ignores_substitute": True,},

    {"id": 48, "name": "Supersonic",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 55, "pp": 20,
     "sound_move": True, "bounceable": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 0, "ignores_substitute": True,},

    {"id": 59, "name": "Blizzard",
     "type": TYPE_ICE, "category": SPEC, "power": 110, "accuracy": 70, "pp": 5,
     "is_spread": True, "secondary_effect": SE_FREEZE, "secondary_chance": 10},

    {"id": 66, "name": "Submission",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 80, "accuracy": 80, "pp": 20,
     "makes_contact": True, "recoil_percent": 25},

    {"id": 77, "name": "Poison Powder",
     "type": TYPE_POISON, "category": STAT, "power": 0, "accuracy": 75, "pp": 35,
     "powder_move": True, "bounceable": True, "secondary_effect": SE_POISON, "secondary_chance": 0},

    {"id": 78, "name": "Stun Spore",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 75, "pp": 30,
     "powder_move": True, "bounceable": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 0},

    {"id": 81, "name": "String Shot",
     "type": TYPE_BUG, "category": STAT, "power": 0, "accuracy": 95, "pp": 40,
     "is_spread": True, "bounceable": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -2},

    {"id": 85, "name": "Thunderbolt",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 10},

    {"id": 93, "name": "Confusion",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 50, "accuracy": 100, "pp": 25,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 10},

    {"id": 95, "name": "Hypnosis",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 60, "pp": 20,
     "bounceable": True, "secondary_effect": SE_SLEEP, "secondary_chance": 0},

    {"id": 96, "name": "Meditate",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1, "stat_change_self": True, "snatch_affected": True},

    {"id": 97, "name": "Agility",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 103, "name": "Screech",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 85, "pp": 40,
     "sound_move": True, "bounceable": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -2,
     "stat_change_bypasses_type_gate": True, "ignores_substitute": True,},

    {"id": 104, "name": "Double Team",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "stat_change_stat": STAGE_EVASION, "stat_change_amount": 1, "stat_change_self": True, "snatch_affected": True},

    {"id": 106, "name": "Harden",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1, "stat_change_self": True, "snatch_affected": True},

    {"id": 108, "name": "Smokescreen",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "bounceable": True, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True},

    {"id": 110, "name": "Withdraw",
     "type": TYPE_WATER, "category": STAT, "power": 0, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1, "stat_change_self": True, "snatch_affected": True},

    {"id": 112, "name": "Barrier",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 122, "name": "Lick",
     "type": TYPE_GHOST, "category": PHYS, "power": 30, "accuracy": 100, "pp": 30,
     "makes_contact": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30},

    {"id": 123, "name": "Smog",
     "type": TYPE_POISON, "category": SPEC, "power": 30, "accuracy": 70, "pp": 20,
     "secondary_effect": SE_POISON, "secondary_chance": 40},

    {"id": 124, "name": "Sludge",
     "type": TYPE_POISON, "category": SPEC, "power": 65, "accuracy": 100, "pp": 20,
     "secondary_effect": SE_POISON, "secondary_chance": 30},

    {"id": 125, "name": "Bone Club",
     "type": TYPE_GROUND, "category": PHYS, "power": 65, "accuracy": 85, "pp": 20,
     "secondary_effect": SE_FLINCH, "secondary_chance": 10},

    {"id": 126, "name": "Fire Blast",
     "type": TYPE_FIRE, "category": SPEC, "power": 110, "accuracy": 85, "pp": 5,
     "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id": 127, "name": "Waterfall",
     "type": TYPE_WATER, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20},

    {"id": 133, "name": "Amnesia",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 134, "name": "Kinesis",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 80, "pp": 15,
     "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True, "bounceable": True,},

    {"id": 137, "name": "Glare",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 30,
     "bounceable": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 0},

    {"id": 139, "name": "Poison Gas",
     "type": TYPE_POISON, "category": STAT, "power": 0, "accuracy": 90, "pp": 40,
     "is_spread": True, "bounceable": True, "secondary_effect": SE_POISON, "secondary_chance": 0},

    {"id": 141, "name": "Leech Life",
     "type": TYPE_BUG, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "drain_percent": 50, "healing_move": True},

    {"id": 142, "name": "Lovely Kiss",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 75, "pp": 10,
     "bounceable": True, "secondary_effect": SE_SLEEP, "secondary_chance": 0},

    {"id": 146, "name": "Dizzy Punch",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 10,
     "makes_contact": True, "punching_move": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 20},

    {"id": 147, "name": "Spore",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 100, "pp": 15,
     "powder_move": True, "bounceable": True, "secondary_effect": SE_SLEEP, "secondary_chance": 0},

    {"id": 148, "name": "Flash",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "bounceable": True, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True},

    {"id": 151, "name": "Acid Armor",
     "type": TYPE_POISON, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 158, "name": "Hyper Fang",
     "type": TYPE_NORMAL, "category": PHYS, "power": 80, "accuracy": 90, "pp": 15,
     "makes_contact": True, "biting_move": True, "secondary_effect": SE_FLINCH, "secondary_chance": 10},

    {"id": 159, "name": "Sharpen",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1, "stat_change_self": True, "snatch_affected": True},

    {"id": 178, "name": "Cotton Spore",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 100, "pp": 40,
     "powder_move": True, "is_spread": True, "bounceable": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -2},

    {"id": 181, "name": "Powder Snow",
     "type": TYPE_ICE, "category": SPEC, "power": 40, "accuracy": 100, "pp": 25,
     "is_spread": True, "secondary_effect": SE_FREEZE, "secondary_chance": 10},

    {"id": 184, "name": "Scary Face",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 10,
     "bounceable": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -2,
     "stat_change_bypasses_type_gate": True},

    {"id": 186, "name": "Sweet Kiss",
     "type": TYPE_FAIRY, "category": STAT, "power": 0, "accuracy": 75, "pp": 10,
     "bounceable": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 0},

    {"id": 188, "name": "Sludge Bomb",
     "type": TYPE_POISON, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "ballistic_move": True, "secondary_effect": SE_POISON, "secondary_chance": 30},

    {"id": 192, "name": "Zap Cannon",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 120, "accuracy": 50, "pp": 5,
     "ballistic_move": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 100},

    {"id": 204, "name": "Charm",
     "type": TYPE_FAIRY, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "bounceable": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -2},

    {"id": 209, "name": "Spark",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 65, "accuracy": 100, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30},

    {"id": 221, "name": "Sacred Fire",
     "type": TYPE_FIRE, "category": PHYS, "power": 100, "accuracy": 95, "pp": 5,
     "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 50},

    {"id": 223, "name": "Dynamic Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 100, "accuracy": 50, "pp": 5,
     "makes_contact": True, "punching_move": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 100},

    {"id": 225, "name": "Dragon Breath",
     "type": TYPE_DRAGON, "category": SPEC, "power": 60, "accuracy": 100, "pp": 20,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 30},

    {"id": 230, "name": "Sweet Scent",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "is_spread": True, "bounceable": True, "stat_change_stat": STAGE_EVASION, "stat_change_amount": -2,
     "stat_change_bypasses_type_gate": True},

    {"id": 239, "name": "Twister",
     "type": TYPE_DRAGON, "category": SPEC, "power": 40, "accuracy": 100, "pp": 20,
     "is_spread": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20, "damages_airborne": True},

    {"id": 257, "name": "Heat Wave",
     "type": TYPE_FIRE, "category": SPEC, "power": 95, "accuracy": 90, "pp": 10,
     "is_spread": True, "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id": 291, "name": "Dive",
     "type": TYPE_WATER, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_UNDERWATER,
     # [D4 Bundle 4] assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6).
     "ban_flags": (BAN_ASSIST | BAN_SLEEP_TALK),},

    {"id": 294, "name": "Tail Glow",
     "type": TYPE_BUG, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 3, "stat_change_self": True, "snatch_affected": True},

    {"id": 297, "name": "Feather Dance",
     "type": TYPE_FLYING, "category": STAT, "power": 0, "accuracy": 100, "pp": 15,
     "bounceable": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -2},

    # [NEW ITEM B/C] Real source .target=TARGET_FOES_AND_ALLY (confuses
    # every OTHER battler in doubles, opponents AND the user's own ally) —
    # target_includes_ally mirrors Self-Destruct/Explosion's own [M21] fix;
    # is_spread alone (opponents only) was already set but structurally
    # inert until the new status-move spread dispatch below existed. See
    # docs/m21_recon.md's "Full-Roster Spread/Status-Target Audit" section.
    {"id": 298, "name": "Teeter Dance",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "is_spread": True, "target_includes_ally": True,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 0},

    {"id": 299, "name": "Blaze Kick",
     "type": TYPE_FIRE, "category": PHYS, "power": 85, "accuracy": 90, "pp": 10,
     "makes_contact": True, "critical_hit_stage": 1, "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id": 302, "name": "Needle Arm",
     "type": TYPE_GRASS, "category": PHYS, "power": 60, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 305, "name": "Poison Fang",
     "type": TYPE_POISON, "category": PHYS, "power": 50, "accuracy": 100, "pp": 15,
     "makes_contact": True, "biting_move": True, "secondary_effect": SE_TOXIC, "secondary_chance": 50},

    {"id": 310, "name": "Astonish",
     "type": TYPE_GHOST, "category": PHYS, "power": 30, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 313, "name": "Fake Tears",
     "type": TYPE_DARK, "category": STAT, "power": 0, "accuracy": 100, "pp": 20,
     "bounceable": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -2},

    {"id": 319, "name": "Metal Sound",
     "type": TYPE_STEEL, "category": STAT, "power": 0, "accuracy": 85, "pp": 40,
     "sound_move": True, "bounceable": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -2, "ignores_substitute": True,},

    {"id": 320, "name": "Grass Whistle",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 55, "pp": 15,
     "sound_move": True, "bounceable": True, "secondary_effect": SE_SLEEP, "secondary_chance": 0, "ignores_substitute": True,},

    {"id": 324, "name": "Signal Beam",
     "type": TYPE_BUG, "category": SPEC, "power": 75, "accuracy": 100, "pp": 15,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 10},

    {"id": 326, "name": "Extrasensory",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 20,
     "secondary_effect": SE_FLINCH, "secondary_chance": 10},

    {"id": 334, "name": "Iron Defense",
     "type": TYPE_STEEL, "category": STAT, "power": 0, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 340, "name": "Bounce",
     "type": TYPE_FLYING, "category": PHYS, "power": 85, "accuracy": 85, "pp": 5,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_ON_AIR, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30,
     # [D4 Bundle 4] assistBanned=TRUE (B_UPDATED_MOVE_FLAGS>=GEN_6).
     "ban_flags": (BAN_ASSIST | BAN_SLEEP_TALK),},

    {"id": 342, "name": "Poison Tail",
     "type": TYPE_POISON, "category": PHYS, "power": 50, "accuracy": 100, "pp": 25,
     "makes_contact": True, "critical_hit_stage": 1, "secondary_effect": SE_POISON, "secondary_chance": 10},

    {"id": 344, "name": "Volt Tackle",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 33, "secondary_effect": SE_PARALYSIS, "secondary_chance": 10},

    {"id": 352, "name": "Water Pulse",
     "type": TYPE_WATER, "category": SPEC, "power": 60, "accuracy": 100, "pp": 20,
     "pulse_move": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 20},

    {"id": 394, "name": "Flare Blitz",
     "type": TYPE_FIRE, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "thaws_user": True, "recoil_percent": 33, "secondary_effect": SE_BURN, "secondary_chance": 10},

    {"id": 395, "name": "Force Palm",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "makes_contact": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30},

    {"id": 397, "name": "Rock Polish",
     "type": TYPE_ROCK, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 398, "name": "Poison Jab",
     "type": TYPE_POISON, "category": PHYS, "power": 80, "accuracy": 100, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_POISON, "secondary_chance": 30},

    {"id": 399, "name": "Dark Pulse",
     "type": TYPE_DARK, "category": SPEC, "power": 80, "accuracy": 100, "pp": 15,
     "pulse_move": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20},

    {"id": 403, "name": "Air Slash",
     "type": TYPE_FLYING, "category": SPEC, "power": 75, "accuracy": 95, "pp": 15,
     "slicing_move": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 407, "name": "Dragon Rush",
     "type": TYPE_DRAGON, "category": PHYS, "power": 100, "accuracy": 75, "pp": 10,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20, "double_power_on_minimized": True,},

    {"id": 417, "name": "Nasty Plot",
     "type": TYPE_DARK, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    {"id": 428, "name": "Zen Headbutt",
     "type": TYPE_PSYCHIC, "category": PHYS, "power": 80, "accuracy": 90, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20},

    {"id": 431, "name": "Rock Climb",
     "type": TYPE_NORMAL, "category": PHYS, "power": 90, "accuracy": 85, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 20},

    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 435, "name": "Discharge",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 15,
     "is_spread": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30,
     "target_includes_ally": True},

    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 436, "name": "Lava Plume",
     "type": TYPE_FIRE, "category": SPEC, "power": 80, "accuracy": 100, "pp": 15,
     "is_spread": True, "secondary_effect": SE_BURN, "secondary_chance": 30,
     "target_includes_ally": True},

    {"id": 440, "name": "Cross Poison",
     "type": TYPE_POISON, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "makes_contact": True, "slicing_move": True, "critical_hit_stage": 1, "secondary_effect": SE_POISON, "secondary_chance": 10},

    {"id": 441, "name": "Gunk Shot",
     "type": TYPE_POISON, "category": PHYS, "power": 120, "accuracy": 80, "pp": 5,
     "secondary_effect": SE_POISON, "secondary_chance": 30},

    {"id": 442, "name": "Iron Head",
     "type": TYPE_STEEL, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 452, "name": "Wood Hammer",
     "type": TYPE_GRASS, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 33},

    {"id": 457, "name": "Head Smash",
     "type": TYPE_ROCK, "category": PHYS, "power": 150, "accuracy": 80, "pp": 5,
     "makes_contact": True, "recoil_percent": 50},

    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 482, "name": "Sludge Wave",
     "type": TYPE_POISON, "category": SPEC, "power": 95, "accuracy": 100, "pp": 10,
     "is_spread": True, "secondary_effect": SE_POISON, "secondary_chance": 10,
     "target_includes_ally": True},

    {"id": 503, "name": "Scald",
     "type": TYPE_WATER, "category": SPEC, "power": 80, "accuracy": 100, "pp": 15,
     "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 30},

    {"id": 517, "name": "Inferno",
     "type": TYPE_FIRE, "category": SPEC, "power": 100, "accuracy": 50, "pp": 5,
     "secondary_effect": SE_BURN, "secondary_chance": 100},

    {"id": 528, "name": "Wild Charge",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 25},

    {"id": 531, "name": "Heart Stamp",
     "type": TYPE_PSYCHIC, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 532, "name": "Horn Leech",
     "type": TYPE_GRASS, "category": PHYS, "power": 75, "accuracy": 100, "pp": 10,
     "makes_contact": True, "drain_percent": 50, "healing_move": True},

    {"id": 537, "name": "Steamroller",
     "type": TYPE_BUG, "category": PHYS, "power": 65, "accuracy": 100, "pp": 20,
     "makes_contact": True, "double_power_on_minimized": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 538, "name": "Cotton Guard",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 3, "stat_change_self": True, "snatch_affected": True},

    {"id": 543, "name": "Head Charge",
     "type": TYPE_NORMAL, "category": PHYS, "power": 120, "accuracy": 100, "pp": 15,
     "makes_contact": True, "recoil_percent": 25},

    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id": 545, "name": "Searing Shot",
     "type": TYPE_FIRE, "category": SPEC, "power": 100, "accuracy": 100, "pp": 5,
     "ballistic_move": True, "is_spread": True, "secondary_effect": SE_BURN,
     "secondary_chance": 30, "target_includes_ally": True},

    {"id": 547, "name": "Relic Song",
     "type": TYPE_NORMAL, "category": SPEC, "power": 75, "accuracy": 100, "pp": 10,
     "sound_move": True, "is_spread": True, "secondary_effect": SE_SLEEP, "secondary_chance": 10,
     "ban_flags": BAN_METRONOME, "ignores_substitute": True,},

    {"id": 550, "name": "Bolt Strike",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 130, "accuracy": 85, "pp": 5,
     "makes_contact": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 20},

    {"id": 551, "name": "Blue Flare",
     "type": TYPE_FIRE, "category": SPEC, "power": 130, "accuracy": 85, "pp": 5,
     "secondary_effect": SE_BURN, "secondary_chance": 20},

    {"id": 553, "name": "Freeze Shock",
     "type": TYPE_ICE, "category": PHYS, "power": 140, "accuracy": 90, "pp": 5,
     "two_turn": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30,
     "ban_flags": (BAN_METRONOME | BAN_SLEEP_TALK)},

    {"id": 554, "name": "Ice Burn",
     "type": TYPE_ICE, "category": SPEC, "power": 140, "accuracy": 90, "pp": 5,
     "two_turn": True, "secondary_effect": SE_BURN, "secondary_chance": 30,
     "ban_flags": (BAN_METRONOME | BAN_SLEEP_TALK)},

    {"id": 556, "name": "Icicle Crash",
     "type": TYPE_ICE, "category": PHYS, "power": 85, "accuracy": 90, "pp": 10,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    # Re-confirmed the drain mechanism needs NO change: drain_percent is
    # applied inside _do_damaging_hit (damage * drain_percent / 100), called
    # once per target in the spread loop — the ally is simply one more
    # target in that same existing loop, healing the attacker off the
    # ally's own hit just like any opponent's, matching source's real
    # per-hit (not accumulate-then-heal-once) drain behavior.
    {"id": 570, "name": "Parabolic Charge",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 65, "accuracy": 100, "pp": 20,
     "is_spread": True, "drain_percent": 50, "healing_move": True,
     "target_includes_ally": True},

    {"id": 577, "name": "Draining Kiss",
     "type": TYPE_FAIRY, "category": SPEC, "power": 50, "accuracy": 100, "pp": 10,
     "makes_contact": True, "drain_percent": 75, "healing_move": True},

    {"id": 589, "name": "Play Nice",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "ignores_substitute": True, "bounceable": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True},

    {"id": 590, "name": "Confide",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0, "pp": 20,
     "sound_move": True, "ignores_protect": True, "bounceable": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1,
     "stat_change_bypasses_type_gate": True, "ignores_substitute": True,},

    {"id": 592, "name": "Steam Eruption",
     "type": TYPE_WATER, "category": SPEC, "power": 110, "accuracy": 95, "pp": 5,
     "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},

    {"id": 598, "name": "Eerie Impulse",
     "type": TYPE_ELECTRIC, "category": STAT, "power": 0, "accuracy": 100, "pp": 15,
     "bounceable": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2,
     "stat_change_bypasses_type_gate": True},

    {"id": 608, "name": "Baby-Doll Eyes",
     "type": TYPE_FAIRY, "category": STAT, "power": 0, "accuracy": 100, "pp": 30,
     "priority": 1, "bounceable": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1},

    {"id": 609, "name": "Nuzzle",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 20, "accuracy": 100, "pp": 20,
     "makes_contact": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 100},

    {"id": 613, "name": "Oblivion Wing",
     "type": TYPE_FLYING, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "drain_percent": 75, "healing_move": True},

    {"id": 617, "name": "Light Of Ruin",
     "type": TYPE_FAIRY, "category": SPEC, "power": 140, "accuracy": 90, "pp": 5,
     "recoil_percent": 50,
     "ban_flags": BAN_METRONOME},

    {"id": 660, "name": "Psychic Fangs",
     "type": TYPE_PSYCHIC, "category": PHYS, "power": 85, "accuracy": 100, "pp": 15,
     "makes_contact": True, "biting_move": True, "breaks_screens": True},

    {"id": 670, "name": "Zing Zap",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 677, "name": "Splishy Splash",
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 100, "pp": 15,
     "is_spread": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},

    {"id": 678, "name": "Floaty Fall",
     "type": TYPE_FLYING, "category": PHYS, "power": 90, "accuracy": 95, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},

    {"id": 680, "name": "Bouncy Bubble",
     "type": TYPE_WATER, "category": SPEC, "power": 60, "accuracy": 100, "pp": 20,
     "drain_percent": 100, "healing_move": True,
     "ban_flags": BAN_METRONOME},

    # [M21.5 Bucket 3] secondary_chance corrected 100->0: source's own
    # additionalEffects block for this move omits `.chance` entirely (unlike
    # Nuzzle(609), which explicitly sets `.chance = 100`) -- MoveIsAffected
    # BySheerForce evaluates `(chance > 0) != sheerForceOverride`, so an
    # absent/0 chance with no override means Sheer Force does NOT apply,
    # matching this project's own established "0 = guaranteed, Sheer-Force-
    # exempt" convention for the Overheat/Draco-Meteor-style self-drop family.
    {"id": 681, "name": "Buzzy Buzz",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 60, "accuracy": 100, "pp": 20,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 0,
     "ban_flags": BAN_METRONOME},

    # [M21.5 Bucket 3] secondary_chance corrected 100->0 -- same reasoning as
    # Buzzy Buzz above: source omits `.chance` entirely for this move too.
    {"id": 682, "name": "Sizzly Slide",
     "type": TYPE_FIRE, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 0,
     "ban_flags": BAN_METRONOME},

    {"id": 708, "name": "Pyro Ball",
     "type": TYPE_FIRE, "category": PHYS, "power": 120, "accuracy": 90, "pp": 5,
     "ballistic_move": True, "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 10,
     "ban_flags": BAN_METRONOME},

    {"id": 718, "name": "Strange Steam",
     "type": TYPE_FAIRY, "category": SPEC, "power": 90, "accuracy": 95, "pp": 10,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 20,
     "ban_flags": BAN_METRONOME},

    {"id": 743, "name": "Scorching Sands",
     "type": TYPE_GROUND, "category": SPEC, "power": 70, "accuracy": 100, "pp": 10,
     "thaws_user": True, "secondary_effect": SE_BURN, "secondary_chance": 30},

    {"id": 749, "name": "Freezing Glare",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_FREEZE, "secondary_chance": 10,
     "ban_flags": BAN_METRONOME},

    {"id": 750, "name": "Fiery Wrath",
     "type": TYPE_DARK, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "is_spread": True, "secondary_effect": SE_FLINCH, "secondary_chance": 20,
     "ban_flags": BAN_METRONOME},

    {"id": 762, "name": "Wave Crash",
     "type": TYPE_WATER, "category": PHYS, "power": 120, "accuracy": 100, "pp": 10,
     "makes_contact": True, "recoil_percent": 33},

    {"id": 764, "name": "Mountain Gale",
     "type": TYPE_ICE, "category": PHYS, "power": 100, "accuracy": 85, "pp": 10,
     "secondary_effect": SE_FLINCH, "secondary_chance": 30},

    {"id": 817, "name": "Bitter Blade",
     "type": TYPE_FIRE, "category": PHYS, "power": 90, "accuracy": 100, "pp": 10,
     "makes_contact": True, "slicing_move": True, "drain_percent": 50, "healing_move": True},

    {"id": 830, "name": "Matcha Gotcha",
     "type": TYPE_GRASS, "category": SPEC, "power": 80, "accuracy": 90, "pp": 15,
     "thaws_user": True, "is_spread": True, "drain_percent": 50, "healing_move": True, "secondary_effect": SE_BURN, "secondary_chance": 20},

    {"id": 847, "name": "Malignant Chain",
     "type": TYPE_POISON, "category": SPEC, "power": 100, "accuracy": 100, "pp": 5,
     "secondary_effect": SE_TOXIC, "secondary_chance": 50},

    # M19-secondary-stat-on-hit: EFFECT_HIT moves whose secondary
    # stat-change payload previously had nowhere to attach (secondary_effect
    # stays SE_NONE by construction; stat_change_stat/amount/self carry the
    # payload instead, dispatched via the new stat_change_stat >= 0 branch in
    # StatusManager.try_secondary_effect). secondary_chance: 0 = guaranteed/
    # Sheer-Force-exempt (10 moves whose source OMITS .chance entirely — all
    # self-targeted post-hit drops); explicit N = a true probabilistic secondary
    # (69 moves), subject to Shield Dust/Covert Cloak/Sheer Force/Serene Grace
    # exactly like every other true secondary effect.
    {"id":   51, "name": "Acid",
     "type": TYPE_POISON, "category": SPEC, "power": 40, "accuracy": 100,
     "pp": 30, "is_spread": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":   61, "name": "Bubble Beam",
     "type": TYPE_WATER, "category": SPEC, "power": 65, "accuracy": 100,
     "pp": 20, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1, "secondary_chance": 10},
    {"id":   62, "name": "Aurora Beam",
     "type": TYPE_ICE, "category": SPEC, "power": 65, "accuracy": 100,
     "pp": 20, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1, "secondary_chance": 10},
    {"id":   94, "name": "Psychic",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 90, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1, "secondary_chance": 10},
    {"id":  132, "name": "Constrict",
     "type": TYPE_NORMAL, "category": PHYS, "power": 10, "accuracy": 100,
     "pp": 35, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":  145, "name": "Bubble",
     "type": TYPE_WATER, "category": SPEC, "power": 40, "accuracy": 100,
     "pp": 30, "is_spread": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":  189, "name": "Mud-Slap",
     "type": TYPE_GROUND, "category": SPEC, "power": 20, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  190, "name": "Octazooka",
     "type": TYPE_WATER, "category": SPEC, "power": 65, "accuracy": 85,
     "pp": 10, "ballistic_move": True, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "secondary_chance": 50},
    {"id":  196, "name": "Icy Wind",
     "type": TYPE_ICE, "category": SPEC, "power": 55, "accuracy": 95,
     "pp": 15, "is_spread": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  211, "name": "Steel Wing",
     "type": TYPE_STEEL, "category": PHYS, "power": 70, "accuracy": 90,
     "pp": 25, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 10},
    {"id":  231, "name": "Iron Tail",
     "type": TYPE_STEEL, "category": PHYS, "power": 100, "accuracy": 75,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 30},
    {"id":  232, "name": "Metal Claw",
     "type": TYPE_STEEL, "category": PHYS, "power": 50, "accuracy": 95,
     "pp": 35, "makes_contact": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 10},
    {"id":  242, "name": "Crunch",
     "type": TYPE_DARK, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 15, "makes_contact": True, "biting_move": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "secondary_chance": 20},
    {"id":  247, "name": "Shadow Ball",
     "type": TYPE_GHOST, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 15, "ballistic_move": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1,
     "secondary_chance": 20},
    {"id":  249, "name": "Rock Smash",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 40, "accuracy": 100,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 50},
    {"id":  295, "name": "Luster Purge",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 9, "accuracy": 100,
     "pp": 5, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1, "secondary_chance": 50},
    {"id":  296, "name": "Mist Ball",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 9, "accuracy": 100,
     "pp": 5, "ballistic_move": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1,
     "secondary_chance": 50},
    {"id":  306, "name": "Crush Claw",
     "type": TYPE_NORMAL, "category": PHYS, "power": 75, "accuracy": 95,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 50},
    {"id":  309, "name": "Meteor Mash",
     "type": TYPE_STEEL, "category": PHYS, "power": 90, "accuracy": 90,
     "pp": 10, "makes_contact": True, "punching_move": True, "stat_change_stat": STAGE_ATK,
     "stat_change_amount": 1, "stat_change_self": True, "secondary_chance": 20},
    {"id":  315, "name": "Overheat",
     "type": TYPE_FIRE, "category": SPEC, "power": 130, "accuracy": 90,
     "pp": 5, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2, "stat_change_self": True,
     "secondary_chance": 0},
    {"id":  317, "name": "Rock Tomb",
     "type": TYPE_ROCK, "category": PHYS, "power": 60, "accuracy": 95,
     "pp": 15, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  330, "name": "Muddy Water",
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 85,
     "pp": 10, "is_spread": True, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "secondary_chance": 30},
    {"id":  341, "name": "Mud Shot",
     "type": TYPE_GROUND, "category": SPEC, "power": 55, "accuracy": 95,
     "pp": 15, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  354, "name": "Psycho Boost",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 140, "accuracy": 90,
     "pp": 5, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2, "stat_change_self": True,
     "secondary_chance": 0},
    {"id":  359, "name": "Hammer Arm",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 100, "accuracy": 90,
     "pp": 10, "makes_contact": True, "punching_move": True, "stat_change_stat": STAGE_SPEED,
     "stat_change_amount": -1, "stat_change_self": True, "secondary_chance": 0},
    {"id":  405, "name": "Bug Buzz",
     "type": TYPE_BUG, "category": SPEC, "power": 90, "accuracy": 100,
     "pp": 10, "sound_move": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1,
     "secondary_chance": 10, "ignores_substitute": True,},
    {"id":  411, "name": "Focus Blast",
     "type": TYPE_FIGHTING, "category": SPEC, "power": 120, "accuracy": 70,
     "pp": 5, "ballistic_move": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":  412, "name": "Energy Ball",
     "type": TYPE_GRASS, "category": SPEC, "power": 90, "accuracy": 100,
     "pp": 10, "ballistic_move": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":  414, "name": "Earth Power",
     "type": TYPE_GROUND, "category": SPEC, "power": 90, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1, "secondary_chance": 10},
    {"id":  426, "name": "Mud Bomb",
     "type": TYPE_GROUND, "category": SPEC, "power": 65, "accuracy": 85,
     "pp": 10, "ballistic_move": True, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1,
     "secondary_chance": 30},
    {"id":  429, "name": "Mirror Shot",
     "type": TYPE_STEEL, "category": SPEC, "power": 65, "accuracy": 85,
     "pp": 10, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "secondary_chance": 30},
    {"id":  430, "name": "Flash Cannon",
     "type": TYPE_STEEL, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1, "secondary_chance": 10},
    {"id":  434, "name": "Draco Meteor",
     "type": TYPE_DRAGON, "category": SPEC, "power": 130, "accuracy": 90,
     "pp": 5, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2, "stat_change_self": True,
     "secondary_chance": 0},
    {"id":  437, "name": "Leaf Storm",
     "type": TYPE_GRASS, "category": SPEC, "power": 130, "accuracy": 90,
     "pp": 5, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2, "stat_change_self": True,
     "secondary_chance": 0},
    {"id":  451, "name": "Charge Beam",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 50, "accuracy": 90,
     "pp": 10, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1, "stat_change_self": True,
     "secondary_chance": 70},
    {"id":  465, "name": "Seed Flare",
     "type": TYPE_GRASS, "category": SPEC, "power": 120, "accuracy": 85,
     "pp": 5, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -2, "secondary_chance": 40},
    {"id":  488, "name": "Flame Charge",
     "type": TYPE_FIRE, "category": PHYS, "power": 50, "accuracy": 100,
     "pp": 20, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100},
    {"id":  490, "name": "Low Sweep",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 65, "accuracy": 100,
     "pp": 20, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  491, "name": "Acid Spray",
     "type": TYPE_POISON, "category": SPEC, "power": 40, "accuracy": 100,
     "pp": 20, "ballistic_move": True, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -2,
     "secondary_chance": 100},
    {"id":  522, "name": "Struggle Bug",
     "type": TYPE_BUG, "category": SPEC, "power": 50, "accuracy": 100,
     "pp": 20, "is_spread": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  527, "name": "Electroweb",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 55, "accuracy": 95,
     "pp": 15, "is_spread": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  534, "name": "Razor Shell",
     "type": TYPE_WATER, "category": PHYS, "power": 75, "accuracy": 95,
     "pp": 10, "makes_contact": True, "slicing_move": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "secondary_chance": 50},
    {"id":  536, "name": "Leaf Tornado",
     "type": TYPE_GRASS, "category": SPEC, "power": 65, "accuracy": 90,
     "pp": 10, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "secondary_chance": 50},
    {"id":  539, "name": "Night Daze",
     "type": TYPE_DARK, "category": SPEC, "power": 85, "accuracy": 95,
     "pp": 10, "stat_change_stat": STAGE_ACCURACY, "stat_change_amount": -1, "secondary_chance": 40},
    {"id":  549, "name": "Glaciate",
     "type": TYPE_ICE, "category": SPEC, "power": 65, "accuracy": 95,
     "pp": 10, "is_spread": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  552, "name": "Fiery Dance",
     "type": TYPE_FIRE, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1, "stat_change_self": True,
     "secondary_chance": 50},
    {"id":  555, "name": "Snarl",
     "type": TYPE_DARK, "category": SPEC, "power": 55, "accuracy": 95,
     "pp": 15, "sound_move": True, "is_spread": True, "stat_change_stat": STAGE_SPATK,
     "stat_change_amount": -1, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME, "ignores_substitute": True,},
    {"id":  583, "name": "Play Rough",
     "type": TYPE_FAIRY, "category": PHYS, "power": 90, "accuracy": 90,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "secondary_chance": 10},
    {"id":  585, "name": "Moonblast",
     "type": TYPE_FAIRY, "category": SPEC, "power": 95, "accuracy": 100,
     "pp": 15, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1, "secondary_chance": 30},
    {"id":  591, "name": "Diamond Storm",
     "type": TYPE_ROCK, "category": PHYS, "power": 100, "accuracy": 95,
     "pp": 5, "is_spread": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 2,
     "stat_change_self": True, "secondary_chance": 50,
     "ban_flags": BAN_METRONOME},
    {"id":  595, "name": "Mystical Fire",
     "type": TYPE_FIRE, "category": SPEC, "power": 75, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  612, "name": "Power-Up Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 40, "accuracy": 100,
     "pp": 20, "makes_contact": True, "punching_move": True, "stat_change_stat": STAGE_ATK,
     "stat_change_amount": 1, "stat_change_self": True, "secondary_chance": 100},
    {"id":  628, "name": "Ice Hammer",
     "type": TYPE_ICE, "category": PHYS, "power": 100, "accuracy": 90,
     "pp": 10, "makes_contact": True, "punching_move": True, "stat_change_stat": STAGE_SPEED,
     "stat_change_amount": -1, "stat_change_self": True, "secondary_chance": 0},
    {"id":  642, "name": "Lunge",
     "type": TYPE_BUG, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  643, "name": "Fire Lash",
     "type": TYPE_FIRE, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  651, "name": "Trop Kick",
     "type": TYPE_GRASS, "category": PHYS, "power": 70, "accuracy": 100,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  654, "name": "Clanging Scales",
     "type": TYPE_DRAGON, "category": SPEC, "power": 110, "accuracy": 100,
     "pp": 5, "sound_move": True, "is_spread": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "stat_change_self": True, "secondary_chance": 0, "ignores_substitute": True,},
    {"id":  659, "name": "Fleur Cannon",
     "type": TYPE_FAIRY, "category": SPEC, "power": 130, "accuracy": 90,
     "pp": 5, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -2, "stat_change_self": True,
     "secondary_chance": 0,
     "ban_flags": BAN_METRONOME},
    {"id":  662, "name": "Shadow Bone",
     "type": TYPE_GHOST, "category": PHYS, "power": 85, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "secondary_chance": 20},
    {"id":  664, "name": "Liquidation",
     "type": TYPE_WATER, "category": PHYS, "power": 85, "accuracy": 100,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 20},
    {"id":  676, "name": "Zippy Zap",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 10, "makes_contact": True, "priority": 2, "always_critical_hit": True,
     "stat_change_stat": STAGE_EVASION, "stat_change_amount": 1, "stat_change_self": True, "secondary_chance": 0,
     "ban_flags": BAN_METRONOME},
    {"id":  706, "name": "Drum Beating",
     "type": TYPE_GRASS, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  712, "name": "Breaking Swipe",
     "type": TYPE_DRAGON, "category": PHYS, "power": 60, "accuracy": 100,
     "pp": 15, "makes_contact": True, "is_spread": True, "stat_change_stat": STAGE_ATK,
     "stat_change_amount": -1, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  715, "name": "Apple Acid",
     "type": TYPE_GRASS, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -1, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  717, "name": "Spirit Break",
     "type": TYPE_FAIRY, "category": PHYS, "power": 75, "accuracy": 100,
     "pp": 15, "makes_contact": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1,
     "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  734, "name": "Skitter Smack",
     "type": TYPE_BUG, "category": PHYS, "power": 70, "accuracy": 90,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": -1,
     "secondary_chance": 100},
    {"id":  751, "name": "Thunderous Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 90, "accuracy": 100,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  756, "name": "Psyshield Bash",
     "type": TYPE_PSYCHIC, "category": PHYS, "power": 70, "accuracy": 90,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100},
    {"id":  759, "name": "Springtide Storm",
     "type": TYPE_FAIRY, "category": SPEC, "power": 100, "accuracy": 80,
     "pp": 5, "is_spread": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},
    {"id":  760, "name": "Mystical Power",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 70, "accuracy": 90,
     "pp": 10, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1, "stat_change_self": True,
     "secondary_chance": 100},
    {"id":  768, "name": "Esper Wing",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "critical_hit_stage": 1, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100},
    {"id":  769, "name": "Bitter Malice",
     "type": TYPE_GHOST, "category": SPEC, "power": 75, "accuracy": 100,
     "pp": 15, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  783, "name": "Lumina Crash",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "stat_change_stat": STAGE_SPDEF, "stat_change_amount": -2, "secondary_chance": 100},
    {"id":  787, "name": "Spin Out",
     "type": TYPE_STEEL, "category": PHYS, "power": 100, "accuracy": 100,
     "pp": 5, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -2,
     "stat_change_self": True, "secondary_chance": 0},
    {"id":  799, "name": "Torch Song",
     "type": TYPE_FIRE, "category": SPEC, "power": 80, "accuracy": 100,
     "pp": 10, "sound_move": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100, "ignores_substitute": True,},
    {"id":  800, "name": "Aqua Step",
     "type": TYPE_WATER, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 10, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100},
    {"id":  810, "name": "Pounce",
     "type": TYPE_BUG, "category": PHYS, "power": 50, "accuracy": 100,
     "pp": 20, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  811, "name": "Trailblaze",
     "type": TYPE_GRASS, "category": PHYS, "power": 50, "accuracy": 100,
     "pp": 20, "makes_contact": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": 1,
     "stat_change_self": True, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},
    {"id":  812, "name": "Chilling Water",
     "type": TYPE_WATER, "category": SPEC, "power": 50, "accuracy": 100,
     "pp": 20, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1, "secondary_chance": 100,
     "ban_flags": BAN_METRONOME},

    # [Bucket 3 multi-stat] moves whose stat-change payload touches 2+
    # distinct stats at once (Ancient Power +1 to all 5 non-HP stats, Shell
    # Smash mixed +2/-1, Spicy Extract mixed +2/-2) -- primary pair in
    # stat_change_stat/amount, everything additional in
    # extra_stat_change_stats/amounts. Coaching(739) deliberately excluded --
    # genuinely ally-targeting (TARGET_ALLY), which this project's self/foe-only
    # stat_change_self schema cannot represent; deferred to merge with
    # M19-ally-targeting-stat-change instead.
    {"id":  246, "name": "Ancient Power",
     "type": TYPE_ROCK, "category": SPEC, "power": 60, "accuracy": 100,
     "pp": 5, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "secondary_chance": 10, "extra_stat_change_stats": [STAGE_DEF, STAGE_SPATK, STAGE_SPDEF, STAGE_SPEED], "extra_stat_change_amounts": [1, 1, 1, 1]},
    {"id":  276, "name": "Superpower",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 120, "accuracy": 100,
     "pp": 5, "makes_contact": True, "stat_change_self": True, "stat_change_stat": STAGE_ATK,
     "stat_change_amount": -1, "secondary_chance": 0, "extra_stat_change_stats": [STAGE_DEF], "extra_stat_change_amounts": [-1]},
    {"id":  318, "name": "Silver Wind",
     "type": TYPE_BUG, "category": SPEC, "power": 60, "accuracy": 100,
     "pp": 5, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "secondary_chance": 10, "extra_stat_change_stats": [STAGE_DEF, STAGE_SPATK, STAGE_SPDEF, STAGE_SPEED], "extra_stat_change_amounts": [1, 1, 1, 1]},
    {"id":  321, "name": "Tickle",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100,
     "pp": 20, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1, "extra_stat_change_stats": [STAGE_DEF],
     "extra_stat_change_amounts": [-1], "stat_change_bypasses_type_gate": True, "bounceable": True,},
    {"id":  322, "name": "Cosmic Power",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  339, "name": "Bulk Up",
     "type": TYPE_FIGHTING, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_DEF], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  347, "name": "Calm Mind",
     "type": TYPE_PSYCHIC, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  349, "name": "Dragon Dance",
     "type": TYPE_DRAGON, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPEED], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  370, "name": "Close Combat",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 120, "accuracy": 100,
     "pp": 5, "makes_contact": True, "stat_change_self": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "secondary_chance": 0, "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [-1]},
    {"id":  466, "name": "Ominous Wind",
     "type": TYPE_GHOST, "category": SPEC, "power": 60, "accuracy": 100,
     "pp": 5, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "secondary_chance": 10, "extra_stat_change_stats": [STAGE_DEF, STAGE_SPATK, STAGE_SPDEF, STAGE_SPEED], "extra_stat_change_amounts": [1, 1, 1, 1]},
    {"id":  468, "name": "Hone Claws",
     "type": TYPE_DARK, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 15, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_ACCURACY], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  483, "name": "Quiver Dance",
     "type": TYPE_BUG, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPDEF, STAGE_SPEED], "extra_stat_change_amounts": [1, 1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  489, "name": "Coil",
     "type": TYPE_POISON, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_DEF, STAGE_ACCURACY], "extra_stat_change_amounts": [1, 1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  504, "name": "Shell Smash",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 15, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 2,
     "extra_stat_change_stats": [STAGE_SPATK, STAGE_SPEED, STAGE_DEF, STAGE_SPDEF], "extra_stat_change_amounts": [2, 2, -1, -1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  508, "name": "Shift Gear",
     "type": TYPE_STEEL, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 10, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPEED], "extra_stat_change_amounts": [2], "snatch_affected": True, "ignores_protect": True,},
    {"id":  526, "name": "Work Up",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 30, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPATK], "extra_stat_change_amounts": [1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  568, "name": "Noble Roar",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 100,
     "pp": 30, "sound_move": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1,
     "extra_stat_change_stats": [STAGE_SPATK], "extra_stat_change_amounts": [-1],
     "stat_change_bypasses_type_gate": True, "bounceable": True, "ignores_substitute": True,},
    {"id":  620, "name": "Dragon Ascent",
     "type": TYPE_FLYING, "category": PHYS, "power": 120, "accuracy": 100,
     "pp": 5, "makes_contact": True, "stat_change_self": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "secondary_chance": 0, "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [-1],
     "ban_flags": BAN_METRONOME},
    {"id":  669, "name": "Tearful Look",
     "type": TYPE_NORMAL, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_stat": STAGE_ATK, "stat_change_amount": -1, "extra_stat_change_stats": [STAGE_SPATK],
     "extra_stat_change_amounts": [-1], "stat_change_bypasses_type_gate": True, "ignores_protect": True, "bounceable": True,},
    {"id":  705, "name": "Decorate",
     "type": TYPE_FAIRY, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 15, "stat_change_stat": STAGE_ATK, "stat_change_amount": 2, "extra_stat_change_stats": [STAGE_SPATK],
     "extra_stat_change_amounts": [2],
     "ban_flags": BAN_METRONOME, "ignores_protect": True,},
    {"id":  765, "name": "Victory Dance",
     "type": TYPE_FIGHTING, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 20, "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_DEF, STAGE_SPEED], "extra_stat_change_amounts": [1, 1], "snatch_affected": True, "ignores_protect": True,},
    {"id":  766, "name": "Headlong Rush",
     "type": TYPE_GROUND, "category": PHYS, "power": 120, "accuracy": 100,
     "pp": 5, "makes_contact": True, "stat_change_self": True, "stat_change_stat": STAGE_DEF,
     "stat_change_amount": -1, "secondary_chance": 0, "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [-1], "punching_move": True,},
    {"id":  786, "name": "Spicy Extract",
     "type": TYPE_GRASS, "category": STAT, "power": 0, "accuracy": 0,
     "pp": 15, "stat_change_stat": STAGE_ATK, "stat_change_amount": 2, "extra_stat_change_stats": [STAGE_DEF],
     "extra_stat_change_amounts": [-2],
     "ban_flags": BAN_METRONOME, "bounceable": True,},
    {"id":  816, "name": "Armor Cannon",
     "type": TYPE_FIRE, "category": SPEC, "power": 120, "accuracy": 100,
     "pp": 5, "stat_change_self": True, "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "secondary_chance": 0, "extra_stat_change_stats": [STAGE_SPDEF], "extra_stat_change_amounts": [-1],
     "ban_flags": BAN_METRONOME},

    # ── [Bucket 3 combined-secondary] Thunder Fang / Ice Fang / Fire Fang: status
    # (slot 1) + independently-rolled 10% flinch (slot 2). GEN_LATEST config values
    # confirmed directly from moves_info.h (no ternaries on these three).
    {"id":  422, "name": "Thunder Fang",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 65, "accuracy": 95, "pp": 15,
     "makes_contact": True, "biting_move": True,
     "secondary_effect": SE_PARALYSIS, "secondary_chance": 10,
     "secondary_effect_2": SE_FLINCH, "secondary_chance_2": 10},
    {"id":  423, "name": "Ice Fang",
     "type": TYPE_ICE, "category": PHYS, "power": 65, "accuracy": 95, "pp": 15,
     "makes_contact": True, "biting_move": True,
     "secondary_effect": SE_FREEZE, "secondary_chance": 10,
     "secondary_effect_2": SE_FLINCH, "secondary_chance_2": 10},
    {"id":  424, "name": "Fire Fang",
     "type": TYPE_FIRE, "category": PHYS, "power": 65, "accuracy": 95, "pp": 15,
     "makes_contact": True, "biting_move": True,
     "secondary_effect": SE_BURN, "secondary_chance": 10,
     "secondary_effect_2": SE_FLINCH, "secondary_chance_2": 10},

    # ── [Bucket 3 screen+damage] Glitzy Glow / Baddy Bad: EFFECT_HIT damage move
    # that also sets a guaranteed self-side screen. GEN_LATEST (>= GEN_8) config:
    # power 80, accuracy 95 (both moves' ternaries resolve the same way).
    {"id":  683, "name": "Glitzy Glow",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 95, "pp": 15,
     "sets_light_screen_on_hit": True,
     "ban_flags": BAN_METRONOME},
    {"id":  684, "name": "Baddy Bad",
     "type": TYPE_DARK, "category": SPEC, "power": 80, "accuracy": 95, "pp": 15,
     "sets_reflect_on_hit": True,
     "ban_flags": BAN_METRONOME},

    # ── [Bucket 4 cheapest singles] Rage, Clear Smog, Incinerate, Sparkling
    # Aria, Throat Chop, Eerie Spell, Blood Moon — 7 single-move sub-groups,
    # each with its own independent Step 0 mechanism (see move_data.gd's
    # per-flag doc comments for full source citations). Secret Power(290) and
    # Uproar(253) — the other 2 moves in this Bucket 4 batch — were deferred
    # (Secret Power needs an overworld-location concept this project doesn't
    # have; Uproar needs the same multi-turn forced-move-repeat mechanism
    # Bucket 4's still-unbuilt M19-rampage sub-group needs) — not added here.
    {"id":  99, "name": "Rage",
     "type": TYPE_NORMAL, "category": PHYS, "power": 20, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_rage": True},
    {"id":  499, "name": "Clear Smog",
     "type": TYPE_POISON, "category": SPEC, "power": 50, "accuracy": 0, "pp": 15,
     "is_clear_smog": True},
    {"id":  510, "name": "Incinerate",
     "type": TYPE_FIRE, "category": SPEC, "power": 60, "accuracy": 100, "pp": 15,
     "is_spread": True, "is_incinerate": True},
    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    # Re-confirmed its own burn-cure (is_sparkling_aria) reads `target`
    # inside _do_damaging_hit (called once per target in the spread loop),
    # so it correctly extends to cure the ally's own burn too if the ally
    # is hit and burned — no special-casing needed.
    {"id":  627, "name": "Sparkling Aria",
     "type": TYPE_WATER, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "sound_move": True, "ignores_substitute": True, "is_spread": True,
     "is_sparkling_aria": True, "target_includes_ally": True},
    {"id":  638, "name": "Throat Chop",
     "type": TYPE_DARK, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_THROAT_CHOP, "secondary_chance": 100},
    {"id":  754, "name": "Eerie Spell",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 5,
     "sound_move": True, "ignores_substitute": True,
     "secondary_effect": SE_EERIE_SPELL, "secondary_chance": 100},
    {"id":  829, "name": "Blood Moon",
     "type": TYPE_NORMAL, "category": SPEC, "power": 140, "accuracy": 100, "pp": 5,
     "cant_use_twice": True},

    # ── [M19-rampage] Thrash / Petal Dance / Outrage / Raging Fury (is_rampage,
    # confuse-on-lock-end) + Uproar (is_uproar, no confuse, field-wide new-sleep
    # block) — GEN_LATEST config values (see move_data.gd's own is_rampage/
    # is_uproar doc comments for the full source citations). Raging Fury
    # deliberately has NO makes_contact — confirmed absent from source, unlike
    # the other three rampage moves.
    {"id":  37, "name": "Thrash",
     "type": TYPE_NORMAL, "category": PHYS, "power": 120, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_rampage": True},
    {"id":  80, "name": "Petal Dance",
     "type": TYPE_GRASS, "category": SPEC, "power": 120, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_rampage": True},
    {"id":  200, "name": "Outrage",
     "type": TYPE_DRAGON, "category": PHYS, "power": 120, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_rampage": True},
    {"id":  761, "name": "Raging Fury",
     "type": TYPE_FIRE, "category": PHYS, "power": 120, "accuracy": 100, "pp": 10,
     "is_rampage": True,
     "ban_flags": BAN_METRONOME},
    {"id":  253, "name": "Uproar",
     "type": TYPE_NORMAL, "category": SPEC, "power": 90, "accuracy": 100, "pp": 10,
     "sound_move": True, "ignores_substitute": True, "is_uproar": True,
     "ban_flags": BAN_SLEEP_TALK},

    # ── [M19-recharge] Hyper Beam / Blast Burn / Hydro Cannon / Frenzy Plant /
    # Giga Impact / Rock Wrecker / Roar of Time / Prismatic Laser / Meteor
    # Assault / Eternabeam — all share MOVE_EFFECT_RECHARGE (is_recharge),
    # but power/accuracy/pp/type/category are individually verified, NOT
    # uniform (see move_data.gd's own is_recharge doc comment for the full
    # source citations). Giga Impact is the ONLY one of the 10 with
    # makes_contact; Rock Wrecker is ballistic_move but non-contact; Meteor
    # Assault is Physical but non-contact (confirmed, not assumed).
    {"id":  63, "name": "Hyper Beam",
     "type": TYPE_NORMAL, "category": SPEC, "power": 150, "accuracy": 90, "pp": 5,
     "is_recharge": True},
    {"id":  307, "name": "Blast Burn",
     "type": TYPE_FIRE, "category": SPEC, "power": 150, "accuracy": 90, "pp": 5,
     "is_recharge": True},
    {"id":  308, "name": "Hydro Cannon",
     "type": TYPE_WATER, "category": SPEC, "power": 150, "accuracy": 90, "pp": 5,
     "is_recharge": True},
    {"id":  338, "name": "Frenzy Plant",
     "type": TYPE_GRASS, "category": SPEC, "power": 150, "accuracy": 90, "pp": 5,
     "is_recharge": True},
    {"id":  416, "name": "Giga Impact",
     "type": TYPE_NORMAL, "category": PHYS, "power": 150, "accuracy": 90, "pp": 5,
     "makes_contact": True, "is_recharge": True},
    {"id":  439, "name": "Rock Wrecker",
     "type": TYPE_ROCK, "category": PHYS, "power": 150, "accuracy": 90, "pp": 5,
     "ballistic_move": True, "is_recharge": True},
    {"id":  459, "name": "Roar of Time",
     "type": TYPE_DRAGON, "category": SPEC, "power": 150, "accuracy": 90, "pp": 5,
     "is_recharge": True},
    {"id":  665, "name": "Prismatic Laser",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 160, "accuracy": 100, "pp": 10,
     "is_recharge": True},
    {"id":  722, "name": "Meteor Assault",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 150, "accuracy": 100, "pp": 5,
     "is_recharge": True,
     "ban_flags": BAN_METRONOME},
    {"id":  723, "name": "Eternabeam",
     "type": TYPE_DRAGON, "category": SPEC, "power": 160, "accuracy": 90, "pp": 5,
     "is_recharge": True,
     "ban_flags": BAN_METRONOME},

    # ── [M19-break-protect] Feint / Shadow Force / Phantom Force / Hyperspace
    # Hole — all 4 share the identical MOVE_EFFECT_FEINT additionalEffect
    # (breaks_protect), but power/accuracy/pp/type/category/priority are NOT
    # uniform (see move_data.gd's own breaks_protect doc comment for the full
    # source citations). Feint alone is non-contact and +2 priority; Shadow
    # Force/Phantom Force are two-turn semi-invulnerable (new
    # SEMI_INV_VANISH) contact moves; Hyperspace Hole has accuracy=0
    # (never misses) and ignores_substitute, non-contact.
    {"id":  364, "name": "Feint",
     "type": TYPE_NORMAL, "category": PHYS, "power": 30, "accuracy": 100, "pp": 10,
     "priority": 2, "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "ignores_protect": True, "breaks_protect": True},
    {"id":  467, "name": "Shadow Force",
     "type": TYPE_GHOST, "category": PHYS, "power": 120, "accuracy": 100, "pp": 5,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_VANISH,
     "ban_flags": BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ASSIST,
     "ignores_protect": True, "breaks_protect": True},
    {"id":  566, "name": "Phantom Force",
     "type": TYPE_GHOST, "category": PHYS, "power": 90, "accuracy": 100, "pp": 10,
     "makes_contact": True, "two_turn": True, "semi_inv_state": SEMI_INV_VANISH,
     "ban_flags": BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ASSIST,
     "ignores_protect": True, "breaks_protect": True},
    {"id":  593, "name": "Hyperspace Hole",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 0, "pp": 5,
     "ban_flags": BAN_METRONOME,
     "ignores_protect": True, "ignores_substitute": True, "breaks_protect": True},

    # ── [M19-recoil-on-miss] Jump Kick / High Jump Kick / Axe Kick / Supercell
    # Slam — all 4 share the identical EFFECT_RECOIL_IF_MISS mechanism
    # (crashes_on_miss), a genuinely uniform crash formula (flat 50% of the
    # ATTACKER's own max HP at this project's GEN_LATEST config) despite the
    # 4 moves' own power/accuracy/pp NOT being uniform. Axe Kick additionally
    # carries its own unrelated 30% confusion secondary; Supercell Slam
    # carries double_power_on_minimized (already-existing Stomp-family
    # mechanism, reused as-is).
    {"id":  26, "name": "Jump Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 100, "accuracy": 95, "pp": 10,
     "makes_contact": True, "crashes_on_miss": True},
    {"id":  136, "name": "High Jump Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 130, "accuracy": 90, "pp": 10,
     "makes_contact": True, "crashes_on_miss": True},
    {"id":  781, "name": "Axe Kick",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 120, "accuracy": 90, "pp": 10,
     "makes_contact": True, "crashes_on_miss": True,
     "secondary_effect": SE_CONFUSION, "secondary_chance": 30},
    {"id":  844, "name": "Supercell Slam",
     "type": TYPE_ELECTRIC, "category": PHYS, "power": 100, "accuracy": 95, "pp": 15,
     "makes_contact": True, "crashes_on_miss": True, "double_power_on_minimized": True},

    # ── [M19-weather-conditional-accuracy] Thunder / Hurricane / Bleakwind
    # Storm / Wildbolt Storm / Sandsear Storm — all 5 carry
    # always_hits_in_rain; Thunder/Hurricane ADDITIONALLY carry
    # accuracy_halved_in_sun (a genuinely separate, second flag — confirmed
    # NOT shared by the "Storm" trio, which has no sun penalty at all).
    # Bleakwind Storm(774) was flagged double-blocked during
    # `[M19-secondary-stat-on-hit]` and correctly excluded from that
    # session's 79-move batch — it was NEVER previously implemented at all
    # (re-verified directly: no prior `.tres`/gen_moves.py entry existed for
    # any of these 5 IDs before this session), so this entry builds BOTH its
    # stat-on-hit secondary AND its weather-accuracy flag together, not just
    # "adding weather flags to an existing entry" as originally assumed.
    # `.windMove` (all of Hurricane/the Storm trio) is a real source flag
    # but has zero consumers anywhere in this project (no Wind Rider/Wind
    # Power-style ability implemented) — deliberately not modeled, not a
    # silently dropped check.
    {"id":  87, "name": "Thunder",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 110, "accuracy": 70, "pp": 10,
     "damages_airborne": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 30,
     "always_hits_in_rain": True, "accuracy_halved_in_sun": True},
    {"id":  542, "name": "Hurricane",
     "type": TYPE_FLYING, "category": SPEC, "power": 110, "accuracy": 70, "pp": 10,
     "damages_airborne": True, "secondary_effect": SE_CONFUSION, "secondary_chance": 30,
     "always_hits_in_rain": True, "accuracy_halved_in_sun": True},
    {"id":  774, "name": "Bleakwind Storm",
     "type": TYPE_FLYING, "category": SPEC, "power": 100, "accuracy": 80, "pp": 10,
     "is_spread": True, "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1,
     "secondary_chance": 30, "always_hits_in_rain": True},
    {"id":  775, "name": "Wildbolt Storm",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 100, "accuracy": 80, "pp": 10,
     "is_spread": True, "secondary_effect": SE_PARALYSIS, "secondary_chance": 20,
     "always_hits_in_rain": True},
    {"id":  776, "name": "Sandsear Storm",
     "type": TYPE_GROUND, "category": SPEC, "power": 100, "accuracy": 80, "pp": 10,
     "is_spread": True, "secondary_effect": SE_BURN, "secondary_chance": 20,
     "always_hits_in_rain": True},

    # ── [Bucket 4 2-move sub-groups] — 9 independent sub-groups bundled into
    # one session, matching [Bucket 4 cheapest singles]'s established
    # precedent. Each sub-group's own mechanism verified individually from
    # source — none share a mechanism just because they're bundled together.

    # M19-percent-current-hp-damage: EFFECT_FIXED_PERCENT_DAMAGE, both share
    # the literal same 50% figure.
    {"id":  162, "name": "Super Fang",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 90, "pp": 10,
     "makes_contact": True, "percent_current_hp_damage": 50},
    {"id":  803, "name": "Ruination",
     "type": TYPE_DARK, "category": SPEC, "power": 1, "accuracy": 90, "pp": 10,
     "ban_flags": BAN_METRONOME, "percent_current_hp_damage": 50},

    # M19-ignores-stat-stages: ignoresTargetDefenseEvasionStages, reuses the
    # SAME insertion points Unaware already established (no new mechanism).
    {"id":  498, "name": "Chip Away",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "makes_contact": True, "ignores_defense_evasion_stages": True},
    {"id":  533, "name": "Sacred Sword",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 90, "accuracy": 100, "pp": 15,
     "makes_contact": True, "slicing_move": True, "ignores_defense_evasion_stages": True},
    {"id":  626, "name": "Darkest Lariat",
     "type": TYPE_DARK, "category": PHYS, "power": 85, "accuracy": 100, "pp": 10,
     "makes_contact": True, "ignores_defense_evasion_stages": True},

    # M19-charge-turn-spatk-boost: MOVE_EFFECT_STAT_PLUS spAtk=1 onChargeTurnOnly
    # — a parallel field to Skull Bash's charge_turn_defense_boost. Electro
    # Shot ADDITIONALLY skips its charge turn in rain (Meteor Beam does not
    # — confirmed individually, not assumed symmetric).
    {"id":  728, "name": "Meteor Beam",
     "type": TYPE_ROCK, "category": SPEC, "power": 120, "accuracy": 90, "pp": 10,
     "two_turn": True, "charge_turn_spatk_boost": 1,
     "ban_flags": BAN_SLEEP_TALK},
    {"id":  833, "name": "Electro Shot",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 130, "accuracy": 100, "pp": 10,
     "two_turn": True, "charge_turn_spatk_boost": 1, "skips_charge_in_rain": True,
     "ban_flags": BAN_SLEEP_TALK},

    # M19-hp-based-power: EFFECT_FLAIL, both share the literal same banded
    # power-from-own-missing-HP formula.
    {"id":  175, "name": "Flail",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 15,
     "makes_contact": True, "is_flail_power": True},
    {"id":  179, "name": "Reversal",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 1, "accuracy": 100, "pp": 15,
     "makes_contact": True, "is_flail_power": True},

    # M19-stat-raised-trigger: onlyIfTargetRaisedStats, chance=100 (guaranteed
    # IF the condition is met — a true secondary, still subject to Shield
    # Dust/Covert Cloak/Sheer Force/Serene Grace like any other chance>0 SE).
    {"id":  735, "name": "Burning Jealousy",
     "type": TYPE_FIRE, "category": SPEC, "power": 70, "accuracy": 100, "pp": 5,
     "is_spread": True, "secondary_effect": SE_BURN, "secondary_chance": 100,
     "requires_target_stat_raised": True},
    {"id":  842, "name": "Alluring Voice",
     "type": TYPE_FAIRY, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "sound_move": True, "ignores_substitute": True, "secondary_effect": SE_CONFUSION,
     "secondary_chance": 100, "requires_target_stat_raised": True},

    # M19-random-status-choice: two genuinely DIFFERENT pools (confirmed
    # individually from source, not shared) — Tri Attack's real 3rd option
    # (freeze-or-frostbite) resolves to plain STATUS_FREEZE, no
    # STATUS_FROSTBITE exists anywhere in this project.
    {"id":  161, "name": "Tri Attack",
     "type": TYPE_NORMAL, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_RANDOM_STATUS, "secondary_chance": 20,
     "random_status_pool": [STATUS_BURN, STATUS_FREEZE, STATUS_PARALYSIS]},
    {"id":  755, "name": "Dire Claw",
     "type": TYPE_POISON, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True, "secondary_effect": SE_RANDOM_STATUS, "secondary_chance": 50,
     "random_status_pool": [STATUS_POISON, STATUS_PARALYSIS, STATUS_SLEEP]},

    # M19-self-faint: .explosion=TRUE, unconditional self-KO regardless of
    # hit/miss, Damp-blocked.
    # [M21] target_includes_ally: also hits the user's own ally in doubles
    # (TARGET_FOES_AND_ALLY), confirmed from source alongside is_spread.
    {"id":  120, "name": "Self-Destruct",
     "type": TYPE_NORMAL, "category": PHYS, "power": 200, "accuracy": 100, "pp": 5,
     "is_spread": True, "is_self_faint": True, "target_includes_ally": True},
    {"id":  153, "name": "Explosion",
     "type": TYPE_NORMAL, "category": PHYS, "power": 250, "accuracy": 100, "pp": 5,
     "is_spread": True, "is_self_faint": True, "target_includes_ally": True},

    # M19-berry-steal: MOVE_EFFECT_BUG_BITE, both share the literal same
    # steal-and-immediately-eat mechanism (Pluck's own name is a historical
    # artifact, not a distinct mechanism).
    {"id":  365, "name": "Pluck",
     "type": TYPE_FLYING, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "steals_and_eats_berry": True},
    {"id":  450, "name": "Bug Bite",
     "type": TYPE_BUG, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "steals_and_eats_berry": True},

    # M19-ignores-target-ability: ignoresTargetAbility — the LITERAL SAME
    # moldBreakerActive flag Mold Breaker itself sets, confirmed from source.
    {"id":  667, "name": "Sunsteel Strike",
     "type": TYPE_STEEL, "category": PHYS, "power": 100, "accuracy": 100, "pp": 5,
     "makes_contact": True, "ignores_target_ability": True,
     "ban_flags": BAN_METRONOME},
    {"id":  668, "name": "Moongeist Beam",
     "type": TYPE_GHOST, "category": SPEC, "power": 100, "accuracy": 100, "pp": 5,
     "ignores_target_ability": True,
     "ban_flags": BAN_METRONOME},

    # ── [M19-steal-stats] / [M19-ally-targeting-stat-change] ──
    # Spectral Thief(666): preAttackEffect steal of the target's positive
    # stat stages (all 7, incl. Accuracy/Evasion) onto the attacker. See
    # move_data.gd's steals_positive_stat_stages field doc comment and
    # BattleManager's own call-site comment for full source citations.
    {"id":  666, "name": "Spectral Thief",
     "type": TYPE_GHOST, "category": PHYS, "power": 90, "accuracy": 100, "pp": 10,
     "makes_contact": True, "ignores_substitute": True,
     "ban_flags": BAN_METRONOME, "steals_positive_stat_stages": True},

    # Howl(336): TARGET_USER_AND_ALLY at GEN_LATEST — self +1 Atk (ordinary
    # stat_change_self) plus the same +1 bolted onto the user's ally
    # (also_boosts_ally, a no-op in singles).
    {"id":  336, "name": "Howl",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "sound_move": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 1, "stat_change_self": True,
     "also_boosts_ally": True, "snatch_affected": True},

    # Aromatic Mist(597): TARGET_ALLY only, +1 SpDef on the ally, fails if
    # not doubles (see BattleManager's _get_ally-based dispatch).
    {"id":  597, "name": "Aromatic Mist",
     "type": TYPE_FAIRY, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "ignores_substitute": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_SPDEF, "stat_change_amount": 1,
     "stat_change_target_ally": True},

    # Coaching(739): TARGET_ALLY only, +1 Atk / +1 Def on the ally (2-stat
    # payload via the existing extra_stat_change_stats/amounts mechanism).
    {"id":  739, "name": "Coaching",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_DEF], "extra_stat_change_amounts": [1],
     "stat_change_target_ally": True},

    # ── [M19e] Weather-conditional heal family ──
    # Morning Sun(234)/Synthesis(235)/Moonlight(236): share the sun-boosted
    # (2/3), no-weather (1/2), other-weather (1/4) formula.
    {"id":  234, "name": "Morning Sun",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True,
     "heals_based_on_weather": True, "weather_heal_boost_type": WEATHER_SUN,
     "weather_heal_has_quarter_branch": True, "snatch_affected": True, "healing_move": True,},
    {"id":  235, "name": "Synthesis",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True,
     "heals_based_on_weather": True, "weather_heal_boost_type": WEATHER_SUN,
     "weather_heal_has_quarter_branch": True, "snatch_affected": True, "healing_move": True,},
    {"id":  236, "name": "Moonlight",
     "type": TYPE_FAIRY, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True,
     "heals_based_on_weather": True, "weather_heal_boost_type": WEATHER_SUN,
     "weather_heal_has_quarter_branch": True, "snatch_affected": True, "healing_move": True,},
    # Shore Up(622): sandstorm-boosted (2/3) / else (1/2) — no 1/4 branch at
    # all, a genuine non-uniformity within this sub-group (confirmed from
    # source, not assumed symmetric with the 3 sun-based moves above).
    {"id":  622, "name": "Shore Up",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True,
     "heals_based_on_weather": True, "weather_heal_boost_type": WEATHER_SANDSTORM,
     "weather_heal_has_quarter_branch": False, "snatch_affected": True, "healing_move": True,},

    # ── [M19f] Escape-prevention family ──
    # Spider Web(169): ignoresProtect=FALSE at GEN_LATEST (a real asymmetry
    # with Mean Look/Block below, confirmed individually from source).
    {"id":  169, "name": "Spider Web",
     "type": TYPE_BUG, "category": STAT, "accuracy": 0, "pp": 10,
     "bounceable": True, "is_mean_look": True},
    # Mean Look(212)/Block(335): ignoresProtect=TRUE at GEN_LATEST
    # (B_UPDATED_MOVE_FLAGS >= GEN_6).
    {"id":  212, "name": "Mean Look",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "bounceable": True, "is_mean_look": True},
    {"id":  335, "name": "Block",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "bounceable": True, "is_mean_look": True},
    # Spirit Shackle(625): damaging move, SE_PREVENT_ESCAPE secondary at
    # explicit chance=100 (a true secondary — Shield Dust/Covert Cloak/Sheer
    # Force all correctly apply, unlike Mean Look/Block/Spider Web's own
    # guaranteed-by-construction pure-status dispatch). No makesContact in
    # source, no Ghost-type immunity (see move_data.gd's SE_PREVENT_ESCAPE
    # doc comment for the source-confirmed asymmetry with is_mean_look).
    {"id":  625, "name": "Spirit Shackle",
     "type": TYPE_GHOST, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "secondary_effect": SE_PREVENT_ESCAPE, "secondary_chance": 100},
    # Jaw Lock(692): the bidirectional variant (traps user AND target).
    # Guaranteed (no .chance field in source -> secondary_chance=0).
    {"id":  692, "name": "Jaw Lock",
     "type": TYPE_DARK, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "biting_move": True,
     "secondary_effect": SE_TRAP_BOTH, "secondary_chance": 0},

    # ── [M19c] Protect-family variants — all share is_protect's existing
    # dispatch (.effect = EFFECT_PROTECT in source, same as Protect/Detect),
    # distinguished only by protect_method. ──
    # Wide Guard(469): side-wide, blocks only SPREAD moves (is_spread).
    {"id":  469, "name": "Wide Guard",
     "type": TYPE_ROCK, "category": STAT, "accuracy": 0, "pp": 10, "priority": 3,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME,
     "is_protect": True, "protect_method": PROTECT_METHOD_WIDE_GUARD, "snatch_affected": True},
    # Quick Guard(501): side-wide, blocks only PRIORITY>0 moves (ability-boosted).
    {"id":  501, "name": "Quick Guard",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 0, "pp": 15, "priority": 3,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME,
     "is_protect": True, "protect_method": PROTECT_METHOD_QUICK_GUARD, "snatch_affected": True},
    # Spiky Shield(596): blocks everything; contact -> maxHP/8 recoil to attacker.
    {"id":  596, "name": "Spiky Shield",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 0, "pp": 10, "priority": 4,
     "ignores_protect": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (whole Protect family).
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "is_protect": True, "protect_method": PROTECT_METHOD_SPIKY_SHIELD},
    # Baneful Bunker(624): blocks everything; contact -> poisons attacker.
    {"id":  624, "name": "Baneful Bunker",
     "type": TYPE_POISON, "category": STAT, "accuracy": 0, "pp": 10, "priority": 4,
     "ignores_protect": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (whole Protect family).
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "is_protect": True, "protect_method": PROTECT_METHOD_BANEFUL_BUNKER},
    # Obstruct(720): blocks only NON-STATUS moves; contact -> -2 Def on attacker.
    # accuracy=100 in source (functionally moot -- is_protect dispatch fires
    # before any accuracy check), recorded for data fidelity only.
    {"id":  720, "name": "Obstruct",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 10, "priority": 4,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME,
     "is_protect": True, "protect_method": PROTECT_METHOD_OBSTRUCT},
    # Silk Trap(780): blocks only NON-STATUS moves; contact -> -1 Speed on attacker.
    {"id":  780, "name": "Silk Trap",
     "type": TYPE_BUG, "category": STAT, "accuracy": 0, "pp": 10, "priority": 4,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME,
     "is_protect": True, "protect_method": PROTECT_METHOD_SILK_TRAP},
    # Burning Bulwark(836): blocks everything; contact -> burns attacker.
    {"id":  836, "name": "Burning Bulwark",
     "type": TYPE_FIRE, "category": STAT, "accuracy": 0, "pp": 10, "priority": 4,
     "ignores_protect": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (whole Protect family).
     "ban_flags": (BAN_MIRROR_MOVE | BAN_COPYCAT | BAN_ASSIST),
     "is_protect": True, "protect_method": PROTECT_METHOD_BURNING_BULWARK},

    # ── [M19d] Counter/Mirror-Move remnants ──
    # Metal Burst(368): EFFECT_REFLECT_DAMAGE like Counter/Mirror Coat, but
    # 1.5x (not 2x) and BOTH categories (not one) -- priority=0, NOT -5, a
    # real asymmetry with Counter/Mirror Coat despite the shared handler.
    # NOT metronome-banned in source (unlike Counter/Mirror Coat, which are).
    {"id":  368, "name": "Metal Burst",
     "type": TYPE_STEEL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 10,
     # [D4 Bundle 4] meFirstBanned=TRUE (the reflect-damage family; NOT
     # copycat/assistBanned — confirmed via direct source read those two
     # flags are only set on Counter/Mirror Coat, not Metal Burst).
     "ban_flags": BAN_ME_FIRST,
     "metal_burst": True},
    # Mirror Move(119): repeats the move that hit the user this turn (NOT the
    # target's own last-used move -- a different tracking axis, see
    # move_data.gd's own doc comment). Metronome/Mirror-Move-banned in source.
    {"id":  119, "name": "Mirror Move",
     "type": TYPE_FLYING, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     # [Mimic/Sketch] mimicBanned=TRUE added (was missing).
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST | BAN_MIMIC | BAN_SLEEP_TALK | BAN_ENCORE),
     "is_mirror_move": True},

    # ── [D0] Priority unblock: Leech Seed / Haze / Aromatherapy+Heal Bell ──
    # Leech Seed(73): foe-targeting, own dedicated Grass-immune check (not
    # the general type gate), blocked by Substitute (no ignoresSubstitute
    # in source), bounceable (magicCoatAffected=TRUE).
    {"id":   73, "name": "Leech Seed",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 90, "pp": 10,
     "bounceable": True, "is_leech_seed": True},
    # Haze(114): field-wide (TARGET_FIELD), ignoresProtect/ignoresSubstitute
    # both TRUE in source (moot in practice — is_haze's own dispatch doesn't
    # check either, matching this project's other field-wide-effect moves).
    {"id":  114, "name": "Haze",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_haze": True},
    # Heal Bell(215): soundMove=TRUE (the Soundproof-partner gate applies);
    # Aromatherapy(312): NOT a sound move (the Soundproof-partner gate never
    # blocks it) — see move_data.gd's is_heal_bell doc comment for the full
    # asymmetry citation.
    {"id":  215, "name": "Heal Bell",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE,
     "sound_move": True, "is_heal_bell": True, "snatch_affected": True},
    {"id":  312, "name": "Aromatherapy",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_heal_bell": True, "snatch_affected": True},

    # ── [D0] Follow Me / Rage Powder — mechanism already fully built (M14b),
    # near-pure data entry against an already-tested dispatch. Rage Powder
    # carries powderMove=TRUE (Follow Me does not) — a REAL correction to
    # this sub-group's own original Step 0 assumption: the general
    # Soundproof/Bulletproof-shaped blocks_move_flag gate checks `defender`,
    # which for this self-targeted move resolves to the DEFAULT-SELECTED
    # opponent, NOT the attacker itself, so it does NOT grant Grass-type/
    # Overcoat immunity "for free" as first assumed — the is_follow_me
    # dispatch itself now checks blocks_move_flag against the ATTACKER
    # explicitly (one small addition, still zero new AbilityManager code). ──
    {"id":  266, "name": "Follow Me",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20, "priority": 2,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "is_follow_me": True},
    {"id":  476, "name": "Rage Powder",
     "type": TYPE_BUG, "category": STAT, "accuracy": 0, "pp": 20, "priority": 2,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "powder_move": True, "is_follow_me": True},

    # ── [D0] Soft-Boiled / Milk Drink — EFFECT_SOFTBOILED, functionally
    # identical to the already-implemented EFFECT_RESTORE_HP family
    # (Recover/Slack Off/Heal Order) — confirmed individually from source
    # rather than assumed duplicated, genuinely identical data. ──
    {"id":  135, "name": "Soft-Boiled",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True, "snatch_affected": True},
    {"id":  208, "name": "Milk Drink",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "is_restore_hp": True, "healing_move": True, "snatch_affected": True},

    # ── [D0] Sappy Seed / Freezy Frost / Sparkly Swirl — the 3 moves Bucket
    # 4's M19-blocked-on-other-tier4 sub-group was gated on, now unblocked.
    # All 3 are EFFECT_HIT damage moves with a GUARANTEED (no .chance field)
    # additional effect reusing the 3 primitives directly above verbatim. ──
    {"id":  685, "name": "Sappy Seed",
     "type": TYPE_GRASS, "category": PHYS, "power": 100, "accuracy": 90, "pp": 10,
     "is_leech_seed_on_hit": True,
     "ban_flags": BAN_METRONOME},
    {"id":  686, "name": "Freezy Frost",
     "type": TYPE_ICE, "category": SPEC, "power": 100, "accuracy": 90, "pp": 10,
     "is_haze_on_hit": True,
     "ban_flags": BAN_METRONOME},
    {"id":  687, "name": "Sparkly Swirl",
     "type": TYPE_FAIRY, "category": SPEC, "power": 120, "accuracy": 85, "pp": 5,
     "is_heal_bell_on_hit": True,
     "ban_flags": BAN_METRONOME},

    # ── [D1] Solar Blade / Snipe Shot / Hidden Power / Hyperspace Fury —
    # 4 "already effectively free" moves flagged by the Section D recon,
    # each reusing infrastructure this project already built and tested. ──
    # Solar Blade(632): shares .effect=EFFECT_SOLAR_BEAM with Solar Beam(76)
    # itself — same is_solar_beam charge-skip-in-sun dispatch, category-
    # agnostic. Physical (Solar Beam is Special), makesContact, slicingMove.
    # FLAGGED not fixed: Solar Beam's own rain/sand/hail/fog damage-halving
    # was never implemented in this project (only the charge-skip half) —
    # Solar Blade ships with the same incomplete-but-consistent behavior.
    {"id":  632, "name": "Solar Blade",
     "type": TYPE_GRASS, "category": PHYS, "power": 125, "accuracy": 100, "pp": 10,
     "makes_contact": True, "slicing_move": True,
     "two_turn": True, "is_solar_beam": True,
     "ban_flags": BAN_SLEEP_TALK},
    # Snipe Shot(691): bypasses BOTH Follow-Me/Rage-Powder AND Lightning-Rod/
    # Storm-Drain redirect at the SAME chokepoint Propeller Tail/Stalwart's
    # ability check already occupies — new ignores_redirection move flag.
    {"id":  691, "name": "Snipe Shot",
     "type": TYPE_WATER, "category": SPEC, "power": 80, "accuracy": 100, "pp": 15,
     "critical_hit_stage": 1, "ignores_redirection": True},
    # Hidden Power(237): type is IV-derived (is_hidden_power, computed in
    # DamageCalculator._hidden_power_type); power is a FLAT 60 at this
    # project's GEN_LATEST config (B_HIDDEN_POWER_DMG >= GEN_6 fixes power,
    # the classic bit-parity power formula is dead code here) — a real
    # correction to the recon's own "power AND type from IVs" framing.
    {"id":  237, "name": "Hidden Power",
     "type": TYPE_NORMAL, "category": SPEC, "power": 60, "accuracy": 100, "pp": 15,
     "is_hidden_power": True},
    # Hyperspace Fury(621): its own distinct .effect=EFFECT_HYPERSPACE_FURY,
    # but battleScript=BattleScript_EffectHit — functionally identical to a
    # plain EFFECT_HIT move. Reuses breaks_protect ([M19-break-protect])
    # directly for its Feint-shaped protect-break, plus a GUARANTEED
    # (secondary_chance=0, the same shape M19-secondary-stat-on-hit's own
    # guaranteed self-drops use) self -1 Defense via the existing
    # stat_change_stat/amount/self fields — zero new mechanism, pure
    # composition of 2 already-shipped pieces.
    {"id":  621, "name": "Hyperspace Fury",
     "type": TYPE_DARK, "category": PHYS, "power": 100, "accuracy": 0, "pp": 5,
     "ban_flags": (BAN_METRONOME | BAN_SKETCH),
     "ignores_protect": True, "ignores_substitute": True, "breaks_protect": True,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1, "stat_change_self": True},

    # ── [D1] EFFECT_WEATHER: Sandstorm/Rain Dance/Sunny Day/Hail/Snowscape —
    # reuses BattleManager.try_set_weather directly. Snowscape maps to the
    # same WEATHER_HAIL constant Hail/Snow Warning already use (see
    # weather_type's own doc comment for the FLAGGED Hail/Snow split gap). ──
    {"id":  201, "name": "Sandstorm",
     "type": TYPE_ROCK, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": BAN_MIRROR_MOVE, "weather_type": WEATHER_SANDSTORM, "ignores_protect": True,},
    {"id":  240, "name": "Rain Dance",
     "type": TYPE_WATER, "category": STAT, "accuracy": 0, "pp": 5,
     "ban_flags": BAN_MIRROR_MOVE, "weather_type": WEATHER_RAIN, "ignores_protect": True,},
    {"id":  241, "name": "Sunny Day",
     "type": TYPE_FIRE, "category": STAT, "accuracy": 0, "pp": 5,
     "ban_flags": BAN_MIRROR_MOVE, "weather_type": WEATHER_SUN, "ignores_protect": True,},
    {"id":  258, "name": "Hail",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": BAN_MIRROR_MOVE, "weather_type": WEATHER_HAIL, "ignores_protect": True,},
    {"id":  809, "name": "Snowscape",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME, "weather_type": WEATHER_HAIL, "ignores_protect": True,},

    # ── [D1] EFFECT_POWER_BASED_ON_USER_HP: Eruption/Water Spout/Dragon
    # Energy — continuous power_scales_with_user_hp, all uniform data. ──
    # [NEW ITEM A] is_spread=True on all 3: real source .target=TARGET_BOTH,
    # was missing entirely. Confirmed `_dmg_power_override` (which
    # power_scales_with_user_hp feeds) is computed ONCE, before the spread/
    # single split, from attacker.current_hp/max_hp — unaffected by target
    # count, applied identically to every target in the spread loop. No
    # per-target power divergence risk.
    {"id":  284, "name": "Eruption",
     "type": TYPE_FIRE, "category": SPEC, "power": 150, "accuracy": 100, "pp": 5,
     "power_scales_with_user_hp": True, "is_spread": True},
    {"id":  323, "name": "Water Spout",
     "type": TYPE_WATER, "category": SPEC, "power": 150, "accuracy": 100, "pp": 5,
     "power_scales_with_user_hp": True, "is_spread": True},
    {"id":  748, "name": "Dragon Energy",
     "type": TYPE_DRAGON, "category": SPEC, "power": 150, "accuracy": 100, "pp": 5,
     "ban_flags": BAN_METRONOME, "power_scales_with_user_hp": True, "is_spread": True},

    # ── [D1] EFFECT_POWER_BASED_ON_TARGET_HP: Wring Out/Crush Grip/Hard
    # Press — continuous power_scales_with_target_hp. Hard Press is a real
    # non-uniformity (100/10, not 120/5, and Physical not Special). ──
    {"id":  378, "name": "Wring Out",
     "type": TYPE_NORMAL, "category": SPEC, "power": 120, "accuracy": 100, "pp": 5,
     "makes_contact": True, "power_scales_with_target_hp": True},
    {"id":  462, "name": "Crush Grip",
     "type": TYPE_NORMAL, "category": PHYS, "power": 120, "accuracy": 100, "pp": 5,
     "makes_contact": True, "power_scales_with_target_hp": True},
    {"id":  840, "name": "Hard Press",
     "type": TYPE_STEEL, "category": PHYS, "power": 100, "accuracy": 100, "pp": 10,
     "makes_contact": True, "power_scales_with_target_hp": True},

    # ── [D1] EFFECT_STEAL_ITEM: Thief/Covet — reuses
    # AbilityManager.try_thief_steal (the Pickpocket/Magician primitive). ──
    {"id":  168, "name": "Thief",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "ban_flags": BAN_ME_FIRST | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "steals_item_if_itemless": True},
    {"id":  343, "name": "Covet",
     "type": TYPE_NORMAL, "category": PHYS, "power": 60, "accuracy": 100, "pp": 25,
     "makes_contact": True, "ban_flags": BAN_ME_FIRST | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST,
     "steals_item_if_itemless": True},

    # ── [D1] EFFECT_LOCK_ON: Mind Reader/Lock-On — sets sure_hit_target,
    # bypassing accuracy AND semi-invulnerability on the user's next hit. ──
    {"id":  170, "name": "Mind Reader",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "is_lock_on": True},
    {"id":  199, "name": "Lock-On",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "is_lock_on": True},

    # ── [D1] EFFECT_SWAGGER: Swagger/Flatter — raises the TARGET's stat AND
    # confuses it; Own Tempo blocks the WHOLE move (see is_swagger's own
    # doc comment for the real correction found at Step 0). Accuracy
    # genuinely non-uniform (85 vs 100), confirmed individually. ──
    {"id":  207, "name": "Swagger",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 85, "pp": 15,
     "bounceable": True, "is_swagger": True,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 2},
    {"id":  260, "name": "Flatter",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 15,
     "bounceable": True, "is_swagger": True,
     "stat_change_stat": STAGE_SPATK, "stat_change_amount": 1},

    # ── [D1] EFFECT_SUCKER_PUNCH: Sucker Punch/Thunderclap — fails if the
    # target already acted or chose a status move. Thunderclap is Special
    # (Sucker Punch Physical), a real category difference. ──
    {"id":  389, "name": "Sucker Punch",
     "type": TYPE_DARK, "category": PHYS, "power": 70, "accuracy": 100, "pp": 5,
     "priority": 1, "makes_contact": True, "is_sucker_punch": True},
    {"id":  837, "name": "Thunderclap",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 70, "accuracy": 100, "pp": 5,
     "priority": 1, "is_sucker_punch": True},

    # ── [D1] EFFECT_STORED_POWER: Stored Power/Power Trip — power scales
    # with the sum of positive stat-stage MAGNITUDES (all 7 stats). ──
    {"id":  500, "name": "Stored Power",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 20, "accuracy": 100, "pp": 10,
     "is_stored_power": True},
    {"id":  644, "name": "Power Trip",
     "type": TYPE_DARK, "category": PHYS, "power": 20, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_stored_power": True},

    # ── [D2 batch] On-hit hazard/screen family ──────────────────────────────
    # EFFECT_STONE_AXE/EFFECT_CEASELESS_EDGE: guaranteed on-hit hazard set on
    # the TARGET's side (MoveEnd-dispatch, not the standard secondary-effect
    # mechanism — source's own sheerForceOverride=TRUE is a flagged, not
    # fixed, gap, see sets_stealth_rock_on_hit/sets_spikes_on_hit's own
    # doc comment).
    {"id":  758, "name": "Stone Axe",
     "type": TYPE_ROCK, "category": PHYS, "power": 65, "accuracy": 90, "pp": 15,
     "makes_contact": True, "slicing_move": True, "sets_stealth_rock_on_hit": True},
    {"id":  773, "name": "Ceaseless Edge",
     "type": TYPE_DARK, "category": PHYS, "power": 65, "accuracy": 90, "pp": 15,
     "makes_contact": True, "slicing_move": True, "sets_spikes_on_hit": True},

    # Ice Spinner(789): a real correction found at Step 0 — EFFECT_ICE_SPINNER
    # removes TERRAIN, not hazards (a genuinely different effect from
    # EFFECT_RAPID_SPIN despite the D2 recon's own "clears hazards" framing).
    # Terrain is permanently void in this project (`[M17d]`), so this reduces
    # to a plain damage move with no working secondary — no flag needed.
    {"id":  789, "name": "Ice Spinner",
     "type": TYPE_ICE, "category": PHYS, "power": 80, "accuracy": 100, "pp": 15,
     "makes_contact": True},

    # Mortal Spin(794): shares the LITERAL SAME EFFECT_RAPID_SPIN as Rapid
    # Spin(229) itself — is_rapid_spin applies unmodified, clearing one
    # hazard from the ATTACKER's own side. Plus a guaranteed 100% Poison
    # secondary via the existing generic fields. TARGET_BOTH in source
    # (hits every opposing battler in doubles) → is_spread.
    {"id":  794, "name": "Mortal Spin",
     "type": TYPE_POISON, "category": PHYS, "power": 30, "accuracy": 100, "pp": 15,
     "makes_contact": True, "is_spread": True, "is_rapid_spin": True,
     "secondary_effect": SE_POISON, "secondary_chance": 100},

    # Tidy Up(808): confirmed BROADER than the D2 recon's own framing — also
    # clears every Substitute on the field, not just hazards (see is_tidy_up's
    # own doc comment). ignoresProtect=TRUE in source.
    {"id":  808, "name": "Tidy Up",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_tidy_up": True,
     "stat_change_self": True, "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_SPEED], "extra_stat_change_amounts": [1],
     "ban_flags": BAN_METRONOME},

    # Defog(432): confirmed BROADER than the D2 recon's own "clear + evasion
    # drop" framing — clears the TARGET's screens (Reflect/Light Screen/
    # Aurora Veil only, this project's implemented subset) AND hazards from
    # BOTH sides (see is_defog's own doc comment). magicCoatAffected=TRUE at
    # this project's GEN_LATEST config → bounceable.
    {"id":  432, "name": "Defog",
     "type": TYPE_FLYING, "category": STAT, "accuracy": 0, "pp": 15,
     "bounceable": True, "is_defog": True,
     "stat_change_stat": STAGE_EVASION, "stat_change_amount": -1},

    # ── [D2 batch] Ability-manipulation family ──────────────────────────────
    # Role Play(272): attacker copies target's ability. ignoresProtect=TRUE
    # AND ignoresSubstitute=TRUE in source — a real asymmetry within this
    # family (Skill Swap/Heart Swap below do NOT ignore Protect).
    {"id":  272, "name": "Role Play",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True, "is_role_play": True},

    # Skill Swap(285): bidirectional ability swap, reuses Wandering Spirit's
    # exact mechanism (`[M17h]`). ignoresSubstitute=TRUE, NOT ignoresProtect.
    {"id":  285, "name": "Skill Swap",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_substitute": True, "is_skill_swap": True},

    # Worry Seed(388): overwrites the target's ability with Insomnia
    # (ability_id=15) specifically. Real accuracy check (100), NOT
    # ignoresSubstitute/ignoresProtect — a fully normal foe-targeting status
    # move otherwise. magicCoatAffected=TRUE → bounceable.
    {"id":  388, "name": "Worry Seed",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 100, "pp": 10,
     "bounceable": True, "overwrite_target_ability_id": 15},

    # Heart Swap(391): confirmed NOT an ability move despite the family label
    # — swaps all 7 stat STAGES bidirectionally (Psych Up's own shape,
    # `[M16e]`, but a genuine swap not a one-directional copy).
    # ignoresSubstitute=TRUE, NOT ignoresProtect (same asymmetry as Skill
    # Swap, not Role Play).
    {"id":  391, "name": "Heart Swap",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_substitute": True, "is_heart_swap": True},

    # ── [D2 batch 2] Offense-stat-source-override family ────────────────────
    # Foul Play(492): damage off the TARGET's own Attack stat/stage, not the
    # attacker's. Category stays fixed Physical for every other purpose.
    {"id":  492, "name": "Foul Play",
     "type": TYPE_DARK, "category": PHYS, "power": 95, "accuracy": 100, "pp": 15,
     "makes_contact": True, "is_foul_play": True},

    # Body Press(704): damage off the USER's own Defense stat/stage instead
    # of Attack. Wonder Room's edge case is permanently moot (unimplemented).
    {"id":  704, "name": "Body Press",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 80, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_body_press": True,
     "ban_flags": BAN_METRONOME},

    # Photon Geyser(675): a real hidden second effect found at Step 0 — the
    # move's own CATEGORY dynamically swaps (Special->Physical) based on the
    # attacker's stage-adjusted Atk vs SpAtk, not just a raw stat lookup (see
    # is_photon_geyser's own doc comment). ignoresTargetAbility=TRUE reuses
    # the EXISTING mechanism directly.
    {"id":  675, "name": "Photon Geyser",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 100, "accuracy": 100, "pp": 5,
     "is_photon_geyser": True, "ignores_target_ability": True,
     "ban_flags": BAN_METRONOME},

    # ── [D2 batch 2] Per-mon TypeChart-override family ──────────────────────
    # Freeze-Dry(573): forces the Water-type component to a flat 2.0
    # regardless of the real chart value (Water is normally neutral to Ice,
    # not resistant). Also carries a genuine 10% Freeze secondary the D2
    # recon never flagged, reusing the existing SE_FREEZE token verbatim.
    {"id":  573, "name": "Freeze-Dry",
     "type": TYPE_ICE, "category": SPEC, "power": 70, "accuracy": 100, "pp": 20,
     "super_effective_vs_type": TYPE_WATER,
     "secondary_effect": SE_FREEZE, "secondary_chance": 10},

    # Tar Shot(695): permanent per-mon flag doubling Fire-move effectiveness
    # (a flat post-combination multiplier, NOT per-defending-type-component
    # like Freeze-Dry above — see is_tar_shot's own doc comment). Guaranteed
    # -1 Speed, but confirmed an ALL-OR-NOTHING gate with the flag-set — an
    # already-tar-shot'd target blocks the Speed drop too.
    {"id":  695, "name": "Tar Shot",
     "type": TYPE_ROCK, "category": STAT, "accuracy": 100, "pp": 15,
     "bounceable": True, "is_tar_shot": True,
     "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1},

    # Foresight(193)/Odor Sleuth(316): confirmed genuinely identical
    # (literal same EFFECT_FORESIGHT) — permanent per-target volatile,
    # bypasses this project's own Ghost-type Normal/Fighting immunity AND
    # ignores the target's own evasion stage. ignoresSubstitute=TRUE,
    # magicCoatAffected=TRUE at this project's config -> bounceable.
    {"id":  193, "name": "Foresight",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_substitute": True, "bounceable": True, "is_foresight": True},
    {"id":  316, "name": "Odor Sleuth",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_substitute": True, "bounceable": True, "is_foresight": True},

    # ── [D3 turn-order/event-tracker batch] Turn-order-manipulation family ──
    # After You(495): pushes the target to act immediately next. Fails if the
    # target already acted. ignoresProtect=TRUE, ignoresSubstitute=TRUE.
    {"id":  495, "name": "After You",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "ignores_substitute": True, "is_after_you": True,
     "ban_flags": BAN_METRONOME},

    # Quash(511): pushes the target to act last among remaining battlers.
    # Fails if the target already acted.
    {"id":  511, "name": "Quash",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 15,
     "is_quash": True,
     "ban_flags": BAN_METRONOME},

    # Upper Hand(846): priority +3 damaging move that only connects if the
    # target's own chosen move is itself priority [1,3] and hasn't acted yet
    # — re-checked via the SAME ability-boosted priority function real
    # turn-order sorting uses. Guaranteed flinch via the existing generic
    # SE_FLINCH secondary (chance 100) once connected.
    {"id":  846, "name": "Upper Hand",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 65, "accuracy": 100, "pp": 15,
     "priority": 3, "makes_contact": True, "is_upper_hand": True,
     "secondary_effect": SE_FLINCH, "secondary_chance": 100},

    # Instruct(652): forces the target to immediately re-use its own last
    # move, free of PP cost (a called move). ignoresSubstitute=TRUE.
    {"id":  652, "name": "Instruct",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_substitute": True, "is_instruct": True,
     "ban_flags": BAN_METRONOME},

    # ── [D3 turn-order/event-tracker batch] "Event happened this
    # turn/battle" tracker family ────────────────────────────────────────
    # Lash Out(736): power doubles if the user's own stat was lowered this
    # turn, by any source.
    {"id":  736, "name": "Lash Out",
     "type": TYPE_DARK, "category": PHYS, "power": 75, "accuracy": 100, "pp": 5,
     "makes_contact": True, "is_lash_out": True},

    # Retaliate(514): power doubles if a Pokémon on the user's own side
    # fainted during the previous turn.
    {"id":  514, "name": "Retaliate",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 5,
     "makes_contact": True, "is_retaliate": True},

    # Rage Fist(815): power increases +50 per prior hit taken this battle
    # (a battle-lifetime counter), capped at 350 total.
    {"id":  815, "name": "Rage Fist",
     "type": TYPE_GHOST, "category": PHYS, "power": 50, "accuracy": 100, "pp": 10,
     "makes_contact": True, "punching_move": True, "is_rage_fist": True,
     "ban_flags": BAN_METRONOME},

    # Echoed Voice(497): power scales with a field-wide consecutive-turn-use
    # counter (capped at +4x), reset the instant a turn passes without use.
    {"id":  497, "name": "Echoed Voice",
     "type": TYPE_NORMAL, "category": SPEC, "power": 40, "accuracy": 100, "pp": 15,
     "sound_move": True, "is_echoed_voice": True, "ignores_substitute": True,},

    # ── [Delayed-effect family] Per-slot delayed scheduler ──────────────────
    # Future Sight(248)/Doom Desire(353): schedule a hit resolving 2 turns
    # later against whoever occupies the target's slot then. No accuracy
    # roll at cast or resolve time.
    {"id":  248, "name": "Future Sight",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 120, "accuracy": 100, "pp": 10,
     "ignores_protect": True, "is_future_sight": True},
    {"id":  353, "name": "Doom Desire",
     "type": TYPE_STEEL, "category": SPEC, "power": 140, "accuracy": 100, "pp": 5,
     "ignores_protect": True, "is_future_sight": True},

    # Wish(273): schedules a heal resolving 1 turn later (caster's own max
    # HP / 2) against whoever occupies the CASTER's own slot then.
    {"id":  273, "name": "Wish",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "healing_move": True, "is_wish": True, "snatch_affected": True,},

    # ── [Delayed-effect family] Per-mon volatile counter ────────────────────
    # Yawn(281): 2-turn drowsiness counter, fresh sleep-infliction attempt
    # (all immunities re-derived) when it hits 0.
    {"id":  281, "name": "Yawn",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "bounceable": True, "is_yawn": True},

    # ── [Delayed-effect family] Switch-in-triggered one-shot ────────────────
    # Healing Wish(361)/Lunar Dance(461): user faints (fails outright if no
    # valid switch target) to store a full heal+status-cure (+full PP for
    # Lunar Dance) for whoever next switches into that slot.
    {"id":  361, "name": "Healing Wish",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "healing_move": True, "is_healing_wish": True, "snatch_affected": True,},
    {"id":  461, "name": "Lunar Dance",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "healing_move": True, "is_lunar_dance": True, "snatch_affected": True,},

    # ── [Psyshock/Psystrike] Defense-stat-source override ───────────────────
    # Psyshock(473)/Psystrike(540): Special-category moves that compute
    # damage off the DEFENDER's Defense stat/stage instead of Sp. Defense.
    {"id":  473, "name": "Psyshock",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 80, "accuracy": 100, "pp": 10,
     "is_psyshock": True},
    {"id":  540, "name": "Psystrike",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 100, "accuracy": 100, "pp": 10,
     "is_psyshock": True},

    # ── [D1 easy bundle] EFFECT_HIT_ESCAPE: attacker gets a voluntary-
    # style switch prompt after a connecting hit ────────────────────────────
    {"id":  369, "name": "U-turn",
     "type": TYPE_BUG, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_hit_escape": True},
    {"id":  521, "name": "Volt Switch",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 70, "accuracy": 100, "pp": 20,
     "is_hit_escape": True},
    {"id":  740, "name": "Flip Turn",
     "type": TYPE_WATER, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_hit_escape": True},

    # ── [D1 easy bundle] EFFECT_HIT_SWITCH_TARGET: forces the DEFENDER out
    # after a hit that dealt real HP damage ──────────────────────────────────
    {"id":  509, "name": "Circle Throw",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 60, "accuracy": 90, "pp": 10,
     "priority": -6, "makes_contact": True, "is_hit_switch_target": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": BAN_COPYCAT | BAN_ASSIST},
    {"id":  525, "name": "Dragon Tail",
     "type": TYPE_DRAGON, "category": PHYS, "power": 60, "accuracy": 90, "pp": 10,
     "priority": -6, "makes_contact": True, "is_hit_switch_target": True,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": BAN_COPYCAT | BAN_ASSIST},

    # ── [D1 easy bundle] EFFECT_FIRST_TURN_ONLY: fails unless this is the
    # user's first action since switching in ────────────────────────────────
    {"id":  252, "name": "Fake Out",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 10,
     "priority": 3, "makes_contact": True, "is_first_turn_only": True,
     "secondary_effect": SE_FLINCH, "secondary_chance": 100},
    {"id":  623, "name": "First Impression",
     "type": TYPE_BUG, "category": PHYS, "power": 90, "accuracy": 100, "pp": 10,
     "priority": 2, "makes_contact": True, "is_first_turn_only": True},

    # ── [D1 easy bundle] EFFECT_TRICK: bidirectional held-item swap ─────────
    {"id":  271, "name": "Trick",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 100, "pp": 10,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": (BAN_COPYCAT | BAN_ASSIST | BAN_METRONOME),
     "is_trick": True},
    {"id":  415, "name": "Switcheroo",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 10,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE.
     "ban_flags": (BAN_COPYCAT | BAN_ASSIST | BAN_METRONOME),
     "is_trick": True},

    # ── [D1 easy bundle] EFFECT_REVENGE: doubled if hit BY THIS TARGET
    # earlier this turn ──────────────────────────────────────────────────────
    {"id":  279, "name": "Revenge",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "priority": -4, "makes_contact": True, "is_revenge": True},
    {"id":  419, "name": "Avalanche",
     "type": TYPE_ICE, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "priority": -4, "makes_contact": True, "is_revenge": True},

    # ── [D1 easy bundle] EFFECT_STOMPING_TANTRUM: doubled if the user's
    # own previous move failed exactly one turn ago ─────────────────────────
    {"id":  661, "name": "Stomping Tantrum",
     "type": TYPE_GROUND, "category": PHYS, "power": 75, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_stomping_tantrum": True},
    {"id":  843, "name": "Temper Flare",
     "type": TYPE_FIRE, "category": PHYS, "power": 75, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_stomping_tantrum": True},

    # ── [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS]: doubles power if the target
    # has a qualifying status. All 5 individually re-verified at Step 0 — NOT
    # uniform: Hex/Infernal Parade use STATUS_ARG_ANY (any non-volatile
    # status, including a Comatose holder treated as asleep — see
    # BattleManager's own dispatch doc comment); Venoshock/Barb Barrage use
    # STATUS_ARG_POISON_ANY (poison or toxic); Smelling Salts uses a single
    # specific STATUS_PARALYSIS value. Barb Barrage/Infernal Parade are
    # genuine two-mechanism composites — their own 50%/30% poison/burn
    # secondary chance is PURE REUSE of the existing generic secondary_effect
    # dispatch (SE_POISON/SE_BURN), not new code. Smelling Salts is a THIRD
    # composite shape: is_smelling_salts also cures the target's paralysis on
    # hit, but ONLY if not blocked by a live, non-ignored Substitute (a real,
    # Smelling-Salts-only exception to the power-double itself — see
    # move_data.gd's own doc comment for the exact source citation). ──
    {"id":  265, "name": "Smelling Salts",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_double_power_on_status": True,
     "double_power_status_arg": STATUS_PARALYSIS, "is_smelling_salts": True},
    {"id":  474, "name": "Venoshock",
     "type": TYPE_POISON, "category": SPEC, "power": 65, "accuracy": 100, "pp": 10,
     "is_double_power_on_status": True, "double_power_status_arg": STATUS_ARG_POISON_ANY},
    {"id":  506, "name": "Hex",
     "type": TYPE_GHOST, "category": SPEC, "power": 65, "accuracy": 100, "pp": 10,
     "is_double_power_on_status": True, "double_power_status_arg": STATUS_ARG_ANY},
    {"id":  767, "name": "Barb Barrage",
     "type": TYPE_POISON, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "is_double_power_on_status": True, "double_power_status_arg": STATUS_ARG_POISON_ANY,
     "secondary_effect": SE_POISON, "secondary_chance": 50},
    {"id":  772, "name": "Infernal Parade",
     "type": TYPE_GHOST, "category": SPEC, "power": 60, "accuracy": 100, "pp": 15,
     "is_double_power_on_status": True, "double_power_status_arg": STATUS_ARG_ANY,
     "secondary_effect": SE_BURN, "secondary_chance": 30},

    # ── [D4 bundle]: Struggle/Helping Hand (FREE — mechanism already fully
    # built and wired, this is a pure data-entry gap); Sleep Talk (reuses
    # the Metronome/Mirror-Move reassignment pattern, scoped to the
    # attacker's own moveset); Taunt (reuses the Disable/Encore/Throat-Chop
    # turn-counter-volatile shape, execution-time block); Assurance (reuses
    # Revenge's hit_by_this_turn tracker, but keyed to "hit by anyone," not
    # the user specifically); Magic Coat (shares Magic Bounce's exact
    # dispatch chain, source-confirmed). Step 0 individually re-verified
    # each against moves_info.h — see move_data.gd's own per-flag doc
    # comments for full citations. ──
    {"id":  165, "name": "Struggle",
     "type": TYPE_NORMAL, "category": PHYS, "power": 50, "accuracy": 0, "pp": 1,
     "makes_contact": True, "is_struggle": True,
     "ban_flags": (BAN_METRONOME | BAN_SLEEP_TALK | BAN_COPYCAT | BAN_INSTRUCT | BAN_ASSIST | BAN_MIMIC | BAN_ME_FIRST | BAN_MIRROR_MOVE | BAN_SKETCH | BAN_ENCORE),},
    {"id":  270, "name": "Helping Hand",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "priority": 5, "ignores_protect": True, "ignores_substitute": True,
     "is_helping_hand": True,
     "ban_flags": BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST | BAN_MIRROR_MOVE},
    {"id":  214, "name": "Sleep Talk",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_sleep_talk": True, "usable_while_asleep": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_SLEEP_TALK
                   | BAN_INSTRUCT | BAN_MIMIC | BAN_ENCORE | BAN_ASSIST)},
    {"id":  269, "name": "Taunt",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 20,
     "ignores_substitute": True, "bounceable": True, "blocked_by_aroma_veil": True,
     "is_taunt": True},
    {"id":  372, "name": "Assurance",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_assurance": True},
    {"id":  277, "name": "Magic Coat",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 15,
     "priority": 4, "ignores_protect": True, "is_magic_coat": True,
     "ban_flags": BAN_MIRROR_MOVE},

    # ── D4 CHEAP bundle: Dream Eater, Torment, Gyro Ball, Electro Ball, Snore,
    # Endure, Fell Stinger, Magnet Rise, Smack Down, Ingrain, Aqua Ring,
    # Payback — 12 moves from D4's singleton pool. Dream Eater (fails outright
    # against a non-sleeping/non-Comatose target, reuses the generic
    # drain_percent absorb-family chokepoint — NOT the Volt/Water Absorb
    # ability family, a real Step-0 correction); Torment (permanent
    # target-side move-block, reuses Blood Moon's cant_use_twice SHAPE but
    # target-inflicted); Gyro Ball/Electro Ball (genuinely different speed-
    # ratio formulas — continuous-capped vs. stepped/banded, confirmed
    # independently rather than assumed mirrored); Snore (usable_while_asleep,
    # Sleep Talk's own precedent — no fail-if-awake gate, unlike Dream Eater);
    # Endure (shares Protect/Detect's setprotectlike dispatch but branches
    # internally to a SEPARATE endure_active field, confirmed from source —
    # never blocks the incoming hit); Fell Stinger (+3 Atk on KO, Moxie's own
    # killer-lookup shape); Magnet Rise/Smack Down/Ingrain (all three share
    # AbilityManager.is_grounded's priority-tier insertion); Ingrain (3-piece
    # composite: end-of-turn self-heal shared with Aqua Ring, self-grounding,
    # AND full escape-prevention — both voluntary-switch-block (is_trapped)
    # and forced-switch-block (blocks_forced_switch, confirmed from source
    # that Roar's own script checks VOLATILE_ROOT directly) — achieved via
    # pure reuse of existing infrastructure, a fuller build than this move's
    # own original partial-scope proposal); Aqua Ring (heal-only, no
    # grounding/switch-block); Payback (doubles if the target already acted
    # AND did not just switch in this turn, a genuinely conditional formula
    # at this project's GEN_LATEST config). Step 0 individually re-verified
    # each against moves_info.h/battle_util.c/battle_script_commands.c/
    # battle_end_turn.c — see move_data.gd's own per-flag doc comments and
    # battle_pokemon.gd's own per-field doc comments for full citations. ──
    {"id":  138, "name": "Dream Eater",
     "type": TYPE_PSYCHIC, "category": SPEC, "power": 100, "accuracy": 100, "pp": 15,
     "drain_percent": 50, "requires_target_asleep": True, "healing_move": True},
    {"id":  173, "name": "Snore",
     "type": TYPE_NORMAL, "category": SPEC, "power": 50, "accuracy": 100, "pp": 15,
     "ignores_substitute": True, "sound_move": True, "usable_while_asleep": True,
     "is_snore": True, "secondary_effect": SE_FLINCH, "secondary_chance": 30,
     "ban_flags": BAN_METRONOME},
    {"id":  203, "name": "Endure",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "priority": 4, "is_protect": True, "protect_method": PROTECT_METHOD_ENDURE,
     # [D4 Bundle 4] copycatBanned/assistBanned=TRUE (whole Protect family).
     "ban_flags": (BAN_COPYCAT | BAN_ASSIST | BAN_METRONOME),},
    {"id":  259, "name": "Torment",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 15,
     "bounceable": True, "blocked_by_aroma_veil": True, "is_torment": True},
    {"id":  275, "name": "Ingrain",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_ingrain": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True},
    {"id":  360, "name": "Gyro Ball",
     "type": TYPE_STEEL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 5,
     "makes_contact": True, "ballistic_move": True, "is_gyro_ball": True},
    {"id":  371, "name": "Payback",
     "type": TYPE_DARK, "category": PHYS, "power": 50, "accuracy": 100, "pp": 10,
     "makes_contact": True, "is_payback": True},
    {"id":  392, "name": "Aqua Ring",
     "type": TYPE_WATER, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_aqua_ring": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True,},
    {"id":  393, "name": "Magnet Rise",
     "type": TYPE_ELECTRIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_magnet_rise": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True,},
    {"id":  479, "name": "Smack Down",
     "type": TYPE_ROCK, "category": PHYS, "power": 50, "accuracy": 100, "pp": 15,
     "damages_airborne": True, "is_smack_down": True},
    {"id":  486, "name": "Electro Ball",
     "type": TYPE_ELECTRIC, "category": SPEC, "power": 1, "accuracy": 100, "pp": 10,
     "ballistic_move": True, "is_electro_ball": True},
    {"id":  565, "name": "Fell Stinger",
     "type": TYPE_BUG, "category": PHYS, "power": 50, "accuracy": 100, "pp": 25,
     "makes_contact": True, "is_fell_stinger": True},

    # ── D4 bundle 3: Splash, Refresh, Purify, Memento, Belly Drum, Fillet
    # Away, Clangorous Soul, Nightmare, Spite, Recycle, Facade, Take Heart.
    # Real Step-0 corrections: Refresh cures Burn/Poison/Toxic/Paralysis
    # ONLY (NOT Sleep/Freeze, STATUS1_CAN_MOVE); Take Heart raises Attack+
    # Sp.Atk (NOT Sp.Atk/Sp.Def, per source's own data table); the HP-cost
    # stat-boost trio hard-fails with zero HP cost unless the stat change
    # would do something AND the HP payment can be made; Recycle restores
    # a genuinely broader last_used_item field, not the berry-only
    # last_consumed_berry; Purify/Nightmare/Spite were all found to share
    # Foresight's own "never calls typecalc" type-immunity-gate bug, now
    # fixed. See move_data.gd's own per-flag doc comments for full
    # citations. ──
    {"id":  150, "name": "Splash",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 40,
     "ignores_protect": True, "is_do_nothing": True,
     "ban_flags": BAN_MIRROR_MOVE},
    {"id":  287, "name": "Refresh",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "is_refresh": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True},
    {"id":  648, "name": "Purify",
     "type": TYPE_POISON, "category": STAT, "accuracy": 0, "pp": 20,
     "healing_move": True, "bounceable": True, "is_purify": True,
     "ban_flags": BAN_MIRROR_MOVE},
    {"id":  262, "name": "Memento",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 10,
     "is_memento": True,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": -2,
     "extra_stat_change_stats": [STAGE_SPATK], "extra_stat_change_amounts": [-2]},
    {"id":  187, "name": "Belly Drum",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "hp_cost_stat_boost": True, "hp_cost_divisor": 2,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 12, "stat_change_self": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True},
    {"id":  796, "name": "Fillet Away",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "hp_cost_stat_boost": True, "hp_cost_divisor": 2,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 2, "stat_change_self": True,
     "extra_stat_change_stats": [STAGE_SPATK, STAGE_SPEED],
     "extra_stat_change_amounts": [2, 2],
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME, "snatch_affected": True},
    {"id":  703, "name": "Clangorous Soul",
     "type": TYPE_DRAGON, "category": STAT, "accuracy": 100, "pp": 5,
     "ignores_protect": True, "sound_move": True,
     "hp_cost_stat_boost": True, "hp_cost_divisor": 3,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 1, "stat_change_self": True,
     "extra_stat_change_stats": [STAGE_DEF, STAGE_SPATK, STAGE_SPDEF, STAGE_SPEED],
     "extra_stat_change_amounts": [1, 1, 1, 1],
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME, "snatch_affected": True},
    {"id":  171, "name": "Nightmare",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 100, "pp": 15,
     "is_nightmare": True},
    {"id":  180, "name": "Spite",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 100, "pp": 10,
     "ignores_substitute": True, "bounceable": True, "is_spite": True},
    {"id":  278, "name": "Recycle",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_recycle": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True,},
    {"id":  263, "name": "Facade",
     "type": TYPE_NORMAL, "category": PHYS, "power": 70, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_facade": True},
    {"id":  778, "name": "Take Heart",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "is_take_heart": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True},

    # ── [D4 Bundle 4] Cluster 1: side-condition timers ───────────────────────
    {"id":  366, "name": "Tailwind",
     "type": TYPE_FLYING, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_tailwind": True, "snatch_affected": True},
    {"id":  564, "name": "Sticky Web",
     "type": TYPE_BUG, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "bounceable": True, "ban_flags": BAN_MIRROR_MOVE,
     "is_sticky_web": True},
    {"id":  219, "name": "Safeguard",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 25,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_safeguard": True, "snatch_affected": True},
    {"id":   54, "name": "Mist",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_mist": True, "snatch_affected": True},

    # ── [D4 Bundle 4] Cluster 2: call-a-different-move family ────────────────
    {"id":  383, "name": "Copycat",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ASSIST | BAN_MIMIC | BAN_ENCORE),
     "is_copycat": True},
    {"id":  382, "name": "Me First",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_substitute": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_ME_FIRST | BAN_COPYCAT
                   | BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ENCORE | BAN_ASSIST | BAN_MIMIC),
     "is_me_first": True},
    {"id":  274, "name": "Assist",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_SLEEP_TALK
                   | BAN_INSTRUCT | BAN_ENCORE | BAN_ASSIST | BAN_MIMIC),
     "is_assist": True},

    # ── [D4 Bundle 4] Cluster 3: target-directed heal variants ───────────────
    {"id":  505, "name": "Heal Pulse",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "bounceable": True, "healing_move": True, "pulse_move": True,
     "ban_flags": BAN_MIRROR_MOVE, "is_heal_pulse": True},
    {"id":  719, "name": "Life Dew",
     "type": TYPE_WATER, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True, "healing_move": True,
     "ban_flags": BAN_MIRROR_MOVE | BAN_METRONOME, "is_life_dew": True, "snatch_affected": True},

    # ── [D4 Bundle 4] Cluster 4: Stockpile family ─────────────────────────────
    {"id":  254, "name": "Stockpile",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "stat_change_self": True,
     "ban_flags": BAN_MIRROR_MOVE, "is_stockpile": True, "snatch_affected": True},
    {"id":  255, "name": "Spit Up",
     "type": TYPE_NORMAL, "category": SPEC, "power": 1, "accuracy": 100, "pp": 10,
     "ban_flags": BAN_MIRROR_MOVE, "is_spit_up": True},
    {"id":  256, "name": "Swallow",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "healing_move": True,
     "ban_flags": BAN_MIRROR_MOVE, "is_swallow": True, "snatch_affected": True},

    # ── [D4 Bundle 5] Cluster 1: field-wide side conditions ──────────────────
    {"id":  300, "name": "Mud Sport",
     "type": TYPE_GROUND, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_mud_sport": True},
    {"id":  346, "name": "Water Sport",
     "type": TYPE_WATER, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_water_sport": True},

    # ── [D4 Bundle 5] Cluster 2: type-mutation family ─────────────────────────
    {"id":  311, "name": "Weather Ball",
     "type": TYPE_NORMAL, "category": SPEC, "power": 50, "accuracy": 100, "pp": 10,
     "ballistic_move": True, "is_weather_ball": True},
    {"id":  513, "name": "Reflect Type",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_substitute": True, "ban_flags": BAN_MIRROR_MOVE, "is_reflect_type": True},

    # ── [D4 Bundle 5] Cluster 3: heal-and-drain family ────────────────────────
    {"id":  355, "name": "Roost",
     "type": TYPE_FLYING, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "healing_move": True,
     "ban_flags": BAN_MIRROR_MOVE, "is_roost": True, "snatch_affected": True},
    {"id":  631, "name": "Strength Sap",
     "type": TYPE_GRASS, "category": STAT, "accuracy": 100, "pp": 10,
     "bounceable": True, "healing_move": True, "is_strength_sap": True},

    # ── [D4 Bundle 5] Cluster 4: HP-cost-attached-to-damage family ────────────
    {"id":  724, "name": "Steel Beam",
     "type": TYPE_STEEL, "category": SPEC, "power": 140, "accuracy": 95, "pp": 5,
     "ban_flags": BAN_METRONOME, "is_steel_beam": True},
    {"id":  763, "name": "Chloroblast",
     "type": TYPE_GRASS, "category": SPEC, "power": 150, "accuracy": 95, "pp": 5,
     "is_chloroblast": True},

    # ── [D4 Bundle 5] Cluster 5: persistent-flag-consumed-by-next-action family ─
    {"id":  268, "name": "Charge",
     "type": TYPE_ELECTRIC, "category": STAT, "accuracy": 0, "pp": 20,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_SPDEF, "stat_change_amount": 1, "stat_change_self": True,
     "is_charge": True, "snatch_affected": True},
    {"id":  636, "name": "Laser Focus",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_laser_focus": True, "snatch_affected": True},

    # ── [D4 Bundle 5] Cluster 6: stat-array manipulation ──────────────────────
    {"id":  576, "name": "Topsy-Turvy",
     "type": TYPE_DARK, "category": STAT, "accuracy": 0, "pp": 20,
     "bounceable": True, "is_topsy_turvy": True},
    {"id":  475, "name": "Autotomize",
     "type": TYPE_STEEL, "category": STAT, "accuracy": 0, "pp": 15,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_SPEED, "stat_change_amount": 2, "stat_change_self": True, "snatch_affected": True},

    # ── [D4 Bundle 5] Cluster 7: escalating power ─────────────────────────────
    {"id":  210, "name": "Fury Cutter",
     "type": TYPE_BUG, "category": PHYS, "power": 40, "accuracy": 95, "pp": 20,
     "makes_contact": True, "slicing_move": True, "is_fury_cutter": True},

    # ── [D4 Bundle 6] 23 REUSE-LIKELY residual moves ──────────────────────────
    {"id":  100, "name": "Teleport",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 20, "priority": -6,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_teleport": True},
    {"id":  156, "name": "Rest",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "healing_move": True,
     "ban_flags": BAN_MIRROR_MOVE, "is_rest": True, "snatch_affected": True},
    {"id":  206, "name": "False Swipe",
     "type": TYPE_NORMAL, "category": PHYS, "power": 40, "accuracy": 100, "pp": 40,
     "makes_contact": True, "is_false_swipe": True},
    {"id":  217, "name": "Present",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 90, "pp": 15,
     "is_present": True},
    {"id":  282, "name": "Knock Off",
     "type": TYPE_DARK, "category": PHYS, "power": 65, "accuracy": 100, "pp": 20,
     "makes_contact": True, "is_knock_off": True},
    {"id":  283, "name": "Endeavor",
     "type": TYPE_NORMAL, "category": PHYS, "power": 1, "accuracy": 100, "pp": 5,
     "makes_contact": True, "is_endeavor": True},
    {"id":  362, "name": "Brine",
     "type": TYPE_WATER, "category": SPEC, "power": 65, "accuracy": 100, "pp": 10,
     "is_brine": True},
    {"id":  367, "name": "Acupressure",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 30,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_acupressure": True},
    {"id":  375, "name": "Psycho Shift",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 100, "pp": 10,
     "is_psycho_shift": True},
    {"id":  386, "name": "Punishment",
     "type": TYPE_DARK, "category": PHYS, "power": 60, "accuracy": 100, "pp": 5,
     "makes_contact": True, "is_punishment": True},
    {"id":  477, "name": "Telekinesis",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 15,
     "bounceable": True, "is_telekinesis": True},
    {"id":  512, "name": "Acrobatics",
     "type": TYPE_FLYING, "category": PHYS, "power": 55, "accuracy": 100, "pp": 15,
     "makes_contact": True, "is_acrobatics": True},
    # [NEW ITEM C] target_includes_ally: real .target=TARGET_FOES_AND_ALLY.
    {"id":  523, "name": "Bulldoze",
     "type": TYPE_GROUND, "category": PHYS, "power": 60, "accuracy": 100, "pp": 20,
     "is_spread": True, "target_includes_ally": True,
     "stat_change_stat": STAGE_SPEED, "stat_change_amount": -1, "secondary_chance": 100},
    {"id":  562, "name": "Belch",
     "type": TYPE_POISON, "category": SPEC, "power": 120, "accuracy": 90, "pp": 10,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_ME_FIRST | BAN_METRONOME | BAN_MIMIC
                   | BAN_COPYCAT | BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ASSIST),
     "is_belch": True},
    {"id":  575, "name": "Parting Shot",
     "type": TYPE_DARK, "category": STAT, "accuracy": 100, "pp": 20,
     "bounceable": True, "ignores_substitute": True, "sound_move": True,
     "is_parting_shot": True},
    {"id":  599, "name": "Venom Drench",
     "type": TYPE_POISON, "category": STAT, "accuracy": 100, "pp": 20,
     "is_spread": True, "bounceable": True, "is_venom_drench": True},
    {"id":  601, "name": "Geomancy",
     "type": TYPE_FAIRY, "category": STAT, "accuracy": 0, "pp": 10,
     "ban_flags": (BAN_SLEEP_TALK | BAN_INSTRUCT), "two_turn": True,
     "stat_change_stat": STAGE_SPATK, "stat_change_amount": 2, "stat_change_self": True,
     "extra_stat_change_stats": [STAGE_SPDEF, STAGE_SPEED],
     "extra_stat_change_amounts": [2, 2]},
    {"id":  635, "name": "Toxic Thread",
     "type": TYPE_POISON, "category": STAT, "accuracy": 100, "pp": 20,
     "bounceable": True, "is_toxic_thread": True},
    {"id":  693, "name": "Stuff Cheeks",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE, "is_stuff_cheeks": True, "snatch_affected": True},
    {"id":  694, "name": "No Retreat",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 1, "stat_change_self": True,
     "extra_stat_change_stats": [STAGE_DEF, STAGE_SPATK, STAGE_SPDEF, STAGE_SPEED],
     "extra_stat_change_amounts": [1, 1, 1, 1],
     "is_no_retreat": True, "snatch_affected": True},
    {"id":  699, "name": "Octolock",
     "type": TYPE_FIGHTING, "category": STAT, "accuracy": 100, "pp": 15,
     "is_octolock": True},
    {"id":  737, "name": "Poltergeist",
     "type": TYPE_GHOST, "category": PHYS, "power": 110, "accuracy": 90, "pp": 5,
     "is_poltergeist": True},
    {"id":  807, "name": "Chilly Reception",
     "type": TYPE_ICE, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME),
     "is_chilly_reception": True},

    # [D4 Bundle 7] Curse: Ghost-type user curses the target (see is_curse's
    # own doc comment); non-Ghost user self +1 Atk/+1 Def/-1 Speed via the
    # generic multi-stat dispatch (stat_change_self=True).
    {"id":  174, "name": "Curse",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True,
     "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_stat": STAGE_ATK, "stat_change_amount": 1,
     "extra_stat_change_stats": [STAGE_DEF, STAGE_SPEED],
     "extra_stat_change_amounts": [1, -1], "stat_change_self": True,
     "is_curse": True},
    {"id":  264, "name": "Focus Punch",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 150, "accuracy": 100,
     "pp": 20, "priority": -3, "makes_contact": True, "punching_move": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_ME_FIRST | BAN_METRONOME
                   | BAN_COPYCAT | BAN_ASSIST | BAN_SLEEP_TALK | BAN_INSTRUCT),
     "is_focus_punch": True},
    {"id":  288, "name": "Grudge",
     "type": TYPE_GHOST, "category": STAT, "accuracy": 0, "pp": 5,
     "ignores_protect": True, "ignores_substitute": True,
     "ban_flags": BAN_MIRROR_MOVE,
     "stat_change_self": True, "is_grudge": True},
    {"id":  387, "name": "Last Resort",
     "type": TYPE_NORMAL, "category": PHYS, "power": 140, "accuracy": 100,
     "pp": 5, "makes_contact": True, "is_last_resort": True},
    {"id":  639, "name": "Pollen Puff",
     "type": TYPE_BUG, "category": SPEC, "power": 90, "accuracy": 100,
     "pp": 15, "ballistic_move": True, "is_pollen_puff": True},
    {"id":  653, "name": "Beak Blast",
     "type": TYPE_FLYING, "category": PHYS, "power": 100, "accuracy": 100,
     "pp": 15, "priority": -3, "ballistic_move": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_ME_FIRST | BAN_METRONOME
                   | BAN_COPYCAT | BAN_ASSIST | BAN_SLEEP_TALK | BAN_INSTRUCT),
     "is_beak_blast": True},
    # [NEW ITEM A] is_spread=True: real source .target=TARGET_BOTH, was
    # missing entirely — confirmed once armed, Shell Trap falls through to
    # the ordinary accuracy+hit dispatch exactly like a normal move (its own
    # is_shell_trap gate only intercepts the UNARMED-fail case above), so
    # the spread branch is the correct, unmodified integration point.
    {"id":  658, "name": "Shell Trap",
     "type": TYPE_FIRE, "category": SPEC, "power": 150, "accuracy": 100,
     "pp": 5, "priority": -3,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_ME_FIRST | BAN_METRONOME
                   | BAN_COPYCAT | BAN_ASSIST | BAN_SLEEP_TALK | BAN_INSTRUCT),
     "is_shell_trap": True, "is_spread": True},

    # [D4 Bundle 8] Round/Snatch/Imprison — reinstated after Rob reversed
    # [Exclusion bookkeeping]'s own same-day exclusion; Grav Apple is a pure
    # data entry reusing the existing generic secondary-stat-on-hit dispatch
    # (M19-secondary-stat-on-hit), no new is_* flag needed at all.
    {"id":  496, "name": "Round",
     "type": TYPE_NORMAL, "category": SPEC, "power": 60, "accuracy": 100,
     "pp": 15, "sound_move": True, "ignores_substitute": True,
     "is_round": True},
    {"id":  289, "name": "Snatch",
     "type": TYPE_DARK, "category": STAT, "accuracy": 0, "pp": 10,
     "priority": 4, "ignores_protect": True, "ignores_substitute": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_METRONOME | BAN_COPYCAT | BAN_ASSIST),
     "is_snatch": True},
    {"id":  286, "name": "Imprison",
     "type": TYPE_PSYCHIC, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True, "ignores_substitute": True,
     "ban_flags": BAN_MIRROR_MOVE, "snatch_affected": True,
     "is_imprison": True},
    {"id":  716, "name": "Grav Apple",
     "type": TYPE_GRASS, "category": PHYS, "power": 80, "accuracy": 100,
     "pp": 10, "ban_flags": BAN_METRONOME,
     "stat_change_stat": STAGE_DEF, "stat_change_amount": -1,
     "stat_change_self": False},

    # [D4 Bundle 9] Flying Press(560): EFFECT_TWO_TYPED_MOVE. Power 100 at
    # this project's GEN_LATEST config (B_UPDATED_MOVE_DATA>=GEN_7 ? 100:80).
    # double_power_on_minimized=True — source's own .minimizeDoubleDamage
    # field explicitly names this move as one of its carriers (confirmed via
    # this project's own pre-existing MoveData.double_power_on_minimized doc
    # comment, which already listed Flying Press by name before this move was
    # ever implemented). second_type=Flying is the move's own
    # .argument.type — see MoveData.two_typed_move's own doc comment for the
    # full source citation and the STAB deviation decision.
    {"id":  560, "name": "Flying Press",
     "type": TYPE_FIGHTING, "category": PHYS, "power": 100, "accuracy": 95,
     "pp": 10, "makes_contact": True, "double_power_on_minimized": True,
     "two_typed_move": True, "second_type": TYPE_FLYING},

    # [D4 Bundle 9] Sky Drop(507): EFFECT_SKY_DROP. gravityBanned/
    # skyBattleBanned are moot (neither Gravity nor Sky Battle exists in this
    # project). sleepTalkBanned/instructBanned/assistBanned (GEN_6+) all
    # carry over — see MoveData.is_sky_drop's own doc comment for the full
    # source citation.
    {"id":  507, "name": "Sky Drop",
     "type": TYPE_FLYING, "category": PHYS, "power": 60, "accuracy": 100,
     "pp": 10, "makes_contact": True,
     "ban_flags": (BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ASSIST),
     "is_sky_drop": True},

    # [Mimic/Sketch] Mimic(102): EFFECT_MIMIC. accuracy=0 (no accuracy check
    # at GEN_LATEST), ignoresSubstitute=TRUE. mimicBanned/metronomeBanned/
    # copycatBanned/sleepTalkBanned/instructBanned/encoreBanned/assistBanned
    # all TRUE (moves_info.h MOVE_MIMIC) — see MoveData.is_mimic's own doc
    # comment for the full citation.
    {"id":  102, "name": "Mimic",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_substitute": True,
     "ban_flags": (BAN_MIMIC | BAN_METRONOME | BAN_COPYCAT | BAN_SLEEP_TALK
                   | BAN_INSTRUCT | BAN_ENCORE | BAN_ASSIST),
     "is_mimic": True},

    # [Mimic/Sketch] Sketch(166): EFFECT_SKETCH. accuracy=0, pp=1,
    # ignoresProtect/ignoresSubstitute=TRUE (GEN_5+). mirrorMoveBanned/
    # mimicBanned/metronomeBanned/copycatBanned/sleepTalkBanned/
    # instructBanned/encoreBanned/assistBanned/sketchBanned all TRUE
    # (moves_info.h MOVE_SKETCH) — see MoveData.is_sketch's own doc comment
    # for the full citation, including the confirmed differences from Mimic.
    {"id":  166, "name": "Sketch",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 1,
     "ignores_protect": True, "ignores_substitute": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_MIMIC | BAN_METRONOME | BAN_COPYCAT
                   | BAN_SLEEP_TALK | BAN_INSTRUCT | BAN_ENCORE | BAN_ASSIST
                   | BAN_SKETCH),
     "is_sketch": True},

    # [Perish Song] Perish Song(195): EFFECT_PERISH_SONG. accuracy=0,
    # target=ALL_BATTLERS (both sides, incl. the caster). ignoresProtect/
    # ignoresSubstitute=TRUE, soundMove=TRUE (Soundproof-blockable, per
    # target), mirrorMoveBanned=TRUE. See MoveData.is_perish_song's own doc
    # comment for the full citation.
    {"id":  195, "name": "Perish Song",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 5,
     "target": TARGET_ALL_BATTLERS,
     "ignores_protect": True, "ignores_substitute": True, "sound_move": True,
     "ban_flags": BAN_MIRROR_MOVE,
     "is_perish_song": True},

    # [Transform] Transform(144): EFFECT_TRANSFORM. accuracy=0, pp=10,
    # target=SELECTED (this project's default — no explicit "target" key
    # needed). ignoresProtect=TRUE; ignoresSubstitute = B_UPDATED_MOVE_FLAGS
    # < GEN_5, which resolves FALSE at this project's GEN_LATEST config, so
    # Substitute DOES block it (confirmed, not assumed — deliberately
    # omitted here so it defaults to False). mirrorMoveBanned/mimicBanned/
    # metronomeBanned (GEN_5+)/copycatBanned (GEN_5+)/instructBanned/
    # encoreBanned/assistBanned (GEN_5+) all TRUE at this config; no
    # sketchBanned (source's real sketchBanned list is only Struggle/Sketch
    # itself/Chatter — confirmed during the Mimic/Sketch session — so Sketch
    # can legitimately copy Transform). See MoveData.is_transform's own doc
    # comment for the full citation of every field copied/excluded on cast.
    {"id":  144, "name": "Transform",
     "type": TYPE_NORMAL, "category": STAT, "accuracy": 0, "pp": 10,
     "ignores_protect": True,
     "ban_flags": (BAN_MIRROR_MOVE | BAN_MIMIC | BAN_METRONOME | BAN_COPYCAT
                   | BAN_INSTRUCT | BAN_ENCORE | BAN_ASSIST),
     "is_transform": True},
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
    # [Bucket 3 combined-secondary] a second, independent secondary-effect roll
    # (Thunder/Ice/Fire Fang's status + flinch).
    "secondary_effect_2":  SE_NONE,
    "secondary_chance_2":  0,
    "stat_change_stat":    -1,
    "stat_change_amount":  0,
    "stat_change_self":    False,
    # [EFFECT_STAT_CHANGE audit] see move_data.gd's own doc comment
    "stat_change_bypasses_type_gate": False,
    # [Bucket 3 multi-stat] extra (stat, amount) pairs beyond the primary one
    "extra_stat_change_stats":   [],
    "extra_stat_change_amounts": [],
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
    # [Bucket 3 screen+damage] Glitzy Glow / Baddy Bad — screen set on a damaging hit.
    "sets_reflect_on_hit":       False,
    "sets_light_screen_on_hit":  False,
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
    # [D4 Bundle 8] snatch_affected (Snatch's own snatchAffected-derived field —
    # see MoveData.is_snatch's own doc comment for the full source citation).
    "snatch_affected":            False,
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
    "is_dragon_darts":            False,

    # [M19-pre1] weight-based and friendship-based dynamic power.
    "is_low_kick_power":          False,
    "is_heat_crash_power":        False,
    "is_return_power":            False,
    "is_frustration_power":       False,

    # [Bucket 4 cheapest singles]
    "is_rage":                    False,
    "is_clear_smog":              False,
    "is_incinerate":              False,
    "is_sparkling_aria":          False,
    "cant_use_twice":             False,

    # [M19-rampage]
    "is_rampage":                 False,
    "is_uproar":                  False,

    # [M19-recharge]
    "is_recharge":                False,

    # [M19-break-protect]
    "breaks_protect":             False,

    # [M19-recoil-on-miss]
    "crashes_on_miss":            False,

    # [M19-weather-conditional-accuracy]
    "always_hits_in_rain":        False,
    "accuracy_halved_in_sun":     False,

    # [Bucket 4 2-move sub-groups]
    "percent_current_hp_damage":  0,
    "ignores_defense_evasion_stages": False,
    "charge_turn_spatk_boost":    0,
    "skips_charge_in_rain":       False,
    "is_flail_power":             False,
    "requires_target_stat_raised": False,
    "random_status_pool":         [],
    "is_self_faint":              False,
    "target_includes_ally":       False,
    "steals_and_eats_berry":      False,
    "ignores_target_ability":     False,

    # [M19-steal-stats] / [M19-ally-targeting-stat-change]
    "steals_positive_stat_stages": False,
    "stat_change_target_ally":    False,
    "also_boosts_ally":           False,

    # [M19e] / [M19f]
    "heals_based_on_weather":       False,
    "weather_heal_boost_type":      0,
    "weather_heal_has_quarter_branch": False,
    "is_mean_look":                 False,

    # [M19c] / [M19d]
    "protect_method":  0,
    "metal_burst":     False,
    "is_mirror_move":  False,

    # [D0]
    "is_leech_seed":        False,
    "is_haze":              False,
    "is_heal_bell":         False,
    "is_leech_seed_on_hit": False,
    "is_haze_on_hit":       False,
    "is_heal_bell_on_hit":  False,

    # [D1]
    "ignores_redirection": False,
    "is_hidden_power":     False,

    # [D1 cheap clusters]
    "weather_type":                  0,
    "power_scales_with_user_hp":     False,
    "power_scales_with_target_hp":   False,
    "steals_item_if_itemless":       False,
    "is_lock_on":                    False,
    "is_swagger":                    False,
    "is_sucker_punch":               False,
    "is_stored_power":               False,

    # [D2 batch]
    "sets_stealth_rock_on_hit":  False,
    "sets_spikes_on_hit":        False,
    "is_defog":                  False,
    "is_tidy_up":                False,
    "is_role_play":              False,
    "is_skill_swap":              False,
    "is_heart_swap":              False,
    "overwrite_target_ability_id": -1,

    # [D2 batch 2]
    "is_foul_play":            False,
    "is_body_press":           False,
    "is_photon_geyser":        False,
    "super_effective_vs_type": TYPE_NONE,
    "is_tar_shot":             False,
    "is_foresight":            False,

    # [D3 turn-order/event-tracker batch]
    "is_after_you":            False,
    "is_quash":                False,
    "is_upper_hand":           False,
    "is_instruct":             False,
    "is_lash_out":             False,
    "is_retaliate":            False,
    "is_rage_fist":            False,
    "is_echoed_voice":         False,

    # [Delayed-effect family] / [Psyshock/Psystrike]
    "is_future_sight":         False,
    "is_wish":                 False,
    "is_yawn":                 False,
    "is_healing_wish":         False,
    "is_lunar_dance":          False,
    "is_psyshock":             False,

    # [D1 easy bundle]
    "is_hit_escape":           False,
    "is_hit_switch_target":    False,
    "is_first_turn_only":      False,
    "is_trick":                False,
    "is_revenge":              False,
    "is_stomping_tantrum":     False,

    # [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS]
    "is_double_power_on_status": False,
    "double_power_status_arg":   -1,
    "is_smelling_salts":         False,

    # [D4 bundle]
    "is_sleep_talk":         False,
    "usable_while_asleep":   False,
    "is_taunt":              False,
    "is_assurance":          False,
    "is_magic_coat":         False,

    # [D4 CHEAP bundle]
    "requires_target_asleep": False,
    "is_torment":             False,
    "is_gyro_ball":           False,
    "is_electro_ball":        False,
    "is_snore":               False,
    "is_fell_stinger":        False,
    "is_magnet_rise":         False,
    "is_smack_down":          False,
    "is_ingrain":             False,
    "is_aqua_ring":           False,
    "is_payback":             False,

    # [D4 bundle 3]
    "is_do_nothing":          False,
    "is_refresh":             False,
    "is_purify":              False,
    "is_memento":             False,
    "hp_cost_stat_boost":     False,
    "hp_cost_divisor":        0,
    "is_nightmare":           False,
    "is_spite":               False,
    "is_recycle":             False,
    "is_facade":              False,
    "is_take_heart":          False,

    # [D4 Bundle 4]
    "is_tailwind":            False,
    "is_sticky_web":          False,
    "is_safeguard":           False,
    "is_mist":                False,
    "is_copycat":             False,
    "is_me_first":            False,
    "is_assist":              False,
    "is_heal_pulse":          False,
    "is_life_dew":            False,
    "is_stockpile":           False,
    "is_spit_up":             False,
    "is_swallow":             False,

    # [D4 Bundle 5]
    "is_mud_sport":           False,
    "is_water_sport":         False,
    "is_weather_ball":        False,
    "is_reflect_type":        False,
    "is_roost":               False,
    "is_strength_sap":        False,
    "is_steel_beam":          False,
    "is_chloroblast":         False,
    "is_charge":              False,
    "is_laser_focus":         False,
    "is_topsy_turvy":         False,
    "is_fury_cutter":         False,

    # [D4 Bundle 6]
    "is_teleport":            False,
    "is_rest":                False,
    "is_false_swipe":         False,
    "is_present":             False,
    "is_knock_off":           False,
    "is_endeavor":            False,
    "is_brine":               False,
    "is_acupressure":         False,
    "is_psycho_shift":        False,
    "is_punishment":          False,
    "is_telekinesis":         False,
    "is_acrobatics":          False,
    "is_belch":               False,
    "is_parting_shot":        False,
    "is_venom_drench":        False,
    "is_toxic_thread":        False,
    "is_stuff_cheeks":        False,
    "is_no_retreat":          False,
    "is_octolock":            False,
    "is_poltergeist":         False,
    "is_chilly_reception":    False,
    "is_curse":               False,
    "is_focus_punch":         False,
    "is_grudge":              False,
    "is_last_resort":         False,
    "is_pollen_puff":         False,
    "is_beak_blast":          False,
    "is_shell_trap":          False,
    "is_round":               False,
    "is_snatch":              False,
    "is_imprison":            False,
    "two_typed_move":         False,
    "second_type":            -1,
    "is_sky_drop":            False,
    "is_mimic":               False,
    "is_sketch":              False,
    "is_perish_song":         False,
    "is_transform":           False,
    "target":                 0,
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
    "secondary_effect_2", "secondary_chance_2",
    "stat_change_stat", "stat_change_amount", "stat_change_self",
    "stat_change_bypasses_type_gate",
    "extra_stat_change_stats", "extra_stat_change_amounts",
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
    "sets_reflect_on_hit", "sets_light_screen_on_hit",
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
    # [D4 Bundle 8] fields
    "snatch_affected",
    # M18.5d-2 fields
    "is_attract",
    # M18.5g fields
    "strike_count", "multi_hit", "is_triple_kick", "is_scale_shot", "is_dragon_darts",
    # M19-pre1 fields
    "is_low_kick_power", "is_heat_crash_power", "is_return_power", "is_frustration_power",
    # [Bucket 4 cheapest singles] fields
    "is_rage", "is_clear_smog", "is_incinerate", "is_sparkling_aria", "cant_use_twice",
    # [M19-rampage] fields
    "is_rampage", "is_uproar",
    # [M19-recharge] fields
    "is_recharge",
    # [M19-break-protect] fields
    "breaks_protect",
    # [M19-recoil-on-miss] fields
    "crashes_on_miss",
    # [M19-weather-conditional-accuracy] fields
    "always_hits_in_rain", "accuracy_halved_in_sun",
    # [Bucket 4 2-move sub-groups] fields
    "percent_current_hp_damage", "ignores_defense_evasion_stages",
    "charge_turn_spatk_boost", "skips_charge_in_rain", "is_flail_power",
    "requires_target_stat_raised", "random_status_pool", "is_self_faint", "target_includes_ally",
    "steals_and_eats_berry", "ignores_target_ability",
    # [M19-steal-stats] / [M19-ally-targeting-stat-change] fields
    "steals_positive_stat_stages", "stat_change_target_ally", "also_boosts_ally",
    # [M19e] / [M19f] fields
    "heals_based_on_weather", "weather_heal_boost_type",
    "weather_heal_has_quarter_branch", "is_mean_look",
    # [M19c] / [M19d] fields
    "protect_method", "metal_burst", "is_mirror_move",
    # [D0] fields
    "is_leech_seed", "is_haze", "is_heal_bell",
    "is_leech_seed_on_hit", "is_haze_on_hit", "is_heal_bell_on_hit",
    # [D1] fields
    "ignores_redirection", "is_hidden_power",
    # [D1 cheap clusters] fields
    "weather_type", "power_scales_with_user_hp", "power_scales_with_target_hp",
    "steals_item_if_itemless", "is_lock_on", "is_swagger",
    "is_sucker_punch", "is_stored_power",
    # [D2 batch] fields
    "sets_stealth_rock_on_hit", "sets_spikes_on_hit",
    "is_defog", "is_tidy_up",
    "is_role_play", "is_skill_swap", "is_heart_swap",
    "overwrite_target_ability_id",
    # [D2 batch 2] fields
    "is_foul_play", "is_body_press", "is_photon_geyser",
    "super_effective_vs_type", "is_tar_shot", "is_foresight",
    # [D3 turn-order/event-tracker batch] fields
    "is_after_you", "is_quash", "is_upper_hand", "is_instruct",
    "is_lash_out", "is_retaliate", "is_rage_fist", "is_echoed_voice",
    # [Delayed-effect family] / [Psyshock/Psystrike] fields
    "is_future_sight", "is_wish", "is_yawn", "is_healing_wish",
    "is_lunar_dance", "is_psyshock",
    # [D1 easy bundle] fields
    "is_hit_escape", "is_hit_switch_target", "is_first_turn_only",
    "is_trick", "is_revenge", "is_stomping_tantrum",
    # [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS] fields
    "is_double_power_on_status", "double_power_status_arg", "is_smelling_salts",
    # [D4 bundle] fields
    "is_sleep_talk", "usable_while_asleep", "is_taunt", "is_assurance",
    "is_magic_coat",
    # [D4 CHEAP bundle] fields
    "requires_target_asleep", "is_torment", "is_gyro_ball", "is_electro_ball",
    "is_snore", "is_fell_stinger", "is_magnet_rise", "is_smack_down",
    "is_ingrain", "is_aqua_ring", "is_payback",
    # [D4 bundle 3] fields
    "is_do_nothing", "is_refresh", "is_purify", "is_memento",
    "hp_cost_stat_boost", "hp_cost_divisor", "is_nightmare", "is_spite",
    "is_recycle", "is_facade", "is_take_heart",
    # [D4 Bundle 4] fields
    "is_tailwind", "is_sticky_web", "is_safeguard", "is_mist",
    "is_copycat", "is_me_first", "is_assist",
    "is_heal_pulse", "is_life_dew",
    "is_stockpile", "is_spit_up", "is_swallow",
    # [D4 Bundle 5] fields
    "is_mud_sport", "is_water_sport", "is_weather_ball", "is_reflect_type",
    "is_roost", "is_strength_sap", "is_steel_beam", "is_chloroblast",
    "is_charge", "is_laser_focus", "is_topsy_turvy", "is_fury_cutter",
    # [D4 Bundle 6] fields
    "is_teleport", "is_rest", "is_false_swipe", "is_present", "is_knock_off",
    "is_endeavor", "is_brine", "is_acupressure", "is_psycho_shift",
    "is_punishment", "is_telekinesis", "is_acrobatics", "is_belch",
    "is_parting_shot", "is_venom_drench", "is_toxic_thread", "is_stuff_cheeks",
    "is_no_retreat", "is_octolock", "is_poltergeist", "is_chilly_reception",
    # [D4 Bundle 7] fields
    "is_curse", "is_focus_punch", "is_grudge", "is_last_resort",
    "is_pollen_puff", "is_beak_blast", "is_shell_trap",
    # [D4 Bundle 8] fields
    "is_round", "is_snatch", "is_imprison",
    # [D4 Bundle 9] fields
    "two_typed_move", "second_type", "is_sky_drop",
    # [Mimic/Sketch] fields
    "is_mimic", "is_sketch",
    # [Perish Song] fields
    "is_perish_song", "target",
    # [Transform] fields
    "is_transform",
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
