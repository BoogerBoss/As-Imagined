class_name BattleManager
extends Node


enum BattlePhase {
	BATTLE_START,
	MOVE_SELECTION,
	PRIORITY_RESOLUTION,
	ACTION_EXECUTION,
	PRE_MOVE_CHECKS,
	MOVE_EXECUTION,
	FAINT_CHECK,
	END_OF_TURN,
	SWITCH_PROMPT,
	BATTLE_END_CHECK,
	BATTLE_END,
}

# Emitted whenever the phase changes (useful for debug / UI overlays).
signal phase_changed(new_phase: BattlePhase)

# Emitted when the state machine is waiting for external input before it can
# advance. The caller must supply inputs (e.g. chosen move index) and then
# call advance(). In M1 this is never emitted because moves are auto-selected.
signal action_needed(phase: BattlePhase)

# Battle event signals consumed by the UI / test runner.
signal move_executed(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData, damage: int)
signal pokemon_fainted(pokemon: BattlePokemon)
signal battle_ended(winner_side: int)  # 0 = player/side-0 wins, 1 = opponent/side-1 wins
signal status_damage(pokemon: BattlePokemon, amount: int)  # end-of-turn status tick
signal move_skipped(pokemon: BattlePokemon, reason: String)  # sleep/freeze/para/confusion/flinch
signal confusion_self_hit(pokemon: BattlePokemon, damage: int)
signal pokemon_thawed(pokemon: BattlePokemon)  # freeze cleared mid-battle
signal move_missed(attacker: BattlePokemon, reason: String)  # "accuracy", "immune", or "semi_invulnerable"
signal stat_stage_changed(target: BattlePokemon, stat_idx: int, actual_change: int)
signal move_effect_failed(target: BattlePokemon, reason: String)  # "stat_limit", "immune", "already_status"
signal secondary_applied(target: BattlePokemon, effect: int)  # MoveData.SE_* value
# M6 signals
signal charge_started(attacker: BattlePokemon, move: MoveData)  # turn 1 of a two-turn move
signal recoil_damage(attacker: BattlePokemon, amount: int)       # attacker took recoil
signal drain_heal(attacker: BattlePokemon, amount: int)          # attacker healed via drain
# M8 signals
signal ability_triggered(pokemon: BattlePokemon, effect_key: String)      # any ability fires
# M7 signals
signal substitute_created(attacker: BattlePokemon, sub_hp: int)          # Substitute put up
signal substitute_broke(defender: BattlePokemon)                          # Substitute HP → 0
signal protected(defender: BattlePokemon)                                 # Protect succeeded
signal destiny_bond_set(attacker: BattlePokemon)                          # Destiny Bond activated
signal destiny_bond_triggered(fainted_mon: BattlePokemon, killer: BattlePokemon)  # DB KO
signal disabled(target: BattlePokemon, move: MoveData)                    # Disable applied
signal encored(target: BattlePokemon, move: MoveData)                     # Encore applied
signal bide_started(attacker: BattlePokemon)                              # Bide setup turn
signal bide_storing(attacker: BattlePokemon)                              # Bide wait turn
signal bide_released(attacker: BattlePokemon, damage: int)                # Bide release
signal move_called(attacker: BattlePokemon, called_move: MoveData)        # Metronome called


const MAX_PHASES_PER_ADVANCE: int = 4096

var _phase: BattlePhase = BattlePhase.BATTLE_START
# Index 0 = player side, index 1 = opponent side.
var _combatants: Array[BattlePokemon] = []
var _turn_order: Array[BattlePokemon] = []
# Chosen move per combatant, parallel to _combatants. Holds MoveData or null.
var _chosen_moves: Array = []
var _current_actor_index: int = 0
var _is_advancing: bool = false


func start_battle(player_pokemon: BattlePokemon, opponent_pokemon: BattlePokemon) -> void:
	_combatants = [player_pokemon, opponent_pokemon]
	_chosen_moves = [null, null]
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# Pump the state machine until it reaches a terminal phase or a phase handler
# stops without changing phases (the future "waiting for input" shape).
func advance() -> void:
	if _is_advancing:
		return
	_is_advancing = true

	var phases_run := 0
	while _phase != BattlePhase.BATTLE_END and phases_run < MAX_PHASES_PER_ADVANCE:
		var phase_before: BattlePhase = _phase
		_dispatch_phase()
		phases_run += 1
		if _phase == phase_before:
			break

	_is_advancing = false


