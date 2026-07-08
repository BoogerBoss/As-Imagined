class_name AbilityManager
extends RefCounted

# Ability trigger/dispatch system for Milestone 8.
# Mirrors AbilityBattleEffects(enum AbilityEffect caseID, ...) in
# src/battle_util.c (L2919). We implement only the triggers needed for M8.
#
# Trigger points (matching ABILITYEFFECT_* enum in include/battle_util.h L43–65):
#   ON_SWITCH_IN   → fires when a Pokémon enters battle (ABILITYEFFECT_ON_SWITCHIN)
#   MOVE_END       → fires after a move hits the defender (ABILITYEFFECT_MOVE_END)
#   END_TURN       → fires at end of turn (ABILITYEFFECT_ENDTURN)
#
# Passive modifiers (Huge Power, Thick Fat, Levitate) are not dispatched through
# AbilityBattleEffects in the source — they're inline in GetAttackStatModifier /
# GetDefenseStatModifier / CalcTypeEffectivenessMultiplierInternal. We handle them
# as query functions called from DamageCalculator.

# ── Ability ID constants ─────────────────────────────────────────────────────
# Source: include/constants/abilities.h
const ABILITY_NONE:        int = 0
const ABILITY_SPEED_BOOST: int = 3
const ABILITY_STATIC:      int = 9
const ABILITY_INTIMIDATE:  int = 22
const ABILITY_ROUGH_SKIN:  int = 24
const ABILITY_LEVITATE:    int = 26
const ABILITY_SYNCHRONIZE: int = 28
const ABILITY_HUGE_POWER:  int = 37
const ABILITY_THICK_FAT:   int = 47
const ABILITY_FLAME_BODY:  int = 49
const ABILITY_DRIZZLE:     int = 2
const ABILITY_DROUGHT:     int = 70
const ABILITY_PURE_POWER:  int = 74

# M17a: Tier A move effects — damage-pipeline modifiers, no new infrastructure.
# Source: include/constants/abilities.h. Docs/m17_recon.md Section 9 Bucket A (plus
# Compound Eyes/Battle Armor/Shell Armor/Adaptability/Rock Head/No Guard from the
# original M17 recon's Bucket A, docs/m17_recon.md Section 4/5) — final list locked
# in docs/decisions.md [M17a] after cross-checking Section 13's exclusions removed
# Shadow Shield/Prism Armor/Neuroforce/Full Metal Body/Transistor/Dragon's Maw.
const ABILITY_BATTLE_ARMOR:   int = 4
const ABILITY_COMPOUND_EYES:  int = 14
const ABILITY_MARVEL_SCALE:   int = 63
const ABILITY_OVERGROW:       int = 65
const ABILITY_BLAZE:          int = 66
const ABILITY_TORRENT:        int = 67
const ABILITY_SWARM:          int = 68
const ABILITY_ROCK_HEAD:      int = 69
const ABILITY_SHELL_ARMOR:    int = 75
const ABILITY_ADAPTABILITY:   int = 91
const ABILITY_SNIPER:         int = 97
const ABILITY_NO_GUARD:       int = 99
const ABILITY_TINTED_LENS:    int = 110
const ABILITY_FILTER:         int = 111
const ABILITY_SOLID_ROCK:     int = 116
const ABILITY_GUTS:           int = 62
const ABILITY_HUSTLE:         int = 55
const ABILITY_HEATPROOF:      int = 85
const ABILITY_DEFEATIST:      int = 129
const ABILITY_TOXIC_BOOST:    int = 137
const ABILITY_FLARE_BOOST:    int = 138
const ABILITY_MULTISCALE:     int = 136
const ABILITY_IRON_BARBS:     int = 160
const ABILITY_SAND_FORCE:     int = 159
const ABILITY_FUR_COAT:       int = 169
const ABILITY_TOUGH_CLAWS:    int = 181
const ABILITY_STEELWORKER:    int = 200
const ABILITY_BATTERY:        int = 217
const ABILITY_ICE_SCALES:     int = 246
const ABILITY_POWER_SPOT:     int = 249
const ABILITY_STEELY_SPIRIT:  int = 252
const ABILITY_ROCKY_PAYLOAD:  int = 276

# M17b: Tier B move effects — stat-stage-system interactions, no new infrastructure.
# Source: include/constants/abilities.h. docs/m17_recon.md Section 4/5 (original) and
# Section 9 Bucket B (addendum) — final list locked in docs/decisions.md [M17b] after
# cross-checking Section 13's exclusions (Soul-Heart, Full Metal Body, Intrepid Sword,
# Dauntless Shield, Chilling Neigh, Grim Neigh, As One ×2 all removed as legendary-
# exclusive) and a correction to the exclusion list itself (Beast Boost, also
# UB-exclusive per Section 13.1, was missing from the task's transcription). Guard Dog
# and Opportunist are deferred — see decisions.md for why each needs infra this tier
# doesn't have. Moxie is INCLUDED despite the recon's shallow-pass note that it wasn't
# "hooked anywhere" — a deeper look found `_last_attacker`/`pokemon_fainted` (M14b/M7)
# already provide everything it needs.
const ABILITY_STEADFAST:      int = 80
const ABILITY_ANGER_POINT:    int = 83
const ABILITY_SIMPLE:         int = 86
const ABILITY_DOWNLOAD:       int = 88
const ABILITY_CLEAR_BODY:     int = 29
const ABILITY_WHITE_SMOKE:    int = 73
const ABILITY_KEEN_EYE:       int = 51
const ABILITY_HYPER_CUTTER:   int = 52
const ABILITY_MOXIE:          int = 153
const ABILITY_UNAWARE:        int = 109
const ABILITY_CONTRARY:       int = 126
const ABILITY_DEFIANT:        int = 128
const ABILITY_WEAK_ARMOR:     int = 133
const ABILITY_MOODY:          int = 141
const ABILITY_BIG_PECKS:      int = 145
const ABILITY_JUSTIFIED:      int = 154
const ABILITY_RATTLED:        int = 155
const ABILITY_FLOWER_VEIL:    int = 166
const ABILITY_SWEET_VEIL:     int = 175
const ABILITY_GOOEY:          int = 183
const ABILITY_STAMINA:        int = 192
const ABILITY_WATER_COMPACTION: int = 195
const ABILITY_BERSERK:        int = 201
const ABILITY_TANGLING_HAIR:  int = 221
const ABILITY_COMPETITIVE:    int = 172
const ABILITY_COTTON_DOWN:    int = 238
const ABILITY_STEAM_ENGINE:   int = 243
const ABILITY_PASTEL_VEIL:    int = 257
const ABILITY_THERMAL_EXCHANGE: int = 270
const ABILITY_ANGER_SHELL:    int = 271
const ABILITY_PURIFYING_SALT: int = 272
const ABILITY_SUPERSWEET_SYRUP: int = 306

# M17c: Tier C move effects — switch-in/turn-end triggers, no new field-state
# infrastructure. Source: include/constants/abilities.h. docs/m17_recon.md Section 4/5
# (original) Bucket C and Section 9 Bucket C (addendum) — final list locked in
# docs/decisions.md [M17c] after cross-checking Section 13's exclusions (Toxic Chain
# removed as Loyal-Three-legendary-exclusive) and a correction to the exclusion list
# itself (Spicy Spray, Scovillain-Mega-exclusive per Section 13.3, falls under this
# project's pre-existing "no Mega Evolution" scope note — not in the task's Section 13
# transcription but excluded on separate, already-established grounds). Solar Power and
# Poison Heal are deferred to M17d per Section 11's own tier proposal (multi-part
# abilities spanning the damage pipeline, bundled with the Primal weather trio).
# Harvest is deferred (needs new "last consumed berry" tracking, absent from Section
# 11's actual M17c list despite being Bucket C in the original table).
const ABILITY_EFFECT_SPORE:   int = 27
const ABILITY_POISON_POINT:   int = 38
const ABILITY_RAIN_DISH:      int = 44
const ABILITY_SAND_STREAM:    int = 45
const ABILITY_TRUANT:         int = 54
const ABILITY_SHED_SKIN:      int = 61
const ABILITY_DRY_SKIN:       int = 87
const ABILITY_HYDRATION:      int = 93
const ABILITY_ANTICIPATION:   int = 107
const ABILITY_FOREWARN:       int = 108
const ABILITY_ICE_BODY:       int = 115
const ABILITY_SNOW_WARNING:   int = 117
const ABILITY_FRISK:          int = 119
const ABILITY_FLOWER_GIFT:    int = 122
const ABILITY_CURSED_BODY:    int = 130
const ABILITY_HEALER:         int = 131
const ABILITY_POISON_TOUCH:   int = 143
const ABILITY_CHEEK_POUCH:    int = 167
const ABILITY_SLUSH_RUSH:     int = 202
const ABILITY_RIPEN:          int = 247
const ABILITY_TOXIC_DEBRIS:   int = 295
const ABILITY_HOSPITALITY:    int = 299

# M17d: Weather-setter completions + Primal trio + multi-part abilities deferred from
# M17c. Source: include/constants/abilities.h. docs/m17_recon.md Section 11's M17d
# proposal — final list locked in docs/decisions.md [M17d] after cross-checking Section
# 13's exclusions (Orichalcum Pulse excluded as Koraidon-exclusive per Rob's updated
# legendary-exclusivity standard, despite Section 11's stale prose pairing it with
# Hadron Engine into this tier) and confirming Dry Skin already shipped in M17c. Harvest
# deferred again (needs genuinely new "last consumed berry" infra this tier's other 5
# abilities don't).
const ABILITY_POISON_HEAL:      int = 90
const ABILITY_SOLAR_POWER:      int = 94
const ABILITY_PRIMORDIAL_SEA:   int = 189
const ABILITY_DESOLATE_LAND:    int = 190
const ABILITY_DELTA_STREAM:     int = 191

# M17f: Trapping check (new infrastructure) — Shadow Tag/Arena Trap/Magnet Pull.
# Source: include/constants/abilities.h. docs/m17_recon.md Section 11's M17f proposal
# (unchanged 3-ability group, infra flag #3) — cross-checked against Section 13's
# exclusion sweep (13.1-13.4): none of the three appear anywhere in it, clean.
const ABILITY_SHADOW_TAG:       int = 23
const ABILITY_ARENA_TRAP:       int = 71
const ABILITY_MAGNET_PULL:      int = 42

# M17g: Ability-suppression plumbing (new infrastructure) — Mold Breaker/Neutralizing
# Gas. Source: include/constants/abilities.h. docs/m17_recon.md Section 11's M17g
# proposal, re-derived (Step 0) against Section 13: Turboblaze (163)/Teravolt (164)
# EXCLUDED (both flagged legendary-exclusive in Section 13.1 — Reshiram/Kyurem-White,
# Zekrom/Kyurem-Black — same correction pattern as Beast Boost in [M17b] and
# Orichalcum Pulse in [M17d]). Mycelium Might (298) DEFERRED, not included: it's a
# genuine hybrid (battle_util.c L4805-4820: the ability-ignore half fits this tier's
# plumbing, but its other half — own status moves always act last in their priority
# bracket — is the Stall turn-order shape, which isn't built in this project yet).
# Implementing only the ability-ignore half would misrepresent the ability, the same
# reasoning [M17b] used to defer Guard Dog's two-part mechanic. Final M17g list: just
# Mold Breaker and Neutralizing Gas.
const ABILITY_MOLD_BREAKER:     int = 104
const ABILITY_NEUTRALIZING_GAS: int = 256

# M17g/M17h: exemption flags live on the AbilityData RESOURCE ITSELF
# (`AbilityData.breakable`/`.cant_be_suppressed`/`.cant_be_traced`/`.cant_be_copied`/
# `.cant_be_swapped`/`.cant_be_overwritten` — scripts/data/ability_data.gd), not as
# hardcoded ID arrays in this file. M17g's original design used two such arrays
# (MOLD_BREAKER_BREAKABLE, NEUTRALIZING_GAS_UNSUPPRESSABLE); this was retrofitted
# during M17h after discovering `AbilityData` already had these exact fields defined
# (with citations to Trace/Wandering Spirit/Neutralizing Gas/Mold Breaker) and
# `gen_abilities.py` already had full rendering support for them, sitting completely
# unused. Rather than add a THIRD parallel mechanism for M17h's own new exemption
# needs (cant_be_traced/cant_be_copied/cant_be_swapped), all five flags were unified
# onto the one pre-built, purpose-named mechanism — a single source of truth per
# ability, set once in `gen_abilities.py`, with no separate list to keep in sync.
# See docs/decisions.md [M17h] for the full migration and the addendum note on [M17g].
#
# Every `AbilityData.cant_be_*`/`.breakable` value in this project's data was cross-
# checked directly against `src/data/abilities.h` for each of the ~115 abilities this
# project implements (not assumed from the field names alone) — 26 abilities are
# `breakable` (Battle Armor, Shell Armor, Levitate, Thick Fat, Marvel Scale, Fur Coat,
# Multiscale, Filter, Solid Rock, Ice Scales, Heatproof, Dry Skin, Purifying Salt,
# Clear Body, White Smoke, Hyper Cutter, Big Pecks, Keen Eye, Flower Veil, Sweet Veil,
# Pastel Veil, Simple, Contrary, Unaware, Flower Gift, Thermal Exchange); NONE are
# `cant_be_suppressed` (every source ability with that flag — Multitype, Zen Mode,
# Stance Change, Shields Down, Schooling, Disguise, Battle Bond, Power Construct,
# Comatose, RKS System, Gulp Missile, Ice Face, As One ×2, Zero to Hero, Commander,
# Tera Shift — is a battle-form-change/Mega/Tera/legendary-exclusive mechanic already
# out of scope, confirmed via grep: none are implemented); Trace/Receiver/Power of
# Alchemy/Neutralizing Gas are `cant_be_traced`; Trace/Flower Gift/Receiver/Power of
# Alchemy/Neutralizing Gas are `cant_be_copied`; only Neutralizing Gas is
# `cant_be_swapped`; only Truant is `cant_be_overwritten` (though nothing in this
# project's code currently reads that flag — see the Mummy/Lingering Aroma note below
# for why, and docs/decisions.md [M17h] for the "populated but not yet consumed" call).

# M17h: Ability-copy/overwrite plumbing (new infrastructure) — Trace, Mummy, Receiver,
# Power of Alchemy, Wandering Spirit, Lingering Aroma. Third genuinely new-infrastructure
# tier in M17 (after M17f's trapping check and M17g's suppression plumbing). Source:
# include/constants/abilities.h. docs/m17_recon.md Section 11's M17h proposal — final
# list re-verified (Step 0) against Section 13's full exclusion sweep: none of the six
# appear anywhere in it, clean (unlike the M17f→M17g handoff, no correction needed here).
# Lingering Aroma's source ID is defined symbolically (`= ABILITIES_COUNT_GEN8`, not a
# literal number) — independently recounted against `include/constants/abilities.h`
# (AS_ONE_SHADOW_RIDER=267, then the unassigned ABILITIES_COUNT_GEN8 lands on 268) to
# confirm it resolves to 268, matching this project's pre-existing placeholder `.tres`
# from an earlier (pre-M17) data-pipeline fix.
const ABILITY_TRACE:             int = 36
const ABILITY_MUMMY:             int = 152
const ABILITY_RECEIVER:          int = 222
const ABILITY_POWER_OF_ALCHEMY:  int = 223
const ABILITY_WANDERING_SPIRIT:  int = 254
const ABILITY_LINGERING_AROMA:   int = 268

# M17i: Switch-out trigger hook (new infrastructure). Step 0 list re-verified against
# Section 13's full exclusion sweep: neither ID appears anywhere in it.
const ABILITY_NATURAL_CURE:  int = 30
const ABILITY_REGENERATOR:   int = 144

# M17j: Item-transfer primitive (new infrastructure). Step 0 list re-verified against
# Section 13's full exclusion sweep: none of the four appear anywhere in it.
# Pickpocket's canonical ID is defined symbolically in source (`= ABILITIES_COUNT_GEN4`,
# not a literal number) — independently recounted (`ABILITY_AIR_LOCK = 76`, then
# `ABILITIES_COUNT_GEN3` auto-increments to 77, `ABILITY_TANGLED_FEET = ABILITIES_
# COUNT_GEN3` restarts the Gen-4 literal sequence at 77, ..., `ABILITY_BAD_DREAMS = 123`,
# then the unassigned `ABILITIES_COUNT_GEN4` lands on 124) to confirm it resolves to 124,
# matching this project's pre-existing placeholder `.tres` (already present, unlike
# Lingering Aroma's M17h-era gap).
const ABILITY_STICKY_HOLD: int = 60
const ABILITY_PICKPOCKET:  int = 124
const ABILITY_MAGICIAN:    int = 170
const ABILITY_SYMBIOSIS:   int = 180

# M17k: Priority-move-block check (new infrastructure). Step 0 list re-verified against
# Section 13's full exclusion sweep: none of the three appear anywhere in it. Confirmed
# from source (`IsDazzlingAbility`, battle_move_resolution.c L1499-1509) that all three
# share the exact same mechanic — a single shared dispatch, not three near-identical
# but subtly-different implementations.
const ABILITY_QUEENLY_MAJESTY: int = 214
const ABILITY_DAZZLING:        int = 219
const ABILITY_ARMOR_TAIL:      int = 296

# M17l: Doubles-redirect/aura abilities. Step 0 list re-verified against Section 13's
# full exclusion sweep: none of the six appear anywhere in it. Two genuinely different
# mechanic shapes: Lightning Rod/Storm Drain are redirect-TRIGGER abilities (defender
# side), Propeller Tail/Stalwart are redirect-BYPASS abilities (attacker side) — the
# opposite direction, not a variant of the same mechanic. Telepathy/Friend Guard are a
# separate damage-exemption/reduction pair, unrelated to redirection at all.
const ABILITY_LIGHTNING_ROD:  int = 31
const ABILITY_STORM_DRAIN:    int = 114
const ABILITY_FRIEND_GUARD:   int = 132
const ABILITY_TELEPATHY:      int = 140
const ABILITY_PROPELLER_TAIL: int = 239
const ABILITY_STALWART:       int = 242

# M17m: Absorb-family abilities (docs/m17m_absorb_recon.md; Step 0 re-verified all seven
# IDs fresh against `include/constants/abilities.h` and confirmed none appear in Section
# 13's exclusion sweep). All seven route through the SAME source dispatch,
# `CanAbilityAbsorbMove` (battle_util.c L2235-2313), that `[M17l]`'s Lightning
# Rod/Storm Drain already partially extended via `absorbs_move_type` — but the
# on-absorb EFFECT is three genuinely different shapes, not one: heal maxHP/4 (Volt
# Absorb, Water Absorb, Earth Eater, and Dry Skin's water half — ABILITY_DRY_SKIN
# already declared above, M17c), stat-stage boost of VARYING magnitude (Sap Sipper
# Atk+1, Motor Drive Speed+1 — NOT Sp.Atk, unlike Lightning Rod — Well-Baked Body
# Def+2, NOT +1 — the single highest-risk detail in this tier), and a persistent
# no-immediate-effect flag whose payoff is a LATER Fire-move power boost for the
# holder itself (Flash Fire — see `attack_modifier_uq412`, the same function
# Overgrow/Blaze/Torrent/Swarm already occupy for their own HP-threshold boosts).
const ABILITY_VOLT_ABSORB:     int = 10
const ABILITY_WATER_ABSORB:    int = 11
const ABILITY_FLASH_FIRE:      int = 18
const ABILITY_MOTOR_DRIVE:     int = 78
const ABILITY_SAP_SIPPER:      int = 157
const ABILITY_WELL_BAKED_BODY: int = 273
const ABILITY_EARTH_EATER:     int = 297

# M17n-1: Status-immunity family + simple no-ops (docs/m17n_recon.md Group 1). Step 0
# re-verified all IDs fresh against `include/constants/abilities.h` and confirmed none
# appear in Section 13's exclusion sweep. Four categories, not one uniform shape:
# genuine status-immunity abilities (Category A), move-flag immunity needing pre-
# existing-but-unused MoveData flags (Category B), documented cosmetic no-ops
# (Category C: Illuminate/Honey Gather, matching the Anticipation/Forewarn/Frisk
# precedent), and abilities confirmed genuinely out of battle-engine scope (Category D:
# Run Away/Pickup/Ball Fetch — deliberately given NO constant/`.tres` entry at all,
# distinct from Category C's "exists but does nothing" no-ops).
const ABILITY_DAMP:          int = 6
const ABILITY_LIMBER:        int = 7
const ABILITY_OBLIVIOUS:     int = 12
const ABILITY_SHIELD_DUST:   int = 19
const ABILITY_OWN_TEMPO:     int = 20
const ABILITY_INNER_FOCUS:   int = 39
const ABILITY_MAGMA_ARMOR:   int = 40
const ABILITY_WATER_VEIL:    int = 41
const ABILITY_SOUNDPROOF:    int = 43
const ABILITY_EARLY_BIRD:    int = 48
const ABILITY_CUTE_CHARM:    int = 56
const ABILITY_RIVALRY:       int = 79  # [M18.5d-2]: no prior constant existed — never implemented
const ABILITY_INSOMNIA:      int = 15
const ABILITY_ILLUMINATE:    int = 35
const ABILITY_IMMUNITY:      int = 17
const ABILITY_LEAF_GUARD:    int = 102
const ABILITY_VITAL_SPIRIT:  int = 72
const ABILITY_AROMA_VEIL:    int = 165
const ABILITY_BULLETPROOF:   int = 171
const ABILITY_HONEY_GATHER:  int = 118

# M17n-2: Weather/evasion + speed family, plus Air Lock (docs/m17n_recon.md Group 2).
# Step 0 re-verified all 8 IDs fresh against `include/constants/abilities.h`; none
# appear in the exclusion list (Air Lock is the ESTABLISHED KEPT precedent from Section
# 13.1, not itself excluded — confirmed by re-reading that section directly, not
# assumed from its legendary (Rayquaza) association). Cloud Nine/Air Lock confirmed
# genuinely identical from source (`HasWeatherEffect`, battle_util.c L9873-9889) — the
# exact same case branch, no asymmetry of any kind (both non-breakable, both
# suppressible by Neutralizing Gas, both purely cosmetic on switch-in).
const ABILITY_SAND_VEIL:    int = 8
const ABILITY_CLOUD_NINE:   int = 13
const ABILITY_SWIFT_SWIM:   int = 33
const ABILITY_CHLOROPHYLL:  int = 34
const ABILITY_AIR_LOCK:     int = 76
const ABILITY_SNOW_CLOAK:   int = 81
const ABILITY_SAND_RUSH:    int = 146
const ABILITY_SAND_SPIT:    int = 245

# M17n-3: Turn-order/priority modifiers (docs/m17n_recon.md Group 3). Step 0
# re-verified all 6 IDs fresh against `include/constants/abilities.h`; none appear in
# the exclusion list. Confirmed via a direct grep of `src/data/abilities.h` that NONE
# of the six carries a `breakable`/`cantBe*` flag — every one of them is judged
# against the HOLDER's own chosen move, never a "defender's ability" an opposing
# Mold-Breaker attacker could bypass, so `effective_ability_id` is called with no
# `attacker` context for five of the six (see `move_priority_bonus`/
# `quick_draw_activates`/`has_slow_turn_order_effect` below). Mycelium Might (298) is
# the sole exception: it ALSO acts as a Mold-Breaker-type ability toward an opposing
# battler while the holder's own current move is status-category — see
# `effective_ability_id`'s new `attacker_move` param below.
const ABILITY_STALL:           int = 100
const ABILITY_PRANKSTER:       int = 158
const ABILITY_GALE_WINGS:      int = 177
const ABILITY_TRIAGE:          int = 205
const ABILITY_QUICK_DRAW:      int = 259
const ABILITY_MYCELIUM_MIGHT:  int = 298

# M17n-5: Damage-pipeline leftovers (docs/m17n_recon.md Group 4, trimmed by Rob's
# explicit exclusions — Ruin quartet/Water Bubble/Supreme Overlord/Plus/Minus — see
# docs/decisions.md [M17n-5] for the full count-discrepancy note: this project's own
# re-derivation lands on 18 named abilities, not 19; of those 18, Skill Link (92) is
# further DEFERRED this tier — confirmed via direct grep that no multi_hit mechanic
# exists anywhere in this codebase's battle logic (multi_hit/strike_count are dormant
# MoveData schema fields only), so it has nothing to modify. No constant added for it.
# Breakable-flag reachability checked individually per ability, not assumed uniform:
# genuinely wired for Mold-Breaker bypass (all true defender-role checks) — Sturdy,
# Fluffy, Punk Rock's defense half, Tangled Feet. Set faithfully in .tres data but NOT
# functionally reachable in this project (matching [M17j]'s Sticky Hold precedent —
# structurally attacker-self-checks in source too, never read in a defender role) —
# Technician, Sheer Force, Mega Launcher, Stakeout.
const ABILITY_STURDY:          int = 5
const ABILITY_IRON_FIST:       int = 89
const ABILITY_TECHNICIAN:      int = 101
const ABILITY_RECKLESS:        int = 120
const ABILITY_SHEER_FORCE:     int = 125
const ABILITY_ANALYTIC:        int = 148
const ABILITY_SUPER_LUCK:      int = 105
const ABILITY_TANGLED_FEET:    int = 77
const ABILITY_STRONG_JAW:      int = 173
const ABILITY_MEGA_LAUNCHER:   int = 178
const ABILITY_STAKEOUT:        int = 198
const ABILITY_LONG_REACH:      int = 203
const ABILITY_FLUFFY:          int = 218
const ABILITY_PUNK_ROCK:       int = 244
const ABILITY_SHARPNESS:       int = 292
const ABILITY_SLOW_START:      int = 112
const ABILITY_SERENE_GRACE:    int = 32

# M17n-4 (Group 7): type-mutation/choice-lock cheap reuses. RKS System (225) excluded
# per Rob's explicit decision (recorded in memory, not implemented here) — do not add
# a constant for it. Color Change/Protean/Libero all reuse the existing
# BattleManager._set_mon_type/_reset_mon_type/BattlePokemon.original_types
# infrastructure (M16e/follow-up-fixes); Gorilla Tactics reuses the existing
# BattlePokemon.choice_locked_move field M12 already built. None of these five carry
# any breakable/cant_be_* flag in source EXCEPT Multitype (cantBeCopied/cantBeSwapped/
# cantBeTraced/cantBeSuppressed/cantBeOverwritten all TRUE — src/data/abilities.h
# L906-916) — confirmed by reading each ability's actual data-table entry directly
# after an earlier grep pass with too-wide context bled flags from adjacent unrelated
# abilities (Immunity/Fur Coat/Neutralizing Gas) into these five; re-verified narrowly.
const ABILITY_COLOR_CHANGE:    int = 16
const ABILITY_PROTEAN:         int = 168
const ABILITY_LIBERO:          int = 236
const ABILITY_MULTITYPE:       int = 121
const ABILITY_GORILLA_TACTICS: int = 255

# M17n-6 (Group 5): type-effectiveness-pipeline leftovers, including Wonder Guard —
# the highest-risk remaining item in all of M17 per docs/m17_recon.md's own flag.
# IDs re-verified fresh against include/constants/abilities.h (not carried over from
# any recon doc) — Wonder Guard=25, Normalize=96, Scrappy=113, Overcoat=142,
# Refrigerate=174, Pixilate=182, Liquid Voice=204, Galvanize=206, Mind's Eye=300.
const ABILITY_WONDER_GUARD: int = 25
const ABILITY_NORMALIZE:    int = 96
const ABILITY_SCRAPPY:      int = 113
const ABILITY_OVERCOAT:     int = 142
const ABILITY_REFRIGERATE:  int = 174
const ABILITY_PIXILATE:     int = 182
const ABILITY_LIQUID_VOICE: int = 204
const ABILITY_GALVANIZE:    int = 206
const ABILITY_MINDS_EYE:    int = 300

# M17n-6 follow-up: two "-ate" family members originally excluded, both explicit
# exclusion reversals confirmed by Rob (recorded in memory), not re-derived here.
# Aerilate (184) — was excluded as Mega-exclusive-only (Section 13.3); reversed,
# now in scope. Dragonize (312) — was one of Section 8.3's 6 hack-custom/
# non-canonical IDs in THIS reference tree (no aiRating field, sandwiched between
# two literal blank "-------"/"No special ability" placeholder slots and two
# abilities whose own description is literally "Unimplemented.") — flagged
# explicitly back to Rob before implementing per this follow-up's own instruction,
# who confirmed it's a deliberate override: Dragonize has since become a real
# ability in a newer generation than this reference tree models, and should be
# implemented despite the reference repo's own hack-cluster positioning.
const ABILITY_AERILATE:  int = 184
const ABILITY_DRAGONIZE: int = 312

# M17n-7 (Group 6): item/berry interaction. IDs re-verified fresh against
# include/constants/abilities.h. None of these six carry a `breakable` flag in
# source's data table (confirmed individually, not assumed uniform) — every
# Mold-Breaker-bypass test this tier would otherwise need is correctly absent.
const ABILITY_GLUTTONY:  int = 82
const ABILITY_UNBURDEN:  int = 84
const ABILITY_KLUTZ:     int = 103
const ABILITY_UNNERVE:   int = 127
const ABILITY_HARVEST:   int = 139
const ABILITY_CUD_CHEW:  int = 291

# M17n-8 (Group 8, sub-tier 1: contact/faint-timing + reactive/one-off). IDs
# re-verified fresh against include/constants/abilities.h. None of these five carry a
# `breakable` or `cant_be_suppressed` flag in source's data table (confirmed
# individually) — no Mold-Breaker-bypass test needed for any of them; Neutralizing
# Gas suppression applies to all five via the standard effective_ability_id chokepoint.
const ABILITY_MERCILESS:    int = 196
const ABILITY_CORROSION:    int = 212
const ABILITY_INNARDS_OUT:  int = 215
const ABILITY_OPPORTUNIST:  int = 290
const ABILITY_AFTERMATH:    int = 106

# M17n-9 (Group 8, "wide-but-shallow systems"). IDs re-verified fresh against
# include/constants/abilities.h. Magic Guard and Infiltrator carry NEITHER
# `breakable` NOR `cant_be_suppressed` in source's data table (confirmed
# individually) — no Mold-Breaker-bypass test needed for either (both are
# attacker-or-holder-only self-checks, structurally outside Mold Breaker's
# "bypass the DEFENDER's ability" scope). Magic Bounce is the one exception:
# source's abilities.h data table gives it `.breakable = TRUE` explicitly — a
# Mold-Breaker-wielding attacker's status move bypasses a Magic Bounce holder's
# reflection entirely, confirmed from source rather than assumed either way.
const ABILITY_MAGIC_GUARD:  int = 98
const ABILITY_INFILTRATOR:  int = 151
const ABILITY_MAGIC_BOUNCE: int = 156

