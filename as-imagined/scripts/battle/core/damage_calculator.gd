class_name DamageCalculator
extends RefCounted

# Damage formula port from pokeemerald-expansion.
# Primary sources:
#   src/battle_util.c :: CalculateBaseDamage (L7215)
#   src/battle_util.c :: DoMoveDamageCalcVars (L7577)
#   src/battle_util.c :: ApplyModifiersAfterDmgRoll (L7617)
#   src/battle_util.c :: CalcCritChanceStage (L7820)
#   src/battle_util.c :: IsCriticalHit (L7916)
#   src/battle_util.c :: GetCriticalModifier (L7294)
#   src/pokemon.c     :: gStatStageRatios (L505)
#   include/fpmath.h  :: uq4_12_multiply_by_int_half_down (L70)
#   src/battle_util.c :: GetWeatherDamageModifier (L7251) — M11
# Config assumptions (matching expansion defaults, all GEN_LATEST):
#   B_CRIT_MULTIPLIER: 1.5× (Gen 6+)
#   B_CRIT_CHANCE: Gen 7+ odds table {stage 0→1/24, 1→1/8, 2→1/2, 3+→always}
#   B_UPDATED_TYPE_MATCHUPS: Gen-latest chart (see TypeChart)
#   B_BURN_DAMAGE: burn also halves physical attack (GEN_LATEST)

# M11: Field weather constants — source: include/constants/battle.h :: enum BattleWeather
# gBattleWeather is a bitmask in source; we simplify to a plain enum int per battle.
# The weather modifier is applied in DoMoveDamageCalcVars (L7594): after base damage,
# before the critical hit modifier, before the random roll.
# Primal weather (Desolate Land / Primordial Sea) reuse WEATHER_SUN/WEATHER_RAIN directly
# (M17d, docs/decisions.md — no separate "Primal Sun"/"Primal Rain" value needed, since
# this project has no Air-Lock-blocks-Primal-only or weather-move-resists-Primal-only
# special-casing that would need to tell them apart from the ordinary versions).
# Snow and Fog are still out of scope. Sandstorm and Hail are in scope for end-of-turn
# chip only (no damage modifier).
const WEATHER_NONE:      int = 0  # B_WEATHER_NONE
const WEATHER_RAIN:      int = 1  # B_WEATHER_RAIN_NORMAL (Drizzle, Rain Dance)
const WEATHER_SUN:       int = 2  # B_WEATHER_SUN_NORMAL  (Drought, Sunny Day)
const WEATHER_SANDSTORM: int = 3  # B_WEATHER_SANDSTORM   (Sand Stream, Sandstorm)
const WEATHER_HAIL:      int = 4  # B_WEATHER_HAIL        (Snow Warning, Hail)
const WEATHER_STRONG_WINDS: int = 5  # B_WEATHER_STRONG_WINDS (Delta Stream) — M17d

# Stat stage multiplier table — source: src/pokemon.c :: gStatStageRatios
# Index 0 = stage -6 (MIN), index 6 = stage 0 (DEFAULT), index 12 = stage +6 (MAX).
# Applied as: stat = stat * ratio[stage_index][0] / ratio[stage_index][1]
const STAGE_RATIOS: Array = [
	[10, 40],  # -6
	[10, 35],  # -5
	[10, 30],  # -4
	[10, 25],  # -3
	[10, 20],  # -2
	[10, 15],  # -1
	[10, 10],  #  0  (neutral)
	[15, 10],  # +1
	[20, 10],  # +2
	[25, 10],  # +3
	[30, 10],  # +4
	[35, 10],  # +5
	[40, 10],  # +6
]

# Gen 7+ crit odds — source: src/battle_util.c :: sGen7CriticalHitOdds (L7768)
# Chance = 1 / CRIT_ODDS[stage]. Stages 3+ clamp to always-crit (index 3 = 1).
const CRIT_ODDS_GEN7: Array = [24, 8, 2, 1]

# Random roll range — source: include/battle_util.h :: DMG_ROLL_PERCENT_LO/HI
const DMG_ROLL_LO: int = 85
const DMG_ROLL_HI: int = 100

# UQ4.12 modifier constant for 1.5× — used for STAB and the Gen6+ crit multiplier.
# Source: include/fpmath.h :: UQ_4_12(1.5) = (uq4_12_t)(1.5 * 4096 + 0.5) = 6144
const UQ412_1_5: int = 6144

# M16c: Screens (Reflect/Light Screen/Aurora Veil) damage-reduction modifiers.
# Source: battle_util.c :: GetScreensModifier (L7347-7365):
#   return (IsDoubleBattle()) ? UQ_4_12(0.667) : UQ_4_12(0.5);
# UQ_4_12(0.5)  = (uq4_12_t)(0.5  * 4096 + 0.5) = 2048
# UQ_4_12(0.667) = (uq4_12_t)(0.667 * 4096 + 0.5) = 2732 (source's literal 0.667, not the
#   mathematically "true" 2/3 — matched bit-for-bit rather than recomputed).
const UQ412_SCREEN_SINGLES: int = 2048
const UQ412_SCREEN_DOUBLES: int = 2732


