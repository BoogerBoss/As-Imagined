extends Node

# [M25a] Regression suite for a real playthrough bug: "No Struggle move
# fires when a Pokémon is out of usable PP."
#
# Step 0 found Struggle itself was ALREADY fully implemented at the
# BattleManager engine level (_struggle_move/_is_forced_struggle, wired
# into the AI-controlled and default-fallback branches of
# _phase_move_selection since an earlier milestone) -- not genuinely
# unbuilt, as the bug report's own phrasing might suggest. The real,
# confirmed gap was narrower: the HUMAN-CONTROLLED branch's own
# `elif _human_controlled[side]: continue` fired unconditionally,
# regardless of PP state, permanently stalling MOVE_SELECTION for a human
# player with no PP left anywhere -- and even if it hadn't stalled, the
# real UI's move-selection menu (_build_main_menu) has no path to submit
# a "Struggle" action at all (Struggle isn't a member of mon.moves, so
# queue_move_targeted()'s own mon.moves[idx] lookup can never resolve it).
#
# Fix: the human-controlled branch's own condition now excludes the
# forced-Struggle case; a NEW branch immediately after it auto-assigns
# _struggle_move directly, matching how AI/default-fallback combatants
# already worked -- the real games don't even show a Fight menu when
# Struggle is forced. A second part of the fix: battle_screen.gd's own
# _current_action_field_slot() (which decides which field slot's menu to
# render) now recognizes a forced-Struggle slot as already resolved
# (mirroring its existing `.fainted` check) via a new public
# BattleManager.is_forced_struggle() wrapper, so the UI doesn't render a
# stale, all-disabled-buttons Fight menu for a slot the engine already
# auto-resolved.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_human_side_auto_struggles_when_out_of_pp()
	_test_human_side_with_pp_left_still_waits_normally()
	_test_current_action_field_slot_skips_forced_struggle()
	_test_is_forced_struggle_public_wrapper_matches_real_states()

	var total := _pass + _fail
	print("m25a_struggle_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── 1. A human-controlled side with 0 PP on every move auto-Struggles
# instead of stalling MOVE_SELECTION forever. ──────────────────────────────

func _test_human_side_auto_struggles_when_out_of_pp() -> void:
	var out_of_pp := _make_mon("OutOfPP", 200)
	out_of_pp.add_move(_load_move(33))  # Tackle
	out_of_pp.current_pp[0] = 0

	var opp := _make_mon("Target", 200)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(BattleParty.single(out_of_pp), BattleParty.single(opp))

	# start_battle_with_parties() already calls advance() once internally --
	# if the fix works, the human side's own forced-Struggle resolves
	# within that same call (no external queue_move_targeted() needed),
	# and the opponent (AI-less, default-fallback) also auto-resolves, so
	# the turn should have already fully executed.
	_chk("battle did not stall at MOVE_SELECTION waiting for impossible human input",
			bm.get_phase() != BattleManager.BattlePhase.MOVE_SELECTION or opp.current_hp < opp.max_hp)
	_chk("Struggle actually connected and dealt real damage",
			opp.current_hp < opp.max_hp)
	_chk("Struggle's own recoil hurt the user (a real, distinguishing Struggle mechanic)",
			out_of_pp.current_hp < out_of_pp.max_hp)

	bm.queue_free()


# ── 2. A human-controlled side that still HAS usable PP is completely
# unaffected -- still correctly waits for real external input. ─────────────

func _test_human_side_with_pp_left_still_waits_normally() -> void:
	var healthy := _make_mon("HasPP", 200)
	healthy.add_move(_load_move(33))
	# PP intentionally left at its real default (nonzero).

	var opp := _make_mon("Target2", 200)
	opp.add_move(_load_move(33))

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(BattleParty.single(healthy), BattleParty.single(opp))

	_chk("a human side with real PP left still stalls at MOVE_SELECTION (no regression)",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)
	_chk("nothing was auto-resolved -- opponent untouched",
			opp.current_hp == opp.max_hp)

	bm.queue_free()


# ── 3. battle_screen.gd's own _current_action_field_slot() correctly
# skips a forced-Struggle slot instead of trying to render its menu. ───────

func _test_current_action_field_slot_skips_forced_struggle() -> void:
	var out_of_pp := _make_mon("Slotted", 100)
	out_of_pp.add_move(_load_move(33))
	out_of_pp.current_pp[0] = 0

	var party := BattleParty.single(out_of_pp)
	var bm := BattleManager.new()
	add_child(bm)

	var bs := BattleScreen.new()
	bs._player_party = party
	bs._bm = bm
	bs._slot_acted = [false]

	var slot: int = bs._current_action_field_slot()
	_chk("a forced-Struggle slot is treated as already resolved, not shown a menu",
			slot == -1)
	_chk("_slot_acted was updated so a later real-PP slot in doubles wouldn't be skipped too",
			bs._slot_acted[0] == true)

	bs.queue_free()
	bm.queue_free()


# ── 4. The public wrapper matches every real forced/not-forced state. ──────

func _test_is_forced_struggle_public_wrapper_matches_real_states() -> void:
	var bm := BattleManager.new()
	add_child(bm)

	var no_moves := _make_mon("NoMoves", 100)
	_chk("a moveless mon is forced-Struggle", bm.is_forced_struggle(no_moves))

	var zero_pp := _make_mon("ZeroPP", 100)
	zero_pp.add_move(_load_move(33))
	zero_pp.add_move(_load_move(52))
	zero_pp.current_pp[0] = 0
	zero_pp.current_pp[1] = 0
	_chk("a mon with every move at 0 PP is forced-Struggle", bm.is_forced_struggle(zero_pp))

	var some_pp := _make_mon("SomePP", 100)
	some_pp.add_move(_load_move(33))
	some_pp.add_move(_load_move(52))
	some_pp.current_pp[0] = 0
	# current_pp[1] left at its real nonzero default.
	_chk("a mon with at least one usable move is NOT forced-Struggle",
			not bm.is_forced_struggle(some_pp))

	bm.queue_free()
