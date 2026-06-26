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


var _phase: BattlePhase = BattlePhase.BATTLE_START
# Index 0 = player side, index 1 = opponent side.
var _combatants: Array[BattlePokemon] = []
var _turn_order: Array[BattlePokemon] = []
# Chosen move per combatant, parallel to _combatants. Holds MoveData or null.
var _chosen_moves: Array = []
var _current_actor_index: int = 0


func start_battle(player_pokemon: BattlePokemon, opponent_pokemon: BattlePokemon) -> void:
	_combatants = [player_pokemon, opponent_pokemon]
	_chosen_moves = [null, null]
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# Push the state machine forward by one phase.
# Auto-advancing phases call this themselves. Phases that need input emit
# action_needed and then stop; external code calls advance() after supplying
# the choice.
func advance() -> void:
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
	_set_phase(BattlePhase.MOVE_SELECTION)
	advance()


func _phase_move_selection() -> void:
	# M1: auto-select first available move for each side.
	# M2+: emit action_needed, wait for player input and AI choice.
	# M6: charging Pokémon (two-turn turn 2) have their move forced to charging_move.
	# Source: battle_main.c — gLockedMoves forces action selection for two-turn moves.
	for i in range(_combatants.size()):
		if _combatants[i].charging_move != null:
			_chosen_moves[i] = _combatants[i].charging_move
		else:
			_chosen_moves[i] = _combatants[i].moves[0] if _combatants[i].moves.size() > 0 else null
	_set_phase(BattlePhase.PRIORITY_RESOLUTION)
	advance()


func _phase_priority_resolution() -> void:
	# Clear flinch volatile at the start of each turn so it lasts exactly one turn.
	# Source: battle_move_resolution.c :: CancelerFlinch — flinched is set by move execution
	# and checked on the NEXT turn's pre-move canceler chain.
	for mon: BattlePokemon in _combatants:
		mon.flinched = false
	_turn_order = _combatants.duplicate()
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
		return randi() % 2 == 0  # random tiebreak
	)
	_current_actor_index = 0
	_set_phase(BattlePhase.ACTION_EXECUTION)
	advance()


func _phase_action_execution() -> void:
	if _current_actor_index >= _turn_order.size():
		_set_phase(BattlePhase.END_OF_TURN)
		advance()
		return
	_set_phase(BattlePhase.PRE_MOVE_CHECKS)
	advance()


func _phase_pre_move_checks() -> void:
	var actor: BattlePokemon = _turn_order[_current_actor_index]

	if actor.fainted:
		_set_phase(BattlePhase.MOVE_EXECUTION)
		advance()
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
		advance()
		return

	_set_phase(BattlePhase.MOVE_EXECUTION)
	advance()


