class_name BattleManager
extends Node

# M11: Field-wide weather constants — mirrors DamageCalculator.WEATHER_*.
# Defined here for callers who reference BattleManager directly (tests, UI).
# Source: include/constants/battle.h :: enum BattleWeather / B_WEATHER_* bitmask.
# In source, gBattleWeather is a bitmask; we use a plain int enum (one active at a time).
const WEATHER_NONE:      int = DamageCalculator.WEATHER_NONE
const WEATHER_RAIN:      int = DamageCalculator.WEATHER_RAIN
const WEATHER_SUN:       int = DamageCalculator.WEATHER_SUN
const WEATHER_SANDSTORM: int = DamageCalculator.WEATHER_SANDSTORM
const WEATHER_HAIL:      int = DamageCalculator.WEATHER_HAIL

# Duration of ability-set weather in turns (no held-item extension in M11 scope).
# Source: TryChangeBattleWeather (battle_util.c L1996): gBattleStruct->weatherDuration = 5.
const WEATHER_DURATION_DEFAULT: int = 5

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
# M9 signals
signal pokemon_switched_out(pokemon: BattlePokemon, side: int)            # left the field
signal pokemon_switched_in(pokemon: BattlePokemon, side: int, slot: int)  # entered the field
signal forced_switch(old_mon: BattlePokemon, new_mon: BattlePokemon)      # Roar/Whirlwind result
signal baton_passed(from_mon: BattlePokemon, to_mon: BattlePokemon)       # Baton Pass completed
signal replacement_needed(side: int)                                       # fainted, party not empty
# M11 signals
signal weather_set(by_pokemon: BattlePokemon, weather_type: int)          # weather changed
signal weather_expired(weather_type: int)                                  # weather duration ran out
signal weather_damage(pokemon: BattlePokemon, amount: int)                 # sandstorm/hail chip
# M12 signals
signal item_consumed(pokemon: BattlePokemon, item: ItemData)               # one-use item activated
signal item_healed(pokemon: BattlePokemon, amount: int)                    # Leftovers / Sitrus Berry
signal item_damage(pokemon: BattlePokemon, amount: int)                    # Life Orb recoil
# M14b signals
signal helping_hand_used(user: BattlePokemon, ally: BattlePokemon)         # Helping Hand boosted ally
signal follow_me_used(user: BattlePokemon)                                 # Follow Me/Rage Powder active

signal screen_set(side: int, screen_name: String)                          # "reflect"/"light_screen"/"aurora_veil" went up
signal screen_expired(side: int, screen_name: String)                      # duration ran out
signal screens_broken(side: int)                                           # Brick Break cleared a side's screens


const MAX_PHASES_PER_ADVANCE: int = 4096

var _phase: BattlePhase = BattlePhase.BATTLE_START

# M9: per-side party objects. _combatants[i] = _parties[i].get_active().
var _parties: Array[BattleParty] = []
# Index 0 = player side, index 1 = opponent side — always the ACTIVE Pokémon.
var _combatants: Array[BattlePokemon] = []
var _turn_order: Array[BattlePokemon] = []
# Chosen move per combatant (null if that side is switching this turn).
var _chosen_moves: Array = []
# M9: switch slot per combatant (-1 = not switching, ≥0 = party slot to switch to).
var _chosen_switch_slots: Array[int] = []
# M9: actor→side map set at PRIORITY_RESOLUTION, used to recover side index mid-turn.
# Keyed by BattlePokemon object (the active mon at resolution time).
var _actor_sides: Dictionary = {}
var _current_actor_index: int = 0
var _is_advancing: bool = false

# M14a: number of active Pokémon per side (1 = singles, 2 = doubles).
# Governs combatant layout: _combatants[side * _active_per_side + field_slot].
var _active_per_side: int = 1

# M14a: per-actor combatant index (BattlePokemon → int 0..N-1).
# Set at PRIORITY_RESOLUTION alongside _actor_sides.
# Used wherever we need the combatant's position in _combatants (e.g. _chosen_moves lookup).
var _actor_indices: Dictionary = {}

# M14a: chosen target combatant index per actor this turn.
# _chosen_targets[combatant_idx] = the combatant index of the move's target.
# Defaults to the first opponent slot; overridden by queue_move_targeted actions.
var _chosen_targets: Array[int] = []

# M9: pre-queued action lists per combatant index.
# Each element: {"type": "switch", "slot": int} or {"type": "move", "index": int}
# or {"type": "move", "index": int, "target": int} for doubles.
# M14a: sized to 4 to support doubles (combatants 0-3). Singles only uses [0] and [1].
# Test suites fill these before start_battle*() to control turn order deterministically.
var _action_queues: Array = [[], [], [], []]

# M9: pre-queued replacement slots for SWITCH_PROMPT (faint replacement).
# -1 entry = auto-select first available non-fainted slot.
# M14a: indexed by combatant index (not side); [0]/[1] are singles-compatible.
var _replacement_queues: Array = [[], [], [], []]

# M9: forced RNG for Roar/Whirlwind candidate selection (for deterministic tests).
# -1 = use real RNG; ≥0 = index into candidates array.
var _force_roar_rng: int = -1

# Test seam: force accuracy check result for all moves this battle.
# null = use real RNG via StatusManager.check_accuracy; true = always hit; false = always miss.
# Mirrors the force_hit: Variant = null parameter already on StatusManager.check_accuracy.
# Use bm._force_hit = true in tests that need a guaranteed hit on a non-accuracy=0 move.
var _force_hit: Variant = null

# Test seam: force the damage roll for all damaging hits this battle.
# null = use real RNG (85-100 random roll, the same convention as _force_hit's null);
# 85-100 = pin to that exact roll. DamageCalculator.calculate's own force_roll param uses
# -1 as its "use real RNG" sentinel (int-typed, can't hold null), so this is converted at
# the _do_damaging_hit call site: _force_roll if _force_roll != null else -1.
# Use bm._force_roll = 100 in tests that need deterministic damage instead of a wide range.
var _force_roll: Variant = null

# Test seam: force the crit result for all damaging hits this battle.
# null = use real RNG; true = always crit; false = suppress crit (deterministic tests).
# Mirrors the force_crit: Variant = null parameter already on DamageCalculator.calculate —
# same null-sentinel convention on both sides, no conversion needed at the call site.
var _force_crit: Variant = null

# Test seam: force the contact-ability roll (Static / Flame Body trigger) for all
# damaging hits this battle.  null = use real RNG; true = always trigger; false = suppress.
# Mirrors force_contact_roll already accepted by AbilityManager.try_contact_effects —
# BM-9 fix threads this value through _do_damaging_hit so integration tests can control it.
var _force_contact_roll: Variant = null

# Test seam: force Magnitude's rolled power for all Magnitude uses this battle.
# null = use real RNG (weighted table roll); one of {10,30,50,70,90,110,150} = pin it.
# Mirrors the null-sentinel convention of the other _force_* seams above.
var _force_magnitude_power: Variant = null

# M9: pre-queued Baton Pass target slots per combatant index (-1 = auto-select first valid).
# M14a: indexed by combatant index; singles uses [0] and [1].
var _baton_pass_queues: Array = [[], [], [], []]

# M10: per-side TrainerAI instances (null = human / test-queue side).
# Set before start_battle*() with set_trainer_ai(side, ai).
var _trainer_ais: Array = [null, null]

# M14b: tracks the last Pokémon to deal damage to each target this turn.
# Key: BattlePokemon (defender), Value: BattlePokemon (attacker that last hit them).
# Cleared at the start of each turn (PRIORITY_RESOLUTION).
# Used by Destiny Bond: when a Destiny Bond holder faints, the killer is _last_attacker
# rather than _get_first_opponent (which is wrong in doubles if the second slot lands the KO).
# Source: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953) uses gBattlerAttacker
#   global at time of lethal hit — equivalent to tracking last attacker per target.
var _last_attacker: Dictionary = {}

# M14b: per-side Follow Me/Rage Powder state. -1 = no Follow Me active this turn.
# Value = combatant index of the Pokémon that used Follow Me/Rage Powder.
# Source: gSideTimers[side].followmeTimer / followmeTarget (battle_main.c L5060–5061).
# Cleared at the start of each turn (PRIORITY_RESOLUTION / TurnValuesCleanUp equivalent).
var _follow_me_targets: Array[int] = [-1, -1]

# M14b: per-combatant Helping Hand boost flag for this turn.
# True = this combatant's ally used Helping Hand; next damaging move gets 1.5× base power.
# Source: gProtectStructs[battler].helpingHand (battle_util.c L6436).
# Cleared at the start of each turn (PRIORITY_RESOLUTION / TurnValuesCleanUp equivalent).
var _helping_hand: Array[bool] = [false, false, false, false]

# M11: Field-wide weather state. Weather is NOT per-Pokémon — it's a battle-field
# effect that persists through switches (gBattleWeather + gBattleStruct->weatherDuration).
# Source: gBattleWeather (battle_util.c global), weatherDuration (gBattleStruct field).
var weather: int = WEATHER_NONE
var weather_duration: int = 0  # turns remaining; 0 when no weather is active

