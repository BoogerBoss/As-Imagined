extends Node

# [Turn-order-splice trio] Items 5, 8, 11, 12, 13 — Step 0 + implementation.
#
# Closes the full turn-order-splice family deferred since M21's own
# bundle-safe session. See docs/decisions.md's `[Turn-order-splice trio]`
# entry for the full Step 0 citations; summarized here per section.
#
# ── Item 8 (Trick Room x Pursuit doubles) — the one genuine BUG, not an
# unbuilt feature. Root cause: `_phase_priority_resolution`'s single
# `_turn_order.sort_custom` call site embedded Pursuit's interception as a
# pairwise comparator override (`if b_switch and not a_switch and
# _pursuit_targets_switcher(ia, ib): return true`), which is only valid for
# the SPECIFIC pair being compared — with a 3rd/4th battler present it
# produces a genuine, confirmed CYCLE (A0 < B0 < A1 < A0 in a same-side
# speed-tie scenario), undefined behavior for Godot's `Array.sort_custom`
# (no transitivity guarantee). Re-verified this session: this is the ONLY
# `sort_custom` call site in the whole codebase (grepped fresh), so no other
# tie-break site shares this risk. The apparent "non-determinism across
# reruns" isn't Godot's sort itself being randomized — `tiebreak[mon] =
# randi()` differs every turn, and different random tiebreak values resolve
# the undefined cyclic comparator differently each run; the sort algorithm
# itself is deterministic given fixed inputs, but the comparator's own
# inputs (the random tiebreak) aren't fixed run to run.
#
# Fix: Pursuit's interception was removed from the comparator entirely
# (which is now a clean, transitive total order — switch-tier > priority >
# quick/slow > speed > tiebreak) and reimplemented as a separate, explicit
# POST-SORT splice pass (`_apply_pursuit_interception`), matching source's
# own real architecture — `ChangeOrderTargetAfterAttacker` fires reactively
# exactly when a switch action is about to execute
# (`Cmd_jumpifnopursuitswitchdmg`, battle_script_commands.c L8499), it is
# NOT baked into the initial priority/speed sort at all.
#
# ── Shared-primitive question (Step 0 point 2) — answered: NO single
# primitive covers items 11/12/13, confirmed by checking each against
# source individually rather than assuming symmetry:
#   - Items 8 (Pursuit) and 12 (Shell Trap), plus this project's
#     ALREADY-SHIPPED After You, all genuinely share one primitive: source's
#     `ChangeOrderTargetAfterAttacker` — "splice battler X to occupy a given
#     slot, shifting whoever's there (and after) back by one." This
#     project's own pre-existing After You code (`_turn_order.remove_at`/
#     `.insert(_current_actor_index + 1, ...)`) already WAS this exact
#     shape — extracted into the new shared `_splice_battler_to_position`
#     helper, which After You now calls too (pure refactor, behavior
#     unchanged, confirmed via regression).
#   - Item 11 (Round) needs a STABLE PARTITION shape instead: source's
#     `TryUpdateRoundTurnOrder` (battle_script_commands.c L11099-11141)
#     buckets all not-yet-acted battlers into [Round users] then
#     [everyone else], preserving each bucket's own relative order,
#     placed contiguously right after the current Round user's position.
#     Genuinely different from a pairwise splice.
#   - Item 13 (Quash) needs a third, different shape: source's real Gen8+
#     algorithm (`BS_TryQuash`, battle_script_commands.c L11762-11796) is an
#     INCREMENTAL BUBBLE-SWAP — push the target back one slot at a time via
#     pairwise `GetWhichBattlerFaster` comparisons, stopping the instant the
#     target is faster than the next remaining battler (NOT "always move to
#     the absolute end", which is only the pre-Gen8 behavior). This
#     project's `GEN_LATEST=GEN_9` config activates the Gen8+ branch, so the
#     OLD "always append to end" implementation was a real, confirmed bug
#     for this project's own active config, not a disclosed simplification.
#
# ── Item 5 (Dragon Darts) — confirmed genuinely different in shape from all
# four items above: NOT a spread/redirect at all. Source's real mechanism
# (`CancelerAccuracyCheck`'s `isSmartTarget` branch, battle_move_resolution.c
# L2189-2225): roll the FIRST hit against whichever target is currently
# selected; if THAT SPECIFIC roll misses (and Follow-Me/CanTargetPartner/
# immunity eligibility conditions hold), silently redirect `gBattlerTarget`
# to the target's ally for the retry, with no miss recorded against the
# original target at all. This needed a new per-hit redirect capability
# inside `_do_multi_hit_sequence`, reusing NEW ITEM D's now-per-target-
# capable `StatusManager.check_accuracy` for each individual hit's own roll.
#
# All 5 items implemented this session (build order: 8 -> 12 -> 11 -> 13 ->
# 5, per Step 0's own risk-ordering, confirmed with Rob via AskUserQuestion
# before proceeding given the "no shared primitive for 11/12/13" fork).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_item8_pursuit_transitivity_fix()
	_test_item8_multiple_pursuers()
	_test_item8_negative_control_no_pursuit()
	_test_item12_shell_trap_doubles_splice()
	_test_item12_singles_no_splice()
	_test_item11_round_promotes_single_later_user()
	_test_item11_round_promotes_multiple_later_users()
	_test_item11_singles_no_promotion()
	_test_item13_quash_partial_bubble()
	_test_item13_quash_bubbles_to_end_when_slower_than_all()
	_test_item13_quash_noop_when_already_faster()
	_test_item5_dragon_darts_normal_hit()
	_test_item5_dragon_darts_redirects_on_miss()
	_test_item5_dragon_darts_both_miss_no_redirect_possible()
	_test_item5_dragon_darts_no_redirect_when_ally_fainted()
	_test_item5_dragon_darts_no_redirect_when_ally_immune()
	_test_item5_dragon_darts_singles_no_redirect()

	var total := _pass + _fail
	print("turn_order_splice_test: %d/%d passed" % [_pass, total])
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