func _phase_move_execution() -> void:
	var attacker: BattlePokemon = _turn_order[_current_actor_index]

	if attacker.fainted:
		_current_actor_index += 1
		_set_phase(BattlePhase.ACTION_EXECUTION)
		advance()
		return

	var defender: BattlePokemon = _get_opponent(attacker)
	var move: MoveData = _chosen_moves[_combatants.find(attacker)]

	# User-thaw: frozen Pokémon using a thawsUser move thaws before dealing damage.
	# Source: battle_move_resolution.c :: CancelerThaw (L586–622); fires after the
	# attacker-canceler chain when MoveThawsUser(cv->move) is true.
	if StatusManager.check_user_thaw(attacker, move):
		pokemon_thawed.emit(attacker)

	# ── Two-turn charge/release ───────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerCharging (L1737)
	# Turn 1 (charge): attacker.charging_move == null → lock the move, set semi-inv,
	#   emit charge_started, record 0-damage move_executed, then skip to faint check.
	# Turn 2 (release): attacker.charging_move != null → clear charging state, fall
	#   through to the normal accuracy → damage pipeline.
	if move.two_turn:
		if attacker.charging_move == null:
			attacker.charging_move = move
			attacker.semi_invulnerable = move.semi_inv_state
			charge_started.emit(attacker, move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			advance()
			return
		else:
			# Turn 2: release — clear charge state before the attack resolves.
			attacker.charging_move = null
			attacker.semi_invulnerable = MoveData.SEMI_INV_NONE

	# ── Accuracy check ────────────────────────────────────────────────────────
	# Source: all move BattleScripts include accuracycheck before effect application.
	# Source: battle_script_commands.c :: Cmd_accuracycheck (L1058)
	# Includes semi-invulnerable miss check (source: CancelerAccuracyCheck L1993).
	if not StatusManager.check_accuracy(attacker, defender, move):
		move_missed.emit(attacker, "accuracy")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		advance()
		return

	if move.power > 0:
		# ── Damaging move ──────────────────────────────────────────────────────
		# DamageCalculator.calculate handles fixed_damage and level_damage internally.
		var result: Dictionary = DamageCalculator.calculate(attacker, defender, move)
		var damage: int = result["damage"]
		defender.current_hp = max(0, defender.current_hp - damage)
		move_executed.emit(attacker, defender, move, damage)

		# Target-thaw: Fire-type damaging move clears freeze on the defender.
		# Source: battle_script_commands.c :: CanFireMoveThawTarget (L11036–11038);
		#   B_HIT_THAW = GEN_LATEST >= GEN_3: TYPE_FIRE && power > 0 && damage > 0
		# Source: battle_move_resolution.c :: MoveEndDefrost (L3288–3314)
		if StatusManager.check_target_thaw(defender, move, damage):
			pokemon_thawed.emit(defender)

		# ── Recoil ─────────────────────────────────────────────────────────────
		# Source: battle_move_resolution.c :: EFFECT_RECOIL case (L3371)
		#   recoil = savedDmg * max(1, GetMoveRecoil(move)) / 100
		# We omit the max(1, pct) on the percentage because recoil_percent is
		# always ≥ 25 in practice; the floor means min damage is 0 (not 1).
		# Recoil can faint the attacker; faint_check handles it.
		if move.recoil_percent > 0 and damage > 0:
			var recoil: int = damage * move.recoil_percent / 100
			if recoil > 0:
				attacker.current_hp = max(0, attacker.current_hp - recoil)
				recoil_damage.emit(attacker, recoil)

		# ── Drain (absorb) ─────────────────────────────────────────────────────
		# Source: battle_move_resolution.c :: EFFECT_ABSORB case (L2635)
		#   heal = moveDamage * GetMoveAbsorbPercentage(move) / 100
		# heal capped at max_hp; 0 heal is possible for very small damage.
		if move.drain_percent > 0 and damage > 0:
			var heal: int = damage * move.drain_percent / 100
			if heal > 0:
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + heal)
				drain_heal.emit(attacker, heal)

		# ── Secondary effect (only fires if move connected: damage > 0) ────────
		# Source: battle_script_commands.c :: Cmd_setadditionaleffects (L3506)
		# For flinch: only apply if defender hasn't acted this turn.
		# Source: battle_move_resolution.c :: CancelerFlinch (L298)
		if damage > 0 and move.secondary_effect != MoveData.SE_NONE:
			var effect_hit: bool = StatusManager.try_secondary_effect(attacker, defender, move)
			if effect_hit:
				if move.secondary_effect == MoveData.SE_FLINCH:
					var defender_idx: int = _turn_order.find(defender)
					if defender_idx > _current_actor_index:
						defender.flinched = true
						secondary_applied.emit(defender, MoveData.SE_FLINCH)
					# else: flinch rolled but defender already acted — wasted, no signal
				else:
					secondary_applied.emit(defender, move.secondary_effect)
	else:
		# ── Status / stat-change move ─────────────────────────────────────────
		# Type immunity check for opponent-targeting moves:
		#   e.g. Thunder Wave (Electric) vs Ground-type: 0.0× → blocked.
		#   e.g. Confuse Ray (Ghost) vs Normal-type: 0.0× → blocked.
		# Source: battle_util.c :: CanSetNonVolatileStatus → IsBattlerUnaffectedByMove (L5276)
		# Self-targeting moves (Swords Dance) skip this check.
		var targets_foe: bool = not move.stat_change_self
		if targets_foe and move.type != TypeChart.TYPE_NONE:
			var eff: float = TypeChart.get_effectiveness(move.type, defender.species.types)
			if eff == 0.0:
				move_missed.emit(attacker, "immune")
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				advance()
				return

		if move.stat_change_stat >= 0:
			# ── Stat-change move (Swords Dance, Growl, Tail Whip, etc.) ────────
			var stat_target: BattlePokemon = attacker if move.stat_change_self else defender
			var actual: int = StatusManager.apply_stat_change(
					stat_target, move.stat_change_stat, move.stat_change_amount)
			if actual == 0:
				move_effect_failed.emit(stat_target, "stat_limit")
			else:
				stat_stage_changed.emit(stat_target, move.stat_change_stat, actual)

		elif move.secondary_effect != MoveData.SE_NONE:
			# ── Primary status/confusion move (Thunder Wave, Toxic, Confuse Ray, etc.) ─
			# secondary_chance == 0 means the effect is guaranteed (it's the whole point).
			# Source: BattleScript_EffectNonVolatileStatus / BattleScript_EffectConfuse
			var applied: bool = StatusManager.try_secondary_effect(attacker, defender, move)
			if applied:
				secondary_applied.emit(defender, move.secondary_effect)
			else:
				move_effect_failed.emit(defender, "immune")

		move_executed.emit(attacker, defender, move, 0)

	_current_actor_index += 1
	_set_phase(BattlePhase.FAINT_CHECK)
	advance()


func _phase_faint_check() -> void:
	for combatant: BattlePokemon in _combatants:
		if combatant.current_hp <= 0 and not combatant.fainted:
			combatant.fainted = true
			# Clear charge state on faint so stale charging_move can't persist.
			# Source: FaintClearSetData in battle_main.c clears all volatiles on faint.
			combatant.charging_move = null
			combatant.semi_invulnerable = MoveData.SEMI_INV_NONE
			pokemon_fainted.emit(combatant)

	for combatant: BattlePokemon in _combatants:
		if combatant.fainted:
			_set_phase(BattlePhase.BATTLE_END_CHECK)
			advance()
			return

	# Nobody fainted — continue the action execution loop or move to end of turn.
	if _current_actor_index < _turn_order.size():
		_set_phase(BattlePhase.ACTION_EXECUTION)
	else:
		_set_phase(BattlePhase.END_OF_TURN)
	advance()


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

	_set_phase(BattlePhase.BATTLE_END_CHECK)
	advance()


func _phase_switch_prompt() -> void:
	# M1 stub: 1v1 battle, switch mechanic not yet implemented.
	_set_phase(BattlePhase.BATTLE_END_CHECK)
	advance()


func _phase_battle_end_check() -> void:
	for i in range(_combatants.size()):
		if _combatants[i].fainted:
			_set_phase(BattlePhase.BATTLE_END)
			battle_ended.emit(1 - i)  # the non-fainted side wins
			return
	# No faints from end-of-turn effects — start the next turn.
	_set_phase(BattlePhase.MOVE_SELECTION)
	advance()


# --- Helpers ---

func _set_phase(p: BattlePhase) -> void:
	_phase = p
	phase_changed.emit(p)


func _get_opponent(pokemon: BattlePokemon) -> BattlePokemon:
	return _combatants[1] if pokemon == _combatants[0] else _combatants[0]
