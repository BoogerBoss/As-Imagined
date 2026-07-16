extends Node

# [D3 turn-order/event-tracker batch] Two independent families (8 moves):
#
# Part A — turn-order-manipulation family (4 moves): After You(495),
#   Quash(511), Upper Hand(846), Instruct(652). All read/write existing
#   _turn_order/_current_actor_index state; Instruct additionally reassigns
#   attacker/defender themselves (a genuinely new fall-through shape beyond
#   Mirror Move/Metronome's defender-only reassignment).
# Part B — "event happened this turn/battle" tracker family (4 moves):
#   Lash Out(736), Retaliate(514), Rage Fist(815), Echoed Voice(497). Each
#   mirrors the already-shipped stat_raised_this_turn pattern but with a
#   genuinely different scope/persistence: Lash Out is the exact decrease-
#   side mirror (self, per-turn); Retaliate is side-wide with a 2-turn
#   timer; Rage Fist is a battle-LIFETIME counter (no reset at all); Echoed
#   Voice is FIELD-WIDE (not per-mon/per-side).
#
# Ground truth: reference/pokeemerald_expansion/src/battle_util.c
# (case EFFECT_LASH_OUT L6308-6310, EFFECT_RETALIATE L6401-6406,
# EFFECT_RAGE_FIST L6349-6351, EFFECT_ECHOED_VOICE L6264-6270),
# src/battle_main.c (GetChosenMovePriority L4722-4731, SwapTurnOrder,
# retaliateTimer decrement L3939-3940, lashOutAffected reset L5056),
# src/battle_stat_change.c (lashOutAffected set L368),
# src/battle_script_commands.c (BS_TryAfterYou L13326-13338,
# BS_TryQuash L11762-11799, BS_TryInstruct L13149-13195, timesGotHit++
# L1685), src/battle_move_resolution.c (EFFECT_UPPER_HAND L1403-1417),
# src/battle_end_turn.c (echoedVoiceCounter L79-88), GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_after_you()
	_test_quash()
	_test_upper_hand()
	_test_instruct()
	_test_lash_out()
	_test_retaliate()
	_test_rage_fist()
	_test_echoed_voice()

	var total := _pass + _fail
	print("d3_batch_test: %d/%d passed" % [_pass, total])
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


# Doubling the effective base power BEFORE the damage formula's later floor
# operations and additive "+2" term doesn't guarantee an EXACTLY 2x/3x final
# output (the same over-precise-assertion pitfall CLAUDE.md's [D2 batch]
# entry already documents for Solar Beam's halving) — allow a small
# tolerance rather than demanding exact integer equality.
func _approx_scaled(actual: int, baseline: int, factor: int, tolerance: int = 4) -> bool:
	return absi(actual - baseline * factor) <= tolerance


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (8 moves) ─────────────────────────────────────

