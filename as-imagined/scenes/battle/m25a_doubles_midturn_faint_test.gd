extends Node

# [M25a] Regression suite for a real playthrough bug: "in doubles, if the
# first Pokémon's attack KOs its target mid-turn, the second Pokémon
# doesn't act that turn."
#
# Root cause, confirmed via a direct BattleManager-level reproduction
# (not guessed from the symptom): _phase_faint_check routes ANY mid-turn
# faint straight to SWITCH_PROMPT (correct -- a replacement is needed).
# The bug was in _phase_switch_prompt's OWN ending: once every fainted
# slot was resolved, it UNCONDITIONALLY jumped to BATTLE_END_CHECK ->
# (battle not over) MOVE_SELECTION, starting a brand-new turn -- silently
# dropping every OTHER combatant's own already-queued action for the
# CURRENT turn that hadn't resolved yet. Invisible in singles (a faint
# there always coincides with the turn's own action queue already being
# exhausted), but a real, confirmed bug in doubles: a fast Pokémon KOing
# its target left every other still-alive, not-yet-acted combatant
# (including the ATTACKER's OWN teammate) skipped entirely for that turn.
#
# Fix: _phase_switch_prompt's ending now checks the exact same
# `_current_actor_index < _turn_order.size()` condition
# _phase_faint_check's own "no new faint" branch already uses -- if the
# current turn still has combatants pending AND neither side has been
# fully defeated, resume ACTION_EXECUTION instead of ending the turn
# early. A pure additive change: every case that isn't "mid-turn faint,
# turn_order not yet exhausted, battle still ongoing" falls through to
# the exact same BATTLE_END_CHECK path as before.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_second_combatant_still_acts_after_midturn_ko()
	_test_last_actor_faint_still_ends_turn_normally()
	_test_full_side_wipe_ends_battle_without_resuming_actions()

	var total := _pass + _fail
	print("m25a_doubles_midturn_faint_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, hp: int, atk: int, spd: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = 50
	sp.base_sp_attack = 50
	sp.base_sp_defense = 50
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _doubles_party(members: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed: Array[BattlePokemon] = []
	for m: BattlePokemon in members:
		typed.append(m)
	p.members = typed
	p.active_indices = [0, 1]
	return p


# Runs exactly one turn's worth of advance() calls (stops once a fresh
# MOVE_SELECTION or BATTLE_END is reached), auto-resolving any SWITCH_PROMPT
# with an explicit "no replacement" (both sides have no bench in these
# fixtures, matching the M25a UI-hardlock fix's own contract).
func _run_one_turn(bm: BattleManager) -> void:
	var left_move_selection := false
	for _step in range(20):
		if bm.get_phase() == BattleManager.BattlePhase.BATTLE_END:
			return
		if bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION and left_move_selection:
			return
		if bm.get_phase() != BattleManager.BattlePhase.MOVE_SELECTION:
			left_move_selection = true
		bm.advance()
		if bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT:
			for ci in range(bm._combatants.size()):
				bm.queue_replacement_for(ci, -1)


# ── 1. The exact reported bug: Fast KOs its target mid-turn; Slow (the
# SAME side's own second, still-alive Pokémon, later in turn order) must
# still act this same turn. ─────────────────────────────────────────────────

func _test_second_combatant_still_acts_after_midturn_ko() -> void:
	var fast := _make_mon("Fast", 100, 200, 200)
	fast.add_move(_load_move(33))  # Tackle
	var slow := _make_mon("Slow", 100, 80, 1)
	slow.add_move(_load_move(33))  # Tackle
	var ply_party := _doubles_party([fast, slow])

	var opp0 := _make_mon("Opp0", 1, 50, 50)   # dies in one hit from Fast
	opp0.add_move(_load_move(33))
	var opp1 := _make_mon("Opp1", 200, 50, 50)  # Slow's own target
	opp1.add_move(_load_move(33))
	var opp_party := _doubles_party([opp0, opp1])

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	bm.start_battle_doubles(ply_party, opp_party)

	bm.queue_move_targeted(0, 0, 2)  # Fast -> opp slot0 (KOs it)
	bm.queue_move_targeted(1, 0, 3)  # Slow -> opp slot1
	bm.queue_move_targeted(2, 0, 0)  # opp0 (will be skipped -- fainted before acting)
	bm.queue_move_targeted(3, 0, 0)  # opp1 -> Fast

	_run_one_turn(bm)

	_chk("Fast's attack connected and KO'd opp0", opp0.fainted and opp0.current_hp == 0)
	_chk("Slow (the second, still-alive Pokémon) still acted this turn -- opp1 took real damage",
			opp1.current_hp < opp1.max_hp)
	_chk("opp1 (still alive) also got to act -- Fast took real damage back",
			fast.current_hp < fast.max_hp)

	bm.queue_free()


# ── 2. A faint on the LAST actor's own move must still behave exactly as
# before (falls through to BATTLE_END_CHECK, no regression to that path). ──

func _test_last_actor_faint_still_ends_turn_normally() -> void:
	var slow_attacker := _make_mon("SlowAttacker", 100, 200, 1)
	slow_attacker.add_move(_load_move(33))
	var ally := _make_mon("Ally", 100, 10, 200)
	ally.add_move(_load_move(33))
	var ply_party := _doubles_party([ally, slow_attacker])

	var opp0 := _make_mon("Opp0", 1, 50, 50)
	opp0.add_move(_load_move(33))
	var opp1 := _make_mon("Opp1", 200, 5, 50)
	opp1.add_move(_load_move(33))
	var opp_party := _doubles_party([opp0, opp1])

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	bm.start_battle_doubles(ply_party, opp_party)

	# Ally (fast, weak) hits opp1 first for negligible damage; SlowAttacker
	# (slowest of all 4 -- acts LAST) delivers the KO on opp0.
	bm.queue_move_targeted(0, 0, 3)   # Ally -> opp1 (survives)
	bm.queue_move_targeted(1, 0, 2)   # SlowAttacker -> opp0 (KO, LAST in turn order)
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)

	_run_one_turn(bm)

	_chk("the last actor's own KO still resolves correctly", opp0.fainted)
	_chk("battle correctly reaches a stable phase afterward (no hang)",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION
			or bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)

	bm.queue_free()


# ── 3. A full-side wipe mid-turn ends the battle rather than resuming the
# winning side's remaining not-yet-acted combatants. ────────────────────────

func _test_full_side_wipe_ends_battle_without_resuming_actions() -> void:
	var fast := _make_mon("Fast2", 100, 200, 200)
	fast.add_move(_load_move(89))  # Earthquake (spread, TARGET_BOTH)
	var slow := _make_mon("Slow2", 100, 80, 1)
	slow.add_move(_load_move(33))
	var ply_party := _doubles_party([fast, slow])

	var opp0 := _make_mon("OppA", 1, 50, 50)
	opp0.add_move(_load_move(33))
	var opp1 := _make_mon("OppB", 1, 50, 50)
	opp1.add_move(_load_move(33))
	var opp_party := _doubles_party([opp0, opp1])

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	bm.start_battle_doubles(ply_party, opp_party)

	bm.queue_move_targeted(0, 0, 2)  # Fast's Earthquake -> hits BOTH opp0/opp1
	bm.queue_move_targeted(1, 0, 2)
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)

	_run_one_turn(bm)

	_chk("both opponents fainted (full side wipe)", opp0.fainted and opp1.fainted)
	_chk("battle correctly ended (winner declared), not stuck resuming actions",
			bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)

	bm.queue_free()