# M16c: per-side screen conditions (Reflect / Light Screen / Aurora Veil).
# Indexed by SIDE (0/1) — always length 2 regardless of singles/doubles, same convention as
# _follow_me_targets above (doubles just means 2 field slots share one side's conditions).
# These are side-bound, not battler-bound: they persist across the owning side's switches
# (nothing in _clear_volatiles / _switch_out_clear touches this array — by construction,
# since those operate on BattlePokemon, not on BattleManager's side-indexed state) and only
# clear on expiry (duration reaching 0) or an explicit screen-removal move (Brick Break).
# Source: gSideStatuses[side] (bitmask) + gSideTimers[side].{reflectTimer,lightscreenTimer,
#   auroraVeilTimer} (include/battle.h). Turns-remaining ints here fold together the
#   presence bit and the timer into one field per condition (0 = not active).
var _side_conditions: Array = [
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0},
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0},
]

# M15 Task 3: Struggle instantiated in _ready(); used when all PP are depleted.
# Source: battle_main.c L4727–4728 — noValidMoves → MOVE_STRUGGLE substitution.
var _struggle_move: MoveData = null


func _ready() -> void:
	_struggle_move = MoveData.new()
	_struggle_move.move_name = "Struggle"
	_struggle_move.type = TypeChart.TYPE_MYSTERY
	_struggle_move.category = 0
	_struggle_move.power = 50
	_struggle_move.pp = 1
	_struggle_move.accuracy = 0
	_struggle_move.is_struggle = true
	_struggle_move.makes_contact = true


# ── Entry points ────────────────────────────────────────────────────────────────

# Backward-compat 1v1 entry point: wraps each BattlePokemon into a 1-member BattleParty.
# All M1-M8 test suites call this signature and are unaffected by M9 party logic.
func start_battle(player_pokemon: BattlePokemon, opponent_pokemon: BattlePokemon) -> void:
	start_battle_with_parties(
		BattleParty.single(player_pokemon),
		BattleParty.single(opponent_pokemon))


# M9 entry point: full party on each side (singles).
func start_battle_with_parties(player_party: BattleParty,
		opponent_party: BattleParty) -> void:
	_active_per_side = 1
	_parties = [player_party, opponent_party]
	_combatants = [player_party.get_active(), opponent_party.get_active()]
	_chosen_moves = [null, null]
	_chosen_switch_slots = [-1, -1]
	_chosen_targets = [1, 0]  # each targets the single opponent
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# M14a entry point: 2v2 doubles. Each party must have active_indices = [0, 1].
# Combatant layout (side-grouped): [side0_slot0, side0_slot1, side1_slot0, side1_slot1].
# Source: gBattlerPositions — B_POSITION_PLAYER_LEFT=0, B_POSITION_PLAYER_RIGHT=2,
#   B_POSITION_OPPONENT_LEFT=1, B_POSITION_OPPONENT_RIGHT=3 (battle.h L1234).
#   We use side-grouped order (both player slots contiguous) rather than alternating.
func start_battle_doubles(player_party: BattleParty,
		opponent_party: BattleParty) -> void:
	_active_per_side = 2
	_parties = [player_party, opponent_party]
	_combatants = [
		player_party.get_active_at(0),
		player_party.get_active_at(1),
		opponent_party.get_active_at(0),
		opponent_party.get_active_at(1),
	]
	_chosen_moves   = [null, null, null, null]
	_chosen_switch_slots = [-1, -1, -1, -1]
	_chosen_targets = [2, 2, 0, 0]  # default: each targets first slot of opposing side
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# ── Action queue API (called by tests before start or between turns) ─────────

func queue_switch(side: int, slot: int) -> void:
	_action_queues[side].append({"type": "switch", "slot": slot})


func queue_move(side: int, move_index: int) -> void:
	_action_queues[side].append({"type": "move", "index": move_index})


func queue_replacement(side: int, slot: int) -> void:
	_replacement_queues[side].append(slot)


func queue_baton_pass_target(side: int, slot: int) -> void:
	_baton_pass_queues[side].append(slot)


# M14a: doubles-aware queue APIs. combatant_idx is 0-3 in doubles.
# queue_move_targeted also allows an explicit target (opposing combatant index).
func queue_move_targeted(combatant_idx: int, move_index: int, target_idx: int) -> void:
	_action_queues[combatant_idx].append(
		{"type": "move", "index": move_index, "target": target_idx})

func queue_switch_for(combatant_idx: int, slot: int) -> void:
	_action_queues[combatant_idx].append({"type": "switch", "slot": slot})

func queue_replacement_for(combatant_idx: int, slot: int) -> void:
	_replacement_queues[combatant_idx].append(slot)


# M10: attach a TrainerAI to one side. null = human / test-queue control.
# Source: BattleAI_SetupFlags assigns AI flags per battler (battle_ai_main.c L302).
func set_trainer_ai(side: int, ai) -> void:
	_trainer_ais[side] = ai


# M11/M12: Attempt to set field weather. Returns true if weather changed.
# Source: TryChangeBattleWeather (battle_util.c L1969–2015):
#   — Returns FALSE if gBattleWeather already has the requested weather flag active.
#   — Duration = 8 if setter holds the matching rock item, else 5.
#     (M12: rock extension via ItemManager.weather_duration; by_pokemon=null → default 5.)
#   — Primal weather override logic: not in scope.
func try_set_weather(weather_type: int, by_pokemon: BattlePokemon = null) -> bool:
	if weather == weather_type:
		return false
	weather = weather_type
	weather_duration = ItemManager.weather_duration(by_pokemon, weather_type) \
		if weather_type != WEATHER_NONE else 0
	return true


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
	# Fire switch-in ability effects for all starting Pokémon (they enter simultaneously).
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L3310)
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		_apply_switch_in_abilities(mon, i / _active_per_side)
	_set_phase(BattlePhase.MOVE_SELECTION)


func _phase_move_selection() -> void:
	# Determine action for each combatant. Priority order:
	# 1. Lock-in (charging / encored) — overrides queue and auto-select.
	# 2. Pre-queued action from _action_queues (for deterministic test control).
	# 3. TrainerAI decision (SMART/BASIC tiers).
	# 4. Auto-select: first available move.
	# Source: battle_main.c gLockedMoves + gBattleMons[].volatiles.encoredMove
	# M14a: iterates all combatants (2 in singles, 4 in doubles).
	#   _action_queues indexed by combatant index; side = combatant_idx / _active_per_side.
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		_chosen_switch_slots[i] = -1
		_chosen_targets[i] = _default_target(i)
		# Skip fainted combatants (doubles: a slot can be empty with no bench replacement).
		if mon.fainted:
			_chosen_moves[i] = null
			continue
		var side: int = i / _active_per_side
		if mon.charging_move != null:
			_chosen_moves[i] = mon.charging_move
		elif mon.encored_move != null:
			_chosen_moves[i] = mon.encored_move
		elif not _action_queues[i].is_empty():
			var action: Dictionary = _action_queues[i].pop_front()
			if action["type"] == "switch":
				_chosen_switch_slots[i] = action["slot"]
				_chosen_moves[i] = null
			else:
				var idx: int = action.get("index", 0)
				_chosen_moves[i] = mon.moves[idx] if idx < mon.moves.size() else null
				if action.has("target"):
					_chosen_targets[i] = action["target"]
		elif _trainer_ais[side] != null:
			# TrainerAI decides. Source: ComputeAiBattlerDecisions (battle_ai_main.c L401).
			# M14c: doubles uses choose_action_doubles (per-slot target scoring);
			#   singles uses choose_action (single defender).
			var ai: TrainerAI = _trainer_ais[side]
			var action: Dictionary
			if _active_per_side == 2:
				# Doubles: pass both opponent slots so AI can pick (move, target) jointly.
				# Source: ChooseMoveOrAction_Doubles (battle_ai_main.c L918).
				var opp_start: int = (1 - side) * _active_per_side
				var ally_idx: int = side * _active_per_side + (1 - i % _active_per_side)
				action = ai.choose_action_doubles(
						mon,
						_combatants[ally_idx],
						_combatants[opp_start], opp_start,
						_combatants[opp_start + 1], opp_start + 1,
						_parties[side], _parties[1 - side], weather)
			else:
				# Singles: original path, unchanged.
				var opponent: BattlePokemon = _get_first_opponent(mon)
				action = ai.choose_action(
						mon, opponent, _parties[side], _parties[1 - side], weather)
			if action["type"] == "switch":
				_chosen_switch_slots[i] = action["slot"]
				_chosen_moves[i] = null
			else:
				var idx: int = action.get("index", 0)
				_chosen_moves[i] = mon.moves[idx] if idx < mon.moves.size() else null
				if action.has("target"):
					_chosen_targets[i] = action["target"]
		else:
			_chosen_moves[i] = mon.moves[0] if mon.moves.size() > 0 else null
		# M12: Choice lock enforcement — overrides whatever path set above.
		# Source: gBattleStruct->chosenMovePositions[battler] checked in CanChooseMove.
		# Only applies when not switching and not already locked by a charge move.
		if mon.choice_locked_move != null and _chosen_switch_slots[i] < 0 \
				and mon.charging_move == null:
			_chosen_moves[i] = mon.choice_locked_move
		# M15 Task 3: Struggle override — all PP depleted forces Struggle.
		# Source: battle_main.c L4727-4728; CancelerPPDeduction skips Struggle (L979).
		if _is_forced_struggle(mon) and _chosen_switch_slots[i] < 0:
			_chosen_moves[i] = _struggle_move
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
		mon.switched_in_this_turn = false
	# M14b: clear per-turn Follow Me, Helping Hand, and last-attacker state.
	# Source: TurnValuesCleanUp (battle_main.c L5022): memset gProtectStructs (helpingHand),
	#   gSideTimers[].followmeTimer = 0 (L5060–5061).
	_last_attacker.clear()
	_follow_me_targets[0] = -1
	_follow_me_targets[1] = -1
	for _hi in range(_helping_hand.size()):
		_helping_hand[_hi] = false

	_turn_order = _combatants.duplicate()

	# Record actor→side and actor→combatant-index mappings before any switches.
	# _actor_sides: used for party lookup (0 or 1); _actor_indices: used for
	# _chosen_moves / _chosen_switch_slots / _chosen_targets indexing (0..3).
	# M14a: _actor_sides now stores the actual SIDE (i / _active_per_side),
	#   not the combatant index. Combatant index is in _actor_indices.
	_actor_sides = {}
	_actor_indices = {}
	for i in range(_combatants.size()):
		_actor_sides[_combatants[i]] = i / _active_per_side
		_actor_indices[_combatants[i]] = i

	var tiebreak: Dictionary = {}
	for mon in _combatants:
		tiebreak[mon] = randi()

	_turn_order.sort_custom(func(a: BattlePokemon, b: BattlePokemon) -> bool:
		# M14a: use _actor_indices (combatant index 0..N-1) to look up chosen actions,
		# not _actor_sides (which is now 0 or 1, not the combatant position).
		var ia: int = _actor_indices.get(a, _combatants.find(a))
		var ib: int = _actor_indices.get(b, _combatants.find(b))
		var a_switch: bool = _chosen_switch_slots[ia] >= 0
		var b_switch: bool = _chosen_switch_slots[ib] >= 0

		# Switch actions before all move actions.
		# Source: battle_main.c L4967-4990 — items/switches placed before moves
		# in gActionsByTurnOrder; speed sort only runs between move actors (L5004-5015).
		if a_switch != b_switch:
			return a_switch  # a goes first if a is switching

		# Both switching: side 0 before side 1 (battler iteration order in source).
		if a_switch:
			return ia < ib

		# Both using moves: priority bracket → effective speed → pre-rolled tiebreak.
		var move_a: MoveData = _chosen_moves[ia]
		var move_b: MoveData = _chosen_moves[ib]
		var pa: int = move_a.priority if move_a else 0
		var pb: int = move_b.priority if move_b else 0
		if pa != pb:
			return pa > pb
		var sa: int = StatusManager.effective_speed(a)
		var sb: int = StatusManager.effective_speed(b)
		if sa != sb:
			return sa > sb
		return tiebreak[a] > tiebreak[b]
	)
	_current_actor_index = 0
	_set_phase(BattlePhase.ACTION_EXECUTION)