func _test_data_integrity() -> void:
	var after_you := _load_move(495)
	_chk("A.01 After You acc=0/pp=15/STAT/Normal",
			after_you.accuracy == 0 and after_you.pp == 15 and after_you.category == 2
			and after_you.type == TypeChart.TYPE_NORMAL)
	_chk("A.02 After You is_after_you/ignores_protect/ignores_substitute",
			after_you.is_after_you == true and after_you.ignores_protect == true
			and after_you.ignores_substitute == true)

	var quash := _load_move(511)
	_chk("A.03 Quash acc=100/pp=15/STAT/Dark",
			quash.accuracy == 100 and quash.pp == 15 and quash.category == 2
			and quash.type == TypeChart.TYPE_DARK)
	_chk("A.04 Quash is_quash", quash.is_quash == true)

	var upper_hand := _load_move(846)
	_chk("A.05 Upper Hand power=65/acc=100/pp=15/PHYS/Fighting/priority=3",
			upper_hand.power == 65 and upper_hand.accuracy == 100 and upper_hand.pp == 15
			and upper_hand.category == 0 and upper_hand.type == TypeChart.TYPE_FIGHTING
			and upper_hand.priority == 3)
	_chk("A.06 Upper Hand is_upper_hand/makes_contact/guaranteed SE_FLINCH",
			upper_hand.is_upper_hand == true and upper_hand.makes_contact == true
			and upper_hand.secondary_effect == MoveData.SE_FLINCH
			and upper_hand.secondary_chance == 100)

	var instruct := _load_move(652)
	_chk("A.07 Instruct acc=0/pp=15/STAT/Psychic",
			instruct.accuracy == 0 and instruct.pp == 15 and instruct.category == 2
			and instruct.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.08 Instruct is_instruct/ignores_substitute",
			instruct.is_instruct == true and instruct.ignores_substitute == true)

	var lash_out := _load_move(736)
	_chk("A.09 Lash Out power=75/acc=100/pp=5/PHYS/Dark",
			lash_out.power == 75 and lash_out.accuracy == 100 and lash_out.pp == 5
			and lash_out.category == 0 and lash_out.type == TypeChart.TYPE_DARK)
	_chk("A.10 Lash Out is_lash_out/makes_contact",
			lash_out.is_lash_out == true and lash_out.makes_contact == true)

	var retaliate := _load_move(514)
	_chk("A.11 Retaliate power=70/acc=100/pp=5/PHYS/Normal",
			retaliate.power == 70 and retaliate.accuracy == 100 and retaliate.pp == 5
			and retaliate.category == 0 and retaliate.type == TypeChart.TYPE_NORMAL)
	_chk("A.12 Retaliate is_retaliate/makes_contact",
			retaliate.is_retaliate == true and retaliate.makes_contact == true)

	var rage_fist := _load_move(815)
	_chk("A.13 Rage Fist power=50/acc=100/pp=10/PHYS/Ghost",
			rage_fist.power == 50 and rage_fist.accuracy == 100 and rage_fist.pp == 10
			and rage_fist.category == 0 and rage_fist.type == TypeChart.TYPE_GHOST)
	_chk("A.14 Rage Fist is_rage_fist/makes_contact/punching_move",
			rage_fist.is_rage_fist == true and rage_fist.makes_contact == true
			and rage_fist.punching_move == true)

	var echoed_voice := _load_move(497)
	_chk("A.15 Echoed Voice power=40/acc=100/pp=15/SPEC/Normal",
			echoed_voice.power == 40 and echoed_voice.accuracy == 100 and echoed_voice.pp == 15
			and echoed_voice.category == 1 and echoed_voice.type == TypeChart.TYPE_NORMAL)
	_chk("A.16 Echoed Voice is_echoed_voice/sound_move",
			echoed_voice.is_echoed_voice == true and echoed_voice.sound_move == true)


# ── Section B: After You ─────────────────────────────────────────────────────

func _test_after_you() -> void:
	# B.01: doubles, P0 (fastest) uses After You on O1 (currently LAST in
	# turn order) — pushes O1 to act immediately after P0, before P1/O0.
	var p0 := _make_mon("P0", 300, 60, 60, 60, 60, 100)
	var p1 := _make_mon("P1", 300, 60, 60, 60, 60, 90)
	var o0 := _make_mon("O0", 300, 60, 60, 60, 60, 80)
	var o1 := _make_mon("O1", 300, 60, 60, 60, 60, 70)
	var after_you := _load_move(495)
	var tackle := _load_move(33)
	p0.add_move(after_you)
	p1.add_move(tackle)
	o0.add_move(tackle)
	o1.add_move(tackle)

	var order := []
	var reorder_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, _d, _m, _amt): order.push_back(a))
	bm.turn_order_changed.connect(func(mover, reason): reorder_events.push_back([mover, reason]))

	var pp := BattleParty.new(); pp.members = [p0, p1]; pp.active_indices = [0, 1]
	var op := BattleParty.new(); op.members = [o0, o1]; op.active_indices = [0, 1]
	bm.queue_move_targeted(0, 0, 3)  # P0 uses After You(idx 0) targeting O1 (combatant idx 3)
	bm.start_battle_doubles(pp, op)

	_chk("B.01 turn_order_changed fired for O1/after_you",
			reorder_events.size() >= 1 and reorder_events[0][0] == o1 and reorder_events[0][1] == "after_you")
	_chk("B.02 execution order: P0, O1, P1, O0",
			order.size() >= 4 and order[0] == p0 and order[1] == o1
			and order[2] == p1 and order[3] == o0)
	bm.queue_free()

	# B.03: singles, attacker SLOWER than target — target already acted this
	# turn by the time the attacker's own turn comes, so After You fails.
	var slow := _make_mon("Slow", 200, 60, 60, 60, 60, 50)
	var fast := _make_mon("Fast", 200, 60, 60, 60, 60, 100)
	slow.add_move(after_you)
	fast.add_move(tackle)
	var failed := [false]
	var reordered := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "after_you_failed": failed[0] = true)
	bm2.turn_order_changed.connect(func(_m, _r): reordered[0] = true)
	bm2.start_battle(slow, fast)
	_chk("B.03 After You fails when target already acted", failed[0] == true)
	_chk("B.04 discriminator: no reorder fired on the failure path", reordered[0] == false)
	bm2.queue_free()