# Calculate damage for one hit of a standard damaging move.
# Returns a Dictionary:
#   "damage"        : int   — damage dealt (minimum 1 if not immune; 0 if immune)
#   "is_crit"       : bool
#   "effectiveness" : float — 0.0 / 0.25 / 0.5 / 1.0 / 2.0 / 4.0
#
# force_roll  : int     — pass -1 to use a real random roll, or 85–100 to pin it
# force_crit  : Variant — null (default) = use normal crit RNG
#                         true            = always crit
#                         false           = suppress crit (use for deterministic tests)
# weather     : int     — WEATHER_* constant (default WEATHER_NONE = no modifier)
#                         M11: rain boosts Water/reduces Fire; sun boosts Fire/reduces Water.
#                         Source: GetWeatherDamageModifier (battle_util.c L7251)
# power_override: int   — M16b: pass ≥0 to replace move.power as the base-power input
#                         (e.g. Rollout's scaled power, Magnitude's rolled power).
#                         -1 (default) = use move.power. Mirrors source's gBattleMovePower
#                         being computed once (CalcMoveBasePower's per-effect switch) before
#                         Helping Hand's multiplicative modifier is applied on top of it.
# screen_active: bool   — M16c: pass true when the category-appropriate screen (Reflect for
#                         Physical, Light Screen for Special, Aurora Veil for either) is up
#                         on the defender's side. Resolved by the caller (BattleManager),
#                         which has access to per-side state that this static function does
#                         not. Ignored on a crit (screens are bypassed — see is_crit below).
# is_doubles: bool      — M16c: selects the ×0.667 (doubles) vs ×0.5 (singles) screen
#                         reduction. Source: GetScreensModifier gates on IsDoubleBattle()
#                         alone (unlike the spread-move 0.75× reduction, no live-target-count
#                         check).
# ally: BattlePokemon   — M17a: the attacker's doubles partner (null in singles or if the
#                         ally has fainted), resolved by BattleManager._get_ally(). Needed
#                         for Battery/Power Spot/Steely Spirit's ally-aura power boost.
# defender_ally: BattlePokemon — M17c: the DEFENDER's doubles partner (null in singles or
#                         if fainted). Needed for Flower Gift's ally-shared Sp. Def boost.
# ng_active: bool       — M17g: whether Neutralizing Gas is active anywhere on the field
#                         (BattleManager._is_neutralizing_gas_active()). Suppresses every
#                         ability check below field-wide, attacker or defender side alike.
static func calculate(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_roll: int = -1,
		force_crit: Variant = null,
		weather: int = WEATHER_NONE,
		is_spread: bool = false,
		helping_hand: bool = false,
		power_override: int = -1,
		screen_active: bool = false,
		is_doubles: bool = false,
		ally: BattlePokemon = null,
		defender_ally: BattlePokemon = null,
		ng_active: bool = false,
		is_last_to_move: bool = false) -> Dictionary:

	# M17n-6: Normalize / Refrigerate / Pixilate / Galvanize / Liquid Voice — move-type
	# mutation must happen before EVERYTHING else below reads move.type (ability-
	# immunity gates, type effectiveness, STAB, the weather modifier, and any
	# type-boosting ability/item modifier further down) — source computes this once,
	# before move processing begins (`SetTypeBeforeUsingMove`), and every later check
	# reads the already-mutated type (battle_util.c L5993-6024). Mirrored here via a
	# shallow-duplicated MoveData with just `.type` overridden, substituted for `move`
	# for the REST of this call — far less invasive than threading a parallel
	# "type override" parameter through every existing type-aware ability/item check
	# this project already has (Overgrow/Blaze/Torrent/Swarm, Steelworker, Dry Skin,
	# Heatproof, Purifying Salt, Steely Spirit, ItemManager's type-boosting items,
	# etc.) — none of those need to change at all, since they just receive an
	# already-mutated MoveData indistinguishable from a real one. The original `move`
	# Resource passed in by the caller is never mutated (duplicate() returns a new
	# instance) — only this local parameter is reassigned.
	var _mutated_move_type: int = AbilityManager.effective_move_type(attacker, move, ng_active)
	var move_type_changed: bool = _mutated_move_type >= 0
	if move_type_changed:
		var mutated_move: MoveData = move.duplicate()
		mutated_move.type = _mutated_move_type
		move = mutated_move

	# M17n-6: Scrappy / Mind's Eye — the attacker's own ability bypasses a Ghost-type
	# defender's flat Normal/Fighting immunity. Computed once, threaded into BOTH of
	# this project's independent type-effectiveness computations below (the early
	# `effectiveness` float and the later per-type UQ4.12 damage-multiplier block),
	# same duplication pattern already established for `weaken_flying_se` (M17d).
	var scrappy_bypass: bool = AbilityManager.bypasses_ghost_immunity(attacker, ng_active)

	# --- Ability type immunity (Levitate vs Ground, etc.) ---
	# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8257):
	#   moveType == TYPE_GROUND && abilityDef == ABILITY_LEVITATE && !gravity → 0.0
	# Checked before TypeChart to produce the same 0-damage early return.
	# M17g: Levitate is breakable — a Mold-Breaker-holder's Ground move bypasses it.
	# [M19-ignores-target-ability] `move` threaded as attacker_move — Sunsteel
	# Strike/Moongeist Beam bypass a Levitate holder's Ground immunity too.
	if AbilityManager.blocks_move_type(defender, move.type, ng_active, attacker, move):
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false}

	# M17l/M17m: absorb-family full immunity, same early gate group as Levitate above
	# (source: same CanAbilityAbsorbMove dispatch). Three effect shapes packed into one
	# Dictionary (see absorbs_move_type's doc comment and docs/decisions.md [M17m] for
	# the cross-cutting design decision behind this contract) — resolved by
	# BattleManager, not here, since applying a stat/heal/flag change needs signal
	# emission this stateless calculator doesn't do.
	# [M19-ignores-target-ability] `move` threaded as attacker_move — same
	# Mold-Breaker-equivalent bypass for the absorb-family.
	var absorb: Dictionary = AbilityManager.absorbs_move_type(defender, move.type, ng_active, attacker, move)
	if not absorb.is_empty():
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false, "absorb_result": absorb}

	# M17l: Telepathy — full immunity to a damaging move whose target is the attacker's
	# own ally (doubles only). `ally` is the attacker's doubles partner, already threaded
	# through for [M17a]'s Battery/Power Spot/Steely Spirit — `defender == ally` is
	# exactly source's own `battlerDef == BATTLE_PARTNER(battlerAtk)` check.
	if AbilityManager.blocks_ally_damage(defender, defender == ally, move, ng_active, attacker):
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false}

	# --- Type immunity check (before any calculation) ---
	# Source: src/battle_util.c :: DoMoveDamageCalc (L7718–7727)
	# M17d: Delta Stream's Strong Winds weakens super-effective hits against Flying-type
	# defenders — see TypeChart.get_effectiveness's doc comment for why this is a plain
	# bool, not a WEATHER_* constant passed into the data layer.
	# M18t: Iron Ball grounds a Flying-type defender, overriding the raw table's own
	# Ground-vs-Flying 0x entry — see TypeChart.get_effectiveness's own doc comment.
	var iron_ball_grounded: bool = ItemManager.holds_iron_ball(defender, ng_active)
	var effectiveness: float = TypeChart.get_effectiveness(
			move.type, defender.species.types, weather == WEATHER_STRONG_WINDS, scrappy_bypass,
			iron_ball_grounded)
	if effectiveness == 0.0:
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false}

	# M17n-6: Wonder Guard — blocks the hit entirely unless `effectiveness` (the FULL
	# combined multiplier just computed above, already reflecting both defender
	# types, Strong Winds' Flying-weakening, and Scrappy/Mind's Eye's Ghost-bypass) is
	# STRICTLY greater than 1.0x. Positioned here — AFTER type effectiveness is
	# computed, unlike Levitate/the absorb family/Telepathy above, which are all flat
	# 0x-or-nothing checks that don't need the combined value — and BEFORE the
	# fixed/level-damage bypass below, since Wonder Guard still applies to those
	# (see AbilityManager.blocks_non_super_effective_hit's doc comment).
	if AbilityManager.blocks_non_super_effective_hit(defender, effectiveness, move, ng_active, attacker):
		return {"damage": 0, "is_crit": false, "effectiveness": effectiveness,
				"defender_item_consumed": false, "wonder_guard_blocked": true}

	# --- Fixed-damage and level-damage bypass the formula but not type immunity ---
	# Source: battle_util.c :: DoMoveDamageCalc (L7725–7727)
	#   typeEffectivenessModifier == 0 → return 0 (handled above)
	#   DoFixedDamageMoveCalc → returns fixedDamage or level as appropriate
	# These skip all stages, STAB, crit, and type modifiers.
	if move.fixed_damage > 0:
		return {"damage": move.fixed_damage, "is_crit": false, "effectiveness": effectiveness,
				"defender_item_consumed": false}
	if move.level_damage:
		return {"damage": attacker.level, "is_crit": false, "effectiveness": effectiveness,
				"defender_item_consumed": false}
	# [M19-percent-current-hp-damage] Super Fang/Ruination — a % of the
	# TARGET's CURRENT (not max) HP, genuinely distinct from fixed_damage/
	# level_damage above. Source: battle_util.c :: DoMoveDamageCalc,
	# case EFFECT_FIXED_PERCENT_DAMAGE (L7660-7661):
	#   dmg = GetNonDynamaxHP(battlerDef) * GetMoveDamagePercentage(move) / 100
	# Same bypass shape as fixed_damage/level_damage (type immunity and
	# Wonder Guard already applied above; skips STAB/crit/roll/stage math).
	if move.percent_current_hp_damage > 0:
		var pct_dmg: int = defender.current_hp * move.percent_current_hp_damage / 100
		return {"damage": pct_dmg, "is_crit": false, "effectiveness": effectiveness,
				"defender_item_consumed": false}

	# --- Critical hit determination ---
	# Source: src/battle_util.c :: IsCriticalHit → CalcCritChanceStage (L7820)
	# Focus Energy adds +2 to the crit stage (CalcCritChanceStage L7836: focusEnergy ? 2 : 0).
	# M17n-5: Super Luck adds +1 (L7841: `abilities[battlerAtk] == ABILITY_SUPER_LUCK ?
	# 1 : 0`) — additive with the move's own critical_hit_stage and Focus Energy,
	# confirmed from source (a single summed stage, not an independent check).
	var super_luck_bonus: int = 1 \
			if AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_SUPER_LUCK \
			else 0
	# M18e: Scope Lens / Razor Claw — +1 crit stage, summed alongside super_luck_bonus.
	var item_crit_bonus: int = ItemManager.crit_stage_bonus(attacker, ng_active)
	# M17n-8: Merciless — a GUARANTEED crit against a poisoned/toxic'd defender, not a
	# stage bonus like Super Luck above. Source: CalcCritChanceStage (battle_util.c
	# L7828-7830): `(abilities[battlerAtk] == ABILITY_MERCILESS && status1 &
	# STATUS1_PSN_ANY) → CRITICAL_HIT_ALWAYS` — the same unconditional-override branch
	# MoveAlwaysCrits/Laser Focus use, checked BEFORE the normal stage-sum path, not
	# folded into it. Confirmed from source it covers both regular poison and toxic
	# (STATUS1_PSN_ANY), matching BattlePokemon.STATUS_POISON/STATUS_TOXIC here.
	var merciless_guaranteed: bool = \
			AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_MERCILESS \
			and (defender.status == BattlePokemon.STATUS_POISON \
					or defender.status == BattlePokemon.STATUS_TOXIC)
	var is_crit: bool = true if merciless_guaranteed else \
			(_roll_crit(move.critical_hit_stage, attacker.focus_energy, super_luck_bonus, \
					item_crit_bonus) \
					if force_crit == null else bool(force_crit))

	# M17a: Battle Armor / Shell Armor block crits outright, overriding even a forced
	# crit (force_crit=true) — source applies this as the final step of crit determination
	# regardless of how critChance was computed (CalcCritChanceStage L7848-7859).
	if AbilityManager.blocks_critical_hit(defender, ng_active, attacker):
		is_crit = false

	# --- Resolve which stat to use (Physical/Special split) ---
	# Source: src/battle_util.c :: CalcAttackStat (L6769–6778), CalcDefenseStat (L7035–7062)
	# category 0=Physical → atk/def, category 1=Special → sp_atk/sp_def
	var atk_stage: int
	var def_stage: int
	var atk_base: int
	var def_base: int
	if move.category == 0:  # Physical
		atk_base  = attacker.attack
		atk_stage = attacker.stat_stages[BattlePokemon.STAGE_ATK]
		def_base  = defender.defense
		def_stage = defender.stat_stages[BattlePokemon.STAGE_DEF]
	else:                   # Special
		atk_base  = attacker.sp_attack
		atk_stage = attacker.stat_stages[BattlePokemon.STAGE_SPATK]
		def_base  = defender.sp_defense
		def_stage = defender.stat_stages[BattlePokemon.STAGE_SPDEF]

	# --- Critical hit ignores attacker's stage drops and defender's stage boosts ---
	# Source: src/battle_util.c :: CalcAttackStat (L6781–6783), CalcDefenseStat (L7068–7070)
	if is_crit:
		if atk_stage < 0:
			atk_stage = 0
		if def_stage > 0:
			def_stage = 0

	# M17b: Unaware ignores the OPPONENT's stage (both boosts and drops, unconditionally
	# reset to neutral) — defender's Unaware ignores the attacker's stage; attacker's
	# Unaware ignores the defender's stage. Two separate checks, not one shared ability.
	# Source: battle_util.c L6785 (attacker stage), L7072 (defender stage).
	if AbilityManager.ignores_attacker_atk_stage(defender, ng_active, attacker):
		atk_stage = 0
	if AbilityManager.ignores_defender_def_stage(attacker, ng_active):
		def_stage = 0
	# [M19-ignores-stat-stages] Chip Away/Sacred Sword/Darkest Lariat — a
	# MOVE-level equivalent of Unaware's own defense-ignore above, same
	# variable, same insertion point. Source: battle_util.c :: CalcDefenseStat
	# (L7075): `if (MoveIgnoresDefenseEvasionStages(move)) defStage = DEFAULT_STAT_STAGE;`
	if move.ignores_defense_evasion_stages:
		def_stage = 0

	var atk: int = _apply_stage(atk_base, atk_stage)
	var def: int = _apply_stage(def_base, def_stage)

	# M18g: item-driven DEFENSE stat modifier (Deep Sea Scale, Metal Powder) — same
	# pipeline stage as CalcDefenseStat's own switch in source (battle_util.c
	# L7160-7189), the raw-stat-before-formula stage. CONFIRMED DISTINCT from
	# def_ability_mod further below (Thick Fat/Marvel Scale/etc.), which lives in
	# GetDefenseStatModifier — a similarly named but different, POST-effectiveness
	# pipeline stage. This is the first item-side defense-stat modifier this
	# project has built (no prior precedent — Eviolite/Assault Vest aren't
	# implemented).
	var def_item_mod: int = ItemManager.defense_stat_modifier_uq412(defender, move, ng_active)
	if def_item_mod != 4096:
		def = _uq412_half_down(def, def_item_mod)

	# --- Ability attack modifier (Huge Power / Pure Power) ---
	# Source: battle_util.c :: GetAttackStatModifier (L6800–6808): attacker abilities switch.
	#   ABILITY_HUGE_POWER / ABILITY_PURE_POWER: IsBattleMovePhysical → modifier ×2.0
	# Applied to the staged attack stat before the base damage formula.
	var atk_ability_mod: int = AbilityManager.attack_modifier_uq412(attacker, move, weather, ng_active, defender)
	if atk_ability_mod != 4096:
		atk = _uq412_half_down(atk, atk_ability_mod)

	# M12: Choice Band/Specs attack modifier — applied to stat BEFORE base formula.
	# Source: GetAttackStatModifier (battle_util.c L6989–6996): BAND→physical ×1.5, SPECS→special ×1.5.
	var atk_item_mod: int = ItemManager.attack_modifier_uq412(attacker, move, ng_active)
	if atk_item_mod != 4096:
		atk = _uq412_half_down(atk, atk_item_mod)

	# --- Base damage formula ---
	# Source: src/battle_util.c :: CalculateBaseDamage (L7215–7218)
	# Formula (integer division, left-to-right):
	#   power * attack * (2 * level / 5 + 2) / defense / 50 + 2
	#
	# M14b: Helping Hand modifies the base power before the formula.
	# Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6436):
	#   for (i < helpingHand) modifier = uq4_12_multiply(modifier, UQ_4_12(1.5)); (L6436–6437)
	#   returned power = uq4_12_multiply_by_int_half_down(modifier, basePower) (L6603).
	var effective_power: int = power_override if power_override >= 0 else move.power
	if helping_hand:
		effective_power = _uq412_half_down(effective_power, 6144)  # UQ_4_12(1.5)

	# M17a: ability-driven base-power modifiers (Toxic Boost, Flare Boost, Sand Force,
	# Tough Claws, Steelworker, Steely Spirit, Battery, Power Spot) — same pipeline stage
	# as Helping Hand above (CalcMoveBasePowerAfterModifiers, battle_util.c L6375-6656).
	# [M18.5d-2]: `defender` threaded through for Rivalry, the only modifier in this
	# chain that needs the DEFENDER's own data (every other one is a pure attacker
	# self-check).
	var ability_power_mod: int = AbilityManager.move_power_modifier_uq412(
			attacker, move, weather, ally, ng_active, is_last_to_move, move_type_changed,
			defender)
	if ability_power_mod != 4096:
		effective_power = _uq412_half_down(effective_power, ability_power_mod)

	# M18a: item-driven base-power modifiers (Charcoal family / Incenses / Silk Scarf /
	# Fairy Feather / Plates) — same pipeline stage as the ability modifiers above.
	# Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6659-6661), the exact
	# case branch immediately following the ability switch this project already reads.
	var item_power_mod: int = ItemManager.move_power_modifier_uq412(attacker, move, ng_active)
	if item_power_mod != 4096:
		effective_power = _uq412_half_down(effective_power, item_power_mod)

	var dmg: int = effective_power * atk * (2 * attacker.level / 5 + 2) / def / 50 + 2

	# M14b: Spread damage reduction — first modifier after base formula.
	# Source: DoMoveDamageCalcVars (battle_util.c L7592): DAMAGE_APPLY_MODIFIER(GetTargetDamageModifier)
	#   applied immediately after CalculateBaseDamage, before weather, crit, or random roll.
	# Source: GetTargetDamageModifier (battle_util.c L7220–7229):
	#   if IsDoubleBattle() && GetMoveTargetCount >= 2 → UQ_4_12(0.75) = 3072 (Gen 4+).
	# is_spread here means the caller determined ≥2 live targets exist; caller counts them.
	# Source: GetMoveTargetCount (L5982): counts non-absent (non-fainted) opposing battlers.
	# Immune targets are still alive → count as targets → spread reduction still applies.
	if is_spread:
		dmg = _uq412_half_down(dmg, 3072)  # UQ_4_12(0.75)

	# --- Weather damage modifier (before crit, before random roll) ---
	# Source: src/battle_util.c :: DoMoveDamageCalcVars (L7594) — DAMAGE_APPLY_MODIFIER
	#   applied in this order: target mod → parental bond → WEATHER → crit → roll.
	# Source: GetWeatherDamageModifier (L7251–7276):
	#   SUN:  Water → UQ_4_12(0.5)=2048; Fire → UQ_4_12(1.5)=6144. Others → 1.0.
	#   RAIN: Fire  → UQ_4_12(0.5)=2048; Water→ UQ_4_12(1.5)=6144. Others → 1.0.
	# M12: Utility Umbrella on either battler strips rain/sun modifier.
	#   Attacker: GetAttackerWeather (L9281–9290) returns WEATHER_NONE for rain/sun.
	#   Defender: GetWeatherDamageModifier (L7258) returns UQ_4_12(1.0) immediately.
	var weather_mod: int
	if ItemManager.blocks_weather_modifier(attacker, ng_active) or \
			ItemManager.blocks_weather_modifier(defender, ng_active):
		weather_mod = 4096
	else:
		weather_mod = _get_weather_modifier(move.type, weather)
	if weather_mod != 4096:
		dmg = _uq412_half_down(dmg, weather_mod)

	# --- Critical hit modifier (applied before random roll) ---
	# Source: src/battle_util.c :: GetCriticalModifier (L7294–7298); B_CRIT_MULTIPLIER=GEN_LATEST → 1.5×
	# Source: include/fpmath.h :: uq4_12_multiply_by_int_half_down (L70–73)
	if is_crit:
		dmg = _uq412_half_down(dmg, UQ412_1_5)

	# --- Random damage roll ---
	# Source: src/battle_util.c :: DoMoveDamageCalcVars (L7598–7602)
	# roll = DMG_ROLL_HI - RandomUniform(0, DMG_ROLL_HI - DMG_ROLL_LO)
	#      = 100 - randint(0..15) → uniform from {85..100}
	var roll: int = force_roll if force_roll >= DMG_ROLL_LO else \
		DMG_ROLL_HI - randi_range(0, DMG_ROLL_HI - DMG_ROLL_LO)
	dmg = dmg * roll / 100  # integer division

	# --- ApplyModifiersAfterDmgRoll ---
	# Source: src/battle_util.c :: ApplyModifiersAfterDmgRoll (L7617–7628)

	# STAB — source: GetSameTypeAttackBonusModifier (L7239–7248)
	# Source: include/fpmath.h :: uq4_12_multiply_by_int_half_down (L70–73)
	# M17a: Adaptability raises STAB from ×1.5 to ×2.0 (L7244/L7247: ternary on
	# ABILITY_ADAPTABILITY). Pledge combos still not implemented.
	if move.type != TypeChart.TYPE_MYSTERY and move.type in attacker.species.types:
		var stab_mod: int = UQ412_1_5
		if AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_ADAPTABILITY:
			stab_mod = 8192  # UQ_4_12(2.0)
		dmg = _uq412_half_down(dmg, stab_mod)

	# Type effectiveness — accumulate both type modifiers in UQ4.12 space, apply combined once.
	# Source: MulByTypeEffectiveness (L8083): *modifier = uq4_12_multiply(*modifier, mod)
	#         CalcTypeEffectivenessMultiplierInternal (L8134–8144): calls MulByTypeEffectiveness
	#           for each defender type, accumulating into a single UQ4.12 modifier.
	#         DAMAGE_APPLY_MODIFIER then applies the combined modifier once via
	#         uq4_12_multiply_by_int_half_down — i.e. a single _uq412_half_down call.
	# uq4_12_multiply uses half-UP rounding (+2048); _uq412_half_down uses half-DOWN (+2047).
	# For dual 0.5× types: accumulate → 0.5×0.5 = 0.25 (UQ4.12 = 1024), apply once.
	#   e.g. post-STAB dmg=15: (15*1024+2047)/4096 = 17407/4096 = 4 (rounds up, 0.25*15=3.75)
	#   vs per-type: (15→7→3) — different; source uses combined-then-apply.
	if move.type != TypeChart.TYPE_MYSTERY:
		var def_types: Array = defender.species.types
		var strong_winds: bool = weather == WEATHER_STRONG_WINDS
		var first_type: int = def_types[0] if def_types.size() > 0 else TypeChart.TYPE_NONE
		var type_mod: int = TypeChart.get_uq412(move.type, first_type, scrappy_bypass)
		# M17d: Delta Stream — a super-effective (>=2.0x) component against a Flying-type
		# defender is weakened to neutral, checked PER type component to match source's
		# exact granularity (battle_util.c :: MulByTypeEffectiveness L8069-8074).
		if strong_winds and first_type == TypeChart.TYPE_FLYING and type_mod >= 8192:
			type_mod = 4096
		if def_types.size() > 1:
			var second_type: int = def_types[1]
			if second_type != first_type and second_type != TypeChart.TYPE_NONE:
				var second_mod: int = TypeChart.get_uq412(move.type, second_type, scrappy_bypass)
				if strong_winds and second_type == TypeChart.TYPE_FLYING and second_mod >= 8192:
					second_mod = 4096
				type_mod = _uq412_multiply(type_mod, second_mod)
		if type_mod == 0:
			return {"damage": 0, "is_crit": is_crit, "effectiveness": 0.0}
		dmg = _uq412_half_down(dmg, type_mod)

	# --- Ability defense modifier (Thick Fat, M17a: Marvel Scale/Fur Coat/Multiscale/
	# Filter/Solid Rock/Ice Scales/Heatproof) ---
	# Source: battle_util.c :: GetDefenseStatModifier — target abilities switch (L6933–6941):
	#   ABILITY_THICK_FAT: (TYPE_FIRE || TYPE_ICE) → modifier ×0.5 applied to atkStat.
	# The modifier is on the attacker's effective attack (halving it), which halves the damage.
	# Applied after type effectiveness, before burn.
	var def_ability_mod: int = AbilityManager.defense_damage_modifier_uq412(
			defender, move, effectiveness, weather, defender_ally, ng_active, attacker)
	if def_ability_mod != 4096:
		dmg = _uq412_half_down(dmg, def_ability_mod)

	# M17l: Friend Guard — ×0.75 whenever the DEFENDER'S ALLY holds it. Source:
	# GetDefenderPartnerAbilitiesModifier (battle_util.c L7460-7478), same modifier
	# group as the defender-ability modifier above (source's GetOtherModifiers calls
	# GetDefenderAbilitiesModifier then GetDefenderPartnerAbilitiesModifier back to back).
	var friend_guard_mod: int = AbilityManager.friend_guard_modifier_uq412(
			defender_ally, attacker, defender, ng_active)
	if friend_guard_mod != 4096:
		dmg = _uq412_half_down(dmg, friend_guard_mod)

	# M17a: Sniper / Tinted Lens — post-type-effectiveness attacker-side modifier.
	# Source: battle_util.c :: GetAttackerAbilitiesModifier (L7378-7397).
	var atk_post_eff_mod: int = AbilityManager.attacker_post_effectiveness_modifier_uq412(
			attacker, effectiveness, is_crit, ng_active)
	if atk_post_eff_mod != 4096:
		dmg = _uq412_half_down(dmg, atk_post_eff_mod)

	# --- Burn modifier (applied after type effectiveness) ---
	# Source: src/battle_util.c :: GetBurnOrFrostBiteModifier (L7278–7291)
	# Source: src/battle_util.c :: ApplyModifiersAfterDmgRoll (L7617–7624)
	# Burn halves the damage of Physical moves used by the burned attacker.
	# Condition: attacker has burn AND move.category == 0 (Physical).
	# M17a: Guts is exempt (L7285: ctx->abilities[battlerAtk] != ABILITY_GUTS).
	var guts_exempt: bool = \
			AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_GUTS
	if attacker.status == BattlePokemon.STATUS_BURN and move.category == 0 and not guts_exempt:
		dmg = _uq412_half_down(dmg, 2048)  # UQ_4_12(0.5) = 2048

	# M16b: Minimize modifier — Stomp etc. deal ×2.0 damage to a minimized target.
	# Source: battle_util.c :: GetMinimizeModifier (L7319-7323), folded into GetOtherModifiers,
	#   which fires inside ApplyModifiersAfterDmgRoll — same modifier group as ability/item
	#   damage mods, positioned after burn and before Life Orb/Resist Berry in that group.
	if move.double_power_on_minimized and defender.minimized:
		dmg = _uq412_half_down(dmg, 8192)  # UQ_4_12(2.0) = 8192

	# M16c: Reflect/Light Screen/Aurora Veil damage reduction. Same modifier group as the
	# Minimize modifier above (both are folded into GetOtherModifiers in source, in the
	# order Minimize → Underground → Dive → Airborne → Screens → CollisionCourse).
	# Source: battle_util.c :: GetScreensModifier (L7347-7365): crits bypass screens
	#   entirely (checked first in source; mirrored here via the is_crit guard) — Infiltrator
	#   ability bypass is not modeled (Infiltrator is outside this project's ability scope).
	if screen_active and not is_crit:
		var screen_mod: int = UQ412_SCREEN_DOUBLES if is_doubles else UQ412_SCREEN_SINGLES
		dmg = _uq412_half_down(dmg, screen_mod)

	# M12: Life Orb damage modifier — AFTER roll, STAB, type eff, burn (and ability mods).
	# Source: GetAttackerItemsModifier (battle_util.c L7497–7499), called from GetOtherModifiers
	#   which is called inside ApplyModifiersAfterDmgRoll after all other per-modifier steps.
	# M18j: `effectiveness` threaded through for Expert Belt's own case in the
	# same function (>= 2.0 gate) — same shape as post_roll_modifier_uq412's
	# existing Life Orb branch, now sharing this one call site.
	var life_orb_mod: int = ItemManager.post_roll_modifier_uq412(attacker, ng_active, effectiveness)
	if life_orb_mod != 4096:
		dmg = _uq412_half_down(dmg, life_orb_mod)

	# M12: Resist Berry — AFTER Life Orb, AFTER type effectiveness.
	# Source: GetDefenderItemsModifier (battle_util.c L7510–7524).
	# Triggers only on super-effective (≥2.0×) moves matching the berry's type param.
	# BattleManager must consume the item when defender_item_consumed is true.
	# M17n-7: Unnerve — blocks the defender's berry from triggering at all while any
	# opposing battler has Unnerve. `[attacker, ally]` is exactly the defender's
	# opposing side visible to this function (this stateless calculator has no
	# access to the full combatant list) — the same set
	# `IsUnnerveAbilityOnOpposingSide` would iterate in source.
	var unnerve_active: bool = AbilityManager.is_unnerve_active([attacker, ally], ng_active)
	var defender_item_consumed: bool = ItemManager.defender_berry_consumed(
			defender, move, effectiveness, ng_active, unnerve_active)
	if defender_item_consumed:
		dmg = _uq412_half_down(dmg, ItemManager.UQ412_RESIST_BERRY)

	# Minimum damage: always deal at least 1 if not immune
	if dmg == 0:
		dmg = 1

	return {"damage": dmg, "is_crit": is_crit, "effectiveness": effectiveness,
			"defender_item_consumed": defender_item_consumed}


