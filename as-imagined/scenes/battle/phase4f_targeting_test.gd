extends Node

# [M23.11 Phase 4f] BattleManager-level test suite for the doubles
# menu/targeting layer's DATA-side plumbing — get_live_targets/
# get_combatant_index, and the multi-slot MOVE_SELECTION/SWITCH_PROMPT
# stall-and-resume sequencing battle_screen.gd's new UI drives via plain
# queue_*()/advance() calls.
#
# [Deliberately NOT tested here] Actually instantiating battle_screen.tscn
# — matching m23_6_battle_setup_test.gd's own established precedent (see
# that file's own doc comment): this project's sweep script appends
# --autoplay to every scene invocation unconditionally, and battle_screen
# .gd's own _ready() checks OS.get_cmdline_args() process-wide, so any
# scene that embedded battle_screen.tscn as a child during a sweep run
# would trigger _run_autoplay()'s get_tree().quit() and silently kill this
# entire test process before its own summary line ran. Every mechanism
# this suite exercises (get_live_targets, get_combatant_index, the
# MOVE_SELECTION/SWITCH_PROMPT stall) is plain BattleManager API — exactly
# what battle_screen.gd's own handlers call — so it's fully testable
# without the Control scene at all. The genuine end-to-end UI proof is the
# mandated real screenshot verification instead (see docs/m23_recon.md's
# Phase 4f entry).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_get_live_targets_ordinary_moves()
	_test_get_live_targets_ally_targeting_moves()
	_test_get_live_targets_acupressure()
	_test_get_combatant_index()
	_test_move_selection_multi_slot_stall()
	_test_switch_prompt_multi_slot_stall()
	_test_spread_move_hits_both_opponents()
	_test_target_ally_move_resolves_to_ally()
	_test_singles_regression_shape()
	_test_needs_target_select()

	var total := _pass + _fail
	print("phase4f_targeting_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────
# Same hand-built-fixture shape as every other suite in this project
# (PokemonSpecies.new() + manual base stats, BattlePokemon.from_species,
# real .tres moves) — no PokemonRegistry/converter involved.

static func _make_mon(mon_name: String, hp: int, atk: int, def_stat: int,
		spatk: int, spdef: int, spd: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


static func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


const TACKLE_ID := 33
const SURF_ID := 57
const HELPING_HAND_ID := 270
const ACUPRESSURE_ID := 367


# Builds a fresh 2-active-per-side doubles BattleManager: player party has 2
# active + 2 bench (for faint-replacement tests), opponent party has 2
# active + 0 bench (irrelevant to these tests). Neither side's TrainerAI is
# set unless the caller does so afterward — every combatant's action is
# driven directly via queue_move_targeted for full determinism.
func _make_doubles_battle(side1_human: bool = false) -> Dictionary:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true

	var p0 := _make_mon("P0", 200, 80, 80, 80, 80, 100)
	var p1 := _make_mon("P1", 200, 80, 80, 80, 80, 90)
	var bench_a := _make_mon("BenchA", 200, 80, 80, 80, 80, 50)
	var bench_b := _make_mon("BenchB", 200, 80, 80, 80, 80, 50)
	for m in [p0, p1, bench_a, bench_b]:
		m.add_move(_load_move(TACKLE_ID))
		m.add_move(_load_move(HELPING_HAND_ID))
		m.add_move(_load_move(ACUPRESSURE_ID))
		m.add_move(_load_move(SURF_ID))

	var o0 := _make_mon("O0", 200, 80, 80, 80, 80, 70)
	var o1 := _make_mon("O1", 200, 80, 80, 80, 80, 60)
	for m in [o0, o1]:
		m.add_move(_load_move(TACKLE_ID))

	var player_party := BattleParty.new()
	player_party.members = [p0, p1, bench_a, bench_b]
	player_party.active_indices = [0, 1]

	var opp_party := BattleParty.new()
	opp_party.members = [o0, o1]
	opp_party.active_indices = [0, 1]

	bm.set_human_controlled(0, true)
	# [Test-setup note] side1_human, when requested, must be set BEFORE
	# start_battle_doubles() below (which calls advance() internally) — a
	# combatant with neither a queued action, nor a TrainerAI, nor
	# human_controlled set auto-selects moves[0] and is marked resolved
	# immediately; setting human_controlled afterward is too late to stop
	# that (confirmed via a scratch diagnostic during this suite's own
	# authoring, not guessed).
	if side1_human:
		bm.set_human_controlled(1, true)
	bm.start_battle_doubles(player_party, opp_party)

	return {"bm": bm, "player_party": player_party, "opp_party": opp_party,
			"p0": p0, "p1": p1, "bench_a": bench_a, "bench_b": bench_b,
			"o0": o0, "o1": o1}


func _make_singles_battle() -> Dictionary:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true

	var p0 := _make_mon("SP0", 200, 80, 80, 80, 80, 100)
	var o0 := _make_mon("SO0", 200, 80, 80, 80, 80, 70)
	p0.add_move(_load_move(TACKLE_ID))
	p0.add_move(_load_move(HELPING_HAND_ID))
	p0.add_move(_load_move(ACUPRESSURE_ID))
	o0.add_move(_load_move(TACKLE_ID))

	var player_party := BattleParty.single(p0)
	var opp_party := BattleParty.single(o0)

	bm.set_human_controlled(0, true)
	bm.start_battle_with_parties(player_party, opp_party)

	return {"bm": bm, "player_party": player_party, "opp_party": opp_party, "p0": p0, "o0": o0}


# ── Section A: get_live_targets — ordinary foe-targeting moves ─────────────

func _test_get_live_targets_ordinary_moves() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var tackle: MoveData = d["p0"].moves[0]

	var candidates: Array[BattlePokemon] = bm.get_live_targets(d["p0"], tackle)
	_chk("doubles: ordinary move sees both live opponents", candidates.size() == 2)
	_chk("doubles: candidates are exactly [o0, o1]",
			candidates.has(d["o0"]) and candidates.has(d["o1"]))

	d["o1"].fainted = true
	d["o1"].current_hp = 0
	var candidates_one_fainted: Array[BattlePokemon] = bm.get_live_targets(d["p0"], tackle)
	_chk("doubles: a fainted opponent is excluded", candidates_one_fainted.size() == 1)
	_chk("doubles: the remaining candidate is the live opponent",
			candidates_one_fainted.has(d["o0"]) and not candidates_one_fainted.has(d["o1"]))

	bm.queue_free()

	var s := _make_singles_battle()
	var sbm: BattleManager = s["bm"]
	var s_tackle: MoveData = s["p0"].moves[0]
	var singles_candidates: Array[BattlePokemon] = sbm.get_live_targets(s["p0"], s_tackle)
	_chk("singles: ordinary move sees exactly the one opponent",
			singles_candidates.size() == 1 and singles_candidates[0] == s["o0"])

	# null move behaves identically to a plain foe-targeting move (matches
	# _get_live_opponents' own pre-existing shape, e.g. the trapping gate's
	# own call site).
	var null_move_candidates: Array[BattlePokemon] = sbm.get_live_targets(s["p0"])
	_chk("singles: move==null falls back to plain live-opponents shape",
			null_move_candidates.size() == 1 and null_move_candidates[0] == s["o0"])
	sbm.queue_free()


# ── Section A (cont.): get_live_targets — TARGET_ALLY-only moves ──────────

func _test_get_live_targets_ally_targeting_moves() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var helping_hand: MoveData = d["p0"].moves[1]

	var candidates: Array[BattlePokemon] = bm.get_live_targets(d["p0"], helping_hand)
	_chk("doubles: Helping Hand's only candidate is the live ally",
			candidates.size() == 1 and candidates[0] == d["p1"])

	d["p1"].fainted = true
	var fainted_ally_candidates: Array[BattlePokemon] = bm.get_live_targets(d["p0"], helping_hand)
	_chk("doubles: Helping Hand with a fainted ally has zero candidates",
			fainted_ally_candidates.is_empty())
	bm.queue_free()

	var s := _make_singles_battle()
	var sbm: BattleManager = s["bm"]
	var s_helping_hand: MoveData = s["p0"].moves[1]
	var singles_candidates: Array[BattlePokemon] = sbm.get_live_targets(s["p0"], s_helping_hand)
	_chk("singles: Helping Hand has zero candidates (no ally exists)",
			singles_candidates.is_empty())
	sbm.queue_free()


# ── Section A (cont.): get_live_targets — TARGET_USER_OR_ALLY (Acupressure) ─

func _test_get_live_targets_acupressure() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var acupressure: MoveData = d["p0"].moves[2]

	var candidates: Array[BattlePokemon] = bm.get_live_targets(d["p0"], acupressure)
	_chk("doubles: Acupressure offers exactly [self, ally]", candidates.size() == 2)
	_chk("doubles: Acupressure's candidates are [self, ally] in that order",
			candidates[0] == d["p0"] and candidates[1] == d["p1"])
	bm.queue_free()

	var s := _make_singles_battle()
	var sbm: BattleManager = s["bm"]
	var s_acupressure: MoveData = s["p0"].moves[2]
	var singles_candidates: Array[BattlePokemon] = sbm.get_live_targets(s["p0"], s_acupressure)
	_chk("singles: Acupressure's only candidate is self (no ally to choose)",
			singles_candidates.size() == 1 and singles_candidates[0] == s["p0"])
	sbm.queue_free()


# ── Section B: get_combatant_index ─────────────────────────────────────────

func _test_get_combatant_index() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	_chk("get_combatant_index(p0) == 0", bm.get_combatant_index(d["p0"]) == 0)
	_chk("get_combatant_index(p1) == 1", bm.get_combatant_index(d["p1"]) == 1)
	_chk("get_combatant_index(o0) == 2", bm.get_combatant_index(d["o0"]) == 2)
	_chk("get_combatant_index(o1) == 3", bm.get_combatant_index(d["o1"]) == 3)

	var bystander := _make_mon("Bystander", 100, 50, 50, 50, 50, 50)
	_chk("get_combatant_index of a mon not in this battle returns -1",
			bm.get_combatant_index(bystander) == -1)
	bm.queue_free()


# ── Section C: multi-slot MOVE_SELECTION stall/resume (doubles) ───────────
# Verifies (rather than trusts) the scoping report's own finding: this
# phase already stalls independently per human-controlled combatant, with
# zero BattleManager changes needed — the UI's whole job is just to
# sequence the calls below.

func _test_move_selection_multi_slot_stall() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var opp_ai := TrainerAI.new()
	opp_ai.tier = TrainerAI.Tier.BASIC
	bm.set_trainer_ai(1, opp_ai)

	var executed_count := [0]
	bm.move_executed.connect(func(_a, _b, _c, _d2): executed_count[0] += 1)

	_chk("fresh doubles battle stalls at MOVE_SELECTION (both player slots unresolved)",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)

	# Only combatant 0 (p0) submits an action -- combatant 1 (p1) still
	# hasn't, so the phase must NOT advance yet.
	bm.queue_move_targeted(0, 0, bm.get_combatant_index(d["o0"]))
	bm.advance()
	_chk("MOVE_SELECTION still stalled after only slot 0 acts",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)
	_chk("no move has executed yet (turn hasn't resolved)", executed_count[0] == 0)

	# Now combatant 1 (p1) submits too -- every human-controlled slot is
	# resolved, so the whole turn (both player moves + both AI moves) should
	# run to completion within this single advance() call.
	bm.queue_move_targeted(1, 0, bm.get_combatant_index(d["o1"]))
	bm.advance()
	_chk("the turn actually resolved once both slots submitted an action (4 moves executed)",
			executed_count[0] == 4)
	_chk("phase moved past MOVE_SELECTION's turn-1 stall (back at MOVE_SELECTION for turn 2, not stuck)",
			bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION)
	bm.queue_free()


# ── Section D: multi-slot SWITCH_PROMPT stall/resume (doubles) ────────────
# A simultaneous double-faint (a single spread hit KOing both player slots
# at once, the only way this engine's per-action-immediate-faint-check
# architecture produces a genuine SIMULTANEOUS double-faint rather than
# interrupting the turn after the first one) — verifies the forced-
# replacement flow stalls and resumes per-combatant exactly like
# MOVE_SELECTION does, with the same "just sequence the queue_*() calls"
# UI contract.

func _test_switch_prompt_multi_slot_stall() -> void:
	# side1_human=true: this test needs deterministic control over BOTH
	# sides' targeting (o0's Surf must land on both player slots at once),
	# so side 1 is also marked human_controlled — see
	# _make_doubles_battle's own doc comment for why this must happen
	# before start_battle_doubles(), not after. Every real caller of this
	# contract (i.e. battle_screen.gd) only ever drives side 0; this is
	# purely a test-determinism artifact.
	var d := _make_doubles_battle(true)
	var bm: BattleManager = d["bm"]

	# Low HP so a single hit is guaranteed lethal (force_hit=true already
	# set in _make_doubles_battle; no crit/roll forcing needed since any
	# nonzero damage KOs a 1-HP mon).
	d["p0"].current_hp = 1
	d["p1"].current_hp = 1
	d["o0"].add_move(_load_move(SURF_ID))  # index 1 on o0 (after Tackle)

	var replacements_needed := [0]
	bm.replacement_needed.connect(func(_s): replacements_needed[0] += 1)

	# o0's single spread hit (Surf) KOs BOTH player slots in the SAME
	# action, the only way to get a genuine simultaneous double-faint here
	# — o1's own queued action never actually executes this turn (the
	# faint interrupts the turn immediately after o0 acts), so its target
	# is irrelevant.
	bm.queue_move_targeted(0, 0, bm.get_combatant_index(d["o0"]))
	bm.queue_move_targeted(1, 0, bm.get_combatant_index(d["o1"]))
	bm.queue_move_targeted(2, 1, bm.get_combatant_index(d["p0"]))
	bm.queue_move_targeted(3, 0, bm.get_combatant_index(d["p0"]))
	bm.advance()

	_chk("both player slots fainted simultaneously, battle stalls at SWITCH_PROMPT",
			bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT)
	_chk("both player slots faint (bench available, so no auto-skip)",
			d["p0"].fainted and d["p1"].fainted)

	# Only combatant 0's replacement is supplied -- combatant 1 still needs
	# one, so the phase must still be SWITCH_PROMPT.
	bm.queue_replacement_for(0, 2)  # bench_a into slot 0
	bm.advance()
	_chk("SWITCH_PROMPT still stalled after only slot 0's replacement is supplied",
			bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT)
	_chk("slot 0 was actually replaced", d["player_party"].get_active_at(0) == d["bench_a"])
	_chk("slot 1 is still the original fainted mon (not yet replaced)",
			d["player_party"].get_active_at(1) == d["p1"])

	bm.queue_replacement_for(1, 3)  # bench_b into slot 1
	bm.advance()
	_chk("slot 1 was replaced once its own reply was supplied",
			d["player_party"].get_active_at(1) == d["bench_b"])
	_chk("phase moved on past SWITCH_PROMPT once both slots were resolved",
			bm.get_phase() != BattleManager.BattlePhase.SWITCH_PROMPT)
	_chk("replacement_needed fired once per fainted slot (2 total)",
			replacements_needed[0] == 2)
	bm.queue_free()


# ── Section E: spread moves never need (or are affected by) a target choice ─
# Confirms empirically -- not just re-asserted from the scoping report --
# that a spread move dispatches to every qualifying opponent regardless of
# the target index the UI's "skip picker" path resolves to.

func _test_spread_move_hits_both_opponents() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var opp_ai := TrainerAI.new()
	opp_ai.tier = TrainerAI.Tier.BASIC
	bm.set_trainer_ai(1, opp_ai)

	var hit_targets: Array[BattlePokemon] = []
	bm.move_executed.connect(func(_atk, defender, _move, _dmg): hit_targets.append(defender))

	var surf: MoveData = d["p0"].moves[3]
	_chk("fixture sanity: Surf is flagged is_spread", surf.is_spread)

	# Matches battle_screen.gd's own _on_move_pressed fallback exactly: a
	# spread move never shows a picker, so the UI always passes the first
	# live opponent's combatant index (here: get_combatant_index(o0)) --
	# confirm the actual dispatch still hits BOTH opponents regardless.
	bm.queue_move_targeted(0, 3, bm.get_combatant_index(d["o0"]))
	bm.queue_move_targeted(1, 0, bm.get_combatant_index(d["o1"]))  # p1: plain Tackle, unrelated
	bm.advance()

	_chk("Surf (is_spread) hit BOTH opponents despite one shared target index",
			hit_targets.has(d["o0"]) and hit_targets.has(d["o1"]))
	bm.queue_free()


# ── Section F: TARGET_ALLY move resolves correctly via the picker's own
# auto-resolve path (get_live_targets -> get_combatant_index -> dispatch) ──

func _test_target_ally_move_resolves_to_ally() -> void:
	var d := _make_doubles_battle()
	var bm: BattleManager = d["bm"]
	var opp_ai := TrainerAI.new()
	opp_ai.tier = TrainerAI.Tier.BASIC
	bm.set_trainer_ai(1, opp_ai)

	var helping_hand: MoveData = d["p0"].moves[1]
	var candidates: Array[BattlePokemon] = bm.get_live_targets(d["p0"], helping_hand)
	var target_idx: int = bm.get_combatant_index(candidates[0])
	_chk("auto-resolved Helping Hand target is the ally's own combatant index",
			target_idx == bm.get_combatant_index(d["p1"]))

	var boosted := [false]
	bm.helping_hand_used.connect(func(_user, ally): boosted[0] = (ally == d["p1"]))

	bm.queue_move_targeted(0, 1, target_idx)  # p0 uses Helping Hand on p1
	bm.queue_move_targeted(1, 0, bm.get_combatant_index(d["o0"]))  # p1: plain Tackle
	bm.advance()

	_chk("Helping Hand, dispatched via the picker's own auto-resolve path, boosted the ally",
			boosted[0])
	bm.queue_free()


# ── Section G: singles regression guard ────────────────────────────────────
# Confirms the exact pre-4f dispatch shape (combatant_idx=0, target_idx=1)
# still falls out of the new get_live_targets/get_combatant_index-driven
# path with zero behavior change, end to end through a real battle turn.

func _test_singles_regression_shape() -> void:
	var s := _make_singles_battle()
	var sbm: BattleManager = s["bm"]

	var tackle: MoveData = s["p0"].moves[0]
	var candidates: Array[BattlePokemon] = sbm.get_live_targets(s["p0"], tackle)
	_chk("singles: exactly one candidate", candidates.size() == 1)
	var target_idx: int = sbm.get_combatant_index(candidates[0])
	_chk("singles: resolved target index is 1 (the pre-4f hardcoded default)",
			target_idx == 1)

	var executed := [false]
	sbm.move_executed.connect(func(_a, _b, _c, _d): executed[0] = true)
	sbm.queue_move_targeted(0, 0, target_idx)
	sbm.advance()
	_chk("singles: the move dispatched and executed exactly as before 4f",
			executed[0])
	sbm.queue_free()


# ── Section H: BattleScreen._needs_target_select (pure, no scene needed) ───

func _test_needs_target_select() -> void:
	var tackle: MoveData = _load_move(TACKLE_ID)
	var surf: MoveData = _load_move(SURF_ID)
	var helping_hand: MoveData = _load_move(HELPING_HAND_ID)
	var acupressure: MoveData = _load_move(ACUPRESSURE_ID)

	_chk("ordinary move, singles (1 candidate): no picker",
			not BattleScreen._needs_target_select(tackle, 1))
	_chk("ordinary move, doubles (2 candidates): picker needed",
			BattleScreen._needs_target_select(tackle, 2))
	_chk("ordinary move, 0 candidates: no picker (defensive)",
			not BattleScreen._needs_target_select(tackle, 0))
	_chk("spread move, 2 candidates: never a picker",
			not BattleScreen._needs_target_select(surf, 2))
	_chk("TARGET_ALLY move, 1 candidate (auto-resolve): no picker",
			not BattleScreen._needs_target_select(helping_hand, 1))
	_chk("TARGET_ALLY move, 0 candidates (no ally): no picker",
			not BattleScreen._needs_target_select(helping_hand, 0))
	_chk("TARGET_USER_OR_ALLY move, 2 candidates (self+ally): picker needed",
			BattleScreen._needs_target_select(acupressure, 2))
	_chk("TARGET_USER_OR_ALLY move, 1 candidate (self only): no picker",
			not BattleScreen._needs_target_select(acupressure, 1))
