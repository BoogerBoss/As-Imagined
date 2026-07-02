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
# Primal weather (Desolate Land / Primordial Sea) and Snow, Fog, Strong Winds are out of
# M11 scope; Sandstorm and Hail are in scope for end-of-turn chip only (no damage modifier).
const WEATHER_NONE:      int = 0  # B_WEATHER_NONE
const WEATHER_RAIN:      int = 1  # B_WEATHER_RAIN_NORMAL (Drizzle, Rain Dance)
const WEATHER_SUN:       int = 2  # B_WEATHER_SUN_NORMAL  (Drought, Sunny Day)
const WEATHER_SANDSTORM: int = 3  # B_WEATHER_SANDSTORM   (Sand Stream, Sandstorm)
const WEATHER_HAIL:      int = 4  # B_WEATHER_HAIL        (Snow Warning, Hail)

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
		is_doubles: bool = false) -> Dictionary:

	# --- Ability type immunity (Levitate vs Ground, etc.) ---
	# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8257):
	#   moveType == TYPE_GROUND && abilityDef == ABILITY_LEVITATE && !gravity → 0.0
	# Checked before TypeChart to produce the same 0-damage early return.
	if AbilityManager.blocks_move_type(defender, move.type):
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false}

	# --- Type immunity check (before any calculation) ---
	# Source: src/battle_util.c :: DoMoveDamageCalc (L7718–7727)
	var effectiveness: float = TypeChart.get_effectiveness(
			move.type, defender.species.types)
	if effectiveness == 0.0:
		return {"damage": 0, "is_crit": false, "effectiveness": 0.0,
				"defender_item_consumed": false}

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

	# --- Critical hit determination ---
	# Source: src/battle_util.c :: IsCriticalHit → CalcCritChanceStage (L7820)
	# Focus Energy adds +2 to the crit stage (CalcCritChanceStage L7836: focusEnergy ? 2 : 0).
	var is_crit: bool = _roll_crit(move.critical_hit_stage, attacker.focus_energy) if force_crit == null else bool(force_crit)

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

	# --- Ability attack modifier (Huge Power / Pure Power) ---
	# Source: battle_util.c :: GetAttackStatModifier (L6800–6808): attacker abilities switch.
	#   ABILITY_HUGE_POWER / ABILITY_PURE_POWER: IsBattleMovePhysical → modifier ×2.0
	# Applied to the staged attack stat before the base damage formula.
	var atk_ability_mod: int = AbilityManager.attack_modifier_uq412(attacker, move)
	if atk_ability_mod != 4096:
		atk = _uq412_half_down(atk, atk_ability_mod)

	# M12: Choice Band/Specs attack modifier — applied to stat BEFORE base formula.
	# Source: GetAttackStatModifier (battle_util.c L6989–6996): BAND→physical ×1.5, SPECS→special ×1.5.
	var atk_item_mod: int = ItemManager.attack_modifier_uq412(attacker, move)
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
	if ItemManager.blocks_weather_modifier(attacker) or \
			ItemManager.blocks_weather_modifier(defender):
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

	# --- Ability defense modifier (Thick Fat) ---
	# Source: battle_util.c :: GetDefenseStatModifier — target abilities switch (L6933–6941):
	#   ABILITY_THICK_FAT: (TYPE_FIRE || TYPE_ICE) → modifier ×0.5 applied to atkStat.
	# The modifier is on the attacker's effective attack (halving it), which halves the damage.
	# Applied after type effectiveness, before burn.
	var def_ability_mod: int = AbilityManager.defense_damage_modifier_uq412(defender, move)
	if def_ability_mod != 4096:
		dmg = _uq412_half_down(dmg, def_ability_mod)

	# --- Burn modifier (applied after type effectiveness) ---
	# Source: src/battle_util.c :: GetBurnOrFrostBiteModifier (L7278–7291)
	# Source: src/battle_util.c :: ApplyModifiersAfterDmgRoll (L7617–7624)
	# Burn halves the damage of Physical moves used by the burned attacker.
	# Condition: attacker has burn AND move.category == 0 (Physical).
	# (Guts ability bypasses this but is not in M3 scope.)
	if attacker.status == BattlePokemon.STATUS_BURN and move.category == 0:
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
	var life_orb_mod: int = ItemManager.post_roll_modifier_uq412(attacker)
	if life_orb_mod != 4096:
		dmg = _uq412_half_down(dmg, life_orb_mod)

	# M12: Resist Berry — AFTER Life Orb, AFTER type effectiveness.
	# Source: GetDefenderItemsModifier (battle_util.c L7510–7524).
	# Triggers only on super-effective (≥2.0×) moves matching the berry's type param.
	# BattleManager must consume the item when defender_item_consumed is true.
	var defender_item_consumed: bool = ItemManager.defender_berry_consumed(
			defender, move, effectiveness)
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
static func _roll_crit(move_crit_stage: int, focus_energy: bool = false) -> bool:
	var stage: int = clampi(move_crit_stage + (2 if focus_energy else 0), 0, 3)
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
