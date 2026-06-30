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


# ── Tier 1: Passive stat modifiers ──────────────────────────────────────────

# Attack multiplier from the attacker's ability.
# Applied to the physical Attack stat before damage formula.
# Source: battle_util.c :: GetAttackStatModifier — attacker abilities switch (L6800–6808):
#   ABILITY_HUGE_POWER / ABILITY_PURE_POWER: IsBattleMovePhysical → modifier ×2.0
# Returns a UQ4.12 integer: 4096 = 1.0×, 8192 = 2.0×.
static func attack_modifier_uq412(attacker: BattlePokemon, move: MoveData) -> int:
	if attacker.ability == null:
		return 4096  # UQ_4_12(1.0)
	var id: int = attacker.ability.ability_id
	if (id == ABILITY_HUGE_POWER or id == ABILITY_PURE_POWER) and move.category == 0:
		return 8192  # UQ_4_12(2.0) — doubles physical Attack
	return 4096


# Incoming damage modifier from the defender's ability.
# Applied after type effectiveness in the damage pipeline.
# Source: battle_util.c :: GetDefenseStatModifier — target abilities switch (L6933–6941):
#   ABILITY_THICK_FAT: (TYPE_FIRE || TYPE_ICE) → modifier ×0.5
# Returns a UQ4.12 integer: 4096 = 1.0×, 2048 = 0.5×.
static func defense_damage_modifier_uq412(defender: BattlePokemon, move: MoveData) -> int:
	if defender.ability == null:
		return 4096
	var id: int = defender.ability.ability_id
	if id == ABILITY_THICK_FAT:
		if move.type == TypeChart.TYPE_FIRE or move.type == TypeChart.TYPE_ICE:
			return 2048  # UQ_4_12(0.5) — halves attacker's effective Attack
	return 4096


# Type immunity from an ability (Levitate → Ground immunity).
# Applied before type effectiveness in DamageCalculator; returns true = move deals 0.
# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8257):
#   moveType == TYPE_GROUND && abilityDef == ABILITY_LEVITATE && !gravity → modifier 0.0
# Gravity field flag not yet in scope; treated as always false here.
static func blocks_move_type(defender: BattlePokemon, move_type: int) -> bool:
	if defender.ability == null:
		return false
	if defender.ability.ability_id == ABILITY_LEVITATE:
		return move_type == TypeChart.TYPE_GROUND
	return false


# ── Tier 2: Switch-in effects ────────────────────────────────────────────────

# Fire switch-in ability effects for a Pokémon entering battle.
# Source: battle_util.c :: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (L3310):
#   ABILITY_INTIMIDATE: shouldAbilityTrigger && !IsOpposingSideEmpty →
#     SetStatChange(all opponents, STAT_ATK, -1). In 1v1, one opponent only.
# Drizzle/Drought: weather is set via get_switch_in_weather() + BattleManager.try_set_weather().
#
# Returns the actual Attack stat stage change applied to opponent (0 = nothing happened).
static func try_switch_in(pokemon: BattlePokemon, opponent: BattlePokemon) -> int:
	if pokemon.ability == null:
		return 0
	var id: int = pokemon.ability.ability_id
	if id == ABILITY_INTIMIDATE:
		if not opponent.fainted:
			return StatusManager.apply_stat_change(
					opponent, BattlePokemon.STAGE_ATK, -1)
	# Drizzle/Drought weather-set is handled by BattleManager calling get_switch_in_weather()
	# immediately after try_switch_in() — the weather call is separated so BattleManager
	# owns the weather state (it's a field effect, not per-Pokémon).
	return 0


# Return the WEATHER_* value (DamageCalculator constants) that should be set when this
# Pokémon switches in, or WEATHER_NONE (0) if the ability has no weather effect.
# Source: ABILITYEFFECT_ON_SWITCHIN — ABILITY_DRIZZLE → TryChangeBattleWeather(RAIN) (L3213)
#                                    — ABILITY_DROUGHT → TryChangeBattleWeather(SUN)  (L3242)
# BattleManager calls try_set_weather(get_switch_in_weather(mon)) after try_switch_in().
static func get_switch_in_weather(pokemon: BattlePokemon) -> int:
	if pokemon.ability == null:
		return DamageCalculator.WEATHER_NONE
	match pokemon.ability.ability_id:
		ABILITY_DRIZZLE:
			return DamageCalculator.WEATHER_RAIN
		ABILITY_DROUGHT:
			return DamageCalculator.WEATHER_SUN
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
# Returns the actual Speed stat stage change (0 = nothing happened).
static func try_end_of_turn(pokemon: BattlePokemon) -> int:
	if pokemon.ability == null:
		return 0
	if pokemon.fainted:
		return 0
	var id: int = pokemon.ability.ability_id
	if id == ABILITY_SPEED_BOOST and not pokemon.switched_in_this_turn:
		return StatusManager.apply_stat_change(
				pokemon, BattlePokemon.STAGE_SPEED, 1)
	return 0


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
#   ABILITY_STATIC     (L4091): B_ABILITY_TRIGGER_CHANCE >= GEN_4 → RandomPercentage 30%
#                                → paralyze attacker if CanBeParalyzed
#   ABILITY_FLAME_BODY (L4114): same 30% roll → burn attacker if CanBeBurned
#
# Returns a Dictionary:
#   "rough_skin_damage" : int    — HP deducted from attacker (0 if none)
#   "status_applied"    : int    — BattlePokemon.STATUS_* inflicted on attacker (0 = none)
#   "ability_name"      : String — key identifying which ability fired ("" if none)
#
# force_contact_roll: null = RNG; true = force trigger; false = suppress
static func try_contact_effects(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		damage: int,
		force_contact_roll: Variant = null) -> Dictionary:

	var result := {"rough_skin_damage": 0, "status_applied": 0, "ability_name": ""}
	if defender.ability == null:
		return result
	if not move.makes_contact:
		return result
	if damage <= 0:
		return result
	if attacker.fainted:
		return result

	var id: int = defender.ability.ability_id

	# Rough Skin: attacker takes maxHP/8 on contact (B_ROUGH_SKIN_DMG >= GEN_4 = /8).
	# Source: L3975 GetNonDynamaxMaxHP(gBattlerAttacker) / 8
	# No Magic Guard check in M8 scope.
	if id == ABILITY_ROUGH_SKIN:
		var rs_dmg: int = attacker.max_hp / 8
		if rs_dmg > 0:
			result["rough_skin_damage"] = rs_dmg
			result["ability_name"] = "rough_skin"
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

	return result


static func _roll_contact(force: Variant, chance_pct: int) -> bool:
	if force != null:
		return bool(force)
	return randi() % 100 < chance_pct


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
		applied_status: int) -> int:

	if holder.ability == null:
		return 0
	if holder.ability.ability_id != ABILITY_SYNCHRONIZE:
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
