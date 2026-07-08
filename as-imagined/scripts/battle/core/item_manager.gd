class_name ItemManager
extends RefCounted

# Held-item mechanic implementations — M12.
# All constants sourced from include/constants/hold_effects.h (the HOLD_EFFECT enum).
# All UQ4.12 values sourced from include/fpmath.h.

# M18-patch-1: Pocket enum id, source: include/constants/item.h — POCKET_ITEMS=0,
# POCKET_POKE_BALLS=1, POCKET_TM_HM=2, POCKET_BERRIES=3, POCKET_KEY_ITEMS=4. Only
# POCKET_BERRIES is modeled — this project has no need to distinguish the other
# four pockets for any battle mechanic. Source's own TryCheekPouch
# (battle_script_commands.c:6175) gates directly on
# `GetItemPocket(itemId) == POCKET_BERRIES` at the item-removal site — this
# constant/field mirrors that exact mechanism, not a bespoke "is_berry" flag.
const POCKET_BERRIES: int = 3

# ── Hold-effect constants ─────────────────────────────────────────────────────
# Source: include/constants/hold_effects.h
const HOLD_EFFECT_NONE:          int = 0
const HOLD_EFFECT_RESTORE_HP:    int = 1    # M18b: Oran Berry — flat heal
const HOLD_EFFECT_CURE_PAR:      int = 2    # M18b: Cheri Berry
const HOLD_EFFECT_CURE_SLP:      int = 3    # M18b: Chesto Berry
const HOLD_EFFECT_CURE_PSN:      int = 4    # M18b: Pecha Berry — cures Poison AND Toxic
const HOLD_EFFECT_CURE_BRN:      int = 5    # M18b: Rawst Berry
const HOLD_EFFECT_CURE_FRZ:      int = 6    # M18b: Aspear Berry
const HOLD_EFFECT_CURE_CONFUSION: int = 8   # M18b: Persim Berry — clears confusion_turns, not status
const HOLD_EFFECT_CURE_STATUS:   int = 9    # Lum Berry — onStatusChange flag set
const HOLD_EFFECT_CHOICE_BAND:   int = 29
const HOLD_EFFECT_LEFTOVERS:     int = 41
const HOLD_EFFECT_CHOICE_SCARF:  int = 49
const HOLD_EFFECT_CHOICE_SPECS:  int = 50
const HOLD_EFFECT_DAMP_ROCK:     int = 51   # Rain → 8 turns
const HOLD_EFFECT_HEAT_ROCK:     int = 53   # Sun → 8 turns
const HOLD_EFFECT_ICY_ROCK:      int = 54   # Hail → 8 turns
const HOLD_EFFECT_SMOOTH_ROCK:   int = 56   # Sandstorm → 8 turns
const HOLD_EFFECT_LIFE_ORB:      int = 60
const HOLD_EFFECT_RESIST_BERRY:  int = 80   # type-resist berry (Occa=Fire, Wacan=Electric, …)
const HOLD_EFFECT_RESTORE_PCT_HP: int = 82  # Sitrus Berry — param=25 (25 %)
const HOLD_EFFECT_UTILITY_UMBRELLA: int = 115
const HOLD_EFFECT_HEAVY_DUTY_BOOTS: int = 119  # full immunity to entry hazards on switch-in
const HOLD_EFFECT_PLATE:         int = 89  # Multitype's held-item type source (M17n-4)
const HOLD_EFFECT_TYPE_POWER:    int = 43  # M18a: Charcoal family / Incenses / Silk Scarf / Fairy Feather
const HOLD_EFFECT_SCOPE_LENS:    int = 40  # M18e: Scope Lens AND Razor Claw — literally the same
                                            # holdEffect value in source (src/data/items.h), not two
                                            # separate constants; both grant the identical +1 crit stage
                                            # with no move-category condition (GetHoldEffectCritChanceIncrease,
                                            # battle_util.c L7795-7810)
const HOLD_EFFECT_QUICK_CLAW:    int = 26  # M18l: probabilistic act-first, param=20 (20%, read
                                            # dynamically from hold_effect_param — NOT gated on move
                                            # category, unlike Quick Draw's ability equivalent
                                            # (battle_main.c L5191 has no IsBattleMoveStatus check here)
const HOLD_EFFECT_LAGGING_TAIL:  int = 66  # M18l: Full Incense AND Lagging Tail — literally the same
                                            # holdEffect value in source (src/data/items.h L8543/L10270),
                                            # not two separate constants; both grant unconditional
                                            # always-act-last, matching Stall's shape exactly (battle_main.c
                                            # L4409-4410, no move-category gate — unlike Mycelium Might's
                                            # narrower ability equivalent)

# M18c: Berry HP-threshold effects (10 items). All 8 of the 25%-threshold berries
# below (5 flat-stat + Lansat + Starf + Custap) share holdEffectParam=4, confirmed
# uniform via direct per-item src/data/items.h read (not assumed).
const HOLD_EFFECT_ATTACK_UP:     int = 15  # Liechi Berry — +1 Atk (Ripen: +2)
const HOLD_EFFECT_DEFENSE_UP:    int = 16  # Ganlon Berry — +1 Def (Ripen: +2)
const HOLD_EFFECT_SPEED_UP:      int = 17  # Salac Berry — +1 Speed (Ripen: +2)
const HOLD_EFFECT_SP_ATTACK_UP:  int = 18  # Petaya Berry — +1 SpAtk (Ripen: +2)
const HOLD_EFFECT_SP_DEFENSE_UP: int = 19  # Apicot Berry — +1 SpDef (Ripen: +2)
const HOLD_EFFECT_CRITICAL_UP:   int = 20  # Lansat Berry — sets focus_energy (NOT
                                            # crit_stage_bonus()/M18e's mechanism — a
                                            # real correction, confirmed via source:
                                            # CriticalHitRatioUp sets
                                            # volatiles.focusEnergy=TRUE directly, the
                                            # SAME flag Focus Energy the move sets.
                                            # Ripen does NOT affect this one (confirmed
                                            # absent from source, unlike the 6 stat berries).
const HOLD_EFFECT_RANDOM_STAT_UP: int = 21 # Starf Berry — +2 to one random non-maxed
                                            # stat from {Atk,Def,SpAtk,SpDef,Speed}
                                            # (Ripen: +4) — EXCLUDES Accuracy/Evasion,
                                            # unlike Moody's own broader pool.
const HOLD_EFFECT_ENIGMA_BERRY:  int = 79  # heals 25% max HP (Ripen: 50%) when hit
                                            # DIRECTLY (not absorbed by Substitute) by a
                                            # move that resolves super-effective — NOT an
                                            # HP threshold, NOT the resist-berry TYPE-match
                                            # check; reads the actual computed
                                            # effectiveness after damage, architecturally
                                            # separate from every other item in this file.
const HOLD_EFFECT_MICLE_BERRY:   int = 83  # one-shot ×1.2 accuracy (Ripen: ×1.4) on the
                                            # holder's NEXT accuracy check only.
const HOLD_EFFECT_CUSTAP_BERRY:  int = 84  # deterministic (no roll) act-first at the HP
                                            # threshold — reuses M18l's quick_effect dict.
                                            # CORRECTION: source's turn-order check has NO
                                            # IsUnnerveBlocked call at all (a separate code
                                            # path from the general berry dispatcher) —
                                            # Custap bypasses Unnerve while Klutz/Gluttony
                                            # still apply normally.

# M18d: Leppa Berry / Jaboca Berry / Rowap Berry (3 items).
const HOLD_EFFECT_RESTORE_PP:    int = 7   # Leppa Berry — restores 10 PP (Ripen: 20)
                                            # to the FIRST zero-PP move in slot order,
                                            # checked at MoveEnd for the ATTACKER (the
                                            # mon that just acted), not tied to whether
                                            # THIS move was the one that hit 0.
const HOLD_EFFECT_JABOCA_BERRY:  int = 85  # 1/8 attacker's max HP (Ripen: 1/4) on any
                                            # PHYSICAL-category hit. CORRECTION: source
                                            # (TryJabocaBerry, battle_hold_effects.c
                                            # L332-353) checks ONLY IsBattleMovePhysical —
                                            # no IsMoveMakingContact call anywhere. Fires
                                            # even on a non-contact physical move.
const HOLD_EFFECT_ROWAP_BERRY:   int = 86  # Same as Jaboca but SPECIAL-category — same
                                            # correction applies (TryRowapBerry,
                                            # battle_hold_effects.c L355-376, checks only
                                            # IsBattleMoveSpecial, no contact check).

# M18g: species-gated stat/crit items + Soul Dew (9 items). CORRECTION: [M17n-4]
# (cited by the plan as the species-gate precedent) establishes NO species-gate
# mechanism at all — Multitype's own held-item read is a Plate-TYPE check, not a
# species check. No prior precedent exists in this codebase; built fresh here.
const HOLD_EFFECT_SOUL_DEW:      int = 33  # Latios/Latias — TYPE-BOOST ONLY under this
                                            # project's B_SOUL_DEW_BOOST=GEN_LATEST config
                                            # (>=GEN_7 resolution); NOT a SpDef stat boost
                                            # (that's the pre-Gen7 behavior, a different
                                            # mechanism this project does not implement).
const HOLD_EFFECT_DEEP_SEA_TOOTH: int = 34 # Clamperl — ×2.0 Sp.Attack, special-only.
const HOLD_EFFECT_DEEP_SEA_SCALE: int = 35 # Clamperl — ×2.0 Sp.Defense, special-only.
                                            # CORRECTION: lives in CalcDefenseStat (the
                                            # raw-stat-before-formula stage, same as
                                            # Choice Band/Specs), NOT
                                            # GetDefenseStatModifier's post-effectiveness
                                            # stage where Thick Fat/Marvel Scale/etc.
                                            # already live via AbilityManager.
                                            # defense_damage_modifier_uq412 — a
                                            # similarly-named but different function.
const HOLD_EFFECT_LIGHT_BALL:    int = 42  # Pikachu — ×2.0 BOTH Attack and Sp.Attack,
                                            # unconditional on move category (config-gated
                                            # true under GEN_LATEST).
const HOLD_EFFECT_LUCKY_PUNCH:   int = 45  # Chansey ONLY (NOT Blissey) — +2 crit stage.
const HOLD_EFFECT_METAL_POWDER:  int = 46  # Ditto — ×2.0 DEFENSE (not SpDef), physical-only.
                                            # CORRECTION: a real distinction from Quick
                                            # Powder — the two are NOT the same stat.
                                            # "Untransformed" condition is untestable in
                                            # this project: no Transform/Imposter mechanic
                                            # exists (confirmed via grep), so this gate is
                                            # vacuously always satisfied — flagged, not
                                            # silently omitted.
const HOLD_EFFECT_THICK_CLUB:    int = 47  # Cubone OR Marowak — ×2.0 Attack, physical-only.
const HOLD_EFFECT_LEEK:          int = 48  # Farfetch'd [+ Sirfetch'd(865), absent from
                                            # this project's 386-species/Gen-3-capped
                                            # roster, confirmed via direct dex lookup] —
                                            # +2 crit stage.
const HOLD_EFFECT_QUICK_POWDER:  int = 75  # Ditto — ×2.0 SPEED (not Defense). Same
                                            # untransformed-untestable note as Metal Powder.

# M18g: national_dex_num values (must match data/pokemon.json / PokemonSpecies).
const SPECIES_PIKACHU:    int = 25
const SPECIES_FARFETCHD:  int = 83
const SPECIES_CUBONE:     int = 104
const SPECIES_MAROWAK:    int = 105
const SPECIES_CHANSEY:    int = 113
const SPECIES_DITTO:      int = 132
const SPECIES_CLAMPERL:   int = 366
const SPECIES_LATIAS:     int = 380
const SPECIES_LATIOS:     int = 381
const SPECIES_KYOGRE:     int = 382  # M18w: Blue Orb
const SPECIES_GROUDON:    int = 383  # M18w: Red Orb

# M18h: EV/Power-item Speed-halving family (7 items). CORRECTION found at Step 0:
# Macho Brace does NOT share the 6 "Power X" items' hold_effect constant — it has
# its own distinct HOLD_EFFECT_MACHO_BRACE — but the actual EFFECT is identical:
# source dispatches both through one shared condition, `if (holdEffect ==
# HOLD_EFFECT_MACHO_BRACE || holdEffect == HOLD_EFFECT_POWER_ITEM) speed /= 2;`
# (battle_main.c L4699), the same chokepoint Choice Scarf/Quick Powder already
# occupy in apply_speed_modifier below. The inverse of [M18e]'s Scope Lens/Razor
# Claw finding: two DIFFERENT constants, IDENTICAL behavior (not one constant
# assumed-different, or one constant genuinely-different). The EV-doubling half
# (holdEffectParam=POWER_ITEM_BOOST, resolves to 8 under this project's
# GEN_LATEST config) is confirmed permanently moot for all 7 — re-verified
# directly via a fresh grep of every `evs[` mutation in scripts/battle/core/*.gd
# (Step 0), not trusted from a prior citation: the only writes anywhere are
# static initialization/test setup, no EV-gain mechanism exists in battle logic
# to double.
const HOLD_EFFECT_MACHO_BRACE: int = 24  # Macho Brace — own constant, same effect as below
const HOLD_EFFECT_POWER_ITEM:  int = 81  # Power Weight/Bracer/Belt/Lens/Band/Anklet (6 items)

# M18i: Status Orbs (2 items). CORRECTION found at Step 0: NOT a "first turn held"
# timer mechanic — source (TryFlameOrb/TryToxicOrb, battle_hold_effects.c L600-630)
# fires at IsOrbsActivation timing inside the STANDARD per-turn end-of-turn item
# dispatch (battle_end_turn.c L1349-1358), checked EVERY end of turn, gated only by
# CanBeBurned/CanBePoisoned (the same immunity check a move would use). It only
# ever visibly fires once because the holder then HAS the status and
# StatusManager.try_apply_status's existing "already has a status" gate blocks
# re-application — no turn counter of any kind exists in source, and none is
# built here.
const HOLD_EFFECT_FLAME_ORB: int = 68  # self-inflicts STATUS_BURN
const HOLD_EFFECT_TOXIC_ORB: int = 69  # self-inflicts STATUS_TOXIC (badly poisoned,
                                        # NOT regular STATUS_POISON)

