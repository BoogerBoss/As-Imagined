extends Node

# [M23.0a] Async battle-loop mechanism — no-UI proof scene.
#
# Proves the pause/resume mechanism built in battle_manager.gd (see the
# `[M23.0a]`-tagged fields/comments there: `_human_controlled`,
# `_move_selection_active`/`_move_choice_resolved`,
# `_switch_prompt_active`/`_switch_prompt_resolved`, `set_human_controlled`)
# without building any real UI — this scene IS the "future UI click handler"
# stand-in, calling the exact same `queue_move_targeted`/`queue_switch_for`/
# `queue_replacement_for` + `advance()` methods a real UI would call.
#
# Confirmed design (full writeup in docs/m23_recon.md):
#  - `_human_controlled: Array[bool]` is per-SIDE, checked only once
#    `_trainer_ais[side] == null` and the test-queue is empty — the existing
#    "null == auto-select" meaning is completely undisturbed for any side that
#    never calls `set_human_controlled(side, true)`.
#  - `_phase_move_selection`/`_phase_switch_prompt` both gained a per-combatant
#    "resolved this pass" tracking array, guarding the top of their loops so a
#    resumed call never re-touches (or re-rolls) an already-resolved
#    combatant. Neither function calls `_set_phase` while anything remains
#    unresolved, so `advance()`'s PRE-EXISTING `phase == phase_before` stall
#    detection halts the whole battle loop with ZERO changes to `advance()`
#    itself.
#  - The external "supply the human's action" API is NOT a new method — it's
#    the exact same `queue_move`/`queue_move_targeted`/`queue_switch_for`/
#    `queue_item_for`/`queue_replacement_for` methods tests already use.
#  - Turn-order-splice primitives (Quash et al.) only ever run during
#    ACTION_EXECUTION, which by construction never starts until every
#    combatant's move-selection choice is fully resolved — confirmed via
#    Section C below that a human-paused slot's choice, once supplied,
#    participates in a splice exactly like any other action.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_a_multi_pause_singles()
	_test_b_faint_replacement_pause()
	_test_c_splice_interaction_doubles()
	_test_d_negative_control_no_human()

	var total := _pass + _fail
	print("m23_0a_proof_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spd: int = 60,
		mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_atk
	sp.base_sp_defense = base_def
	sp.base_speed = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# ── Section A: multi-turn singles battle, side 0 human-controlled ──────────
# Confirms advance() genuinely stalls (not silently auto-resolving) at
# MOVE_SELECTION, that supplying an action externally cleanly resumes it, and
# that this repeats across MULTIPLE pauses within the same battle (not just
# once).

func _test_a_multi_pause_singles() -> void:
	# Both mons bulky with a weak move, so the battle runs several turns —
	# enough to prove repeated pausing, not just a single first-turn pause.
	var player := _make_mon("A_Player", 200, 30, 60, 50)
	var opp := _make_mon("A_Opp", 200, 30, 60, 40)
	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	var executed_log: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	# Force the roll/crit so the number of turns to resolve — and therefore
	# the number of pauses this loop encounters — is fully deterministic
	# across reruns, not dependent on unforced damage-roll variance.
	bm._force_roll = 100
	bm._force_crit = false
	bm._force_hit = true
	bm.move_executed.connect(func(attacker, _defender, _move, _dmg): executed_log.append(attacker))
	bm.set_human_controlled(0, true)

	# start_battle() calls advance() internally — this is turn 1's own pause.
	bm.start_battle(player, opp)

	var pauses_confirmed := 0
	var turns_completed := 0
	var guard := 0
	while bm.get_phase() != BattleManager.BattlePhase.BATTLE_END and guard < 20:
		guard += 1
		_chk("A.%02d stalled at MOVE_SELECTION (turn %d), not silently past it" %
				[guard, turns_completed + 1],
				bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)
		_chk("A.%02d the human side (0) genuinely has no chosen move yet" % guard,
				bm._chosen_moves[0] == null)
		_chk(("A.%02d " % guard) + "the OTHER (auto-select) side already " +
				"resolved WITHIN the same stalled pass — proves partial-" +
				"resolution, not a total no-op",
				bm._chosen_moves[1] != null)
		if bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION:
			pauses_confirmed += 1
		var log_size_before: int = executed_log.size()
		bm.queue_move(0, 0)
		bm.advance()
		turns_completed += 1
		_chk(("A.%02d " % guard) + "resumption produced real forward " +
				"progress (a new move_executed event, or the battle ended)",
				executed_log.size() > log_size_before
				or bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)

	_chk("A.REQUIRED multiple separate pauses occurred in this one battle " +
			"(not just a single first-turn pause)", pauses_confirmed >= 2)
	_chk("A.REQUIRED the battle actually reached BATTLE_END (didn't just " +
			"stall forever)", bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)
	bm.queue_free()


# ── Section B: faint-replacement pause (SWITCH_PROMPT), side 0 human ───────

func _test_b_faint_replacement_pause() -> void:
	var active := _make_mon("B_Active", 10, 30, 30, 50)   # very frail
	var bench := _make_mon("B_Bench", 200, 60, 60, 50)
	var opp := _make_mon("B_Opp", 200, 200, 30, 200)      # overwhelming attacker
	var tackle := _load_move(33)
	active.add_move(tackle)
	bench.add_move(tackle)
	opp.add_move(tackle)

	var player_party := BattleParty.new()
	player_party.members = [active, bench]
	player_party.active_indices = [0]

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.set_human_controlled(0, true)

	# start_battle_with_parties() calls advance() internally — turn 1's
	# MOVE_SELECTION pause (side 0 human-controlled, nothing queued yet).
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))
	_chk("B.01 stalled at MOVE_SELECTION before any input is supplied",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)

	# Supply turn 1's move; the overwhelming opponent should KO `active`.
	bm.queue_move(0, 0)
	bm.advance()

	_chk("B.02 REQUIRED the active mon fainted and the phase stalled at " +
			"SWITCH_PROMPT — a genuinely distinct pause point from " +
			"MOVE_SELECTION", active.fainted
			and bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT)
	_chk("B.03 the bench mon has NOT been auto-switched in during the stall",
			bm._parties[0].active_indices[0] == 0)

	# Supply the human's chosen replacement (combatant idx 0, bench slot 1).
	bm.queue_replacement_for(0, 1)
	bm.advance()

	_chk("B.04 REQUIRED clean resumption: the bench mon is now active",
			bm._parties[0].active_indices[0] == 1)
	_chk("B.05 the battle continued past the pause (a further turn began, " +
			"i.e. SWITCH_PROMPT's own existing unconditional -> " +
			"BATTLE_END_CHECK -> MOVE_SELECTION transition still fires)",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION
			or bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)
	bm.queue_free()


