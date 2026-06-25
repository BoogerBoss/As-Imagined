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
# Config assumptions (matching expansion defaults, all GEN_LATEST):
#   B_CRIT_MULTIPLIER: 1.5× (Gen 6+)
#   B_CRIT_CHANCE: Gen 7+ odds table {stage 0→1/24, 1→1/8, 2→1/2, 3+→always}
#   B_UPDATED_TYPE_MATCHUPS: Gen-latest chart (see TypeChart)
# Scope for M2: no abilities, no held items, no weather, no field effects, no doubles.

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
static func calculate(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_roll: int = -1,
		force_crit: Variant = null) -> Dictionary:

	# --- Type immunity check (before any calculation) ---
	# Source: src/battle_util.c :: DoMoveDamageCalc (L7718–7727)
	var effectiveness: float = TypeChart.get_effectiveness(
			move.type, defender.species.types)
	if effectiveness == 0.0:
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0}

	# --- Critical hit determination ---
	# Source: src/battle_util.c :: IsCriticalHit → CalcCritChanceStage (L7820)
	var is_crit: bool = _roll_crit(move.critical_hit_stage) if force_crit == null else bool(force_crit)

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

	var atk: int = _apply_stage(atk_base, atk_stage)
	var def: int = _apply_stage(def_base, def_stage)

	# --- Base damage formula ---
	# Source: src/battle_util.c :: CalculateBaseDamage (L7215–7218)
	# Formula (integer division, left-to-right):
	#   power * attack * (2 * level / 5 + 2) / defense / 50 + 2
	var dmg: int = move.power * atk * (2 * attacker.level / 5 + 2) / def / 50 + 2

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
	# (Adaptability and pledge combos not implemented in M2)
	if move.type != TypeChart.TYPE_MYSTERY and move.type in attacker.species.types:
		dmg = _uq412_half_down(dmg, UQ412_1_5)

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
		var first_type: int = def_types[0] if def_types.size() > 0 else TypeChart.TYPE_NONE
		var type_mod: int = TypeChart.get_uq412(move.type, first_type)
		if def_types.size() > 1:
			var second_type: int = def_types[1]
			if second_type != first_type and second_type != TypeChart.TYPE_NONE:
				type_mod = _uq412_multiply(type_mod, TypeChart.get_uq412(move.type, second_type))
		if type_mod == 0:
			return {"damage": 0, "is_crit": is_crit, "effectiveness": 0.0}
		dmg = _uq412_half_down(dmg, type_mod)

	# Burn modifier (GetBurnOrFrostBiteModifier) — M3+
	# Other modifiers (items, abilities) — M8+

	# Minimum damage: always deal at least 1 if not immune
	if dmg == 0:
		dmg = 1

	return {"damage": dmg, "is_crit": is_crit, "effectiveness": effectiveness}


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


# Roll for a critical hit using Gen 7+ odds.
# Source: src/battle_util.c :: CalcCritChanceStage (L7820–7861) + IsCriticalHit (L7916–7953)
# Config: B_CRIT_CHANCE = GEN_LATEST → sGen7CriticalHitOdds = {24, 8, 2, 1}
# stage = move.critical_hit_stage (0 for normal, 1 for high-crit moves like Slash)
static func _roll_crit(move_crit_stage: int) -> bool:
	var stage: int = clampi(move_crit_stage, 0, 3)
	var odds: int = CRIT_ODDS_GEN7[stage]
	return randi() % odds == 0