# ── Section C: Quash ──────────────────────────────────────────────────────────

func _test_quash() -> void:
	# [Turn-order-splice trio, item 13] C.01/C.02 CORRECTED: this fixture's
	# own assertion originally asserted the OLD "always push to the
	# absolute end" behavior (Gen7-). Re-derived from source this session
	# (BS_TryQuash, battle_script_commands.c L11762-11796): at this
	# project's GEN_LATEST=GEN_9 config, Quash's real algorithm only pushes
	# the target back PAST remaining battlers it's genuinely SLOWER than,
	# stopping the instant it reaches one it's faster than — it does NOT
	# unconditionally relocate to the very end. In THIS fixture, O0 (speed
	# 90) is already faster than every remaining battler (P1 speed 80, O1
	# speed 70) — a properly speed-sorted array already has O0 in the
	# correct position relative to both, so the corrected Gen8+ bubble
	# genuinely does nothing here (the same "as close to last as possible
	# without changing order relative to Pokémon it's faster than"
	# behavior real Gen8+ games document). See
	# turn_order_splice_test.gd's own dedicated item-13 section for a
	# fixture that DOES exercise genuine partial movement.
	var p0 := _make_mon("QP0", 300, 60, 60, 60, 60, 100)
	var p1 := _make_mon("QP1", 300, 60, 60, 60, 60, 80)
	var o0 := _make_mon("QO0", 300, 60, 60, 60, 60, 90)
	var o1 := _make_mon("QO1", 300, 60, 60, 60, 60, 70)
	var quash := _load_move(511)
	var tackle := _load_move(33)
	p0.add_move(quash)
	p1.add_move(tackle)
	o0.add_move(tackle)
	o1.add_move(tackle)

	var order := []
	var reorder_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, _d, _m, _amt): order.push_back(a))
	bm.turn_order_changed.connect(func(mover, reason): reorder_events.push_back([mover, reason]))

	var pp := BattleParty.new(); pp.members = [p0, p1]; pp.active_indices = [0, 1]
	var op := BattleParty.new(); op.members = [o0, o1]; op.active_indices = [0, 1]
	bm.queue_move_targeted(0, 0, 2)  # P0 uses Quash(idx 0) targeting O0 (combatant idx 2)
	bm.start_battle_doubles(pp, op)

	_chk("C.01 turn_order_changed still fires for O0/quash (the move " +
			"itself succeeds — Quash only fails if the target already acted)",
			reorder_events.size() >= 1 and reorder_events[0][0] == o0 and reorder_events[0][1] == "quash")
	_chk("C.02 CORRECTED: execution order stays P0, O0, P1, O1 — O0 is " +
			"already faster than everything remaining (P1, O1), so the real " +
			"Gen8+ bubble genuinely does nothing here (was incorrectly " +
			"asserted as 'pushed to the very end' before this session's fix)",
			order.size() >= 4 and order[0] == p0 and order[1] == o0
			and order[2] == p1 and order[3] == o1)
	bm.queue_free()

	# C.03: singles, attacker SLOWER than target — target already acted, fails.
	var slow := _make_mon("QSlow", 200, 60, 60, 60, 60, 50)
	var fast := _make_mon("QFast", 200, 60, 60, 60, 60, 100)
	slow.add_move(quash)
	fast.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "quash_failed": failed[0] = true)
	bm2.start_battle(slow, fast)
	_chk("C.03 Quash fails when target already acted", failed[0] == true)
	bm2.queue_free()