# ── Section C: turn-order-splice interaction, doubles, side 0 human ────────
# One of side 0's human-paused slots is targeted by Quash (used by a side-1
# combatant whose action is already queued/locked-in BEFORE side 0 supplies
# its own input) — proves (a) side 1's pre-resolved actions are never
# re-rolled while side 0 is still paused (the doubles recompute-vs-lock-in
# question from Step 0), and (b) a splice primitive correctly reorders the
# human's own action once supplied, exactly as it would for any AI/auto
# action.

func _test_c_splice_interaction_doubles() -> void:
	var quash := _load_move(511)
	var tackle := _load_move(33)
	var scary_face := _load_move(184)  # -2 Speed, guaranteed, on the user's foe

	# Quash's real Gen8+ bubble only moves its target PAST battlers the
	# target is (at the moment the bubble runs) genuinely SLOWER than — a
	# cleanly speed-sorted _turn_order can never present that condition on
	# its own (whoever's already positioned right after a battler is, by
	# construction of the sort, never someone that battler is slower than).
	# The real, natural way this condition arises in an actual battle is
	# exactly what's set up here: b1 (fastest of all four) lowers a0's
	# Speed via Scary Face BEFORE b0 gets to use Quash on it — a0's INITIAL
	# _turn_order position was sorted using its ORIGINAL (undropped) Speed,
	# but the bubble's own comparison re-evaluates a0's speed FRESH at the
	# moment it runs, now reflecting the drop. Pre-drop sort (by original
	# Speed): b1(200), b0(150), a0(100), a1(55). Post-Scary-Face, a0's
	# effective Speed is 100 * 0.5 (a -2 stage multiplier) = 50, now BELOW
	# a1's untouched 55 — exactly the "genuinely slower than what's next"
	# condition the bubble needs to continue swapping a0 past a1.
	var a0 := _make_mon("C_A0", 100, 60, 60, 100)
	var a1 := _make_mon("C_A1", 100, 60, 60, 55)
	var b0 := _make_mon("C_B0", 100, 60, 60, 150)
	var b1 := _make_mon("C_B1", 100, 60, 60, 200)
	a0.add_move(tackle)
	a1.add_move(tackle)
	b0.add_move(quash)
	b1.add_move(scary_face)

	var executed_order: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_executed.connect(func(attacker, _defender, _move, _dmg): executed_order.append(attacker))
	bm.set_human_controlled(0, true)

	# Side 1 (b0, b1) is NOT human-controlled and NOT AI — pre-queue its
	# actions BEFORE the battle even starts, so at the moment side 0 (human)
	# is still paused, side 1's choices are already fully resolved within the
	# very same _phase_move_selection pass. b0 (Quash) and b1 (Scary Face)
	# both target a0 (combatant index 0) — the human-paused slot.
	bm.queue_move_targeted(2, 0, 0)  # b0 uses Quash on a0
	bm.queue_move_targeted(3, 0, 0)  # b1 uses Scary Face on a0

	bm.start_battle_doubles(
			_make_party_of_two(a0, a1), _make_party_of_two(b0, b1))

	_chk("C.01 stalled at MOVE_SELECTION with side 0 (human) unresolved",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION
			and bm._chosen_moves[0] == null and bm._chosen_moves[1] == null)
	_chk("C.02 REQUIRED side 1's pre-queued actions already resolved WITHIN " +
			"the same stalled pass — proves the doubles recompute-vs-lock-in " +
			"case: an already-decided side is never re-touched while the " +
			"other side is still paused",
			bm._chosen_moves[2] == quash and bm._chosen_moves[3] == scary_face)

	# Supply side 0's (human's) actions for both of its slots.
	bm.queue_move_targeted(0, 0, 2)
	bm.queue_move_targeted(1, 0, 2)
	bm.advance()

	# Final expected order: b1 (Scary Face, fastest, acts 1st), b0 (Quash,
	# acts 2nd), a1 (bubbled ahead of a0 once a0's dropped Speed makes it
	# genuinely slower), a0 (bubbled to last).
	_chk("C.REQUIRED Quash (used by b0, a side-1/queued action) correctly " +
			"pushed a0's (the human-paused slot's, once resumed) execution " +
			"to LAST — past a1, which a0 was originally faster than but " +
			"became genuinely slower than mid-turn once b1's Scary Face " +
			"(also side-1/queued) dropped its Speed — proving the human's " +
			"own chosen action, once supplied, participated correctly in " +
			"the splice exactly like any other queued action would, with " +
			"no special-casing needed for the pause mechanism",
			executed_order.size() == 4 and executed_order == [b1, b0, a1, a0])
	bm.queue_free()


func _make_party_of_two(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var party := BattleParty.new()
	party.members = [m0, m1]
	party.active_indices = [0, 1]
	return party


# ── Section D: negative control — no human_controlled anywhere ─────────────
# Confirms the mechanism is purely additive: a battle with every side left at
# its pre-M23.0a default (_human_controlled == [false, false], the same
# array literal every one of the 136 pre-existing tests already runs under
# without ever calling set_human_controlled) completes via a single
# start_battle() call with no stall at all, exactly as before this session.

func _test_d_negative_control_no_human() -> void:
	var player := _make_mon("D_Player", 100, 60, 60, 100)
	var opp := _make_mon("D_Opp", 100, 60, 60, 50)
	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	# Deliberately no set_human_controlled call at all.
	bm.start_battle(player, opp)

	_chk("D.REQUIRED negative control: with no side marked human-controlled, " +
			"the battle runs to completion in one start_battle() call with " +
			"no stall whatsoever, matching every pre-existing test's " +
			"behavior exactly", bm.get_phase() == BattleManager.BattlePhase.BATTLE_END)
	bm.queue_free()