# UQ4.12 × UQ4.12 multiply — source: include/fpmath.h :: uq4_12_multiply (L50–54)
# Used to accumulate type effectiveness modifiers in UQ4.12 space.
# Rounds to nearest in the UQ4.12 domain, half-UP (ties round up).
# Formula: (a * b + UQ_4_12_ROUND) >> UQ_4_12_SHIFT = (a * b + 2048) >> 12
static func _uq412_multiply(a: int, b: int) -> int:
	return (a * b + 2048) >> 12


# Integer-multiply an integer value by a UQ4.12 fixed-point modifier.
# Source: include/fpmath.h :: uq4_12_multiply_by_int_half_down (L70–73)
# Returns an integer, rounded to nearest with ties rounding DOWN ("half-down").
# Formula: (value * factor_uq412 + (UQ_4_12_ROUND - 1)) / 4096
#        = (value * factor_uq412 + 2047) / 4096   (GDScript int '/' truncates toward zero)
# This is NOT the same as floori() for all inputs: for a combined 0.25× modifier
# and inputs where 0.25 * x has fractional part > 0.5 (e.g. x=7), this rounds UP
# while floori() rounds DOWN. For the individual pipeline values (0.5×, 1.0×, 1.5×, 2.0×)
# the two happen to agree because those multipliers never produce a fractional part > 0.5.
static func _uq412_half_down(value: int, factor: int) -> int:
	return (value * factor + 2047) / 4096


