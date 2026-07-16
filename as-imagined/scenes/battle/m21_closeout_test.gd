extends Node

# [M21 closeout] Acupressure ally-choice + Lightning Rod/Storm Drain
# attacker-ally redirect — Step 0 + implementation.
#
# Closes the final two open items from docs/m21_recon.md's doubles-
# interaction-cleanup inventory.
#
# ── Item 1 (Acupressure's TARGET_USER_OR_ALLY ally-choice gap) ─────────────
# Step 0 confirmed source's real self-vs-ally choice is a genuine PLAYER-
# FACING target-selection menu decision (`battle_controller_player.c`'s own
# TARGET_USER_OR_ALLY-specific branches, not an AI-only or automatic rule).
# This project has no real target-selection UI (deliberately deferred to
# M10, unbuilt) — but critically, this project's OWN existing
# `_chosen_targets` mechanism (already used to let a test/AI pick which of
# two opponents a foe-targeting move hits in doubles) serves this identically
# without needing any NEW infrastructure: it's already a general "which
# target was selected" resolution, just never previously read by an
# ally-targeting-CHOICE move (every ally-targeting move shipped so far —
# Helping Hand, Aromatic Mist, Coaching — is ALWAYS ally-only, a fixed
# target, never a genuine choice between two options). Confirmed NOT
# blocked on new UI infrastructure — implemented by having Acupressure's own
# dispatch read whichever combatant `_chosen_targets` resolved to (already
# computed generically as `defender` before Acupressure's own branch),
# falling back safely to self whenever that isn't the attacker's own live
# ally (singles, or nothing explicitly chosen — matching `_default_target`'s
# own generic opponent-returning behavior, which would otherwise be wrong
# for this move specifically).
#
# ── Item 2 (Lightning Rod/Storm Drain attacker-ally redirect) ──────────────
# Step 0 re-derived `HandleMoveTargetRedirection` precisely
# (battle_move_resolution.c:822-888): source runs ONE UNIFIED loop over
# every battler (excluding the attacker itself and the current target),
# picking whichever qualifying Lightning-Rod/Storm-Drain holder has the
# EARLIEST turn order — NOT two separate special cases for "target's ally"
# vs "attacker's ally". In this project's fixed 2v2 doubles shape, excluding
# attacker+target from the 4 total battlers leaves exactly two possible
# candidates (the target's own ally, the attacker's own ally), so both are
# modeled explicitly as the two candidates that unified loop could ever
# actually find here. `AbilityManager.resolve_redirect_target` gained a new
# `attacker_ally` parameter (required, inserted before `move_type`) plus
# optional turn-position ints for the tie-break when both qualify at once —
# confirmed via source's own `GetBattlerTurnOrderNum(battler) <
# redirectorOrderNum` comparison, not a new/different rule. Already
# Mold-Breaker-aware "for free" (every ability check routes through
# `effective_ability_id(..., attacker)`, unchanged from before this session).
#
# Test-audit-first pass: `m17l_test.gd`'s own direct unit tests
# (S2.06-S2.12) called the OLD 4-positional-arg signature — updated in
# place to pass `null` for the new `attacker_ally` param (none of those
# tests exercise the attacker-ally case, which gets its own dedicated
# coverage below). Caught via a real hang when first run post-signature-
# change (a GDScript static-type mismatch — TypeChart.TYPE_ELECTRIC, an
# int, landing in the new BattlePokemon-typed `attacker_ally` slot — not a
# logic bug in the new code itself). `d4_bundle6_test.gd`'s own Acupressure
# section (J.01/J.02) re-ran unchanged and clean (both scenarios are
# singles, where the ally-choice change is a structural no-op).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_acupressure_targets_ally_when_chosen()
	_test_acupressure_falls_back_to_self_when_not_chosen()
	_test_acupressure_falls_back_to_self_when_ally_fainted()
	_test_acupressure_ally_choice_respects_ally_own_eligibility()
	_test_acupressure_singles_negative_control()
	_test_lightning_rod_redirects_attacker_own_ally()
	_test_lightning_rod_existing_target_ally_redirect_unaffected()
	_test_lightning_rod_both_qualify_earliest_turn_order_wins()
	_test_lightning_rod_both_qualify_reversed_turn_order()

	var total := _pass + _fail
	print("m21_closeout_test: %d/%d passed" % [_pass, total])
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon_stats(mon_name: String, mon_type: int, spd: int = 60,
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


# ── Item 1: Acupressure ──────────────────────────────────────────────────────

# Direct single-dispatch helper: A0 uses Acupressure, `chosen_target_idx`
# controls which combatant index `_chosen_targets[0]` resolves to (2 = B0,
# the generic `_default_target`-style opponent default; 1 = A1, the
# attacker's own ally).
func _dispatch_acupressure(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon,
		b1: BattlePokemon, chosen_target_idx: int,
		stage_events: Array) -> BattleManager:
	var acupressure := _load_move(367)
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(mon, stat_idx, actual):
		stage_events.append([mon, stat_idx, actual])
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [acupressure, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [chosen_target_idx, 0, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_acupressure_targets_ally_when_chosen() -> void:
	var a0 := _make_mon_stats("Ac1A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Ac1A1", TypeChart.TYPE_NORMAL)
	var b0 := _make_mon_stats("Ac1B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Ac1B1", TypeChart.TYPE_NORMAL)
	var stage_events := []
	var bm := _dispatch_acupressure(a0, a1, b0, b1, 1, stage_events)  # A0 chooses A1 (its own ally)
	_chk("A.01 REQUIRED (the core fix): Acupressure raises the ALLY's (A1) " +
			"own stat, not the caster's (A0), when the ally is explicitly chosen " +
			"— events: %s" % [stage_events],
			stage_events.size() == 1 and stage_events[0][0] == a1)
	bm.queue_free()


func _test_acupressure_falls_back_to_self_when_not_chosen() -> void:
	# _chosen_targets pointing at an OPPONENT (B0, index 2 — the generic
	# _default_target-style value every other move would get by default)
	# must NOT be treated as a valid Acupressure target — falls back to self.
	var a0 := _make_mon_stats("Ac2A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Ac2A1", TypeChart.TYPE_NORMAL)
	var b0 := _make_mon_stats("Ac2B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Ac2B1", TypeChart.TYPE_NORMAL)
	var stage_events := []
	var bm := _dispatch_acupressure(a0, a1, b0, b1, 2, stage_events)  # resolves to B0 (an opponent)
	_chk("B.01 REQUIRED: an opponent as the resolved target falls back to " +
			"self (A0), never raises an opponent's stat — events: %s" % [stage_events],
			stage_events.size() == 1 and stage_events[0][0] == a0)
	bm.queue_free()


func _test_acupressure_falls_back_to_self_when_ally_fainted() -> void:
	var a0 := _make_mon_stats("Ac3A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Ac3A1", TypeChart.TYPE_NORMAL)
	a1.current_hp = 0
	a1.fainted = true
	var b0 := _make_mon_stats("Ac3B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Ac3B1", TypeChart.TYPE_NORMAL)
	var stage_events := []
	var bm := _dispatch_acupressure(a0, a1, b0, b1, 1, stage_events)  # A1 chosen but fainted
	_chk("C.01 REQUIRED: a fainted ally falls back to self, even if " +
			"explicitly chosen — events: %s" % [stage_events],
			stage_events.size() == 1 and stage_events[0][0] == a0)
	bm.queue_free()


func _test_acupressure_ally_choice_respects_ally_own_eligibility() -> void:
	# The ally (A1) has all 7 stats already maxed; the caster (A0) does not.
	# Choosing the ally must FAIL outright (matching source: the choice is
	# already locked in, no automatic fallback-to-self-if-capped).
	var a0 := _make_mon_stats("Ac4A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Ac4A1", TypeChart.TYPE_NORMAL)
	for i in range(7):
		a1.stat_stages[i] = 6
	var b0 := _make_mon_stats("Ac4B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Ac4B1", TypeChart.TYPE_NORMAL)
	var stage_events := []
	var acupressure := _load_move(367)
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(mon, stat_idx, actual): stage_events.append([mon, stat_idx, actual]))
	var fail_events := []
	bm.move_effect_failed.connect(func(_a, reason): fail_events.append(reason))
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [acupressure, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [1, 0, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("D.01 REQUIRED: choosing a maxed-out ally fails outright (no " +
			"fallback to raising self instead) — stage events: %s, fail: %s" %
			[stage_events, fail_events],
			stage_events.is_empty() and fail_events == ["stat_limit"])
	bm.queue_free()


func _test_acupressure_singles_negative_control() -> void:
	var acupressure := _load_move(367)
	var atk := _make_mon_stats("Ac5Atk", TypeChart.TYPE_NORMAL)
	atk.add_move(acupressure)
	var def := _make_mon_stats("Ac5Def", TypeChart.TYPE_NORMAL)
	var stage_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.stat_stage_changed.connect(func(mon, stat_idx, actual):
		if stage_events.is_empty():
			stage_events.append([mon, stat_idx, actual]))
	bm.start_battle(atk, def)
	_chk("E.01 singles negative control: no ally exists, Acupressure " +
			"always raises the caster's own stat — events: %s" % [stage_events],
			stage_events.size() == 1 and stage_events[0][0] == atk)
	bm.queue_free()


# ── Item 2: Lightning Rod/Storm Drain attacker-ally redirect ────────────────

func _dispatch_thunderbolt(a0: BattlePokemon, a1: BattlePokemon, b0: BattlePokemon,
		b1: BattlePokemon, hit_events: Array) -> BattleManager:
	var thunderbolt := _load_move(85)  # Thunderbolt, single-target Electric
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == thunderbolt:
			hit_events.append(d)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [thunderbolt, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 0, 0, 0]  # A0 targets B0 (index 2)
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_lightning_rod_redirects_attacker_own_ally() -> void:
	var lightning_rod := _load_ability(31)
	var a0 := _make_mon_stats("Lr1A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Lr1A1", TypeChart.TYPE_NORMAL)  # attacker's own ally
	a1.ability = lightning_rod
	var b0 := _make_mon_stats("Lr1B0", TypeChart.TYPE_NORMAL)  # original target, no ability
	var b1 := _make_mon_stats("Lr1B1", TypeChart.TYPE_NORMAL)
	var hit_events := []
	var bm := _dispatch_thunderbolt(a0, a1, b0, b1, hit_events)
	_chk("F.01 REQUIRED (the core fix): Thunderbolt aimed at B0 redirects " +
			"onto the ATTACKER's own ally (A1, holding Lightning Rod) — hits: %s" % [hit_events],
			hit_events == [a1])
	bm.queue_free()


func _test_lightning_rod_existing_target_ally_redirect_unaffected() -> void:
	var lightning_rod := _load_ability(31)
	var a0 := _make_mon_stats("Lr2A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Lr2A1", TypeChart.TYPE_NORMAL)  # no ability
	var b0 := _make_mon_stats("Lr2B0", TypeChart.TYPE_NORMAL)  # original target, no ability
	var b1 := _make_mon_stats("Lr2B1", TypeChart.TYPE_NORMAL)  # target's own ally
	b1.ability = lightning_rod
	var hit_events := []
	var bm := _dispatch_thunderbolt(a0, a1, b0, b1, hit_events)
	_chk("G.01 negative control: the ORIGINAL, already-shipped redirect " +
			"case (target's own ally, B1) still works correctly and " +
			"unaffected — hits: %s" % [hit_events], hit_events == [b1])
	bm.queue_free()


func _test_lightning_rod_both_qualify_earliest_turn_order_wins() -> void:
	# BOTH A1 (attacker's ally) and B1 (target's ally) hold Lightning Rod —
	# A1 is placed EARLIER in _turn_order than B1, so A1 must win the
	# redirect (source's own "earliest turn order" tie-break), and exactly
	# ONE redirect must happen (no double-redirect).
	var lightning_rod := _load_ability(31)
	var a0 := _make_mon_stats("Lr3A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Lr3A1", TypeChart.TYPE_NORMAL)
	a1.ability = lightning_rod
	var b0 := _make_mon_stats("Lr3B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Lr3B1", TypeChart.TYPE_NORMAL)
	b1.ability = lightning_rod
	var hit_events := []
	var thunderbolt := _load_move(85)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, _dmg):
		if atk == a0 and mv == thunderbolt:
			hit_events.append(d)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [thunderbolt, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 0, 0, 0]
	# A1 (attacker's ally) placed earlier in turn order than B1 (target's ally).
	bm._turn_order = [a0, a1, b0, b1]
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("H.01 REQUIRED: when BOTH candidates qualify, the one with the " +
			"EARLIER turn order (A1) wins — exactly one redirect, no double-" +
			"redirect or wrong target — hits: %s" % [hit_events], hit_events == [a1])
	bm.queue_free()


func _test_lightning_rod_both_qualify_reversed_turn_order() -> void:
	# Same setup, but B1 (target's ally) is now EARLIER in turn order than
	# A1 (attacker's ally) — B1 must win instead, proving the tie-break is
	# genuinely turn-order-driven, not just "attacker's ally always wins".
	var lightning_rod := _load_ability(31)
	var a0 := _make_mon_stats("Lr4A0", TypeChart.TYPE_NORMAL)
	var a1 := _make_mon_stats("Lr4A1", TypeChart.TYPE_NORMAL)
	a1.ability = lightning_rod
	var b0 := _make_mon_stats("Lr4B0", TypeChart.TYPE_NORMAL)
	var b1 := _make_mon_stats("Lr4B1", TypeChart.TYPE_NORMAL)
	b1.ability = lightning_rod
	var hit_events := []
	var thunderbolt := _load_move(85)
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, _dmg):
		if atk == a0 and mv == thunderbolt:
			hit_events.append(d)
	)
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [thunderbolt, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 0, 0, 0]
	# B1 (target's ally) placed earlier in turn order than A1 (attacker's ally).
	bm._turn_order = [a0, b1, b0, a1]
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("I.01 REQUIRED: reversing the turn-order relationship flips the " +
			"winner to B1, confirming the tie-break is genuinely turn-order-" +
			"driven — hits: %s" % [hit_events], hit_events == [b1])
	bm.queue_free()