# M17n-10 (Group 8, "unique/standalone" part 1). IDs re-verified fresh against
# include/constants/abilities.h. Guard Dog is the only one of these six carrying a
# `breakable` flag in source's data table (confirmed individually); the other five
# have neither `breakable` nor `cant_be_suppressed`. Guard Dog's `.breakable` only
# actually matters for ONE of its two mechanics though — its forced-switch block
# (`blocks_forced_switch`), checked during real move resolution. Its OTHER mechanic
# (the Intimidate-reversal half, in `try_switch_in` below) is NOT Mold-Breaker-aware
# despite the shared flag — traced `moldBreakerActive`'s own source set-site and
# confirmed it's never active outside a move-processing window, which a switch-in
# ability trigger structurally isn't (see that function's own doc comment for the
# full citation). Forecast additionally carries `cant_be_copied`/`cant_be_traced`
# (both pre-existing AbilityData fields from `[M17h]`, not new).
const ABILITY_SCREEN_CLEANER: int = 251
const ABILITY_LIQUID_OOZE:    int = 64
const ABILITY_PRESSURE:       int = 46
const ABILITY_QUICK_FEET:     int = 95
const ABILITY_GUARD_DOG:      int = 275
const ABILITY_FORECAST:       int = 59

# M17n-11 (Group 8, "unique/standalone" part 2 — the FINAL M17n sub-tier). IDs
# re-verified fresh against include/constants/abilities.h. Wonder Skin and Mirror
# Armor both carry `breakable=TRUE` in source's data table; Costar has neither flag;
# Comatose carries `cant_be_copied`/`cant_be_swapped`/`cant_be_traced`/
# `cant_be_suppressed`/`cant_be_overwritten` (ALL FIVE M17h-style exemption flags) but
# NOT `breakable` — so, unlike every other ability this project has wired a
# Mold-Breaker-bypass for, Comatose's own mechanic (see StatusManager.try_apply_status)
# is never bypassable by an attacker's Mold Breaker, and Neutralizing Gas never
# suppresses it either.
const ABILITY_COMATOSE:       int = 213
const ABILITY_COSTAR:         int = 294
const ABILITY_WONDER_SKIN:    int = 147
const ABILITY_MIRROR_ARMOR:   int = 240

# M17h: source models FOUR distinct "can this ability be read from / changed away from"
# flags in `src/data/abilities.h` — `cantBeTraced`, `cantBeCopied`, `cantBeSwapped`,
# `cantBeOverwritten` — genuinely different from each other and from M17g's
# `cantBeSuppressed` (Truant is `cantBeOverwritten` but NOT `cantBeSuppressed`; Flower
# Gift is `cantBeCopied` but nothing else; confirmed by direct inspection, not assumed
# to overlap). Each is checked at a DIFFERENT point per ability, verified from source
# rather than treated as interchangeable, and each reads straight off the relevant
# `AbilityData.cant_be_*` field (see the field-based-design comment above) rather than
# a hardcoded array:
#   - Trace's `IsAbilityPreventingEscape`-shaped switch-in dispatch (battle_util.c
#     L2964-3000) checks `cantBeTraced` on the TARGET's raw ability.
#   - Receiver/Power of Alchemy's `BS_TryActivateReceiver` (battle_script_commands.c
#     L12946-12968) checks `cantBeCopied` on the FAINTED ALLY's raw ability.
#   - Wandering Spirit's dispatch (battle_util.c L3884-3909) checks `cantBeSwapped` on
#     the ATTACKER's CURRENT ability (the one about to be swapped away).
#   - Mummy/Lingering Aroma's dispatch (battle_util.c L3859-3883) checks
#     `cantBeSuppressed` (NOT `cantBeOverwritten` — verified directly; `cantBeOverwritten`
#     is actually consumed by Skill-Swap/Entrainment-style MOVES, which this project
#     doesn't have) on the ATTACKER's CURRENT ability — this REUSES `AbilityData
#     .cant_be_suppressed`, the exact same field M17g's Neutralizing Gas exemption
#     reads, rather than duplicating it.
# Note: source's `ABILITY_NONE` entry is itself flagged `cantBeTraced`/`cantBeSwapped`
# (but NOT `cantBeCopied` or `cantBeSuppressed`) — in this project, "no ability" is
# `mon.ability == null` rather than an explicit id-0 `AbilityData` resource, so every
# function below checks `== null` directly rather than reading a field off a sentinel.


# M17h: Trace — switch-in, copies a LIVE opponent's CURRENT ability onto the Trace
# holder. Deliberately reads the opponent's RAW `.ability` field, not the suppression-
# aware `effective_ability_id` — confirmed from source, which reads `gBattleMons
# [chosenTarget].ability` directly (battle_util.c L2996), NOT through `GetBattlerAbility`.
# This means Trace copies what an opponent's ability actually IS even if that ability is
# currently being suppressed by an active Neutralizing Gas elsewhere on the field —
# suppression is a separate runtime check applied every time the copied ability is
# later consumed, not a copy-time filter. See docs/decisions.md [M17h] for the
# cross-tier test confirming this explicitly.
#
# Targeting rule (battle_util.c L2971-2988): the two OPPOSING field slots (already
# exactly what `live_opponents` — built the same way M17f's `_get_live_opponents`
# already does — contains in this project's doubles layout) are filtered to alive +
# not-`cantBeTraced`; if BOTH remain eligible, a 50/50 random pick (`RandomPercentage
# (RNG_TRACE, 50)`); if only ONE is eligible, that one deterministically; if NEITHER,
# Trace does nothing this switch-in. This project calls its switch-in ability dispatch
# exactly once per switch-in event (no source-side multi-pass retry loop to guard
# against), so no `traceActivated`-equivalent volatile flag is needed here — the
# call-site architecture itself already provides the "exactly once" guarantee source
# gets from that flag. Ability Shield's early-break (source line ~2993) isn't modeled —
# this project has no Ability Shield item anywhere (same "not modeled" precedent as
# M17f's Shed Shell and M17g's various Ability-Shield gates).
#
# force_pick_second: null = real RNG (50/50); true/false = pin which of exactly 2
#   eligible opponents gets chosen (only meaningful when both slots are eligible).
# ng_active: whether the Trace HOLDER's own ability is currently active — source reads
#   this through `GetBattlerAbility` (suppression-aware) at the dispatch layer, unlike
#   the opponent-side read below (deliberately raw — see the function's main comment).
# Returns the copied ability_id, or -1 if Trace didn't fire (not a Trace holder, or no
# eligible live opponent).
static func try_trace(
		pokemon: BattlePokemon, live_opponents: Array,
		ng_active: bool = false, force_pick_second: Variant = null) -> int:
	if effective_ability_id(pokemon, ng_active) != ABILITY_TRACE:
		return -1
	var eligible: Array = []
	for opp: BattlePokemon in live_opponents:
		if opp.fainted or opp.ability == null:
			continue
		if opp.ability.cant_be_traced:
			continue
		eligible.append(opp)
	if eligible.is_empty():
		return -1
	var chosen: BattlePokemon
	if eligible.size() > 1:
		var pick_second: bool = bool(force_pick_second) if force_pick_second != null \
				else (randi() % 100 < 50)
		chosen = eligible[1] if pick_second else eligible[0]
	else:
		chosen = eligible[0]
	pokemon.ability = chosen.ability
	return chosen.ability.ability_id


# M17h: Receiver / Power of Alchemy — on an ally fainting in a doubles battle, copies
# the fainted ally's ability onto the holder. Source: `BS_TryActivateReceiver`
# (battle_script_commands.c L12946-12968), dispatched from the shared `BattleScript_
# FaintBattler` script (`tryactivatereceiver BS_FAINTED`, data/battle_scripts_1.s
# L2739) that runs for EVERY faint regardless of context — the doubles-only,
# ally-specific restriction comes entirely from the function's own condition
# (`receiverBattler = BATTLE_PARTNER(faintedBattler)`; in singles there IS no partner
# slot, so this project's existing `_get_ally` already returns null there, naturally
# gating this to doubles with zero extra plumbing, matching M17c's Hospitality
# precedent exactly). Confirmed from source that Power of Alchemy shares this EXACT
# same function (`receiverAbility == ABILITY_RECEIVER || receiverAbility ==
# ABILITY_POWER_OF_ALCHEMY`, L12954) — not a separate near-identical implementation.
#
# Reads the FAINTED mon's RAW `.ability` field (source: `gBattleMons[faintedBattler]
# .ability`, L12959 — NOT through `GetBattlerAbility`, since a fainted battler's
# suppression-aware ability would read as NONE via `battlerState[...].notOnField` —
# reading raw is the only way to recover what the fainted mon's ability actually was).
#
# fainted: the ally that just fainted. ally: the potential Receiver/Power-of-Alchemy
# holder (the fainted mon's own doubles partner) — null in singles or if already fainted
# itself (also correctly handles "the Receiver holder itself is the one fainting": in
# that case `fainted` IS the Receiver holder, and `ally`'s own ability is checked
# instead, which won't match unless the ally ALSO happens to hold Receiver).
# ng_active: whether the potential Receiver/Power-of-Alchemy holder's own ability is
#   currently active — source reads this through `GetBattlerAbility` (suppression-aware,
#   `enum Ability receiverAbility = GetBattlerAbility(receiverBattler);` L12951), unlike
#   the fainted ally's read below (deliberately raw — see the function's main comment).
# Returns the copied ability_id, or -1 if it didn't fire.
static func try_receiver_copy(
		fainted: BattlePokemon, ally: BattlePokemon, ng_active: bool = false) -> int:
	if ally == null or ally.fainted:
		return -1
	var ally_id: int = effective_ability_id(ally, ng_active)
	if ally_id != ABILITY_RECEIVER and ally_id != ABILITY_POWER_OF_ALCHEMY:
		return -1
	if fainted.ability == null:
		return -1
	if fainted.ability.cant_be_copied:
		return -1
	ally.ability = fainted.ability
	return fainted.ability.ability_id


# M17h: Wandering Spirit — contact hit landing → SWAPS abilities bidirectionally with
# the attacker (distinct from Mummy's one-directional overwrite just below — confirmed
# from source: both sides are reassigned, L3904-3905, not just the attacker).
# Source: battle_util.c L3884-3909. Exemption checked on the ATTACKER's CURRENT ability
# (the one being swapped away) via `AbilityData.cant_be_swapped` — a genuinely
# different field than Mummy's `cant_be_suppressed` check, verified directly rather than
# assumed to be the same gate. `attacker.ability == null` is also exempt (source's
# `ABILITY_NONE` is itself flagged `cantBeSwapped`). Dynamax exemption
# (`GetActiveGimmick(gBattlerTarget) == GIMMICK_DYNAMAX`) isn't modeled — this project
# has no Dynamax. Reads/writes raw `.ability` fields throughout, same as Trace/Receiver —
# suppression is never a copy-time filter (see try_trace's doc comment).
#
# ng_active: whether the Wandering Spirit HOLDER's own ability is currently active
#   (suppression-aware, matching source's `gLastUsedAbility` dispatch gate) — the
#   attacker's exemption check just below stays a RAW read (see the function's main
#   comment for why).
# Returns true if the swap occurred (caller resolves the two new ability_ids off
# `defender.ability`/`attacker.ability` directly afterward for signal emission).
static func try_wandering_spirit_swap(
		defender: BattlePokemon, attacker: BattlePokemon,
		move: MoveData, damage: int, ng_active: bool = false) -> bool:
	if effective_ability_id(defender, ng_active) != ABILITY_WANDERING_SPIRIT:
		return false
	if not move_makes_contact(attacker, move, ng_active) or damage <= 0 or attacker.fainted:
		return false
	if attacker.ability == null:
		return false
	if attacker.ability.cant_be_swapped:
		return false
	var attacker_old_ability: AbilityData = attacker.ability
	attacker.ability = defender.ability
	defender.ability = attacker_old_ability
	return true


# M17h: Mummy / Lingering Aroma — contact hit landing → overwrites the ATTACKER's
# ability with Mummy/Lingering Aroma itself (one-directional — the holder's OWN ability
# never changes, the opposite direction from Wandering Spirit's swap above; confirmed
# from source: only `gBattleMons[gBattlerAttacker].ability` is reassigned, L3878, never
# `gBattlerTarget`'s). Source: battle_util.c L3859-3883. Confirmed Lingering Aroma is
# mechanically identical to Mummy, not just similarly-shaped (shares the exact same
# switch-case block, `case ABILITY_LINGERING_AROMA: case ABILITY_MUMMY:`, L3859-3860).
# Exemption checked on the ATTACKER's CURRENT ability via `AbilityData
# .cant_be_suppressed` — the EXACT SAME field M17g's Neutralizing Gas exemption reads
# (verified from source this is genuinely the same flag Mummy checks, not a
# coincidental resemblance to a different exemption) — plus an explicit no-op guard
# when the attacker already holds Mummy OR
# Lingering Aroma (source: L3866-3867, avoids a redundant re-trigger/message when the
# result would be unchanged; also stands in for source's `volatiles.overwrittenAbility
# != GetBattlerAbility(gBattlerTarget)` check, which only ever matters when the
# attacker's ability already equals the holder's — impossible here except via these two
# IDs, since the holder's ability is guaranteed to be one of them by construction).
# `attacker.ability == null` is NOT exempt (source's `ABILITY_NONE` has no
# `cantBeSuppressed` flag) — an ability-less attacker correctly gets Mummy applied.
#
# Returns the new ability_id assigned to the attacker, or -1 if it didn't fire.
static func try_mummy_overwrite(
		defender: BattlePokemon, attacker: BattlePokemon,
		move: MoveData, damage: int, ng_active: bool = false) -> int:
	var holder_id: int = effective_ability_id(defender, ng_active)
	if holder_id != ABILITY_MUMMY and holder_id != ABILITY_LINGERING_AROMA:
		return -1
	if not move_makes_contact(attacker, move, ng_active) or damage <= 0 or attacker.fainted:
		return -1
	if attacker.ability != null:
		var atk_id: int = attacker.ability.ability_id
		if atk_id == ABILITY_MUMMY or atk_id == ABILITY_LINGERING_AROMA:
			return -1
		if attacker.ability.cant_be_suppressed:
			return -1
	attacker.ability = defender.ability
	return holder_id


# M17i: Regenerator / Natural Cure — switch-out trigger hook (new infrastructure).
# Source: battle_script_commands.c :: Cmd_switchoutabilities (L9339-9367), dispatched
# via GetBattlerAbility(battler) — the suppression-aware read, matching this project's
# effective_ability_id (confirmed neither ability sets .cantBeSuppressed in
# src/data/abilities.h, so Neutralizing Gas correctly CAN suppress both). BattleManager
# calls this once per mon at every site that reaches source's Cmd_switchoutabilities:
# voluntary switch, Roar/Whirlwind forced switch, and Baton Pass — NOT faint-based
# replacement, since a fainted mon never calls source's `returntoball`/
# `switchoutabilities` at all (a separate faint-animation script path entirely). This is
# a correction worth flagging explicitly: the gate is "did this mon leave the field
# alive," not "was the switch voluntary" — source's own script confirms Roar-forced
# switch-outs (BattleScript_RoarSuccessRet, `switchoutabilities BS_TARGET`) DO trigger
# Regenerator/Natural Cure, same as a self-chosen switch.
# Natural Cure resets toxic_counter alongside status, matching the existing precedent
# set by M17c's Hydration/Shed Skin/Healer (curing a status that may have already been
# ticking, as opposed to the Lum-Berry-style "cure a just-inflicted status" sites
# elsewhere in this file, where toxic_counter is still guaranteed to be 0).
# Returns a Dictionary so BattleManager can emit the correct existing signals
# (ability_healed / ability_triggered) rather than mutating fields itself blind.
static func try_switch_out(mon: BattlePokemon, ng_active: bool = false) -> Dictionary:
	var result: Dictionary = {"healed_amount": 0, "cured_status": false}
	var id: int = effective_ability_id(mon, ng_active)
	if id == ABILITY_REGENERATOR:
		var healed_hp: int = min(mon.max_hp, mon.current_hp + int(mon.max_hp / 3))
		result["healed_amount"] = healed_hp - mon.current_hp
		mon.current_hp = healed_hp
	elif id == ABILITY_NATURAL_CURE:
		if mon.status != BattlePokemon.STATUS_NONE:
			mon.status = BattlePokemon.STATUS_NONE
			mon.toxic_counter = 0
			result["cured_status"] = true
	return result


# M17j: Item-transfer primitive (new infrastructure). Shared low-level primitive that
# moves `victim`'s held item onto `stealer` (stealer must currently hold none), gated on
# Sticky Hold — the ONE place this check lives, reused by both Pickpocket's and
# Magician's trigger logic below rather than duplicated in each.
# Source: `StealTargetItem` (battle_script_commands.c L2055-2087) for the mechanical
# move itself (`gBattleMons[itemBattler].item = ITEM_NONE;
# gBattleMons[battlerStealer].item = gLastUsedItem;` — a plain one-directional move, never
# an actual two-way swap, since both call sites only ever fire when the stealer already
# has no item of its own); the explicit `ABILITY_STICKY_HOLD` checks guarding each of its
# call sites are what's ported here (Pickpocket: battle_move_resolution.c L3971 — checked
# on the ATTACKER being stolen from; Magician: battle_util.c L4454 — checked on the
# TARGET being stolen from), both via the suppression-aware ability read (`cv->abilities`
# is source's pre-resolved-per-turn ability cache; `GetBattlerAbility` respectively) —
# matching this project's `effective_ability_id`.
# M17n-7: Unburden — source's `StealTargetItem` (battle_script_commands.c L2072/2078)
# clears the STEALER's unburdenActive (they just GAINED an item) and calls
# CheckSetUnburden on the VICTIM (they just LOST theirs, activating it if they hold
# Unburden) — the opposite-direction pair this function's own item move mirrors.
# M18p: bypass_sticky_hold (new, default false) — Sticky Barb's own transfer
# (TryStickyBarbOnTargetHit, battle_hold_effects.c L564-583) explicitly bypasses
# Sticky Hold ("// No sticky hold checks." in source, confirmed genuine: CanStealItem
# and its CanBattlerGetOrLoseItem helper, both read in full, have ZERO Sticky Hold
# reference anywhere — Pickpocket/Magician's own Sticky Hold gates are each a
# SEPARATE explicit check bolted on at THEIR OWN call sites, external to CanStealItem,
# not something CanStealItem itself provides). Defaults false so Pickpocket/Magician's
# existing calls are unaffected; only Sticky Barb's new call site passes true.
static func _try_steal_item(stealer: BattlePokemon, victim: BattlePokemon,
		ng_active: bool = false, bypass_sticky_hold: bool = false) -> bool:
	if stealer.held_item != null:
		return false
	if victim.held_item == null:
		return false
	if not bypass_sticky_hold and effective_ability_id(victim, ng_active) == ABILITY_STICKY_HOLD:
		return false
	stealer.held_item = victim.held_item
	victim.held_item = null
	stealer.unburden_active = false
	if effective_ability_id(victim, ng_active) == ABILITY_UNBURDEN:
		victim.unburden_active = true
	return true


# M18p: Sticky Barb — on a contact hit landing, the item moves from the holder onto
# the attacker (if the attacker currently holds nothing), bypassing Sticky Hold
# (see _try_steal_item's own doc comment for the source citation). Contact-gating
# (via AbilityManager.move_triggers_contact_retaliation) and the item's own
# HOLD_EFFECT_STICKY_BARB check are both left to the caller — this function only
# performs the transfer itself, matching _try_steal_item's own division of labor.
static func try_sticky_barb_transfer(
		attacker: BattlePokemon, holder: BattlePokemon, ng_active: bool = false) -> bool:
	return _try_steal_item(attacker, holder, ng_active, true)


# M17j: Pickpocket — on being hit by a contact move, steals the ATTACKER's item, if the
# Pickpocket holder currently has none of its own. Source: `MoveEndPickpocket`
# (battle_move_resolution.c L3944-3984): the Pickpocket HOLDER must be a battler other
# than the current attacker that was damaged by a contact move this turn and itself holds
# no item (`gBattleMons[battlerDef].item == ITEM_NONE`) — i.e. Pickpocket's holder is
# always the one hit (the defender role in this project's dispatch shape), stealing FROM
# whoever hit it. Dispatched from `try_contact_effects` below (defender-keyed, already
# contact/damage/fainted-attacker-gated by that function's shared guards), matching
# Static/Flame Body/Poison Point's existing inline shape rather than a separate
# top-level wrapper.
# `CanStealItem`'s Mail/Z-Crystal/species-form-change/Booster-Energy/Ogerpon-mask
# exemptions (battle_util.c L8686-8708) are NOT modeled — this project implements none of
# Mail, Z-moves, Mega/form-change items, Paradox Booster Energy, or Ogerpon, so every one
# of those categories is a known, out-of-scope gap rather than a silently-dropped check.


# M17j: Magician — on landing a damaging hit (contact NOT required — confirmed from
# source, no `IsMoveMakingContact` check anywhere in this case, unlike Pickpocket),
# steals the TARGET's item, if the Magician holder currently has none of its own and the
# target still has one to take. Source: `battle_util.c` L4399-4465
# (`ABILITYEFFECT_MOVE_END_FOES_FAINTED` switch, `ABILITY_MAGICIAN` case) — genuinely
# attacker-keyed (the ATTACKER's own ability firing after ITS hit lands), unlike every
# existing entry in `try_contact_effects`/`try_hit_reactive_effects`, which are all
# defender-keyed reactions to being hit. This is why Magician gets its own top-level
# function called directly from `BattleManager._do_damaging_hit`, rather than folded into
# either of those two dispatches. Source's `EFFECT_FLING`/`EFFECT_NATURAL_GIFT`/
# `EFFECT_FUTURE_SIGHT` exclusions (moves that already consume/reference an item
# mid-resolution) are NOT modeled — none of Fling, Natural Gift, or Future Sight exist in
# this project's move roster (confirmed via grep), a known, out-of-scope gap rather than
# a silently-dropped check.
static func try_magician(attacker: BattlePokemon, target: BattlePokemon, damage: int,
		ng_active: bool = false) -> bool:
	if damage <= 0:
		return false
	if attacker.fainted:
		return false
	if effective_ability_id(attacker, ng_active) != ABILITY_MAGICIAN:
		return false
	return _try_steal_item(attacker, target, ng_active)


# M17j: Symbiosis — when an ally (doubles-only) has its held item removed by ANY means,
# the Symbiosis holder immediately gives its OWN item to that ally, if the Symbiosis
# holder currently has an item to give and the ally is now itemless. Source:
# `TryTriggerSymbiosis`/`TrySymbiosis` (battle_util.c L9962-9990) + `BestowItem`
# (battle_util.c L9998-10011, the one-directional "giver loses it, receiver gains it"
# primitive — distinct from `_try_steal_item` above: Sticky Hold does NOT gate this side,
# since the giver is voluntarily handing its item away, not having it removed by force;
# whatever effect originally stripped the ally's item already had its own Sticky Hold
# check, if applicable, before this function is ever reached). Source's further
# exclusions (already-recorded-stolen no-re-trigger, Eject Button/Eject Pack hold
# effects, gem-boost consumption, berry-damage-reduction consumption) are NOT modeled —
# none of gems, Eject Button/Pack, or "berry reduced damage" tracking exist in this
# project, a known, out-of-scope gap rather than a silently-dropped check.
# `ally == null` (singles) is the exact value `BattleManager._get_ally` already returns
# there, matching the established zero-extra-plumbing precedent (`[M17c]`'s Hospitality,
# `[M17h]`'s Receiver).
static func try_symbiosis(mon: BattlePokemon, ally: BattlePokemon,
		ng_active: bool = false) -> bool:
	if ally == null:
		return false
	if mon.held_item != null:
		return false
	if ally.held_item == null:
		return false
	if effective_ability_id(ally, ng_active) != ABILITY_SYMBIOSIS:
		return false
	mon.held_item = ally.held_item
	ally.held_item = null
	# M17n-7: Unburden — source's `BestowItem` (battle_util.c L9998-10011) clears the
	# RECEIVER's unburdenActive (`mon`, gaining an item here) and calls
	# CheckSetUnburden on the GIVER (`ally`) — structurally unreachable in practice
	# (the giver here is confirmed to hold Symbiosis, and a Pokémon has exactly one
	# ability, so `ally` can never also hold Unburden), matching source's own
	# unconditional call regardless of reachability.
	mon.unburden_active = false
	if effective_ability_id(ally, ng_active) == ABILITY_UNBURDEN:
		ally.unburden_active = true
	return true


# M17k: Dazzling / Queenly Majesty / Armor Tail — priority-move-block check (new
# infrastructure). Source: `IsDazzlingAbility` (battle_move_resolution.c L1499-1509) —
# all three share this exact same dispatch, not three near-identical implementations.
static func _is_dazzling_family(id: int) -> bool:
	return id == ABILITY_DAZZLING or id == ABILITY_QUEENLY_MAJESTY or id == ABILITY_ARMOR_TAIL


# M17k: `CancelerPriorityBlock` (battle_move_resolution.c L1511-1548) — an
# EXECUTION-TIME gate (a "Canceler," dispatched in source's attacker-canceler chain
# BEFORE `CancelerAccuracyCheck`, confirmed from `sMoveSuccessOrderCancelers`'s ordering
# at L2434/L2447), not a selection-time block — the move is chosen normally and then
# FAILS (`BattleScript_PokemonCannotUseMove`), matching this project's existing
# `move_effect_failed`-then-`move_executed(..., 0)` pattern (e.g. Roar's
# no-switch-target fail) rather than a `move_skipped` pre-move cancellation.
# Gated on `move.priority > 0` only (source: `priority <= 0 ... return
# CANCELER_RESULT_SUCCESS`) — a priority-zero or negative move is never blocked.
# M17n-3 correction: source computes this `priority` via `GetChosenMovePriority`
# (battle_move_resolution.c L1512) — the SAME ability-boosted priority function that
# feeds turn-order sorting (`GetBattleMovePriority`, battle_main.c L4735-4775), NOT the
# move's raw data priority. This was unreachable at [M17k]'s own implementation time
# (no ability could alter priority yet) but is a real, now-reachable gap once
# Prankster/Gale Wings/Triage exist: a Prankster-boosted status move (raw priority 0,
# effective priority 1) must be blockable by Dazzling/Queenly Majesty/Armor Tail, and
# a Stall-holder's move must NOT gain a phantom block from its (nonexistent) priority
# change — Stall/Mycelium Might/Quick Draw don't alter `GetBattleMovePriority`'s
# return value at all, only the separate same-priority-bracket tiebreak, so they
# correctly don't interact with this check either. Fixed by computing the effective
# priority the same way the turn-order comparator does, via `move_priority_bonus`.
# SIDE-WIDE, not holder-only: source's loop checks every battler on the OPPOSING side of
# the attacker (skipping the attacker's own allies), so if EITHER the move's actual
# target OR that target's doubles partner holds one of these three abilities, the move
# fails — regardless of which specific combatant was chosen as the target. This project
# models that as checking `defender` and `defender_ally` (the two combatants on the
# defending side), matching the established defender/defender_ally pairing convention
# ([M17c]'s Flower Gift) rather than a generic N-battler loop.
# Does NOT affect the holder's OWN priority moves — this function is only ever consulted
# with the ATTACKER's move and the OPPOSING side's ability holder(s); an attacking
# Dazzling holder is simply never checked against its own move here.
# Source's `moveTarget == TARGET_FIELD || TARGET_OPPONENTS_FIELD` exclusion (field-wide
# moves like Trick Room/Spikes/Stealth Rock aren't "aimed at" a battler, so can't be
# blocked) is NOT modeled as a separate check — verified directly that none of this
# project's three field-targeting moves (is_trick_room/is_spikes/is_stealth_rock) has
# positive priority (Trick Room is -7; the two hazards are 0), so `move.priority > 0`
# alone already excludes all of them; a known, confirmed-non-applicable simplification,
# not an assumed one.
# All three abilities carry `breakable = TRUE` in source (src/data/abilities.h
# L1640-1645/L1677-1682/L2296-2301) — genuinely reachable here (unlike Sticky Hold's
# non-applicable case in [M17j]), since the attacker and the Dazzling-family holder are
# always DIFFERENT battlers. Threaded through via `effective_ability_id`'s existing
# `attacker` parameter so a Mold-Breaker-holding attacker correctly bypasses the block.
# [M18.5d-2] Shared gate for BOTH Attract's own move-based infliction
# (`BattleScript_EffectAttract`, battle_scripts_1.s L2220+ — a script-level
# `jumpifability BS_TARGET_SIDE, ABILITY_AROMA_VEIL` check, then `tryinfatuating` /
# `Cmd_tryinfatuating`, battle_script_commands.c L7613-7650, which ALSO re-checks
# Aroma Veil plus Oblivious) and Cute Charm's identical combination (battle_util.c
# L4130-4146: `!IsAbilityAndRecord(gBattlerAttacker, ..., ABILITY_OBLIVIOUS) &&
# !IsAbilityOnSide(gBattlerAttacker, ABILITY_AROMA_VEIL)`). Both real-source call
# sites protect "whoever's about to become infatuated" with the identical
# Oblivious-OR-Aroma-Veil-on-their-side combination — confirmed genuinely unified,
# not just similarly-shaped, so this project builds ONE shared helper rather than
# duplicating the check at each of the two call sites.
# `victim` = the Pokémon about to become infatuated (Attract's target, or Cute
#   Charm's contact attacker — the roles are reversed between the two callers,
#   but "whoever's about to be infatuated" is always this parameter).
# `victim_ally` = victim's doubles partner (null in singles) — Aroma Veil is
#   side-wide, matching `blocks_priority_move`'s own `defender_ally` shape below.
# `attacker`/`attacker_move` = Mold-Breaker/Mycelium-Might bypass context, per
#   `effective_ability_id`'s own established shape — both Oblivious and Aroma Veil
#   are `.breakable = TRUE` in source. Left null for Cute Charm's call (not a move,
#   so no Mold-Breaker bypass applies — matches this file's existing precedent of
#   Cute Charm's own dispatch having no `attacker` param either, since Cute Charm
#   itself has no `.breakable` flag to bypass in the first place).
# Returns "" if not blocked, else "oblivious" or "aroma_veil" (a distinguishable
# tag, mirroring `cud_chew_check`'s own "" / "arm" / "fire" shape) so callers can
# emit a precise `ability_triggered` tag rather than a generic one.
static func attract_block_reason(
		victim: BattlePokemon, victim_ally: BattlePokemon, ng_active: bool = false,
		attacker: BattlePokemon = null, attacker_move: MoveData = null) -> String:
	if effective_ability_id(victim, ng_active, attacker, attacker_move) == ABILITY_OBLIVIOUS:
		return "oblivious"
	if effective_ability_id(victim, ng_active, attacker, attacker_move) == ABILITY_AROMA_VEIL:
		return "aroma_veil"
	if victim_ally != null and not victim_ally.fainted \
			and effective_ability_id(victim_ally, ng_active, attacker, attacker_move) == ABILITY_AROMA_VEIL:
		return "aroma_veil"
	return ""


static func blocks_priority_move(defender: BattlePokemon, defender_ally: BattlePokemon,
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false) -> bool:
	# M17n-3: effective priority (raw + ability bonus), not just move.priority — see
	# the doc comment above for why this must match GetChosenMovePriority exactly.
	var effective_priority: int = move.priority + move_priority_bonus(attacker, move, ng_active)
	if effective_priority <= 0:
		return false
	if _is_dazzling_family(effective_ability_id(defender, ng_active, attacker)):
		return true
	if defender_ally != null and not defender_ally.fainted \
			and _is_dazzling_family(effective_ability_id(defender_ally, ng_active, attacker)):
		return true
	return false