# M18j: Power/accuracy flat-modifier misc (7 items).
# CORRECTION found at Step 0: Expert Belt is NOT in the same pipeline stage as
# Muscle Band/Wise Glasses despite the plan's "power items" grouping — source
# places it in GetAttackerItemsModifier (battle_util.c L7493, the SAME function
# this project's post_roll_modifier_uq412/Life Orb already implements), applied
# AFTER the roll/type-effectiveness — NOT CalcMoveBasePowerAfterModifiers where
# Muscle Band/Wise Glasses (and move_power_modifier_uq412) live.
const HOLD_EFFECT_MUSCLE_BAND: int = 62   # physical power x1.1, FLOORED rounding
const HOLD_EFFECT_WISE_GLASSES: int = 64  # special power x1.1, FLOORED rounding —
                                           # CORRECTION: source calls
                                           # PercentToUQ4_12_Floored ((4096*pct)/100,
                                           # no rounding) for these two, a DIFFERENT
                                           # formula than M18a's Charcoal-family items
                                           # (PercentToUQ4_12, (4096*pct+50)/100,
                                           # rounds) — a genuine 1-unit difference at
                                           # 10% (4505 floored vs. 4506 rounded).
const HOLD_EFFECT_EXPERT_BELT: int = 59   # flat x1.2 when effectiveness>=2.0 (2x OR
                                           # 4x, uniform — no extra stacking at 4x).
                                           # holdEffectParam=20 in source data but
                                           # NOT actually read — the dispatch function
                                           # hardcodes UQ_4_12(1.2)=4915 directly.
const HOLD_EFFECT_WIDE_LENS: int = 63     # attacker accuracy x1.10, unconditional
const HOLD_EFFECT_ZOOM_LENS: int = 65     # attacker accuracy x1.20, ONLY if the
                                           # target has already acted this turn —
                                           # confirmed checkable via this project's
                                           # existing _turn_order/_current_actor_index
                                           # position tracking (same infrastructure
                                           # _is_last_to_move already established for
                                           # Analytic, [M17n-5]), NOT a blocker.
const HOLD_EFFECT_EVASION_UP: int = 22    # Bright Powder AND Lax Incense — literal
                                           # same constant, both holdEffectParam=10
                                           # under this reference clone's
                                           # I_LAX_INCENSE_BOOST>=GEN_4 config —
                                           # confirmed genuinely identical, not
                                           # assumed. Defender-side accuracy x0.90
const HOLD_EFFECT_RED_CARD: int = 97      # M18n: forces the ATTACKER to switch —
                                           # closes the exact gap
                                           # AbilityManager.blocks_forced_switch's own
                                           # doc comment already anticipated ("this
                                           # project has no Red Card item").
const HOLD_EFFECT_EJECT_BUTTON: int = 100 # M18n: forces the HOLDER itself to switch —
                                           # NOT Guard-Dog-blocked, unlike Red Card
                                           # (confirmed absent from source: Guard Dog
                                           # only blocks being forced out BY AN
                                           # OPPONENT's effect).
const HOLD_EFFECT_FOCUS_BAND: int = 38    # M18o: probabilistic (param=10, 10%) survive-
                                           # lethal, NO HP gate — genuinely different
                                           # shape from Focus Sash despite the similar
                                           # name, confirmed via source: same `else if`
                                           # chain as Sturdy, checked BEFORE Focus Sash,
                                           # NOT consumed (repeatable every hit).
const HOLD_EFFECT_SHELL_BELL: int = 44    # M18q: heals 1/8 (param=8) of the FINAL
                                           # damage just dealt, gated on not-already-
                                           # at-max-HP.
const HOLD_EFFECT_BIG_ROOT: int = 58      # M18q: +30% (param=30) to move-drain healing
                                           # — source's own formula is (hp*1300)/1000,
                                           # deliberately NOT UQ4.12 despite nearly every
                                           # other item modifier in this file being so.
const HOLD_EFFECT_FOCUS_SASH: int = 67    # M18o: full-HP-gated (IsBattlerAtMaxHp, same
                                           # gate Sturdy uses), NO param/roll at all —
                                           # unconditional given full HP. SINGLE-USE,
                                           # unlike Focus Band (confirmed via
                                           # docs/changelogs/1.8.x/1.8.4.md's own "Focus
                                           # Sash but not consuming the item" bugfix
                                           # entry — no differentiating consumption call
                                           # exists in GetAdjustedDamage itself, both
                                           # items' own hold_effects.h timing entries are
                                           # empty).
const HOLD_EFFECT_FLINCH: int = 30        # M18k: King's Rock AND Razor Fang — literal
                                           # same constant, both holdEffectParam=10
                                           # (src/data/items.h), confirmed genuinely
                                           # identical. Adds a flinch roll to a move
                                           # that has NO native flinch effect of its
                                           # own (MUTUALLY EXCLUSIVE with an existing
                                           # SE_FLINCH move, not additive/stacking —
                                           # source's TryKingsRock guard is
                                           # !MoveHasAdditionalEffect(move,
                                           # MOVE_EFFECT_FLINCH)). Architecturally
                                           # separate from try_secondary_effect
                                           # entirely — dispatched from source's
                                           # onAttackerAfterHit item pipeline, not the
                                           # move-effect pipeline Sheer Force/Shield
                                           # Dust hook into, so neither interacts with
                                           # this item's roll.
                                           # against the holder.

# M18r: Standalone reuses (7 items, 7 different existing mechanisms — grouped only
# for scheduling convenience, per docs/m18_subtier_plan.md's own framing). Values
# re-derived programmatically from include/constants/hold_effects.h's enum position
# (not hand-counted), cross-validated against 8 pre-existing project constants
# (MACHO_BRACE=24, QUICK_CLAW=26, FOCUS_BAND=38, SHELL_BELL=44, BIG_ROOT=58,
# FOCUS_SASH=67, RED_CARD=97, EJECT_BUTTON=100) with zero mismatches.
const HOLD_EFFECT_LIGHT_CLAY: int = 55      # Reflect/Light Screen/Aurora Veil timer:
                                             # 8 turns instead of 5, checked on the
                                             # SETTER at set time (TrySetReflect/
                                             # TrySetLightScreen/BS_SetAuroraVeil,
                                             # battle_script_commands.c). Passive,
                                             # never consumed.
const HOLD_EFFECT_POWER_HERB: int = 57      # Skips the charge turn of a two-turn move
                                             # once (CancelerCharging, battle_move_
                                             # resolution.c L1778), consumed on use.
                                             # Semi-invulnerable moves (Fly/Dig/Dive/
                                             # Bounce) CAN fire early via this too —
                                             # source's check has no semi-inv carve-out,
                                             # unlike Solar Beam's separate sun-only
                                             # skip.
const HOLD_EFFECT_BLACK_SLUDGE: int = 72    # Poison-type holder: heals maxHP/16 (reuses
                                             # TryLeftovers exactly — Leftovers-shape).
                                             # Non-Poison holder: DAMAGES maxHP/8 (NOT
                                             # 1/16 — a correction to this tier's own
                                             # plan doc, confirmed via TryBlackSludge
                                             # Damage, battle_hold_effects.c L650),
                                             # gated by Magic Guard (the damage side
                                             # only — the heal side has no Magic Guard
                                             # interaction since it's not damage).
const HOLD_EFFECT_SHED_SHELL: int = 74      # Bypasses ability-based trapping (Shadow
                                             # Tag/Arena Trap/Magnet Pull) for VOLUNTARY
                                             # switch selection only — CanBattlerEscape,
                                             # battle_main.c L4234/4238. Passive, never
                                             # consumed. Baton Pass/faint-replacement/
                                             # forced switches (Roar etc.) already
                                             # bypass is_trapped() architecturally, per
                                             # its own doc comment, so no change needed
                                             # at those call sites.
const HOLD_EFFECT_SAFETY_GOGGLES: int = 104 # TWO independent exemptions, checked at
                                             # the SAME source sites Overcoat/Grass-type
                                             # already occupy: (1) full sandstorm/hail
                                             # chip immunity (battle_end_turn.c L151,
                                             # L174 — the exact Overcoat check site),
                                             # (2) full powder-move immunity
                                             # (IsAffectedByPowderMove, battle_util.c
                                             # L10545-10552 — the exact Overcoat/Grass-
                                             # type check site). Passive, never consumed.
const HOLD_EFFECT_ROOM_SERVICE: int = 117   # -1 Speed (if not already at -6) while
                                             # Trick Room is active. TWO independent
                                             # triggers confirmed from hold_effects.h's
                                             # own table (.onSwitchIn=TRUE AND
                                             # .onEffect=TRUE) — a correction to this
                                             # tier's own plan doc, which named only the
                                             # switch-in half: also fires the instant
                                             # Trick Room is SET, looping over every
                                             # battler already on the field (Battle
                                             # Script_EffectTrickRoom's unconditional
                                             # BattleScript_TryRoomServiceLoop call,
                                             # right after setroom). Single-use,
                                             # consumed on either trigger (removeitem in
                                             # BattleScript_ConsumableItemStatRaise).
const HOLD_EFFECT_BLUNDER_POLICY: int = 118 # +2 Speed (if not already at +6) when the
                                             # HOLDER's own move misses via a genuine
                                             # accuracy check. Explicitly excludes OHKO
                                             # moves (cv->moveEffect != EFFECT_OHKO,
                                             # battle_move_resolution.c L2212) — this
                                             # project's OHKO-miss path emits the exact
                                             # same move_missed reason=="accuracy"
                                             # string as a normal miss, so the OHKO
                                             # exclusion needs an explicit move.is_ohko
                                             # check, not just a reason-string filter.
                                             # Source's multi-hit exclusion
                                             # (!isMultiHitOn) is structurally moot here
                                             # — no multi-hit move mechanic exists
                                             # anywhere in this project (confirmed
                                             # dormant per [M17n-5]). Source's
                                             # !redCardSwitched guard (this same
                                             # resolution's attacker was NOT just forced
                                             # out by Red Card) is a real cross-tier
                                             # interaction NOT modeled here — flagged,
                                             # not built, same class as [M18n]/[M18q]'s
                                             # own flagged doubles/spread-move gaps.
                                             # Consumed only if Speed actually rose
                                             # (source's CompareStat(...,MAX_STAT_STAGE,
                                             # CMP_LESS_THAN,...) guards the whole
                                             # trigger, not just the stat-change call).

# M18s/M18u/M18w combined session (6 items). Values re-derived programmatically
# from include/constants/hold_effects.h's enum position, cross-validated against
# 7 pre-existing project constants with zero mismatches.
const HOLD_EFFECT_EVIOLITE: int = 91        # M18s: +50% Def AND SpDef (both categories,
                                             # unconditional) if CanEvolve(species) —
                                             # CalcDefenseStat (battle_util.c L7173-7180),
                                             # the SAME function Deep Sea Scale/Metal
                                             # Powder already occupy. "Not fully evolved"
                                             # = PokemonRegistry.get_evolutions(dex).size()
                                             # > 0, confirmed to exactly match source's
                                             # CanEvolve (a species with a real further
                                             # evolution; a species with ZERO possible
                                             # evolutions, e.g. Ditto, correctly gets NO
                                             # boost — same code path as fully-evolved).
                                             # Transform-species substitution
                                             # (gBattleMons[...].volatiles.transformed)
                                             # is N/A — no Transform mechanic exists here.
const HOLD_EFFECT_ASSAULT_VEST: int = 92    # M18s: +50% SpDef only (`!usesDefStat`,
                                             # special hits) — SAME function as Eviolite,
                                             # unconditional (no species/category gate on
                                             # the damage-reduction half). The move-
                                             # restriction half (status moves unusable)
                                             # is a SEPARATE mechanism — see
                                             # holds_assault_vest's own doc comment.
const HOLD_EFFECT_BERSERK_GENE: int = 129   # M18u: switch-in only (.onSwitchIn=TRUE,
                                             # no .onEffect — hold_effects.h). +2 Atk,
                                             # NO-OP entirely (no consumption, no
                                             # confusion) if Atk is already at +6
                                             # (CompareStat(...,MAX_STAT_STAGE,
                                             # CMP_EQUAL,...) guards the WHOLE function,
                                             # battle_hold_effects.c L137-138). Confusion
                                             # is INFINITE (see StatusManager.
                                             # try_apply_confusion's `infinite` param) —
                                             # a real correction to this tier's own "reuse
                                             # the existing generic confusion mechanic"
                                             # framing, found by reading TryBerserkGene
                                             # directly rather than assumed standard.
                                             # Consumed regardless of whether confusion
                                             # actually lands (Own Tempo block, etc.) —
                                             # `removeitem` sits at the battle script's
                                             # shared end label all three branches reach.
const HOLD_EFFECT_METRONOME: int = 61       # M18u: +20%/consecutive same-move use,
                                             # capped at 5 uses (+100% max). Source:
                                             # GetAttackerItemsModifier (battle_util.c
                                             # L7486-7491) — the SAME function/pipeline
                                             # stage Life Orb/Expert Belt already occupy
                                             # (post_roll_modifier_uq412 here), NOT a new
                                             # stage. Counter incremented/reset at the
                                             # exact site source colocates its own reset
                                             # check (battle_move_resolution.c L1006-1008,
                                             # right before PP deduction) — this project's
                                             # simplified reset condition is "the move
                                             # differs from last_move_used" only; source's
                                             # broader "OR unableToUseMove" half (Disable/
                                             # Taunt/no-PP/etc. all also reset it) is NOT
                                             # replicated — flagged, not built, given how
                                             # many distinct block-reasons that would mean
                                             # threading through. A miss does NOT reset
                                             # the counter (matches source: the reset
                                             # check runs before accuracy is ever rolled).
const HOLD_EFFECT_PRIMAL_ORB: int = 108     # M18w: Red Orb AND Blue Orb share this
                                             # EXACT holdEffect value in source (src/data/
                                             # items.h) — species-differentiated via each
                                             # item's own required_species (Groudon/
                                             # Kyogre), the SAME ItemData field/mechanism
                                             # M18g's species-gated items already use, NOT
                                             # a per-item holdEffect split. CORRECTION:
                                             # real Primal Reversion is a full species/
                                             # stat/type swap (SPECIES_GROUDON_PRIMAL/
                                             # SPECIES_KYOGRE_PRIMAL are literally
                                             # different species entries in source) — the
                                             # same shape as Mega Evolution, which this
                                             # project has already structurally excluded
                                             # (no form/species-swap-mid-battle
                                             # infrastructure exists). In-scope deliverable
                                             # is ability-set ONLY (Desolate Land/
                                             # Primordial Sea on switch-in), matching this
                                             # tier's own narrower "form-change + set-
                                             # ability" framing and its own note that only
                                             # the ability half was missing.