# ── Section D: Upper Hand ─────────────────────────────────────────────────────

func _test_upper_hand() -> void:
	# D.01: connects — target's chosen move (Quick Attack, priority 1) is in
	# range [1,3] and hasn't acted yet (Upper Hand's own priority 3 always
	# resolves first regardless of speed).
	var atk := _make_mon("UHAtk", 200, 80, 60, 60, 60, 50)
	var def := _make_mon("UHDef", 200, 60, 60, 60, 60, 100)  # faster, but priority loses to +3
	var upper_hand := _load_move(846)
	var quick_attack := _load_move(98)
	atk.add_move(upper_hand)
	def.add_move(quick_attack)

	var flinched := [false]
	var dealt := [0]
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm.secondary_applied.connect(func(_t, se): if se == MoveData.SE_FLINCH: flinched[0] = true)
	bm.move_executed.connect(func(a, _d, _m, amt): if a == atk: dealt[0] = amt)
	bm.start_battle(atk, def)
	_chk("D.01 Upper Hand connects (damage dealt) vs a priority-move target",
			dealt[0] > 0)
	_chk("D.02 Upper Hand's guaranteed flinch fired on connect", flinched[0] == true)
	bm.queue_free()

	# D.03: whiffs — target's chosen move (Tackle, priority 0) is out of
	# range, so the whole move fails (0 damage, no flinch).
	var atk2 := _make_mon("UHAtk2", 200, 80, 60, 60, 60, 50)
	var def2 := _make_mon("UHDef2", 200, 60, 60, 60, 60, 100)
	var tackle := _load_move(33)
	atk2.add_move(upper_hand)
	def2.add_move(tackle)
	var failed := [false]
	var dealt2 := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "upper_hand_failed": failed[0] = true)
	bm2.move_executed.connect(func(a, _d, _m, amt): if a == atk2: dealt2[0] = amt)
	bm2.start_battle(atk2, def2)
	_chk("D.03 Upper Hand fails vs a non-priority (Tackle) target", failed[0] == true)
	_chk("D.04 discriminator: 0 damage dealt on the failure path", dealt2[0] == 0)
	bm2.queue_free()


# ── Section E: Instruct ───────────────────────────────────────────────────────