# M17n-10: Guard Dog's SECOND, independent half — blocks a forced-switch-out effect
# entirely (Roar/Whirlwind in this project's roster). Source: EFFECT_HIT_SWITCH_TARGET
# handling (battle_move_resolution.c L3517-3524) — `if (cv->abilities[cv->battlerDef]
# == ABILITY_GUARD_DOG) break;` unconditionally cancels the forced switch before it's
# ever applied, no stat-stage interaction at all (a genuinely separate mechanic from
# the Intimidate-reversal half in `try_switch_in`). Source's neighboring Suction Cups
# case is a different, unimplemented ability, out of this tier's scope. Source's other
# reference (battle_move_resolution.c L3748, Red Card's own forced-switch) — GAP
# CLOSED in [M18n]: Red Card reuses this exact function, called with the ATTACKER
# (the one being forced to switch) in the `defender` slot and the item HOLDER (who
# caused the force) in the `attacker` slot — the same generic shape, roles swapped
# from Roar's own call. Eject Button does NOT call this function at all — confirmed
# absent from its own source function; Guard Dog only blocks being forced out BY AN
# OPPONENT's effect, not a self-triggered switch. `.breakable = TRUE`, so a
# Mold-Breaker attacker's Roar/Whirlwind (or Red Card victim) still forces the switch.
static func blocks_forced_switch(defender: BattlePokemon, attacker: BattlePokemon,
		ng_active: bool = false) -> bool:
	return effective_ability_id(defender, ng_active, attacker) == ABILITY_GUARD_DOG


# M17g: the single suppression-aware chokepoint every ability-consuming function in
# this file (and StatusManager/DamageCalculator) should read an ability THROUGH,
# rather than reading `mon.ability.ability_id` raw. Mirrors source's
# `GetBattlerAbilityInternal` (battle_util.c L4844-4878) exactly:
#   1. Neutralizing Gas suppresses every OTHER live battler's ability field-wide
#      (except one flagged `AbilityData.cant_be_suppressed`, and except its own holder).
#   2. Mold Breaker (attacker-scoped) additionally suppresses `mon`'s ability if
#      `attacker` is a DIFFERENT battler currently using a move, `attacker`'s OWN
#      effective ability (recursion, without an attacker — an ability never
#      suppresses its own wielder) is Mold Breaker, and `mon`'s ability is flagged
#      `AbilityData.breakable`. (Turboblaze/Teravolt share the exact same source
#      bypass array per docs/m17_recon.md L626-627, but both are excluded from this
#      project's scope per Section 13 — see the Step 0 comment above ABILITY_MOLD_BREAKER.)
# This recursive self-check means an already-NG-suppressed Mold Breaker holder can't
# bypass anything either — a real, source-faithful double-suppression interaction,
# not a special case bolted on afterward.
# ng_active: whether ANY live battler's CURRENT ability is Neutralizing Gas — computed
#   once per call site by BattleManager._is_neutralizing_gas_active() (this project has
#   no Skill Swap/Gastro Acid/Entrainment yet, so "current ability" is a safe stand-in
#   for source's separate activation-flag tracking; see decisions.md [M17g]).
# attacker: the Pokémon currently resolving a move against `mon`, or null when there is
#   no such context (switch-in triggers, end-of-turn ticks, ability-triggered reactions
#   like Intimidate/Moxie/Anger Point — none of these are "a move," so Mold Breaker
#   correctly never applies there, matching source's moldBreakerActive being scoped
#   strictly to the window of processing one specific move).
# M17n-3: new trailing `attacker_move` param — Mycelium Might acts as a
# Mold-Breaker-type ability (source: `IsMoldBreakerTypeAbility`, battle_util.c
# L4805-4818) toward an opposing battler ONLY while the Mycelium Might holder's
# CURRENT move being processed is status-category — narrower than Mold Breaker's
# unconditional bypass, so it needs the move in scope rather than just the attacker.
# Default null preserves every pre-existing call site's behavior unchanged (Mycelium
# Might simply never bypasses anything when no move context is threaded through).
static func effective_ability_id(
		mon: BattlePokemon, ng_active: bool = false, attacker: BattlePokemon = null,
		attacker_move: MoveData = null) -> int:
	if mon.ability == null:
		return ABILITY_NONE
	var id: int = mon.ability.ability_id
	if ng_active and id != ABILITY_NEUTRALIZING_GAS and not mon.ability.cant_be_suppressed:
		return ABILITY_NONE
	if attacker != null and attacker != mon and mon.ability.breakable:
		var attacker_id: int = effective_ability_id(attacker, ng_active)
		if attacker_id == ABILITY_MOLD_BREAKER:
			return ABILITY_NONE
		if attacker_id == ABILITY_MYCELIUM_MIGHT and attacker_move != null \
				and attacker_move.category == 2:
			return ABILITY_NONE
	return id


# M17g: whether Neutralizing Gas is currently active anywhere on the field.
# Source: battle_util.c :: IsNeutralizingGasOnField (L4794-4803): any live battler
# with the neutralizingGas volatile set (and not itself Gastro-Acid'd, which this
# project doesn't model — no Gastro Acid move exists here, so that half is moot).
# Simplified to a direct ability-identity check (see effective_ability_id's doc
# comment for why that's valid at this project's current scope).
# combatants: ALL live battlers on the field (both sides) — BattleManager passes its
#   full `_combatants` array filtered to non-fainted, mirroring how `_get_live_opponents`
#   already filters one side.
static func is_neutralizing_gas_active(combatants: Array) -> bool:
	for mon: BattlePokemon in combatants:
		if mon.fainted:
			continue
		if mon.ability != null and mon.ability.ability_id == ABILITY_NEUTRALIZING_GAS:
			return true
	return false


# M17n-7: whether Unnerve (or Unnerve-shaped As One, not in this project's scope) is
# active on any of `opponents` — field-wide for as long as the holder is present, not
# per-hit/per-turn. Source: `IsUnnerveBlocked` (battle_util.c L333-343) →
# `IsUnnerveAbilityOnOpposingSide` (L346-363), which loops every OTHER live battler
# (not just the direct attacker) checking for Unnerve. `opponents` is resolved by the
# caller: `BattleManager._get_live_opponents(mon)` in full-battle contexts, or a plain
# `[attacker, ally]` array in `DamageCalculator.calculate` (which has no access to the
# full combatant list, but already receives exactly the attacker's side as params —
# the same side `IsUnnerveAbilityOnOpposingSide` would iterate for a resist-berry
# check). Entries may be null (singles has no ally) or fainted; both are skipped.
static func is_unnerve_active(opponents: Array, ng_active: bool = false) -> bool:
	for opp: BattlePokemon in opponents:
		if opp == null or opp.fainted:
			continue
		if effective_ability_id(opp, ng_active) == ABILITY_UNNERVE:
			return true
	return false


# M17n-7: Gluttony — for a berry whose NORMAL eat-early HP fraction is 4 or
# stricter (i.e. 25% HP or lower — stat-raise berries like Liechi/Salac, confuse-
# heal berries like Figy/Wiki, Micle Berry), the holder eats it at 50% HP instead.
# Source: `HasEnoughHpToEatBerry` (battle_util.c L5460-5474): the primary check is
# `hp <= maxHP/hpFraction`; Gluttony's own OR-branch only fires when that primary
# check has ALREADY failed, is gated on `hpFraction <= 4`, and re-checks
# `hp <= maxHP/2` — i.e. it WIDENS a stricter-than-50% threshold up to 50%, it never
# narrows one that's already 50% or looser.
# Sitrus Berry's own fraction is hardcoded to 2 (50%) in source regardless of this
# ability (`ItemHealHp` always calls `HasEnoughHpToEatBerry(battler, ability, 2,
# itemId)` — the literal `2`, not a per-item or per-ability value) — already at
# the exact fraction Gluttony would move a stricter berry to, so passing Sitrus's
# fraction through this function is a confirmed no-op (2 in, 2 out). Resist Berry
# has no HP-threshold check anywhere in source (`GetDefenderItemsModifier` gates
# purely on move-type-match and effectiveness) — moot, never calls this function at
# all. No stat-raise/confuse-heal/Micle-style berry exists anywhere in this
# project's implemented item roster (confirmed via grep of `ItemManager`'s
# `HOLD_EFFECT_*` constants) — Gluttony genuinely has no observable effect on any
# currently-implemented item. Wired in generically here (not left unimplemented)
# so it composes correctly the moment such a berry is added, matching the
# "recorded but currently unreachable" precedent already established for Sticky
# Hold ([M17j]).
static func gluttony_adjusted_hp_fraction(
		mon: BattlePokemon, base_fraction: int, ng_active: bool = false) -> int:
	if base_fraction <= 4 and effective_ability_id(mon, ng_active) == ABILITY_GLUTTONY:
		return 2
	return base_fraction


# M17n-2: whether Air Lock/Cloud Nine is currently active anywhere on the field.
# Source: HasWeatherEffect (battle_util.c L9873-9889) — any live battler holding either
# ability negates ALL weather effects for as long as it's present. Unlike
# `is_neutralizing_gas_active` (which reads `mon.ability.ability_id` raw, since NG's
# own presence-check can't be gated by itself recursively), THIS check uses
# `effective_ability_id` per battler — Air Lock/Cloud Nine have no `cantBeSuppressed`
# flag in source, so Neutralizing Gas correctly suppresses them if both are present.
# Neither is `breakable` in source either — a field-wide passive with no "attacker"
# concept, so no Mold-Breaker consideration applies (confirmed, not assumed).
#
# Source's `GetWeather()` (battle_util.c L9274-9279) is the ONE accessor every
# weather-conditional check in source reads through, and it already returns
# `WEATHER_NONE` whenever `HasWeatherEffect()` is false — meaning Air Lock/Cloud Nine's
# negation is naturally comprehensive in source (damage modifiers, end-of-turn chip,
# Sand Veil/Snow Cloak, Swift Swim/Chlorophyll/Sand Rush, even Flower Gift/Solar
# Power/Leaf Guard from prior tiers) via ONE substitution point, not many. This project
# has no single global weather accessor (every function receives `weather` as a plain
# parameter instead), so `BattleManager._effective_weather()` reproduces the same
# substitution at each of its ABILITY-facing call sites — see that method's own doc
# comment for exactly which pre-existing abilities this retroactively covers "for
# free," and which pure MOVE-mechanic weather interactions (Solar Beam's sun
# charge-skip, Growth's sun power-doubling, Aurora Veil's hail requirement) are
# deliberately left out of this tier's scope, matching the recon's own "damage
# modifiers and end-of-turn chip/heal" framing for these two abilities specifically.
static func is_weather_negated(combatants: Array, ng_active: bool = false) -> bool:
	for mon: BattlePokemon in combatants:
		if mon.fainted:
			continue
		var id: int = effective_ability_id(mon, ng_active)
		if id == ABILITY_AIR_LOCK or id == ABILITY_CLOUD_NINE:
			return true
	return false