# M18m: Stat-change-reactive consumed items (4 items). Values re-derived
# programmatically, cross-validated against 7 pre-existing constants with zero
# mismatches. Despite the tier's own "stat-change-reactive" grouping, these are
# NOT all the same trigger shape — verified individually per the "never assume
# symmetry" discipline.
const HOLD_EFFECT_WEAKNESS_POLICY: int = 107 # +2 Atk AND +2 SpAtk (both,
                                              # unconditional) on taking a
                                              # super-effective hit. Source:
                                              # TryWeaknessPolicy
                                              # (battle_hold_effects.c L256-269) —
                                              # the SAME on-hit dispatch site
                                              # Enigma Berry ([M18c]) already
                                              # occupies (IsBattlerTurnDamaged +
                                              # a MOVE_RESULT_SUPER_EFFECTIVE-
                                              # equivalent effectiveness>1.0
                                              # check), not a new choke point.
const HOLD_EFFECT_WHITE_HERB: int = 23       # Resets ALL currently-negative stat
                                              # stages to 0. Source:
                                              # RestoreWhiteHerbStats
                                              # (battle_hold_effects.c L148-164)
                                              # UNCONDITIONALLY scans every stat
                                              # at every MoveEnd — genuinely NOT
                                              # gated on "a decrease just
                                              # happened THIS move," unlike Eject
                                              # Pack below despite both being
                                              # grouped as "any stat lowered" by
                                              # this tier's own plan doc. Needs no
                                              # snapshot/diff — a plain scan of
                                              # current `stat_stages` at this
                                              # project's own MoveEnd-equivalent
                                              # checkpoint (`_phase_faint_check`,
                                              # which already runs once per
                                              # resolved move regardless of
                                              # outcome) reproduces this exactly.
const HOLD_EFFECT_EJECT_PACK: int = 116      # Forces the HOLDER to switch when a
                                              # stat decrease is JUST applied to
                                              # it, from ANY source (the holder's
                                              # own move, an opponent's move,
                                              # hazards, etc. — confirmed NOT
                                              # opponent-only). Source: TryEjectPack
                                              # (battle_move_resolution.c
                                              # L4069-4088) checks a
                                              # `tryEjectPack` volatile flag SET
                                              # only at the exact moment of
                                              # application (battle_stat_change.c
                                              # L365-368) and cleared frequently —
                                              # a genuine "just happened this
                                              # resolution" trigger, reproduced
                                              # here via a stat_stages snapshot-
                                              # diff taken at the same MoveEnd-
                                              # equivalent checkpoint White Herb
                                              # uses. Reuses `_do_forced_switch_in`
                                              # and the random-replacement-pick
                                              # shape [M18n]'s Red Card/Eject
                                              # Button already established — NOT
                                              # Guard-Dog-blockable (the holder
                                              # switches itself; Guard Dog only
                                              # blocks being forced out BY an
                                              # opponent, same reasoning [M18n]'s
                                              # Eject Button already confirmed).
                                              # Source's IsPursuitTargetSet()/
                                              # HasAnyBattlerQueuedSwitch()/Sky-
                                              # Drop/Commander/Parting-Shot
                                              # exclusions are all N/A — none of
                                              # those mechanics (queued switches,
                                              # Sky Drop, Commander, Parting Shot)
                                              # exist in this project.
const HOLD_EFFECT_MIRROR_HERB: int = 123     # Copies an opponent's move-driven
                                              # stat INCREASE onto the holder,
                                              # once, consumed. Source confirms
                                              # this is a genuine structural twin
                                              # of Opportunist ([M17n-8]) at the
                                              # SOURCE level, not just "similar
                                              # enough to reuse" — both are
                                              # checked in the LITERAL SAME loop
                                              # (battle_stat_change.c L430-449),
                                              # so Opportunist's own documented
                                              # scope limit ("primary move-driven
                                              # stat increases only, not
                                              # Moxie/Download-style ability-
                                              # driven ones") is a shared source-
                                              # level limitation, correctly
                                              # inherited here too, not a new
                                              # simplification. Source additionally
                                              # QUEUES and batches the copy until
                                              # MoveEnd (gQueuedStatBoosts,
                                              # src/battle_main.c) since Mirror
                                              # Herb is single-use unlike
                                              # Opportunist's permanent-ability
                                              # repeatability — simplified here to
                                              # an immediate copy-and-consume
                                              # (matching Opportunist's own
                                              # immediate-apply shape), since this
                                              # project's one-stat-per-move
                                              # architecture means a second
                                              # qualifying trigger could never
                                              # occur before the single-use item
                                              # is already spent.

# M18p: Contact-reactive damage family (4 items). Values re-derived
# programmatically, cross-validated against 6 pre-existing constants
# (MACHO_BRACE=24, QUICK_CLAW=26, FOCUS_BAND=38, SHELL_BELL=44, BIG_ROOT=58,
# FOCUS_SASH=67) plus RED_CARD=97/EJECT_BUTTON=100 landing at their
# already-established values, zero mismatches. Despite the "contact-reactive
# family" grouping, Protective Pads and Punching Glove sit at TWO DIFFERENT
# LEVELS of the same source function pair (IsMoveMakingContact vs. its
# CanBattlerAvoidContactEffects wrapper) — see AbilityManager.move_makes_contact
# and .move_triggers_contact_retaliation's own doc comments for the full
# citation; this is the real "don't assume family symmetry" finding for this
# tier, not a contact-vs-category confusion like [M18d]'s.
const HOLD_EFFECT_STICKY_BARB: int = 70       # TWO independent triggers, source-
                                               # confirmed genuinely unrelated to
                                               # each other beyond sharing an
                                               # item: (a) TryStickyBarbOnTargetHit
                                               # (battle_hold_effects.c L564-583) —
                                               # contact-gated, transfers the item
                                               # from holder to attacker, explicitly
                                               # "No sticky hold checks" in source
                                               # (confirmed: CanStealItem/
                                               # CanBattlerGetOrLoseItem, read in
                                               # full, have ZERO Sticky Hold
                                               # reference anywhere — a genuine
                                               # exception to this project's own
                                               # _try_steal_item's baked-in Sticky
                                               # Hold gate, which Pickpocket/
                                               # Magician both rely on unmodified);
                                               # (b) TryStickyBarbOnEndTurn
                                               # (L585-599) — unconditional maxHP/8
                                               # self-damage every end of turn,
                                               # gated by the HOLDER's own Magic
                                               # Guard, dispatched via IsOrbsActivation
                                               # alongside Flame/Toxic Orb — NOT
                                               # contact-related at all.
const HOLD_EFFECT_ROCKY_HELMET: int = 95      # Contact-gated ONLY (no category
                                               # check) — TryRockyHelmet
                                               # (battle_hold_effects.c L236-254):
                                               # holder takes direct damage from a
                                               # contact move → maxHP/6 retaliation
                                               # to the ATTACKER, gated on attacker
                                               # alive and the ATTACKER's own Magic
                                               # Guard (not the holder's — same
                                               # shape [M18d]'s Jaboca/Rowap already
                                               # established for "who takes the
                                               # damage owns the Magic Guard check").
                                               # Not consumed (holdEffectParam=0,
                                               # passive item).
const HOLD_EFFECT_PROTECTIVE_PADS: int = 109  # Has NO ItemBattleEffects case of
                                               # its own — confirmed via grep, it's
                                               # purely a gate inside
                                               # CanBattlerAvoidContactEffects
                                               # (battle_util.c L5717-5726), ONE
                                               # LEVEL ABOVE IsMoveMakingContact,
                                               # applied at every genuine
                                               # contact-RETALIATION site (Rough
                                               # Skin/Iron Barbs/Static/Flame Body/
                                               # Poison Point/Effect Spore/Mummy/
                                               # Wandering Spirit/Gooey/Tangling
                                               # Hair/Pickpocket/Rocky Helmet/Sticky
                                               # Barb-transfer/Aftermath — confirmed
                                               # by reading every
                                               # CanBattlerAvoidContactEffects call
                                               # site directly). Deliberately does
                                               # NOT apply to Tough Claws' power
                                               # boost, Poison Touch's own contact
                                               # check, or Fluffy's defense
                                               # modifier — those three call the
                                               # narrower IsMoveMakingContact
                                               # directly in source, bypassing the
                                               # Protective Pads gate entirely
                                               # (confirmed via direct grep of every
                                               # raw IsMoveMakingContact call site).
const HOLD_EFFECT_PUNCHING_GLOVE: int = 124   # TWO parts, source-confirmed
                                               # genuinely different in scope from
                                               # Protective Pads above despite the
                                               # family resemblance: (a) ×1.1 power
                                               # on punching moves
                                               # (GetAttackerItemsModifier,
                                               # battle_util.c L6664-6666), same
                                               # modifier chain as Iron Fist
                                               # ([M17n-5]'s move_power_modifier_uq412,
                                               # reusing the already-wired
                                               # `punching_move` MoveData flag); (b)
                                               # strips the contact flag from the
                                               # HOLDER's own punching moves —
                                               # lives INSIDE IsMoveMakingContact
                                               # itself (battle_util.c L5735-5738),
                                               # the SAME level as Long Reach's
                                               # exemption, so it universally
                                               # affects EVERY consumer of
                                               # move_makes_contact (Tough Claws
                                               # included), unlike Protective Pads'
                                               # narrower retaliation-only scope.

# M18t: Iron Ball / Air Balloon. Values re-derived programmatically,
# cross-validated against 6 pre-existing constants, zero mismatches.
const HOLD_EFFECT_IRON_BALL: int = 71    # TWO independent effects, confirmed
                                          # from source not to share any code
                                          # path: (a) unconditionally grounds
                                          # the holder — highest-priority
                                          # override in source's own
                                          # IsBattlerGroundedInverseCheck chain
                                          # (battle_util.c L5879-5894), beating
                                          # even Levitate/Air Balloon/Flying-
                                          # type; wired into BOTH
                                          # AbilityManager.is_grounded (hazards/
                                          # Arena Trap) and
                                          # .blocks_move_type/TypeChart's new
                                          # grounded_override param (damage-calc
                                          # Ground-move immunity, both the
                                          # Levitate ability-check AND the raw
                                          # Flying-type table entry); (b) halves
                                          # Speed, unconditional, SAME magnitude
                                          # as Macho Brace/Power Item
                                          # (battle_main.c L4701-4702) — a
                                          # wholly separate pipeline stage, no
                                          # shared code with the grounding half.
const HOLD_EFFECT_AIR_BALLOON: int = 96  # Grants Ground-move immunity (added
                                          # to the "ungrounded" set alongside
                                          # Levitate — TryAirBalloon,
                                          # battle_hold_effects.c L213-234).
                                          # CORRECTION to a plausible wrong
                                          # assumption: consumption is NOT
                                          # "this Pokemon just blocked a Ground
                                          # move" — it's `IsBattlerTurnDamaged
                                          # (battler, INCLUDING_SUBSTITUTES)`,
                                          # i.e. pops from ANY damaging hit
                                          # landing (Ground-type or not), even
                                          # one absorbed entirely by
                                          # Substitute. A blocked Ground hit
                                          # deals 0 damage so it correctly
                                          # never pops from the hit it just
                                          # deflected. The INCLUDING_SUBSTITUTES
                                          # semantic means this project's
                                          # consumption check must sit BEFORE
                                          # the existing `went_to_sub` early-
                                          # return in `_do_damaging_hit` — same
                                          # placement Rapid Spin already
                                          # established for the identical
                                          # reason. Source's switch-in flavor-
                                          # text half (TryAirBalloon's `else if
                                          # switchIn` branch) is a pure message,
                                          # no mechanical effect — confirmed
                                          # out of scope, matching this
                                          # project's established cosmetic-
                                          # no-op precedent ([M17c]'s
                                          # Anticipation/Forewarn/Frisk).

# Weather duration with the matching rock item vs. without.
# Source: TryChangeBattleWeather (battle_util.c L1993–1996): 8 if rock holder, else 5.
const WEATHER_DURATION_ROCK: int    = 8
const WEATHER_DURATION_DEFAULT: int = 5

# UQ4.12 multipliers.
# Source: include/fpmath.h :: UQ_4_12(n) = round(n * 4096).
# Life Orb uses UQ_4_12_FLOORED(1.3) = floor(1.3 * 4096) = 5324 (see GetAttackerItemsModifier).
const UQ412_CHOICE_MULT: int     = 6144   # 1.5 × — Band, Specs
const UQ412_LIFE_ORB: int        = 5324   # 1.3 × (floored) — Life Orb damage boost
const UQ412_RESIST_BERRY: int    = 2048   # 0.5 × — Resist Berry halving
const UQ412_RIPEN_RESIST_BERRY: int = 1024  # 0.25 × — Resist Berry halving, doubled by Ripen
const UQ412_TYPE_BOOST: int      = 4915   # 1.2 × — matching-type held item (M18a)
const UQ412_DOUBLE: int          = 8192   # 2.0 × — M18g species-gated stat items
const UQ412_EXPERT_BELT: int     = 4915   # 1.2 × (hardcoded UQ_4_12(1.2) in source,
                                           # NOT read from hold_effect_param despite
                                           # items.h storing 20 there) — numerically
                                           # identical to UQ412_TYPE_BOOST but a
                                           # separate constant: different function,
                                           # different pipeline stage, different
                                           # source formula (plain macro rounding,
                                           # not PercentToUQ4_12)
const UQ412_PUNCHING_GLOVE: int  = 4506   # 1.1 × (M18p) — round(1.1*4096)=4506, a
                                           # hardcoded UQ_4_12(1.1) literal in source
                                           # (battle_util.c L6664-6666), NOT the
                                           # FLOORED param-driven formula Muscle
                                           # Band/Wise Glasses use — verified
                                           # directly, not assumed to share their
                                           # rounding.


# ── Attack-stat item modifier (applied to stat, BEFORE base formula) ──────────
#
# Source: GetAttackStatModifier (battle_util.c L6989–6996).
#   BAND boosts physical attack; SPECS boosts special attack.
#   SCARF has no attack-stat modifier.
#
# Returns the UQ4.12 multiplier to apply to the relevant attack stat.
# Caller is responsible for checking move category (0=physical, 1=special).