func _test_instruct() -> void:
	# E.01/E.02: tgt is FASTER, so within turn 1 it acts first (Tackle,
	# setting its own last_move_used) and THEN atk's Instruct fires later
	# the SAME turn, forcing tgt to immediately re-use Tackle again — no PP
	# cost, and a second hit lands within that same turn.
	var atk := _make_mon("InAtk", 300, 60, 60, 60, 60, 50)
	var tgt := _make_mon("InTgt", 300, 60, 60, 60, 60, 100)
	var instruct := _load_move(652)
	var tackle := _load_move(33)
	atk.add_move(instruct)
	tgt.add_move(tackle)

	# PP is snapshotted at two precise, bounded moments (never after the
	# whole battle, which runs for several more turns beyond the one under
	# test — the documented whole-battle-aggregation pitfall) — right when
	# Instruct calls the re-used move (pp_at_call, AFTER tgt's own real
	# turn-1 deduction has already happened), and right when that SPECIFIC
	# re-used hit executes (pp_after_reuse) — equal means no extra PP cost.
	var called := []
	var pp_at_call := [-1]
	var pp_after_reuse := [-1]
	var hits_from_tgt := [0]
	var tackle_idx := tgt.moves.find(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_called.connect(func(_a, m):
		called.push_back(m)
		if pp_at_call[0] == -1:
			pp_at_call[0] = tgt.current_pp[tackle_idx])
	bm.move_executed.connect(func(a, _d, m, amt):
		if a == tgt and m == tackle and amt > 0:
			hits_from_tgt[0] += 1
			if hits_from_tgt[0] == 2 and pp_after_reuse[0] == -1:
				pp_after_reuse[0] = tgt.current_pp[tackle_idx])

	bm.start_battle(atk, tgt)

	_chk("E.01 Instruct called Tackle (tgt's own last move)",
			called.size() >= 1 and called[0] == tackle)
	_chk("E.02 tgt hit atk at least twice within the Instruct turn (Tackle + re-used Tackle)",
			hits_from_tgt[0] >= 2)
	_chk("E.03 the re-used Tackle did not cost extra PP",
			pp_at_call[0] >= 0 and pp_after_reuse[0] == pp_at_call[0])
	bm.queue_free()

	# E.04: fails when the target has no last_move_used yet (fresh battle,
	# attacker faster, target hasn't acted this turn or any prior turn).
	var atk2 := _make_mon("InAtk2", 200, 60, 60, 60, 60, 100)
	var tgt2 := _make_mon("InTgt2", 200, 60, 60, 60, 60, 50)
	atk2.add_move(instruct)
	tgt2.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "instruct_failed": failed[0] = true)
	bm2.start_battle(atk2, tgt2)
	_chk("E.04 Instruct fails with no last_move_used yet", failed[0] == true)
	bm2.queue_free()

	# E.05: exclusion — target's last move is Rollout (is_rollout), banned
	# from re-use via Instruct.
	var atk3 := _make_mon("InAtk3", 300, 60, 60, 60, 60, 60)
	var tgt3 := _make_mon("InTgt3", 300, 60, 60, 60, 60, 90)
	var rollout := _load_move(205)
	tgt3.add_move(rollout)
	atk3.add_move(instruct)
	var failed3 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason): if reason == "instruct_failed": failed3[0] = true)
	bm3.start_battle(atk3, tgt3)
	_chk("E.05 Instruct fails to re-trigger Rollout (is_rollout excluded)", failed3[0] == true)
	bm3.queue_free()


# ── Section F: Lash Out ───────────────────────────────────────────────────────

func _test_lash_out() -> void:
	# F.01 vs F.02: pairwise comparison. Opponent is FASTER and uses Scary
	# Face (lowers attacker's own SPEED — deliberately NOT Attack, so the
	# doubling is isolated from any confounding change to Lash Out's own
	# damage-relevant stat) before attacker's own Lash Out fires the SAME
	# turn — doubled. Baseline: opponent uses Tackle instead (no stat
	# change) — undoubled. Both forced roll+crit=false.
	var lash_out := _load_move(736)
	var scary_face := _load_move(184)
	var tackle := _load_move(33)

	var atk_a := _make_mon("LOAtkA", 300, 80, 60, 60, 60, 50)
	var opp_a := _make_mon("LOOppA", 300, 60, 60, 60, 60, 100)
	atk_a.add_move(lash_out)
	opp_a.add_move(scary_face)
	var dealt_a := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk_a and dealt_a[0] == 0: dealt_a[0] = amt)
	bm_a.start_battle(atk_a, opp_a)
	bm_a.queue_free()

	var atk_b := _make_mon("LOAtkB", 300, 80, 60, 60, 60, 50)
	var opp_b := _make_mon("LOOppB", 300, 60, 60, 60, 60, 100)
	atk_b.add_move(lash_out)
	opp_b.add_move(tackle)
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	_chk("F.01 Lash Out is doubled when the user's own stat was lowered this turn",
			_approx_scaled(dealt_a[0], dealt_b[0], 2))
	_chk("F.02 discriminator: baseline (no stat change) is the plain undoubled hit",
			dealt_b[0] > 0)

	# F.03: stat_lowered_this_turn does NOT persist to the next turn — a
	# 2-turn battle where the opponent (faster) lowers atk's Speed via Scary
	# Face only on turn 1 (queued explicitly), then reverts to Tackle turn 2
	# (its auto-selected moves[0]). atk's own Lash Out (its only move, used
	# every turn) is doubled turn 1, undoubled turn 2 once the per-turn
	# reset has run.
	var atk_c := _make_mon("LOAtkC", 300, 80, 60, 60, 60, 50)
	var opp_c := _make_mon("LOOppC", 300, 60, 60, 60, 60, 100)
	atk_c.add_move(lash_out)
	opp_c.add_move(tackle)
	opp_c.add_move(scary_face)
	var dmg_seq := []
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c.queue_move(1, 1)  # opponent's turn-1 action only: Scary Face (moves[1])
	bm_c.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_c and amt > 0:
			dmg_seq.push_back(amt))
	bm_c.start_battle(atk_c, opp_c)
	bm_c.queue_free()
	_chk("F.03 stat_lowered_this_turn does not persist: turn-1 doubled, turn-2 not",
			dmg_seq.size() >= 2 and _approx_scaled(dmg_seq[0], dmg_seq[1], 2))


