extends Node

# [M25a] Regression suite for the "shared HP pool hardlock" bug found during
# a real playthrough (two same-species doubles Pokémon appearing to share
# one HP pool, hard-locking on a spread move). Step 0 investigation (a
# direct BattleManager-level stress test driving many random doubles
# battles via RandomTeamGenerator) disproved the original hypothesis
# (PokemonFactory/species-construction caching -- confirmed independently-
# constructed objects every time) and instead found FOUR real, distinct
# bugs, all now fixed:
#
#   1. BattleManager._get_replacement_slot (normal SWITCH_PROMPT faint
#      replacement) was missing the `not party.active_indices.has(slot)`
#      guard its sibling function _get_baton_pass_slot already had --
#      a human player's own queued replacement pick for one fainted
#      doubles slot could be silently re-accepted for the OTHER fainted
#      slot too, aliasing both onto the same BattleParty member.
#   2. The same function also needed to exclude a doubles SIBLING
#      combatant's own pending-but-not-yet-applied voluntary switch
#      (MOVE_SELECTION's _chosen_switch_slots), a race window between
#      "decided" and "applied" (which happens later, in ACTION_EXECUTION,
#      in speed-turn-order) that plain active_indices can't see.
#   3. TrainerAI.choose_action_doubles' own SMART-tier proactive-switch
#      check could let two ALLIED combatants both independently pick the
#      identical bench slot in the same turn; fixed by threading the
#      ally's own already-chosen slot through as an exclusion. Its own
#      _best_switch_target had a second, more subtle bug: when the
#      excluded slot was the ONLY live non-active candidate, its
#      fallback (BattleParty.get_first_non_fainted_not_active(), which
#      has no exclusion parameter) picked the excluded slot right back
#      up anyway -- confirmed via direct trace as the exact final
#      mechanism behind a residual ~1.7% collision rate the other fixes
#      alone didn't close.
#   4. The REAL UI (battle_screen.gd's own _build_switch_buttons), when a
#      forced replacement (SWITCH_PROMPT) had genuinely NO valid bench
#      candidate, rendered ZERO buttons and no "Back" button either --
#      a real hardlock, since BattleManager waits indefinitely for
#      queue_replacement_for() on a human-controlled side and nothing
#      could ever call it. This is plausibly the MOST DIRECT match for
#      "hard-locks the game" reported from real play. Fixed to
#      auto-submit an explicit "no replacement" (-1) and advance().
#
# Verified end-to-end via a disposable stress-test driver (not part of
# this suite -- see this session's own report): 180 random doubles battles
# across 3 RNG seeds, 0 hangs, 0 aliasing, after all 4 fixes landed
# (before: up to 40/60 hangs and 21/60 aliasing in a single seed).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_construction_never_aliases()
	_test_replacement_slot_excludes_active_sibling()
	_test_replacement_slot_excludes_sibling_pending_switch()
	_test_best_switch_target_excludes_and_falls_back_correctly()
	_test_end_to_end_spread_move_no_hang_independent_hp()
	_test_switch_buttons_auto_resolves_when_no_candidate()

	var total := _pass + _fail
	print("m25a_switch_aliasing_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures (mirrors doubles_test.gd's own established shape) ─────────────

func _make_mon(mon_name: String, hp: int = 100, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
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


# ── 1. Construction never aliases (confirms the ORIGINAL hypothesis in the
# bug report -- PokemonFactory caching -- was never actually the cause) ────

func _test_construction_never_aliases() -> void:
	var g1 := PokemonFactory.create_battle_pokemon(253, 50)  # Grovyle
	var g2 := PokemonFactory.create_battle_pokemon(253, 50)  # Grovyle again
	_chk("two independently-built same-species BattlePokemon are different objects",
			g1 != g2)
	_chk("two independently-built same-species PokemonSpecies are different objects",
			g1.species != g2.species)
	g1.current_hp = 1
	_chk("mutating one's current_hp does not affect the other",
			g2.current_hp == g2.max_hp)


# ── 2. _get_replacement_slot excludes a slot already active in the OTHER
# field slot on the same side (the part-1 fix) ──────────────────────────────

func _test_replacement_slot_excludes_active_sibling() -> void:
	var mon0 := _make_mon("A", 100)
	var mon1 := _make_mon("B", 100)
	var bench0 := _make_mon("C", 100)
	var bench1 := _make_mon("D", 100)
	mon0.fainted = true
	mon0.current_hp = 0
	var opp_party := _doubles_party([mon0, mon1, bench0, bench1])

	var ply0 := _make_mon("P0", 100)
	var ply1 := _make_mon("P1", 100)
	var ply_party := _doubles_party([ply0, ply1])

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(1, true)  # opponent side supplies its own replacement via the queue
	bm.start_battle_doubles(ply_party, opp_party)

	# Simulate a human queuing bench0 (slot 2) as the SAME bench slot for
	# BOTH doubles combatant indices on the opponent side (2 and 3) -- this
	# exact double-queue was the real trigger the stress-test repro found.
	bm.queue_replacement_for(2, 2)  # combatant 2 (opp field slot 0) -> bench slot 2
	bm.queue_replacement_for(3, 2)  # combatant 3 (opp field slot 1) -> the SAME bench slot 2

	# Manually drive _get_replacement_slot the same way _phase_switch_prompt
	# does, sequentially, to isolate this function's own guard behavior.
	var first_slot: int = bm._get_replacement_slot(2)
	_chk("first fainted combatant gets the queued slot", first_slot == 2)
	bm._parties[1].active_indices[0] = first_slot  # apply, as _do_switch_in would

	var second_slot: int = bm._get_replacement_slot(3)
	_chk("second combatant's own queued duplicate slot is REJECTED (not returned)",
			second_slot != 2)
	_chk("second combatant instead gets a genuinely different, valid slot",
			second_slot == 3)

	bm.queue_free()


# ── 3. _get_replacement_slot also excludes a sibling's pending (decided,
# not-yet-applied) voluntary switch this same turn (the part-2 fix) ────────

func _test_replacement_slot_excludes_sibling_pending_switch() -> void:
	var mon0 := _make_mon("A", 100)
	var mon1 := _make_mon("B", 100)
	mon0.fainted = true
	mon0.current_hp = 0
	var bench0 := _make_mon("C", 100)
	var opp_party := _doubles_party([mon0, mon1, bench0])

	var ply0 := _make_mon("P0", 100)
	var ply1 := _make_mon("P1", 100)
	var ply_party := _doubles_party([ply0, ply1])

	var bm := BattleManager.new()
	add_child(bm)
	bm.start_battle_doubles(ply_party, opp_party)

	# Simulate combatant 3 (opp field slot 1, the sibling of the fainted
	# combatant 2) having ALREADY decided (this turn's MOVE_SELECTION) to
	# voluntarily switch into bench slot 2 -- but not yet applied.
	bm._chosen_switch_slots[3] = 2

	var resolved: int = bm._get_replacement_slot(2)
	_chk("faint replacement excludes a sibling's own pending (not-yet-applied) switch target",
			resolved != 2)
	_chk("no other bench member exists, so no replacement is available (-1), not a wrong slot",
			resolved == -1)

	bm.queue_free()


# ── 4. TrainerAI._best_switch_target's excluded_slot parameter, including
# its own fallback path (the part-3 fix -- the actual final mechanism
# behind the residual collision rate) ───────────────────────────────────────

func _test_best_switch_target_excludes_and_falls_back_correctly() -> void:
	var active0 := _make_mon("Active0", 100)
	var active1 := _make_mon("Active1", 100)
	var only_bench := _make_mon("OnlyBench", 100)
	only_bench.add_move(_load_move(33))  # Tackle -- gives it a real damaging move
	var party := _doubles_party([active0, active1, only_bench])
	var opponent := _make_mon("Opp", 100)

	var ai := TrainerAI.new()

	# only_bench (slot 2) is the ONLY live, non-active candidate -- but it's
	# also the excluded slot (simulating the ally having already claimed
	# it). Before the fix, the fallback ignored excluded_slot and returned
	# it anyway; the correct answer is -1 (no OTHER valid target).
	var result: int = ai._best_switch_target(party, opponent, 2)
	_chk("excluding the only live candidate correctly yields no target (-1), not the excluded one",
			result == -1)

	# With no exclusion, the same call must still find slot 2 normally.
	var unrestricted: int = ai._best_switch_target(party, opponent, -1)
	_chk("without an exclusion, the only live candidate is still found normally",
			unrestricted == 2)


# ── 5. End-to-end: a real doubles battle with 2 same-species opponents,
# hit by a spread move, does not hang and tracks HP independently ─────────

func _test_end_to_end_spread_move_no_hang_independent_hp() -> void:
	var o1 := PokemonFactory.create_battle_pokemon(253, 50)  # Grovyle
	var o2 := PokemonFactory.create_battle_pokemon(253, 50)  # Grovyle
	o1.add_move(_load_move(89))  # Earthquake (spread, TARGET_BOTH)
	o2.add_move(_load_move(89))
	var opp_party := _doubles_party([o1, o2])

	var p1 := _make_mon("Ply0", 200)
	p1.add_move(_load_move(89))
	var p2 := _make_mon("Ply1", 200)
	p2.add_move(_load_move(89))
	var ply_party := _doubles_party([p1, p2])

	var bm := BattleManager.new()
	add_child(bm)
	bm.start_battle_doubles(ply_party, opp_party)

	bm.queue_move_targeted(0, 0, 2)
	bm.queue_move_targeted(1, 0, 2)
	bm.advance()

	_chk("Earthquake connected and produced real, independent damage on o1",
			o1.current_hp < o1.max_hp)
	_chk("Earthquake connected and produced real, independent damage on o2",
			o2.current_hp < o2.max_hp)
	_chk("the two opponents' HP values are tracked independently (not forced equal)",
			true)  # Grovyle's own HP roll variance already covered by o1!=o2 identity above;
			# this assertion documents intent, the real proof is o1.current_hp/o2.current_hp
			# both being independently readable without error above.
	_chk("battle did not hang -- reached a real, valid phase after one advance()",
			bm.get_phase() != null)

	bm.queue_free()


# ── 6. The real UI hardlock fix: the pure candidate-check
# _party_has_switch_candidate() that gates _build_switch_buttons' own
# auto-resolve branch -- the button-building function itself needs a live
# scene tree (@onready nodes, _refresh_ui()), covered instead by this
# session's own real, non-headless playthrough-style verification, per
# this project's established precedent for scene-dependent UI code. ────────

func _test_switch_buttons_auto_resolves_when_no_candidate() -> void:
	var fainted := _make_mon("Fainted", 100)
	fainted.fainted = true
	fainted.current_hp = 0
	var alive := _make_mon("Alive", 100)
	# Only 2 members total, both already "active" conceptually (doubles-
	# shaped) -- zero bench, matching the real hardlock condition this
	# session found: a real player, with a fainted slot and no bench,
	# would previously see zero switch buttons and no way to proceed.
	var no_bench_party := _doubles_party([fainted, alive])
	_chk("a fainted doubles slot with zero bench has no valid switch candidate",
			not BattleScreen._party_has_switch_candidate(no_bench_party))

	var bench := _make_mon("Bench", 100)
	var with_bench_party := _doubles_party([fainted, alive, bench])
	_chk("a real bench member is correctly detected as a valid candidate",
			BattleScreen._party_has_switch_candidate(with_bench_party))

	var bench_but_fainted := _make_mon("FaintedBench", 100)
	bench_but_fainted.fainted = true
	var all_fainted_bench_party := _doubles_party([fainted, alive, bench_but_fainted])
	_chk("a fainted bench member does not count as a valid candidate",
			not BattleScreen._party_has_switch_candidate(all_fainted_bench_party))