# M17n-7: Klutz — the holder's own held item has no effect. Source:
# GetBattlerHoldEffectInternal (battle_util.c L5674-5692), the SINGLE chokepoint
# every held-item read in source funnels through: `if (ability == ABILITY_KLUTZ &&
# !gastroAcid) return HOLD_EFFECT_NONE`. No canonical exceptions apply here — the
# real games' Macho Brace/Power items/Iron Ball exemptions exist because those
# items are read via a DIFFERENT, raw parameter path in `GetBattlerTotalSpeedStat`
# rather than through this chokepoint, but this project implements NONE of those
# three items (confirmed via grep of HOLD_EFFECT_* constants below) — so the
# exception question is moot for every item this project actually models; Klutz
# suppresses all of them uniformly, matching this project's own scope. Gastro
# Acid (the ability-suppression status that would exempt a Klutz holder) is not
# implemented in this project either — moot, not silently dropped.
# Mirrors `AbilityManager.effective_ability_id`'s established shared-chokepoint
# pattern (`[M17g]`) rather than gating each of this file's ~13 functions
# ad-hoc — the same "build one accessor, retrofit every reader" precedent.
static func effective_held_item(mon: BattlePokemon, ng_active: bool = false) -> ItemData:
	if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_KLUTZ:
		return null
	return mon.held_item


# M18g: species gate for Light Ball/Thick Club/Lucky Punch/Metal Powder/Quick
# Powder/Deep Sea Scale/Deep Sea Tooth/Soul Dew/Leek. `item.required_species == 0`
# means unrestricted (every other item in this file). No prior precedent for this
# check existed anywhere in the codebase before this tier — see the
# HOLD_EFFECT_SOUL_DEW constant's own doc comment for the [M17n-4] correction.
static func _species_matches(mon: BattlePokemon, item: ItemData) -> bool:
	if item.required_species == 0:
		return true
	var dex: int = mon.species.national_dex_num
	return dex == item.required_species or \
			(item.required_species2 != 0 and dex == item.required_species2)