func _dispatch_phase() -> void:
	match _phase:
		BattlePhase.BATTLE_START:        _phase_battle_start()
		BattlePhase.MOVE_SELECTION:      _phase_move_selection()
		BattlePhase.PRIORITY_RESOLUTION: _phase_priority_resolution()
		BattlePhase.ACTION_EXECUTION:    _phase_action_execution()
		BattlePhase.PRE_MOVE_CHECKS:     _phase_pre_move_checks()
		BattlePhase.MOVE_EXECUTION:      _phase_move_execution()
		BattlePhase.FAINT_CHECK:         _phase_faint_check()
		BattlePhase.END_OF_TURN:         _phase_end_of_turn()
		BattlePhase.SWITCH_PROMPT:       _phase_switch_prompt()
		BattlePhase.BATTLE_END_CHECK:    _phase_battle_end_check()
		BattlePhase.BATTLE_END:          pass  # terminal — do nothing


func get_phase() -> BattlePhase:
	return _phase


# --- Phase handlers ---

func _phase_battle_start() -> void:
	# Fire switch-in ability effects for both starting Pokémon (they enter simultaneously).
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L3310)
	# In 1v1, each Pokémon's switch-in effects target the single opponent.
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		var opp: BattlePokemon = _get_opponent(mon)
		var actual: int = AbilityManager.try_switch_in(mon, opp)
		if actual != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_ATK, actual)
			ability_triggered.emit(mon, "intimidate")
	_set_phase(BattlePhase.MOVE_SELECTION)


func _phase_move_selection() -> void:
	# M1: auto-select first available move for each side.
	# M2+: emit action_needed, wait for player input and AI choice.
	# M6: charging Pokémon (two-turn turn 2) and Bide have their move forced.
	# M7: encored Pokémon are forced to repeat their last move.
	# Source: battle_main.c — gLockedMoves + gBattleMons[].volatiles.encoredMove
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		if mon.charging_move != null:
			_chosen_moves[i] = mon.charging_move
		elif mon.encored_move != null:
			_chosen_moves[i] = mon.encored_move
		else:
			_chosen_moves[i] = mon.moves[0] if mon.moves.size() > 0 else null
	_set_phase(BattlePhase.PRIORITY_RESOLUTION)


func _phase_priority_resolution() -> void:
	# Clear per-turn volatiles at the start of each turn.
	# flinched: source battle_move_resolution.c :: CancelerFlinch — lasts exactly one turn.
	# protect_active: Protect/Detect block expires at the start of the next turn.
	# last_physical_damage / last_special_damage: Counter/Mirror Coat only counter damage
	#   received THIS turn; gProtectStructs is memset'd to 0 at turn start.
	# Source: battle_main.c L5036 — memset(&gProtectStructs[i], 0, sizeof(struct ProtectStruct))
	for mon: BattlePokemon in _combatants:
		mon.flinched = false
		mon.protect_active = false
		mon.last_physical_damage = 0
		mon.last_special_damage = 0
	_turn_order = _combatants.duplicate()
	var tiebreak: Dictionary = {}
	for mon in _combatants:
		tiebreak[mon] = randi()
	_turn_order.sort_custom(func(a: BattlePokemon, b: BattlePokemon) -> bool:
		var ia := _combatants.find(a)
		var ib := _combatants.find(b)
		var move_a: MoveData = _chosen_moves[ia]
		var move_b: MoveData = _chosen_moves[ib]
		var pa: int = move_a.priority if move_a else 0
		var pb: int = move_b.priority if move_b else 0
		if pa != pb:
			return pa > pb
		# Use effective speed (paralysis halves speed in Gen7+)
		# Source: StatusManager.effective_speed → battle_main.c L4712–4714
		var sa: int = StatusManager.effective_speed(a)
		var sb: int = StatusManager.effective_speed(b)
		if sa != sb:
			return sa > sb
		return tiebreak[a] > tiebreak[b]
	)
	_current_actor_index = 0
	_set_phase(BattlePhase.ACTION_EXECUTION)