# M17n-3: additional priority for the holder's own chosen move, mirroring
# `GetBattleMovePriority`'s ability branch (battle_main.c L4735-4775). Source's
# if/else-if chain (quash → Gale Wings → Prankster → Grassy Glide → Triage) is
# structurally an else-if only because a Pokémon can only ever have ONE ability at a
# time — Gale Wings/Prankster/Triage can never co-occur on the same holder, so the
# chain order doesn't change behavior here; Grassy Glide (a move-effect flag, not an
# ability) and quash (a volatile this project doesn't model) are both outside this
# tier's scope, confirmed non-applicable rather than silently dropped.
# Called with NO `attacker` context: this is the holder judging its OWN chosen move,
# never a "defender's ability" an opposing Mold-Breaker attacker could bypass (same
# reasoning `effective_speed`'s Slush-Rush-family calls already established).
static func move_priority_bonus(
		mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	if mon == null or move == null:
		return 0
	var id: int = effective_ability_id(mon, ng_active)
	# Gale Wings: +1 for Flying-type moves. B_GALE_WINGS = GEN_LATEST (>= GEN_7) means
	# the full-HP gate always applies at this project's config — source: battle_main.c
	# L4752-4757, `GetConfig(B_GALE_WINGS) < GEN_7 || IsBattlerAtMaxHp(battler)`.
	if id == ABILITY_GALE_WINGS and move.type == TypeChart.TYPE_FLYING \
			and mon.current_hp == mon.max_hp:
		return 1
	# Prankster: +1 for status-category moves (category == 2, per this project's
	# 0=Physical/1=Special/2=Status convention). Source: L4758-4762.
	if id == ABILITY_PRANKSTER and move.category == 2:
		return 1
	# Triage: +3 for moves carrying the `healing_move` data flag — a genuinely
	# separate per-move flag from `is_restore_hp`, confirmed via source
	# (`gMovesInfo[...].healingMove`) rather than assumed identical; only
	# Recover/Slack Off/Heal Order carry it in this project's current roster. Source:
	# L4769-4772.
	if id == ABILITY_TRIAGE and move.healing_move:
		return 3
	return 0


# M17n-3 follow-up: a status move whose priority was elevated specifically by
# Prankster fails against a Dark-type target (Gen 7+ only). Source: `BlocksPrankster`
# (battle_util.c L9234-9252), dispatched from `CanTargetBlockPranksterMove` →
# `CanMoveBeBlockedByTarget`, an execution-time canceler (battle_move_resolution.c
# L2022) gated on `gProtectStructs[attacker].pranksterElevated` — a flag set
# (battle_main.c L4758-4762) EXACTLY when the move is status-category AND the
# attacker's ability is Prankster, i.e. precisely `move_priority_bonus`'s own
# Prankster branch condition. No separate stored flag is needed here — the same
# (ability, move.category) check IS the condition, derived fresh rather than cached,
# consistent with every other ability query in this file. `B_PRANKSTER_DARK_TYPES =
# GEN_LATEST` (include/config/battle.h L46) means the gate always applies at this
# project's config, so it isn't threaded through as a separate parameter.
# NOT Mold-Breaker-bypassable: `BlocksPrankster` gates on the DEFENDER's TYPE, not an
# ability — confirmed via source that no `IsMoldBreakerTypeAbility` call appears
# anywhere in `BlocksPrankster`, so an attacking Mold-Breaker-holding Prankster user
# (a contradiction in terms — a Pokémon can only have one ability — but relevant if
# Mold Breaker breaks through as the ATTACKER via some future move-based bypass) has
# no bearing on typing at all. Called with no `attacker`-bypass context on
# `effective_ability_id`, same reasoning as `move_priority_bonus` above (this is the
# attacker's own ability being read, not a defender's ability being bypassed).
static func blocks_prankster_move(
		attacker: BattlePokemon, defender: BattlePokemon, move: MoveData,
		ng_active: bool = false) -> bool:
	if move == null or move.category != 2:
		return false
	if effective_ability_id(attacker, ng_active) != ABILITY_PRANKSTER:
		return false
	return TypeChart.TYPE_DARK in defender.species.types


# M17n-3: Quick Draw — 30% chance to act first within a tied priority bracket, gated
# on the chosen move being NON-status (source: battle_main.c L5187,
# `!IsBattleMoveStatus(gChosenMoveByBattler[battler1]) && quickDrawRandom[battler1]`;
# the roll itself is L4987, `RandomPercentage(RNG_QUICK_DRAW, 30)`). Must be evaluated
# EXACTLY ONCE per battler per turn — not re-rolled per pairwise comparison — so
# `BattleManager._phase_priority_resolution` precomputes this into a Dictionary before
# the sort, the same way the existing per-turn `tiebreak` dict is built.
# No `attacker` context, same reasoning as `move_priority_bonus` above.
static func quick_draw_activates(
		mon: BattlePokemon, move: MoveData, ng_active: bool = false,
		forced_roll: Variant = null) -> bool:
	if mon == null or move == null or move.category == 2:
		return false
	if effective_ability_id(mon, ng_active) != ABILITY_QUICK_DRAW:
		return false
	if forced_roll != null:
		return bool(forced_roll)
	return randi() % 100 < 30


# M17n-3: Stall / Mycelium Might — always act LAST within a tied priority bracket.
# Source: battle_main.c :: GetWhichBattlerFasterArgs (L4788-4789):
#   `battler1HasStallingAbility = abilities[battlerAtk] == ABILITY_STALL ||
#    gProtectStructs[battlerAtk].myceliumMight`.
# Stall applies UNCONDITIONALLY every turn. Mycelium Might's slow-effect is narrower —
# source sets the `myceliumMight` ProtectStruct flag only when
# `IsBattleMoveStatus(gChosenMoveByBattler[battler]) && ability == ABILITY_MYCELIUM_MIGHT`
# (battle_main.c L4407-4408) — confirmed via source rather than assumed identical to
# Stall's unconditional shape. Same per-turn-precompute requirement as Quick Draw
# above (the move used here is the battler's own chosen move for the turn, stable
# across the whole sort).
static func has_slow_turn_order_effect(
		mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> bool:
	if mon == null:
		return false
	var id: int = effective_ability_id(mon, ng_active)
	if id == ABILITY_STALL:
		return true
	if id == ABILITY_MYCELIUM_MIGHT and move != null and move.category == 2:
		return true
	return false


# ── Tier 1: Passive stat modifiers ──────────────────────────────────────────

# Attack multiplier from the attacker's ability.
# Applied to the physical Attack stat before damage formula.
# Source: battle_util.c :: GetAttackStatModifier — attacker abilities switch (L6800–6808):
#   ABILITY_HUGE_POWER / ABILITY_PURE_POWER: IsBattleMovePhysical → modifier ×2.0
#
# M17a additions, same function (GetAttackStatModifier), same attacker-abilities switch:
#   ABILITY_OVERGROW/BLAZE/TORRENT/SWARM (L6821-6836): matching move type AND
#     hp <= maxHP/3 → ×1.5. Applies to either category (no IsBattleMovePhysical gate).
#   ABILITY_HUSTLE (L6860-6862): IsBattleMovePhysical → ×1.5.
#   ABILITY_GUTS (L6868-6870): status1 & STATUS1_ANY (any status) AND IsBattleMovePhysical → ×1.5.
#   ABILITY_ROCKY_PAYLOAD (L6891-6893): moveType == TYPE_ROCK → ×1.5 (no other condition).
#   ABILITY_DEFEATIST (L6812-6813): hp <= maxHP/2 → ×0.5 (no category gate).
#
# M17c addition, same function:
#   ABILITY_FLOWER_GIFT (L6855-6858): sun active AND IsBattleMovePhysical → ×1.5. Source
#     gates this on `species == SPECIES_CHERRIM_SUNSHINE` (a battle-triggered form-change
#     this project doesn't model — see docs/m17_recon.md Section 8.4/Bucket D). Dropping
#     the species-form gate and keeping the generic weather-conditional boost matches the
#     precedent Rob already set for the Primal weather trio (docs/decisions.md [M17c]).
# weather: int — WEATHER_* constant (DamageCalculator), default WEATHER_NONE, needed only
#   for Flower Gift's sun check; every existing caller passes it explicitly now.
# Returns a UQ4.12 integer: 4096 = 1.0×, 8192 = 2.0×.
# M17n-5 addition: new `defender` param, needed only for Stakeout's "did the TARGET
# switch in this turn" check (source: battle_util.c L6864-6866, GetAttackStatModifier)
# — a genuinely different battler than `attacker`, unlike every other case in this
# function, which all read only the attacker's own state. Default null preserves every
# pre-existing call site (Stakeout simply never fires without it).
static func attack_modifier_uq412(
		attacker: BattlePokemon, move: MoveData,
		weather: int = DamageCalculator.WEATHER_NONE, ng_active: bool = false,
		defender: BattlePokemon = null) -> int:
	var id: int = effective_ability_id(attacker, ng_active)
	if id == ABILITY_NONE:
		return 4096  # UQ_4_12(1.0)
	if (id == ABILITY_HUGE_POWER or id == ABILITY_PURE_POWER) and move.category == 0:
		return 8192  # UQ_4_12(2.0) — doubles physical Attack

	if id == ABILITY_DEFEATIST and attacker.current_hp <= attacker.max_hp / 2:
		return 2048  # UQ_4_12(0.5)

	var third_hp: bool = attacker.current_hp <= attacker.max_hp / 3
	if id == ABILITY_OVERGROW and move.type == TypeChart.TYPE_GRASS and third_hp:
		return 6144  # UQ_4_12(1.5)
	if id == ABILITY_BLAZE and move.type == TypeChart.TYPE_FIRE and third_hp:
		return 6144
	if id == ABILITY_TORRENT and move.type == TypeChart.TYPE_WATER and third_hp:
		return 6144
	if id == ABILITY_SWARM and move.type == TypeChart.TYPE_BUG and third_hp:
		return 6144

	if id == ABILITY_HUSTLE and move.category == 0:
		return 6144
	if id == ABILITY_GUTS and attacker.status != BattlePokemon.STATUS_NONE and move.category == 0:
		return 6144
	if id == ABILITY_ROCKY_PAYLOAD and move.type == TypeChart.TYPE_ROCK:
		return 6144

	if id == ABILITY_FLOWER_GIFT and weather == DamageCalculator.WEATHER_SUN and move.category == 0:
		return 6144

	# M17d: Solar Power — damage-pipeline half (the other half, end-of-turn self-damage,
	# is in StatusManager.end_of_turn_damage's caller — see [M17d] decisions.md).
	# Source: battle_util.c :: GetAttackStatModifier, ABILITY_SOLAR_POWER case (L6809-6811):
	#   IsBattleMoveSpecial(move) AND sun active → ×1.5 (special moves only, unlike
	#   Flower Gift's physical-only gate right above).
	if id == ABILITY_SOLAR_POWER and weather == DamageCalculator.WEATHER_SUN and move.category == 1:
		return 6144

	# M17m: Flash Fire's delayed payoff — a Fire-type move from the SAME holder that
	# previously absorbed a Fire-type hit (see absorbs_move_type's "flag" case) gets a
	# ×1.5 power boost. Source: battle_util.c L6817-6819, same attacker-side base-power
	# switch as Overgrow/Blaze/Torrent/Swarm above — a raw persistent-flag read, no
	# re-check of the stat/HP kind this ability's absorb dispatch otherwise has, matching
	# source exactly (the switch is already keyed on the effective/suppression-aware
	# ability id via `id`, so a suppressed Flash Fire holder's flag is inert this turn
	# even though the flag itself isn't cleared by suppression).
	if id == ABILITY_FLASH_FIRE and move.type == TypeChart.TYPE_FIRE and attacker.flash_fire_active:
		return 6144  # UQ_4_12(1.5)

	# M17n-5: Stakeout — ×2.0 vs. a target that switched in THIS turn. Source:
	# battle_util.c L6864-6866, `BattlerJustSwitchedIn(battlerDef)` (isFirstTurn == 2,
	# specifically mid-battle switch-ins — NOT the initial simultaneous battle-start
	# send-out, which is a different isFirstTurn value). This project's
	# `switched_in_this_turn` is confirmed to match that exact scope: it's set ONLY at
	# the three mid-battle switch-in call sites (_do_voluntary_switch/_do_forced_switch_in/
	# _do_switch_in), never during _phase_battle_start, and reset to false at the start
	# of every _phase_priority_resolution — verified via direct grep, not assumed. No
	# category gate in source (applies to both physical and special moves).
	if id == ABILITY_STAKEOUT and defender != null and defender.switched_in_this_turn:
		return 8192  # UQ_4_12(2.0)

	# M17n-5: Slow Start — Atk ×0.5 for physical moves only, while the 5-turn timer is
	# still running. Source: battle_util.c L6805-6807 (IsBattleMovePhysical gate; Speed's
	# own unconditional half lives in StatusManager.effective_speed instead).
	if id == ABILITY_SLOW_START and attacker.slow_start_timer > 0 and move.category == 0:
		return 2048  # UQ_4_12(0.5)

	return 4096


# Incoming damage modifier from the defender's ability.
# Applied after type effectiveness in the damage pipeline.
# Source: battle_util.c :: GetDefenseStatModifier — target abilities switch (L6933–6941):
#   ABILITY_THICK_FAT: (TYPE_FIRE || TYPE_ICE) → modifier ×0.5
#
# M17a additions fold in abilities from THREE distinct source functions that this
# project collapses into one post-type-effectiveness call, matching the Thick Fat
# precedent (Thick Fat is itself really a pre-formula atkStat halving in source, not
# a post-effectiveness final-damage multiplier — this project already simplified that,
# so the same simplification is applied here rather than adding new pipeline stages):
#   GetDefenseStatModifier (usesDefStat-gated, i.e. physical only — L7089-7104):
#     ABILITY_MARVEL_SCALE: statused AND physical → ×1.5 on the DEFENSE STAT. Since
#       this project applies a single post-effectiveness damage multiplier instead of
#       a pre-formula stat modifier, the equivalent damage-taken multiplier is the
#       RECIPROCAL of the stat multiplier (damage ∝ 1/defense): 1/1.5 ≈ 0.667 (2731),
#       same reciprocal relationship Fur Coat already established below (2.0 stat → 0.5 damage).
#     ABILITY_FUR_COAT: physical → ×0.5 (source doubles the def STAT; halving final
#       damage is the equivalent outcome for a single multiplicative factor)
#   GetDefenderAbilitiesModifier (post-type-eff — L7407-7444):
#     ABILITY_MULTISCALE: defender at max HP → ×0.5
#     ABILITY_FILTER / ABILITY_SOLID_ROCK: effectiveness >= 2.0 (super effective) → ×0.75
#     ABILITY_ICE_SCALES: move is Special → ×0.5
#   CalcMoveBasePowerAfterModifiers, "target's abilities" block (L6607-6613):
#     ABILITY_HEATPROOF: moveType == TYPE_FIRE → ×0.5 (source applies pre-formula to
#       base power; folded in here for the same reason as Thick Fat/Fur Coat above)
#
# M17c additions, same function:
#   ABILITY_DRY_SKIN (battle_util.c "target's abilities" block, L6616-6619): moveType ==
#     TYPE_FIRE → ×1.25 (damage taken INCREASES, unlike every other entry here). Dry Skin's
#     other two parts (Water-move absorb+heal, end-of-turn rain-heal/sun-damage) are handled
#     elsewhere — see try_end_of_turn and docs/decisions.md [M17c] for why the Water-absorb
#     half is deferred (needs Bucket-E immunity+heal infra this project doesn't have yet,
#     shared gap with the still-unimplemented Volt Absorb/Water Absorb).
#   ABILITY_FLOWER_GIFT (L7114-7117, self; L7145-7148, ally): sun active AND the move is
#     Special (usesDefStat is false for Sp. Def) → the SAME reciprocal-of-1.5 treatment as
#     Marvel Scale (2731 ≈ 0.667×). Checked on the defender OR the defender's doubles ally,
#     matching source's separate "ally's abilities" switch block.
#
# effectiveness: the float effectiveness value already computed by DamageCalculator
#   (0.0/0.25/0.5/1.0/2.0/4.0) — needed for Filter/Solid Rock's >=2.0 gate.
# weather: WEATHER_* constant — needed for Flower Gift's sun gate.
# ally: defender's doubles partner (null in singles or if fainted) — needed for Flower
#   Gift's ally-wide Sp. Def share.
# Returns a UQ4.12 integer: 4096 = 1.0×, 2048 = 0.5×, 2731 ≈ 0.667×, 3072 = 0.75×, 5120 = 1.25×.
static func defense_damage_modifier_uq412(
		defender: BattlePokemon, move: MoveData, effectiveness: float = 1.0,
		weather: int = DamageCalculator.WEATHER_NONE, ally: BattlePokemon = null,
		ng_active: bool = false, attacker: BattlePokemon = null) -> int:
	var flower_gift_holder: bool = \
			effective_ability_id(defender, ng_active, attacker) == ABILITY_FLOWER_GIFT
	var ally_flower_gift: bool = ally != null and not ally.fainted \
			and effective_ability_id(ally, ng_active, attacker) == ABILITY_FLOWER_GIFT
	if (flower_gift_holder or ally_flower_gift) \
			and weather == DamageCalculator.WEATHER_SUN and move.category == 1:
		return 2731  # UQ_4_12(1/1.5) ≈ 0.667 — reciprocal of the ×1.5 Sp. Def boost
	var id: int = effective_ability_id(defender, ng_active, attacker)
	if id == ABILITY_NONE:
		return 4096
	if id == ABILITY_DRY_SKIN and move.type == TypeChart.TYPE_FIRE:
		return 5120  # UQ_4_12(1.25) — damage taken INCREASES
	if id == ABILITY_THICK_FAT:
		if move.type == TypeChart.TYPE_FIRE or move.type == TypeChart.TYPE_ICE:
			return 2048  # UQ_4_12(0.5) — halves attacker's effective Attack

	if id == ABILITY_MARVEL_SCALE and defender.status != BattlePokemon.STATUS_NONE \
			and move.category == 0:
		return 2731  # UQ_4_12(1/1.5) ≈ 0.667 — reciprocal of the ×1.5 Defense stat boost
	if id == ABILITY_FUR_COAT and move.category == 0:
		return 2048  # UQ_4_12(0.5)
	if id == ABILITY_MULTISCALE and defender.current_hp == defender.max_hp:
		return 2048
	if (id == ABILITY_FILTER or id == ABILITY_SOLID_ROCK) and effectiveness >= 2.0:
		return 3072  # UQ_4_12(0.75)
	if id == ABILITY_ICE_SCALES and move.category == 1:
		return 2048
	if id == ABILITY_HEATPROOF and move.type == TypeChart.TYPE_FIRE:
		return 2048

	# M17b: Purifying Salt is two-part (status immunity, handled in
	# StatusManager.try_apply_status, + this Ghost-type damage-taken halving). The
	# damage half is the same shape as Heatproof (a target-ability post-type-
	# effectiveness multiplier), just Ghost-typed instead of Fire-typed, so it's kept
	# here rather than split into a separate M17a-era function.
	# Source: battle_util.c :: CalcMoveBasePowerAfterModifiers, "target's abilities"
	#   block (L6941-6947): moveType == TYPE_GHOST → ×0.5.
	if id == ABILITY_PURIFYING_SALT and move.type == TypeChart.TYPE_GHOST:
		return 2048

	# M17n-5: Fluffy — TWO MUTUALLY EXCLUSIVE branches (confirmed from source, not two
	# independently-stacking multipliers): a non-contact Fire-type move → ×2.0; a
	# contact NON-Fire-type move → ×0.5. Source: battle_util.c L7424-7434
	# (GetDefenderAbilitiesModifier): `if (moveType==FIRE && !isContact) modifier=2.0;
	# if (moveType!=FIRE && isContact) modifier=0.5;` — neither branch's condition can
	# ever be true simultaneously with the other, so a CONTACT FIRE move (e.g. Flare
	# Blitz) triggers NEITHER branch and nets ×1.0 (unaffected) — NOT both 0.5 and 2.0
	# stacking to cancel out. `move_makes_contact` (not raw `move.makes_contact`)
	# is used so an attacking Long-Reach holder's move correctly reads as non-contact
	# here too. `breakable = TRUE` in source — genuinely reachable (attacker and
	# Fluffy holder are always different battlers).
	if id == ABILITY_FLUFFY:
		var contact: bool = move_makes_contact(attacker, move, ng_active)
		if move.type == TypeChart.TYPE_FIRE and not contact:
			return 8192  # UQ_4_12(2.0)
		if move.type != TypeChart.TYPE_FIRE and contact:
			return 2048  # UQ_4_12(0.5)

	# M17n-5: Punk Rock — damage TAKEN from a sound move ×0.5 (the OTHER half — the
	# holder's OWN sound-move power ×1.3 — lives in move_power_modifier_uq412, a
	# genuinely different function/direction). Source: battle_util.c L7436-7441
	# (same GetDefenderAbilitiesModifier as Fluffy above). No double-counting risk if
	# a Punk Rock holder's sound move hits another Punk Rock holder: this defender-side
	# check reads only `id` (the DEFENDER's ability), completely independent of
	# move_power_modifier_uq412's separate read of the ATTACKER's ability — confirmed
	# from source rather than assumed non-issue (each side's own switch-case only ever
	# consults that side's own ability field).
	if id == ABILITY_PUNK_ROCK and move.sound_move:
		return 2048

	return 4096


# M17n-5: Long Reach — the holder's own moves NEVER count as contact, unconditionally
# overriding `move.makes_contact`. Source: IsMoveMakingContact (battle_util.c
# L5728-5746) — the SINGLE canonical function every "does this hit count as contact"
# check in source routes through (Fluffy's own check above calls this exact function
# too, confirmed from source) — mirrored here as one shared helper rather than
# touching each individual contact-triggered ability's own dispatch (try_contact_effects'
# top gate, try_wandering_spirit_swap, try_mummy_overwrite all reuse this). `attacker
# == null` falls back to the raw flag (no Long-Reach context available), matching
# every other ability query in this file's null-safety convention.
static func move_makes_contact(
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false) -> bool:
	if not move.makes_contact:
		return false
	if attacker == null:
		return true
	# M18p: Punching Glove strips the contact flag from the HOLDER's OWN punching
	# moves. Source: IsMoveMakingContact (battle_util.c L5735-5738) checks this
	# INSIDE the same function as Long Reach's exemption just below — the SAME
	# level, not the narrower CanBattlerAvoidContactEffects wrapper Protective
	# Pads occupies (see move_triggers_contact_retaliation below) — so this
	# universally affects every consumer of this function, Tough Claws' power
	# boost included, exactly like Long Reach does.
	if move.punching_move and ItemManager.holds_punching_glove(attacker, ng_active):
		return false
	return effective_ability_id(attacker, ng_active) != ABILITY_LONG_REACH


# M18p: Protective Pads' actual gate. Source: CanBattlerAvoidContactEffects
# (battle_util.c L5717-5726) wraps IsMoveMakingContact ONE LEVEL UP — checked
# only by genuine contact-RETALIATION consumers (Rough Skin/Iron Barbs/Static/
# Flame Body/Poison Point/Effect Spore/Mummy/Wandering Spirit/Gooey/Tangling
# Hair/Pickpocket via try_contact_effects below; Aftermath via
# faint_retaliation_damage; Rocky Helmet/Sticky Barb-transfer in ItemManager),
# never by move_makes_contact's other consumers (Tough Claws' power boost,
# Poison Touch's own inline check, Fluffy if ever built) — those call
# IsMoveMakingContact directly in source, confirmed via grep of every raw call
# site, so Protective Pads must NOT be folded into move_makes_contact itself.
static func move_triggers_contact_retaliation(
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false) -> bool:
	if not move_makes_contact(attacker, move, ng_active):
		return false
	return not ItemManager.holds_protective_pads(attacker, ng_active)


# M17n-4: Protean/Libero — the user's own type changes to match the move it's ABOUT to
# use, once per switch-in stint. Source: CancelerProtean/ProteanTryChangeType
# (battle_move_resolution.c L1647-1662, battle_util.c L919-932): fires for either
# ability identically (confirmed genuinely the same function/condition, not just
# flavor-text twins — Libero has no source logic of its own at all); gated on
# `!volatiles.usedProteanLibero` (see BattlePokemon.used_protean_libero's doc comment
# for the once-per-battle-comment-vs-once-per-stint-behavior distinction), not already
# exactly that type (checked against BOTH of this project's two type slots, mirroring
# source's `types[0] != moveType || types[1] != moveType` — skips only when a mono-typed
# mon already matches), not Struggle, not a bounced move (this project has no Magic
# Bounce/Dancer redirect chain — moot), not Tera-active (this project has no
# Terastallization — moot). Returns the new type, or TYPE_NONE if it shouldn't fire;
# BattleManager performs the actual `_set_mon_type` mutation, sets
# `used_protean_libero`, and emits signals — same division of responsibility as every
# other type-mutation call site.
static func protean_new_type(
		mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	if mon == null or move == null:
		return TypeChart.TYPE_NONE
	var id: int = effective_ability_id(mon, ng_active)
	if id != ABILITY_PROTEAN and id != ABILITY_LIBERO:
		return TypeChart.TYPE_NONE
	if mon.used_protean_libero:
		return TypeChart.TYPE_NONE
	if move.is_struggle:
		return TypeChart.TYPE_NONE
	# Same "already this type" idiom as Conversion (BattleManager._phase_move_execution's
	# is_conversion branch): membership check against species.types, not a literal
	# both-slots-equal comparison — consistent with this project's established
	# single-type-mutation convention rather than a stricter re-derivation from source's
	# own dual-slot representation.
	if move.type in mon.species.types:
		return TypeChart.TYPE_NONE
	return move.type


# M17n-10: Forecast — Castform's type reflects the active weather. Source: Castform's
# own `formChangeTable` (form_change_tables.h): sun→Fire, rain→Water, hail/snow→Ice,
# anything else (incl. no weather)→Normal, dispatched via the shared
# ABILITYEFFECT_ON_WEATHER case (battle_util.c L4696-4712) alongside Flower Gift/Ice
# Face (neither reacted to here — Flower Gift is a stat-boost-only implementation in
# this project with no form data, and Ice Face is excluded per Section 8.4). Utility
# Umbrella exempts sun/rain specifically (`IsBattlerWeatherAffected`, battle_util.c
# L9295) — NOT hail, the same asymmetry `[M17n-2]` already established for Swift
# Swim/Chlorophyll (respect it) vs. Sand Rush/Slush Rush (don't). `weather` is the
# caller's already-resolved EFFECTIVE weather (Air Lock/Cloud Nine-aware, matching
# every other weather-conditional ability in this project) — a Castform sharing a
# field with an Air Lock holder correctly reverts to Normal-type. Returns
# `TypeChart.TYPE_NONE` (a safe sentinel — never Forecast's own real output) when the
# ability doesn't apply, so callers can skip the mutation/signal entirely rather than
# re-applying an already-correct type every single call.
static func forecast_type(mon: BattlePokemon, ng_active: bool, weather: int) -> int:
	if effective_ability_id(mon, ng_active) != ABILITY_FORECAST:
		return TypeChart.TYPE_NONE
	var umbrella: bool = ItemManager.blocks_weather_modifier(mon, ng_active)
	if weather == DamageCalculator.WEATHER_SUN and not umbrella:
		return TypeChart.TYPE_FIRE
	if weather == DamageCalculator.WEATHER_RAIN and not umbrella:
		return TypeChart.TYPE_WATER
	if weather == DamageCalculator.WEATHER_HAIL:
		return TypeChart.TYPE_ICE
	return TypeChart.TYPE_NORMAL


# M17n-10: Liquid Ooze — the DRAINED Pokémon's own ability (not the attacker's)
# inverts a successful drain-percent heal into damage of the same amount. Source:
# SetHealScript (battle_move_resolution.c L2587-2599). No `breakable` flag in source
# (confirmed via `data/abilities.h`) — this is the drained mon protecting itself, not
# something an attacker's Mold Breaker could bypass.
static func inverts_drain(drained_mon: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(drained_mon, ng_active) == ABILITY_LIQUID_OOZE


# M17n-10: Pressure — extra PP deducted per Pressure-holding opponent targeted.
# Source: CancelerPPDeduction (battle_move_resolution.c L982-1002). For a spread
# move (TARGET_BOTH/TARGET_FOES_AND_ALLY, this project's `MoveData.is_spread`),
# TARGET_ALL_BATTLERS, or TARGET_FIELD, +1 PP is deducted per LIVE, non-ally battler
# holding Pressure — the doubles-spread edge case: a spread move against two
# Pressure holders costs 3 PP, not 2 (source's own loop excludes only allies, so
# both opposing slots are counted independently). `MoveForcesPressure` in source
# flags a handful of moves (Perish Song etc.) that force this same field-wide count
# even though their own `.target` isn't one of the three listed — none of those
# flagged moves exist in this project's roster, confirmed via grep, so it's omitted.
# For any other single-target move, +1 PP only if the resolved defender itself has
# Pressure AND isn't the attacker — matching source's `battlerAtk != battlerDef`
# guard, which also correctly zeroes this out for TARGET_USER/TARGET_ALLY/etc.
# self-or-ally-only moves without needing a separate check. TARGET_OPPONENTS_FIELD
# hazards (Spikes/Stealth Rock/Toxic Spikes) are explicitly excluded from that final
# branch in source and don't match the spread/ALL_BATTLERS/FIELD list either — a
# hazard move never draws extra PP from an opposing Pressure holder.
static func pressure_pp_cost(move: MoveData, attacker: BattlePokemon, defender: BattlePokemon,
		attacker_side: int, combatants: Array, active_per_side: int, ng_active: bool = false) -> int:
	var extra := 0
	if move.is_spread or move.target == MoveData.TARGET_ALL_BATTLERS \
			or move.target == MoveData.TARGET_FIELD:
		var opp_start: int = (1 - attacker_side) * active_per_side
		for i in range(active_per_side):
			var mon: BattlePokemon = combatants[opp_start + i]
			if not mon.fainted and effective_ability_id(mon, ng_active) == ABILITY_PRESSURE:
				extra += 1
	elif move.target != MoveData.TARGET_OPPONENTS_FIELD:
		if defender != attacker and effective_ability_id(defender, ng_active) == ABILITY_PRESSURE:
			extra += 1
	return 1 + extra


# M17a: post-type-effectiveness attacker-side modifier.
# Source: battle_util.c :: GetAttackerAbilitiesModifier (L7378-7397):
#   ABILITY_SNIPER: isCrit → ×1.5
#   ABILITY_TINTED_LENS: typeEffectivenessModifier <= 0.5 (not-very-effective) → ×2.0
# (ABILITY_NEUROFORCE, the third case in this source switch, is excluded from this
# project's scope per docs/m17_recon.md Section 13 — Necrozma-Ultra is legendary-exclusive.)
# Applied after type effectiveness and after Battle Armor/Shell Armor's crit block, so
# is_crit here already reflects that block (Sniper simply won't fire if crit was blocked).
static func attacker_post_effectiveness_modifier_uq412(
		attacker: BattlePokemon, effectiveness: float, is_crit: bool,
		ng_active: bool = false) -> int:
	var id: int = effective_ability_id(attacker, ng_active)
	if id == ABILITY_NONE:
		return 4096
	if id == ABILITY_SNIPER and is_crit:
		return 6144  # UQ_4_12(1.5)
	if id == ABILITY_TINTED_LENS and effectiveness <= 0.5:
		return 8192  # UQ_4_12(2.0)
	return 4096


# M17a: whether the defender's ability blocks this hit from being a critical hit.
# Source: battle_util.c :: CalcCritChanceStage (L7848-7859): if critChance !=
#   CRITICAL_HIT_BLOCKED and defender has Battle Armor or Shell Armor, critChance is
#   forcibly set to CRITICAL_HIT_BLOCKED — this overrides even an always-crit move/effect,
#   so DamageCalculator applies this after crit is determined (by roll OR by force_crit),
#   not as a pre-roll probability adjustment.
static func blocks_critical_hit(
		defender: BattlePokemon, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	var id: int = effective_ability_id(defender, ng_active, attacker)
	return id == ABILITY_BATTLE_ARMOR or id == ABILITY_SHELL_ARMOR


# M17a: move base-power modifier — source's CalcMoveBasePowerAfterModifiers (L6375-6656),
# applied to the move's base power before the damage formula (same pipeline stage as
# M14b's Helping Hand ×1.5). Only the M17a-relevant cases from that function:
#   ABILITY_TOXIC_BOOST  (L6469-6471): poisoned (incl. toxic) AND physical → ×1.5
#   ABILITY_FLARE_BOOST  (L6465-6467): burned AND special → ×1.5
#   ABILITY_SAND_FORCE   (L6486-6490): moveType in {Steel,Rock,Ground} AND sandstorm active → ×1.3
#   ABILITY_TOUGH_CLAWS  (L6510-6512): move makes contact → ×1.3
#   ABILITY_STEELWORKER  (L6526-6528): moveType == Steel → ×1.5
#   ABILITY_STEELY_SPIRIT (self, L6558-6560): moveType == Steel → ×1.5
#   "attacker partner's abilities" block (L6588-6600), doubles-only, checked independently
#   of the attacker's own ability (both could theoretically fire, mirroring source's
#   separate switch statements):
#     ABILITY_BATTERY (ally holds it): move is Special → ×1.3
#     ABILITY_POWER_SPOT (ally holds it): unconditional → ×1.3
#     ABILITY_STEELY_SPIRIT (ally holds it): moveType == Steel → ×1.5
# weather: DamageCalculator.WEATHER_* constant, for Sand Force's sandstorm gate.
# ally: the attacker's doubles partner, or null in singles / if the ally has fainted —
#   resolved by BattleManager (this static function has no battle-state access).
# is_last_to_move: M17n-5 addition, for Analytic — whether `attacker` is the last
#   battler with a pending MOVE action this turn (source: IsLastMonToMove,
#   battle_util.c L1098-1115, checked against the FINAL resolved turn order — i.e.
#   AFTER Trick Room/Pursuit/[M17n-3]'s priority abilities have already been applied,
#   not a raw speed comparison). Resolved by BattleManager (this static function has
#   no turn-order access); default false preserves every pre-existing call site.
#
# M17n-5 additions, same function (CalcMoveBasePowerAfterModifiers, L6375-6656),
# same attacker-abilities switch:
#   ABILITY_IRON_FIST     (L6473-6475): IsPunchingMove(move) → ×1.2
#   ABILITY_TECHNICIAN    (L6461-6464): move's BASE power (not any in-progress
#     modified value — `basePower` is captured once at function entry, before any
#     modifier in this switch runs) <= 60 → ×1.5
#   ABILITY_RECKLESS      (L6471-6473): moveEffect in {EFFECT_RECOIL,
#     EFFECT_RECOIL_IF_MISS} → ×1.2. This project has no EFFECT_RECOIL_IF_MISS-shaped
#     move (no Jump-Kick-style crash-on-miss mechanic exists anywhere in this
#     codebase) — confirmed equivalent to `move.recoil_percent > 0` given this
#     project's CURRENT roster (all 3 existing recoil moves are EFFECT_RECOIL-shaped,
#     verified individually via their own data-pipeline source comments, not
#     assumed) — re-check this equivalence if a crash-on-miss move is ever added.
#   ABILITY_SHEER_FORCE   (L6481-6483): MoveIsAffectedBySheerForce → ×1.3. Source's
#     helper (`MoveIsAffectedBySheerForce`, battle_util.c L9536-9547) checks for a
#     probabilistic secondary effect — equivalent to this project's own
#     `move.secondary_chance > 0` ("a true secondary effect," the exact phrasing
#     StatusManager.try_secondary_effect already uses for the same concept). A move
#     with NO secondary effect (chance == 0) does NOT get this boost — confirmed from
#     source, not assumed; the suppression half lives in
#     StatusManager.try_secondary_effect, gated on the SAME condition.
#   ABILITY_STRONG_JAW    (L6514-6516): IsBitingMove(move) → ×1.5
#   ABILITY_MEGA_LAUNCHER (L6518-6520): IsPulseMove(move) → ×1.5. No move in this
#     project's current roster carries pulse_move=true (confirmed via grep) — the
#     mechanism is real and tested via a synthetic MoveData, matching this project's
#     established `_make_move`-style precedent for flag-dependent power modifiers.
#   ABILITY_PUNK_ROCK     (L6554-6556): IsSoundMove(move) → ×1.3 (own-move boost half;
#     the OTHER half — damage TAKEN from an opponent's sound move ×0.5 — lives in
#     defense_damage_modifier_uq412 below, a genuinely different function/direction,
#     confirmed from source rather than assumed non-issue for the "hits another Punk
#     Rock holder" edge case: each side's own switch-case only ever reads that side's
#     OWN ability, so no double-counting is possible by construction).
#   ABILITY_SHARPNESS     (L6562-6564): IsSlicingMove(move) → ×1.5
#   ABILITY_ANALYTIC      (L6496-6508): moving last (see is_last_to_move doc above) →
#     ×1.3. Source explicitly excludes EFFECT_FUTURE_SIGHT (not implemented in this
#     project — N/A, not a dropped check).
static func move_power_modifier_uq412(
		attacker: BattlePokemon, move: MoveData, weather: int,
		ally: BattlePokemon = null, ng_active: bool = false,
		is_last_to_move: bool = false, move_type_changed: bool = false,
		defender: BattlePokemon = null) -> int:
	var modifier: int = 4096

	var atk_ability_id: int = effective_ability_id(attacker, ng_active)
	if atk_ability_id != ABILITY_NONE:
		var id: int = atk_ability_id
		# [M18.5d-2] Rivalry — same pipeline stage as every other modifier in this
		# function (CalcMoveBasePowerAfterModifiers, battle_util.c L6490-6494, the
		# exact case immediately preceding Analytic below). `defender` is a NEW param
		# on this function solely for Rivalry — every other modifier here only ever
		# needed the attacker's own data. Exact values: UQ_4_12(1.25)=5120 (same
		# gender), UQ_4_12(0.75)=3072 (opposite gender); genderless on either side
		# means neither `are_same_gender` nor `are_opposite_gender` fires, so the
		# modifier stays 4096 (neutral) — matches source's own fall-through (no
		# `default` branch needed, the `if`/`else if` pair simply doesn't match).
		if id == ABILITY_RIVALRY and defender != null:
			if BattlePokemon.are_same_gender(attacker, defender):
				modifier = DamageCalculator._uq412_multiply(modifier, 5120)
			elif BattlePokemon.are_opposite_gender(attacker, defender):
				modifier = DamageCalculator._uq412_multiply(modifier, 3072)
		if id == ABILITY_TOXIC_BOOST \
				and (attacker.status == BattlePokemon.STATUS_POISON
					or attacker.status == BattlePokemon.STATUS_TOXIC) \
				and move.category == 0:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_FLARE_BOOST and attacker.status == BattlePokemon.STATUS_BURN \
				and move.category == 1:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_SAND_FORCE and weather == DamageCalculator.WEATHER_SANDSTORM \
				and (move.type == TypeChart.TYPE_STEEL or move.type == TypeChart.TYPE_ROCK
					or move.type == TypeChart.TYPE_GROUND):
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)  # UQ_4_12(1.3)
		# [M17.5 Batch Fix]: switched from a raw `move.makes_contact` read to the shared
		# `move_makes_contact()` wrapper for consistency with every other contact-flag
		# consumer in this file (Rough Skin/Static/Flame Body/etc. all already go
		# through it). Purely a style fix — currently behaviorally identical, since a
		# battler can't simultaneously hold Tough Claws and Long Reach, but this closes
		# the one remaining raw-flag read the M17.5 recon flagged.
		if id == ABILITY_TOUGH_CLAWS and move_makes_contact(attacker, move, ng_active):
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if id == ABILITY_STEELWORKER and move.type == TypeChart.TYPE_STEEL:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_STEELY_SPIRIT and move.type == TypeChart.TYPE_STEEL:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_IRON_FIST and move.punching_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 4915)  # UQ_4_12(1.2)
		if id == ABILITY_TECHNICIAN and move.power <= 60:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_RECKLESS and move.recoil_percent > 0:
			modifier = DamageCalculator._uq412_multiply(modifier, 4915)
		if id == ABILITY_SHEER_FORCE and move.secondary_chance > 0:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if id == ABILITY_STRONG_JAW and move.biting_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_MEGA_LAUNCHER and move.pulse_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_PUNK_ROCK and move.sound_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if id == ABILITY_SHARPNESS and move.slicing_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_ANALYTIC and is_last_to_move:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		# M17n-4: Gorilla Tactics — physical-move base power ×1.5. Source:
		# CalcMoveBasePowerAfterModifiers, case ABILITY_GORILLA_TACTICS
		# (battle_util.c L6884-6889); source also excludes Dynamax, which this project
		# doesn't model, so that half of the condition is moot here. This is a DIFFERENT
		# pipeline stage from Choice Band/Specs' attack-STAT modifier
		# (ItemManager.attack_modifier_uq412) — confirmed from source's own test
		# ("Gorilla Tactics stacks with Choice Band to reach 2.25x Attack",
		# test/battle/ability/gorilla_tactics.c) that the two compose multiplicatively
		# (1.5 x 1.5 = 2.25), which this project's pipeline already produces automatically
		# once this branch exists, since the two modifiers already apply at genuinely
		# separate stages (attack stat vs. base power) — no special-case stacking code
		# needed.
		if id == ABILITY_GORILLA_TACTICS and move.category == 0:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		# M17n-6: Normalize / Refrigerate / Pixilate / Galvanize — ×1.2 power boost,
		# GEN_LATEST config (source: `GetConfig(B_ATE_MULTIPLIER) >= GEN_7 ? 1.2 :
		# 1.3` — this project's reference config is always GEN_LATEST, so 1.2/4915
		# unconditionally, matching every other GEN_LATEST-only branch in this file).
		# Gated on `move_type_changed` (this call's own `effective_move_type` result,
		# resolved by DamageCalculator BEFORE this function is called and threaded
		# through as this trailing bool) rather than re-deriving move.type here —
		# by this point `move` may already be a type-mutated duplicate (see
		# DamageCalculator.calculate's doc comment), so `move.type` alone can't
		# distinguish "this ability caused it" from "the move was already that type".
		# Confirmed from source (battle_util.c L6538-6552) all FOUR abilities share
		# this exact ×1.2 value — including Normalize itself, which (unlike the
		# "-ate" family) sets its equivalent of `move_type_changed` UNCONDITIONALLY
		# for every move it uses, even an already-Normal one (see effective_move_type's
		# doc comment) — so a Normalize holder's every attack gets this boost, not
		# just moves that visibly changed type.
		# M17n-6 follow-up: Aerilate/Dragonize confirmed from source
		# (battle_util.c L6542-6549) to share the exact same 1.2/4915 gate.
		if (id == ABILITY_NORMALIZE or id == ABILITY_REFRIGERATE or id == ABILITY_PIXILATE
				or id == ABILITY_GALVANIZE or id == ABILITY_AERILATE or id == ABILITY_DRAGONIZE) \
				and move_type_changed:
			modifier = DamageCalculator._uq412_multiply(modifier, 4915)  # UQ_4_12(1.2)

	var ally_ability_id: int = effective_ability_id(ally, ng_active) if ally != null and not ally.fainted else ABILITY_NONE
	if ally_ability_id != ABILITY_NONE:
		var ally_id: int = ally_ability_id
		if ally_id == ABILITY_BATTERY and move.category == 1:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if ally_id == ABILITY_POWER_SPOT:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if ally_id == ABILITY_STEELY_SPIRIT and move.type == TypeChart.TYPE_STEEL:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)

	return modifier


# M17a: whether accuracy checks should be skipped entirely (always hit) because either
# battler has No Guard.
# Source: battle_util.c :: the CanMoveHit-equivalent accuracy-skip check (L10182-10193):
#   ABILITY_NO_GUARD on EITHER the attacker or the defender → move always hits (except
#   STATE_COMMANDER semi-invulnerability, which this project doesn't model — Commander
#   the ability/mechanic is excluded per docs/m17_recon.md Section 8.6). This also
#   bypasses the semi-invulnerable-turn block (Dig/Fly), matching source's ordering
#   (checked before the accuracy roll and before the semi-invulnerable gate).
static func bypasses_accuracy_check(
		attacker: BattlePokemon, defender: BattlePokemon, ng_active: bool = false) -> bool:
	if effective_ability_id(attacker, ng_active) == ABILITY_NO_GUARD:
		return true
	if effective_ability_id(defender, ng_active) == ABILITY_NO_GUARD:
		return true
	return false


# M17a: attacker-ability accuracy percentage modifier.
# Source: battle_util.c :: GetTotalAccuracy — attacker's ability switch (L10283-10295):
#   ABILITY_COMPOUND_EYES: ×1.30 (unconditional)
#   ABILITY_HUSTLE: IsBattleMovePhysical → ×0.80 ("hustle loss")
# (ABILITY_VICTORY_STAR, the third case in this source switch, is excluded from this
# project's scope per docs/m17_recon.md Section 13 — Victini is mythical-exclusive.)
#
# M17n-2 additions: the SAME function's target's-ability switch (L10299-10316):
#   ABILITY_SAND_VEIL: attacker's effective weather == sandstorm → ×0.80 ("sand veil
#     loss" — the accuracy REDUCTION shape rather than an evasion-stage increase, same
#     numeric outcome, matching this project's existing "calc" integer-percentage math
#     rather than modeling a phantom evasion stage).
#   ABILITY_SNOW_CLOAK: hail/snow → ×0.80, same shape.
# `defender`/`weather` are new trailing params — `weather` should be the EFFECTIVE
# weather (see `BattleManager._effective_weather()`), so no separate Air-Lock/Cloud-Nine
# check is needed here either.
# Returns a plain percentage (100 = no change), matching StatusManager.check_accuracy's
# existing integer-percentage math style rather than the DamageCalculator's UQ4.12 style.
static func accuracy_modifier_percent(
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false,
		defender: BattlePokemon = null, weather: int = DamageCalculator.WEATHER_NONE) -> int:
	var pct: int = 100
	var id: int = effective_ability_id(attacker, ng_active)
	if id == ABILITY_COMPOUND_EYES:
		pct = (pct * 130) / 100
	elif id == ABILITY_HUSTLE and move.category == 0:
		pct = (pct * 80) / 100

	if defender != null:
		var def_id: int = effective_ability_id(defender, ng_active, attacker)
		if def_id == ABILITY_SAND_VEIL and weather == DamageCalculator.WEATHER_SANDSTORM:
			pct = (pct * 80) / 100
		elif def_id == ABILITY_SNOW_CLOAK and weather == DamageCalculator.WEATHER_HAIL:
			pct = (pct * 80) / 100
		# M17n-5: Tangled Feet — same function/switch as Sand Veil/Snow Cloak
		# (GetTotalAccuracy's target's-ability switch, battle_util.c L10310-10313), but
		# ×0.50 (not ×0.80) while the DEFENDER is confused. `breakable = TRUE` in
		# source, same reachability as Sand Veil/Snow Cloak.
		elif def_id == ABILITY_TANGLED_FEET and defender.confusion_turns > 0:
			pct = (pct * 50) / 100

	return pct


# M17a: whether the attacker's ability blocks standard move-recoil damage.
# Source: battle_move_resolution.c :: EFFECT_RECOIL/EFFECT_CHLOROBLAST handling
#   (L3382-3384): `IsAbilityAndRecord(...ROCK_HEAD) || IsAbilityAndRecord(...MAGIC_GUARD)`
#   — Rock Head and Magic Guard both skip recoil entirely via the same OR'd condition,
#   implemented as of [M17n-9] (previously "Magic Guard, out of scope" before it existed).
# Does NOT apply to Struggle recoil (confirmed a separate, unconditional code path in
# source too — `MOVE_EFFECT_RECOIL_HP_25`, battle_script_commands.c L2534-2542, has no
# Magic-Guard/Rock-Head check anywhere in that case) or to Life Orb recoil (a
# separate item-effect gate, see ItemManager.life_orb_recoil).
static func blocks_recoil(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	var id: int = effective_ability_id(attacker, ng_active)
	return id == ABILITY_ROCK_HEAD or id == ABILITY_MAGIC_GUARD


# Type immunity from ability/item (Levitate/Air Balloon → Ground immunity; Iron
# Ball → the inverse, an unconditional override that REMOVES that immunity).
# Applied before type effectiveness in DamageCalculator; returns true = move deals 0.
# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8159-8176) via
#   IsBattlerGroundedInverseCheck (L5879-5894) — real source uses ONE unified,
#   priority-ordered "is this battler grounded" check (Iron Ball forced-grounded,
#   checked FIRST and unconditional, beats everything else; then
#   Levitate/Air Balloon/Telekinesis/Magnet Rise → ungrounded; then Flying-type →
#   ungrounded; else grounded). Gravity/Ingrain/Smack Down/Telekinesis/Magnet Rise
#   are all confirmed absent from this project (`[M18t]`) — this function only
#   needs the Iron Ball/Levitate/Air Balloon slice of that chain, since Flying-
#   type's own raw immunity is a SEPARATE mechanism (TypeChart's own table,
#   see get_effectiveness's new `grounded_override` param).
# M18t: Iron Ball checked FIRST and unconditionally — a Levitate holder or
#   Air-Balloon holder wearing Iron Ball (impossible simultaneously, since a mon
#   holds exactly one item, but Iron Ball vs. Levitate specifically is the real
#   case this matters for) is grounded regardless, matching source's own
#   `holdEffect == HOLD_EFFECT_IRON_BALL: return TRUE` short-circuit ahead of
#   every ungrounding check.
static func blocks_move_type(
		defender: BattlePokemon, move_type: int, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	if move_type != TypeChart.TYPE_GROUND:
		return false
	if ItemManager.holds_iron_ball(defender, ng_active):
		return false
	if effective_ability_id(defender, ng_active, attacker) == ABILITY_LEVITATE:
		return true
	if ItemManager.holds_air_balloon(defender, ng_active):
		return true
	return false


# M17n-6: Wonder Guard — blocks a damaging hit entirely UNLESS the full combined
# type-effectiveness multiplier (both defender types, weather-flying-weakening, and
# the Scrappy/Mind's Eye Ghost-bypass above, all already folded into `effectiveness`
# by the time DamageCalculator calls this) is STRICTLY greater than 1.0x.
# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8259-8270) —
# `(abilities[battlerDef] == ABILITY_WONDER_GUARD && modifier <= UQ_4_12(1.0) &&
# !isPresentHealing) && GetMovePower(move) != 0`. This project has no Present move
# (isPresentHealing is moot, confirmed absent via grep). `GetMovePower() != 0` is
# reproduced here as `move.power > 0` — status moves default to power=0 (naturally
# exempt, confirmed by this tier's own testing) while fixed/level-damage moves
# (Seismic Toss, Night Shade, Dragon Rage, Sonic Boom) carry the same power=1
# PLACEHOLDER source itself uses purely to mark "this is a damaging move" (see
# scripts/gen_moves.py's own comments citing this), so Wonder Guard correctly still
# blocks those too, unless super effective — matching real-game behavior.
# `move.type != TYPE_MYSTERY` reproduces source's separate `ctx->move != MOVE_STRUGGLE`
# exclusion (Struggle/confusion self-hit never reach this project's own
# type-effectiveness computation at all when moveType is TYPE_MYSTERY — see the
# existing guards at lines 325/341 of DamageCalculator.calculate this mirrors) —
# Struggle has power=50 (nonzero) so it would otherwise be wrongly blocked without
# this guard.
# Confirmed this project's `calculate_confusion_damage` (the OTHER, wholly separate
# self-hit damage function) never calls this check at all by construction — no
# additional exclusion needed there.
# `effective_ability_id` gives Mold-Breaker-bypass (breakable=TRUE in source) and
# Neutralizing-Gas-suppression for free, the same chokepoint every other tier uses.
static func blocks_non_super_effective_hit(
		defender: BattlePokemon, effectiveness: float, move: MoveData,
		ng_active: bool = false, attacker: BattlePokemon = null) -> bool:
	if move.power <= 0 or move.type == TypeChart.TYPE_MYSTERY:
		return false
	if effective_ability_id(defender, ng_active, attacker) != ABILITY_WONDER_GUARD:
		return false
	return effectiveness <= 1.0


# M17n-8: Corrosion — the ATTACKER's own ability bypasses a Poison- or Steel-type
# target's normal status-type immunity to Poison/Toxic infliction. Source:
# `CanSetNonVolatileStatus` (battle_util.c L5250): `abilityAtk != ABILITY_CORROSION &&
# IS_BATTLER_ANY_TYPE(battlerDef, TYPE_POISON, TYPE_STEEL)` — a single condition that
# bypasses BOTH Poison-type and Steel-type immunity together (confirmed from source,
# not assumed uniform — there is no separate Steel-only or Poison-only carve-out).
# Attacker's own ability only, mirrors `bypasses_ghost_immunity`'s exact precedent
# below (an ability is never "broken through" on its own holder, so no
# Mold-Breaker/`attacker` param here either — moot anyway since Corrosion has no
# `breakable` flag in source).
static func bypasses_poison_steel_immunity(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(attacker, ng_active) == ABILITY_CORROSION


# M17n-9: Magic Guard — the HOLDER takes damage ONLY from direct attacks; every
# indirect damage source this project implements is exempted (confirmed per-site
# against source rather than assumed uniform): weather chip (sandstorm/hail),
# status residual (poison/toxic/burn), standard recoil moves (EFFECT_RECOIL,
# alongside Rock Head), Rough Skin/Iron Barbs' damage to the ATTACKER, Life Orb
# recoil, and entry-hazard damage on switch-in (Spikes/Stealth Rock). Two real
# indirect-damage sources this project also implements are confirmed from source
# to be the OPPOSITE of exempted, so deliberately NOT gated here: Struggle's fixed
# recoil (`MOVE_EFFECT_RECOIL_HP_25`, battle_script_commands.c L2534-2542, has no
# `IsAbilityAndRecord(...MAGIC_GUARD)` guard anywhere in that case) and
# Aftermath/Innards Out's retaliation against the KILLER (`battle_util.c`
# ABILITY_AFTERMATH/ABILITY_INNARDS_OUT cases, L3985-4021 — gated only by Damp,
# never by the killer's own Magic Guard). Substitute's own HP cost
# (`Cmd_setsubstitute`, battle_script_commands.c L7813) also has no Magic Guard
# check in source — it's a voluntary self-cost, not "indirect damage" in the
# sense this ability blocks. No single existing chokepoint unifies all six
# exempted sources (each is its own already-built, independently-tested system:
# `blocks_weather_chip_damage`, `StatusManager.end_of_turn_damage`,
# `blocks_recoil`, `try_contact_effects`, `ItemManager.life_orb_recoil`, the
# switch-in hazard block) — refactoring all six into one shared "apply indirect
# damage" pipeline purely to gate Magic Guard would touch a much larger blast
# radius than this ability needs; this single reusable predicate, consulted at
# each of the six existing call sites individually, is the same shape already
# established for Overcoat/`blocks_weather_chip_damage` (one predicate, multiple
# call sites) rather than a new pipeline. No `breakable` flag in source (confirmed
# via `data/abilities.h`) — Mold Breaker structurally doesn't apply anyway, since
# every one of these checks is the HOLDER protecting itself, never an attacker's
# move being resisted by the opponent's ability.
static func blocks_indirect_damage(mon: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(mon, ng_active) == ABILITY_MAGIC_GUARD


# M17n-9: Infiltrator — the ATTACKER's moves bypass Reflect/Light Screen/Aurora
# Veil (`GetScreensModifier`, battle_util.c L7358-7362) AND Substitute
# (`IsSubstituteProtected`, battle_script_commands.c L9534, gated on
# `GetConfig(B_INFILTRATOR_SUBSTITUTE) < GEN_6` — this project targets
# GEN_LATEST/expanded, so the Gen6+ bypass branch applies) for BOTH damaging and
# status moves — `IsSubstituteProtected` is a single shared function every
# substitute-vs-move check in source routes through, not two separate mechanisms.
# Deliberately scoped to ONLY these two systems: source's Infiltrator also bypasses
# Mist and Safeguard, but neither exists in this project (no-op, nothing to gate).
# Attacker's own ability only (no Mold-Breaker/`attacker` param) — mirrors
# `bypasses_ghost_immunity`'s precedent; moot regardless since Infiltrator has no
# `breakable` flag in source (confirmed via `data/abilities.h`).
static func bypasses_infiltrator_barriers(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(attacker, ng_active) == ABILITY_INFILTRATOR


# M17n-9: Magic Bounce — reflects the FIRST foe-targeting status move used against
# the holder back at its own user, as if the user had targeted themselves; the
# original holder is never affected. Source: `TryMagicBounce` (battle_move_resolution.c
# L5158-5171), gated on `MoveCanBeBouncedBack` (`gMovesInfo[move].magicCoatAffected`,
# include/move.h L350-352) — NOT a blanket "all status moves" rule. Re-derived this
# project's exact bounceable subset directly from source's per-move
# `magicCoatAffected` flags rather than assuming every status move qualifies: of
# this project's 91 implemented moves, exactly 9 carry the flag AND are
# foe-targeting in this project's own dispatch — Sand Attack, Tail Whip, Leer,
# Growl, Sleep Powder, Thunder Wave, Toxic, Confuse Ray, Will-O-Wisp (see
# `MoveData.bounceable`, set per-move in `gen_moves.py`). Self-targeting stat moves
# (Swords Dance, Growth), copy/utility moves (Psych Up, Conversion, Conversion 2,
# Pain Split), Encore, and Disable are all confirmed absent from source's
# magicCoatAffected=TRUE table — correctly excluded. Known, documented scope
# limit: Stealth Rock IS magicCoatAffected=TRUE in source (Gen5+) but hazard-setting
# in this project runs through an entirely separate side-wide dispatch
# (`move.is_stealth_rock`, its own early-return branch) that this tier does not
# touch — extending Magic Bounce to hazards would need that dispatch reworked to
# check for an opposing Magic Bounce holder, a larger effort than this "wide but
# shallow" ability's own budget; flagged for a future tier if hazard-bounce is
# ever wanted, not silently dropped.
#
# Magic-Bounce-vs-Magic-Bounce: source's `gBattleStruct->bouncedMoveIsUsed` flag
# means a move can only ever be bounced ONCE — confirmed from
# `TryMagicBounce`/`TryMagicCoat`, both of which unconditionally return FALSE if
# already set. This project's implementation (a single non-recursive attacker/
# defender swap in `_phase_move_execution`, checked exactly once per move) gets
# this "only one bounce ever" behavior for free from the linear control flow, with
# no separate guard flag needed — even if the original attacker also holds Magic
# Bounce, the swapped roles are never re-checked.
#
# Prankster + Dark-type interaction: source's `CanTargetBlockPranksterMove`
# (battle_util.c L2203-2210) explicitly skips the Dark-type Prankster-immunity
# block when the TARGET currently has Magic Bounce (or Magic Coat) active — Magic
# Bounce takes priority over simply shrugging the move off as Dark-type-immune, so
# a Prankster-boosted status move against a Dark-type Magic Bounce holder still
# gets reflected rather than just failing outright. This project's own
# `blocks_prankster_move` check sits in `_phase_move_execution` AFTER this
# function's Magic Bounce check (bounce is checked immediately once `foe_targeting`
# is known, before the Substitute/type-immunity/Prankster gates further down) —
# matching source's ordering, so a Dark-type Magic Bounce holder correctly bounces
# a Prankster'd status move rather than the Prankster-Dark-immunity gate
# incorrectly firing first and eating the move as a no-op.
#
# `.breakable = TRUE` in source's data table (confirmed via `data/abilities.h`,
# unlike Magic Guard/Infiltrator above) — a Mold-Breaker-wielding attacker's status
# move is NOT reflected at all, hitting the target normally. Threaded through the
# full 4-arg `effective_ability_id(defender, ng_active, attacker, attacker_move)`
# form for exactly this reason, unlike every other predicate in this file that only
# checks its own holder.
static func bounces_status_move(defender: BattlePokemon, ng_active: bool,
		attacker: BattlePokemon, attacker_move: MoveData) -> bool:
	return effective_ability_id(defender, ng_active, attacker, attacker_move) == ABILITY_MAGIC_BOUNCE


# M17n-6: Scrappy / Mind's Eye — the ATTACKER's Normal/Fighting-type moves bypass a
# Ghost-type defender's flat type immunity. Source: battle_util.c ::
# MulByTypeEffectiveness (L8046-8052) — checked per defending-type component
# alongside Foresight/Miracle Eye's identical-shaped bypasses (neither of which this
# project models — no Foresight/Miracle Eye anywhere, confirmed via grep). Scrappy has
# no exclusive OTHER-type-immunity bypass (does NOT let a Ground move hit Flying, for
# example) — this is Ghost/Normal/Fighting-specific by construction, threaded into
# TypeChart.get_effectiveness/get_uq412's own `bypass_ghost_immunity` param rather
# than being a separate early gate like Levitate, since (unlike Levitate) it needs the
# PER-COMPONENT type computation, not a flat move-type check. Attacker's own ability
# only (no Mold-Breaker/`attacker` param) — mirrors `ignores_defender_evasion_stage`'s
# existing precedent for exactly this reason (an ability is never "broken through" on
# its own holder).
static func bypasses_ghost_immunity(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	var id: int = effective_ability_id(attacker, ng_active)
	return id == ABILITY_SCRAPPY or id == ABILITY_MINDS_EYE


# M17n-6: Overcoat — full immunity to weather-based end-of-turn chip damage
# (sandstorm/hail). Source: battle_end_turn.c :: HandleEndTurnWeatherDamage
# (L143-169) — Overcoat is one of several per-Pokemon exemptions checked directly
# alongside the Rock/Ground/Steel type exemption and semi-invulnerable state.
#
# [M17n-2] follow-up fix (post-[M17n-6]): source's sandstorm branch (L144-147) ALSO
# exempts Sand Veil, Sand Force, and Sand Rush; its hail branch (L166) ALSO exempts
# Snow Cloak — confirmed directly from a fresh read of the current source, not
# carried over from any prior citation. `[M17n-2]`'s original decisions.md entry
# concluded the opposite ("Sand Veil/Sand Rush do NOT grant chip immunity") and
# shipped a supporting code comment here saying so — Rob has confirmed that
# conclusion was simply wrong (not a reference-tree version discrepancy), so this is
# corrected here rather than left as a flagged-but-unfixed gap. `weather` is the
# CURRENT weather (matching `[M17n-2]`'s own `_effective_weather()` convention —
# Air Lock/Cloud Nine negation already happens before this function's caller ever
# reaches a non-WEATHER_NONE value) — Sand Veil/Sand Force/Sand Rush only exempt
# during sandstorm, Snow Cloak only during hail, matching source's per-weather-branch
# structure (these abilities do NOT cross-exempt the other weather's chip damage).
# Magic Guard also appears in source's exemption chain (L150, L167) but is not
# implemented anywhere in this project (no `ABILITY_MAGIC_GUARD` constant exists,
# confirmed via grep) — correctly absent, not a silently-dropped case.
# Called with no `attacker`/Mold-Breaker param — end-of-turn ticks are outside any
# move-processing window, so Mold Breaker structurally never applies here, matching
# `[M17g]`'s established "Mold Breaker is move-scoped" precedent (same reasoning
# already used for `is_trapped`'s selection-time gate). Neutralizing Gas suppression
# still applies via the standard `effective_ability_id` chokepoint, for every
# ability checked here including the four added by this fix.
static func blocks_weather_chip_damage(
		mon: BattlePokemon, ng_active: bool = false,
		weather: int = DamageCalculator.WEATHER_NONE) -> bool:
	var id: int = effective_ability_id(mon, ng_active)
	if id == ABILITY_OVERCOAT:
		return true
	if weather == DamageCalculator.WEATHER_SANDSTORM:
		return id == ABILITY_SAND_VEIL or id == ABILITY_SAND_FORCE or id == ABILITY_SAND_RUSH
	if weather == DamageCalculator.WEATHER_HAIL:
		return id == ABILITY_SNOW_CLOAK
	return false


# M17n-6: Normalize / Refrigerate / Pixilate / Galvanize / Liquid Voice — mutates the
# ATTACKER's move's effective type for THIS hit. Returns -1 if unaffected (use
# move.type as-is), else the new TypeChart.TYPE_* to substitute.
# Source: battle_main.c :: GetBattleMoveType's ability-override branch (L5993-6024):
#   1. IsSoundMove(move) && ability==LIQUID_VOICE → TYPE_WATER (checked FIRST,
#      unconditionally on original type — reuses the existing `sound_move` MoveData
#      flag from [M17n-1]/[M17n-5], no new flag needed).
#   2. moveType==TYPE_NORMAL && ability!=NORMALIZE → TrySetAteType's per-ability
#      switch (L5751-5765): Refrigerate→Ice, Pixilate→Fairy, Galvanize→Electric
#      (Aerilate→Flying excluded from this project's scope; "Dragonize" is a
#      rom-hack-only custom entry, not a real ability, not carried into this
#      project's ability list at all).
#   3. else if ability==NORMALIZE → TYPE_NORMAL, UNCONDITIONALLY on the original
#      type (not gated on moveType==TYPE_NORMAL like branch 2 — source's own
#      ability!=NORMALIZE guard on branch 2 is what routes an already-Normal move
#      away from branch 2 and into this unconditional branch instead). This means
#      a Normalize holder's ALREADY-Normal-type move is a genuine type no-op but
#      STILL sets source's `ateBoost` flag true (see move_power_modifier_uq412's
#      matching case) — confirmed deliberately, not a bug, since Normalize gives
#      +20% to literally every move it uses, not just ones that visibly changed type.
# Source excludes several variable-type move effects (Hidden Power, Weather Ball,
# Natural Gift, Judgment-style Change-Type-on-Item, Revelation Dance, Terrain Pulse,
# Tera Blast/Starstorm, Aura Wheel) from both branches 2 and 3 — none of these move
# effects exist anywhere in this project's roster (confirmed via grep), so they are
# not modeled here at all rather than added as inert exclusions.
# Scoped to the DAMAGE pipeline only (DamageCalculator.calculate substitutes a
# shallow-duplicated MoveData with just `.type` overridden, never mutating the
# shared move Resource) — status-move type mutation project-wide is NOT modeled,
# since no established hook exists there and this tier's own scope is the
# type-effectiveness/damage pipeline specifically.
static func effective_move_type(
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var id: int = effective_ability_id(attacker, ng_active)
	if move.sound_move and id == ABILITY_LIQUID_VOICE:
		return TypeChart.TYPE_WATER
	if move.type == TypeChart.TYPE_NORMAL and id != ABILITY_NORMALIZE:
		if id == ABILITY_REFRIGERATE:
			return TypeChart.TYPE_ICE
		if id == ABILITY_PIXILATE:
			return TypeChart.TYPE_FAIRY
		if id == ABILITY_GALVANIZE:
			return TypeChart.TYPE_ELECTRIC
		# M17n-6 follow-up: Aerilate (Normal->Flying) and Dragonize (Normal->Dragon)
		# — confirmed from source (TrySetAteType, battle_main.c L5757/L5763-5765)
		# to be the SAME switch/branch as Refrigerate/Pixilate/Galvanize, not a
		# separate mechanism.
		if id == ABILITY_AERILATE:
			return TypeChart.TYPE_FLYING
		if id == ABILITY_DRAGONIZE:
			return TypeChart.TYPE_DRAGON
		return -1
	if id == ABILITY_NORMALIZE:
		return TypeChart.TYPE_NORMAL
	return -1


# M17n-1: Soundproof / Bulletproof — full immunity to a move carrying a specific FLAG
# (not a type). Source: `CanAbilityAbsorbMove` (battle_util.c L2282-2289) — the SAME
# dispatch group Levitate/the absorb-family use, checked via `IsSoundMove(ctx->move)`/
# `IsBallisticMove(ctx->move)` rather than `ctx->moveType`. Unlike the absorb family,
# this is a flat, unconditional block (`BattleScript_AbilityProtectedTarget`, no
# heal/stat/flag side-effect of any kind) — applies to EVERY move carrying the flag,
# damaging or status alike (Growl/Roar/Whirlwind are all `sound_move` status moves in
# this project's roster; a future sound/ballistic damaging move is covered the same
# way). Wired into `_phase_move_execution` BEFORE the accuracy check, the same
# relative position `blocks_priority_move` already established, since this is
# logically "does the move even connect at all" — a single choke point covering both
# damaging and status moves, rather than splitting the check across
# `DamageCalculator` (damage-only) and the status-move branch (status-only).
# `sound_move`/`ballistic_move` are pre-existing `MoveData` fields (from the original
# move-data schema) — no new MoveData flag was needed, confirmed via a direct field
# check before writing this function, per the `[M17h]`-established dormant-field-check
# discipline applied to move data as well as ability data.
static func blocks_move_flag(
		defender: BattlePokemon, move: MoveData, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	var id: int = effective_ability_id(defender, ng_active, attacker)
	if id == ABILITY_SOUNDPROOF and move.sound_move:
		return true
	if id == ABILITY_BULLETPROOF and move.ballistic_move:
		return true
	# M17n-6: Overcoat's powder-move half — same shape/dispatch group as Soundproof/
	# Bulletproof above. Source: `IsPowderMoveBlocked` (battle_util.c L2216-2229),
	# which itself calls `IsAffectedByPowderMove` (L10545-10552, gated on
	# `B_POWDER_OVERCOAT >= GEN_6`, satisfied at this project's GEN_LATEST config) —
	# a flat, unconditional full-move block (`BattleScript_PowderMoveNoEffect`),
	# applying to Sleep Powder/Stun Spore/Spore-style status moves exactly like
	# Soundproof blocks sound-flagged status moves. `powder_move` is a pre-existing
	# dormant `MoveData` field (Sleep Powder already has it set from the original
	# schema) — confirmed via grep it was never read anywhere before this, so no new
	# flag was needed, matching the `[M17h]`-established dormant-field-check
	# discipline.
	if id == ABILITY_OVERCOAT and move.powder_move:
		return true
	# [M17.5 Batch Fix]: Grass-type's general powder-move immunity — the OTHER half of
	# `IsAffectedByPowderMove` (battle_util.c L10545-10552), gated on
	# `B_POWDER_GRASS >= GEN_6` (also satisfied at this project's GEN_LATEST config),
	# independent of Overcoat's ability-based exemption directly above. This is a pure
	# type check (not an ability), so it is unconditional — never Mold-Breaker-
	# bypassable (Mold Breaker only bypasses ABILITIES, never innate typing) and
	# unaffected by Neutralizing Gas. Found as a live gap during the M17.5 recon: only
	# Overcoat's half was ever wired here; the Grass-type half was previously only
	# checked, incidentally and for an unrelated purpose, inside Effect Spore's own
	# attacker-side exemption (see `try_contact_effects` below) — that check protects a
	# Grass-type ATTACKER from Effect Spore's proc and is architecturally unrelated to
	# a Grass-type DEFENDER being hit by an actual powder move; left untouched by this
	# fix.
	if defender != null and TypeChart.TYPE_GRASS in defender.species.types and move.powder_move:
		return true
	# [M18r]: Safety Goggles — source's third `IsAffectedByPowderMove` exemption
	# (battle_util.c L10545-10552), item-scope so it's checked directly against
	# ItemManager rather than through `effective_ability_id` above (matching the
	# existing Utility Umbrella precedent elsewhere in this file). Unconditional
	# like the Grass-type check just above — item possession, not an ability, so
	# never Mold-Breaker-bypassable and unaffected by Neutralizing Gas.
	if defender != null and move.powder_move and ItemManager.holds_safety_goggles(defender, ng_active):
		return true
	return false


# M17l/M17m: full immunity (0 damage) to a matching-type move, whenever the holder is
# hit (whether by direct targeting or, for Lightning Rod/Storm Drain, by the redirect
# below). Source: `CanAbilityAbsorbMove` (battle_util.c L2235-2313) — ONE dispatch
# function in source, but THREE genuinely different on-absorb effect shapes, per
# `docs/m17m_absorb_recon.md`'s finding that M17l's original bare-int/STAGE_* return
# contract (kept for Lightning Rod/Storm Drain only) couldn't express the other two:
#
# CROSS-CUTTING DESIGN DECISION (see docs/decisions.md [M17m]): widened this function's
# return type from a bare `int` (STAGE_* or -1) to a `Dictionary`, rather than adding
# sibling functions, because Well-Baked Body's magnitude (+2, not +1 like every other
# stat-boost entry) can't be expressed by a STAGE_*-only return without a second special
# case at every call site — a Dictionary carries "kind" + payload uniformly for all
# three shapes and keeps `DamageCalculator`/`BattleManager` to one dispatch point each,
# matching the shape of the single source function they all come from.
#
# Returns `{}` if not absorbed. Otherwise one of:
#   {"kind": "stat", "stat": <BattlePokemon.STAGE_*>, "amount": <int>} — Lightning Rod/
#     Storm Drain (Sp.Atk +1, `AbsorbedByStatIncreaseAbility`, L2328-2340, via
#     `CanAbilityAbsorbMove` L2258-2265), Sap Sipper (Atk +1, Grass, L2266-2268), Motor
#     Drive (Speed +1, NOT Sp.Atk — L2254-2257), Well-Baked Body (Def **+2**, NOT +1 —
#     L2270-2272). The stat-cap-already-at-+6 no-op is the caller's job via the normal
#     `StatusManager.apply_stat_change` clamp, not re-implemented here — the move is
#     still absorbed (0 damage) even when the boost itself doesn't land, matching
#     source's `AbsorbedByStatIncreaseAbility` returning an "absorbed, no boost" script
#     variant rather than "not absorbed at all" in that case.
#   {"kind": "heal", "fraction": <int>} — Volt Absorb (Electric, L2241-2243), Water
#     Absorb (Water, L2245-2248), Earth Eater (Ground, L2250-2253), and Dry Skin's water
#     half (Water — L2246-2248 is the literal SAME case label as Water Absorb, the
#     previously-deferred third of `[M17c]`'s Dry Skin work). All four share
#     `AbsorbedByDrainHpAbility` (L2315-2326): heal maxHP/4, but ONLY if not already at
#     max HP — the move is absorbed (0 damage) either way; heal-fraction is always 4 in
#     this project (this project has no Heal Block mechanic anywhere to gate on, unlike
#     source's `B_HEAL_BLOCKING`-gated branch — confirmed absent via a grep sweep, not
#     silently dropped).
#   {"kind": "flag"} — Flash Fire (Fire, L2278-2280, gated on `B_FLASH_FIRE_FROZEN >=
#     GEN_5` which this project's reference config has at GEN_LATEST, so no freeze gate
#     applies). Sets a persistent volatile (`BattlePokemon.flash_fire_active`) with NO
#     immediate stat/HP change of its own — the actual payoff is a LATER Fire-type move
#     from the same holder getting a ×1.5 power boost, handled entirely separately in
#     `attack_modifier_uq412` (battle_util.c L6817-6819, the same attacker-side
#     base-power switch Overgrow/Blaze/Torrent/Swarm already occupy), since that's an
#     attacker-side check on a LATER turn, not part of this defender-side absorb dispatch
#     at all.
#
# Applied BEFORE the general type-effectiveness table, same as Levitate's Ground
# immunity above (source: same `CanAbilityAbsorbMove` dispatch group).
static func absorbs_move_type(
		defender: BattlePokemon, move_type: int, ng_active: bool = false,
		attacker: BattlePokemon = null) -> Dictionary:
	var id: int = effective_ability_id(defender, ng_active, attacker)
	if id == ABILITY_LIGHTNING_ROD and move_type == TypeChart.TYPE_ELECTRIC:
		return {"kind": "stat", "stat": BattlePokemon.STAGE_SPATK, "amount": 1}
	if id == ABILITY_STORM_DRAIN and move_type == TypeChart.TYPE_WATER:
		return {"kind": "stat", "stat": BattlePokemon.STAGE_SPATK, "amount": 1}
	if id == ABILITY_SAP_SIPPER and move_type == TypeChart.TYPE_GRASS:
		return {"kind": "stat", "stat": BattlePokemon.STAGE_ATK, "amount": 1}
	if id == ABILITY_MOTOR_DRIVE and move_type == TypeChart.TYPE_ELECTRIC:
		return {"kind": "stat", "stat": BattlePokemon.STAGE_SPEED, "amount": 1}
	if id == ABILITY_WELL_BAKED_BODY and move_type == TypeChart.TYPE_FIRE:
		return {"kind": "stat", "stat": BattlePokemon.STAGE_DEF, "amount": 2}
	if id == ABILITY_VOLT_ABSORB and move_type == TypeChart.TYPE_ELECTRIC:
		return {"kind": "heal", "fraction": 4}
	if (id == ABILITY_WATER_ABSORB or id == ABILITY_DRY_SKIN) and move_type == TypeChart.TYPE_WATER:
		return {"kind": "heal", "fraction": 4}
	if id == ABILITY_EARTH_EATER and move_type == TypeChart.TYPE_GROUND:
		return {"kind": "heal", "fraction": 4}
	if id == ABILITY_FLASH_FIRE and move_type == TypeChart.TYPE_FIRE:
		return {"kind": "flag"}
	return {}


# M17l: Telepathy — full immunity (0 damage) to a damaging move whose target is the
# HOLDER'S OWN ATTACKING ALLY (doubles only). Source: battle_util.c L8201-8206 — checked
# via `ctx->battlerDef == BATTLE_PARTNER(ctx->battlerAtk)`, NOT gated on the move being a
# spread move specifically (confirmed directly from source rather than assumed from the
# ability's "prevents ally spread-move damage" flavor text) — in practice this is only
# ever reachable via a spread move since normal move selection never deliberately aims a
# damaging move at one's own ally, but the underlying check itself is broader than that.
# `is_attacker_ally` is resolved by the caller (DamageCalculator already has both
# `defender` and the attacker's `ally` in scope — reusing that existing parameter rather
# than threading a new one through, since `defender == ally` is exactly the condition
# source checks).
static func blocks_ally_damage(
		defender: BattlePokemon, is_attacker_ally: bool, move: MoveData,
		ng_active: bool = false, attacker: BattlePokemon = null) -> bool:
	if not is_attacker_ally or move.power <= 0:
		return false
	return effective_ability_id(defender, ng_active, attacker) == ABILITY_TELEPATHY


# M17l: Friend Guard — reduces damage the DEFENDER takes by 25% whenever the DEFENDER'S
# ALLY holds Friend Guard. Source: `GetDefenderPartnerAbilitiesModifier`
# (battle_util.c L7460-7478) — ×0.75 (UQ_4_12(0.75) = 3072), gated on
# `battlerAtk != battlerDef` (excludes confusion self-hit damage — structurally always
# true in this project anyway, since confusion self-hit uses the separate
# `calculate_confusion_damage` function, never this one, but kept for source fidelity).
# Reuses the EXISTING `defender_ally` parameter `[M17c]`'s Flower Gift already
# established — no new plumbing needed.
static func friend_guard_modifier_uq412(
		defender_ally: BattlePokemon, attacker: BattlePokemon, defender: BattlePokemon,
		ng_active: bool = false) -> int:
	if defender_ally == null or defender_ally.fainted:
		return 4096
	if attacker == defender:
		return 4096
	if effective_ability_id(defender_ally, ng_active, attacker) == ABILITY_FRIEND_GUARD:
		return 3072  # UQ_4_12(0.75)
	return 4096


# M17l: Propeller Tail / Stalwart — the ATTACKER's own moves ignore ALL redirection
# (both Follow Me/Rage Powder AND Lightning Rod/Storm Drain-style ability redirect) when
# the attacker holds either. Source: `IsAffectedByFollowMe`'s own gate
# (battle_move_resolution.c L809-810) and `HandleMoveTargetRedirection`'s redirect-loop
# condition (L872-873) both exclude a Propeller-Tail/Stalwart-holding attacker
# identically — confirmed these two abilities are genuinely mechanically identical (not
# just similarly-shaped), matching the recon's own framing. Neither carries a
# `breakable` flag in source (src/data/abilities.h L1827-1832/L1855-1860) — this is the
# ATTACKER's own ability being consulted, not a defensive ability being bypassed, so
# Mold Breaker has no bearing on it (the same "different concept, no interaction"
# reasoning already established for other attacker-side checks in this project).
static func bypasses_redirection(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	var id: int = effective_ability_id(attacker, ng_active)
	return id == ABILITY_PROPELLER_TAIL or id == ABILITY_STALWART


# M17l: Lightning Rod / Storm Drain — redirect target resolution (doubles only). Source:
# `HandleMoveTargetRedirection` (battle_move_resolution.c L822-888): if the move's
# ORIGINAL target doesn't already hold the matching ability itself (in which case it
# already absorbs the hit directly — no redirect needed, checked via
# `currTargetCantAbsorb`, L847-850), and the original target's doubles partner DOES hold
# it, the move redirects onto that partner instead.
# NOT modeled (a known, narrower gap, consistent with this project's established
# defender/defender_ally-pair convention rather than a full N-battler search): source's
# `B_REDIRECT_ABILITY_ALLIES >= GEN_4` quirk, which also lets these abilities redirect a
# move used by the ATTACKER's OWN ally onto that ally — this project only models
# redirect onto the ORIGINAL TARGET's ally, the overwhelmingly common real scenario (an
# opposing attacker's move aimed at one of two Pokémon on the defending side gets pulled
# onto the other one instead).
# Correctly Mold-Breaker-aware "for free": since both the original-target check and the
# ally check route through `effective_ability_id(..., attacker)`, a Mold-Breaker-holding
# attacker's move is never redirected at all — matching source, where the SAME
# suppression-aware `GetBattlerAbility` read backs `cv->abilities[]` throughout this
# entire function.
# Returns the redirect target (the ally), or null if no redirect applies.
static func resolve_redirect_target(
		original_target: BattlePokemon, target_ally: BattlePokemon,
		attacker: BattlePokemon, move_type: int, ng_active: bool = false) -> BattlePokemon:
	if target_ally == null or target_ally.fainted:
		return null
	var orig_id: int = effective_ability_id(original_target, ng_active, attacker)
	if (orig_id == ABILITY_LIGHTNING_ROD and move_type == TypeChart.TYPE_ELECTRIC) \
			or (orig_id == ABILITY_STORM_DRAIN and move_type == TypeChart.TYPE_WATER):
		return null
	var ally_id: int = effective_ability_id(target_ally, ng_active, attacker)
	if (ally_id == ABILITY_LIGHTNING_ROD and move_type == TypeChart.TYPE_ELECTRIC) \
			or (ally_id == ABILITY_STORM_DRAIN and move_type == TypeChart.TYPE_WATER):
		return target_ally
	return null


# M16d: "grounded" check for entry hazards (Spikes, Toxic Spikes) — Stealth Rock does NOT
# use this (it hits Flying-types/Levitate holders too; only Spikes/Toxic Spikes gate on it).
# Source: battle_util.c :: IsBattlerGrounded (L5896) → IsBattlerGroundedInverseCheck (L5879)
#   → IsBattlerUngroundedByAbilityItemOrEffect (L5866): Levitate ability or Flying-type
#   makes a battler ungrounded (returns false here).
# M18t: Air Balloon and Iron Ball closed — see their own doc comments in
#   item_manager.gd. Confirmed still absent, and out of scope (no code anywhere
#   in this project references them): Magnet Rise / Telekinesis volatiles,
#   Gravity field status, Ingrain/Smack Down volatiles. Iron Ball is checked
#   FIRST, unconditionally, matching source's own priority order
#   (IsBattlerGroundedInverseCheck, battle_util.c L5879-5894) — it overrides
#   even Levitate/Air Balloon/Flying-type. This extension also correctly
#   affects this function's OTHER two callers (hazard immunity, Arena Trap
#   below) for free: an Air Balloon holder now correctly avoids Spikes/Toxic
#   Spikes and can't be trapped by Arena Trap; an Iron Ball holder loses both
#   exemptions if it would otherwise have had them via Levitate/Flying-type.
# M17g: ng_active added — Neutralizing Gas suppresses Levitate's grounding exemption
# field-wide, same as every other ability check (source's IsBattlerGrounded reads the
# ability via GetBattlerAbility, the same suppression-aware chokepoint). No `attacker`
# param: is_grounded is only ever called outside any move-resolution window (hazard
# immunity at switch-in, Arena Trap's grounded-check inside is_trapped at selection
# time) — Mold Breaker's per-move scope structurally cannot apply here (see is_trapped's
# updated comment below for the source citation proving this).
static func is_grounded(mon: BattlePokemon, ng_active: bool = false) -> bool:
	if ItemManager.holds_iron_ball(mon, ng_active):
		return true
	if effective_ability_id(mon, ng_active) == ABILITY_LEVITATE:
		return false
	if ItemManager.holds_air_balloon(mon, ng_active):
		return false
	if TypeChart.TYPE_FLYING in mon.species.types:
		return false
	return true


# M17f: "can this Pokémon voluntarily switch" trapping gate.
# Source: battle_util.c :: IsAbilityPreventingEscape (L4917-4941):
#   - Ghost-types are exempt from ALL trapping abilities when
#     B_GHOSTS_ESCAPE >= GEN_6 (this project runs GEN_LATEST throughout, matching
#     damage_calculator.gd's header convention, so the exemption is unconditional here).
#   - ABILITY_SHADOW_TAG: traps unconditionally UNLESS the trapped mon ALSO has Shadow
#     Tag, which only exempts (mirror match, neither side trapped) when
#     B_SHADOW_TAG_ESCAPE >= GEN_4 — also GEN_LATEST here, so the mirror exception
#     always applies.
#   - ABILITY_ARENA_TRAP: traps only a GROUNDED opponent (reuses is_grounded above).
#   - ABILITY_MAGNET_PULL: traps only a Steel-type opponent.
# Only gates VOLUNTARY switch selection. battle_manager.gd's _phase_move_selection calls
# this right after a queued/AI-chosen switch sets _chosen_switch_slots, before it's
# treated as this turn's real action. Forced switches (Roar/Whirlwind), faint-triggered
# replacement, and Baton Pass never call this — see the call site's comment for why each
# of those paths is architecturally separate from _chosen_switch_slots.
# Shed Shell (the one item exemption source has) is not modeled: this project has no
# Shed Shell item anywhere in ItemManager/data, so there is nothing to exempt.
#
# M17g correction: Neutralizing Gas DOES suppress trapping — confirmed via source,
# `IsAbilityPreventingEscape` (battle_util.c L4917-4941) reads every trapper's ability
# through `GetBattlerAbility(battlerDef)` (L4928), the same suppression-aware chokepoint
# Neutralizing Gas's field-wide check already routes through everywhere else — so an
# active Neutralizing Gas holder makes Shadow Tag/Arena Trap/Magnet Pull stop trapping,
# same as every other ability. Mold Breaker does NOT suppress trapping, though: this
# corrects an assumption in this tier's own task brief, which is worth stating
# explicitly rather than silently overriding. `moldBreakerActive`
# (battle_util.c L9799-9802) is set true only "if (gCurrentMove != MOVE_NONE)",
# immediately before a specific move's effects are resolved, and reset false at
# switch-in cleanup (battle_main.c L3326-3327) — it is scoped strictly to the window of
# processing one Pokémon's current move. `IsAbilityPreventingEscape` is called only
# from selection-time menu code (the Run option, the party-switch B_ACTION_SWITCH case
# — battle_main.c L3993/L4230), entirely outside any move-processing window, so
# moldBreakerActive is never true there regardless of who's on the field. Consequently
# this function takes an `ng_active` param but no `attacker` param.
# ng_active: whether Neutralizing Gas is active anywhere on the field (see
#   AbilityManager.is_neutralizing_gas_active) — suppresses every trapper's ability
#   uniformly, so it's applied once per opponent in the loop below.
static func is_trapped(
		mon: BattlePokemon, live_opponents: Array, ng_active: bool = false) -> bool:
	# This Ghost-type gate is deliberately the FIRST check and covers the whole function,
	# not just the ability loop below. Source confirms this same B_GHOSTS_ESCAPE >= GEN_6
	# check gates BOTH trapping mechanisms independently: IsAbilityPreventingEscape
	# (L4919, abilities — what this function currently implements) AND CanBattlerEscape
	# (L4947, the separate function behind move-based trapping volatiles — escapePrevention
	# from Mean Look/Block/Spider Web, "wrapped" from Wrap/Fire Spin/Whirlpool/Sand
	# Tomb/Clamp/Magma Storm/Infestation, "root" from Ingrain, and the STATUS_FIELD_FAIRY_LOCK
	# field status) — i.e. the immunity is uniform across every trapping SOURCE in source,
	# not an ability-specific carve-out. This project has none of those move-based
	# volatiles yet (out of scope for M17, which is abilities only), but when they DO get
	# built, they should gate through this same is_trapped() (or an equivalent single
	# choke point) rather than reimplementing the Ghost check per-move — that's the whole
	# reason this check sits above the loop instead of being threaded into each ability's
	# own condition.
	if TypeChart.TYPE_GHOST in mon.species.types:
		return false
	# [M18.5f] Bind/Wrap-family trapping — the move-based volatile this comment block
	# above already anticipated. Placed right after the Ghost gate (not inside the
	# ability loop below, since it isn't ability-driven) so a Ghost-type still
	# correctly bypasses it via the shared early return above, matching
	# CanBattlerEscape's real check order (battle_util.c L4943-4960: Ghost checked
	# before wrapped). A Ghost-type hit by a binding move still takes the recurring
	# end-of-turn damage (BattlePokemon.wrapped_by stays set) — only the free-switch
	# exemption comes from here.
	if mon.wrapped_by != null:
		return true
	for opp: BattlePokemon in live_opponents:
		var opp_id: int = effective_ability_id(opp, ng_active)
		if opp_id == ABILITY_NONE:
			continue
		if opp_id == ABILITY_SHADOW_TAG:
			if effective_ability_id(mon, ng_active) == ABILITY_SHADOW_TAG:
				continue
			return true
		if opp_id == ABILITY_ARENA_TRAP and is_grounded(mon, ng_active):
			return true
		if opp_id == ABILITY_MAGNET_PULL and TypeChart.TYPE_STEEL in mon.species.types:
			return true
	return false


# ── M17b: Stat-stage-system interactions ─────────────────────────────────────
#
# Three genuinely different shapes live in this bucket (per docs/m17_recon.md
# Section 9's classification and the task brief for this milestone):
#   (1) Magnitude modifiers — touch the stat-CHANGE-APPLICATION step itself.
#   (2) Change-blocking abilities — gate BEFORE the change applies.
#   (3) Reactive triggers — fire a NEW stat change in response to a hit/switch-
#       in/end-of-turn tick, hooking into EXISTING M8/M11/M16d infrastructure.
# All three are called from StatusManager.apply_stat_change, the single central
# function every stat-raising/lowering move/ability/item already goes through —
# reading `target.ability` there directly needs zero new call-site plumbing for
# shapes (1) and (2). Shape (3) mostly lives in new AbilityManager functions
# called from BattleManager, mirroring M17a's move_power_modifier_uq412 pattern.

# (1) Magnitude modifier — transforms the raw stage amount BEFORE it's applied.
# Source: battle_stat_change.c :: AdjustStatStage (L797-815):
#   ABILITY_CONTRARY: stage = -1 * stage
#   ABILITY_SIMPLE:   stage = 2 * stage
# Called on cv->battlerDef (the RECEIVING Pokémon), applies to ANY stat change
# regardless of source (self-inflicted or opponent-inflicted), before the
# change is checked against MIN/MAX or against ability-blocking.
static func adjust_stat_stage_amount(
		target: BattlePokemon, amount: int, ng_active: bool = false,
		attacker: BattlePokemon = null) -> int:
	var id: int = effective_ability_id(target, ng_active, attacker)
	if id == ABILITY_NONE:
		return amount
	if id == ABILITY_CONTRARY:
		return -amount
	if id == ABILITY_SIMPLE:
		return amount * 2
	return amount


# (2) Change-blocking — whether a (already Simple/Contrary-adjusted) NEGATIVE
# stage change on `target` should be blocked entirely.
# Source: battle_stat_change.c :: CanAbilityPreventStatLoss (L823-831):
#   ABILITY_CLEAR_BODY / ABILITY_WHITE_SMOKE → blocks ALL stat reductions.
#   (ABILITY_FULL_METAL_BODY, the third case, is excluded per Section 13 — Solgaleo.)
# Source: battle_stat_change.c :: AbilityPreventsSpecificStatDrop (L836-850):
#   ABILITY_HYPER_CUTTER → blocks only STAT_ATK.
#   ABILITY_BIG_PECKS    → blocks only STAT_DEF.
#   ABILITY_KEEN_EYE     → blocks only STAT_ACC (accuracy).
#   (ABILITY_MINDS_EYE/ABILITY_ILLUMINATE, the other cases, are out of this
#   project's ability scope.)
# Source: battle_stat_change.c :: IsFlowerVeilBlocked/StatChange_IsFlowerVeilProtected
#   (L601-634): blocks ALL reductions on a GRASS-type battlerDef if the battler
#   itself OR its ally holds Flower Veil.
# stat_idx: a BattlePokemon.STAGE_* constant.
static func blocks_stat_decrease(
		target: BattlePokemon, stat_idx: int, ally: BattlePokemon = null,
		ng_active: bool = false, attacker: BattlePokemon = null) -> bool:
	var id: int = effective_ability_id(target, ng_active, attacker)
	if id != ABILITY_NONE:
		if id == ABILITY_CLEAR_BODY or id == ABILITY_WHITE_SMOKE:
			return true
		if id == ABILITY_HYPER_CUTTER and stat_idx == BattlePokemon.STAGE_ATK:
			return true
		if id == ABILITY_BIG_PECKS and stat_idx == BattlePokemon.STAGE_DEF:
			return true
		if id == ABILITY_KEEN_EYE and stat_idx == BattlePokemon.STAGE_ACCURACY:
			return true

	if TypeChart.TYPE_GRASS in target.species.types:
		if id == ABILITY_FLOWER_VEIL:
			return true
		if ally != null and not ally.fainted \
				and effective_ability_id(ally, ng_active, attacker) == ABILITY_FLOWER_VEIL:
			return true

	return false


# (3) Reactive trigger — Defiant/Competitive fire a follow-up +2 raise when a
# stat decrease actually lands on the holder.
# Source: battle_script_commands.c :: BS_TryDefiantRattled (L13885-13905) +
#   battle_util.c :: ShouldDefiantCompetitiveActivate (L1149-1168):
#   ABILITY_DEFIANT: Attack not already maxed → Atk +2.
#   ABILITY_COMPETITIVE: Sp. Atk not already maxed → SpA +2.
# Known simplification: source gates this on the decrease coming from an
# OPPOSING battler (self-inflicted drops like Overheat/Leaf Storm don't trigger
# it) — this project has no move that lowers the user's own stat yet (only
# Swords Dance-style self-RAISES exist), so that distinction is unreachable in
# practice today. Revisit if a self-stat-lowering move is ever added.
# Returns the STAGE_* to boost, or -1 if neither ability applies.
static func defiant_competitive_stat(target: BattlePokemon, ng_active: bool = false) -> int:
	var id: int = effective_ability_id(target, ng_active)
	if id == ABILITY_NONE:
		return -1
	if id == ABILITY_DEFIANT:
		return BattlePokemon.STAGE_ATK
	if id == ABILITY_COMPETITIVE:
		return BattlePokemon.STAGE_SPATK
	return -1


# Unaware — 3 touch-points across two different call sites (DamageCalculator's
# stage lookup and StatusManager's accuracy calc), not one clean function like
# Simple/Contrary. Split into 4 narrow predicates matching each source check.
# Source: battle_util.c L6785 (attacker's effective ATK stage), L7072 (defender's
#   effective DEF/SPDEF stage), L10251 (evasion-ignoring, shared with Keen Eye/
#   Minds Eye/Illuminate), L10256 (accuracy-ignoring).
# Each resets the relevant stage to DEFAULT (0) — ignoring BOTH boosts and drops,
# not just boosts.

# Attacker's Unaware ignores the DEFENDER's Defense/Sp.Def stage in damage calc.
# M17g: attacker's OWN ability — only ng_active matters (Mold Breaker never suppresses
# its own wielder's ability; CanBreakThroughAbility explicitly excludes battlerDef ==
# battlerAtk, battle_util.c L4824).
static func ignores_defender_def_stage(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(attacker, ng_active) == ABILITY_UNAWARE


# Defender's Unaware ignores the ATTACKER's Attack/Sp.Atk stage in damage calc.
# M17g: Unaware is breakable — the DEFENDER's ability, checked against the current
# attacker, so both ng_active and attacker (for Mold Breaker) apply here.
static func ignores_attacker_atk_stage(
		defender: BattlePokemon, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	return effective_ability_id(defender, ng_active, attacker) == ABILITY_UNAWARE


# Attacker's Unaware (or Keen Eye) ignores the DEFENDER's evasion stage in the
# accuracy formula. Source explicitly groups Unaware/Keen Eye/Minds Eye/Illuminate
# here — only the first two were in this project's ability scope until now.
# M17g: attacker's OWN ability — only ng_active matters (see ignores_defender_def_stage).
# M17n-6: Mind's Eye's second, unrelated half (the first is its Ghost-immunity
# bypass, see `bypasses_ghost_immunity` above — confirmed from source, battle_util.c
# L10251, to be the LITERAL SAME `atkAbility == ABILITY_UNAWARE || atkAbility ==
# ABILITY_KEEN_EYE || atkAbility == ABILITY_MINDS_EYE` condition this function
# already existed to express, per this function's own pre-existing doc comment
# anticipating exactly this addition — genuinely independent of the Ghost-bypass half
# (an attacker can trigger this evasion-ignore even against a non-Ghost target that
# has no relevance to the other half at all, and vice versa).
static func ignores_defender_evasion_stage(
		attacker: BattlePokemon, ng_active: bool = false) -> bool:
	var id: int = effective_ability_id(attacker, ng_active)
	return id == ABILITY_UNAWARE or id == ABILITY_KEEN_EYE or id == ABILITY_MINDS_EYE


# Defender's Unaware ignores the ATTACKER's own accuracy stage in the accuracy formula.
# M17g: Unaware is breakable — the DEFENDER's ability, checked against the current
# attacker (both ng_active and attacker/Mold Breaker apply).
static func ignores_attacker_accuracy_stage(
		defender: BattlePokemon, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	return effective_ability_id(defender, ng_active, attacker) == ABILITY_UNAWARE


# ── Tier 2: Switch-in effects ────────────────────────────────────────────────

# Fire switch-in ability effects for a Pokémon entering battle.
# Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (L3310):
#   ABILITY_INTIMIDATE: shouldAbilityTrigger && !IsOpposingSideEmpty →
#     SetStatChange(all opponents, STAT_ATK, -1).
#     BattleManager calls this once per live opposing combatant via _apply_switch_in_abilities.
# Drizzle/Drought: weather is set via get_switch_in_weather() + BattleManager.try_set_weather().
#
# M17b additions to this same trigger point:
#   ABILITY_RATTLED (battle_util.c L3790-3801, the "being Intimidated" half of its dual
#     trigger — the OTHER half, Bug/Dark/Ghost-type hit, is in try_hit_reactive_effects):
#     when Intimidate successfully lowers this opponent's Attack, Rattled also raises
#     their own Speed +1. Checked here (Intimidate-specific), NOT as a generic "any
#     Attack decrease" reactor, since Growl also lowers Attack in this project and
#     Rattled must not fire from that — only from actually being intimidated.
#   ABILITY_PASTEL_VEIL (battle_util.c L3073-3081, cure-on-switch-in half; the other
#     half — ally-wide poison immunity — is in StatusManager.try_apply_status):
#     cures `pokemon`'s own poison/toxic status if already inflicted when it switches in.
#
# opponent_ally: opponent's doubles partner (for Intimidate's Flower-Veil-block check,
#   threaded through to StatusManager.apply_stat_change) — null in singles.
#
# Returns a Dictionary:
#   "atk_change"            : int  — Attack stage change applied to opponent (Intimidate)
#   "opponent_speed_change" : int  — Speed stage change applied to opponent (Rattled)
#   "cured_own_poison"      : bool — true if Pastel Veil cured pokemon's own poison/toxic
#   "cured_status"          : bool — true if Immunity/Limber/Insomnia/Vital Spirit/Water
#                                    Veil/Magma Armor cured pokemon's own matching
#                                    pre-existing major status on switch-in (M17n-1)
#   "cured_confusion"       : bool — true if Own Tempo cured pokemon's own pre-existing
#                                    confusion on switch-in (M17n-1)
#   "cured_infatuation"     : bool — true if Oblivious cured pokemon's own pre-existing
#                                    infatuation on switch-in (M18.5d-2)
#   "opponent_guard_dog_change" : int — Attack stage change applied to the opponent
#                                    when Guard Dog reverses Intimidate into a raise
#                                    (M17n-10); mutually exclusive with "atk_change"
#   "mirror_armor_reflect_change" : int — Attack stage change applied to POKEMON
#                                    (not opponent) when the opponent's Mirror Armor
#                                    reflects Intimidate's drop back (M17n-11);
#                                    mutually exclusive with "atk_change" and
#                                    "opponent_guard_dog_change"
#   "mirror_armor_holder"   : BattlePokemon or null — the Mirror Armor holder, for
#                                    the caller's own "mirror_armor" ability_triggered
#                                    tag (M17n-11)
static func try_switch_in(
		pokemon: BattlePokemon, opponent: BattlePokemon,
		opponent_ally: BattlePokemon = null, ng_active: bool = false) -> Dictionary:
	var result := {
		"atk_change": 0, "opponent_speed_change": 0, "cured_own_poison": false,
		"opponent_defiant_stat": -1, "opponent_defiant_change": 0,
		"opponent_guard_dog_change": 0,
		"mirror_armor_reflect_change": 0, "mirror_armor_holder": null,
		"cured_status": false, "cured_confusion": false, "cured_infatuation": false,
	}
	var id: int = effective_ability_id(pokemon, ng_active)
	if id == ABILITY_NONE:
		return result
	if id == ABILITY_INTIMIDATE:
		# M17n-1: Inner Focus/Own Tempo/Oblivious fully block Intimidate's Attack drop
		# under B_UPDATED_INTIMIDATE >= GEN_8 (this project's GEN_LATEST config) — source:
		# battle_stat_change.c :: IsIntimidateBlocked (L660-675). Source's same case list
		# also includes Scrappy (113) — implemented in [M17n-6], wired in here in the
		# [M17.5 Batch Fix] session, closing the gap this comment used to flag. Guard Dog
		# is a separate, ALREADY-DIFFERENT-SHAPED case in the same source function (turns
		# the drop into a +1 raise instead of blocking it outright) and is unrelated to
		# this check.
		var opp_blocks_intimidate: bool = not opponent.fainted and (
				effective_ability_id(opponent, ng_active) == ABILITY_INNER_FOCUS
				or effective_ability_id(opponent, ng_active) == ABILITY_OWN_TEMPO
				or effective_ability_id(opponent, ng_active) == ABILITY_OBLIVIOUS
				or effective_ability_id(opponent, ng_active) == ABILITY_SCRAPPY)
		# M17n-10: Guard Dog — reverses (not just blocks) Intimidate's -1 Attack drop
		# into a +1 Attack raise for the intimidated Pokémon itself. Source: the SAME
		# `IsIntimidateBlocked` switch (L676-690) — reuses `BattleScript_DefiantActivates`,
		# confirming this is mechanically Defiant's own shape (a reactive raise), not a
		# generic block, but Intimidate-specific rather than "any Attack decrease"
		# (unlike Defiant/Competitive, which react to ANY opponent-caused decrease).
		# Gated on the target's Attack stage not already being at the -6 floor
		# (`CompareStat(..., MIN_STAT_STAGE, CMP_GREATER_THAN, ...)`,  L699) — the same
		# "the incoming drop would be a real no-op otherwise" gate already established
		# for Defiant/Competitive in `[M17b]` — if already at -6, Guard Dog does not
		# intercept and the (no-op) Intimidate drop proceeds normally instead.
		# NOT Mold-Breaker-aware here, despite `.breakable = TRUE` in source's data
		# table — traced `gBattleStruct->moldBreakerActive`'s own set-site
		# (battle_util.c L9799: `if (gCurrentMove != MOVE_NONE) moldBreakerActive =
		# ...; else moldBreakerActive = FALSE;`) and confirmed it is FALSE whenever no
		# move is currently resolving, which is exactly the case for a switch-in
		# ability trigger — the same "architecturally outside any move-processing
		# window" reasoning `[M17f]`/`[M17g]` already established for trapping (their
		# own `is_trapped()` deliberately has no `attacker` param for the identical
		# reason). Guard Dog's `.breakable` flag is real and DOES apply — just to its
		# OTHER half (`blocks_forced_switch`, checked during an actual Roar/Whirlwind
		# resolution, genuinely inside a move-processing window). Source's additional
		# Flower-Veil-ally speed-order tie-break (`StatChange_IsFlowerVeilProtected`,
		# L678-681 — avoids double-applying the block when a Grass-type
		# Guard-Dog-holder's OWN Flower-Veil-holding ally would already block the drop
		# first) is a narrow doubles-only edge case not modeled here — flagged, not
		# implemented.
		var opp_guard_dog: bool = not opponent.fainted \
				and effective_ability_id(opponent, ng_active) == ABILITY_GUARD_DOG \
				and opponent.stat_stages[BattlePokemon.STAGE_ATK] > -6
		# M17n-11: Mirror Armor — the OTHER opposing-ability shape Intimidate's -1
		# Attack drop can meet, structurally independent from Guard Dog above (a
		# single mon can only hold one ability, so this and `opp_guard_dog` never
		# both apply to the same `opponent` — confirmed no interaction risk, just two
		# different per-holder mechanisms Intimidate can meet across a doubles
		# field). Reflects the drop onto `pokemon` (the switching-in Intimidate
		# source) instead of applying it to `opponent` at all. Same "not
		# Mold-Breaker-aware here" reasoning as Guard Dog directly above — no
		# `attacker` param passed to `mirror_armor_reflects`.
		var opp_mirror_armor: bool = not opponent.fainted \
				and mirror_armor_reflects(opponent, pokemon, ng_active)
		if opp_guard_dog:
			result["opponent_guard_dog_change"] = StatusManager.apply_stat_change(
					opponent, BattlePokemon.STAGE_ATK, 1, opponent_ally, ng_active)
		elif opp_mirror_armor:
			result["mirror_armor_reflect_change"] = StatusManager.apply_stat_change(
					pokemon, BattlePokemon.STAGE_ATK, -1, null, ng_active)
			result["mirror_armor_holder"] = opponent
		elif not opponent.fainted and not opp_blocks_intimidate:
			var atk_change: int = StatusManager.apply_stat_change(
					opponent, BattlePokemon.STAGE_ATK, -1, opponent_ally, ng_active)
			result["atk_change"] = atk_change
			if atk_change < 0 and effective_ability_id(opponent, ng_active) == ABILITY_RATTLED:
				result["opponent_speed_change"] = StatusManager.apply_stat_change(
						opponent, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
			# M17b: Defiant/Competitive — Intimidate is an opponent-caused Attack
			# decrease, same trigger condition as a stat-lowering move.
			if atk_change < 0:
				var dc_stat: int = defiant_competitive_stat(opponent, ng_active)
				if dc_stat != -1:
					result["opponent_defiant_stat"] = dc_stat
					result["opponent_defiant_change"] = StatusManager.apply_stat_change(opponent, dc_stat, 2, null, ng_active)
	if id == ABILITY_PASTEL_VEIL:
		if pokemon.status == BattlePokemon.STATUS_POISON or pokemon.status == BattlePokemon.STATUS_TOXIC:
			pokemon.status = BattlePokemon.STATUS_NONE
			pokemon.toxic_counter = 0
			result["cured_own_poison"] = true

	# M17n-1: switch-in status/confusion self-cure. Source: battle_util.c ::
	# TryImmunityAbilityHealStatus (L8817-8889), dispatched via ABILITYEFFECT_IMMUNITY
	# from battle_switch_in.c L283 — a genuinely separate trigger POINT from the
	# infliction-blocking checks in StatusManager (those stop a NEW status; this cures
	# an ALREADY-PRESENT one the instant the holder switches in, e.g. after inheriting
	# a status via some pre-existing effect). Mirrors Pastel Veil's own cure-on-switch-in
	# shape immediately above, extended to the rest of the matching-status family:
	#   ABILITY_IMMUNITY: poison/toxic (same source case as Pastel Veil, L8822-8828).
	#   ABILITY_OWN_TEMPO: confusion (L8830-8836) — NOT a major status, clears
	#     `confusion_turns` instead of `.status`.
	#   ABILITY_LIMBER: paralysis (L8837-8843).
	#   ABILITY_INSOMNIA / ABILITY_VITAL_SPIRIT: sleep (L8844-8853).
	#   ABILITY_WATER_VEIL: burn (L8854-8862; source's ABILITY_WATER_BUBBLE/
	#     ABILITY_THERMAL_EXCHANGE share this case but neither is wired to this cure
	#     yet — Water Bubble isn't implemented, Thermal Exchange's own [M17b] work
	#     didn't include this cure and isn't being revisited here).
	#   ABILITY_MAGMA_ARMOR: freeze (L8863-8868).
	# Oblivious's own case in this same source function (L8875-8886) cures
	# infatuation/taunt — both N/A, neither exists in this project.
	if id == ABILITY_IMMUNITY and (pokemon.status == BattlePokemon.STATUS_POISON or pokemon.status == BattlePokemon.STATUS_TOXIC):
		pokemon.status = BattlePokemon.STATUS_NONE
		pokemon.toxic_counter = 0
		result["cured_status"] = true
	elif id == ABILITY_LIMBER and pokemon.status == BattlePokemon.STATUS_PARALYSIS:
		pokemon.status = BattlePokemon.STATUS_NONE
		result["cured_status"] = true
	elif (id == ABILITY_INSOMNIA or id == ABILITY_VITAL_SPIRIT) and pokemon.status == BattlePokemon.STATUS_SLEEP:
		pokemon.status = BattlePokemon.STATUS_NONE
		pokemon.sleep_turns = 0
		result["cured_status"] = true
	elif id == ABILITY_WATER_VEIL and pokemon.status == BattlePokemon.STATUS_BURN:
		pokemon.status = BattlePokemon.STATUS_NONE
		result["cured_status"] = true
	elif id == ABILITY_MAGMA_ARMOR and pokemon.status == BattlePokemon.STATUS_FREEZE:
		pokemon.status = BattlePokemon.STATUS_NONE
		result["cured_status"] = true
	if id == ABILITY_OWN_TEMPO and pokemon.confusion_turns > 0:
		pokemon.confusion_turns = 0
		result["cured_confusion"] = true

	# [M18.5d-2] Oblivious — cures the holder's own PRE-EXISTING infatuation on
	# switch-in, the SAME source function/trigger point as Immunity/Limber/Own Tempo
	# above (TryImmunityAbilityHealStatus, battle_util.c L8875-8886) — genuinely N/A
	# before this tier (no infatuation existed for it to cure), closed now that
	# Attract/Cute Charm exist. Source's OTHER half of this same case
	# (`B_OBLIVIOUS_TAUNT >= GEN_6` curing Taunt) stays N/A — Taunt is still not
	# implemented in this project (confirmed via grep, not assumed).
	if id == ABILITY_OBLIVIOUS and pokemon.infatuated_by != null:
		pokemon.infatuated_by = null
		result["cured_infatuation"] = true

	# M17n-5: Slow Start — starts a 5-turn Atk/Speed-halving timer on switch-in.
	# Source: battle_util.c L3052-3055 (ABILITYEFFECT_ON_SWITCHIN case), B_SLOW_START_TIMER
	# = 5 (include/config/battle.h L206).
	if id == ABILITY_SLOW_START:
		pokemon.slow_start_timer = 5

	# Drizzle/Drought weather-set is handled by BattleManager calling get_switch_in_weather()
	# immediately after try_switch_in() — the weather call is separated so BattleManager
	# owns the weather state (it's a field effect, not per-Pokémon).
	return result


# M17b: Download — switch-in, compares BOTH live opponents' effective Defense vs
# Sp. Defense (summed, per source) and raises the holder's Attack or Sp. Atk by 1.
# Separate from try_switch_in because it isn't a per-opponent effect (Intimidate/
# Rattled/Pastel Veil act once per opponent in a loop; Download needs the combined
# total across all opposing battlers first).
# Source: battle_util.c :: ABILITY_DOWNLOAD case (L3151-3163) + GetDownloadStat
#   (L10957-10979): sums opposingDef/opposingSpDef (stat-stage-adjusted) across both
#   opposing flanks; ties go to Sp. Atk (`opposingDef < opposingSpDef` strictly).
# opponents: all LIVE opposing BattlePokemon (1 in singles, up to 2 in doubles).
# Returns the STAGE_* raised (STAGE_ATK or STAGE_SPATK), or -1 if Download doesn't apply
# (no ability, or the relevant stat is already at +6).
static func download_stat(
		pokemon: BattlePokemon, opponents: Array, ng_active: bool = false) -> int:
	if effective_ability_id(pokemon, ng_active) != ABILITY_DOWNLOAD:
		return -1
	var total_def: float = 0.0
	var total_spdef: float = 0.0
	for opp: BattlePokemon in opponents:
		if opp.fainted:
			continue
		total_def += _staged_stat(opp.defense, opp.stat_stages[BattlePokemon.STAGE_DEF])
		total_spdef += _staged_stat(opp.sp_defense, opp.stat_stages[BattlePokemon.STAGE_SPDEF])
	var stat_idx: int = BattlePokemon.STAGE_ATK if total_def < total_spdef else BattlePokemon.STAGE_SPATK
	if pokemon.stat_stages[stat_idx] >= 6:
		return -1
	return stat_idx


# Stat-stage multiplier helper matching DamageCalculator.STAGE_RATIOS, needed by
# download_stat since it must compare EFFECTIVE (stage-adjusted) Def/SpDef, not raw.
static func _staged_stat(base_stat: int, stage: int) -> float:
	var idx: int = clampi(stage + 6, 0, 12)
	var ratio: Array = DamageCalculator.STAGE_RATIOS[idx]
	return float(base_stat) * float(ratio[0]) / float(ratio[1])


# M17b: Supersweet Syrup — switch-in, ONE-TIME ONLY (per source's per-party-member
# `supersweetSyrup` flag, not per-switch-in), lowers ONE opponent's Evasion by 1.
# Same per-opponent-loop shape as Intimidate (BattleManager calls this once per live
# opposing combatant), but gated on BattlePokemon.supersweet_syrup_used so it can only
# ever fire once across the whole battle for a given Pokémon, even if it switches out
# and back in multiple times.
# Source: battle_util.c :: ABILITY_SUPERSWEET_SYRUP case (L3324-3336).
# Returns the actual Evasion stage change applied to opponent (0 = nothing happened).
static func try_switch_in_evasion(
		pokemon: BattlePokemon, opponent: BattlePokemon, ng_active: bool = false) -> int:
	if effective_ability_id(pokemon, ng_active) != ABILITY_SUPERSWEET_SYRUP:
		return 0
	if pokemon.supersweet_syrup_used:
		return 0
	if opponent.fainted:
		return 0
	pokemon.supersweet_syrup_used = true
	return StatusManager.apply_stat_change(opponent, BattlePokemon.STAGE_EVASION, -1, null, ng_active)


# M17c: Hospitality — switch-in, doubles-only, heals the switching-in Pokémon's OWN
# ally (not an opponent) for maxHP/4.
# Source: battle_util.c :: ABILITY_HOSPITALITY case (L4662-4674): IsDoubleBattle(), ally
#   alive, not heal-blocked, not at max HP → heal maxHP/4. This project has no heal-block
#   volatile yet, so that condition is simply absent (matches how other heal effects in
#   this codebase, e.g. Leftovers, don't check it either).
# Returns the heal amount (0 = not this ability, no ally, ally fainted, or already at max).
static func try_switch_in_ally_heal(
		pokemon: BattlePokemon, ally: BattlePokemon, ng_active: bool = false) -> int:
	if effective_ability_id(pokemon, ng_active) != ABILITY_HOSPITALITY:
		return 0
	if ally == null or ally.fainted:
		return 0
	if ally.current_hp >= ally.max_hp:
		return 0
	return max(1, ally.max_hp / 4)


# M17n-11: Costar — switch-in, doubles-only, copies the ally's CURRENT stat stages
# (all 7) plus its focus_energy crit-boost volatile onto the holder. Source:
# ABILITY_COSTAR case (battle_util.c ABILITYEFFECT_ON_SWITCHIN dispatch): requires
# IsDoubleBattle(), the ally alive, AND BattlerHasCopyableChanges(partner)
# (battle_util.c L5964-5979 — true if the ally has ANY non-default stat stage OR
# focusEnergy/dragonCheer/bonusCritStages set) — a confirmed no-op (no message, no
# copy at all) if the ally has nothing worth copying, not a copy-of-zeroes. Source
# also copies dragonCheer/bonusCritStages; neither exists in this project (no G-Max
# moves, no Dragon Cheer), so only stat_stages + focus_energy are copied — the exact
# same stat-stage-array-copy shape `[M16e]`'s Psych Up already established
# (`for _pi in range(...): stages[_pi] = ...`), reused directly rather than
# reimplemented. `_get_ally` already returns null in singles with zero extra
# plumbing (the same "doubles-only for free" precedent `[M17c]`'s Hospitality and
# `[M17h]`'s Receiver/Power of Alchemy both established), so a singles battle is a
# guaranteed no-op here too. Returns true if the copy actually happened (false = not
# this ability, no ally, ally fainted, or ally has nothing copyable).
static func try_costar_copy(pokemon: BattlePokemon, ally: BattlePokemon, ng_active: bool = false) -> bool:
	if effective_ability_id(pokemon, ng_active) != ABILITY_COSTAR:
		return false
	if ally == null or ally.fainted:
		return false
	var has_copyable: bool = ally.focus_energy
	if not has_copyable:
		for stage: int in ally.stat_stages:
			if stage != 0:
				has_copyable = true
				break
	if not has_copyable:
		return false
	for _pi in range(pokemon.stat_stages.size()):
		pokemon.stat_stages[_pi] = ally.stat_stages[_pi]
	pokemon.focus_energy = ally.focus_energy
	return true


# M17n-11: Mirror Armor — whenever a stat-lowering effect targets the holder, the
# drop is instead reflected onto whoever caused it (same stage/amount, redirected —
# NOT reversed in sign the way Guard Dog reverses Intimidate into a raise for
# itself). Source: `IsMirrorArmorReflected` (battle_stat_change.c L742-744):
# `cv->abilities[cv->battlerDef] != ABILITY_MIRROR_ARMOR || st->certain` bail-out,
# THEN — critically — `if (cv->battlerAtk == cv->battlerDef) gBattleScripting.battler
# = cv->battlerDef; else gBattleScripting.battler = cv->battlerAtk;` — a
# SELF-inflicted drop (Overheat/Draco Meteor/Close Combat lowering the user's OWN
# stat) is confirmed to NOT redirect anywhere; it simply applies to the holder
# itself like normal. This function only answers "should this redirect happen" —
# callers are responsible for passing null/skipping when the drop is self-inflicted
# (this project's `move.stat_change_self` flag makes that check trivial at the one
# move-based call site; the Intimidate call site in `try_switch_in` is inherently
# never self-inflicted, since Intimidate's source and target are always different
# battlers by construction). `.breakable = TRUE` in source, BUT — same architectural
# finding as `[M17n-10]`'s Guard Dog correction — `moldBreakerActive` is only ever
# set while an actual move is resolving (`gCurrentMove != MOVE_NONE`,
# battle_util.c L9799), so Mold Breaker only actually matters for the MOVE-based
# call site, never for the Intimidate/switch-in call site (which must call this
# with `attacker` left null, exactly like Guard Dog's own analogous check).
static func mirror_armor_reflects(target: BattlePokemon, source: BattlePokemon,
		ng_active: bool = false, attacker: BattlePokemon = null) -> bool:
	if target == null or source == null or target == source:
		return false
	return effective_ability_id(target, ng_active, attacker) == ABILITY_MIRROR_ARMOR


# Return the WEATHER_* value (DamageCalculator constants) that should be set when this
# Pokémon switches in, or WEATHER_NONE (0) if the ability has no weather effect.
# Source: ABILITYEFFECT_ON_SWITCHIN — ABILITY_DRIZZLE → TryChangeBattleWeather(RAIN) (L3213)
#                                    — ABILITY_DROUGHT → TryChangeBattleWeather(SUN)  (L3242)
#
# M17c additions, same trigger point:
#   ABILITY_SAND_STREAM (L3227-3239): → TryChangeBattleWeather(SANDSTORM).
#   ABILITY_SNOW_WARNING (L3256-3269): → TryChangeBattleWeather(HAIL or SNOW, gated on
#     B_SNOW_WARNING >= GEN_9). This project's WEATHER_HAIL is a single Gen<9-style
#     constant with no separate Snow value (see DamageCalculator's weather comment) —
#     mapping to WEATHER_HAIL is the correct, not simplified, choice for this codebase's
#     existing weather model, not a dropped distinction.
#
# M17d additions, same trigger point:
#   ABILITY_PRIMORDIAL_SEA (L3400-3407) → TryChangeBattleWeather(RAIN_PRIMAL).
#   ABILITY_DESOLATE_LAND (L3391-3398) → TryChangeBattleWeather(SUN_PRIMAL).
#   Both reuse this project's ordinary WEATHER_RAIN/WEATHER_SUN directly rather than
#   adding separate "Primal" weather values — per docs/m17_recon.md Section 8.5's
#   explicit recommendation, dropping the "must be the Primal-Reversion form of a
#   specific legendary" gate entirely, consistent with Rob's stated intent to freely
#   reassign any ability to any species. This project has no Air-Lock-blocks-Primal-only
#   or weather-move-resists-Primal-only special-casing that would need the ordinary and
#   Primal versions to be distinguishable, so a plain reuse is correct, not a simplification.
#   ABILITY_DELTA_STREAM (L3409-3416) → TryChangeBattleWeather(STRONG_WINDS), a genuinely
#   NEW weather value this project didn't have before (DamageCalculator.WEATHER_STRONG_WINDS)
#   — see DamageCalculator.calculate for its type-effectiveness side effect (weakens
#   super-effective hits against Flying-type defenders).
#
# BattleManager calls try_set_weather(get_switch_in_weather(mon)) after try_switch_in().
static func get_switch_in_weather(pokemon: BattlePokemon, ng_active: bool = false) -> int:
	var id: int = effective_ability_id(pokemon, ng_active)
	if id == ABILITY_NONE:
		return DamageCalculator.WEATHER_NONE
	match id:
		ABILITY_DRIZZLE:
			return DamageCalculator.WEATHER_RAIN
		ABILITY_DROUGHT:
			return DamageCalculator.WEATHER_SUN
		ABILITY_SAND_STREAM:
			return DamageCalculator.WEATHER_SANDSTORM
		ABILITY_SNOW_WARNING:
			return DamageCalculator.WEATHER_HAIL
		ABILITY_PRIMORDIAL_SEA:
			return DamageCalculator.WEATHER_RAIN
		ABILITY_DESOLATE_LAND:
			return DamageCalculator.WEATHER_SUN
		ABILITY_DELTA_STREAM:
			return DamageCalculator.WEATHER_STRONG_WINDS
	return DamageCalculator.WEATHER_NONE


# ── Tier 2: End-of-turn effects ───────────────────────────────────────────────

# Fire end-of-turn ability effects for a Pokémon.
# Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (L3605–3621):
#   ABILITY_SPEED_BOOST: CompareStat(speed < MAX) && !BattlerJustSwitchedIn →
#     SetStatChange(battler, STAT_SPEED, +1).
# !BattlerJustSwitchedIn (battle_util.c L10982): returns true when isFirstTurn == 2,
#   set at mid-battle switch-in (battle_main.c L3198/L3309), cleared at L5038.
# Mirrored via BattlePokemon.switched_in_this_turn; cleared in _phase_priority_resolution.
#
# M17b: Moody, same trigger point.
# Source: battle_util.c :: ABILITY_MOODY case (L3613-3635): raises ONE random
#   not-already-maxed stat (Atk/Def/SpA/SpD/Spe/Acc/Eva, per B_MOODY_ACC_EVASION>=GEN_8,
#   this project's GEN_LATEST config) by +2, then lowers a DIFFERENT random
#   not-already-minned stat by -1 (excluding whichever stat was just raised).
#   If nothing is eligible to raise (or to lower), that half is skipped.
#
# force_moody_raise/force_moody_lower: BattlePokemon.STAGE_* index to pin instead of
#   rolling — null = real RNG, matching this codebase's established force_* convention.
#
# M17c additions, same trigger point:
#   ABILITY_RAIN_DISH (L3557-3567): rain active, not at max HP → heal maxHP/16.
#   ABILITY_ICE_BODY (L3541-3549): hail active, not at max HP → heal maxHP/16.
#   ABILITY_DRY_SKIN (L3553-3556, rain half, shares Rain Dish's healAmount branch with a
#     /8 divisor instead of /16 — L3562; L2246/L6616 sun half via the shared
#     SOLAR_POWER_HP_DROP label, L3663-3667): rain active, not at max HP → heal maxHP/8;
#     sun active → damage maxHP/8. Dry Skin's third part (Water-move absorb+heal) is
#     deferred — see defense_damage_modifier_uq412's comment above.
#   ABILITY_HYDRATION (L3568-3574): rain active, has any status → cure it (shares the
#     ABILITY_HEAL_MON_STATUS label with Shed Skin below).
#   ABILITY_SHED_SKIN (L3575-3600): has any status, 1/3 chance (GEN_LATEST: the `==GEN_4`
#     branch is false, so RandomChance(1,3) applies, NOT the 30% RandomPercentage branch
#     Static/Poison Point use — a different threshold despite looking similar) → cure it.
#   ABILITY_HEALER (L3669-3677): doubles-only, ally alive with any status, 30% chance →
#     cure the ALLY's status (not the holder's own).
#   ABILITY_TRUANT (L3646-3647): unconditionally toggles `truantCounter` every end of
#     turn (XOR), matching "skips every other turn" — mirrored via the new
#     BattlePokemon.truant_loafing bool, checked by StatusManager.pre_move_check.
#
# M17d addition, same trigger point:
#   ABILITY_SOLAR_POWER (L3660-3667, the SOLAR_POWER_HP_DROP label Dry Skin's sun half
#     also jumps to — this is the ability the label is actually named after): sun
#     active → damage maxHP/8, unconditionally (no not-at-max-HP gate, unlike the heal
#     abilities above). The OTHER half (Special Attack ×1.5 in sun) is in
#     attack_modifier_uq412.
#
# weather: WEATHER_* constant — needed for Rain Dish/Ice Body/Dry Skin/Hydration/Solar Power.
# ally: doubles partner (null in singles or if fainted) — needed for Healer.
# force_shed_skin_roll/force_healer_roll: null = real RNG, true/false = pin the outcome.
#
# Returns a Dictionary:
#   "speed_boost_change" : int — Speed Boost's stage change (0 = nothing)
#   "moody_raised_stat"  : int — STAGE_* raised, or -1 if none
#   "moody_raised_amount": int — actual stage change applied (0 if blocked/maxed)
#   "moody_lowered_stat" : int — STAGE_* lowered, or -1 if none
#   "moody_lowered_amount": int — actual stage change applied (0 if blocked/minned)
#   "heal_amount"        : int — Rain Dish/Ice Body/Dry Skin heal (0 = none)
#   "damage_amount"      : int — Dry Skin/Solar Power sun self-damage (0 = none)
#   "cured_status"       : bool — Hydration/Shed Skin cured the holder's own status
#   "healed_ally_status" : bool — Healer cured the ally's status
static func try_end_of_turn(
		pokemon: BattlePokemon,
		force_moody_raise: Variant = null,
		force_moody_lower: Variant = null,
		weather: int = DamageCalculator.WEATHER_NONE,
		ally: BattlePokemon = null,
		force_shed_skin_roll: Variant = null,
		force_healer_roll: Variant = null,
		ng_active: bool = false) -> Dictionary:
	var result := {
		"speed_boost_change": 0,
		"moody_raised_stat": -1, "moody_raised_amount": 0,
		"moody_lowered_stat": -1, "moody_lowered_amount": 0,
		"heal_amount": 0, "damage_amount": 0,
		"cured_status": false, "healed_ally_status": false,
		"slow_start_ended": false,
	}
	if pokemon.fainted:
		return result
	var id: int = effective_ability_id(pokemon, ng_active)
	if id == ABILITY_NONE:
		return result
	if id == ABILITY_SPEED_BOOST and not pokemon.switched_in_this_turn:
		result["speed_boost_change"] = StatusManager.apply_stat_change(
				pokemon, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
	if id == ABILITY_MOODY:
		_apply_moody(pokemon, result, force_moody_raise, force_moody_lower, ng_active)
	if id == ABILITY_TRUANT:
		pokemon.truant_loafing = not pokemon.truant_loafing
	# M17n-5: Slow Start — post-decrement check, matching source's
	# `if (timer > 0 && --timer == 0)` shape exactly (battle_util.c L3649-3654).
	if id == ABILITY_SLOW_START and pokemon.slow_start_timer > 0:
		pokemon.slow_start_timer -= 1
		if pokemon.slow_start_timer == 0:
			result["slow_start_ended"] = true

	var not_at_max: bool = pokemon.current_hp < pokemon.max_hp
	if id == ABILITY_RAIN_DISH and weather == DamageCalculator.WEATHER_RAIN and not_at_max:
		result["heal_amount"] = max(1, pokemon.max_hp / 16)
	elif id == ABILITY_ICE_BODY and weather == DamageCalculator.WEATHER_HAIL and not_at_max:
		result["heal_amount"] = max(1, pokemon.max_hp / 16)
	elif id == ABILITY_DRY_SKIN:
		if weather == DamageCalculator.WEATHER_RAIN and not_at_max:
			result["heal_amount"] = max(1, pokemon.max_hp / 8)
		elif weather == DamageCalculator.WEATHER_SUN:
			result["damage_amount"] = max(1, pokemon.max_hp / 8)
	elif id == ABILITY_SOLAR_POWER and weather == DamageCalculator.WEATHER_SUN:
		# M17d: shares Dry Skin's SOLAR_POWER_HP_DROP label (battle_util.c L3660-3667) —
		# this is the ability the label is actually named after. Damage half only; the
		# ATK boost half lives in attack_modifier_uq412.
		result["damage_amount"] = max(1, pokemon.max_hp / 8)

	if id == ABILITY_HYDRATION and weather == DamageCalculator.WEATHER_RAIN \
			and pokemon.status != BattlePokemon.STATUS_NONE:
		result["cured_status"] = true
	elif id == ABILITY_SHED_SKIN and pokemon.status != BattlePokemon.STATUS_NONE:
		var ss_fires: bool = bool(force_shed_skin_roll) if force_shed_skin_roll != null \
				else (randi() % 3 == 0)
		if ss_fires:
			result["cured_status"] = true

	if id == ABILITY_HEALER and ally != null and not ally.fainted \
			and ally.status != BattlePokemon.STATUS_NONE:
		var h_fires: bool = bool(force_healer_roll) if force_healer_roll != null \
				else (randi() % 100 < 30)
		if h_fires:
			result["healed_ally_status"] = true

	return result


# M17n-7: Harvest — end-of-turn (THIRD_EVENT_BLOCK_ABILITIES, the same handler
# block Truant/Slow Start/Moody/Speed Boost fire from), a probabilistic chance to
# regenerate the LAST consumed berry back onto the holder's item slot. Source:
# `AbilityBattleEffects`'s `ABILITY_HARVEST` case (battle_util.c L3531-3539):
#   (IsBattlerWeatherAffected(holdEffect, weather, B_WEATHER_SUN) ||
#    RandomPercentage(RNG_HARVEST, 50))
#   && item == ITEM_NONE
#   && GetItemPocket(usedHeldItem) == POCKET_BERRIES
# Confirmed from source, not assumed: the proc rate is a FLAT 50% normally, but
# GUARANTEED (100%) under sun — `IsBattlerWeatherAffected` (battle_util.c L9293-9302)
# respects the holder's own Utility Umbrella (strips the sun bonus) and, since
# `weather` here is the caller-supplied EFFECTIVE weather (this project's
# `_effective_weather()` convention — Air Lock/Cloud Nine already negate it to
# WEATHER_NONE before this function ever sees it), Air Lock/Cloud Nine correctly
# also strip the sun bonus for free, with zero extra plumbing.
# `mon.held_item == null` and `mon.last_consumed_berry != null` are this project's
# equivalents of `item == ITEM_NONE` / `GetItemPocket(usedHeldItem) == POCKET_BERRIES`
# — the latter needs no separate "is this a berry" check HERE since [M18-patch-1]
# moved that gate to `last_consumed_berry`'s own single assignment site in
# `_consume_item` (battle_manager.gd): it's only ever set when the consumed item's
# `pocket == ItemManager.POCKET_BERRIES`, so by the time this function reads it,
# it's already guaranteed to be a real berry or null. (Previously this comment
# claimed no gate was needed because every consumed item WAS a berry at the time —
# that assumption went stale once [M18n]/[M18o] added non-berry consumables; fixed
# at the shared assignment point rather than re-checking in every reader.)
# `forced_roll` mirrors `quick_draw_activates`'s established seam shape exactly.
static func harvest_activates(
		mon: BattlePokemon, weather: int = DamageCalculator.WEATHER_NONE,
		ng_active: bool = false, forced_roll: Variant = null) -> bool:
	if effective_ability_id(mon, ng_active) != ABILITY_HARVEST:
		return false
	if mon.held_item != null:
		return false
	if mon.last_consumed_berry == null:
		return false
	if forced_roll != null:
		return bool(forced_roll)
	var sun_active: bool = weather == DamageCalculator.WEATHER_SUN \
			and not ItemManager.blocks_weather_modifier(mon, ng_active)
	if sun_active:
		return true
	return randi() % 100 < 50


# M17n-7: Cud Chew — a one-turn arm/fire cycle, genuinely distinct from Harvest's
# shape: it never regenerates the physical item, only re-runs the SAME berry's
# effect script exactly once, one full turn after the original consumption. Source:
# `AbilityBattleEffects`'s `ABILITY_CUD_CHEW` case (battle_util.c L3695-3707):
#   if (volatiles.cudChew == TRUE) { cudChew = FALSE; <re-run usedHeldItem's effect
#     script>; usedHeldItem = ITEM_NONE; }
#   else if (!cudChew && GetItemPocket(usedHeldItem) == POCKET_BERRIES) { cudChew = TRUE; }
# The if/else-if structure means arming and firing can never happen in the SAME
# end-of-turn pass — a berry eaten on turn N arms at the end of turn N and fires at
# the end of turn N+1, never turn N itself and never turn N+2 (once `cud_chew_armed`
# is true, the arm branch is unreachable until fire clears it back to false, and
# firing also clears `last_consumed_berry` so a new arm needs a genuinely NEW
# consumption, not a repeat of the same one).
# Returns "" (no-op), "arm", or "fire" for the caller (BattleManager) to act on —
# the actual re-trigger (which berry-effect function to call, healing/curing,
# signal emission) needs access to ItemManager/signals this stateless function
# doesn't have. The `last_consumed_berry != null` check below needs no separate
# berry gate of its own — [M18-patch-1] made that guarantee at the field's single
# assignment site in `_consume_item`, matching source's own `GetItemPocket(...) ==
# POCKET_BERRIES` check cited above.
static func cud_chew_check(mon: BattlePokemon, ng_active: bool = false) -> String:
	if effective_ability_id(mon, ng_active) != ABILITY_CUD_CHEW:
		return ""
	if mon.cud_chew_armed:
		return "fire"
	if mon.last_consumed_berry != null:
		return "arm"
	return ""


static func _apply_moody(
		pokemon: BattlePokemon, result: Dictionary,
		force_raise: Variant, force_lower: Variant, ng_active: bool = false) -> void:
	var valid_to_raise: Array = []
	for i in range(7):
		if pokemon.stat_stages[i] < 6:
			valid_to_raise.append(i)

	var raised_stat: int = -1
	if valid_to_raise.size() > 0:
		raised_stat = int(force_raise) if (force_raise != null and int(force_raise) in valid_to_raise) \
				else valid_to_raise[randi() % valid_to_raise.size()]
		result["moody_raised_stat"] = raised_stat
		result["moody_raised_amount"] = StatusManager.apply_stat_change(pokemon, raised_stat, 2, null, ng_active)

	var valid_to_lower: Array = []
	for i in range(7):
		if i != raised_stat and pokemon.stat_stages[i] > -6:
			valid_to_lower.append(i)

	if valid_to_lower.size() > 0:
		var lowered_stat: int = int(force_lower) if (force_lower != null and int(force_lower) in valid_to_lower) \
				else valid_to_lower[randi() % valid_to_lower.size()]
		result["moody_lowered_stat"] = lowered_stat
		result["moody_lowered_amount"] = StatusManager.apply_stat_change(pokemon, lowered_stat, -1, null, ng_active)


# ── Tier 3: Contact / trigger-based effects (ABILITYEFFECT_MOVE_END) ─────────

# Fire contact-based ability effects on the defender when the attacker hits them.
# Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...) —
#   Only fires when IsBattlerTurnDamaged (damage > 0) AND !attacker.attackerInParty.
#   Contact check: !CanBattlerAvoidContactEffects = IsMoveMakingContact (L5729):
#     MoveMakesContact(move) (our move.makes_contact) AND !HOLD_EFFECT_PROTECTIVE_PADS
#     AND !ABILITY_LONG_REACH. M8 scope has no items/Long Reach, so contact = makes_contact.
#
# Implementations:
#   ABILITY_ROUGH_SKIN (L3965): B_ROUGH_SKIN_DMG >= GEN_4 → attacker.maxHP / 8
#   ABILITY_IRON_BARBS (L17a, same case block as Rough Skin — battle_util.c L3965-3966:
#                        "case ABILITY_ROUGH_SKIN: case ABILITY_IRON_BARBS:" — identical
#                        effect, same maxHP/8 damage, same conditions)
#   ABILITY_STATIC     (L4091): B_ABILITY_TRIGGER_CHANCE >= GEN_4 → RandomPercentage 30%
#                                → paralyze attacker if CanBeParalyzed
#   ABILITY_FLAME_BODY (L4114): same 30% roll → burn attacker if CanBeBurned
#   ABILITY_GOOEY / ABILITY_TANGLING_HAIR (M17b, L3923-3958, shared case block):
#     unconditional (no RNG roll) attacker Speed -1. Source simulates the change first
#     (StatChange.onlyChecking) to decide whether to show a message; this project just
#     calls apply_stat_change directly and reports whatever actually happened (0 if the
#     attacker's own ability, e.g. Clear Body, blocked it — correctly composes with the
#     M17b change-blocking abilities without any Gooey-specific bypass logic).
#   ABILITY_POISON_POINT (M17c, L4068-4090): same 30% roll shape as Static — poison the
#     ATTACKER on contact if CanBePoisoned (this project's existing Poison/Steel
#     type-immunity check in try_apply_status already covers that). Defender-keyed
#     (dispatched via `id`, same as every other ability in this function), matching
#     source's own `ABILITYEFFECT_MOVE_END` pass (the defender's ability reacting to
#     being hit).
#   ABILITY_POISON_TOUCH ([M18.5a], L4281-4299): a GENUINELY DIFFERENT dispatch shape,
#     corrected from a [M17c]-era bug that merged it into the Poison Point branch above.
#     Source dispatches Poison Touch via the SEPARATE `ABILITYEFFECT_MOVE_END_ATTACKER`
#     pass — keyed on the ATTACKER's ability, not the defender's — and poisons the
#     DEFENDER (`gEffectBattler = gBattlerTarget`), not the attacker (confirmed via
#     `CanBePoisoned`'s battlerAtk/battlerDef argument order). Checked independently,
#     before `id` is even computed, since it must not be blocked by a defender with no
#     ability of its own. Also gated by `IsMoveEffectBlockedByTarget` (L9811-9825,
#     Shield Dust/Covert Cloak) against the DEFENDER — a real gap found and left
#     unfixed at [M18x], closed here alongside the direction fix since both share the
#     identical root cause and the correct gate insertion point only became clear once
#     the direction was corrected (see [M18.5a] decisions.md entry).
#   ABILITY_EFFECT_SPORE (M17c, L4024-4066): weighted 3-way roll — GEN_LATEST config
#     (B_ABILITY_TRIGGER_CHANCE >= GEN_4 but NOT == GEN_4, matching the same generation
#     branch Shed Skin uses) gives 9% poison / 10% paralysis / 11% sleep (not an even
#     10/10/10 split — a genuine GEN_5+ quirk in source's cutoffs) out of a roll in
#     0-99, else no effect. Also requires `IsAffectedByPowderMove(gBattlerAttacker,
#     abilityAtk, holdEffectAtk)` (L4032) — confirmed via direct source read this is
#     evaluated against the ATTACKER (the mon making contact, who is the one at risk
#     of being afflicted), not the Effect Spore holder itself. [M17.5 Batch Fix]: this
#     project's general powder-move system (`AbilityManager.blocks_move_flag`) now
#     covers Overcoat + Grass-type; both of the ATTACKER-side exemptions
#     `IsAffectedByPowderMove` encodes are applied directly below (Safety Goggles,
#     source's third exemption, is item-scope and not implemented in this project).
#     Overcoat is checked via `effective_ability_id` with no Mold-Breaker `attacker`
#     param — like Scrappy's Ghost-bypass and Magic Guard's self-protection, this is
#     the attacker's OWN ability protecting itself, never "broken through" by the
#     Effect Spore holder's side (Mold Breaker only ever bypasses a DEFENDER's ability
#     from an attacking move's perspective, which isn't this shape) — but IS still
#     subject to Neutralizing Gas suppression like any other ability.
#
# Returns a Dictionary:
#   "rough_skin_damage" : int    — HP deducted from attacker (0 if none)
#   "status_applied"    : int    — BattlePokemon.STATUS_* inflicted on attacker (0 = none)
#   "speed_change"       : int   — Speed stage change applied to attacker (0 = none)
#   "ability_name"      : String — key identifying which ability fired ("" if none)
#   "attract_inflicted" : bool   — [M18.5d-2] Cute Charm infatuated the attacker
#
# force_contact_roll: null = RNG; true = force trigger; false = suppress (Static/Flame
#   Body/Poison Point/Poison Touch's shared 30% roll).
# force_effect_spore_roll: null = RNG; int 0-99 = pin the underlying roll value.
# attacker_ally: [M18.5d-2] the ATTACKER's doubles partner (null in singles) — needed
#   only for Cute Charm's Aroma-Veil-on-the-victim's-side check (attract_block_reason).
static func try_contact_effects(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		damage: int,
		force_contact_roll: Variant = null,
		force_effect_spore_roll: Variant = null,
		ng_active: bool = false,
		attacker_ally: BattlePokemon = null) -> Dictionary:

	var result := {
		"rough_skin_damage": 0, "status_applied": 0, "speed_change": 0, "ability_name": "",
		"mummy_overwritten_ability": -1, "wandering_spirit_swapped": false,
		"pickpocket_stole": false, "attract_inflicted": false,
	}
	# M17n-5: routed through move_makes_contact (not the raw flag) so an attacking
	# Long Reach holder correctly disables every contact-triggered ability in this
	# dispatch (Static/Flame Body/Rough Skin/Poison Point/Poison Touch/Effect
	# Spore/Cursed Body/Toxic Debris/Iron Barbs/Rocky Payload/Pickpocket/Mummy/
	# Wandering Spirit/Gooey/Tangling Hair/Stamina/Water Compaction/Cotton
	# Down/Steam Engine) via this ONE shared chokepoint — matching source's own
	# single-`IsMoveMakingContact`-consumer design rather than touching each ability's
	# individual dispatch.
	# M18p: upgraded to move_triggers_contact_retaliation, which additionally gates
	# on the attacker's own Protective Pads — every ability this function dispatches
	# is a genuine contact-RETALIATION effect in source's CanBattlerAvoidContactEffects
	# sense (confirmed by reading every one of its call sites directly), so this one
	# gate correctly covers all of them at once.
	if not move_triggers_contact_retaliation(attacker, move, ng_active):
		return result
	if damage <= 0:
		return result
	if attacker.fainted:
		return result

	# [M18.5a] Poison Touch: ATTACKER-keyed (unlike every other check below, all
	# defender-keyed), so it must be checked independently of `id` and BEFORE the
	# `id == ABILITY_NONE` early return just below — a defender with no ability of
	# its own must not block an attacking Poison Touch holder from being checked.
	# Poisons the DEFENDER (see this function's header comment for the full source
	# citation and the [M17c]->[M18x]->[M18.5a] bug history). Gated by Shield
	# Dust/Covert Cloak, checked against the DEFENDER (the one about to receive the
	# poison), mirroring `StatusManager.try_secondary_effect`'s existing gate exactly.
	# `defender.current_hp > 0` (not `.fainted`, per this project's established
	# synchronous-aliveness convention) since the defender can faint from this exact
	# hit before this dispatch runs.
	# Known limitation, flagged not fixed (out of scope for this bugfix-only tier):
	# if the ATTACKER holds Poison Touch AND the DEFENDER independently holds Poison
	# Point, only Poison Touch is checked/applied — this function's single-effect-
	# per-call return shape (shared by every branch below) has no way to report two
	# independently-triggered abilities from one contact hit. A rare double-
	# ability-holder edge case, not a masking of either ability's own correctness.
	if effective_ability_id(attacker, ng_active) == ABILITY_POISON_TOUCH \
			and defender.current_hp > 0:
		var pt_blocked: bool = \
				effective_ability_id(defender, ng_active, attacker, move) == ABILITY_SHIELD_DUST \
				or ItemManager.holds_covert_cloak(defender, ng_active)
		if not pt_blocked:
			var pt_fires: bool = _roll_contact(force_contact_roll, 30)
			if pt_fires and StatusManager.try_apply_status(defender, BattlePokemon.STATUS_POISON):
				result["status_applied"] = BattlePokemon.STATUS_POISON
				result["ability_name"] = "poison_touch"
				return result

	var id: int = effective_ability_id(defender, ng_active)
	if id == ABILITY_NONE:
		return result

	# M17j: Pickpocket — defender (the Pickpocket holder, hit by this contact move) steals
	# the attacker's item, if the defender currently holds none. Gated on Sticky Hold via
	# the shared `_try_steal_item` primitive (checked on the attacker being stolen from).
	if id == ABILITY_PICKPOCKET:
		if _try_steal_item(defender, attacker, ng_active):
			result["pickpocket_stole"] = true
			result["ability_name"] = "pickpocket"
		return result

	if id == ABILITY_GOOEY or id == ABILITY_TANGLING_HAIR:
		var speed_actual: int = StatusManager.apply_stat_change(
				attacker, BattlePokemon.STAGE_SPEED, -1, null, ng_active)
		if speed_actual != 0:
			result["speed_change"] = speed_actual
			result["ability_name"] = "tangling_hair" if id == ABILITY_TANGLING_HAIR else "gooey"
		return result

	# Rough Skin / Iron Barbs: attacker takes maxHP/8 on contact (B_ROUGH_SKIN_DMG >= GEN_4 = /8).
	# Source: L3965-3975 (shared case block) GetNonDynamaxMaxHP(gBattlerAttacker) / 8
	# M17n-9: Magic Guard now gates this — it's the ATTACKER's own ability (the one
	# taking the damage), not the Rough Skin/Iron Barbs holder's, confirmed from
	# source's own `IsAbilityAndRecord(gBattlerAttacker, ...MAGIC_GUARD)` check
	# (battle_util.c L3972) sitting inside this exact case block.
	if id == ABILITY_ROUGH_SKIN or id == ABILITY_IRON_BARBS:
		if blocks_indirect_damage(attacker, ng_active):
			return result
		var rs_dmg: int = attacker.max_hp / 8
		if rs_dmg > 0:
			result["rough_skin_damage"] = rs_dmg
			result["ability_name"] = "iron_barbs" if id == ABILITY_IRON_BARBS else "rough_skin"
		return result

	# Static: 30% chance to paralyze attacker (if not already statused, not Electric-type).
	# Source: L4091; CanBeParalyzed = not Electric-type + no status (our try_apply_status handles this).
	if id == ABILITY_STATIC:
		var fires: bool = _roll_contact(force_contact_roll, 30)
		if fires and StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_PARALYSIS):
			result["status_applied"] = BattlePokemon.STATUS_PARALYSIS
			result["ability_name"] = "static"
		return result

	# Flame Body: 30% chance to burn attacker on contact.
	# Source: L4114; CanBeBurned = not Fire-type + no status (try_apply_status handles this).
	if id == ABILITY_FLAME_BODY:
		var fires: bool = _roll_contact(force_contact_roll, 30)
		if fires and StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_BURN):
			result["status_applied"] = BattlePokemon.STATUS_BURN
			result["ability_name"] = "flame_body"
		return result

	# M17c: Poison Point — 30% chance to poison the attacker on contact. (Poison
	# Touch's ATTACKER-keyed check now lives independently above — see [M18.5a].)
	if id == ABILITY_POISON_POINT:
		var fires: bool = _roll_contact(force_contact_roll, 30)
		if fires and StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_POISON):
			result["status_applied"] = BattlePokemon.STATUS_POISON
			result["ability_name"] = "poison_point"
		return result

	# [M18.5d-2] Cute Charm — 30% chance to infatuate the ATTACKER on contact (same
	# 30% roll shape as Static/Flame Body/Poison Point, defender-keyed exactly like
	# them). Source: battle_util.c L4130-4146 (ABILITY_CUTE_CHARM case, the same
	# switch). Reuses StatusManager.try_apply_attract (Attract's own infliction
	# function) rather than duplicating its already-required infatuation/gender/
	# block checks — `inflictor` is `defender` (the Cute Charm holder), `victim` is
	# `attacker` (who made contact and is about to be infatuated). No
	# `attacker`/`attacker_move` Mold-Breaker params passed to try_apply_attract:
	# not a move, and Cute Charm itself has no `.breakable` flag either (matching
	# this whole dispatch's `id` computation, which likewise passes no `attacker`
	# param — Mold Breaker never bypasses this trigger). Source's blocked/failed
	# outcomes (Oblivious, Aroma Veil, same-gender/genderless) all silently no-op
	# with no message — unlike Attract's own move script, Cute Charm has no
	# distinguishable "protected" popup, so this project doesn't distinguish WHY
	# it failed either, matching that silent shape exactly.
	if id == ABILITY_CUTE_CHARM:
		var fires: bool = _roll_contact(force_contact_roll, 30)
		if fires:
			var cc_result: String = StatusManager.try_apply_attract(
					attacker, defender, attacker_ally, ng_active)
			if cc_result == "":
				result["attract_inflicted"] = true
				result["ability_name"] = "cute_charm"
		return result

	# M17c: Effect Spore — weighted 3-way roll (9% poison / 10% paralysis / 11% sleep),
	# skipped entirely if the attacker is immune to powder. [M17.5 Batch Fix]: added the
	# attacker's own Overcoat exemption alongside the pre-existing Grass-type one — both
	# are the ATTACKER-side halves of `IsAffectedByPowderMove` (see this function's own
	# header comment above for the full citation and Mold-Breaker/NG reasoning).
	if id == ABILITY_EFFECT_SPORE and TypeChart.TYPE_GRASS not in attacker.species.types \
			and effective_ability_id(attacker, ng_active) != ABILITY_OVERCOAT:
		var roll: int = int(force_effect_spore_roll) if force_effect_spore_roll != null \
				else randi() % 100
		if roll < 9:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_POISON):
				result["status_applied"] = BattlePokemon.STATUS_POISON
				result["ability_name"] = "effect_spore"
		elif roll < 19:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_PARALYSIS):
				result["status_applied"] = BattlePokemon.STATUS_PARALYSIS
				result["ability_name"] = "effect_spore"
		elif roll < 30:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_SLEEP):
				result["status_applied"] = BattlePokemon.STATUS_SLEEP
				result["ability_name"] = "effect_spore"
		return result

	# M17h: Wandering Spirit — bidirectional ability swap with the attacker. Checked
	# before Mummy/Lingering Aroma below since `id` here is already known to be exactly
	# one ability at a time (this whole function dispatches on a single `id` value), so
	# ordering between these two branches has no observable effect either way.
	if id == ABILITY_WANDERING_SPIRIT:
		if try_wandering_spirit_swap(defender, attacker, move, damage, ng_active):
			result["wandering_spirit_swapped"] = true
			result["ability_name"] = "wandering_spirit"
		return result

	# M17h: Mummy / Lingering Aroma — one-directional overwrite of the attacker's ability.
	if id == ABILITY_MUMMY or id == ABILITY_LINGERING_AROMA:
		var new_ability: int = try_mummy_overwrite(defender, attacker, move, damage, ng_active)
		if new_ability != -1:
			result["mummy_overwritten_ability"] = new_ability
			result["ability_name"] = "lingering_aroma" if id == ABILITY_LINGERING_AROMA else "mummy"
		return result

	return result


# M17b: reactive effects triggered by ANY damaging hit landing on the ability holder —
# NOT gated on contact. This is a genuinely different dispatch shape than
# try_contact_effects above: source's AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...)
# is called after EVERY damaging hit regardless of contact (battle_move_resolution.c
# L2696), and individual cases self-gate on contact only where the real ability needs
# it (Mummy/Wandering Spirit/Rough Skin/Iron Barbs/Gooey/Tangling Hair/Static/Flame
# Body all inline-check CanBattlerAvoidContactEffects; Justified/Rattled/Water
# Compaction/Stamina/Weak Armor/Anger Point/Cotton Down/Steam Engine/Thermal Exchange
# do NOT). The original M8 comment on try_contact_effects overgeneralized this as a
# blanket contact requirement — that happened to be true for M8's specific subset, not
# a rule for the whole dispatch. Corrected here rather than silently perpetuated.
#
# Source citations (all battle_util.c):
#   ABILITY_JUSTIFIED (L3772-3783): moveType==DARK, Atk not maxed → Atk +1.
#   ABILITY_RATTLED (L3790-3801, hit half only — the OTHER half, "being Intimidated",
#     is in try_switch_in): moveType in {Dark,Bug,Ghost}, Speed not maxed → Spe +1.
#   ABILITY_WATER_COMPACTION (L3802-3813): moveType==WATER, Def not maxed → Def +2.
#   ABILITY_STAMINA (L3814-3825): ANY damaging hit (attacker != defender guard is
#     redundant here — this project has no self-hit-triggers-Stamina path), Def not
#     maxed → Def +1.
#   ABILITY_WEAK_ARMOR (L3826-3841): IsBattleMovePhysical, (Speed not maxed OR Def not
#     minned) → Def -1, Spe +2 (B_WEAK_ARMOR_SPEED >= GEN_7, this project's config).
#   ABILITY_ANGER_POINT (L3911-3920): critical hit received, Atk not maxed → Atk set to
#     absolute MAX (+12 raw stages = our +6, i.e. "set to +6" not "add to current").
#   ABILITY_BERSERK (L3732-3742): HP crossed from >50% to <=50% THIS hit specifically
#     (not merely "is currently <=50%"), SpA not maxed → SpA +1.
#   ABILITY_ANGER_SHELL (L3743-3766): same >50%→<=50% crossing check → Def -1, SpDef -1,
#     Atk +1, SpA +1, Spe +1, each independently gated on not already at its limit.
#   ABILITY_STEAM_ENGINE (L4169-4179): moveType in {Fire,Water}, Speed not maxed →
#     Spe set to absolute MAX (+6, "SetStatChange(battler, STAT_SPEED, 6)" is a flat
#     +6 stage jump, not a set-to-max like Anger Point — same numeric outcome from any
#     non-maxed starting stage since +6 always saturates, but conceptually an addition).
#   ABILITY_THERMAL_EXCHANGE (L4222-4231): moveType==FIRE, Atk not maxed → Atk +1.
#     (Thermal Exchange's OTHER half — curing the holder's own burn — mirrors Water
#     Veil/Water Bubble's shape and isn't wired here since no in-battle path in this
#     project can inflict burn on a Thermal-Exchange-immune-to-burn holder in a way
#     that's distinguishable from just not being burned in the first place; flagged as
#     a known simplification, not silently dropped.)
#   ABILITY_COTTON_DOWN (L4155-4165): ANY damaging hit → ALL OTHER live battlers'
#     Speed -1 (field-wide, not just the attacker). This function can only see the
#     attacker/defender pair, so it reports a bool flag; BattleManager applies the
#     Speed -1 to the attacker AND the attacker's ally (via _get_ally), matching
#     source's "every battler except the holder" loop.
#   ABILITY_CURSED_BODY (M17c, L3843-3858): any damaging hit landing (NOT contact-gated
#     — no CanBattlerAvoidContactEffects check in source, unlike Mummy/Static/etc. right
#     next to it in the same switch), attacker not already disabled, move used isn't
#     Struggle, 30% chance → disables the attacker's just-used move for 4 turns (same
#     B_DISABLE_TIMER this project's Disable move already uses). Reports a bool flag
#     only; BattleManager applies `disabled_move`/`disable_turns` directly, mirroring how
#     the Disable move itself is applied in battle_manager.gd (no shared helper exists
#     for "apply a disable," so this doesn't introduce one just for this one extra caller).
#   ABILITY_TOXIC_DEBRIS (M17c, L4246-4259): IsBattleMovePhysical, toxic spikes on the
#     ATTACKER's side not already at 2 layers → sets one layer. Reuses M16d's EXISTING
#     `_side_conditions[side]["toxic_spikes_layers"]` directly — reports a bool flag since
#     side-condition state lives in BattleManager, not AbilityManager.
#   ABILITY_SAND_SPIT (M17n-2, L4181-4196): ANY damaging hit landing (not contact-gated,
#     `IsBattlerTurnDamaged` — already exactly this function's own `damage > 0` gate) →
#     attempts to set Sandstorm. Reports a bool flag only; BattleManager calls the
#     EXISTING `try_set_weather(WEATHER_SANDSTORM, defender)` (the same function
#     Drizzle/Drought/Sand Stream already use), which already no-ops if Sandstorm is
#     already active — so the "already sandstorm" gate doesn't need to be re-implemented
#     here. Source's "blocked by Primal weather" branch is confirmed N/A: this project
#     has no distinct Primal-weather value at all (`[M17d]`'s Primordial Sea/Desolate
#     Land/Delta Stream reuse the ordinary WEATHER_RAIN/WEATHER_SUN/WEATHER_STRONG_WINDS
#     constants directly), so there's nothing for a Primal-weather check to distinguish.
#
# hp_before_hit: defender's current_hp BEFORE this hit's damage was applied — needed
#   only for Berserk/Anger Shell's ">50% before, <=50% after" crossing check.
# is_crit: whether this hit was a critical hit (for Anger Point).
# force_cursed_body_roll: null = RNG; true/false = pin Cursed Body's 30% roll.
#
# Returns a Dictionary with one key per ability (0/false = did not fire):
#   "justified_change", "rattled_change", "water_compaction_change", "stamina_change",
#   "weak_armor_def_change", "weak_armor_speed_change", "anger_point_change",
#   "berserk_change", "steam_engine_change", "thermal_exchange_change" : int
#   "anger_shell_changes" : Dictionary {stat_idx: actual_change, ...} (only nonzero entries)
#   "cotton_down_fired" : bool
#   "cursed_body_fired" : bool
#   "toxic_debris_fired" : bool
#   "sand_spit_fired" : bool
#   "color_change_new_type" : int (TypeChart.TYPE_NONE = did not fire)
static func try_hit_reactive_effects(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		damage: int,
		hp_before_hit: int,
		is_crit: bool,
		force_cursed_body_roll: Variant = null,
		ng_active: bool = false) -> Dictionary:

	var result := {
		"justified_change": 0, "rattled_change": 0, "water_compaction_change": 0,
		"stamina_change": 0, "weak_armor_def_change": 0, "weak_armor_speed_change": 0,
		"anger_point_change": 0, "berserk_change": 0, "steam_engine_change": 0,
		"thermal_exchange_change": 0, "anger_shell_changes": {}, "cotton_down_fired": false,
		"cursed_body_fired": false, "toxic_debris_fired": false, "sand_spit_fired": false,
		"color_change_new_type": TypeChart.TYPE_NONE,
	}
	if damage <= 0:
		return result
	if defender.fainted:
		return result

	# M17g: Thermal Exchange is the one ability in this function flagged `.breakable =
	# TRUE` in source (every other reactive trigger here — Justified/Rattled/Water
	# Compaction/Stamina/Weak Armor/Anger Point/Berserk/Anger Shell/Steam Engine/Cotton
	# Down/Cursed Body/Toxic Debris — confirmed NOT breakable), so this is the only
	# function in this reactive-trigger group where Mold Breaker's attacker-scoped
	# bypass can matter; `attacker` is threaded through for exactly that reason.
	var id: int = effective_ability_id(defender, ng_active, attacker)
	if id == ABILITY_NONE:
		return result

	if id == ABILITY_JUSTIFIED and move.type == TypeChart.TYPE_DARK:
		result["justified_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_ATK, 1, null, ng_active)
		return result

	if id == ABILITY_RATTLED and (move.type == TypeChart.TYPE_DARK
			or move.type == TypeChart.TYPE_BUG or move.type == TypeChart.TYPE_GHOST):
		result["rattled_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
		return result

	if id == ABILITY_WATER_COMPACTION and move.type == TypeChart.TYPE_WATER:
		result["water_compaction_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_DEF, 2, null, ng_active)
		return result

	if id == ABILITY_STAMINA:
		result["stamina_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_DEF, 1, null, ng_active)
		return result

	if id == ABILITY_WEAK_ARMOR and move.category == 0:
		result["weak_armor_def_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_DEF, -1, null, ng_active)
		result["weak_armor_speed_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_SPEED, 2, null, ng_active)
		return result

	if id == ABILITY_ANGER_POINT and is_crit:
		result["anger_point_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_ATK, 12, null, ng_active)
		return result

	var crossed_half: bool = hp_before_hit > defender.max_hp / 2 \
			and defender.current_hp <= defender.max_hp / 2
	if id == ABILITY_BERSERK and crossed_half:
		result["berserk_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_SPATK, 1, null, ng_active)
		return result

	if id == ABILITY_ANGER_SHELL and crossed_half:
		var changes := {}
		var def_c: int = StatusManager.apply_stat_change(defender, BattlePokemon.STAGE_DEF, -1, null, ng_active)
		if def_c != 0:
			changes[BattlePokemon.STAGE_DEF] = def_c
		var spdef_c: int = StatusManager.apply_stat_change(defender, BattlePokemon.STAGE_SPDEF, -1, null, ng_active)
		if spdef_c != 0:
			changes[BattlePokemon.STAGE_SPDEF] = spdef_c
		var atk_c: int = StatusManager.apply_stat_change(defender, BattlePokemon.STAGE_ATK, 1, null, ng_active)
		if atk_c != 0:
			changes[BattlePokemon.STAGE_ATK] = atk_c
		var spatk_c: int = StatusManager.apply_stat_change(defender, BattlePokemon.STAGE_SPATK, 1, null, ng_active)
		if spatk_c != 0:
			changes[BattlePokemon.STAGE_SPATK] = spatk_c
		var speed_c: int = StatusManager.apply_stat_change(defender, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
		if speed_c != 0:
			changes[BattlePokemon.STAGE_SPEED] = speed_c
		result["anger_shell_changes"] = changes
		return result

	if id == ABILITY_STEAM_ENGINE and (move.type == TypeChart.TYPE_FIRE or move.type == TypeChart.TYPE_WATER):
		result["steam_engine_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_SPEED, 6, null, ng_active)
		return result

	if id == ABILITY_THERMAL_EXCHANGE and move.type == TypeChart.TYPE_FIRE:
		result["thermal_exchange_change"] = StatusManager.apply_stat_change(
				defender, BattlePokemon.STAGE_ATK, 1, null, ng_active)
		return result

	if id == ABILITY_COTTON_DOWN:
		result["cotton_down_fired"] = true
		return result

	if id == ABILITY_CURSED_BODY and not attacker.fainted and not move.is_struggle \
			and attacker.disabled_move == null:
		var cb_fires: bool = bool(force_cursed_body_roll) if force_cursed_body_roll != null \
				else (randi() % 100 < 30)
		if cb_fires:
			result["cursed_body_fired"] = true
		return result

	if id == ABILITY_TOXIC_DEBRIS and move.category == 0:
		result["toxic_debris_fired"] = true
		return result

	if id == ABILITY_SAND_SPIT:
		result["sand_spit_fired"] = true
		return result

	# M17n-4: Color Change — the holder's own type changes to match the type of the
	# damaging move that just hit it. Source: MoveEndColorChange/AbilityBattleEffects
	# case ABILITY_COLOR_CHANGE (battle_util.c L3715-3729): IsBattlerTurnDamaged (this
	# function's own `damage <= 0` early return, plus the went-to-Substitute early
	# return at this function's ONE call site in `_do_damaging_hit`, already cover
	# EXCLUDING_SUBSTITUTES for free — a Substitute-absorbed hit never reaches this
	# function at all), not already that type, not Struggle, not Stellar/Mystery
	# (TYPE_STELLAR is a defined constant in this project's TypeChart but no move or
	# Pokemon actually uses it — no Tera scope — so this exclusion is currently
	# unreachable in practice but checked for source fidelity anyway, same as the
	# Mystery/Struggle check which IS reachable since this project's Struggle is
	# modeled as TYPE_MYSTERY). Confirmed via source NOT to route through the
	# Mold-Breaker-aware `GetBattlerAbilityInternal` chokepoint — its ability value
	# comes from the plain per-battler `cv->abilities[]` array (GetBattlerAbility, no
	# attacker context) — so Mold Breaker never bypasses Color Change despite source's
	# `.breakable` flag... except source's actual data table has NO `.breakable` flag
	# on ABILITY_COLOR_CHANGE at all (re-verified narrowly after an earlier over-wide
	# grep bled in the NEXT table entry's flag) — doubly confirmed unreachable, by data
	# AND by dispatch path. Returns the new type (or TYPE_NONE if it doesn't fire);
	# BattleManager performs the actual `_set_mon_type` mutation and signal emit, same
	# division of responsibility as every other reactive trigger in this function.
	if id == ABILITY_COLOR_CHANGE and not move.is_struggle \
			and move.type != TypeChart.TYPE_MYSTERY and move.type != TypeChart.TYPE_STELLAR \
			and not (move.type in defender.species.types):
		result["color_change_new_type"] = move.type
		return result

	return result


static func _roll_contact(force: Variant, chance_pct: int) -> bool:
	if force != null:
		return bool(force)
	return randi() % 100 < chance_pct


# M17c: Cheek Pouch — heals maxHP/3 whenever the holder eats ANY berry.
# Source: battle_script_commands.c :: TryCheekPouch (L6175-6188): GetItemPocket(itemId)
#   == POCKET_BERRIES, not at max HP, not heal-blocked → heal maxHP/3.
# Every item this project's `BattleManager._consume_item` currently handles IS a berry
# (Lum/Sitrus/resist berries — the only consumed-item mechanics this codebase has), so
# there's no separate "is this a berry" gate to add; this reuses that single existing
# choke point directly rather than building a new "berry pocket" check.
# Returns the heal amount (0 = not this ability, or already at max HP).
static func cheek_pouch_heal(mon: BattlePokemon, ng_active: bool = false) -> int:
	if effective_ability_id(mon, ng_active) != ABILITY_CHEEK_POUCH:
		return 0
	if mon.current_hp >= mon.max_hp:
		return 0
	return max(1, mon.max_hp / 3)


# M17b: Moxie — Attack +1 for the Pokémon that just KO'd the opponent.
# Source: battle_util.c (L4467-4472): Moxie shares its dispatch case with Chilling
#   Neigh/As One ×2/Grim Neigh/Beast Boost (all excluded per docs/m17_recon.md
#   Section 13 — legendary/UB-exclusive), fired from a faint-triggered ability-effect
#   pass. This project doesn't have that generic pass, but it doesn't need one: M14b's
#   `_last_attacker` dict (built for Destiny Bond) already identifies the killer, and
#   is populated before `pokemon_fainted.emit()` fires (`_phase_faint_check`,
#   battle_manager.gd) — reusing it here is not new infrastructure.
# killer: the BattlePokemon whose hit caused the faint, or null if unknown (matches
#   _last_attacker.get(combatant, null) at the call site).
# Returns the actual Attack stage change (0 = nothing happened, including killer==null).
static func moxie_boost(killer: BattlePokemon, ng_active: bool = false) -> int:
	if killer == null or killer.fainted:
		return 0
	if effective_ability_id(killer, ng_active) != ABILITY_MOXIE:
		return 0
	return StatusManager.apply_stat_change(killer, BattlePokemon.STAGE_ATK, 1, null, ng_active)


# M17n-8: Damp — blocks Aftermath (and, if ever implemented, Explosion/Self-Destruct/
# Mind Blown style moves) from firing for ANYONE on the field, not just the Damp
# holder's own side. Source: `IsAbilityOnField` (battle_util.c L4895-4904), which reads
# through `GetBattlerAbility` (the suppression-aware accessor) — mirrors
# `is_neutralizing_gas_active`'s exact field-wide shape, but NG-aware unlike that one
# (Damp checking itself has no self-reference problem NG's own check has to avoid).
static func is_damp_active(combatants: Array, ng_active: bool = false) -> bool:
	for mon: BattlePokemon in combatants:
		if mon.fainted:
			continue
		if effective_ability_id(mon, ng_active) == ABILITY_DAMP:
			return true
	return false


# M17n-8: Aftermath / Innards Out — shared "on-faint-from-a-hit, retaliate against the
# attacker" shape, per this tier's own instruction to build one mechanism rather than
# duplicate the fainting-detection logic. Both require the fainted mon (`mon`) to have
# actually fainted FROM a hit (`killer` non-null, the same `_last_attacker` convention
# already used by Destiny Bond/Moxie above) and the killer to still be alive. They
# differ in two ways, confirmed from source rather than assumed identical:
#   - Contact requirement: Aftermath REQUIRES contact (source gates it behind the same
#     `CanBattlerAvoidContactEffects` check Rough Skin/Iron Barbs use); Innards Out has
#     NO such gate — it fires from ANY damaging hit, contact or not.
#   - Damage amount: Aftermath deals the KILLER's own max_hp/4 (source:
#     `GetNonDynamaxMaxHP(gBattlerAttacker) / 4`); Innards Out deals the FAINTED MON's
#     own HP immediately before the fatal hit (`hp_before_hit`) — NOT the move's raw
#     calculated damage, which can exceed the mon's actual remaining HP on an overkill
#     hit (source: `battle_script_commands.c` L1650-1653's `hpLost = hpBefore -
#     gBattleMons[battler].hp` capping, accumulated into `innardsOutHpLost` and
#     preferred over the raw `moveDamage` value whenever nonzero).
#   - Aftermath additionally requires no Damp holder anywhere on the field
#     (`IsAbilityOnField(ABILITY_DAMP)`, battle_util.c L3993-3997); Innards Out has no
#     such gate.
# Source: battle_util.c :: ABILITY_AFTERMATH case (L3986-4003), ABILITY_INNARDS_OUT
# case (L4007-4021).
# Returns {} if neither ability applies; otherwise {"ability_name": String, "damage": int}.
static func faint_retaliation_damage(
		mon: BattlePokemon, killer: BattlePokemon, move: MoveData, hp_before_hit: int,
		ng_active: bool = false, damp_active: bool = false) -> Dictionary:
	if killer == null or killer.fainted:
		return {}
	var id: int = effective_ability_id(mon, ng_active)
	if id == ABILITY_AFTERMATH:
		if damp_active:
			return {}
		# M18p: upgraded to move_triggers_contact_retaliation — Aftermath's own
		# contact gate is confirmed (this function's own doc comment above, citing
		# L3986-4003) to be the SAME CanBattlerAvoidContactEffects check Rough
		# Skin/Iron Barbs use, so a Protective-Pads-holding killer correctly
		# avoids Aftermath too.
		if not move_triggers_contact_retaliation(killer, move, ng_active):
			return {}
		return {"ability_name": "aftermath", "damage": killer.max_hp / 4}
	if id == ABILITY_INNARDS_OUT:
		return {"ability_name": "innards_out", "damage": hp_before_hit}
	return {}


# M17c: Anticipation (L3083-3119) / Forewarn (L3142-3150) / Frisk (L3121-3141) — all
# three fire on switch-in but source-verified to have NO mechanical battle-calc effect
# in a non-visual, text/state-driven engine: each one only decides WHICH message to show
# (Anticipation: "shuddered" if any opponent move would be super-effective or is an OHKO
# move; Forewarn: reveals the opponent's highest-power move; Frisk: reveals an opponent's
# held item). None of them change any stat, status, or field state. Per this tier's own
# instruction, these get a no-op registration rather than invented mechanical behavior —
# the ability IDs above are the actual "registration" (combined with their .tres entries
# via gen_abilities.py); no dedicated function is needed since there is nothing to gate
# or apply. Listed here so future work doesn't re-investigate whether they do anything.
const ABILITY_COSMETIC_INFO_ONLY: Array[int] = [
	ABILITY_ANTICIPATION, ABILITY_FOREWARN, ABILITY_FRISK,
]


# ── Synchronize ───────────────────────────────────────────────────────────────

# Attempt to reflect a status back to the attacker when the Synchronize holder
# receives one of: BURN, PARALYSIS, POISON, TOXIC.
# Source: battle_script_commands.c :: TrySynchronizeActivation (L2130–2162):
#   If effectAbility == ABILITY_SYNCHRONIZE and effect in {POISON,TOXIC,PARALYSIS,BURN}:
#     CanSetNonVolatileStatus(holder→attacker, effect) → schedule back-status.
#   B_SYNCHRONIZE_TOXIC >= GEN_5 (GEN_LATEST): TOXIC stays as TOXIC when reflected
#   (pre-Gen5 would downgrade TOXIC to POISON). Not applicable at GEN_LATEST.
# SLEEP and FREEZE are NOT reflected by Synchronize (not in the source's status list).
#
# holder   — the Pokémon with Synchronize that received the status
# attacker — the Pokémon that inflicted the status
# applied_status — the BattlePokemon.STATUS_* that was just applied to holder
#
# Returns the status that was successfully applied to attacker (0 = nothing).
static func try_synchronize(
		holder: BattlePokemon,
		attacker: BattlePokemon,
		applied_status: int,
		ng_active: bool = false) -> int:

	if effective_ability_id(holder, ng_active) != ABILITY_SYNCHRONIZE:
		return 0
	if holder == attacker:
		return 0

	# Synchronize fires for BURN, PARALYSIS, POISON, TOXIC.
	# Source: TrySynchronizeActivation L2143–2157: checks for MOVE_EFFECT_POISON,
	#   MOVE_EFFECT_TOXIC, MOVE_EFFECT_PARALYSIS, MOVE_EFFECT_BURN.
	if applied_status not in [
			BattlePokemon.STATUS_BURN,
			BattlePokemon.STATUS_PARALYSIS,
			BattlePokemon.STATUS_POISON,
			BattlePokemon.STATUS_TOXIC]:
		return 0

	if StatusManager.try_apply_status(attacker, applied_status):
		return applied_status
	return 0