func _phase_action_execution() -> void:
	# Skip fainted actors in a loop so the phase always changes.
	# M14a: in doubles a slot can be permanently fainted with no bench replacement,
	# so fainted skips may happen every turn. Re-dispatching to ACTION_EXECUTION would
	# trigger the advance() safety guard (_phase == phase_before → break), halting the
	# battle. A while loop here guarantees we exit with a different phase each dispatch.
	while _current_actor_index < _turn_order.size() \
			and _turn_order[_current_actor_index].fainted:
		_current_actor_index += 1

	if _current_actor_index >= _turn_order.size():
		_set_phase(BattlePhase.END_OF_TURN)
		return

	var actor: BattlePokemon = _turn_order[_current_actor_index]

	# M9/M14a: check if this actor chose to switch this turn.
	# Use combatant index (not side) to look up switch slots and invoke the switch.
	var actor_idx: int = _actor_indices.get(actor, _combatants.find(actor))
	if actor_idx >= 0 and _chosen_switch_slots[actor_idx] >= 0:
		var slot: int = _chosen_switch_slots[actor_idx]
		_chosen_switch_slots[actor_idx] = -1
		_do_voluntary_switch(actor_idx, slot)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	_set_phase(BattlePhase.PRE_MOVE_CHECKS)


func _phase_pre_move_checks() -> void:
	var actor: BattlePokemon = _turn_order[_current_actor_index]

	if actor.fainted:
		_set_phase(BattlePhase.MOVE_EXECUTION)
		return

	# Status pre-move checks — source: battle_move_resolution.c canceler chain
	# Order: sleep → freeze → confusion → paralysis (matching source canceler order)
	# Pass chosen_move so pre_move_check gates the freeze block on !MoveThawsUser
	# (source L172); a thaws_user move skips the 20% roll and leaves the Pokémon
	# frozen-but-acting; check_user_thaw in MOVE_EXECUTION then thaws it.
	var chosen_move: MoveData = _chosen_moves[_combatants.find(actor)]
	var check: Dictionary = StatusManager.pre_move_check(
			actor, null, null, null, null, chosen_move)

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

	# M14a: use combatant index for move/target lookup; derive side from that.
	var attacker_idx: int = _actor_indices.get(attacker, _combatants.find(attacker))
	var attacker_side: int = attacker_idx / _active_per_side
	var defender: BattlePokemon = _combatants[_chosen_targets[attacker_idx]]
	var move: MoveData = _chosen_moves[attacker_idx]

	# M14a: if chosen target fainted earlier in this turn (doubles only — in singles
	# the only opponent slot has a replacement or the battle has already ended),
	# redirect to the first non-fainted opposing slot.
	if defender.fainted:
		var opp_start: int = (1 - attacker_side) * _active_per_side
		var redirect: BattlePokemon = null
		for fi in range(_active_per_side):
			var cand: BattlePokemon = _combatants[opp_start + fi]
			if not cand.fainted:
				redirect = cand
				break
		if redirect == null:
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		defender = redirect

	# M14b: Follow Me / Rage Powder redirect — single-target damaging moves aimed at
	# a side with an active Follow Me user are redirected to that user instead.
	# Source: IsAffectedByFollowMe (battle_move_resolution.c L799):
	#   redirects TARGET_SELECTED/SMART/OPPONENT/RANDOM moves; spread moves bypass entirely.
	# Source: GetBattleMoveTarget (battle_util.c L5529): check fires at target resolution.
	# Only applies to moves with power > 0 (damaging). Status moves targeting the opponent
	# can also be redirected in source, but limit to damaging moves for M14b scope.
	if not move.is_spread and move.power > 0:
		var def_side: int = 1 - attacker_side
		var fm_idx: int = _follow_me_targets[def_side]
		if fm_idx >= 0 and fm_idx < _combatants.size():
			var fm_user: BattlePokemon = _combatants[fm_idx]
			if not fm_user.fainted and fm_user != attacker:
				defender = fm_user

	# M12: Set choice lock immediately when a choice-item holder commits to a move.
	# Source: ProcessChoiceItem in battle_script_commands.c — fires before accuracy check.
	# Not set during a charge lock (charging_move handles that separately).
	if move != null and ItemManager.is_choice_item(attacker) \
			and attacker.choice_locked_move == null and attacker.charging_move == null:
		attacker.choice_locked_move = move

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

	# M15 Task 3: Decrement PP (charge turn only for two-turn moves; never for Struggle).
	# Source: battle_script_commands.c :: Cmd_decrementmovepointvalue (L5960);
	#   CancelerPPDeduction skips if cv->move == MOVE_STRUGGLE (L979).
	if not move.is_struggle and attacker.charging_move == null:
		var move_idx: int = attacker.moves.find(move)
		if move_idx >= 0:
			attacker.use_pp(move_idx)

	# ── Two-turn charge/release ───────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerCharging (L1737)
	# Solar Beam shortcut: skip charge turn entirely in harsh sun.
	# Source: CanTwoTurnMoveFireThisTurn (L1664) — returns TRUE when
	#   weather & B_WEATHER_SUN and move has twoTurnAttackWeather == B_WEATHER_SUN.
	#   Semi-inv moves (Fly/Dig/Dive/Bounce) can NEVER fire early.
	var _solar_skip: bool = (
		move.is_solar_beam
		and attacker.charging_move == null
		and weather == WEATHER_SUN
	)
	if move.two_turn and not move.is_bide and not _solar_skip:
		if attacker.charging_move == null:
			# Charge-turn stat boost (Skull Bash: +1 Defense on charge turn only).
			# Source: moves_info.h MOVE_SKULL_BASH additionalEffects
			#   {MOVE_EFFECT_STAT_PLUS, .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE}
			if move.charge_turn_defense_boost > 0:
				var actual_boost: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, move.charge_turn_defense_boost)
				if actual_boost != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, actual_boost)
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
	# Moves with ignores_protect bypass this (e.g. Feint — M8+ scope; Roar/Whirlwind).
	if defender.protect_active and not move.ignores_protect:
		move_missed.emit(attacker, "protected")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── OHKO (Guillotine / Horn Drill / Fissure / Sheer Cold) ─────────────────
	# Source: battle_util.c :: DoesOHKOMoveMissTarget (L10378)
	# Bypasses normal accuracy check entirely; has its own level-based formula.
	# Protect already blocked above; type immunity checked here before level fail.
	# On hit: damage = defender.current_hp regardless of stats.
	# Source: battle_util.c L7696: case EFFECT_OHKO: dmg = gBattleMons[ctx->battlerDef].hp
	if move.is_ohko:
		# Type immunity (ability-based and type chart) — same checks as damaging moves.
		if AbilityManager.blocks_move_type(defender, move.type):
			move_missed.emit(attacker, "immune")
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		if move.type != TypeChart.TYPE_NONE:
			var ohko_eff: float = TypeChart.get_effectiveness(move.type, defender.species.types)
			if ohko_eff == 0.0:
				move_missed.emit(attacker, "immune")
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
		# Semi-invulnerable check: OHKO moves respect semi-invulnerability like normal moves.
		# Source: CancelerAccuracyCheck (battle_move_resolution.c L1993) — fires before OHKO check.
		# Fissure has damages_underground=true so it can hit Dig users.
		if _force_hit == null and defender.semi_invulnerable != MoveData.SEMI_INV_NONE:
			var ohko_can_hit: bool = (
				(defender.semi_invulnerable == MoveData.SEMI_INV_UNDERGROUND and move.damages_underground) or
				(defender.semi_invulnerable == MoveData.SEMI_INV_ON_AIR and move.damages_airborne) or
				(defender.semi_invulnerable == MoveData.SEMI_INV_UNDERWATER and move.damages_underwater))
			if not ohko_can_hit:
				move_missed.emit(attacker, "semi_invulnerable")
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
		# Level check: fail if defender.level > attacker.level.
		# Source: DoesOHKOMoveMissTarget L10382: battlerDef.level > battlerAtk.level → fail.
		if defender.level > attacker.level:
			move_missed.emit(attacker, "ohko_failed")
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# Custom accuracy roll: odds = move.accuracy + (atk.level − def.level), vs randi() % 100.
		# Source: DoesOHKOMoveMissTarget L10390: odds = GetMoveAccuracy + (atk.level − def.level).
		var ohko_acc: int = move.accuracy + (attacker.level - defender.level)
		var ohko_hit: bool
		if _force_hit != null:
			ohko_hit = bool(_force_hit)
		else:
			ohko_hit = randi() % 100 < ohko_acc
		if not ohko_hit:
			move_missed.emit(attacker, "accuracy")
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# Hit! Deal defender.current_hp as damage (instant KO).
		_last_attacker[defender] = attacker
		_apply_fixed_dmg_to_target(attacker, defender, move, defender.current_hp)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Rollout / Ice Ball power scaling ──────────────────────────────────────
	# Source: battle_util.c :: CalcRolloutBasePower (L6034-6042):
	#   basePower = move.power; basePower <<= rolloutTimer; if (defenseCurl) basePower *= 2.
	# rollout_turns holds the pre-hit consecutive-use count (0 = fresh start), carried over
	# from the previous turn's post-hit bookkeeping below. Computed before the accuracy
	# check since the power for THIS hit doesn't depend on this hit's own outcome.
	# _dmg_power_override feeds _do_damaging_hit below; -1 = use move.power unmodified.
	var _dmg_power_override: int = -1
	if move.is_rollout:
		var _rb_power: int = move.power
		for _ri in range(attacker.rollout_turns):
			_rb_power *= 2
		if attacker.defense_curled:
			_rb_power *= 2
		attacker.rollout_base_power = _rb_power
		_dmg_power_override = _rb_power

	# ── Magnitude: roll variable base power once per use ──────────────────────
	# Source: battle_move_resolution.c :: CalculateMagnitudeDamage (L5196-5234) — weighted
	#   table {10,30,50,70,90,110,150} with bands {5,10,20,30,20,10,5}% respectively.
	if move.is_magnitude:
		_dmg_power_override = _roll_magnitude_power()

	# ── Accuracy check ────────────────────────────────────────────────────────
	# Source: battle_script_commands.c :: Cmd_accuracycheck (L1058)
	# Includes semi-invulnerable miss check (source: CancelerAccuracyCheck L1993).
	if not StatusManager.check_accuracy(attacker, defender, move, _force_hit):
		# Source: SetSameMoveTurnValues, case EFFECT_ROLLOUT (L4899): increment requires
		#   IsAnyTargetAffected() — a miss resets the consecutive-hit counter to 0.
		if move.is_rollout:
			attacker.rollout_turns = 0
		move_missed.emit(attacker, "accuracy")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Roar / Whirlwind ─────────────────────────────────────────────────────
	# Source: data/moves_info.h MOVE_ROAR / MOVE_WHIRLWIND :: .effect = EFFECT_ROAR
	# Source: battle_script_commands.c L7421 — gProtectStructs[target].forcedSwitch = TRUE
	# Fails if defender has no valid non-fainted switch-in (no party members left).
	# priority = -6 means Roar/Whirlwind always go last; they bypass Protect/Substitute.
	if move.is_roar:
		var def_side: int = 1 - attacker_side
		var def_party: BattleParty = _parties[def_side]
		var rand_slot: int = def_party.get_random_non_fainted_not_active(_force_roar_rng)
		if rand_slot < 0:
			move_effect_failed.emit(attacker, "no_switch_target")
		else:
			var old_defender: BattlePokemon = defender
			# M14b: force out the targeted combatant's field slot, not always slot 0.
			# Source: Cmd_BS_JumpIfRoarFails (battle_script_commands.c L7426):
			#   gProtectStructs[gBattlerTarget].forcedSwitch = TRUE — applies to the
			#   actual targeted battler, not a hardcoded position.
			var def_field_slot: int = _combatants.find(defender) % _active_per_side
			_do_forced_switch_in(def_side, rand_slot, def_field_slot)
			forced_switch.emit(old_defender, _parties[def_side].get_active_at(def_field_slot))
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Baton Pass ────────────────────────────────────────────────────────────
	# Source: data/moves_info.h MOVE_BATON_PASS :: .effect = EFFECT_BATON_PASS
	# Source: battle_main.c :: SwitchInClearSetData (L3117) — stat stages preserved,
	#   confusionTurns / substituteHP explicitly re-applied (L3146–3185).
	# Fails if attacker's party has no valid switch-in target.
	# Switch-in abilities (Intimidate) fire for the incoming Pokémon.
	if move.is_baton_pass:
		var att_party: BattleParty = _parties[attacker_side]
		if not att_party.has_valid_switch_target():
			move_effect_failed.emit(attacker, "no_switch_target")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		var saved: Dictionary = _baton_pass_save(attacker)
		_switch_out_clear(attacker)
		# Determine which slot to bring in.
		var bp_slot: int = _get_baton_pass_slot(attacker_idx)
		var bp_field_slot: int = attacker_idx % _active_per_side
		att_party.active_indices[bp_field_slot] = bp_slot
		_combatants[attacker_idx] = att_party.get_active_at(bp_field_slot)
		var incoming: BattlePokemon = _combatants[attacker_idx]
		_baton_pass_apply(incoming, saved)
		pokemon_switched_out.emit(attacker, attacker_side)
		pokemon_switched_in.emit(incoming, attacker_side, bp_slot)
		baton_passed.emit(attacker, incoming)
		# Switch-in abilities fire for the incoming Pokémon.
		var bp_actual: int = AbilityManager.try_switch_in(incoming, defender)
		if bp_actual != 0:
			stat_stage_changed.emit(defender, BattlePokemon.STAGE_ATK, bp_actual)
			ability_triggered.emit(incoming, "intimidate")
		var bp_set_w: int = AbilityManager.get_switch_in_weather(incoming)
		if bp_set_w != WEATHER_NONE and try_set_weather(bp_set_w, incoming):
			weather_set.emit(incoming, bp_set_w)
		move_executed.emit(attacker, defender, move, 0)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Metronome: select random move and execute it ──────────────────────────
	# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
	#   Picks a random move not banned by metronomeBanned flag (BAN_METRONOME in our system).
	# The called move replaces the original move object for the remainder of the execution path —
	# it routes through all normal effect handlers (damage, status, stat change, etc.).
	# `move_called` signal fires with the chosen move before execution.
	# If pool is empty (degenerate case): `move_effect_failed("metronome_no_moves")`.
	# `last_move_used` is set to the ORIGINAL Metronome move (not the called move) — consistent with
	# source where gLastMoves[] tracks the move slot used, not the called move.
	# Wait: actually the code sets `attacker.last_move_used = move` AFTER the Metronome redirect,
	# where `move` has been overwritten with the called move. This means last_move_used = called move.
	# This is fine for M7; revisit if Encore/Disable interactions with Metronome-called moves matter.
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

	# ── Rollout / Ice Ball: interruption reset ────────────────────────────────
	# Source: battle_move_resolution.c :: SetSameMoveTurnValues `default` case
	#   (L4915-4917): using any move OTHER than Rollout unconditionally resets
	#   rolloutTimer to 0 — this is how switching moves breaks the power streak.
	if not move.is_rollout:
		attacker.rollout_turns = 0

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
		# M14b: spread moves hit all live opposing combatants independently.
		# Source: IsSpreadMove (include/battle.h L1163): TARGET_BOTH or TARGET_FOES_AND_ALLY.
		# Source: IsDoubleSpreadMove (battle_util.c L10662): numSpreadTargets > 1 AND spread.
		# Each target gets a full independent calc (accuracy, damage, secondary effects).
		if move.is_spread and _active_per_side > 1:
			# Count live targets on opposing side to determine if spread reduction applies.
			# Source: GetMoveTargetCount (battle_util.c L5982): counts non-absent (non-fainted).
			# Immune targets are alive → still count → spread reduction applies even if immune.
			var opp_start: int = (1 - attacker_side) * _active_per_side
			var live_target_count: int = 0
			for _fi in range(_active_per_side):
				var _c: BattlePokemon = _combatants[opp_start + _fi]
				if not _c.fainted and _c.current_hp > 0:
					live_target_count += 1
			var spread_dmg_reduction: bool = live_target_count >= 2
			var hh_boost: bool = _helping_hand[attacker_idx]
			for _fi in range(_active_per_side):
				var tgt: BattlePokemon = _combatants[opp_start + _fi]
				if tgt.fainted or tgt.current_hp <= 0:
					continue
				_do_damaging_hit(attacker, tgt, move, spread_dmg_reduction, hh_boost,
						_dmg_power_override)
		else:
			# Single-target damaging move.
			var hh_boost: bool = _helping_hand[attacker_idx]
			_do_damaging_hit(attacker, defender, move, false, hh_boost, _dmg_power_override)

		# ── Rollout / Ice Ball: advance the consecutive-hit counter ───────────────
		# Source: SetSameMoveTurnValues, case EFFECT_ROLLOUT (L4899-4909): a successful
		#   hit increments rolloutTimer; reaching 5 resets it back to 0 (fresh start on the
		#   next use). The accuracy-check branch above already handles the miss-reset case.
		if move.is_rollout:
			attacker.rollout_turns += 1
			if attacker.rollout_turns >= 5:
				attacker.rollout_turns = 0
		# M15 Task 3: Struggle recoil — 1/4 max HP (not % of damage dealt).
		# Source: BattleScript_EffectRecoilHP (battle_script_commands.c L2534–2543).
		if move.is_struggle and not attacker.fainted:
			var struggle_recoil: int = max(1, attacker.max_hp / 4)
			attacker.current_hp = max(0, attacker.current_hp - struggle_recoil)
			recoil_damage.emit(attacker, struggle_recoil)
	else:
		# ── Status / stat-change / unique-effect move ─────────────────────────

		# ── Helping Hand ──────────────────────────────────────────────────────
		# Grants the user's ally a 1.5× base-power boost on their next damaging move.
		# Source: Cmd_trysethelpinghand (battle_script_commands.c L8850):
		#   fails if not doubles, ally is fainted, or ally has already acted this turn.
		#   Sets gProtectStructs[ally].helpingHand++ (cleared by TurnValuesCleanUp EOT).
		# Source: target = TARGET_ALLY (Gen 4+), priority = +5.
		if move.is_helping_hand:
			if _active_per_side < 2:
				move_effect_failed.emit(attacker, "not_doubles")
			else:
				var ally_idx: int = attacker_side * _active_per_side \
						+ (1 - attacker_idx % _active_per_side)
				var ally: BattlePokemon = _combatants[ally_idx]
				var ally_turn_pos: int = _turn_order.find(ally)
				var ally_has_acted: bool = ally_turn_pos >= 0 \
						and ally_turn_pos <= _current_actor_index
				if ally.fainted or ally_has_acted:
					move_effect_failed.emit(attacker, "helping_hand_failed")
				else:
					_helping_hand[ally_idx] = true
					helping_hand_used.emit(attacker, ally)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Follow Me / Rage Powder ───────────────────────────────────────────
		# Redirects all incoming single-target moves toward the user this turn.
		# Source: Cmd_setforcedtarget (battle_script_commands.c L8748):
		#   gSideTimers[user_side].followmeTimer = 1; followmeTarget = user.
		# Source: target = TARGET_USER, priority = +2.
		if move.is_follow_me:
			_follow_me_targets[attacker_side] = attacker_idx
			follow_me_used.emit(attacker)
			move_executed.emit(attacker, attacker, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

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

		# ── Restore HP (Recover / Slack Off / Heal Order) ─────────────────────
		# Source: battle_script_commands.c :: Cmd_tryhealhalfhealth (L7016)
		#   heal = GetNonDynamaxMaxHP(target) / 2; fails if current_hp == max_hp.
		if move.is_restore_hp:
			if attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				var restore_heal: int = max(1, attacker.max_hp / 2)
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + restore_heal)
				drain_heal.emit(attacker, restore_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Focus Energy ──────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_setfocusenergy (L7718)
		#   volatiles.focusEnergy = TRUE; fails if already set.
		# Crit stage boost wired in DamageCalculator._roll_crit (+2 stages).
		if move.is_focus_energy:
			if attacker.focus_energy:
				move_effect_failed.emit(attacker, "already_focus_energy")
			else:
				attacker.focus_energy = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Growth ────────────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_GROWTH (L2003): B_UPDATED_MOVE_DATA >= GEN_5 →
		#   raises ATK +1 AND SpATK +1 (Gen 5+). In harsh sun: +2 to both.
		# Source: battle_stat_change.c :: AdjustStatStage (L800):
		#   if EFFECT_GROWTH and weather == B_WEATHER_SUN → stage = 2.
		if move.is_growth:
			var growth_amt: int = 2 if weather == WEATHER_SUN else 1
			var g_atk: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_ATK, growth_amt)
			if g_atk != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_ATK, g_atk)
			var g_spatk: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_SPATK, growth_amt)
			if g_spatk != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPATK, g_spatk)
			if g_atk == 0 and g_spatk == 0:
				move_effect_failed.emit(attacker, "stat_limit")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Minimize ──────────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_MINIMIZE additionalEffects {STAT_CHANGE_EFFECT_PLUS,
		#   .evasion = 2} (B_MINIMIZE_EVASION >= GEN_5, GEN_LATEST config).
		# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case
		#   EFFECT_MINIMIZE (L1000): volatiles.minimize = TRUE only if the evasion raise
		#   actually succeeded (MOVE_RESULT_STAT_CHANGED).
		if move.is_minimize:
			var min_actual: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_EVASION, 2)
			if min_actual != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_EVASION, min_actual)
				attacker.minimized = true
			else:
				move_effect_failed.emit(attacker, "stat_limit")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Defense Curl ──────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_DEFENSE_CURL additionalEffects
		#   {STAT_CHANGE_EFFECT_PLUS, .defense = 1}.
		# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case
		#   EFFECT_DEFENSE_CURL (L997): volatiles.defenseCurl = TRUE unconditionally,
		#   regardless of whether the Defense raise itself succeeded.
		if move.is_defense_curl:
			var dc_actual: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, 1)
			if dc_actual != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, dc_actual)
			else:
				move_effect_failed.emit(attacker, "stat_limit")
			attacker.defense_curled = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Reflect ───────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: TrySetReflect (L2088-2106): fails (does not
		#   refresh) if SIDE_STATUS_REFLECT already set on the caster's side; else sets it
		#   with a 5-turn timer.
		if move.is_reflect:
			if _side_conditions[attacker_side]["reflect_turns"] > 0:
				move_effect_failed.emit(attacker, "already_reflect")
			else:
				_side_conditions[attacker_side]["reflect_turns"] = 5
				screen_set.emit(attacker_side, "reflect")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Light Screen ─────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: TrySetLightScreen (L2109-2127): same shape as
		#   TrySetReflect but SIDE_STATUS_LIGHTSCREEN / lightscreenTimer.
		if move.is_light_screen:
			if _side_conditions[attacker_side]["light_screen_turns"] > 0:
				move_effect_failed.emit(attacker, "already_light_screen")
			else:
				_side_conditions[attacker_side]["light_screen_turns"] = 5
				screen_set.emit(attacker_side, "light_screen")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Aurora Veil ──────────────────────────────────────────────────────
		# Source: battle_move_resolution.c (L1191-1193): fails outright unless
		#   GetWeather() & B_WEATHER_ICY_ANY — checked BEFORE the "already up" check (this
		#   project only models Hail, no separate Snow weather, so the gate is
		#   weather == WEATHER_HAIL). Source: BS_SetAuroraVeil (L13439-13462): fails only if
		#   SIDE_STATUS_AURORA_VEIL already set — independent of Reflect/Light Screen, so it
		#   can be set even if either (or both) of those are already up on the same side.
		if move.is_aurora_veil:
			if weather != WEATHER_HAIL:
				move_effect_failed.emit(attacker, "no_hail")
			elif _side_conditions[attacker_side]["aurora_veil_turns"] > 0:
				move_effect_failed.emit(attacker, "already_aurora_veil")
			else:
				_side_conditions[attacker_side]["aurora_veil_turns"] = 5
				screen_set.emit(attacker_side, "aurora_veil")
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
				# M12: Lum Berry cures status inflicted by status move primary effect.
				if ItemManager.lum_berry_cures(defender):
					defender.status = BattlePokemon.STATUS_NONE
					_consume_item(defender)
			else:
				move_effect_failed.emit(defender, "immune")

		move_executed.emit(attacker, defender, move, 0)

	_current_actor_index += 1
	_set_phase(BattlePhase.FAINT_CHECK)


func _phase_faint_check() -> void:
	# Capture and process any new faints (hp == 0 and not yet marked fainted).
	# Track whether ANY new faint occurred this tick — only these warrant SWITCH_PROMPT.
	# Previously-fainted slots (fainted=true from an earlier turn) must NOT re-trigger
	# SWITCH_PROMPT or the doubles no-bench scenario loops forever: every post-turn-1
	# action would jump back to SWITCH_PROMPT because B0.fainted is still true.
	var any_new_faint := false
	for combatant: BattlePokemon in _combatants:
		if combatant.current_hp <= 0 and not combatant.fainted:
			any_new_faint = true
			# Capture before clearing: Destiny Bond check.
			# Source: battle_main.c :: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953)
			#   If the fainted mon had destinyBond active, the Pokémon who KO'd it also faints.
			var had_destiny_bond: bool = combatant.destiny_bond
			combatant.fainted = true
			# Clear ALL volatiles on faint.
			# Source: FaintClearSetData in battle_main.c clears gBattleMons[].volatiles.
			_clear_volatiles(combatant)
			pokemon_fainted.emit(combatant)
			# Destiny Bond: KO the Pokémon that dealt the fatal blow (if still standing).
			# M14b: use _last_attacker[combatant] rather than _get_first_opponent — in doubles
			# the fatal hit may come from the second opposing slot, not the first.
			# Source: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953):
			#   checks gBattlerAttacker (the attacker that caused the faint), not a side index.
			if had_destiny_bond:
				var killer: BattlePokemon = _last_attacker.get(combatant, null)
				if killer == null:
					killer = _get_first_opponent(combatant)  # fallback for edge cases
				if not killer.fainted:
					killer.current_hp = 0
					killer.fainted = true
					_clear_volatiles(killer)
					destiny_bond_triggered.emit(combatant, killer)
					pokemon_fainted.emit(killer)

	# If any new faint occurred this tick, go to SWITCH_PROMPT.
	# M9: SWITCH_PROMPT handles replacements and checks full-party faint.
	if any_new_faint:
		_set_phase(BattlePhase.SWITCH_PROMPT)
		return

	# Nobody newly fainted — continue the action execution loop or move to end of turn.
	if _current_actor_index < _turn_order.size():
		_set_phase(BattlePhase.ACTION_EXECUTION)
	else:
		_set_phase(BattlePhase.END_OF_TURN)


func _phase_end_of_turn() -> void:
	# ── M11: Weather duration tick (ENDTURN_WEATHER, position 2 in source handler table) ──
	# Source: HandleEndTurnWeather → EndOrContinueWeather (battle_util.c L244):
	#   if (weatherDuration > 0 && --weatherDuration == 0) → gBattleWeather = B_WEATHER_NONE
	# Tick fires BEFORE weather chip damage and BEFORE status damage.
	if weather != WEATHER_NONE and weather_duration > 0:
		weather_duration -= 1
		if weather_duration == 0:
			var expired_w: int = weather
			weather = WEATHER_NONE
			weather_expired.emit(expired_w)

	# ── M11: Weather chip damage (ENDTURN_WEATHER_DAMAGE, position 3) ────────────────────
	# Source: HandleEndTurnWeatherDamage (battle_end_turn.c L100–186).
	# Fires BEFORE poison/burn (ENDTURN_POISON=12, ENDTURN_BURN=13 in handler table).
	# SANDSTORM: immune if any type is Rock(6)/Ground(5)/Steel(9), or semi-invulnerable.
	#   Source: IS_BATTLER_ANY_TYPE(battler, TYPE_ROCK, TYPE_GROUND, TYPE_STEEL) (L148).
	#   Ability-based immunities (Sand Veil, Sand Force, Sand Rush, Overcoat, Magic Guard)
	#   deferred to M12 — not in scope while those abilities are absent.
	# HAIL: immune if any type is Ice(16), or semi-invulnerable.
	#   Source: IS_BATTLER_OF_TYPE(battler, TYPE_ICE) (L171).
	#   Ability-based immunities (Snow Cloak, Ice Body, Overcoat) deferred to M12.
	# Damage = maxHP / 16 (integer division). Source: GetNonDynamaxMaxHP(battler) / 16 (L154, L177).
	if weather == WEATHER_SANDSTORM or weather == WEATHER_HAIL:
		for mon: BattlePokemon in _turn_order:
			if mon.fainted:
				continue
			if _is_weather_damage_immune(mon, weather):
				continue
			var chip: int = mon.max_hp / 16
			if chip > 0:
				mon.current_hp = max(0, mon.current_hp - chip)
				weather_damage.emit(mon, chip)
				if mon.current_hp == 0:
					mon.fainted = true
					pokemon_fainted.emit(mon)

	# ── Status damage (ENDTURN_POISON=12, ENDTURN_BURN=13 in source handler table) ────────
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

	# M12: Leftovers EOT heal (FIRST_EVENT_BLOCK_HEAL_ITEMS, after status damage).
	# Source: TryLeftovers (battle_hold_effects.c L634–648); fires via FIRST_EVENT_BLOCK_HEAL_ITEMS
	#   which is position 19 in battle_end_turn.c handler table (after ENDTURN_BURN=13).
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var lft_heal: int = ItemManager.leftovers_heal(mon)
		if lft_heal > 0:
			mon.current_hp = min(mon.max_hp, mon.current_hp + lft_heal)
			item_healed.emit(mon, lft_heal)

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

	# M16c: Decrement Reflect/Light Screen/Aurora Veil timers, both sides.
	# Source: battle_end_turn.c :: HandleEndTurnSecondEventBlock, cases
	#   SECOND_EVENT_BLOCK_REFLECT / _LIGHT_SCREEN / _AURORA_VEIL (L1025-1127): decrement;
	#   at 0, clear the side-status bit and fire the "wore off" message.
	for side in range(2):
		var sc: Dictionary = _side_conditions[side]
		if sc["reflect_turns"] > 0:
			sc["reflect_turns"] -= 1
			if sc["reflect_turns"] == 0:
				screen_expired.emit(side, "reflect")
		if sc["light_screen_turns"] > 0:
			sc["light_screen_turns"] -= 1
			if sc["light_screen_turns"] == 0:
				screen_expired.emit(side, "light_screen")
		if sc["aurora_veil_turns"] > 0:
			sc["aurora_veil_turns"] -= 1
			if sc["aurora_veil_turns"] == 0:
				screen_expired.emit(side, "aurora_veil")

	# End-of-turn ability effects (Speed Boost, etc.)
	# Source: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (battle_util.c L3605)
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var spd_actual: int = AbilityManager.try_end_of_turn(mon)
		if spd_actual != 0:
			stat_stage_changed.emit(mon, BattlePokemon.STAGE_SPEED, spd_actual)
			ability_triggered.emit(mon, "speed_boost")

	# Route through SWITCH_PROMPT even after EOT so any EOT faint gets a replacement.
	_set_phase(BattlePhase.SWITCH_PROMPT)


func _phase_switch_prompt() -> void:
	# For each fainted combatant, send in a replacement if one is available.
	# Source: battle_main.c :: L3671+, monToSwitchIntoId, SwitchInClearSetData.
	# M14a: iterates all combatants (not just parties); supports doubles where
	#   one side can have a fainted slot with no bench (other active slot still fights).
	for ci in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[ci]
		if not mon.fainted:
			continue
		var side: int = ci / _active_per_side
		var party: BattleParty = _parties[side]
		if party.is_fully_fainted():
			continue  # no replacements; BATTLE_END_CHECK will declare winner
		# Determine replacement slot (-1 = no bench member available).
		var slot: int = _get_replacement_slot(ci)
		if slot < 0:
			continue  # all surviving party members are already active (doubles)
		_do_switch_in(ci, slot)
		replacement_needed.emit(side)
	_set_phase(BattlePhase.BATTLE_END_CHECK)


func _phase_battle_end_check() -> void:
	# M9: check whether a WHOLE PARTY is fainted (not just the active member).
	# Source: M1 intent — BATTLE_END_CHECK originally checked gBattleMons[].hp,
	# which covers only the active slot; M9 extends to the full party.
	for i in range(_parties.size()):
		if _parties[i].is_fully_fainted():
			_set_phase(BattlePhase.BATTLE_END)
			battle_ended.emit(1 - i)  # the other side wins
			return
	# No side fully fainted — start the next turn.
	_set_phase(BattlePhase.MOVE_SELECTION)


# --- Helpers ---

func _set_phase(p: BattlePhase) -> void:
	_phase = p
	phase_changed.emit(p)


# M14a: returns the first active mon on the opposing side.
# In singles: identical to the old binary _get_opponent.
# In doubles: returns field slot 0 of the opposing side.
# Used for Destiny Bond fallback, singles AI targeting, and faint-replacement AI.
# Intimidate switch-in now uses _apply_switch_in_abilities (loops all live opponents).
func _get_first_opponent(mon: BattlePokemon) -> BattlePokemon:
	var idx: int = _combatants.find(mon)
	var side: int = idx / _active_per_side if idx >= 0 else 0
	return _combatants[(1 - side) * _active_per_side]


# Fire switch-in ability effects for new_mon against all live opposing combatants.
# Source: AbilityBattleEffects ABILITYEFFECT_ON_SWITCHIN (battle_util.c L3310–3323):
#   for i in 0..gBattlersCount: if IsBattlerAlly(battler,i) || !IsBattlerAlive(i): continue
#   SetStatChange(i, STAT_ATK, -1); then BattleScriptCall(BattleScript_IntimidateActivates).
# Loop shape: iterate ALL _combatants and filter by side — mirrors source loop exactly.
#   (Not "iterate only the opposing half") so the logic stays correct under layout changes.
# ability_triggered fires once per activation (one BattleScriptCall in source), not per target.
# Gen 8 Intimidate immunity (Inner Focus, Scrappy, Own Tempo, Oblivious, Guard Dog) is
#   intentionally omitted — none of those abilities exist in this codebase. Port when added.
#   See decisions.md [M14x Intimidate doubles + Gen 8 immunity].
func _apply_switch_in_abilities(new_mon: BattlePokemon, mon_side: int) -> void:
	var any_intimidated := false
	for j in range(_combatants.size()):
		if j / _active_per_side == mon_side:  # IsBattlerAlly: same side → skip
			continue
		var opp: BattlePokemon = _combatants[j]
		if opp.fainted or opp.current_hp == 0:  # !IsBattlerAlive: skip
			continue
		var actual: int = AbilityManager.try_switch_in(new_mon, opp)
		if actual != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_ATK, actual)
			any_intimidated = true
	if any_intimidated:
		ability_triggered.emit(new_mon, "intimidate")
	# M11: Drizzle / Drought — set field weather on switch-in.
	# Source: ABILITY_DRIZZLE / ABILITY_DROUGHT case in ABILITYEFFECT_ON_SWITCHIN
	#   calls TryChangeBattleWeather (battle_util.c L3213, L3242).
	var set_w: int = AbilityManager.get_switch_in_weather(new_mon)
	if set_w != WEATHER_NONE and try_set_weather(set_w, new_mon):
		weather_set.emit(new_mon, set_w)