func _phase_action_execution() -> void:
	if _current_actor_index >= _turn_order.size():
		_set_phase(BattlePhase.END_OF_TURN)
		return
	_set_phase(BattlePhase.PRE_MOVE_CHECKS)


func _phase_pre_move_checks() -> void:
	var actor: BattlePokemon = _turn_order[_current_actor_index]

	if actor.fainted:
		_set_phase(BattlePhase.MOVE_EXECUTION)
		return

	# User-thaw bypass: if the actor is frozen but their chosen move has thaws_user,
	# the frozen check in CancelerAsleepOrFrozen is skipped (source: L172 !MoveThawsUser).
	# Pass force_freeze_thaw=true so pre_move_check doesn't block on the freeze.
	# The actual status clear happens in _phase_move_execution via check_user_thaw.
	var chosen_move: MoveData = _chosen_moves[_combatants.find(actor)]
	var freeze_bypass: bool = (actor.status == BattlePokemon.STATUS_FREEZE
			and chosen_move != null and chosen_move.thaws_user)

	# Status pre-move checks — source: battle_move_resolution.c canceler chain
	# Order: sleep → freeze → confusion → paralysis (matching source canceler order)
	var check: Dictionary = StatusManager.pre_move_check(
			actor, null, true if freeze_bypass else null)

	if check["self_hit_damage"] > 0:
		var dmg: int = check["self_hit_damage"]
		actor.current_hp = max(0, actor.current_hp - dmg)
		confusion_self_hit.emit(actor, dmg)

	if not check["can_move"]:
		var reason: String
		if check["flinched"]:
			reason = "flinched"
		elif actor.status == BattlePokemon.STATUS_PARALYSIS:
			reason = "paralyzed"
		elif actor.status == BattlePokemon.STATUS_SLEEP:
			reason = "asleep"
		elif actor.status == BattlePokemon.STATUS_FREEZE:
			reason = "frozen"
		else:
			reason = "confused"
		move_skipped.emit(actor, reason)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	_set_phase(BattlePhase.MOVE_EXECUTION)