# ── Section G: Retaliate ──────────────────────────────────────────────────────

func _test_retaliate() -> void:
	var retaliate := _load_move(514)
	var tackle := _load_move(33)

	# [D1 easy bundle] CORRECTED (2026-07-10): Retaliate's own decrement was
	# moved from `_phase_end_of_turn` to `_phase_priority_resolution` — the
	# real source site (shared with Stomping Tantrum's own timer), which
	# runs UNCONDITIONALLY at the start of every turn, including turn 1 of
	# a fresh battle. This means any pre-set `_retaliate_timer` value is
	# ALREADY decremented once before the battle's very first action even
	# resolves — so testing "timer==1 at check time" requires pre-setting
	# 2 (not 1), and "timer==2 at check time" requires pre-setting 3 (not
	# 2), accounting for that one guaranteed tick. See docs/decisions.md's
	# `[D1 easy bundle]` entry for the full timing-bug writeup.
	#
	# G.01 vs G.02: direct-state pairwise comparison — effective timer==1
	# doubles, timer==0 does not. Both forced roll+crit=false.
	var atk_a := _make_mon("RTAtkA", 300, 80, 60, 60, 60, 100)
	var opp_a := _make_mon("RTOppA", 300, 60, 60, 60, 60, 50)
	atk_a.add_move(retaliate)
	opp_a.add_move(tackle)
	var dealt_a := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a._retaliate_timer[0] = 2  # decrements to 1 before the first action checks it
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk_a and dealt_a[0] == 0: dealt_a[0] = amt)
	bm_a.start_battle(atk_a, opp_a)
	bm_a.queue_free()

	var atk_b := _make_mon("RTAtkB", 300, 80, 60, 60, 60, 100)
	var opp_b := _make_mon("RTOppB", 300, 60, 60, 60, 60, 50)
	atk_b.add_move(retaliate)
	opp_b.add_move(tackle)
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b._retaliate_timer[0] = 0
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	_chk("G.01 Retaliate is doubled when the side timer reads exactly 1 at check time",
			_approx_scaled(dealt_a[0], dealt_b[0], 2))
	_chk("G.02 discriminator: timer==0 is the plain undoubled hit", dealt_b[0] > 0)

	var atk_c := _make_mon("RTAtkC", 300, 80, 60, 60, 60, 100)
	var opp_c := _make_mon("RTOppC", 300, 60, 60, 60, 60, 50)
	atk_c.add_move(retaliate)
	opp_c.add_move(tackle)
	var dealt_c := [0]
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c._retaliate_timer[0] = 3  # decrements to 2 before the first check — not doubled
	bm_c.move_executed.connect(func(a, _d, _m, amt): if a == atk_c and dealt_c[0] == 0: dealt_c[0] = amt)
	bm_c.start_battle(atk_c, opp_c)
	bm_c.queue_free()
	_chk("G.03 discriminator: effective timer==2 is NOT doubled either",
			dealt_c[0] == dealt_b[0])

	# G.04: integration — a real faint sets the FAINTED mon's own side's
	# timer to 2, DURING turn 1 (after that turn's own start-of-turn
	# decrement already ran, since the faint happens later in the phase
	# sequence). With the corrected decrement site, turn 2's own start-of-
	# turn tick fires BEFORE mon2's first action (2->1), so mon2's very
	# FIRST action back is ALREADY doubled — confirmed via direct tracing,
	# a genuinely different (and now source-accurate) sequence from the
	# pre-fix behavior this test originally documented. Turn 3 decrements
	# again (1->0, undoubled).
	var mon1 := _make_mon("RTMon1", 20, 60, 20, 60, 20, 40)
	var mon2 := _make_mon("RTMon2", 400, 80, 200, 60, 200, 90)
	var opp := _make_mon("RTOpp", 400, 80, 60, 60, 60, 200)
	mon1.add_move(tackle)
	mon2.add_move(retaliate)
	opp.add_move(tackle)

	var timer_snapshots := []
	var faint_events := []
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.pokemon_fainted.connect(func(p): faint_events.push_back(p))
	bm4.move_executed.connect(func(a, _d, _m, amt):
		if a == mon2:
			timer_snapshots.push_back(amt))

	var pp4 := BattleParty.new(); pp4.members = [mon1, mon2]; pp4.active_index = 0
	bm4.start_battle_with_parties(pp4, BattleParty.single(opp))

	_chk("G.05 mon1 fainted (integration setup)", faint_events.any(func(p): return p == mon1))
	_chk("G.06 mon2's turn-2 Retaliate (its FIRST turn back) is already doubled with the corrected timing",
			timer_snapshots.size() >= 2 and _approx_scaled(timer_snapshots[0], timer_snapshots[1], 2))
	_chk("G.07 mon2's turn-3 Retaliate (timer=0) reverts to the plain undoubled value",
			timer_snapshots.size() >= 2 and timer_snapshots[1] > 0)
	bm4.queue_free()