# M14a: default target combatant index for a given attacker.
# Returns the first field slot of the opposing side (combatant index).
# Overridden by queue_move_targeted "target" field or AI decision.
func _default_target(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	return (1 - side) * _active_per_side


# Clear all volatile fields on a Pokémon (faint or switch-out, non-BP).
# Source: FaintClearSetData / SwitchInClearSetData (battle_main.c L3266, L3117)
func _clear_volatiles(mon: BattlePokemon) -> void:
	mon.confusion_turns = 0
	mon.flinched = false
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
	mon.focus_energy = false
	mon.minimized = false
	mon.defense_curled = false
	mon.rollout_turns = 0
	mon.rollout_base_power = 0


# M9: clear volatiles on switch-out (superset of _clear_volatiles: also resets
# stat stages and Counter/Mirror Coat per-turn trackers).
# Non-volatile status (burn/poison/paralysis/sleep/freeze) persists — SOURCE:
#   SwitchInClearSetData does NOT touch gBattleMons[battler].status1 (battle_main.c L3117-3264).
# Toxic counter persists — it is stored in STATUS1 bits 8-11 (STATUS1_TOXIC_COUNTER)
#   which SwitchInClearSetData does NOT clear. Gen 5+ behavior; confirmed no
#   B_TOXIC_COUNTER_RESET config flag in pokeemerald-expansion.
# Stat stages reset to 0 — SOURCE: SwitchInClearSetData L3124-3126 (except Baton Pass).
# protect_consecutive resets — the consecutive-use streak is per-battle-entry.
func _switch_out_clear(mon: BattlePokemon) -> void:
	_clear_volatiles(mon)
	for _si in range(mon.stat_stages.size()):
		mon.stat_stages[_si] = 0
	mon.last_physical_damage = 0
	mon.last_special_damage = 0
	mon.protect_consecutive = 0
	mon.last_move_used = null
	# M12: Choice lock clears on switch-out (not on faint — fainted mon has no future turns).
	# Source: SwitchInClearSetData (battle_main.c L3117) clears chosenMovePositions.
	mon.choice_locked_move = null


# M9: save Baton Pass passable state before switch-out clearing.
# Passable fields derived from VOLATILE_DEFINITIONS V_BATON_PASSABLE entries
# (include/constants/battle.h L209-319) and explicit copies in SwitchInClearSetData (L3146-3185).
# From our implemented fields:
#   stat_stages  — NOT cleared for Baton Pass (L3122 guard)
#   confusion_turns — V_BATON_PASSABLE (VOLATILE_CONFUSION, L210)
#   substitute_hp   — explicitly copied at L3185
func _baton_pass_save(mon: BattlePokemon) -> Dictionary:
	return {
		"stat_stages":     mon.stat_stages.duplicate(),
		"confusion_turns": mon.confusion_turns,
		"substitute_hp":   mon.substitute_hp,
	}


# M9: apply saved Baton Pass passables to the incoming Pokémon.
func _baton_pass_apply(mon: BattlePokemon, data: Dictionary) -> void:
	var src: Array = data["stat_stages"]
	for _si in range(src.size()):
		mon.stat_stages[_si] = src[_si]
	mon.confusion_turns = data["confusion_turns"]
	mon.substitute_hp   = data["substitute_hp"]


# M9/M14a: voluntary switch — switch-out cleanup, party update, switch-in ability.
# M14a: takes combatant_idx (0..N-1) instead of side, so doubles can switch
#   either field slot independently. side and field_slot are derived from combatant_idx.
func _do_voluntary_switch(combatant_idx: int, slot: int) -> void:
	var side: int = combatant_idx / _active_per_side
	var field_slot: int = combatant_idx % _active_per_side
	var old_mon: BattlePokemon = _combatants[combatant_idx]
	_switch_out_clear(old_mon)
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	pokemon_switched_out.emit(old_mon, side)
	pokemon_switched_in.emit(new_mon, side, slot)
	# Switch-in abilities fire for the incoming Pokémon.
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L2960)
	_apply_switch_in_abilities(new_mon, side)