# Apply a stat stage multiplier to a base stat value.
# stage is in [-6, +6]; converts to STAGE_RATIOS index by adding 6.
# Source: src/battle_util.c :: CalcAttackStat (L6788–6789), CalcDefenseStat (L7078–7079)
# Formula: stat = stat * ratio[stage+6][0] / ratio[stage+6][1]  (integer division)
static func _apply_stage(base_stat: int, stage: int) -> int:
	var idx: int = clampi(stage + 6, 0, 12)
	return base_stat * STAGE_RATIOS[idx][0] / STAGE_RATIOS[idx][1]


# Confusion self-hit damage.
# Source: src/battle_move_resolution.c :: CancelerConfused (L402–413)
#   DamageContext: battlerAtk==battlerDef, move=MOVE_NONE (Physical), moveType=TYPE_MYSTERY,
#                  isCrit=FALSE, randomFactor=FALSE, fixedBasePower=40, isSelfInflicted=TRUE
# Because randomFactor=FALSE the function returns before ApplyModifiersAfterDmgRoll — no
# random roll, no STAB, no type effectiveness, no burn halving.
# MOVE_NONE has category=DAMAGE_CATEGORY_PHYSICAL (data/moves_info.h L38), so Attack/Defense.
# Stat stages are applied normally. Formula:
#   40 * attack_staged * (2 * level / 5 + 2) / defense_staged / 50 + 2
static func calculate_confusion_damage(mon: BattlePokemon) -> int:
	var atk: int = _apply_stage(mon.attack,   mon.stat_stages[BattlePokemon.STAGE_ATK])
	var def: int = _apply_stage(mon.defense,  mon.stat_stages[BattlePokemon.STAGE_DEF])
	var dmg: int = 40 * atk * (2 * mon.level / 5 + 2) / def / 50 + 2
	return max(1, dmg)