func _make_mon_stats(mon_name: String, mon_type: int, spd: int,
		base_atk: int = 60, base_def: int = 60, base_hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_atk
	sp.base_sp_defense = base_def
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# Direct single-dispatch helper: constructs a bare 4-combatant doubles
# BattleManager and calls `_phase_priority_resolution()` exactly once,
# returning the resulting `_turn_order`. Bypasses the full multi-turn battle
# loop entirely (this project's established direct-dispatch convention),
# and — critically for these tests — leaves `tiebreak[mon] = randi()` and
# any other real RNG completely UNFORCED, since the whole point is proving
# the fix is deterministic regardless of what random values come out.
func _dispatch_priority(a0: BattlePokemon, a1: BattlePokemon,
		b0: BattlePokemon, b1: BattlePokemon,
		moves: Array[MoveData], switch_slots: Array[int]) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = moves
	bm._chosen_switch_slots = switch_slots
	# [M22 Phase 1] _phase_priority_resolution's comparator now also reads
	# _chosen_items — must be sized to match or every pairwise comparison
	# crashes on an out-of-bounds read. None of these tests exercise item
	# actions, so an all-null array is the correct "nothing changed" fixture.
	bm._chosen_items = [null, null, null, null]
	bm._phase_priority_resolution()
	return bm


# ── Item 8 Section: Pursuit interception transitivity fix ──────────────────

func _test_item8_pursuit_transitivity_fix() -> void:
	var pursuit := _load_move(228)
	var tackle := _load_move(33)

	# The exact reproduction shape from docs/decisions.md's own writeup:
	# A0 (Pursuit) and its own ally A1 (ordinary move) tied at the SAME
	# speed — the tie that made the old comparator's cycle manifest
	# differently depending on the random tiebreak. B0 switches; B1 uses an
	# ordinary move. Run 20 times (per Step 0's own "budget more reruns
	# here specifically" instruction) — the fix must hold regardless of
	# which random tiebreak value comes out for the A0/A1 tie.
	var trials := 20
	var all_correct := true
	for i in range(trials):
		var a0 := _make_mon_stats("P8A0_%d" % i, TypeChart.TYPE_DARK, 80)
		var a1 := _make_mon_stats("P8A1_%d" % i, TypeChart.TYPE_NORMAL, 80)  # tied speed with a0
		var b0 := _make_mon_stats("P8B0_%d" % i, TypeChart.TYPE_NORMAL, 60)
		var b1 := _make_mon_stats("P8B1_%d" % i, TypeChart.TYPE_NORMAL, 40)
		var moves: Array[MoveData] = [pursuit, tackle, null, tackle]
		var switch_slots: Array[int] = [-1, -1, 1, -1]  # b0 switches
		var bm := _dispatch_priority(a0, a1, b0, b1, moves, switch_slots)
		var a0_pos: int = bm._turn_order.find(a0)
		var b0_pos: int = bm._turn_order.find(b0)
		if a0_pos == -1 or b0_pos == -1 or a0_pos >= b0_pos:
			all_correct = false
			print("  trial %d FAILED: turn_order = %s" % [i, bm._turn_order])
		bm.queue_free()
	_chk("A.01 REQUIRED: Pursuit (A0) sorts before the opposing switcher " +
			"(B0) in EVERY one of %d trials, regardless of the random A0/A1 " % [trials] +
			"speed-tie tiebreak value each trial produces — proves the fix " +
			"is deterministic, not just 'usually works'", all_correct)


func _test_item8_multiple_pursuers() -> void:
	# Both A0 and A1 choose Pursuit against the same switcher (B0) — a real
	# doubles scenario (B_PURSUIT_TARGET >= GEN_4 means ANY opposing Pursuit
	# user intercepts, not just one that specifically targeted the
	# switcher). Both must end up before B0, in their OWN relative
	# priority/speed order (A0 faster than A1 here, no tie).
	var pursuit := _load_move(228)
	var a0 := _make_mon_stats("P8mA0", TypeChart.TYPE_DARK, 100)
	var a1 := _make_mon_stats("P8mA1", TypeChart.TYPE_DARK, 90)
	var b0 := _make_mon_stats("P8mB0", TypeChart.TYPE_NORMAL, 60)
	var b1 := _make_mon_stats("P8mB1", TypeChart.TYPE_NORMAL, 40)
	var moves: Array[MoveData] = [pursuit, pursuit, null, null]
	var switch_slots: Array[int] = [-1, -1, 1, 1]  # both b0 and b1 switch
	var bm := _dispatch_priority(a0, a1, b0, b1, moves, switch_slots)
	var a0_pos: int = bm._turn_order.find(a0)
	var a1_pos: int = bm._turn_order.find(a1)
	var b0_pos: int = bm._turn_order.find(b0)
	_chk("B.01 REQUIRED: both opposing Pursuit users (A0, A1) sort before " +
			"the switcher (B0) they both intercept", a0_pos < b0_pos and a1_pos < b0_pos)
	_chk("B.02 the two pursuers keep their OWN relative speed order " +
			"(A0 faster than A1) even after both are spliced ahead of B0",
			a0_pos < a1_pos)
	bm.queue_free()


func _test_item8_negative_control_no_pursuit() -> void:
	# No Pursuit anywhere — ordinary switch-before-moves rule must still
	# hold exactly as before this session's own comparator change.
	var tackle := _load_move(33)
	var a0 := _make_mon_stats("P8nA0", TypeChart.TYPE_NORMAL, 80)
	var a1 := _make_mon_stats("P8nA1", TypeChart.TYPE_NORMAL, 80)
	var b0 := _make_mon_stats("P8nB0", TypeChart.TYPE_NORMAL, 60)
	var b1 := _make_mon_stats("P8nB1", TypeChart.TYPE_NORMAL, 40)
	var moves: Array[MoveData] = [tackle, tackle, null, tackle]
	var switch_slots: Array[int] = [-1, -1, 1, -1]
	var bm := _dispatch_priority(a0, a1, b0, b1, moves, switch_slots)
	var b0_pos: int = bm._turn_order.find(b0)
	_chk("C.01 negative control: with no Pursuit anywhere, the switcher " +
			"(B0) still sorts FIRST (ordinary switch-before-moves rule, " +
			"unaffected by this session's comparator change)", b0_pos == 0)
	bm.queue_free()


# ── Item 12 Section: Shell Trap doubles turn-order splice ───────────────────

func _test_item12_shell_trap_doubles_splice() -> void:
	var tackle := _load_move(33)
	var shell_trap := _load_move(658)
	var a0 := _make_mon_stats("St12A0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("St12A1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("St12B0", TypeChart.TYPE_WATER, 30)  # slow — normally acts last
	var b1 := _make_mon_stats("St12B1", TypeChart.TYPE_NORMAL, 20)

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	# B0's OWN chosen move this turn is Shell Trap (arming reactively when
	# hit by a physical move, per the existing D4-Bundle-7 mechanism this
	# session's own splice hooks into).
	bm._chosen_moves = [tackle, null, shell_trap, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_items = [null, null, null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [2, 0, 0, 0]  # A0 targets B0 (index 2)
	# Initial (pre-splice) order: A0 fastest, then A1, then B0, then B1 —
	# B0 is SLOW, normally scheduled last; the splice must move it up.
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("D.01 REQUIRED: B0's Shell Trap armed reactively from the physical hit",
			b0.shell_trap_armed == true)
	var a0_pos: int = bm._turn_order.find(a0)
	var b0_pos: int = bm._turn_order.find(b0)
	var a1_pos: int = bm._turn_order.find(a1)
	_chk("D.02 REQUIRED (the core fix): B0 is spliced to occupy the slot " +
			"IMMEDIATELY after its own attacker (A0), NOT waiting for its " +
			"own slow/-3-priority turn at the end — final order: %s" % [bm._turn_order],
			b0_pos == a0_pos + 1)
	_chk("D.03 A1 (and everyone else originally between A0 and B0) shifted " +
			"back by exactly one slot, not disturbed further", a1_pos == a0_pos + 2)
	bm.queue_free()


func _test_item12_singles_no_splice() -> void:
	# Doubles-only gate (IsDoubleBattle() in source) — in a singles-shaped
	# dispatch (_active_per_side == 1), Shell Trap still arms, but no
	# turn-order splice should occur at all.
	var tackle := _load_move(33)
	var shell_trap := _load_move(658)
	var a0 := _make_mon_stats("St12sA0", TypeChart.TYPE_NORMAL, 100)
	var b0 := _make_mon_stats("St12sB0", TypeChart.TYPE_WATER, 30)

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var combatants: Array[BattlePokemon] = [a0, b0]
	bm._combatants = combatants
	bm._active_per_side = 1
	var actor_indices := {}
	for i in range(2):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [tackle, shell_trap]
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_items = [null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [1, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("E.01 Shell Trap still arms in singles", b0.shell_trap_armed == true)
	_chk("E.02 REQUIRED: no turn-order splice occurs in singles (order " +
			"unchanged: [A0, B0])", bm._turn_order == combatants)
	bm.queue_free()


# ── Item 11 Section: Round doubles turn-order stable-partition promotion ────

# Direct single-dispatch helper for Round's own scenario: A0 (fastest, acts
# first) uses Round against B0; A1/B1's own chosen moves vary per test.
# Initial `_turn_order` is manually set to the "already speed-sorted" shape
# ([A0, A1, B0, B1]) since this test is isolating the POST-hit promotion
# logic, not the priority-resolution sort itself (already covered by item 8's
# own section and the pre-existing `m19_bucket4_pairs_test.gd` Round tests).
func _dispatch_round(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon,
		b1: BattlePokemon, moves: Array[MoveData]) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = moves
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_items = [null, null, null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [2, 2, 0, 0]  # A0/A1 both target B0 for simplicity
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_item11_round_promotes_single_later_user() -> void:
	var round_move := _load_move(496)
	var tackle := _load_move(33)
	var a0 := _make_mon_stats("R11A0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("R11A1", TypeChart.TYPE_NORMAL, 90)  # NOT Round
	var b0 := _make_mon_stats("R11B0", TypeChart.TYPE_NORMAL, 80)  # NOT Round
	var b1 := _make_mon_stats("R11B1", TypeChart.TYPE_NORMAL, 70)  # Round — should be promoted
	var moves: Array[MoveData] = [round_move, tackle, tackle, round_move]
	var bm := _dispatch_round(a0, a1, b0, b1, moves)

	_chk("F.01 REQUIRED (the core fix): B1 (the only other Round user, " +
			"originally last/slowest) is promoted to occupy the slot " +
			"immediately after A0 — final order: %s" % [bm._turn_order],
			bm._turn_order == [a0, b1, a1, b0])
	bm.queue_free()


func _test_item11_round_promotes_multiple_later_users() -> void:
	var round_move := _load_move(496)
	var tackle := _load_move(33)
	var a0 := _make_mon_stats("R11mA0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("R11mA1", TypeChart.TYPE_NORMAL, 90)  # NOT Round
	var b0 := _make_mon_stats("R11mB0", TypeChart.TYPE_NORMAL, 80)  # Round
	var b1 := _make_mon_stats("R11mB1", TypeChart.TYPE_NORMAL, 70)  # Round
	var moves: Array[MoveData] = [round_move, tackle, round_move, round_move]
	var bm := _dispatch_round(a0, a1, b0, b1, moves)

	_chk("G.01 REQUIRED: BOTH other Round users (B0, B1) are promoted " +
			"ahead of the non-Round user (A1), preserving their own " +
			"relative speed order (B0 before B1) — final order: %s" % [bm._turn_order],
			bm._turn_order == [a0, b0, b1, a1])
	bm.queue_free()


func _test_item11_singles_no_promotion() -> void:
	var round_move := _load_move(496)
	var a0 := _make_mon_stats("R11sA0", TypeChart.TYPE_NORMAL, 100)
	var b0 := _make_mon_stats("R11sB0", TypeChart.TYPE_NORMAL, 50)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var combatants: Array[BattlePokemon] = [a0, b0]
	bm._combatants = combatants
	bm._active_per_side = 1
	var actor_indices := {}
	for i in range(2):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [round_move, round_move]
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_items = [null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [1, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()

	_chk("H.01 REQUIRED: no promotion occurs in singles (doubles-only gate, " +
			"order unchanged: [A0, B0])", bm._turn_order == combatants)
	bm.queue_free()


# ── Item 13 Section: Quash real Gen8+ bubble-swap ────────────────────────────
#
# Re-derived from source this session (BS_TryQuash, battle_script_commands.c
# L11762-11796): the CURRENT (pre-fix) implementation always pushed the
# target to the absolute end of `_turn_order` — that's only correct for the
# PRE-Gen8 config (`B_QUASH_TURN_ORDER < GEN_8`). This project's own
# GEN_LATEST=GEN_9 config activates the real Gen8+ algorithm: push the
# target back ONE SLOT AT A TIME past remaining battlers it's genuinely
# slower than, stopping the INSTANT it reaches one it's faster than — "as
# close to last as possible without changing order relative to Pokémon it's
# faster than," not unconditionally last. These tests construct `_turn_order`
# directly (this project's own established direct-dispatch convention) so
# the bubble mechanism itself can be exercised in isolation, independent of
# how such an arrangement might arise via priority/Trick-Room/mid-turn
# speed changes in a full battle.

func _dispatch_quash(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon,
		b1: BattlePokemon, initial_order: Array[BattlePokemon]) -> BattleManager:
	var quash := _load_move(511)
	var tackle := _load_move(33)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [quash, tackle, tackle, tackle]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_items = [null, null, null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [2, 0, 0, 0]  # A0's Quash targets B0 (index 2)
	bm._turn_order = initial_order.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_item13_quash_partial_bubble() -> void:
	# B0 (Quash target, speed 50) is SLOWER than the very next battler (A1,
	# speed 90) but FASTER than the one after that (B1, speed 30) — the
	# bubble must swap exactly once (past A1) and then STOP, distinct from
	# the old "always to the absolute end" behavior (which would have also
	# pushed it past B1).
	var a0 := _make_mon_stats("Q13aA0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("Q13aA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("Q13aB0", TypeChart.TYPE_NORMAL, 50)
	var b1 := _make_mon_stats("Q13aB1", TypeChart.TYPE_NORMAL, 30)
	var initial: Array[BattlePokemon] = [a0, b0, a1, b1]
	var bm := _dispatch_quash(a0, a1, b0, b1, initial)
	_chk("I.01 REQUIRED (the core fix): B0 swaps past A1 (faster than " +
			"B0) but stops BEFORE B1 (slower than B0) — final order: %s, " % [bm._turn_order] +
			"NOT pushed all the way to the absolute end",
			bm._turn_order == [a0, a1, b0, b1])
	bm.queue_free()


func _test_item13_quash_bubbles_to_end_when_slower_than_all() -> void:
	# B0 (target, speed 20) is genuinely slower than BOTH remaining
	# battlers — the bubble correctly walks it all the way to the end in
	# this case (matching what the old buggy implementation would ALSO
	# have produced here, but for the right underlying reason this time).
	var a0 := _make_mon_stats("Q13bA0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("Q13bA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("Q13bB0", TypeChart.TYPE_NORMAL, 20)
	var b1 := _make_mon_stats("Q13bB1", TypeChart.TYPE_NORMAL, 60)
	var initial: Array[BattlePokemon] = [a0, b0, a1, b1]
	var bm := _dispatch_quash(a0, a1, b0, b1, initial)
	_chk("J.01 B0 (slower than every remaining battler) still ends up " +
			"last — final order: %s" % [bm._turn_order], bm._turn_order == [a0, a1, b1, b0])
	bm.queue_free()


func _test_item13_quash_noop_when_already_faster() -> void:
	# B0 (target, speed 90) is already faster than everyone remaining —
	# the real Gen8+ bubble does NOTHING at all here (a genuine no-op,
	# distinct from the old implementation which would have unconditionally
	# relocated it to the end regardless of its own speed).
	var a0 := _make_mon_stats("Q13cA0", TypeChart.TYPE_NORMAL, 100)
	var a1 := _make_mon_stats("Q13cA1", TypeChart.TYPE_NORMAL, 60)
	var b0 := _make_mon_stats("Q13cB0", TypeChart.TYPE_NORMAL, 90)
	var b1 := _make_mon_stats("Q13cB1", TypeChart.TYPE_NORMAL, 30)
	var initial: Array[BattlePokemon] = [a0, b0, a1, b1]
	var bm := _dispatch_quash(a0, a1, b0, b1, initial)
	_chk("K.01 REQUIRED: B0 stays exactly where it started (already " +
			"faster than everything remaining) — final order: %s" % [bm._turn_order],
			bm._turn_order == initial)
	bm.queue_free()


# ── Item 5 Section: Dragon Darts smart-target redirect ──────────────────────
#
# All scenarios use semi-invulnerability (fully deterministic — Dragon Darts
# carries none of damages_underground/damages_airborne/damages_underwater,
# so ANY semi-invulnerable state blocks its own accuracy check unconditionally,
# no RNG needed) to force the ORIGINAL target's own check to fail, rather
# than relying on evasion-stage probability bands (which can't reach exactly
# 0%) — matching NEW ITEM D's own established "use semi-invulnerable for a
# fully deterministic miss" testing pattern.

func _dispatch_dragon_darts(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon,
		b1: BattlePokemon, per_target_hits: Dictionary, whole_missed: Array) -> BattleManager:
	var dragon_darts := _load_move(697)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, _dmg):
		if atk == a0 and mv == dragon_darts:
			per_target_hits[d] = per_target_hits.get(d, 0) + 1
	)
	bm.move_missed.connect(func(atk, _reason):
		if atk == a0:
			whole_missed.append(true)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [dragon_darts, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_items = [null, null, null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [2, 0, 0, 0]  # A0 targets B0 (index 2)
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_item5_dragon_darts_normal_hit() -> void:
	# No redirect needed: the original target (B0) isn't semi-invulnerable,
	# so its own accuracy check succeeds (move accuracy=100, no evasion) —
	# BOTH hits land on B0, exactly as before this session's own change.
	var a0 := _make_mon_stats("D5aA0", TypeChart.TYPE_DRAGON, 100)
	var a1 := _make_mon_stats("D5aA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("D5aB0", TypeChart.TYPE_NORMAL, 60)
	var b1 := _make_mon_stats("D5aB1", TypeChart.TYPE_NORMAL, 40)
	var per_target_hits := {}
	var whole_missed := []
	var bm := _dispatch_dragon_darts(a0, a1, b0, b1, per_target_hits, whole_missed)
	_chk("L.01 REQUIRED: both hits land on the original target (B0), no " +
			"redirect engaged — hits: %s" % [per_target_hits],
			per_target_hits.get(b0, 0) == 2 and not per_target_hits.has(b1))
	bm.queue_free()


func _test_item5_dragon_darts_redirects_on_miss() -> void:
	# B0 (original target) is semi-invulnerable (mid-Fly) — its own check
	# deterministically fails, redirecting ONCE to its ally B1 (not
	# semi-invulnerable, accuracy=100) — BOTH hits should land on B1
	# instead, and B0 should be completely untouched.
	var a0 := _make_mon_stats("D5bA0", TypeChart.TYPE_DRAGON, 100)
	var a1 := _make_mon_stats("D5bA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("D5bB0", TypeChart.TYPE_NORMAL, 60)
	b0.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var b1 := _make_mon_stats("D5bB1", TypeChart.TYPE_NORMAL, 40)
	var per_target_hits := {}
	var whole_missed := []
	var bm := _dispatch_dragon_darts(a0, a1, b0, b1, per_target_hits, whole_missed)
	_chk("M.01 REQUIRED (the core fix): both hits redirect to the ally " +
			"(B1) after the original target (B0, semi-invulnerable) misses " +
			"— hits: %s" % [per_target_hits],
			per_target_hits.get(b1, 0) == 2 and not per_target_hits.has(b0))
	_chk("M.02 the redirected hits succeeding means the whole-move " +
			"move_missed signal does NOT fire", whole_missed.is_empty())
	bm.queue_free()


func _test_item5_dragon_darts_both_miss_no_redirect_possible() -> void:
	# BOTH B0 and B1 are semi-invulnerable — the redirect happens (B1 is a
	# valid, live, non-immune ally) but B1's OWN check also fails
	# deterministically — a genuine total miss, no damage anywhere.
	var a0 := _make_mon_stats("D5cA0", TypeChart.TYPE_DRAGON, 100)
	var a1 := _make_mon_stats("D5cA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("D5cB0", TypeChart.TYPE_NORMAL, 60)
	b0.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var b1 := _make_mon_stats("D5cB1", TypeChart.TYPE_NORMAL, 40)
	b1.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var per_target_hits := {}
	var whole_missed := []
	var bm := _dispatch_dragon_darts(a0, a1, b0, b1, per_target_hits, whole_missed)
	_chk("N.01 REQUIRED: no damage anywhere when both the original " +
			"target and the redirected ally are unhittable", per_target_hits.is_empty())
	_chk("N.02 the whole-move move_missed signal fires for the genuine " +
			"total miss", whole_missed.size() == 1)
	bm.queue_free()


func _test_item5_dragon_darts_no_redirect_when_ally_fainted() -> void:
	# B0 semi-invulnerable, B1 already fainted — no valid ally exists, so
	# no redirect is attempted at all; the move simply misses.
	var a0 := _make_mon_stats("D5dA0", TypeChart.TYPE_DRAGON, 100)
	var a1 := _make_mon_stats("D5dA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("D5dB0", TypeChart.TYPE_NORMAL, 60)
	b0.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var b1 := _make_mon_stats("D5dB1", TypeChart.TYPE_NORMAL, 40)
	b1.current_hp = 0
	b1.fainted = true
	var per_target_hits := {}
	var whole_missed := []
	var bm := _dispatch_dragon_darts(a0, a1, b0, b1, per_target_hits, whole_missed)
	_chk("O.01 REQUIRED: no redirect and no damage when the only " +
			"candidate ally has already fainted", per_target_hits.is_empty())
	_chk("O.02 whole-move miss fires", whole_missed.size() == 1)
	bm.queue_free()


func _test_item5_dragon_darts_no_redirect_when_ally_immune() -> void:
	# B0 semi-invulnerable, B1 alive but Fairy-type (flatly immune to
	# Dragon-type moves) — redirect eligibility fails on the ally's own
	# type immunity, falling back to a genuine miss against B0.
	var a0 := _make_mon_stats("D5eA0", TypeChart.TYPE_DRAGON, 100)
	var a1 := _make_mon_stats("D5eA1", TypeChart.TYPE_NORMAL, 90)
	var b0 := _make_mon_stats("D5eB0", TypeChart.TYPE_NORMAL, 60)
	b0.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var b1 := _make_mon_stats("D5eB1", TypeChart.TYPE_FAIRY, 40)
	var per_target_hits := {}
	var whole_missed := []
	var bm := _dispatch_dragon_darts(a0, a1, b0, b1, per_target_hits, whole_missed)
	_chk("P.01 REQUIRED: no redirect and no damage when the only " +
			"candidate ally is flatly immune to the move's type", per_target_hits.is_empty())
	_chk("P.02 whole-move miss fires", whole_missed.size() == 1)
	bm.queue_free()


func _test_item5_dragon_darts_singles_no_redirect() -> void:
	# No ally exists in singles (_active_per_side == 1) — B0 semi-
	# invulnerable still just misses outright, no crash, no redirect
	# attempted.
	var dragon_darts := _load_move(697)
	var a0 := _make_mon_stats("D5fA0", TypeChart.TYPE_DRAGON, 100)
	var b0 := _make_mon_stats("D5fB0", TypeChart.TYPE_NORMAL, 60)
	b0.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	var per_target_hits := {}
	var whole_missed := []
	bm.move_executed.connect(func(atk, d, mv, _dmg):
		if atk == a0 and mv == dragon_darts:
			per_target_hits[d] = per_target_hits.get(d, 0) + 1
	)
	bm.move_missed.connect(func(atk, _reason):
		if atk == a0:
			whole_missed.append(true)
	)
	var combatants: Array[BattlePokemon] = [a0, b0]
	bm._combatants = combatants
	bm._active_per_side = 1
	var actor_indices := {}
	for i in range(2):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [dragon_darts, null]
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_items = [null, null]  # [M22 Phase 1] sizing guard
	bm._chosen_targets = [1, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("Q.01 REQUIRED: singles Dragon Darts vs a semi-invulnerable " +
			"target just misses outright, no redirect/crash", per_target_hits.is_empty())
	_chk("Q.02 whole-move miss fires", whole_missed.size() == 1)
	bm.queue_free()