# ── Section H: Rage Fist ──────────────────────────────────────────────────────

func _test_rage_fist() -> void:
	var rage_fist := _load_move(815)
	var tackle := _load_move(33)

	# H.01 vs H.02: direct-state pairwise comparison — 3 prior hits taken
	# vs 0. Both forced roll+crit=false.
	var atk_a := _make_mon("RFAtkA", 300, 60, 60, 60, 60, 100)
	var opp_a := _make_mon("RFOppA", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_a.add_move(rage_fist)
	opp_a.add_move(tackle)
	atk_a.times_hit = 3
	var dealt_a := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk_a and dealt_a[0] == 0: dealt_a[0] = amt)
	bm_a.start_battle(atk_a, opp_a)
	bm_a.queue_free()

	var atk_b := _make_mon("RFAtkB", 300, 60, 60, 60, 60, 100)
	var opp_b := _make_mon("RFOppB", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_b.add_move(rage_fist)
	opp_b.add_move(tackle)
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	_chk("H.01 Rage Fist scales up with prior hits taken (3 hits > 0 hits)",
			dealt_a[0] > dealt_b[0])

	# H.03: cap — times_hit=6 (power exactly at the 350 cap) deals the same
	# damage as times_hit=20 (well past the cap).
	var atk_c := _make_mon("RFAtkC", 300, 60, 60, 60, 60, 100)
	var opp_c := _make_mon("RFOppC", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_c.add_move(rage_fist)
	opp_c.add_move(tackle)
	atk_c.times_hit = 6
	var dealt_c := [0]
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c.move_executed.connect(func(a, _d, _m, amt): if a == atk_c and dealt_c[0] == 0: dealt_c[0] = amt)
	bm_c.start_battle(atk_c, opp_c)
	bm_c.queue_free()

	var atk_d := _make_mon("RFAtkD", 300, 60, 60, 60, 60, 100)
	var opp_d := _make_mon("RFOppD", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_WATER)
	atk_d.add_move(rage_fist)
	opp_d.add_move(tackle)
	atk_d.times_hit = 20
	var dealt_d := [0]
	var bm_d := _make_bm()
	bm_d._force_hit = true
	bm_d._force_roll = 100
	bm_d._force_crit = false
	bm_d.move_executed.connect(func(a, _d, _m, amt): if a == atk_d and dealt_d[0] == 0: dealt_d[0] = amt)
	bm_d.start_battle(atk_d, opp_d)
	bm_d.queue_free()
	_chk("H.02 Rage Fist power caps at 350 (times_hit=6 == times_hit=20 damage)",
			dealt_c[0] == dealt_d[0])

	# H.04: times_hit actually increments when the attacker takes a hit.
	var mon_e := _make_mon("RFMonE", 300, 60, 60, 60, 60, 50)
	var opp_e := _make_mon("RFOppE", 300, 60, 60, 60, 60, 100)
	mon_e.add_move(tackle)
	opp_e.add_move(tackle)
	var bm_e := _make_bm()
	bm_e._force_hit = true
	bm_e.start_battle(mon_e, opp_e)
	bm_e.queue_free()
	_chk("H.03 times_hit incremented from taking a real hit", mon_e.times_hit >= 1)

	# H.05: switch-persistence — _clear_volatiles (the function every real
	# switch-out/faint calls) deliberately does NOT reset times_hit.
	var mon_f := _make_mon("RFMonF", 200, 60, 60, 60, 60, 60)
	mon_f.times_hit = 7
	var bm_f := _make_bm()
	bm_f._clear_volatiles(mon_f)
	_chk("H.04 times_hit survives _clear_volatiles (switch-out/faint), unlike every other volatile",
			mon_f.times_hit == 7)
	bm_f.queue_free()


# ── Section I: Echoed Voice ────────────────────────────────────────────────────

func _test_echoed_voice() -> void:
	var echoed_voice := _load_move(497)
	var tackle := _load_move(33)

	# I.01 vs I.02: direct-state pairwise comparison — counter=2 vs counter=0.
	var atk_a := _make_mon("EVAtkA", 300, 60, 60, 80, 60, 100)
	var opp_a := _make_mon("EVOppA", 300, 60, 60, 60, 60, 50)
	atk_a.add_move(echoed_voice)
	opp_a.add_move(tackle)
	var dealt_a := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a._echoed_voice_counter = 2
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk_a and dealt_a[0] == 0: dealt_a[0] = amt)
	bm_a.start_battle(atk_a, opp_a)
	bm_a.queue_free()

	var atk_b := _make_mon("EVAtkB", 300, 60, 60, 80, 60, 100)
	var opp_b := _make_mon("EVOppB", 300, 60, 60, 60, 60, 50)
	atk_b.add_move(echoed_voice)
	opp_b.add_move(tackle)
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	_chk("I.01 Echoed Voice scales with the field-wide counter (counter=2 gives 3x base)",
			_approx_scaled(dealt_a[0], dealt_b[0], 3, 8))

	# I.03: integration — 3 consecutive Echoed-Voice-only turns ramp the
	# counter 0->1->2, each turn's damage strictly greater than the last.
	var atk_c := _make_mon("EVAtkC", 400, 60, 60, 80, 60, 100)
	var opp_c := _make_mon("EVOppC", 400, 60, 60, 60, 60, 50)
	atk_c.add_move(echoed_voice)
	opp_c.add_move(tackle)
	var dmg_seq := []
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_c and amt > 0:
			dmg_seq.push_back(amt))
	bm_c.start_battle(atk_c, opp_c)
	bm_c.queue_free()
	_chk("I.02 consecutive Echoed Voice turns strictly ramp up damage (counter incrementing)",
			dmg_seq.size() >= 3 and dmg_seq[0] < dmg_seq[1] and dmg_seq[1] < dmg_seq[2])

	# I.04: a skipped turn (Tackle used instead) resets the counter to 0.
	var mon_d := _make_mon("EVMonD", 200, 60, 60, 60, 60, 60)
	var bm_d := _make_bm()
	bm_d._echoed_voice_counter = 3
	bm_d._echoed_voice_used_this_turn = false  # not used this turn -> resets
	bm_d._phase_end_of_turn()
	_chk("I.03 counter resets to 0 the instant a turn passes without use",
			bm_d._echoed_voice_counter == 0)
	bm_d.queue_free()