static func attack_modifier_uq412(mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	var he: int = item.hold_effect
	if he == HOLD_EFFECT_CHOICE_BAND and move.category == 0:
		return UQ412_CHOICE_MULT
	if he == HOLD_EFFECT_CHOICE_SPECS and move.category == 1:
		return UQ412_CHOICE_MULT
	# M18g: Thick Club (Cubone/Marowak, physical-only), Deep Sea Tooth (Clamperl,
	# special-only), Light Ball (Pikachu, ANY category — B_LIGHT_BALL_ATTACK_BOOST
	# resolves >=GEN_4 under this project's GEN_LATEST config, so the category OR
	# is unconditionally satisfied). Same pipeline stage as Choice Band/Specs
	# above (CalcAttackStat, battle_util.c L6977-6989), confirmed via source.
	if he == HOLD_EFFECT_THICK_CLUB and move.category == 0 and _species_matches(mon, item):
		return UQ412_DOUBLE
	if he == HOLD_EFFECT_DEEP_SEA_TOOTH and move.category == 1 and _species_matches(mon, item):
		return UQ412_DOUBLE
	if he == HOLD_EFFECT_LIGHT_BALL and _species_matches(mon, item):
		return UQ412_DOUBLE
	return 4096


# M18s: "not fully evolved" check for Eviolite. Source: CanEvolve (battle_util.c
# L7006-7020) — TRUE iff the species has at least one evolution entry with a
# valid target species, checked against GetSpeciesEvolutions' raw table (no
# level/method/region filtering). This project's data/evolutions.json (loaded via
# PokemonRegistry.get_evolutions) is generated from that exact same source table,
# so a plain size()>0 check reproduces CanEvolve exactly — confirmed by reading
# CanEvolve directly, not assumed. A species with ZERO possible evolutions (e.g.
# Ditto) and a species that's simply fully-evolved both correctly return an empty
# list here — same false result, same non-boost outcome as source. First read of
# PokemonRegistry from anywhere under scripts/battle/core/ — a new but small
# cross-cutting dependency, flagged per this project's own discipline for such
# firsts (mirrors [M18g]'s own "no prior species-gate precedent" note).
static func _can_evolve(mon: BattlePokemon) -> bool:
	return not PokemonRegistry.get_evolutions(mon.species.national_dex_num).is_empty()


# M18g: item-driven DEFENSE stat modifier (Deep Sea Scale, Metal Powder). M18s
# extends this SAME pipeline stage with Eviolite/Assault Vest — a genuinely NEW
# pipeline stage as of M18g, since no item-side defense-stat modifier existed in
# this project before that tier.
# Source: CalcDefenseStat's own switch (battle_util.c L7160-7189) — the raw-stat-
# before-formula stage, confirmed DISTINCT from GetDefenseStatModifier's post-
# effectiveness stage (AbilityManager.defense_damage_modifier_uq412, a similarly
# named but different function where Thick Fat/Marvel Scale/etc. already live).
# Deep Sea Scale: Clamperl, special-only (`!usesDefStat`). Metal Powder: Ditto,
# physical-only (`usesDefStat`) — the "untransformed" condition is vacuously
# always true in this project (no Transform/Imposter mechanic exists).
# Eviolite: BOTH categories (unconditional on move.category, unlike the two
# species-gated items above), gated on `_can_evolve` instead of species.
# Assault Vest: special-only, unconditional (no species/evolution gate at all).
static func defense_stat_modifier_uq412(mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	if item.hold_effect == HOLD_EFFECT_DEEP_SEA_SCALE and move.category == 1 and _species_matches(mon, item):
		return UQ412_DOUBLE
	if item.hold_effect == HOLD_EFFECT_METAL_POWDER and move.category == 0 and _species_matches(mon, item):
		return UQ412_DOUBLE
	if item.hold_effect == HOLD_EFFECT_EVIOLITE and _can_evolve(mon):
		return UQ412_CHOICE_MULT
	if item.hold_effect == HOLD_EFFECT_ASSAULT_VEST and move.category == 1:
		return UQ412_CHOICE_MULT
	return 4096


# ── Post-roll attacker item modifier (Life Orb) ───────────────────────────────
#
# Source: GetAttackerItemsModifier (battle_util.c L7497–7499) called from
#   GetOtherModifiers → ApplyModifiersAfterDmgRoll (AFTER roll, STAB, type eff, burn).

static func post_roll_modifier_uq412(mon: BattlePokemon, ng_active: bool = false,
		effectiveness: float = 1.0) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	if item.hold_effect == HOLD_EFFECT_LIFE_ORB:
		return UQ412_LIFE_ORB
	# M18j: Expert Belt — flat x1.2 when effectiveness >= 2.0 (2x OR 4x, uniform,
	# confirmed no extra stacking at 4x — source's condition is `>=`, not `==`).
	# Source: GetAttackerItemsModifier (battle_util.c L7493-7495), the SAME
	# function/pipeline stage Life Orb above already occupies — a real
	# correction to the plan's "power items" grouping with Muscle Band/Wise
	# Glasses, which live in a completely different function.
	if item.hold_effect == HOLD_EFFECT_EXPERT_BELT and effectiveness >= 2.0:
		return UQ412_EXPERT_BELT
	# M18u: Metronome item — +20%/consecutive same-move use, capped at 5 uses
	# (+100% max). Source: GetAttackerItemsModifier's own HOLD_EFFECT_METRONOME
	# case (battle_util.c L7486-7491) — the SAME function Life Orb/Expert Belt
	# above already occupy. `PercentToUQ4_12(percent) = (4096*percent+50)/100`
	# (source's own rounding formula, battle_util.c L965-967) — at param=20,
	# counter=5: 4096+819*5=8191, not a clean 8192; source's own comment notes
	# this off-by-one "will never really matter" given the domain of real damage
	# numbers, so it's reproduced faithfully rather than "cleaned up."
	if item.hold_effect == HOLD_EFFECT_METRONOME:
		var boost_per_use: int = (4096 * item.hold_effect_param + 50) / 100
		var capped_uses: int = min(mon.metronome_item_counter, 5)
		return 4096 + boost_per_use * capped_uses
	return 4096


# ── Post-roll defender item modifier (Resist Berry) ───────────────────────────
#
# Source: GetDefenderItemsModifier (battle_util.c L7510–7524) called from
#   GetOtherModifiers → AFTER Life Orb, AFTER type effectiveness.
# Triggers when the move's type matches the berry's param type AND
#   (the move is TYPE_NORMAL OR effectiveness is ≥ 2.0×):
#   `ctx->moveType == GetBattlerHoldEffectParam(...) && (ctx->moveType == TYPE_NORMAL ||
#    ctx->typeEffectivenessModifier >= UQ_4_12(2.0))` (L7513). The TYPE_NORMAL bypass exists
#   because Normal-type moves can never be super-effective (no type resists Normal at 2×+),
#   so Chilan Berry (Normal-resist, param=TYPE_NORMAL) would be permanently unreachable
#   without it — Follow-up fixes session, 2026-07-02; previously an unwired gap (M12
#   decisions.md gap I2), Chilan Berry was the only resist berry this bypass applies to.
# The berry is consumed on trigger — BattleManager must call _consume_item().
#
# M17c: Ripen doubles the resist berry's effectiveness — 0.25× instead of 0.5×.
# Source: battle_util.c :: GetDefenderItemsModifier (L7519): `(ctx->abilities[ctx->
#   battlerDef] == ABILITY_RIPEN) ? UQ_4_12(0.25) : UQ_4_12(0.5)`. Direct extension of
#   this existing function (it already takes the full BattlePokemon and can read its
#   ability), no new plumbing needed.

# M17n-7: Unnerve — opposing Pokémon can't eat berries at all while the Unnerve
# holder is on the field. Source: `IsUnnerveBlocked` (battle_util.c L333-343),
# gated on `GetItemPocket(itemId) == POCKET_BERRIES` (non-berry items — Leftovers,
# Life Orb, Choice items, Utility Umbrella, Heavy Duty Boots, Plate — are
# unaffected, confirmed from source; this project's `_consume_item` choke point
# already only ever handles berries in practice, matching Cheek Pouch's own
# established precedent) and `IsUnnerveAbilityOnOpposingSide` (checked field-wide —
# ANY live opposing battler with Unnerve blocks it, not per-hit/per-turn).
# `unnerve_active` is resolved by the caller (BattleManager, via a new
# `is_unnerve_active` helper mirroring `[M17f]`'s `_get_live_opponents` shape) since
# this stateless function has no access to the full combatant list.
static func defender_item_modifier_uq412(defender: BattlePokemon,
		move: MoveData, effectiveness: float, ng_active: bool = false,
		unnerve_active: bool = false) -> int:
	var item: ItemData = effective_held_item(defender, ng_active)
	if item == null:
		return 4096
	if item.hold_effect != HOLD_EFFECT_RESIST_BERRY:
		return 4096
	if unnerve_active:
		return 4096
	# Berry param = the type it resists (e.g. Occa Berry param = TYPE_FIRE).
	if item.hold_effect_param != move.type:
		return 4096
	if move.type != TypeChart.TYPE_NORMAL and effectiveness < 2.0:
		return 4096
	if defender.ability != null and defender.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		return UQ412_RIPEN_RESIST_BERRY
	return UQ412_RESIST_BERRY


# Returns true when the resist berry should trigger (and be consumed) for this hit.
static func defender_berry_consumed(defender: BattlePokemon,
		move: MoveData, effectiveness: float, ng_active: bool = false,
		unnerve_active: bool = false) -> bool:
	return defender_item_modifier_uq412(
			defender, move, effectiveness, ng_active, unnerve_active) != 4096


# ── Speed modifier (Choice Scarf) ─────────────────────────────────────────────
#
# Source: battle_main.c GetChoiceScarf case — integer arithmetic: (speed * 150) / 100.
# NOT UQ4.12 — intentional; matches source.

static func apply_speed_modifier(mon: BattlePokemon, speed: int, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return speed
	if item.hold_effect == HOLD_EFFECT_CHOICE_SCARF:
		return (speed * 150) / 100
	# M18g: Quick Powder — Ditto, ×2.0 SPEED (a DIFFERENT stat than Metal Powder's
	# Defense — confirmed via source, a real correction, not a matched-pair
	# assumption). Source: battle_main.c L4705, the same speed-pipeline chokepoint
	# Choice Scarf occupies above.
	if item.hold_effect == HOLD_EFFECT_QUICK_POWDER and _species_matches(mon, item):
		return speed * 2
	# M18h: Macho Brace / Power Weight/Bracer/Belt/Lens/Band/Anklet — halve Speed,
	# unconditional, no species/category gate. Two distinct hold_effect constants
	# (see their own doc comments above), one shared OR'd branch, matching
	# source's identical dispatch shape exactly.
	if item.hold_effect == HOLD_EFFECT_MACHO_BRACE or item.hold_effect == HOLD_EFFECT_POWER_ITEM:
		return speed / 2
	# M18t: Iron Ball — halves Speed too, unconditional, SAME magnitude as Macho
	# Brace/Power Item above. Source (battle_main.c L4701-4702) keeps this as its
	# own separate `else if` branch rather than folding it into the Macho
	# Brace/Power Item OR — functionally identical here regardless (a Pokémon
	# holds exactly one item), kept as a distinct branch to mirror source and for
	# doc-comment clarity. Independent of Iron Ball's OTHER effect (grounding,
	# AbilityManager.is_grounded/.blocks_move_type) — this is a completely
	# separate pipeline stage, confirmed no shared code path.
	if item.hold_effect == HOLD_EFFECT_IRON_BALL:
		return speed / 2
	return speed


# ── Life Orb recoil ───────────────────────────────────────────────────────────
#
# Source: TryLifeOrb (battle_hold_effects.c L547–562): recoil = max_hp / 10.
# Fires at MoveEnd after damage (MoveEndLifeOrbShellBell, battle_move_resolution.c L3819).
# Returns the recoil amount; BattleManager applies it and emits item_damage.

static func life_orb_recoil(mon: BattlePokemon, ng_active: bool = false) -> int:
	# M17n-9: Magic Guard — Life Orb recoil is gated by it too (battle_hold_effects.c
	# TryLifeOrb, L547-559: `!IsAbilityAndRecord(...MAGIC_GUARD)`), the same as every
	# other indirect-damage source. Checked before the item lookup since a held item
	# and an ability are independent — no ordering dependency, just fail fast.
	if AbilityManager.blocks_indirect_damage(mon, ng_active):
		return 0
	var item: ItemData = effective_held_item(mon, ng_active)
	if item != null and item.hold_effect == HOLD_EFFECT_LIFE_ORB:
		return max(1, mon.max_hp / 10)
	return 0


# ── Leftovers EOT heal ────────────────────────────────────────────────────────
#
# Source: TryLeftovers (battle_hold_effects.c L634–648): heal = max_hp / 16.
# Fires at EOT via FIRST_EVENT_BLOCK_HEAL_ITEMS (after status damage).
# Returns 0 if already at full HP (source: ItemHealHp early-exits when hp == max_hp).

static func leftovers_heal(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_LEFTOVERS:
		return 0
	if mon.current_hp >= mon.max_hp:
		return 0
	return max(1, mon.max_hp / 16)


# ── HP-threshold berries (Sitrus / Oran) ───────────────────────────────────────
#
# Source: HasEnoughHpToEatBerry (battle_util.c L5461–5476): threshold = max_hp / hpFraction.
#   Sitrus Berry AND Oran Berry (M18b) both hardcode hpFraction=2 — confirmed both
#   are the SAME single caller, ItemHealHp (battle_hold_effects.c L826-849), which
#   always calls HasEnoughHpToEatBerry(..., 2, ...) regardless of which of the two
#   hold_effect cases dispatched into it. Only the AMOUNT differs:
#     HOLD_EFFECT_RESTORE_PCT_HP (Sitrus): heal = max_hp * param / 100, param=25.
#     HOLD_EFFECT_RESTORE_HP (Oran, M18b): heal = param directly (flat), param=10.
#   Renamed from sitrus_berry_heal (M18b) — this function now covers both, since
#   both share every gate below (Klutz/Unnerve/Gluttony/Cud-Chew-override/Ripen)
#   identically; only the final amount computation branches.
# Fires at MoveEnd after damage (MoveEndHpThresholdItemsTarget, battle_move_resolution.c).
# Returns heal amount if triggered, 0 otherwise. Berry is consumed on trigger.

# M17n-7: `ng_active`/`unnerve_active` — Klutz (this mon's own) and Unnerve (any
# live opponent's) gates, same shape as the resist-berry function above.
# `override_item` — M17n-7: Cud Chew's re-trigger reuses this SAME heal check one
# turn later, but against `BattlePokemon.last_consumed_berry` rather than the
# CURRENT `held_item` (which is null by the time Cud Chew fires, per source — the
# physical item is never restored, only the effect script re-runs). Source's own
# `BattleScript_CudChewActivates` sets `gBattleScripting.overrideBerryRequirements`
# around its `consumeberry` call, and BOTH `HasEnoughHpToEatBerry` (battle_util.c
# L5465, returns TRUE unconditionally when the flag is set) and `IsUnnerveBlocked`
# (battle_util.c L338, returns FALSE unconditionally) key off that exact flag — so
# `override_item != null` bypasses BOTH the HP threshold AND `unnerve_active` here,
# not just `effective_held_item`. The one exception `ItemHealHp` itself still
# enforces even under override (battle_hold_effects.c L831: `!(override &&
# hp == maxHP)`) is a plain already-at-full-HP no-op, reproduced below directly.
# Klutz is moot in the override branch regardless (Klutz and Cud Chew can never
# coexist on the same holder, since a Pokémon has exactly one ability).
static func hp_threshold_berry_heal(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> int:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or (item.hold_effect != HOLD_EFFECT_RESTORE_PCT_HP
			and item.hold_effect != HOLD_EFFECT_RESTORE_HP):
		return 0
	if override_item != null:
		if mon.current_hp >= mon.max_hp:
			return 0
	else:
		if unnerve_active:
			return 0
		# M17n-7: Gluttony lowers the eat-early threshold's fraction from a stricter
		# value to 2 (50%) for berries whose normal fraction is <=4 (25%-or-stricter).
		# Sitrus Berry's fraction is hardcoded to 2 in source regardless of ability
		# (ItemHealHp always calls HasEnoughHpToEatBerry(..., 2, ...)) — already at the
		# exact value Gluttony would move a stricter berry to, so this call is a
		# confirmed no-op for Sitrus specifically (2 in, 2 out) — see
		# AbilityManager.gluttony_adjusted_hp_fraction's own doc comment for why no
		# currently-implemented berry is actually affected, and why this is wired in
		# generically anyway rather than left unimplemented.
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, 2, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return 0
	var heal_amount: int
	if item.hold_effect == HOLD_EFFECT_RESTORE_PCT_HP:
		heal_amount = mon.max_hp * item.hold_effect_param / 100  # 25 for Sitrus Berry
	else:
		heal_amount = item.hold_effect_param  # 10 for Oran Berry, flat (M18b)
	# M18b: Ripen doubles the heal amount for BOTH modes — source: ItemHealHp
	# (battle_hold_effects.c L841-842): `ability == ABILITY_RIPEN && GetItemPocket
	# == POCKET_BERRIES → healAmount *= 2`, applied AFTER the amount is computed,
	# identically regardless of percent-vs-flat mode. NOTE: this is a genuinely new
	# addition — the pre-M18b Sitrus path never implemented Ripen-doubles-heal
	# (only Ripen-doubles-resist-berry existed, in defender_item_modifier_uq412
	# above, [M17c]); confirmed via source this was a real pre-existing gap in
	# Sitrus's own implementation, not something M18b broke — fixed here since
	# writing this function's amount-computation correctly from scratch either
	# includes it or knowingly omits it, and omitting a confirmed source behavior
	# without a reason wouldn't be defensible. Flagged in docs/decisions.md.
	if mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		heal_amount *= 2
	return max(1, heal_amount)


# ── Status-cure berries (Lum / Cheri / Chesto / Pecha / Rawst / Aspear) ────────
#
# Source: gHoldEffectsInfo (hold_effects.h) — CURE_STATUS has onStatusChange=TRUE.
#   Fires in ItemBattleEffects when any non-volatile status is inflicted (ITEMEFFECT_CURE_STATUS).
#   Source function: TryCureAnyStatus (battle_hold_effects.c L764+) for Lum Berry.
# M18b: Cheri/Chesto/Pecha/Rawst/Aspear each have their OWN distinct hold_effect
#   constant in source (HOLD_EFFECT_CURE_PAR/SLP/PSN/BRN/FRZ) — confirmed via
#   src/data/items.h direct read that NONE of them use HOLD_EFFECT_CURE_STATUS
#   (that one is Lum Berry-exclusive). Source functions: TryCureParalysis/
#   TryCurePoison/TryCureBurn/TryCureFreezeOrFrostbite/TryCureSleep
#   (battle_hold_effects.c L665-748), each a direct single-status check against
#   status1. Renamed from lum_berry_cures (M18b) to reflect the broadened scope;
#   every existing call site already threads through this one function, so no
#   BattleManager call site needed to change shape, only this function's own body.
# TryCurePoison (source L680-692) checks STATUS1_PSN_ANY, not just plain poison —
#   Pecha Berry cures BOTH regular Poison and Toxic. Reproduced below via an `or`.
# Returns true when the berry should cure and be consumed.
# M17n-7: `ng_active`/`unnerve_active`/`override_item` — same shape as
# hp_threshold_berry_heal above (Cud Chew's re-trigger reuses this for any of these
# six berries too, automatically, once wired — no Cud Chew call-site change needed
# beyond what M17n-7 already built).
# `TryCureAnyStatus`/its five per-status siblings have no HP-threshold gate to
# begin with, so `override_item`'s only effect here is bypassing `unnerve_active`
# (matching `IsUnnerveBlocked`'s `overrideBerryRequirements` check, battle_util.c
# L338) — see hp_threshold_berry_heal's doc comment for the full source citation.
static func status_cure_berry_cures(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> bool:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null:
		return false
	if override_item == null and unnerve_active:
		return false
	match item.hold_effect:
		HOLD_EFFECT_CURE_STATUS:
			return mon.status != BattlePokemon.STATUS_NONE
		HOLD_EFFECT_CURE_PAR:
			return mon.status == BattlePokemon.STATUS_PARALYSIS
		HOLD_EFFECT_CURE_SLP:
			return mon.status == BattlePokemon.STATUS_SLEEP
		HOLD_EFFECT_CURE_PSN:
			return mon.status == BattlePokemon.STATUS_POISON or mon.status == BattlePokemon.STATUS_TOXIC
		HOLD_EFFECT_CURE_BRN:
			return mon.status == BattlePokemon.STATUS_BURN
		HOLD_EFFECT_CURE_FRZ:
			return mon.status == BattlePokemon.STATUS_FREEZE
		_:
			return false


# ── Persim Berry (confusion cure) ──────────────────────────────────────────────
#
# Source: TryCureConfusion (battle_hold_effects.c L750-761): checks
#   volatiles.confusionTurns > 0, clears it. Architecturally separate from
#   status_cure_berry_cures above — confusion is a VOLATILE (this project's
#   BattlePokemon.confusion_turns), not part of .status at all, so it cannot
#   share that function's dispatch (which only ever reads/clears .status).
# M17n-7: `ng_active`/`unnerve_active`/`override_item` — same shape as the two
# functions above (Cud Chew's re-trigger reuses this for Persim Berry too, via a
# new third branch in BattleManager's Cud Chew match statement).
static func confusion_cure_berry_cures(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> bool:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_CURE_CONFUSION:
		return false
	if override_item == null and unnerve_active:
		return false
	return mon.confusion_turns > 0


# ── Weather duration ──────────────────────────────────────────────────────────
#
# Source: TryChangeBattleWeather (battle_util.c L1993–1996):
#   if (GetBattlerHoldEffect(setter) == sBattleWeatherInfo[weather].rock) duration=8 else 5.
# Rock↔weather mapping from sBattleWeatherInfo in battle_util.c:
#   RAIN → DAMP_ROCK, SUN → HEAT_ROCK, HAIL → ICY_ROCK, SANDSTORM → SMOOTH_ROCK.

static func weather_duration(setter: BattlePokemon,
		weather_type: int, ng_active: bool = false) -> int:
	if setter == null:
		return WEATHER_DURATION_DEFAULT
	var item: ItemData = effective_held_item(setter, ng_active)
	if item == null:
		return WEATHER_DURATION_DEFAULT
	var he: int = item.hold_effect
	match weather_type:
		DamageCalculator.WEATHER_RAIN:
			if he == HOLD_EFFECT_DAMP_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_SUN:
			if he == HOLD_EFFECT_HEAT_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_HAIL:
			if he == HOLD_EFFECT_ICY_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_SANDSTORM:
			if he == HOLD_EFFECT_SMOOTH_ROCK:
				return WEATHER_DURATION_ROCK
	return WEATHER_DURATION_DEFAULT


# ── Utility Umbrella ──────────────────────────────────────────────────────────
#
# Source: GetWeatherDamageModifier (battle_util.c L7258): if defender holds Umbrella,
#   return UQ_4_12(1.0) immediately (no weather boost/reduction).
#   GetAttackerWeather (L9281–9290): if attacker holds Umbrella, strip rain/sun from
#   the effective weather, returning WEATHER_NONE for modifier purposes.
# Both cases collapse to the same behaviour in our engine: if either battler holds
# Utility Umbrella, weather has no effect on this hit.

static func blocks_weather_modifier(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_UTILITY_UMBRELLA


# ── Choice item detection ─────────────────────────────────────────────────────
#
# Source: IsHoldEffectChoice (item.c L970–974): BAND || SCARF || SPECS.
# M17n-7: Klutz-gated via effective_held_item — source's own choice-lock gate
# (`CheckMoveLimitations`, `IsHoldEffectChoice(holdEffect)`) reads
# `GetBattlerHoldEffect` too, so a Klutz holder wielding a Choice item is NOT
# choice-locked either, matching the item's stat boost also being suppressed.

static func is_choice_item(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return false
	return item.hold_effect in [
		HOLD_EFFECT_CHOICE_BAND,
		HOLD_EFFECT_CHOICE_SCARF,
		HOLD_EFFECT_CHOICE_SPECS,
	]


# ── Heavy Duty Boots — entry hazard immunity ───────────────────────────────────
#
# Source: IsBattlerAffectedByHazards (battle_util.c L9209-9228): returns FALSE (blocked)
#   whenever `holdEffect == HOLD_EFFECT_HEAVY_DUTY_BOOTS`, for ALL of Spikes, Toxic Spikes,
#   and Stealth Rock (checked at every TryHazardsOnSwitchIn call site — battle_switch_in.c
#   L306-378) — full immunity, not a damage reduction. Follow-up fixes session, 2026-07-02
#   (flagged as a known gap in M16d's decisions.md Stealth Rock section).
# Caller (BattleManager._apply_switch_in_hazards) applies this as one uniform gate across
#   all three hazard branches rather than three separate checks, matching how source's
#   IsBattlerAffectedByHazards is the single shared choke point for all of them.
# Note: for Toxic Spikes specifically, a grounded Poison-type ABSORBS/clears the hazard
#   regardless of Heavy Duty Boots (source checks IS_BATTLER_OF_TYPE(POISON) in an earlier
#   else-if branch than the Heavy-Duty-Boots gate — battle_switch_in.c L338-344) — this
#   helper only decides whether the "would be poisoned" branch is blocked, not the absorb
#   branch; the caller must NOT gate the Poison-type-absorb check behind this helper.

static func is_hazard_immune(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_HEAVY_DUTY_BOOTS


# ── M18a: Type-boost held items (base-power modifier) ─────────────────────────
#
# Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6659–6661) — both
#   HOLD_EFFECT_TYPE_POWER (Charcoal family / Incenses / Silk Scarf / Fairy Feather)
#   and HOLD_EFFECT_PLATE share ONE case branch:
#     `if (moveType == GetItemSecondaryId(item)) modifier = uq4_12_multiply(modifier, holdEffectModifier)`
#   where `holdEffectModifier = 1.0 + holdEffectParamAtk/100` and
#   `holdEffectParamAtk = GetBattlerHoldEffectParam(...)`, clamped ≤100.
# Every one of this project's 40 M18a items resolves that param to 20 — confirmed by
#   reading all 40 struct entries in src/data/items.h directly: the Charcoal family/
#   Silk Scarf/Fairy Feather use `.holdEffectParam = TYPE_BOOST_PARAM` and Sea/Wave
#   Incense use an explicit `I_TYPE_BOOST_POWER >= GEN_4 ? 20 : 5` ternary, both of
#   which resolve to 20 under this reference clone's `I_TYPE_BOOST_POWER = GEN_LATEST`
#   config (include/config/item.h:15); every Plate and the remaining 3 Incenses use a
#   literal `.holdEffectParam = 20`. No item in this family varies — the boost is a
#   flat ×1.2 (`UQ412_TYPE_BOOST` = `UQ_4_12(1.2)` = 4915), not itemized per-item.
# This is a BASE-POWER modifier (`CalcMoveBasePowerAfterModifiers`), architecturally
#   the item-side sibling of `AbilityManager.move_power_modifier_uq412` (M17a's
#   Technician/Iron Fist/etc. live in this exact same source function) — NOT of this
#   file's `attack_modifier_uq412` above, which is `GetAttackStatModifier` (Choice
#   Band/Specs, a different function entirely, applied to the attack STAT before the
#   base formula rather than to the move's power). Caller wires this into
#   `DamageCalculator.calculate` alongside `ability_power_mod`, not `atk_item_mod`.
# The real struct field carrying the type is source's `.secondaryId`, which this
#   project's `ItemData` schema has no equivalent for. Reuses `hold_effect_param` to
#   store the type instead — the SAME pragmatic deviation `[M17n-4]` already
#   established for `HOLD_EFFECT_PLATE`'s Multitype read below, now extended
#   uniformly to `HOLD_EFFECT_TYPE_POWER` too, since both share this one case branch
#   in source and neither uses `hold_effect_param` for its literal source purpose
#   here (the 20% is a fixed constant, never itemized per-item in this project).
# Returns 4096 (neutral) if not holding a matching-type item — including when the
#   held item's type doesn't match the move being used, or Klutz suppresses it.
static func move_power_modifier_uq412(mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	# M18g: Soul Dew — Latios/Latias, Psychic/Dragon-type moves only, same
	# UQ412_TYPE_BOOST magnitude (holdEffectParam=20 for BOTH under this project's
	# B_SOUL_DEW_BOOST=GEN_LATEST/>=GEN_7 config — confirmed via src/data/items.h's
	# own `B_SOUL_DEW_BOOST >= GEN_7 ? 20 : 50` ternary). A SEPARATE hold_effect
	# case from HOLD_EFFECT_TYPE_POWER/PLATE (source: battle_util.c L6653-6658,
	# same switch, same CalcMoveBasePowerAfterModifiers function) rather than a
	# type-match against hold_effect_param, since Soul Dew's type pair (Psychic
	# AND Dragon) doesn't fit the one-type-per-item shape every Plate/Charcoal-
	# family item uses.
	if item.hold_effect == HOLD_EFFECT_SOUL_DEW:
		if _species_matches(mon, item) \
				and (move.type == TypeChart.TYPE_PSYCHIC or move.type == TypeChart.TYPE_DRAGON):
			return UQ412_TYPE_BOOST
		return 4096
	# M18j: Muscle Band (physical-only) / Wise Glasses (special-only) — x1.1,
	# read dynamically from hold_effect_param (=10), using the FLOORED formula
	# source uses for these two specifically: 4096 + (param*4096)/100, NOT the
	# rounded PercentToUQ4_12 formula UQ412_TYPE_BOOST above uses. A real,
	# confirmed 1-unit difference at 10% (4505 floored vs. 4506 rounded) —
	# verified by reading both source functions directly, not assumed to share
	# the type-boost family's rounding.
	if item.hold_effect == HOLD_EFFECT_MUSCLE_BAND and move.category == 0:
		return 4096 + (item.hold_effect_param * 4096) / 100
	if item.hold_effect == HOLD_EFFECT_WISE_GLASSES and move.category == 1:
		return 4096 + (item.hold_effect_param * 4096) / 100
	# M18p: Punching Glove — x1.1 on the HOLDER's own punching moves. Source:
	# GetAttackerItemsModifier's HOLD_EFFECT_PUNCHING_GLOVE case (battle_util.c
	# L6664-6666), same switch EXPERT_BELT/PLATE occupy, same pipeline stage as
	# the type-boost family — a plain data check here, reusing the already-wired
	# `punching_move` MoveData flag (Iron Fist's own field).
	if item.hold_effect == HOLD_EFFECT_PUNCHING_GLOVE and move.punching_move:
		return UQ412_PUNCHING_GLOVE
	if item.hold_effect != HOLD_EFFECT_TYPE_POWER and item.hold_effect != HOLD_EFFECT_PLATE:
		return 4096
	if move.type != item.hold_effect_param:
		return 4096
	return UQ412_TYPE_BOOST


# M17n-4: Multitype's held Plate item → type. Source: src/data/items.h's Plate entries
# store the associated type in `.secondaryId` (e.g. Flame Plate: `.secondaryId =
# TYPE_FIRE`), with `.holdEffectParam = 20` reserved for Judgment/Natural Gift's power
# boost — a DIFFERENT field from the type. This project's `ItemData` schema has no
# `secondary_id` field, and has neither Judgment nor Natural Gift implemented (confirmed
# via grep — neither move exists here), so `holdEffectParam`'s source purpose is moot in
# this codebase; reusing `hold_effect_param` for the type value instead is the same
# pragmatic deviation this project's existing Resist Berry modifier already established
# (see `defender_item_modifier_uq412` above, which reads `hold_effect_param` as a type
# id for Occa/Chilan-style berries) rather than adding an unused field to match source's
# literal layout.
# Returns TypeChart.TYPE_NONE if not holding a Plate.
# M17n-7: Klutz-gated via effective_held_item for source-fidelity/uniformity, though
# structurally unreachable in practice (Multitype and Klutz can never coexist on the
# same holder — a Pokémon has exactly one ability) — same "recorded, not reachable"
# precedent as Sticky Hold ([M17j]) and Mind's Eye's breakable flag ([M17n-6]).
static func multitype_plate_type(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_PLATE:
		return TypeChart.TYPE_NONE
	return item.hold_effect_param


# M18e: Scope Lens / Razor Claw — +1 crit stage, summed into the same total
# DamageCalculator._roll_crit already combines Focus Energy's +2 and Super Luck's
# ability_bonus into (source: GetHoldEffectCritChanceIncrease, battle_util.c
# L7795-7810 — HOLD_EFFECT_SCOPE_LENS case, unconditional, no move-category check).
# Returns 0 if not holding a crit-boosting item, matching ability_bonus's own
# zero-default shape.
static func crit_stage_bonus(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 0
	if item.hold_effect == HOLD_EFFECT_SCOPE_LENS:
		return 1
	# M18g: Lucky Punch (Chansey ONLY, not Blissey) / Leek (Farfetch'd [+
	# Sirfetch'd, absent from this roster]) — +2, NOT +1 like Scope Lens/Razor
	# Claw, despite living in the exact same source function
	# (GetHoldEffectCritChanceIncrease, battle_util.c L7804-7810) — a real,
	# confirmed asymmetry, not assumed to match M18e's magnitude.
	if item.hold_effect == HOLD_EFFECT_LUCKY_PUNCH and _species_matches(mon, item):
		return 2
	if item.hold_effect == HOLD_EFFECT_LEEK and _species_matches(mon, item):
		return 2
	return 0


# M18l: Quick Claw — probabilistic act-first within a tied priority bracket, item
# equivalent of AbilityManager.quick_draw_activates. Source: battle_main.c L4987
# (`quickClawRandom[battler] = RandomPercentage(RNG_QUICK_CLAW,
# GetBattlerHoldEffectParam(battler))`) and L5191 (`holdEffectBattler1 ==
# HOLD_EFFECT_QUICK_CLAW && quickClawRandom[battler1]`). Deliberately NOT gated on
# move category — unlike Quick Draw's ability equivalent, source has no
# IsBattleMoveStatus check on this branch, confirmed by direct comparison. The 20%
# chance is read from item.hold_effect_param (not hardcoded), matching source's own
# `GetBattlerHoldEffectParam` read and this project's existing Oran-Berry-style
# param convention. Must be evaluated EXACTLY ONCE per battler per turn, same
# per-turn-precompute requirement as quick_draw_activates ([M17n-3]) — the caller is
# responsible for precomputing this into a per-mon Dictionary before the sort, not
# re-rolling per pairwise comparison.
static func quick_claw_activates(
		mon: BattlePokemon, ng_active: bool = false, forced_roll: Variant = null) -> bool:
	if mon == null:
		return false
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_QUICK_CLAW:
		return false
	if forced_roll != null:
		return bool(forced_roll)
	return randi() % 100 < item.hold_effect_param


# M18l: Full Incense / Lagging Tail — always act LAST within a tied priority
# bracket, item equivalent of AbilityManager.has_slow_turn_order_effect. Source:
# battle_main.c L4409-4410 (`if (GetBattlerHoldEffect(battler) ==
# HOLD_EFFECT_LAGGING_TAIL) gProtectStructs[battler].laggingTail = TRUE`) — set
# UNCONDITIONALLY whenever the holder's hold effect matches, with no move-category
# gate at all (confirmed by direct source read: no IsBattleMoveStatus check anywhere
# near this line), matching Stall's unconditional shape exactly rather than Mycelium
# Might's narrower per-move-category one. Same per-turn-precompute requirement as
# has_slow_turn_order_effect.
static func has_slow_turn_order_item(mon: BattlePokemon, ng_active: bool = false) -> bool:
	if mon == null:
		return false
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_LAGGING_TAIL


# ── M18c: berry HP-threshold effects (10 items) ────────────────────────────────
#
# Source: src/battle_hold_effects.c :: ItemBattleEffects's switch (L1201-1224) for
# the 8 general-dispatch cases (5 stat berries, Lansat, Starf, Micle); Custap is
# handled entirely separately in battle_main.c's turn-order code (see
# custap_berry_activates below). Every general-dispatch case shares
# HasEnoughHpToEatBerry(battler, ability, GetItemHoldEffectParam(item), item) — all
# 8 confirmed holdEffectParam=4 (25%) individually via src/data/items.h, not assumed
# uniform. Each function below inlines that same gate (Klutz via effective_held_item,
# Unnerve, Gluttony-adjusted fraction) rather than sharing a private helper, matching
# hp_threshold_berry_heal/status_cure_berry_cures's own established precedent of
# inlining their gate rather than factoring one out.

# M18c: Liechi(Atk)/Ganlon(Def)/Salac(Speed)/Petaya(SpAtk)/Apicot(SpDef) — each
# raises its OWN stat by +1 (Ripen: +2) at the 25% HP threshold. Source:
# StatRaiseBerry (battle_hold_effects.c L943-964): `CompareStat(...,
# MAX_STAT_STAGE, CMP_LESS_THAN, ability)` is checked BEFORE
# HasEnoughHpToEatBerry — an already-maxed stat means the berry never triggers or
# consumes at all, reproduced below via the same ordering (stat-maxed check first).
# Returns {} if not triggered, else {"item": ItemData, "stat": STAGE_*, "amount": 1|2}.
static func stat_raise_berry_trigger(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> Dictionary:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null:
		return {}
	var stat_idx: int = -1
	match item.hold_effect:
		HOLD_EFFECT_ATTACK_UP: stat_idx = BattlePokemon.STAGE_ATK
		HOLD_EFFECT_DEFENSE_UP: stat_idx = BattlePokemon.STAGE_DEF
		HOLD_EFFECT_SPEED_UP: stat_idx = BattlePokemon.STAGE_SPEED
		HOLD_EFFECT_SP_ATTACK_UP: stat_idx = BattlePokemon.STAGE_SPATK
		HOLD_EFFECT_SP_DEFENSE_UP: stat_idx = BattlePokemon.STAGE_SPDEF
		_: return {}
	if mon.stat_stages[stat_idx] >= 6:
		return {}
	if override_item == null:
		if unnerve_active:
			return {}
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, item.hold_effect_param, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return {}
	var amount: int = 2 if (mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN) else 1
	return {"item": item, "stat": stat_idx, "amount": amount}


# M18c: Starf Berry — raises ONE random non-maxed stat from {Atk, Def, SpAtk,
# SpDef, Speed} by +2 (Ripen: +4) at the 25% HP threshold. Source:
# RandomStatRaiseBerry (battle_hold_effects.c L984-1021): the eligible-stat
# check (any of STAT_ATK..NUM_STATS-1 not maxed) runs BEFORE
# HasEnoughHpToEatBerry, same ordering as stat_raise_berry_trigger above.
# STAT_ATK..NUM_STATS-1 EXCLUDES Accuracy/Evasion — a narrower pool than Moody's
# own (which includes them per B_MOODY_ACC_EVASION>=GEN_8, ability_manager.gd's
# `_apply_moody`) — confirmed via direct enum read, not assumed identical.
# forced_stat: STAGE_* index to pin instead of rolling — null = real RNG, same
# force_moody_raise/force_moody_lower convention `_apply_moody` already established.
# Returns {} if not triggered, else {"item": ItemData, "stat": STAGE_*, "amount": 2|4}.
static func random_stat_raise_berry_trigger(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null,
		forced_stat: Variant = null) -> Dictionary:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_RANDOM_STAT_UP:
		return {}
	var valid: Array = []
	for i in range(5):  # STAGE_ATK(0)..STAGE_SPEED(4)
		if mon.stat_stages[i] < 6:
			valid.append(i)
	if valid.is_empty():
		return {}
	if override_item == null:
		if unnerve_active:
			return {}
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, item.hold_effect_param, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return {}
	var stat_idx: int = int(forced_stat) if (forced_stat != null and int(forced_stat) in valid) \
			else valid[randi() % valid.size()]
	var amount: int = 4 if (mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN) else 2
	return {"item": item, "stat": stat_idx, "amount": amount}


# M18c: Lansat Berry — sets the SAME focus_energy volatile the Focus Energy MOVE
# sets (+2 crit stage via DamageCalculator._roll_crit's existing focus_energy
# param), NOT M18e's crit_stage_bonus()/+1 item mechanism. A real correction found
# at Step 0: source's CriticalHitRatioUp (battle_hold_effects.c L968-981) sets
# `volatiles.focusEnergy = TRUE` directly — the exact same flag, not a parallel
# +1 that sums with it. Also gated on focus_energy not already being active (no
# double-application; source also checks dragonCheer, not implemented here, moot).
# Ripen does NOT affect this one — confirmed absent from source, unlike the 6
# stat-raising berries above. Returns the ItemData to consume, or null.
static func lansat_berry_trigger(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> ItemData:
	if mon == null or mon.focus_energy:
		return null
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_CRITICAL_UP:
		return null
	if override_item == null:
		if unnerve_active:
			return null
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, item.hold_effect_param, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return null
	return item


# M18c: Custap Berry — deterministic (no roll) act-first within a tied priority
# bracket at the 25% HP threshold, item equivalent shape of quick_claw_activates
# but HP-gated instead of probabilistic. OR'd into the SAME quick_effect dict
# M18l built ([M17n-3]'s original chokepoint), reproducing source's own
# battler1HasQuickEffect = quickDraw || usedCustapBerry structure exactly.
# CORRECTION found at Step 0: source's turn-order check (TryChangingTurnOrderEffects,
# battle_main.c L5191) has NO IsUnnerveBlocked call anywhere near it — a completely
# separate code path from ItemBattleEffects (the general berry dispatcher every
# OTHER function in this file's M18c section routes through, and where Unnerve's
# gate actually lives in source). Custap therefore bypasses Unnerve entirely, while
# Klutz (via effective_held_item below) and Gluttony (via the fraction check) still
# apply normally. Returns the ItemData to consume, or null.
static func custap_berry_activates(mon: BattlePokemon, ng_active: bool = false) -> ItemData:
	if mon == null:
		return null
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_CUSTAP_BERRY:
		return null
	var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, item.hold_effect_param, ng_active)
	if mon.current_hp > mon.max_hp / fraction:
		return null
	return item


# M18c: Micle Berry — one-shot ×1.2 accuracy (Ripen: ×1.4) for exactly the
# holder's NEXT accuracy check, at the 25% HP threshold. Sets
# BattlePokemon.micle_boost_active; the caller consumes the item AND sets the flag.
# Returns the ItemData to consume, or null.
static func micle_berry_trigger(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> ItemData:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_MICLE_BERRY:
		return null
	if override_item == null:
		if unnerve_active:
			return null
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, item.hold_effect_param, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return null
	return item


# M18c: Micle Berry's accuracy read — a flag check, not a held-item check (the
# berry is already consumed and gone by the time a move's accuracy is rolled), so
# no Klutz gate applies here — matches source reading
# `gBattleStruct->battlerState[battlerAtk].usedMicleBerry` directly with no
# re-gating (battle_util.c L10357-10362). Ripen checked at USE time (the mon's
# CURRENT ability), matching source's fresh `atkAbility` read in GetTotalAccuracy,
# not the ability at the moment the berry was originally consumed.
static func micle_accuracy_modifier_percent(mon: BattlePokemon) -> int:
	if mon == null or not mon.micle_boost_active:
		return 100
	if mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		return 140
	return 120


# M18c: Enigma Berry — heals 25% max HP (Ripen: 50%) when the holder is hit
# DIRECTLY (not absorbed by Substitute) by a move that resolves super-effective.
# Architecturally separate from every other item in this file, confirmed at Step
# 0: NOT an HP threshold (heals regardless of current HP level) and NOT the
# resist-berry TYPE-match check (defender_item_modifier_uq412 compares
# hold_effect_param to move.type BEFORE damage; this reads the ACTUAL COMPUTED
# effectiveness AFTER damage, via the caller's own DamageCalculator.calculate
# result). Source: TrySetEnigmaBerry (battle_hold_effects.c L378-396) —
# `IsBattlerTurnDamaged(EXCLUDING_SUBSTITUTES) && MOVE_RESULT_SUPER_EFFECTIVE`;
# this project's substitute-absorption branch already returns before reaching the
# caller's insertion point, so EXCLUDING_SUBSTITUTES is satisfied automatically.
# was_super_effective: the caller's own DamageCalculator.calculate result's
# "effectiveness" > 1.0 — this function cannot derive it independently, unlike
# every HP-fraction check above.
static func enigma_berry_heal(mon: BattlePokemon, was_super_effective: bool,
		ng_active: bool = false, unnerve_active: bool = false,
		override_item: ItemData = null) -> int:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_ENIGMA_BERRY:
		return 0
	if override_item != null:
		if mon.current_hp >= mon.max_hp:
			return 0
	else:
		if unnerve_active:
			return 0
		if not was_super_effective:
			return 0
	var heal_amount: int = mon.max_hp * 25 / 100
	if mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		heal_amount *= 2
	return max(1, heal_amount)


# ── M18d: Leppa Berry / Jaboca / Rowap (3 items) ────────────────────────────────

# M18d: Leppa Berry — checked once per own move use, same MoveEnd cadence as
# source's MoveEndSprayLeppaBlunder step (battle_move_resolution.c L4204-4211).
# Source: ItemRestorePp (battle_hold_effects.c L855-916) scans ALL of the mon's
# moves in slot order and restores to the FIRST one at exactly 0 PP (`break`s on
# first match) — NOT necessarily the move just used, NOT random, NOT "restore
# every depleted move." This project's PP model has no PP-bonus field
# (CalculatePPWithBonus is moot — confirmed no such field exists on MoveData/
# BattlePokemon), so the cap is simply the move's own base `pp`.
# Returns {} if not triggered, else {"item": ItemData, "move_index": int, "amount": int}
# ("amount" is the RAW restore amount before capping — the caller clamps against
# the move's own max PP, matching every other heal-amount function in this file's
# established division of responsibility).
static func leppa_berry_restore(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false) -> Dictionary:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_RESTORE_PP or unnerve_active:
		return {}
	var move_idx: int = -1
	for i in range(mon.current_pp.size()):
		if mon.current_pp[i] == 0:
			move_idx = i
			break
	if move_idx == -1:
		return {}
	var amount: int = item.hold_effect_param
	if mon.ability != null and mon.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		amount *= 2
	return {"item": item, "move_index": move_idx, "amount": amount}


# M18d: Jaboca Berry (physical) / Rowap Berry (special) — retaliation damage to
# the ATTACKER equal to 1/8 of the ATTACKER's OWN max HP (Ripen, on the HOLDER's
# side: 1/4), on ANY hit of the matching move category. CORRECTION found at Step
# 0: source (TryJabocaBerry/TryRowapBerry, battle_hold_effects.c L332-376) checks
# ONLY IsBattleMovePhysical/IsBattleMoveSpecial — there is NO IsMoveMakingContact
# call in either function. This is NOT a contact-gated mechanism despite the
# superficial family resemblance to Rough Skin/Iron Barbs (which genuinely ARE
# contact-gated, via AbilityManager.move_makes_contact) — a non-contact physical
# move (e.g. a ranged Rock-type move) still triggers Jaboca.
# `holder` = the berry holder (the one who was hit); `attacker` = the one dealing
# the hit (who takes the retaliation damage and whose max_hp the fraction is based
# on — confirmed from source's own GetNonDynamaxMaxHP(battlerAtk), the ATTACKER's
# max HP, not the holder's).
# Gating deliberately split between this function and the caller, matching
# [M17n-9]'s own established division: this function returns the raw damage
# amount (item + category + Ripen only); the caller applies the attacker-alive
# check and AbilityManager.blocks_indirect_damage (Magic Guard) — the same
# call-site-consulted pattern blocks_indirect_damage already uses at its other
# five sites, rather than importing an ability check into this file.
# unnerve_active gates this the same as every other general-dispatch berry in
# this tier (both route through ItemBattleEffects's shared top-level gate).
static func jaboca_rowap_retaliation_damage(holder: BattlePokemon, attacker: BattlePokemon,
		move: MoveData, ng_active: bool = false, unnerve_active: bool = false) -> int:
	var item: ItemData = effective_held_item(holder, ng_active)
	if item == null or unnerve_active:
		return 0
	if item.hold_effect == HOLD_EFFECT_JABOCA_BERRY and move.category != 0:
		return 0
	if item.hold_effect == HOLD_EFFECT_ROWAP_BERRY and move.category != 1:
		return 0
	if item.hold_effect != HOLD_EFFECT_JABOCA_BERRY and item.hold_effect != HOLD_EFFECT_ROWAP_BERRY:
		return 0
	var dmg: int = attacker.max_hp / 8
	if holder.ability != null and holder.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		dmg *= 2
	return max(1, dmg)


# M18i: Status Orbs — Flame Orb (self-inflicts burn), Toxic Orb (self-inflicts
# badly-poisoned/STATUS_TOXIC, not regular poison). Returns the STATUS_* the
# holder should attempt to self-inflict this end of turn, or STATUS_NONE. The
# caller applies it via StatusManager.try_apply_status (the SAME function moves
# use), passing the holder as its own `attacker` — mirrors source's
# self-referential CanBeBurned(battler, battler, ability)/CanBePoisoned(battler,
# battler, ability, ability) call shape exactly, so existing type immunities
# (Fire-type/burn, Poison-or-Steel-type/toxic) and the Corrosion bypass compose
# for free with zero new immunity logic in this function. NOT Unnerve-gated —
# confirmed via source (IsUnnerveBlocked returns FALSE immediately for any
# non-berry item; Flame Orb/Toxic Orb are POCKET_ITEMS, not POCKET_BERRIES).
static func status_orb_status(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return BattlePokemon.STATUS_NONE
	if item.hold_effect == HOLD_EFFECT_FLAME_ORB:
		return BattlePokemon.STATUS_BURN
	if item.hold_effect == HOLD_EFFECT_TOXIC_ORB:
		return BattlePokemon.STATUS_TOXIC
	return BattlePokemon.STATUS_NONE


# M18j: item-side accuracy modifier — Wide Lens/Zoom Lens (attacker-side) and
# Bright Powder/Lax Incense (defender-side), mirroring
# AbilityManager.accuracy_modifier_percent's own combined attacker+defender
# shape and multiplied into the same `calc` percentage in
# StatusManager.check_accuracy.
# Source: GetTotalAccuracy's item switches (battle_util.c L10334-10354):
#   attacker's hold effect — Wide Lens: `calc = (calc*(100+atkParam))/100`
#     unconditional; Zoom Lens: same formula, gated on
#     `HasBattlerActedThisTurn(battlerDef)` (has the TARGET already acted this
#     turn — checked via this project's existing _turn_order/_current_actor_index
#     position tracking, the same infrastructure `_is_last_to_move` already
#     established for Analytic, [M17n-5]; source's secondary
#     `isFirstTurn != 2` edge-case flag is NOT modeled here — a documented,
#     acknowledged simplification, not a silent omission).
#   target's hold effect — HOLD_EFFECT_EVASION_UP (Bright Powder AND Lax
#     Incense, literal same constant, both holdEffectParam=10 under this
#     reference clone's config, confirmed genuinely identical not assumed):
#     `calc = (calc*(100-defParam))/100`.
# target_already_acted: computed by the caller (BattleManager), null-unsafe
#   default false — matches this project's existing convention of the caller
#   resolving turn-order-position questions and passing the result in (see
#   `is_last_to_move` threaded into DamageCalculator.calculate the same way).
static func accuracy_modifier_percent(attacker: BattlePokemon, defender: BattlePokemon = null,
		ng_active: bool = false, target_already_acted: bool = false) -> int:
	var pct: int = 100
	var atk_item: ItemData = effective_held_item(attacker, ng_active)
	if atk_item != null:
		if atk_item.hold_effect == HOLD_EFFECT_WIDE_LENS:
			pct = (pct * (100 + atk_item.hold_effect_param)) / 100
		elif atk_item.hold_effect == HOLD_EFFECT_ZOOM_LENS and target_already_acted:
			pct = (pct * (100 + atk_item.hold_effect_param)) / 100

	if defender != null:
		var def_item: ItemData = effective_held_item(defender, ng_active)
		if def_item != null and def_item.hold_effect == HOLD_EFFECT_EVASION_UP:
			pct = (pct * (100 - def_item.hold_effect_param)) / 100

	return pct


# M18k: King's Rock / Razor Fang — probabilistic flinch roll added to an
# attacking move that has NO native flinch effect of its own. Source:
# TryKingsRock (battle_hold_effects.c L188-210):
#   !IsBattlerTurnDamaged(battlerDef) → no roll (caller already gates on
#     damage > 0, matching every other on-hit item in this file).
#   MoveIgnoresKingsRock(gCurrentMove) → not modeled: every one of source's
#     own conditions for this flag is gated behind pre-Gen-5
#     B_UPDATED_MOVE_FLAGS comparisons, none of which are unconditional, and
#     this reference clone's B_UPDATED_MOVE_FLAGS=GEN_LATEST makes all of them
#     evaluate false — confirmed via direct grep of moves_info.h, not assumed.
#   MoveHasAdditionalEffect(gCurrentMove, MOVE_EFFECT_FLINCH) → mutually
#     exclusive with a move that already carries its own flinch effect
#     (Air Slash, Rock Slide) — this is NOT an independent second roll
#     stacked on top of an existing flinch chance; it is gated on the MOVE'S
#     DEFINITION having no flinch effect at all, matching this project's
#     `move.secondary_effect != MoveData.SE_FLINCH` check at the caller.
#   ability == ABILITY_STENCH excludes the roll — Stench is not implemented
#     anywhere in this project (confirmed via grep), a standing absence, not
#     a new gap opened by this tier.
#   Serene Grace DOUBLES holdEffectParam here — a SEPARATE application of the
#     same ability check try_secondary_effect already makes for a move's own
#     secondary chance, confirmed explicitly by source's own config comment:
#     "In Gen5+, Serene Grace boosts the added flinch chance of King's Rock
#     and Razor Fang." (B_SERENE_GRACE_BOOST, include/config/battle.h).
#     Rainbow's further doubling is not modeled — no Rainbow side status
#     exists anywhere in this project (matches status_manager.gd's own
#     existing note on this same absence for the move-native case).
# forced_roll: same seam convention as quick_claw_activates — null = RNG,
#   true/false = forced outcome. Caller is responsible for the
#   move.secondary_effect != MoveData.SE_FLINCH gate and for damage > 0.
static func kings_rock_flinch_activates(mon: BattlePokemon, ng_active: bool = false,
		forced_roll: Variant = null) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_FLINCH:
		return false
	var chance: int = item.hold_effect_param
	if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_SERENE_GRACE:
		chance *= 2
	if forced_roll != null:
		return bool(forced_roll)
	return randi() % 100 < chance


# ── M18n: Forced-switch items (Red Card, Eject Button) ─────────────────────────
#
# Source: src/battle_move_resolution.c :: TryRedCard (L3730-3752) / TryEjectButton
# (L3757-3773), both dispatched from MoveEndCardButton — an item-reactive check
# entirely separate from the general ItemBattleEffects switch (both hold effects'
# entries in data/hold_effects.h are EMPTY — no onTargetAfterHit/onAttackerAfterHit
# flag at all, confirmed by direct inspection).
#
# Both items are pure data checks here — "is this the holder's held effect,"
# nothing more. The forced-switch orchestration (valid-target lookup, Guard Dog's
# switch-vs-no-switch branch for Red Card specifically, consumption timing, and
# calling BattleManager._do_forced_switch_in) lives entirely in BattleManager,
# matching this project's established division of labor for every other reactive
# item (Jaboca/Rowap, Quick Claw, King's Rock/Razor Fang above).
#
# Trigger condition (both items, confirmed identical): the holder takes DIRECT
# damage this hit (source's IsBattlerTurnDamaged(..., EXCLUDING_SUBSTITUTES) — a
# Substitute-absorbed hit never reaches either check, and never a status move,
# since IsBattlerTurnDamaged is damage-gated). NEITHER is contact-gated or
# category-gated — confirmed absent from both TryRedCard and TryEjectButton, an
# "any damaging hit" shape matching Enigma Berry ([M18c]), not Jaboca/Rowap's
# category-gated shape ([M18d]).
#
# Magic Guard: confirmed NO interaction with either item — neither function
# references ABILITY_MAGIC_GUARD at all, consistent with forced switching dealing
# no damage for Magic Guard to have anything to block.
static func holds_red_card(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_RED_CARD


static func holds_eject_button(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_EJECT_BUTTON


# ── M18o: Survive-lethal-hit items (Focus Sash, Focus Band) ────────────────────
#
# Source: src/battle_util.c :: GetAdjustedDamage (L7954-8003) — the SAME shared
# endure-check function this project's existing Sturdy already lives in
# (battle_manager.gd's Sturdy block, [M17n-5]). Confirmed a strict `else if`
# CHAIN, first match wins: Endure -> False Swipe -> Sturdy -> Focus Band ->
# Focus Sash -> affection (only Sturdy/Focus Band/Focus Sash reachable here; the
# other three aren't implemented in this project). This means a Pokemon with
# BOTH Sturdy and a held Focus Sash never even reaches the Focus Sash branch —
# it is not consumed, not "wasted," simply untouched by that hit. The caller
# (BattleManager) is responsible for implementing this as an actual elif chain,
# not three independent checks, to preserve this precedence exactly.
#
# Focus Band: holdEffectParam=10 (10%), PROBABILISTIC, NO HP gate at all — can
# trigger from any starting HP. NOT consumed — repeatable every hit for the
# rest of the battle (no differentiating consumption call exists for either
# item in GetAdjustedDamage itself; corroborated by
# docs/changelogs/1.8.x/1.8.4.md's own "Focus Sash but not consuming the item"
# bugfix entry, which has no Focus Band equivalent since it's simply never
# consumed).
static func focus_band_activates(mon: BattlePokemon, ng_active: bool = false,
		forced_roll: Variant = null) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_FOCUS_BAND:
		return false
	if forced_roll != null:
		return bool(forced_roll)
	return randi() % 100 < item.hold_effect_param


# Focus Sash: NO holdEffectParam/roll at all in source — purely full-HP-gated
# (IsBattlerAtMaxHp, the SAME gate Sturdy uses), unconditional given full HP.
# SINGLE-USE — the caller consumes it via _consume_item on trigger.
static func holds_focus_sash(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_FOCUS_SASH


# ── M18q: Big Root / Shell Bell ─────────────────────────────────────────────────
#
# Source: src/battle_util.c :: GetDrainedBigRootHp (L1735-1743) — shared by TWO
# source families: move-based drain (SetHealScript, the SAME chokepoint this
# project's move.drain_percent/Liquid-Ooze mechanism already occupies) AND
# Ingrain/Leech Seed/Strength Sap/Aqua Ring (a separate volatile-status family,
# confirmed absent from this project entirely via grep). Big Root's real scope
# here is move-drain only — not a deliberate scope reduction, just the only
# reachable half of source's own two.
#
# Source's own formula is DELIBERATELY NOT UQ4.12, unlike nearly every other
# item modifier in this file: `hp = (hp * 1300) / 1000` — plain integer math at
# a base-1000 scale. Replicated exactly rather than assumed to generalize from
# this project's own UQ4.12 convention. Held by the ATTACKER (the one draining),
# not the target being drained — confirmed via GetDrainedBigRootHp(battlerAtk,
# ...)'s own parameter.
#
# Applied BEFORE the caller's Liquid Ooze branch in source (GetDrainedBigRootHp
# is called unconditionally, first, inside SetHealScript) — meaning if the
# drained target has Liquid Ooze, the damage reflected back at the attacker is
# ALSO boosted by Big Root, since the multiply happens before the invert/heal
# split. The caller preserves this by applying this function's result to `heal`
# before checking AbilityManager.inverts_drain, the exact ordering already in
# place at that call site.
static func big_root_drain_heal(mon: BattlePokemon, heal: int, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_BIG_ROOT:
		return heal
	return heal * 1300 / 1000


# Source: src/battle_hold_effects.c :: TryShellBell (L524-541) — reads
# gBattleScripting.savedDmg, set in MoveEndSetValues (battle_move_resolution.c
# L2486), the VERY FIRST moveend state, running immediately after damage is
# applied — confirming this is unambiguously the FINAL damage (post-crit,
# post-type-effectiveness, post-item/ability boosts). In this project, that's
# simply the caller's own `damage` local in _do_damaging_hit, already final by
# construction — no new plumbing needed, no separate "saved" tracking variable.
# Gated on NOT already at max HP (no waste-heal — genuinely new for this
# project, no existing precedent checks this before healing). Fires on ANY
# nonzero damage regardless of mechanism (fixed/level damage included — no
# move-category gate in source). Future Sight and Heal Block exclusions are
# both non-applicable here (neither exists in this project).
#
# NOT modeled, flagged not built (both genuine doubles-only edge cases, out of
# this tier's singles-focused test scope, matching M18n's own flagged Red Card
# doubles gap):
#   1. Source excludes healing if the attacker was JUST forced to switch out by
#      Red Card earlier in this same hit resolution (`redCardSwitched`) — this
#      project's `attacker` reference stays valid post-switch, so without an
#      explicit guard this WOULD still heal in that case, a real discrepancy.
#   2. Source's savedDmg accumulates across ALL targets of a spread move before
#      healing once; this project's per-target dispatch would heal once per
#      target hit in a hypothetical doubles spread-move scenario.
static func shell_bell_heal(mon: BattlePokemon, final_damage: int, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_SHELL_BELL:
		return 0
	if final_damage <= 0 or mon.current_hp >= mon.max_hp:
		return 0
	return final_damage / item.hold_effect_param


# ── M18r: Standalone reuses (7 items) ───────────────────────────────────────────
#
# Pure data checks, matching the established holds_red_card/holds_eject_button/
# holds_focus_sash shape — all orchestration (the actual mechanic each item
# modifies) lives in BattleManager, at the existing chokepoint each one reuses.

static func holds_power_herb(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_POWER_HERB


# Returns the screen-set duration (8 if Light Clay held, else the source-passed
# default) — a direct modifier on the caller's own turn-count assignment, same
# shape as WEATHER_DURATION_ROCK/WEATHER_DURATION_DEFAULT above.
static func screen_turns(mon: BattlePokemon, default_turns: int, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item != null and item.hold_effect == HOLD_EFFECT_LIGHT_CLAY:
		return 8
	return default_turns


# Black Sludge — Poison-type holder heal (reuses leftovers_heal's exact
# maxHP/16 formula and full-HP gate, source: TryLeftovers via the Black Sludge
# dispatch case, battle_hold_effects.c L1150-1155). Returns 0 for a non-Poison
# holder (that half is black_sludge_damage below, NOT this function) and for
# a holder not holding Black Sludge at all.
static func black_sludge_heal(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_BLACK_SLUDGE:
		return 0
	if not (TypeChart.TYPE_POISON in mon.species.types):
		return 0
	if mon.current_hp >= mon.max_hp:
		return 0
	return max(1, mon.max_hp / 16)


# Black Sludge — non-Poison holder damage. maxHP/8, NOT maxHP/16 (a correction
# to this tier's own plan doc — see the HOLD_EFFECT_BLACK_SLUDGE constant's own
# doc comment for the source citation). Magic Guard gating is left to the
# caller via AbilityManager.blocks_indirect_damage, matching every other
# indirect-damage source's established call-site pattern (Jaboca/Rowap,
# sandstorm/hail chip, etc.) rather than duplicating that check here.
static func black_sludge_damage(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_BLACK_SLUDGE:
		return 0
	if TypeChart.TYPE_POISON in mon.species.types:
		return 0
	return max(1, mon.max_hp / 8)


static func holds_shed_shell(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_SHED_SHELL


static func holds_safety_goggles(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_SAFETY_GOGGLES


# Room Service — -1 Speed while Trick Room is active, if the holder's Speed
# isn't already at its minimum stage. Returns whether the trigger condition
# (Trick Room active) held at all; the caller applies the actual stat change
# via StatusManager.apply_stat_change (matching every other reactive stat item
# in this project) and only consumes the item if that call reports a nonzero
# actual change, per HOLD_EFFECT_ROOM_SERVICE's own doc comment.
static func holds_room_service(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_ROOM_SERVICE


# Blunder Policy — the OHKO-move exclusion lives at the caller (BattleManager
# already distinguishes "accuracy" misses from the OHKO-only "ohko_failed"/
# "sturdy_blocks_ohko" reasons via move.is_ohko, so this function only needs
# the pure item-data check).
static func holds_blunder_policy(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_BLUNDER_POLICY


# ── M18s: Assault Vest's move-restriction half ──────────────────────────────────
#
# Source: CheckMoveLimitations's unusableMoves bitmask (battle_util.c L1622-1624),
# which makes a status move literally UNSELECTABLE in the move menu — this project
# has no equivalent menu-legality-filter architecture anywhere (confirmed via
# grep). The established pattern for a structurally identical restriction already
# in this project (Disable, [M7]) is fail-at-EXECUTION via `move_skipped`, not
# menu-filtering — Assault Vest matches that existing internal precedent rather
# than inventing new selection-time infrastructure. `moveEffect != EFFECT_ME_FIRST`
# is N/A — no Me First move exists anywhere in this project (confirmed: BAN_ME_FIRST
# is a per-move "can this move be copied by Metronome/Mirror Move/etc." data flag,
# not an indicator the move itself is implemented).
static func holds_assault_vest(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_ASSAULT_VEST


# ── M18u: Berserk Gene ───────────────────────────────────────────────────────────
#
# Pure data check — the +6-Atk-cap gate and confusion-infinite behavior are
# orchestrated by the caller (BattleManager's switch-in block), matching
# HOLD_EFFECT_BERSERK_GENE's own doc comment.
static func holds_berserk_gene(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_BERSERK_GENE


# ── M18w: Red Orb / Blue Orb ─────────────────────────────────────────────────────
#
# Returns the target ability ID (AbilityManager.ABILITY_DESOLATE_LAND or
# ABILITY_PRIMORDIAL_SEA) to set on switch-in, or -1 if the holder doesn't
# qualify (wrong item, wrong species, or no item at all). Source:
# TryPrimalReversion → TryBattleFormChange(FORM_CHANGE_BATTLE_PRIMAL_REVERSION)
# (battle_util.c L4783-4791), gated per-species by the form-change table
# (sGroudonFormChangeTable/sKyogreFormChangeTable, src/data/pokemon/
# form_change_tables.h L735-753): Groudon+Red Orb only, Kyogre+Blue Orb only —
# NOT interchangeable (a Groudon holding Blue Orb, or vice versa, gets nothing).
# Reuses `_species_matches`/`required_species`, the SAME per-item species gate
# M18g's Light Ball/Thick Club/etc. already use — Red Orb's `required_species`
# is set to Groudon(383), Blue Orb's to Kyogre(382), even though BOTH items
# share the identical HOLD_EFFECT_PRIMAL_ORB(108) value, so the item-vs-species
# pairing is fully data-driven (no per-item branching needed here).
# CORRECTION (see HOLD_EFFECT_PRIMAL_ORB's own doc comment): this is
# ABILITY-SET ONLY — no species/stat/type swap, since this project has no
# form-change-mid-battle infrastructure (the same reason Mega Stones are
# excluded from this project's scope entirely).
static func primal_orb_target_ability_id(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_PRIMAL_ORB:
		return -1
	if not _species_matches(mon, item):
		return -1
	if item.required_species == SPECIES_GROUDON:
		return AbilityManager.ABILITY_DESOLATE_LAND
	if item.required_species == SPECIES_KYOGRE:
		return AbilityManager.ABILITY_PRIMORDIAL_SEA
	return -1


# ── M18m: Stat-change-reactive consumed items (4 items) ────────────────────────
#
# Pure data checks, matching the established holds_red_card/holds_eject_button
# shape — all orchestration (the actual mechanic each item triggers) lives in
# BattleManager, at the confirmed insertion point each one needs.

static func holds_weakness_policy(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_WEAKNESS_POLICY


static func holds_white_herb(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_WHITE_HERB


static func holds_eject_pack(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_EJECT_PACK


static func holds_mirror_herb(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_MIRROR_HERB


# ── M18p: Contact-reactive damage family (4 items) ──────────────────────────────
#
# Pure data checks / pure magnitude functions only — contact-gating (via
# AbilityManager.move_makes_contact / .move_triggers_contact_retaliation),
# Magic Guard, and consumption timing are all orchestrated by the caller,
# matching this project's established division of labor for every other
# reactive item (Jaboca/Rowap, Black Sludge, Red Card/Eject Button).

static func holds_rocky_helmet(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_ROCKY_HELMET


# Returns maxHP/6 of the ATTACKER (not the holder) if the HOLDER holds Rocky
# Helmet, else 0. The caller applies this to attacker.current_hp, matching
# jaboca_rowap_retaliation_damage's exact division of responsibility.
static func rocky_helmet_retaliation_damage(
		holder: BattlePokemon, attacker: BattlePokemon, ng_active: bool = false) -> int:
	if not holds_rocky_helmet(holder, ng_active):
		return 0
	return max(1, attacker.max_hp / 6)


static func holds_sticky_barb(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_STICKY_BARB


# End-of-turn self-damage half only (TryStickyBarbOnEndTurn) — NOT
# contact-related, same maxHP/8 shape as black_sludge_damage. Magic Guard
# gating (on the HOLDER, unlike Rocky Helmet's attacker-side gate) is left to
# the caller, matching black_sludge_damage's own established pattern.
static func sticky_barb_damage(mon: BattlePokemon, ng_active: bool = false) -> int:
	if not holds_sticky_barb(mon, ng_active):
		return 0
	return max(1, mon.max_hp / 8)


static func holds_protective_pads(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_PROTECTIVE_PADS


static func holds_punching_glove(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_PUNCHING_GLOVE


# ── M18t: Iron Ball / Air Balloon ────────────────────────────────────────────────
#
# Pure data checks only — both items' actual mechanisms are orchestrated by the
# caller: is_grounded/blocks_move_type/TypeChart's grounded_override
# (AbilityManager, DamageCalculator, BattleManager's OHKO branch) for the
# grounding halves, apply_speed_modifier above for Iron Ball's Speed half, and
# a new BattleManager consumption block (before went_to_sub) for Air Balloon's
# pop.

static func holds_iron_ball(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_IRON_BALL


static func holds_air_balloon(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_AIR_BALLOON