# Roll for a critical hit using Gen 7+ odds.
# Source: src/battle_util.c :: CalcCritChanceStage (L7820–7861) + IsCriticalHit (L7916–7953)
# Config: B_CRIT_CHANCE = GEN_LATEST → sGen7CriticalHitOdds = {24, 8, 2, 1}
# focus_energy adds +2 to the effective crit stage (source L7836: critChance = (focusEnergy ? 2 : 0) + ...).
# stage = move.critical_hit_stage (0 for normal, 1 for high-crit moves like Slash)
# ability_bonus: M17n-5 addition — Super Luck's +1, summed into the same stage total
# as focus_energy's +2 before the 0-3 clamp (source sums all crit-stage
# contributions into ONE value before clamping, confirmed rather than assumed).
# item_bonus: M18e addition — Scope Lens/Razor Claw's +1 (GetHoldEffectCritChanceIncrease,
# battle_util.c L7795-7810), summed into the exact same total alongside ability_bonus,
# matching source's single combined critChance sum (CalcCritChanceStage L7839-7842).
static func _roll_crit(
		move_crit_stage: int, focus_energy: bool = false, ability_bonus: int = 0,
		item_bonus: int = 0) -> bool:
	var stage: int = clampi(
			move_crit_stage + (2 if focus_energy else 0) + ability_bonus + item_bonus, 0, 3)
	var odds: int = CRIT_ODDS_GEN7[stage]
	return randi() % odds == 0


# Weather damage modifier — source: GetWeatherDamageModifier (battle_util.c L7251–7276).
# Returns a UQ4.12 value: 4096=1.0×, 2048=0.5×, 6144=1.5×.
# Applied BEFORE the critical hit modifier and BEFORE the random roll (DoMoveDamageCalcVars L7594).
# Sun:  Water→0.5× (2048), Fire→1.5× (6144). Others→1.0 (4096).
# Rain: Fire→0.5×  (2048), Water→1.5× (6144). Others→1.0 (4096).
# Sandstorm/Hail: no damage modifier (chip handled in end-of-turn; see BattleManager).
static func _get_weather_modifier(move_type: int, weather: int) -> int:
	match weather:
		WEATHER_SUN:
			if move_type == TypeChart.TYPE_WATER: return 2048   # 0.5×
			if move_type == TypeChart.TYPE_FIRE:  return 6144   # 1.5×
		WEATHER_RAIN:
			if move_type == TypeChart.TYPE_FIRE:  return 2048   # 0.5×
			if move_type == TypeChart.TYPE_WATER: return 6144   # 1.5×
	return 4096  # 1.0× — no modifier