# M9/M14b: forced switch-in for Roar/Whirlwind — forces out the combatant at
# the given field_slot of the specified side.
# M14b: field_slot parameter defaults to 0 (singles-compatible) but is now passed
# correctly from Roar execution using the actual targeted combatant's field slot.
# Source: Cmd_BS_JumpIfRoarFails (battle_script_commands.c L7426): applies forced
#   switch to gBattlerTarget — the specific targeted combatant, not always position 0.
func _do_forced_switch_in(side: int, slot: int, field_slot: int = 0) -> void:
	var combatant_idx: int = side * _active_per_side + field_slot
	_switch_out_clear(_combatants[combatant_idx])
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	# Switch-in abilities fire for the forced-in Pokémon.
	_apply_switch_in_abilities(new_mon, side)


# M9/M14a: switch-in after faint (no switch-out clear; old mon already cleared on faint).
# M14a: takes combatant_idx so doubles can replace either field slot independently.
func _do_switch_in(combatant_idx: int, slot: int) -> void:
	var side: int = combatant_idx / _active_per_side
	var field_slot: int = combatant_idx % _active_per_side
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	pokemon_switched_in.emit(new_mon, side, slot)
	_apply_switch_in_abilities(new_mon, side)


# M9/M10/M14a: determine replacement slot — priority: test queue, then AI, then auto-select.
# M14a: takes combatant_idx; side derived internally. _replacement_queues indexed by
#   combatant_idx so queue_replacement(side, slot) and queue_replacement_for(idx, slot)
#   both work correctly (in singles, side == combatant_idx).
func _get_replacement_slot(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	if not _replacement_queues[combatant_idx].is_empty():
		var slot: int = _replacement_queues[combatant_idx].pop_front()
		var party: BattleParty = _parties[side]
		if slot >= 0 and slot < party.members.size() and not party.members[slot].fainted:
			return slot
	# M10: AI chooses the best matchup replacement.
	# Source: Ai_InitPartyStruct + GetSwitchinCandidate SWITCHIN_CONSIDER_MOST_SUITABLE
	#   (battle_ai_switch.c L55+). AI has the opponent's data to make this choice.
	if _trainer_ais[side] != null:
		var opponent: BattlePokemon = _get_first_opponent(_combatants[combatant_idx])
		return _trainer_ais[side].choose_replacement(_parties[side], opponent)
	return _parties[side].get_first_non_fainted_not_active()


# M9/M14a: determine Baton Pass incoming slot from queue or auto-select first valid.
# M14a: takes combatant_idx; _baton_pass_queues indexed by combatant_idx.
#   In singles, combatant_idx == side so queue_baton_pass_target(side, slot) is compat.
func _get_baton_pass_slot(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	if not _baton_pass_queues[combatant_idx].is_empty():
		var slot: int = _baton_pass_queues[combatant_idx].pop_front()
		var party: BattleParty = _parties[side]
		if slot >= 0 and slot < party.members.size() \
				and not party.active_indices.has(slot) \
				and not party.members[slot].fainted:
			return slot
	return _parties[side].get_first_non_fainted_not_active()


# Gen 5+ protect success formula. First use: always succeeds.
# Subsequent consecutive uses: success chance = 1 / (3^n).
# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
#   sGen5ProtectFailChances = {1, 3, 9, 27}
func _roll_protect_success(consecutive: int) -> bool:
	const DENOMS: Array = [1, 3, 9, 27]
	var idx: int = clampi(consecutive, 0, DENOMS.size() - 1)
	var denom: int = DENOMS[idx]
	return denom == 1 or (randi() % denom == 0)


# Magnitude's weighted base-power roll.
# Source: battle_move_resolution.c :: CalculateMagnitudeDamage (L5196-5234):
#   magnitude = RandomUniform(0, 99); weighted bands →
#   [0,5)=10, [5,15)=30, [15,35)=50, [35,65)=70, [65,85)=90, [85,95)=110, [95,100)=150.
# _force_magnitude_power test seam: null = real RNG; else pin to the forced value.
func _roll_magnitude_power() -> int:
	if _force_magnitude_power != null:
		return int(_force_magnitude_power)
	var roll: int = randi() % 100
	if roll < 5:
		return 10
	elif roll < 15:
		return 30
	elif roll < 35:
		return 50
	elif roll < 65:
		return 70
	elif roll < 85:
		return 90
	elif roll < 95:
		return 110
	else:
		return 150


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


# M11: Check whether a Pokémon is immune to weather chip damage.
# Source: HandleEndTurnWeatherDamage (battle_end_turn.c L143–182).
# Sandstorm: immune if any type is Rock(6), Ground(5), or Steel(9), OR semi-invulnerable.
# Hail:      immune if any type is Ice(16), OR semi-invulnerable.
# Ability-based immunities (Sand Veil, Overcoat, Magic Guard, Ice Body, etc.) deferred to M12.
func _is_weather_damage_immune(mon: BattlePokemon, current_weather: int) -> bool:
	if mon.semi_invulnerable != MoveData.SEMI_INV_NONE:
		return true
	var types: Array = mon.species.types
	match current_weather:
		WEATHER_SANDSTORM:
			for t in types:
				if t == TypeChart.TYPE_ROCK or t == TypeChart.TYPE_GROUND or t == TypeChart.TYPE_STEEL:
					return true
		WEATHER_HAIL:
			for t in types:
				if t == TypeChart.TYPE_ICE:
					return true
	return false


# M15 Task 3: Returns true when all move slots have 0 PP (or the Pokémon has no moves).
# Source: battle_main.c L4727-4728 — noValidMoves check before move substitution.
func _is_forced_struggle(mon: BattlePokemon) -> bool:
	if mon.moves.is_empty():
		return true
	for _pi in range(mon.current_pp.size()):
		if mon.current_pp[_pi] > 0:
			return false
	return true


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


# M14b: Execute one damaging hit from attacker onto target.
# Handles DamageCalculator call, substitute routing, Counter tracking, Bide accumulation,
# target-thaw, recoil, drain, secondary effects, contact abilities, item triggers, and
# _last_attacker tracking (used by Destiny Bond killer lookup in _phase_faint_check).
# is_spread: pass true when this is a spread move with ≥2 live targets → 0.75× reduction.
# helping_hand: pass true when attacker's ally used Helping Hand → 1.5× base power.
# power_override: M16b — pass ≥0 to override move.power for this hit (Rollout scaling,
#   Magnitude's rolled power). -1 (default) = use move.power.
# Source: battle_script_commands.c :: MoveDamageDataHpUpdate + downstream effect handlers.
func _do_damaging_hit(attacker: BattlePokemon, target: BattlePokemon,
		move: MoveData, is_spread: bool = false, helping_hand: bool = false,
		power_override: int = -1) -> void:
	var target_idx: int = _combatants.find(target)
	var target_side: int = target_idx / _active_per_side
	var sc: Dictionary = _side_conditions[target_side]

	# M16c: Brick Break-style screen removal fires BEFORE this hit's own damage calc
	# (preAttackEffect=TRUE in source), so a screen this move itself breaks does NOT
	# reduce this hit's damage — `sc` is read fresh (already cleared) below.
	# Source: battle_script_commands.c :: MOVE_EFFECT_BREAK_SCREEN case (L3308-3336).
	if move.breaks_screens and (sc["reflect_turns"] > 0 or sc["light_screen_turns"] > 0
			or sc["aurora_veil_turns"] > 0):
		sc["reflect_turns"] = 0
		sc["light_screen_turns"] = 0
		sc["aurora_veil_turns"] = 0
		screens_broken.emit(target_side)

	# M16c: Reflect/Light Screen/Aurora Veil damage reduction. Resolved here (not inside
	# DamageCalculator, which is a stateless static utility with no access to side state)
	# and passed in as a pre-resolved bool + doubles flag.
	# Source: battle_util.c :: GetScreensModifier (L7347-7365): Aurora Veil applies
	#   regardless of category; Reflect only vs Physical, Light Screen only vs Special.
	#   The three do NOT stack multiplicatively — it's a plain OR, single ×0.5/×0.667 either way.
	var screen_active: bool = false
	if sc["aurora_veil_turns"] > 0:
		screen_active = true
	elif move.category == 0 and sc["reflect_turns"] > 0:
		screen_active = true
	elif move.category == 1 and sc["light_screen_turns"] > 0:
		screen_active = true

	var roll: int = _force_roll if _force_roll != null else -1
	var result: Dictionary = DamageCalculator.calculate(
			attacker, target, move, roll, _force_crit, weather, is_spread, helping_hand,
			power_override, screen_active, _active_per_side > 1)
	var damage: int = result["damage"]

	var went_to_sub: bool = (target.substitute_hp > 0 and not move.ignores_substitute)
	if went_to_sub:
		var sub_dmg: int = min(damage, target.substitute_hp)
		target.substitute_hp -= damage
		if target.substitute_hp <= 0:
			target.substitute_hp = 0
			substitute_broke.emit(target)
		move_executed.emit(attacker, target, move, sub_dmg)
		return

	target.current_hp = max(0, target.current_hp - damage)
	move_executed.emit(attacker, target, move, damage)

	if damage > 0:
		# M14b: track for Destiny Bond killer lookup.
		_last_attacker[target] = attacker
		if move.category == 0:
			target.last_physical_damage = damage
		else:
			target.last_special_damage = damage

	if target.bide_turns > 0 and damage > 0:
		target.bide_damage += damage

	if StatusManager.check_target_thaw(target, move, damage):
		pokemon_thawed.emit(target)

	if move.recoil_percent > 0 and damage > 0:
		var recoil: int = damage * move.recoil_percent / 100
		if recoil > 0:
			attacker.current_hp = max(0, attacker.current_hp - recoil)
			recoil_damage.emit(attacker, recoil)

	if move.drain_percent > 0 and damage > 0:
		var heal: int = damage * move.drain_percent / 100
		if heal > 0:
			attacker.current_hp = min(attacker.max_hp, attacker.current_hp + heal)
			drain_heal.emit(attacker, heal)

	if damage > 0 and move.secondary_effect != MoveData.SE_NONE:
		var effect_hit: bool = StatusManager.try_secondary_effect(attacker, target, move)
		if effect_hit:
			if move.secondary_effect == MoveData.SE_FLINCH:
				var target_turn_pos: int = _turn_order.find(target)
				if target_turn_pos > _current_actor_index:
					target.flinched = true
					secondary_applied.emit(target, MoveData.SE_FLINCH)
			else:
				secondary_applied.emit(target, move.secondary_effect)
				_try_synchronize(target, attacker, _se_to_status(move.secondary_effect))
				if ItemManager.lum_berry_cures(target):
					target.status = BattlePokemon.STATUS_NONE
					_consume_item(target)

	var contact_result: Dictionary = AbilityManager.try_contact_effects(
			attacker, target, move, damage, _force_contact_roll)
	if contact_result["rough_skin_damage"] > 0:
		var rs_dmg: int = contact_result["rough_skin_damage"]
		attacker.current_hp = max(0, attacker.current_hp - rs_dmg)
		recoil_damage.emit(attacker, rs_dmg)
		ability_triggered.emit(target, contact_result["ability_name"])
	if contact_result["status_applied"] != 0:
		var contact_status: int = contact_result["status_applied"]
		secondary_applied.emit(attacker, _status_to_se(contact_status))
		ability_triggered.emit(target, contact_result["ability_name"])
		_try_synchronize(attacker, target, contact_status)
		if ItemManager.lum_berry_cures(attacker):
			attacker.status = BattlePokemon.STATUS_NONE
			_consume_item(attacker)

	if result.get("defender_item_consumed", false):
		_consume_item(target)

	if damage > 0 and not attacker.fainted:
		var lo_recoil: int = ItemManager.life_orb_recoil(attacker)
		if lo_recoil > 0:
			attacker.current_hp = max(0, attacker.current_hp - lo_recoil)
			item_damage.emit(attacker, lo_recoil)

	if not target.fainted:
		var sitrus_heal: int = ItemManager.sitrus_berry_heal(target)
		if sitrus_heal > 0:
			target.current_hp = min(target.max_hp, target.current_hp + sitrus_heal)
			item_healed.emit(target, sitrus_heal)
			_consume_item(target)


# M12: Consume a held item (berries, Life Orb consumed indirectly by PP drain in source,
# but for our engine all one-use items use this path). Emits item_consumed signal.
# Source: ConsumeItem / RemoveBattlerItem (battle_util.c) called by TryCureAnyStatus etc.
func _consume_item(mon: BattlePokemon) -> void:
	var item: ItemData = mon.held_item
	mon.held_item = null
	item_consumed.emit(mon, item)
