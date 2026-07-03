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
	if not move.makes_contact or damage <= 0 or attacker.fainted:
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
	if not move.makes_contact or damage <= 0 or attacker.fainted:
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
static func effective_ability_id(
		mon: BattlePokemon, ng_active: bool = false, attacker: BattlePokemon = null) -> int:
	if mon.ability == null:
		return ABILITY_NONE
	var id: int = mon.ability.ability_id
	if ng_active and id != ABILITY_NEUTRALIZING_GAS and not mon.ability.cant_be_suppressed:
		return ABILITY_NONE
	if attacker != null and attacker != mon and mon.ability.breakable:
		var attacker_id: int = effective_ability_id(attacker, ng_active)
		if attacker_id == ABILITY_MOLD_BREAKER:
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
static func attack_modifier_uq412(
		attacker: BattlePokemon, move: MoveData,
		weather: int = DamageCalculator.WEATHER_NONE, ng_active: bool = false) -> int:
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

	return 4096


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
static func move_power_modifier_uq412(
		attacker: BattlePokemon, move: MoveData, weather: int,
		ally: BattlePokemon = null, ng_active: bool = false) -> int:
	var modifier: int = 4096

	var atk_ability_id: int = effective_ability_id(attacker, ng_active)
	if atk_ability_id != ABILITY_NONE:
		var id: int = atk_ability_id
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
		if id == ABILITY_TOUGH_CLAWS and move.makes_contact:
			modifier = DamageCalculator._uq412_multiply(modifier, 5325)
		if id == ABILITY_STEELWORKER and move.type == TypeChart.TYPE_STEEL:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)
		if id == ABILITY_STEELY_SPIRIT and move.type == TypeChart.TYPE_STEEL:
			modifier = DamageCalculator._uq412_multiply(modifier, 6144)

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
# Returns a plain percentage (100 = no change), matching StatusManager.check_accuracy's
# existing integer-percentage math style rather than the DamageCalculator's UQ4.12 style.
static func accuracy_modifier_percent(
		attacker: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var id: int = effective_ability_id(attacker, ng_active)
	if id == ABILITY_NONE:
		return 100
	if id == ABILITY_COMPOUND_EYES:
		return 130
	if id == ABILITY_HUSTLE and move.category == 0:
		return 80
	return 100


# M17a: whether the attacker's ability blocks standard move-recoil damage.
# Source: battle_move_resolution.c :: EFFECT_RECOIL/EFFECT_CHLOROBLAST handling
#   (L3373-3396): ABILITY_ROCK_HEAD (or Magic Guard, out of scope) → skip recoil entirely.
# Does NOT apply to Struggle recoil (a separate, unconditional code path in both source
# and this project — BattleManager's struggle handling is untouched) or to Life Orb
# recoil (an item effect, unaffected by Rock Head in source).
static func blocks_recoil(attacker: BattlePokemon, ng_active: bool = false) -> bool:
	return effective_ability_id(attacker, ng_active) == ABILITY_ROCK_HEAD


# Type immunity from an ability (Levitate → Ground immunity).
# Applied before type effectiveness in DamageCalculator; returns true = move deals 0.
# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8257):
#   moveType == TYPE_GROUND && abilityDef == ABILITY_LEVITATE && !gravity → modifier 0.0
# Gravity field flag not yet in scope; treated as always false here.
static func blocks_move_type(
		defender: BattlePokemon, move_type: int, ng_active: bool = false,
		attacker: BattlePokemon = null) -> bool:
	if effective_ability_id(defender, ng_active, attacker) == ABILITY_LEVITATE:
		return move_type == TypeChart.TYPE_GROUND
	return false


# M16d: "grounded" check for entry hazards (Spikes, Toxic Spikes) — Stealth Rock does NOT
# use this (it hits Flying-types/Levitate holders too; only Spikes/Toxic Spikes gate on it).
# Source: battle_util.c :: IsBattlerGrounded (L5896) → IsBattlerGroundedInverseCheck (L5879)
#   → IsBattlerUngroundedByAbilityItemOrEffect (L5866): Levitate ability or Flying-type
#   makes a battler ungrounded (returns false here).
# Source (NOT modeled — noted as a known gap, not silently skipped): Air Balloon held item,
#   Magnet Rise / Telekinesis volatiles, and the grounding overrides (Iron Ball item,
#   Gravity field status, Ingrain/Smack Down volatiles) are all outside this project's
#   currently-implemented scope (no held-item-driven grounding, no Gravity field, no
#   Ingrain/Smack Down volatiles anywhere else in the codebase either).
# M17g: ng_active added — Neutralizing Gas suppresses Levitate's grounding exemption
# field-wide, same as every other ability check (source's IsBattlerGrounded reads the
# ability via GetBattlerAbility, the same suppression-aware chokepoint). No `attacker`
# param: is_grounded is only ever called outside any move-resolution window (hazard
# immunity at switch-in, Arena Trap's grounded-check inside is_trapped at selection
# time) — Mold Breaker's per-move scope structurally cannot apply here (see is_trapped's
# updated comment below for the source citation proving this).
static func is_grounded(mon: BattlePokemon, ng_active: bool = false) -> bool:
	if effective_ability_id(mon, ng_active) == ABILITY_LEVITATE:
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
# here — only the first two are in this project's ability scope.
# M17g: attacker's OWN ability — only ng_active matters (see ignores_defender_def_stage).
static func ignores_defender_evasion_stage(
		attacker: BattlePokemon, ng_active: bool = false) -> bool:
	var id: int = effective_ability_id(attacker, ng_active)
	return id == ABILITY_UNAWARE or id == ABILITY_KEEN_EYE


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
static func try_switch_in(
		pokemon: BattlePokemon, opponent: BattlePokemon,
		opponent_ally: BattlePokemon = null, ng_active: bool = false) -> Dictionary:
	var result := {
		"atk_change": 0, "opponent_speed_change": 0, "cured_own_poison": false,
		"opponent_defiant_stat": -1, "opponent_defiant_change": 0,
	}
	var id: int = effective_ability_id(pokemon, ng_active)
	if id == ABILITY_NONE:
		return result
	if id == ABILITY_INTIMIDATE:
		if not opponent.fainted:
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
#   ABILITY_POISON_POINT (M17c, L4068-4090) / ABILITY_POISON_TOUCH (M17c, L4284-...):
#     same 30% roll shape as Static — poison the attacker on contact if CanBePoisoned
#     (this project's existing Poison/Steel type-immunity check in try_apply_status
#     already covers that). Poison Touch's source case is a separate switch entry with
#     an identical roll+effect, not a shared case block with Poison Point — kept as two
#     `id ==` checks rather than one combined condition to mirror source's structure.
#   ABILITY_EFFECT_SPORE (M17c, L4024-4066): weighted 3-way roll — GEN_LATEST config
#     (B_ABILITY_TRIGGER_CHANCE >= GEN_4 but NOT == GEN_4, matching the same generation
#     branch Shed Skin uses) gives 9% poison / 10% paralysis / 11% sleep (not an even
#     10/10/10 split — a genuine GEN_5+ quirk in source's cutoffs) out of a roll in
#     0-99, else no effect. Also requires `IsAffectedByPowderMove(attacker)` (L4032) —
#     this project has no general "powder move" immunity system, but the ATTACKER-side
#     Grass-type/Overcoat exemption that check encodes is a plain type check we already
#     have infrastructure for (TypeChart), so it's applied directly rather than skipped.
#
# Returns a Dictionary:
#   "rough_skin_damage" : int    — HP deducted from attacker (0 if none)
#   "status_applied"    : int    — BattlePokemon.STATUS_* inflicted on attacker (0 = none)
#   "speed_change"       : int   — Speed stage change applied to attacker (0 = none)
#   "ability_name"      : String — key identifying which ability fired ("" if none)
#
# force_contact_roll: null = RNG; true = force trigger; false = suppress (Static/Flame
#   Body/Poison Point/Poison Touch's shared 30% roll).
# force_effect_spore_roll: null = RNG; int 0-99 = pin the underlying roll value.
static func try_contact_effects(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		damage: int,
		force_contact_roll: Variant = null,
		force_effect_spore_roll: Variant = null,
		ng_active: bool = false) -> Dictionary:

	var result := {
		"rough_skin_damage": 0, "status_applied": 0, "speed_change": 0, "ability_name": "",
		"mummy_overwritten_ability": -1, "wandering_spirit_swapped": false,
	}
	if not move.makes_contact:
		return result
	if damage <= 0:
		return result
	if attacker.fainted:
		return result

	var id: int = effective_ability_id(defender, ng_active)
	if id == ABILITY_NONE:
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
	# No Magic Guard check in M8/M17a scope.
	if id == ABILITY_ROUGH_SKIN or id == ABILITY_IRON_BARBS:
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

	# M17c: Poison Point / Poison Touch — 30% chance to poison the attacker on contact.
	if id == ABILITY_POISON_POINT or id == ABILITY_POISON_TOUCH:
		var fires: bool = _roll_contact(force_contact_roll, 30)
		if fires and StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_POISON):
			result["status_applied"] = BattlePokemon.STATUS_POISON
			result["ability_name"] = "poison_touch" if id == ABILITY_POISON_TOUCH else "poison_point"
		return result

	# M17c: Effect Spore — weighted 3-way roll (9% poison / 10% paralysis / 11% sleep),
	# skipped entirely if the attacker is immune to powder (Grass-type, the only part of
	# IsAffectedByPowderMove reachable with this project's current ability roster).
	if id == ABILITY_EFFECT_SPORE and TypeChart.TYPE_GRASS not in attacker.species.types:
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
		"cursed_body_fired": false, "toxic_debris_fired": false,
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