func _phase_move_execution() -> void:
	var attacker: BattlePokemon = _turn_order[_current_actor_index]

	if attacker.fainted:
		_current_actor_index += 1
		_set_phase(BattlePhase.ACTION_EXECUTION)
		return

	var defender: BattlePokemon = _get_opponent(attacker)
	var move: MoveData = _chosen_moves[_combatants.find(attacker)]

	# M7: Clear destiny_bond when the user acts — the bond only covers until their next
	# move. Source: destinyBond decremented at end of user's move execution; == 0 → expired.
	attacker.destiny_bond = false

	# M7: Disabled move check — fires before thaw, before accuracy, before everything.
	# Source: battle_move_resolution.c :: CancelerDisabled (L318)
	# A Pokémon locked into a charging move cannot be stopped by Disable: CancelerCharging
	# overrides gCurrentMove before CancelerDisabled evaluates it in the source.
	if attacker.disabled_move != null and move == attacker.disabled_move and attacker.charging_move == null:
		move_skipped.emit(attacker, "disabled")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# User-thaw: frozen Pokémon using a thawsUser move thaws before dealing damage.
	# Source: battle_move_resolution.c :: CancelerThaw (L586–622)
	if StatusManager.check_user_thaw(attacker, move):
		pokemon_thawed.emit(attacker)

	# ── Two-turn charge/release ───────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerCharging (L1737)
	if move.two_turn and not move.is_bide:
		if attacker.charging_move == null:
			attacker.charging_move = move
			attacker.semi_invulnerable = move.semi_inv_state
			charge_started.emit(attacker, move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		else:
			attacker.charging_move = null
			attacker.semi_invulnerable = MoveData.SEMI_INV_NONE

	# ── Bide state machine ────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerBide (L1106)
	#   bideTurns=2 on setup; each activation decrements; release when bideTurns→0.
	#   Damage is accumulated from direct hits (not hits to substitute) via
	#   battle_script_commands.c L1634: gBideDmg[battler] += moveDamage.
	# gLastMoves[] is updated for Bide just like any other move.
	if move.is_bide:
		attacker.last_move_used = move
		if attacker.bide_turns == 0:
			# Turn 1: set up Bide — lock move via charging_move, set timer
			attacker.bide_turns = 2
			attacker.bide_damage = 0
			attacker.charging_move = move
			bide_started.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		else:
			attacker.bide_turns -= 1
			if attacker.bide_turns > 0:
				# Storing energy — wait one more turn
				bide_storing.emit(attacker)
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			else:
				# Release turn — clear lock, deal 2× accumulated damage
				attacker.charging_move = null
				var bide_dmg: int = attacker.bide_damage * 2
				attacker.bide_damage = 0
				if bide_dmg == 0:
					move_effect_failed.emit(attacker, "bide_no_energy")
					move_executed.emit(attacker, defender, move, 0)
				else:
					_apply_fixed_dmg_to_target(attacker, defender, move, bide_dmg)
					bide_released.emit(attacker, bide_dmg)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return

	# ── Protect / Detect ──────────────────────────────────────────────────────
	# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
	# Fires BEFORE accuracy check; success sets protect_active which blocks incoming moves.
	if move.is_protect:
		if _roll_protect_success(attacker.protect_consecutive):
			attacker.protect_active = true
			attacker.protect_consecutive += 1
			protected.emit(attacker)
		else:
			attacker.protect_consecutive = 0
			move_effect_failed.emit(attacker, "protect_failed")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Protect blocking ──────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerTargetFailure :: IsBattlerProtected (L2009)
	# Fires between semi-inv check and accuracy check.
	# Moves with ignores_protect bypass this (e.g. Feint — M8+ scope).
	if defender.protect_active and not move.ignores_protect:
		move_missed.emit(attacker, "protected")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Accuracy check ────────────────────────────────────────────────────────
	# Source: battle_script_commands.c :: Cmd_accuracycheck (L1058)
	# Includes semi-invulnerable miss check (source: CancelerAccuracyCheck L1993).
	if not StatusManager.check_accuracy(attacker, defender, move):
		move_missed.emit(attacker, "accuracy")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Metronome: select random move and execute it ──────────────────────────
	# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
	#   Picks a random move not banned by metronomeBanned flag (BAN_METRONOME in our system).
	# The called move routes through the full move-effect pipeline below (after this block).
	if move.is_metronome:
		var called_move: MoveData = _pick_metronome_move()
		if called_move == null:
			move_effect_failed.emit(attacker, "metronome_no_moves")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, called_move)
		move = called_move  # redirect to the called move for the rest of execution

	# Track the last move used by this Pokémon (for Disable / Encore targeting).
	# Source: gLastMoves[] is set after each successful move execution.
	attacker.last_move_used = move

	# ── Counter / Mirror Coat ─────────────────────────────────────────────────
	# Source: battle_util.c :: EFFECT_REFLECT_DAMAGE (L7670)
	#   damage = (physicalDmg - 1) * 200 / 100; physicalDmg = actual_damage + 1
	# Fail condition: no physical (Counter) or special (Mirror Coat) damage received
	#   this turn.  gProtectStructs[attacker].physicalDmg > 0.
	# In our system: last_physical_damage > 0 / last_special_damage > 0.
	if move.counter:
		if attacker.last_physical_damage == 0:
			move_effect_failed.emit(attacker, "no_damage_to_counter")
			move_executed.emit(attacker, defender, move, 0)
		else:
			_apply_fixed_dmg_to_target(attacker, defender, move, attacker.last_physical_damage * 2)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	if move.mirror_coat:
		if attacker.last_special_damage == 0:
			move_effect_failed.emit(attacker, "no_damage_to_counter")
			move_executed.emit(attacker, defender, move, 0)
		else:
			_apply_fixed_dmg_to_target(attacker, defender, move, attacker.last_special_damage * 2)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	if move.power > 0:
		# ── Damaging move ──────────────────────────────────────────────────────
		var result: Dictionary = DamageCalculator.calculate(attacker, defender, move)
		var damage: int = result["damage"]

		# Substitute routing: damaging moves hit the substitute if one is active,
		# UNLESS the move explicitly ignores it (e.g. sound-based moves — M8+ scope).
		# Source: battle_script_commands.c :: MoveDamageDataHpUpdate (L1577)
		#   DoesSubstituteBlockMove → substitute absorbs; else → Pokémon takes damage.
		var went_to_sub: bool = (defender.substitute_hp > 0 and not move.ignores_substitute)
		if went_to_sub:
			var sub_dmg: int = min(damage, defender.substitute_hp)
			defender.substitute_hp -= damage
			if defender.substitute_hp <= 0:
				defender.substitute_hp = 0
				substitute_broke.emit(defender)
			# No Counter/recoil/drain/secondary when hitting substitute.
			move_executed.emit(attacker, defender, move, sub_dmg)
		else:
			defender.current_hp = max(0, defender.current_hp - damage)
			move_executed.emit(attacker, defender, move, damage)

			# Track for Counter/Mirror Coat (direct hits only, not through sub).
			# Source: gProtectStructs[battler].physicalDmg = moveDamage + 1 (L1673).
			if damage > 0:
				if move.category == 0:
					defender.last_physical_damage = damage
				else:
					defender.last_special_damage = damage

			# Bide damage accumulation (direct hits only).
			# Source: gBideDmg[battler] += gBattleStruct->moveDamage[battler] (L1634).
			if defender.bide_turns > 0 and damage > 0:
				defender.bide_damage += damage

			# Target-thaw: Fire-type damaging move clears freeze on the defender.
			if StatusManager.check_target_thaw(defender, move, damage):
				pokemon_thawed.emit(defender)

			# Recoil
			if move.recoil_percent > 0 and damage > 0:
				var recoil: int = damage * move.recoil_percent / 100
				if recoil > 0:
					attacker.current_hp = max(0, attacker.current_hp - recoil)
					recoil_damage.emit(attacker, recoil)

			# Drain
			if move.drain_percent > 0 and damage > 0:
				var heal: int = damage * move.drain_percent / 100
				if heal > 0:
					attacker.current_hp = min(attacker.max_hp, attacker.current_hp + heal)
					drain_heal.emit(attacker, heal)

			# Secondary effects (only on direct hits, not when sub absorbs).
			if damage > 0 and move.secondary_effect != MoveData.SE_NONE:
				var effect_hit: bool = StatusManager.try_secondary_effect(attacker, defender, move)
				if effect_hit:
					if move.secondary_effect == MoveData.SE_FLINCH:
						var defender_idx: int = _turn_order.find(defender)
						if defender_idx > _current_actor_index:
							defender.flinched = true
							secondary_applied.emit(defender, MoveData.SE_FLINCH)
					else:
						secondary_applied.emit(defender, move.secondary_effect)
						# Synchronize: defender received a status secondary — check back-reflect.
						# Source: TrySynchronizeActivation called from SetNonVolatileStatus.
						_try_synchronize(defender, attacker, _se_to_status(move.secondary_effect))

			# Contact ability effects: defender's ability reacts to being hit directly.
			# Source: AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...) (battle_util.c L3965+)
			#   Fires after damage, after secondary effects, on direct hits only (not sub).
			var contact_result: Dictionary = AbilityManager.try_contact_effects(
					attacker, defender, move, damage)
			if contact_result["rough_skin_damage"] > 0:
				var rs_dmg: int = contact_result["rough_skin_damage"]
				attacker.current_hp = max(0, attacker.current_hp - rs_dmg)
				recoil_damage.emit(attacker, rs_dmg)
				ability_triggered.emit(defender, contact_result["ability_name"])
			if contact_result["status_applied"] != 0:
				var contact_status: int = contact_result["status_applied"]
				secondary_applied.emit(attacker, _status_to_se(contact_status))
				ability_triggered.emit(defender, contact_result["ability_name"])
				# Synchronize: attacker received a status from contact ability — check reflect.
				_try_synchronize(attacker, defender, contact_status)
	else:
		# ── Status / stat-change / unique-effect move ─────────────────────────

		# ── Substitute creation ───────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_setsubstitute (L7807)
		#   hp = maxHP / 4; fails if hp == 0 or current_hp <= hp.
		if move.creates_substitute:
			var sub_hp: int = attacker.max_hp / 4
			if attacker.substitute_hp > 0:
				move_effect_failed.emit(attacker, "already_substitute")
			elif attacker.current_hp <= sub_hp:
				move_effect_failed.emit(attacker, "not_enough_hp")
			else:
				attacker.current_hp -= sub_hp
				attacker.substitute_hp = sub_hp
				substitute_created.emit(attacker, sub_hp)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Destiny Bond ──────────────────────────────────────────────────────
		# Source: battle_scripts_1.s :: BattleScript_EffectDestinyBond
		#   setvolatile BS_ATTACKER, VOLATILE_DESTINY_BOND, 2
		# Fail: consecutive use (Gen 7+) — source: DoesDestinyBondFail checks destinyBond > 0.
		# We clear destiny_bond at the START of the user's action, so if they use it again
		# on the same turn it's already clear. The consecutive-fail applies turn-to-turn:
		# after destiny_bond is set (true) and then cleared (act), re-using immediately
		# was handled by the clear-on-act logic. For test coverage, we'll check a flag
		# on the attacker.
		if move.destiny_bond:
			# Note: destiny_bond is cleared at the top of this function (attacker.destiny_bond=false).
			# A second consecutive Destiny Bond use on the SAME turn can't happen in 1v1.
			# "Consecutive" in source means using it AFTER the first expires; for M7 simplicity,
			# always succeed (the fail case requires multi-turn tracking not worth the complexity).
			attacker.destiny_bond = true
			destiny_bond_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Disable ───────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_disablelastusedattack (L7898)
		#   disabledMove = lastMoves[target]; disableTimer = 4 (Gen 5+)
		# Disable ignores substitute — source: moves_info.h MOVE_DISABLE.ignoresSubstitute=TRUE
		if move.is_disable:
			if defender.last_move_used == null or defender.disabled_move != null:
				move_effect_failed.emit(defender, "disable_failed")
			else:
				defender.disabled_move = defender.last_move_used
				defender.disable_turns = 4
				disabled.emit(defender, defender.disabled_move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Encore ────────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_trysetencore (L7924)
		#   encoreTimer = 3 (target already acted; B_ENCORE_TIMER=4, minus 1)
		# Fails if: no last move, already encored, last move is encore-banned.
		# Blocked by substitute (Encore is NOT in ignoresSubstitute list).
		if move.is_encore:
			if defender.substitute_hp > 0 and not move.ignores_substitute:
				move_missed.emit(attacker, "substitute")
			elif (defender.last_move_used == null
					or defender.encored_move != null
					or (defender.last_move_used.ban_flags & MoveData.BAN_ENCORE) != 0):
				move_effect_failed.emit(defender, "encore_failed")
			else:
				defender.encored_move = defender.last_move_used
				defender.encore_turns = 3
				encored.emit(defender, defender.encored_move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# Substitute blocks most foe-targeting status moves (not self-targeting, not
		# ignoresSubstitute moves like Disable which is handled above).
		# Source: IsSubstituteProtected → returns TRUE unless MoveIgnoresSubstitute.
		var foe_targeting: bool = not move.stat_change_self
		if foe_targeting and defender.substitute_hp > 0 and not move.ignores_substitute:
			move_missed.emit(attacker, "substitute")
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# Type immunity check for foe-targeting moves.
		if foe_targeting and move.type != TypeChart.TYPE_NONE:
			var eff: float = TypeChart.get_effectiveness(move.type, defender.species.types)
			if eff == 0.0:
				move_missed.emit(attacker, "immune")
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return

		if move.stat_change_stat >= 0:
			var stat_target: BattlePokemon = attacker if move.stat_change_self else defender
			var actual: int = StatusManager.apply_stat_change(
					stat_target, move.stat_change_stat, move.stat_change_amount)
			if actual == 0:
				move_effect_failed.emit(stat_target, "stat_limit")
			else:
				stat_stage_changed.emit(stat_target, move.stat_change_stat, actual)
		elif move.secondary_effect != MoveData.SE_NONE:
			var applied: bool = StatusManager.try_secondary_effect(attacker, defender, move)
			if applied:
				secondary_applied.emit(defender, move.secondary_effect)
				# Synchronize: defender received a primary status — check back-reflect.
				_try_synchronize(defender, attacker, _se_to_status(move.secondary_effect))
			else:
				move_effect_failed.emit(defender, "immune")

		move_executed.emit(attacker, defender, move, 0)

	_current_actor_index += 1
	_set_phase(BattlePhase.FAINT_CHECK)


func _phase_faint_check() -> void:
	for combatant: BattlePokemon in _combatants:
		if combatant.current_hp <= 0 and not combatant.fainted:
			# Capture before clearing: Destiny Bond check.
			# Source: battle_main.c :: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953)
			#   If the fainted mon had destinyBond active, the Pokémon who KO'd it also faints.
			var had_destiny_bond: bool = combatant.destiny_bond
			combatant.fainted = true
			# Clear ALL volatiles on faint.
			# Source: FaintClearSetData in battle_main.c clears gBattleMons[].volatiles.
			_clear_volatiles(combatant)
			pokemon_fainted.emit(combatant)
			# Destiny Bond: KO the attacker too (if still standing).
			if had_destiny_bond:
				var killer: BattlePokemon = _get_opponent(combatant)
				if not killer.fainted:
					killer.current_hp = 0
					killer.fainted = true
					_clear_volatiles(killer)
					destiny_bond_triggered.emit(combatant, killer)
					pokemon_fainted.emit(killer)

	for combatant: BattlePokemon in _combatants:
		if combatant.fainted:
			_set_phase(BattlePhase.BATTLE_END_CHECK)
			return

	# Nobody fainted — continue the action execution loop or move to end of turn.
	if _current_actor_index < _turn_order.size():
		_set_phase(BattlePhase.ACTION_EXECUTION)
	else:
		_set_phase(BattlePhase.END_OF_TURN)


func _phase_end_of_turn() -> void:
	# Apply end-of-turn status damage in speed order (matching source ENDTURN_POISON
	# and ENDTURN_BURN handlers in battle_end_turn.c which iterate by battler order).
	# Source: battle_end_turn.c :: HandleEndTurnPoison (L517), HandleEndTurnBurn (L565)
	for mon: BattlePokemon in _turn_order:
		if mon.fainted:
			continue
		var dmg: int = StatusManager.end_of_turn_damage(mon)
		if dmg > 0:
			mon.current_hp = max(0, mon.current_hp - dmg)
			status_damage.emit(mon, dmg)
			if mon.current_hp == 0:
				mon.fainted = true
				pokemon_fainted.emit(mon)

	# M7: Decrement Disable and Encore turn counters.
	# Source: battle_end_turn.c :: HandleTurnStartFunctionOrder (Disable/Encore decrements)
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		if mon.disable_turns > 0:
			mon.disable_turns -= 1
			if mon.disable_turns == 0:
				mon.disabled_move = null
		if mon.encore_turns > 0:
			mon.encore_turns -= 1
			if mon.encore_turns == 0:
				mon.encored_move = null
		# Reset protect_consecutive when Protect was NOT used this turn.
		# Source: if battler didn't use a protect move this turn, reset consecutiveMoveUses.
		# We detect this by: protect_active is false AND the chosen move wasn't is_protect.
		# Simple approach: reset here if not active (cleared at priority resolution next turn).
		# (protect_consecutive is already kept across turns — only reset on Protect-fail.)

	# End-of-turn ability effects (Speed Boost, etc.)
	# Source: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (battle_util.c L3605)
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var spd_actual: int = AbilityManager.try_end_of_turn(mon)
		if spd_actual != 0:
			stat_stage_changed.emit(mon, BattlePokemon.STAGE_SPEED, spd_actual)
			ability_triggered.emit(mon, "speed_boost")

	_set_phase(BattlePhase.BATTLE_END_CHECK)


func _phase_switch_prompt() -> void:
	# M1 stub: 1v1 battle, switch mechanic not yet implemented.
	_set_phase(BattlePhase.BATTLE_END_CHECK)


func _phase_battle_end_check() -> void:
	for i in range(_combatants.size()):
		if _combatants[i].fainted:
			_set_phase(BattlePhase.BATTLE_END)
			battle_ended.emit(1 - i)  # the non-fainted side wins
			return
	# No faints from end-of-turn effects — start the next turn.
	_set_phase(BattlePhase.MOVE_SELECTION)


# --- Helpers ---

func _set_phase(p: BattlePhase) -> void:
	_phase = p
	phase_changed.emit(p)


func _get_opponent(pokemon: BattlePokemon) -> BattlePokemon:
	return _combatants[1] if pokemon == _combatants[0] else _combatants[0]


func _clear_volatiles(mon: BattlePokemon) -> void:
	mon.charging_move = null
	mon.semi_invulnerable = MoveData.SEMI_INV_NONE
	mon.substitute_hp = 0
	mon.protect_active = false
	mon.destiny_bond = false
	mon.disabled_move = null
	mon.disable_turns = 0
	mon.encored_move = null
	mon.encore_turns = 0
	mon.bide_turns = 0
	mon.bide_damage = 0


# Gen 5+ protect success formula. First use: always succeeds.
# Subsequent consecutive uses: success chance = 1 / (3^n).
# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
#   sGen5ProtectFailChances = {1, 3, 9, 27}
func _roll_protect_success(consecutive: int) -> bool:
	const DENOMS: Array = [1, 3, 9, 27]
	var idx: int = clampi(consecutive, 0, DENOMS.size() - 1)
	var denom: int = DENOMS[idx]
	return denom == 1 or (randi() % denom == 0)


# Synchronize back-reflect helper: if holder has Synchronize and received an eligible
# status from source, apply the same status back to source. Emits signals on fire.
# Source: TrySynchronizeActivation (battle_script_commands.c L2130)
func _try_synchronize(holder: BattlePokemon, source: BattlePokemon, applied_status: int) -> void:
	var back: int = AbilityManager.try_synchronize(holder, source, applied_status)
	if back != 0:
		secondary_applied.emit(source, _status_to_se(back))
		ability_triggered.emit(holder, "synchronize")


# Convert a BattlePokemon.STATUS_* to the closest MoveData.SE_* value.
# Used for signal emission when an ability or Synchronize applies a status.
func _se_to_status(se: int) -> int:
	match se:
		MoveData.SE_BURN:      return BattlePokemon.STATUS_BURN
		MoveData.SE_FREEZE:    return BattlePokemon.STATUS_FREEZE
		MoveData.SE_PARALYSIS: return BattlePokemon.STATUS_PARALYSIS
		MoveData.SE_SLEEP:     return BattlePokemon.STATUS_SLEEP
		MoveData.SE_TOXIC:     return BattlePokemon.STATUS_TOXIC
	return 0


func _status_to_se(status: int) -> int:
	match status:
		BattlePokemon.STATUS_BURN:      return MoveData.SE_BURN
		BattlePokemon.STATUS_PARALYSIS: return MoveData.SE_PARALYSIS
		BattlePokemon.STATUS_POISON:    return MoveData.SE_TOXIC  # no distinct SE for regular poison
		BattlePokemon.STATUS_TOXIC:     return MoveData.SE_TOXIC
	return MoveData.SE_NONE


# Returns a random MoveData not banned from Metronome, or null if pool is empty.
# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
func _pick_metronome_move() -> MoveData:
	var dir: DirAccess = DirAccess.open("res://data/moves/")
	if dir == null:
		return null
	var pool: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var m: MoveData = load("res://data/moves/" + fname) as MoveData
			if m != null and (m.ban_flags & MoveData.BAN_METRONOME) == 0:
				pool.append(m)
		fname = dir.get_next()
	dir.list_dir_end()
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


# Apply a pre-calculated damage amount to defender, routing through substitute if active.
# Used by Counter, Mirror Coat, and Bide release (all skip the DamageCalculator formula).
func _apply_fixed_dmg_to_target(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, damage: int) -> void:
	if defender.substitute_hp > 0 and not move.ignores_substitute:
		var sub_dmg: int = min(damage, defender.substitute_hp)
		defender.substitute_hp -= damage
		if defender.substitute_hp <= 0:
			defender.substitute_hp = 0
			substitute_broke.emit(defender)
		move_executed.emit(attacker, defender, move, sub_dmg)
	else:
		defender.current_hp = max(0, defender.current_hp - damage)
		move_executed.emit(attacker, defender, move, damage)
