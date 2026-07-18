extends Node

# M17n-3 test suite — Turn-order/priority modifiers (docs/m17n_recon.md Group 3).
# Continues the m17n<N> numeral-suffix naming convention established in [M17n-1].
#
# Scope: 6 abilities, per docs/decisions.md [M17n-3]:
#   Prankster (158, +1 priority for status moves), Gale Wings (177, +1 priority for
#     Flying-type moves at full HP), Triage (205, +3 priority for healing_move-flagged
#     moves) — all extend the turn-order priority-bracket computation in
#     BattleManager._phase_priority_resolution via new AbilityManager.move_priority_bonus.
#   Quick Draw (259, 30% chance to act first in a tied bracket, non-status moves only)
#     and Stall/Mycelium Might (100/298, always act last in a tied bracket — Mycelium
#     Might ONLY when its own chosen move is status-category, a source-verified nuance
#     NOT shared with Stall's unconditional shape) — new AbilityManager.
#     quick_draw_activates/has_slow_turn_order_effect, checked BEFORE the speed
#     tiebreak, precomputed once per battler per turn (never re-rolled mid-sort).
#   Mycelium Might's second half: acts as a Mold-Breaker-type ability toward an
#     opposing battler while its own current move is status-category — new
#     `attacker_move` param threaded through effective_ability_id / try_apply_status /
#     try_apply_confusion / try_secondary_effect.
#
# Cross-tier composition, confirmed and (in one case) fixed this tier:
#   - Trick Room ([M16d]): priority-bracket comparison (now including ability bonuses)
#     still runs strictly BEFORE Trick Room's speed-tiebreak inversion — unaffected.
#   - Pursuit ([M16e]): structurally disjoint (switch-vs-move handling, resolved
#     before the tied-priority-bracket branch is ever reached) — no dedicated test
#     needed, same reasoning the M16 Review already established for Trick-Room×Pursuit.
#   - M17k's blocks_priority_move: a REAL, source-confirmed gap was found and fixed —
#     source's CancelerPriorityBlock computes priority via GetChosenMovePriority, the
#     SAME ability-boosted function feeding turn-order, not the move's raw data
#     priority. Unreachable at [M17k]'s own implementation time (no ability could
#     alter priority yet); now fixed via the same move_priority_bonus helper.
#
# Follow-up (same day): a Prankster-boosted status move fails against a Dark-type
# target (Gen 7+, B_PRANKSTER_DARK_TYPES = GEN_LATEST) — source: BlocksPrankster
# (battle_util.c L9234-9252), gated on the exact same (status move, Prankster ability)
# condition as move_priority_bonus's own Prankster branch, no separate stored flag
# needed. New AbilityManager.blocks_prankster_move, wired into _phase_move_execution
# right alongside the existing type-immunity check for foe-targeting status moves.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot (move_executed ordering / secondary_applied), not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: Normal-type combatants throughout except
#     Flying (Gale Wings' own move-type gate) and the Limber/paralysis-immunity test.
#   - Every RNG input forced deterministic (_force_hit / _force_quick_draw_roll) in any
#     test where the outcome must be unambiguous.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_move_priority_bonus_unit()
	_test_section_3_quick_draw_unit()
	_test_section_4_slow_turn_order_unit()
	_test_section_5_prankster_full_battle()
	_test_section_6_gale_wings_full_battle()
	_test_section_7_triage_full_battle()
	_test_section_8_stall_full_battle()
	_test_section_9_quick_draw_full_battle()
	_test_section_10_mycelium_might_turn_order_full_battle()
	_test_section_11_mycelium_might_ability_ignore_full_battle()
	_test_section_12_trick_room_composition_full_battle()
	_test_section_13_stall_overrides_trick_room_full_battle()
	_test_section_14_m17k_dazzling_composition()
	_test_section_15_neutralizing_gas_suppression()
	_test_section_16_negative_control()
	_test_section_17_prankster_dark_type_immunity()

	var total := _pass + _fail
	print("m17n3_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var stall := _load_ability(100)
	_chk("S1.01 Stall id=100, NOT breakable (self-check, no attacker concept)",
			stall.ability_id == 100 and not stall.breakable)

	var prankster := _load_ability(158)
	_chk("S1.02 Prankster id=158, NOT breakable", prankster.ability_id == 158 and not prankster.breakable)

	var gale_wings := _load_ability(177)
	_chk("S1.03 Gale Wings id=177, NOT breakable", gale_wings.ability_id == 177 and not gale_wings.breakable)

	var triage := _load_ability(205)
	_chk("S1.04 Triage id=205, NOT breakable", triage.ability_id == 205 and not triage.breakable)

	var quick_draw := _load_ability(259)
	_chk("S1.05 Quick Draw id=259, NOT breakable", quick_draw.ability_id == 259 and not quick_draw.breakable)

	var mycelium := _load_ability(298)
	_chk("S1.06 Mycelium Might id=298, NOT breakable itself (its bypass role is separate)",
			mycelium.ability_id == 298 and not mycelium.breakable)

	# The dormant `healing_move` MoveData flag, wired for the first time this tier —
	# Recover/Slack Off/Heal Order carry it in this project's roster (confirmed via
	# source's own healingMove-flagged move list).
	# [M21.5 Bucket 1 correction, 2026-07-16]: this test's own original S1.10
	# assertion ("drain moves like Giga Drain do NOT carry it") was wrong — source's
	# real `.healingMove` field on the EFFECT_ABSORB family (Absorb/Mega Drain/Giga
	# Drain/Drain Punch/etc.) is `B_HEAL_BLOCKING >= GEN_6`, which resolves TRUE at
	# this project's own GEN_LATEST=GEN_9 config, exactly like the 8 absorb moves
	# `[M19-bucket2]` correctly flagged TRUE for the same reason. Giga Drain/Absorb/
	# Mega Drain/Drain Punch were implemented before that generalization existed and
	# were never retroactively swept — `[M21.5 Bucket 1]`'s full-roster
	# `healingMove` cross-reference caught the gap and fixed it in `gen_moves.py`.
	var recover := _load_move(105)
	_chk("S1.07 Recover carries healing_move=true", recover.healing_move)
	var slack_off := _load_move(303)
	_chk("S1.08 Slack Off carries healing_move=true", slack_off.healing_move)
	var heal_order := _load_move(456)
	_chk("S1.09 Heal Order carries healing_move=true", heal_order.healing_move)
	var giga_drain := _load_move(202)
	_chk("S1.10 Giga Drain DOES carry healing_move=true (corrected — B_HEAL_BLOCKING" +
			" >= GEN_6 resolves true at this project's config, matching the other" +
			" EFFECT_ABSORB moves)", giga_drain.healing_move)


# ── Section 2: move_priority_bonus — direct unit tests ───────────────────────

func _test_section_2_move_priority_bonus_unit() -> void:
	var gale_wings := _load_ability(177)
	var prankster := _load_ability(158)
	var triage := _load_ability(205)
	var wing_attack := _load_move(17)     # Flying/Physical
	var tackle := _load_move(33)          # Normal/Physical
	var growl := _load_move(45)           # Normal/Status, not healing
	var recover := _load_move(105)        # Normal/Status, healing_move=true

	var gw_mon := _make_mon("GWUnit", [TypeChart.TYPE_FLYING])
	gw_mon.ability = gale_wings
	_chk("S2.01 Gale Wings: +1 for a Flying move at full HP",
			AbilityManager.move_priority_bonus(gw_mon, wing_attack) == 1)
	_chk("S2.02 Gale Wings: +0 for a non-Flying move even at full HP",
			AbilityManager.move_priority_bonus(gw_mon, tackle) == 0)
	gw_mon.current_hp = gw_mon.max_hp - 1
	_chk("S2.03 Gale Wings: +0 for a Flying move NOT at full HP (the B_GALE_WINGS " +
			"GEN_LATEST full-HP gate)",
			AbilityManager.move_priority_bonus(gw_mon, wing_attack) == 0)

	var pr_mon := _make_mon("PranksterUnit", [TypeChart.TYPE_NORMAL])
	pr_mon.ability = prankster
	_chk("S2.04 Prankster: +1 for a status-category move",
			AbilityManager.move_priority_bonus(pr_mon, growl) == 1)
	_chk("S2.05 Prankster: +0 for a damaging move",
			AbilityManager.move_priority_bonus(pr_mon, tackle) == 0)

	var tr_mon := _make_mon("TriageUnit", [TypeChart.TYPE_NORMAL])
	tr_mon.ability = triage
	_chk("S2.06 Triage: +3 for a healing_move-flagged move",
			AbilityManager.move_priority_bonus(tr_mon, recover) == 3)
	_chk("S2.07 Triage: +0 for an ordinary status move WITHOUT healing_move " +
			"(narrower than Prankster's blanket status gate)",
			AbilityManager.move_priority_bonus(tr_mon, growl) == 0)

	_chk("S2.08 null move -> 0 (defensive guard)",
			AbilityManager.move_priority_bonus(pr_mon, null) == 0)
	_chk("S2.09 null mon -> 0 (defensive guard, mirrors blocks_priority_move's " +
			"null-attacker sanity case)",
			AbilityManager.move_priority_bonus(null, tackle) == 0)


# ── Section 3: quick_draw_activates — direct unit tests ──────────────────────

func _test_section_3_quick_draw_unit() -> void:
	var quick_draw := _load_ability(259)
	var tackle := _load_move(33)
	var growl := _load_move(45)

	var qd_mon := _make_mon("QDUnit", [TypeChart.TYPE_NORMAL])
	qd_mon.ability = quick_draw
	_chk("S3.01 Quick Draw activates when forced_roll=true on a damaging move",
			AbilityManager.quick_draw_activates(qd_mon, tackle, false, true))
	_chk("S3.02 Quick Draw does NOT activate when forced_roll=false",
			not AbilityManager.quick_draw_activates(qd_mon, tackle, false, false))
	_chk("S3.03 Quick Draw does NOT activate on a status move even with forced_roll=true " +
			"(source: !IsBattleMoveStatus gate)",
			not AbilityManager.quick_draw_activates(qd_mon, growl, false, true))

	var plain_mon := _make_mon("QDPlainUnit", [TypeChart.TYPE_NORMAL])
	_chk("S3.04 a non-Quick-Draw holder never activates it, even with forced_roll=true",
			not AbilityManager.quick_draw_activates(plain_mon, tackle, false, true))


# ── Section 4: has_slow_turn_order_effect — direct unit tests ────────────────

func _test_section_4_slow_turn_order_unit() -> void:
	var stall := _load_ability(100)
	var mycelium := _load_ability(298)
	var tackle := _load_move(33)   # damaging
	var growl := _load_move(45)    # status

	var stall_mon := _make_mon("StallUnit", [TypeChart.TYPE_NORMAL])
	stall_mon.ability = stall
	_chk("S4.01 Stall: always last, even for a damaging move (unconditional)",
			AbilityManager.has_slow_turn_order_effect(stall_mon, tackle))
	_chk("S4.02 Stall: always last for a status move too",
			AbilityManager.has_slow_turn_order_effect(stall_mon, growl))

	var mm_mon := _make_mon("MyceliumUnit", [TypeChart.TYPE_NORMAL])
	mm_mon.ability = mycelium
	_chk("S4.03 Mycelium Might: last when its OWN chosen move is status",
			AbilityManager.has_slow_turn_order_effect(mm_mon, growl))
	_chk("S4.04 Mycelium Might: NOT last when its own chosen move is a damaging move " +
			"(source-verified nuance NOT shared with Stall's unconditional shape)",
			not AbilityManager.has_slow_turn_order_effect(mm_mon, tackle))


# ── Section 5: Prankster — full-battle turn-order confirmation ───────────────

func _test_section_5_prankster_full_battle() -> void:
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var prankster := _load_ability(158)

	var pr := _make_mon("PranksterBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	pr.ability = prankster
	pr.add_move(growl)
	var opp := _make_mon("PranksterOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(pr), BattleParty.single(opp))

	_chk("S5.01 Prankster's holder (normally slower) acts FIRST with a status move",
			not events.is_empty() and events[0][0] == pr)

	bm.queue_free()

	# Discriminator: same Prankster holder, but its move this turn is DAMAGING —
	# no bonus applies, normal (faster-first) order.
	var pr2 := _make_mon("PranksterBattle2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	pr2.ability = prankster
	pr2.add_move(tackle)
	var opp2 := _make_mon("PranksterOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(pr2), BattleParty.single(opp2))

	_chk("S5.02 discriminator: with a DAMAGING move, Prankster grants no bonus — " +
			"the naturally faster opponent acts first",
			not events2.is_empty() and events2[0][0] == opp2)

	bm2.queue_free()


# ── Section 6: Gale Wings — full-battle turn-order confirmation ──────────────

func _test_section_6_gale_wings_full_battle() -> void:
	var wing_attack := _load_move(17)
	var tackle := _load_move(33)
	var gale_wings := _load_ability(177)

	var gw := _make_mon("GaleWingsBattle", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 40)
	gw.ability = gale_wings
	gw.add_move(wing_attack)
	var opp := _make_mon("GaleWingsOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(gw), BattleParty.single(opp))

	_chk("S6.01 Gale Wings' holder (normally slower, full HP) acts FIRST with a Flying move",
			not events.is_empty() and events[0][0] == gw)

	bm.queue_free()

	# Discriminator: same holder, NOT at full HP — the B_GALE_WINGS GEN_LATEST gate
	# means no bonus applies, normal (faster-first) order.
	var gw2 := _make_mon("GaleWingsBattle2", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 40)
	gw2.ability = gale_wings
	gw2.add_move(wing_attack)
	gw2.current_hp = gw2.max_hp - 1
	var opp2 := _make_mon("GaleWingsOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(gw2), BattleParty.single(opp2))

	_chk("S6.02 discriminator: NOT at full HP, Gale Wings grants no bonus — the " +
			"naturally faster opponent acts first",
			not events2.is_empty() and events2[0][0] == opp2)

	bm2.queue_free()


# ── Section 7: Triage — full-battle turn-order confirmation ──────────────────

func _test_section_7_triage_full_battle() -> void:
	var recover := _load_move(105)
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var triage := _load_ability(205)

	var tr := _make_mon("TriageBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	tr.ability = triage
	tr.add_move(recover)
	var opp := _make_mon("TriageOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(tr), BattleParty.single(opp))

	_chk("S7.01 Triage's holder (normally slower) acts FIRST using Recover (+3 priority)",
			not events.is_empty() and events[0][0] == tr)

	bm.queue_free()

	# Discriminator: same holder using an ordinary status move (Growl, no healing_move
	# flag) — Triage grants no bonus here (narrower than Prankster), normal order.
	var tr2 := _make_mon("TriageBattle2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	tr2.ability = triage
	tr2.add_move(growl)
	var opp2 := _make_mon("TriageOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(tr2), BattleParty.single(opp2))

	_chk("S7.02 discriminator: Growl (status, but not healing_move) grants no Triage " +
			"bonus — the naturally faster opponent acts first",
			not events2.is_empty() and events2[0][0] == opp2)

	bm2.queue_free()


# ── Section 8: Stall — full-battle turn-order confirmation ───────────────────

func _test_section_8_stall_full_battle() -> void:
	var tackle := _load_move(33)
	var stall := _load_ability(100)

	# Stall holder is the FASTER combatant — without Stall it would act first.
	var st := _make_mon("StallBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	st.ability = stall
	st.add_move(tackle)
	var opp := _make_mon("StallOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(st), BattleParty.single(opp))

	_chk("S8.01 Stall's holder (normally FASTER) still acts LAST, even with an " +
			"ordinary damaging move — unconditional, unlike Mycelium Might",
			not events.is_empty() and events[0][0] == opp)

	bm.queue_free()


# ── Section 9: Quick Draw — full-battle turn-order confirmation ──────────────

func _test_section_9_quick_draw_full_battle() -> void:
	var tackle := _load_move(33)
	var growl := _load_move(45)
	var quick_draw := _load_ability(259)

	# Quick Draw holder is SLOWER; forced roll = true -> acts first anyway.
	var qd := _make_mon("QuickDrawBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	qd.ability = quick_draw
	qd.add_move(tackle)
	var opp := _make_mon("QuickDrawOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_quick_draw_roll = true
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(qd), BattleParty.single(opp))

	_chk("S9.01 Quick Draw (forced roll=true) makes the slower holder act FIRST",
			not events.is_empty() and events[0][0] == qd)

	bm.queue_free()

	# Discriminator 1: forced roll = false -> normal (faster-first) order.
	var qd2 := _make_mon("QuickDrawBattle2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	qd2.ability = quick_draw
	qd2.add_move(tackle)
	var opp2 := _make_mon("QuickDrawOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_quick_draw_roll = false
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(qd2), BattleParty.single(opp2))

	_chk("S9.02 discriminator: forced roll=false -> normal order, faster opponent first",
			not events2.is_empty() and events2[0][0] == opp2)

	bm2.queue_free()

	# Discriminator 2: forced roll = true but the holder's chosen move is STATUS ->
	# Quick Draw's category gate blocks it, normal order applies.
	var qd3 := _make_mon("QuickDrawBattle3", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	qd3.ability = quick_draw
	qd3.add_move(growl)
	var opp3 := _make_mon("QuickDrawOpp3", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp3.add_move(tackle)

	var events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_quick_draw_roll = true
	bm3.move_executed.connect(func(a, d, m, dmg): events3.push_back([a, d, m, dmg]))
	bm3.start_battle_with_parties(BattleParty.single(qd3), BattleParty.single(opp3))

	_chk("S9.03 discriminator: a status-move Quick Draw holder gets no bonus even " +
			"with forced roll=true — normal order, faster opponent first",
			not events3.is_empty() and events3[0][0] == opp3)

	bm3.queue_free()


# ── Section 10: Mycelium Might — turn-order-last, gated on its own move category ──

func _test_section_10_mycelium_might_turn_order_full_battle() -> void:
	var thunder_wave := _load_move(86)   # status
	var tackle := _load_move(33)         # damaging
	var mycelium := _load_ability(298)

	# Mycelium Might holder is the FASTER combatant; its chosen move is STATUS ->
	# should still act LAST.
	var mm := _make_mon("MyceliumBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	mm.ability = mycelium
	mm.add_move(thunder_wave)
	var opp := _make_mon("MyceliumOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(mm), BattleParty.single(opp))

	_chk("S10.01 Mycelium Might's holder (normally FASTER) acts LAST when its own " +
			"chosen move is status-category",
			not events.is_empty() and events[0][0] == opp)

	bm.queue_free()

	# Discriminator: same holder, but its chosen move THIS TURN is DAMAGING — the
	# slow-effect does NOT apply (source-verified nuance vs. Stall's unconditional
	# shape) — normal (faster-first) order.
	var mm2 := _make_mon("MyceliumBattle2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	mm2.ability = mycelium
	mm2.add_move(tackle)
	var opp2 := _make_mon("MyceliumOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp2.add_move(tackle)

	var events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_executed.connect(func(a, d, m, dmg): events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(mm2), BattleParty.single(opp2))

	_chk("S10.02 discriminator: with a DAMAGING move, Mycelium Might's slow-effect " +
			"does NOT apply — the naturally faster holder acts first",
			not events2.is_empty() and events2[0][0] == mm2)

	bm2.queue_free()


# ── Section 11: Mycelium Might — ability-ignore (Mold-Breaker-type) half ─────

func _test_section_11_mycelium_might_ability_ignore_full_battle() -> void:
	var thunder_wave := _load_move(86)
	var tackle := _load_move(33)
	var mycelium := _load_ability(298)
	var limber := _load_ability(7)

	# Mycelium Might holder uses Thunder Wave (status) against a Limber holder —
	# should bypass Limber's paralysis immunity, same as Mold Breaker would.
	var mm := _make_mon("MyceliumAI", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	mm.ability = mycelium
	mm.add_move(thunder_wave)
	var lb := _make_mon("LimberAI", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	lb.ability = limber
	lb.add_move(tackle)

	var applied_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.secondary_applied.connect(func(target, se): applied_events.push_back([target, se]))
	bm.start_battle_with_parties(BattleParty.single(mm), BattleParty.single(lb))

	_chk("S11.01 Mycelium Might's Thunder Wave bypasses Limber's paralysis immunity",
			applied_events.any(func(e): return e[0] == lb and e[1] == MoveData.SE_PARALYSIS))

	bm.queue_free()

	# Discriminator: an ordinary (non-Mycelium-Might) attacker's Thunder Wave does NOT
	# bypass the same Limber holder.
	var plain := _make_mon("PlainAI", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	plain.add_move(thunder_wave)
	var lb2 := _make_mon("LimberAI2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	lb2.ability = limber
	lb2.add_move(tackle)

	var applied_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2.secondary_applied.connect(func(target, se): applied_events2.push_back([target, se]))
	bm2.start_battle_with_parties(BattleParty.single(plain), BattleParty.single(lb2))

	_chk("S11.02 discriminator: a plain attacker's Thunder Wave does NOT bypass Limber",
			applied_events2.is_empty())

	bm2.queue_free()


# ── Section 12: Trick Room composition — priority bracket unaffected ────────

func _test_section_12_trick_room_composition_full_battle() -> void:
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var prankster := _load_ability(158)

	# Prankster holder is naturally FASTER (Trick Room alone would flip this to make
	# it act LAST within a tied priority bracket) — but its status move's +1 priority
	# puts it in a HIGHER bracket than the opponent's Tackle (priority 0), so it must
	# still act first regardless of Trick Room's speed-tiebreak inversion.
	var pr := _make_mon("TRPranksterBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	pr.ability = prankster
	pr.add_move(growl)
	var opp := _make_mon("TRPranksterOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.trick_room_turns = 5
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(pr), BattleParty.single(opp))

	_chk("S12.01 under Trick Room, Prankster's +1-priority status move still wins the " +
			"priority BRACKET comparison, unaffected by Trick Room's speed-tiebreak " +
			"inversion (mirrors [M16d]'s own priority-overrides-Trick-Room test)",
			not events.is_empty() and events[0][0] == pr)

	bm.queue_free()


# ── Section 13: Stall overrides Trick Room's tiebreak preference too ────────

func _test_section_13_stall_overrides_trick_room_full_battle() -> void:
	var tackle := _load_move(33)
	var stall := _load_ability(100)

	# Stall holder is SLOWER — under Trick Room alone (no Stall), the slower mon would
	# normally act FIRST (Trick Room inverts the speed tiebreak). Stall must still
	# force it to act LAST, proving the quick/slow-effect check runs strictly BEFORE
	# (and overrides) the speed/Trick-Room comparison, not just plain speed order.
	var st := _make_mon("TRStallBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	st.ability = stall
	st.add_move(tackle)
	var opp := _make_mon("TRStallOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	opp.add_move(tackle)

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.trick_room_turns = 5
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(st), BattleParty.single(opp))

	_chk("S13.01 under Trick Room (which would favor the slower Stall holder), Stall " +
			"still forces its holder to act LAST",
			not events.is_empty() and events[0][0] == opp)

	bm.queue_free()


# ── Section 14: M17k composition — a real gap found and fixed this tier ─────

func _test_section_14_m17k_dazzling_composition() -> void:
	var growl := _load_move(45)     # priority 0, status
	var tackle := _load_move(33)    # priority 0, damaging
	var prankster := _load_ability(158)
	var stall := _load_ability(100)
	var dazzling := _load_ability(219)

	var pr := _make_mon("M17kPrankster", [TypeChart.TYPE_NORMAL])
	pr.ability = prankster
	var dz := _make_mon("M17kDazzling", [TypeChart.TYPE_NORMAL])
	dz.ability = dazzling

	_chk("S14.01 a Prankster-boosted status move (effective priority 1) IS blocked by " +
			"Dazzling — source computes CancelerPriorityBlock's priority via the same " +
			"ability-boosted GetChosenMovePriority function feeding turn order, not the " +
			"move's raw data priority (a real gap found and fixed this tier)",
			AbilityManager.blocks_priority_move(dz, null, pr, growl))
	_chk("S14.02 sanity: the SAME move's raw priority (0) would NOT be blocked on its " +
			"own — confirming S14.01 is really testing the ability-boosted computation",
			growl.priority <= 0)

	var st := _make_mon("M17kStall", [TypeChart.TYPE_NORMAL])
	st.ability = stall
	_chk("S14.03 Stall does NOT phantom-trigger a priority block — it has no effect " +
			"on GetBattleMovePriority's return value at all, only the same-bracket " +
			"tiebreak, so a Stall holder's ordinary Tackle is unaffected",
			not AbilityManager.blocks_priority_move(dz, null, st, tackle))


# ── Section 15: Neutralizing Gas suppression ─────────────────────────────────

func _test_section_15_neutralizing_gas_suppression() -> void:
	var growl := _load_move(45)
	var tackle := _load_move(33)
	var prankster := _load_ability(158)
	var stall := _load_ability(100)
	var quick_draw := _load_ability(259)
	var mycelium := _load_ability(298)

	var pr := _make_mon("NGPranksterN3", [TypeChart.TYPE_NORMAL])
	pr.ability = prankster
	_chk("S15.01 Neutralizing Gas suppresses Prankster's priority bonus",
			AbilityManager.move_priority_bonus(pr, growl, true) == 0)

	var st := _make_mon("NGStallN3", [TypeChart.TYPE_NORMAL])
	st.ability = stall
	_chk("S15.02 Neutralizing Gas suppresses Stall's slow-effect",
			not AbilityManager.has_slow_turn_order_effect(st, tackle, true))

	var qd := _make_mon("NGQuickDrawN3", [TypeChart.TYPE_NORMAL])
	qd.ability = quick_draw
	_chk("S15.03 Neutralizing Gas suppresses Quick Draw (forced_roll=true would " +
			"otherwise guarantee activation)",
			not AbilityManager.quick_draw_activates(qd, tackle, true, true))

	var mm := _make_mon("NGMyceliumN3", [TypeChart.TYPE_NORMAL])
	mm.ability = mycelium
	_chk("S15.04 Neutralizing Gas suppresses Mycelium Might's slow-effect",
			not AbilityManager.has_slow_turn_order_effect(mm, growl, true))


# ── Section 16: Negative control ─────────────────────────────────────────────

func _test_section_16_negative_control() -> void:
	var tackle := _load_move(33)
	var growl := _load_move(45)

	var plain := _make_mon("PlainN3", [TypeChart.TYPE_NORMAL])
	_chk("S16.01 a plain Pokémon with no ability gets no priority bonus (damaging move)",
			AbilityManager.move_priority_bonus(plain, tackle) == 0)
	_chk("S16.02 a plain Pokémon with no ability gets no priority bonus (status move)",
			AbilityManager.move_priority_bonus(plain, growl) == 0)
	_chk("S16.03 a plain Pokémon never activates Quick Draw",
			not AbilityManager.quick_draw_activates(plain, tackle, false, true))
	_chk("S16.04 a plain Pokémon never gets the slow turn-order effect",
			not AbilityManager.has_slow_turn_order_effect(plain, growl))


# ── Section 17: Prankster-boosted status moves fail against a Dark-type target ──
# (Gen 7+ follow-up finding, source: BlocksPrankster, battle_util.c L9234-9252)

func _test_section_17_prankster_dark_type_immunity() -> void:
	var prankster := _load_ability(158)
	var growl := _load_move(45)   # status, foe-targeting
	var tackle := _load_move(33)  # damaging

	var pr := _make_mon("PDarkUnit", [TypeChart.TYPE_NORMAL])
	pr.ability = prankster
	var dark_def := _make_mon("PDarkTarget", [TypeChart.TYPE_DARK])
	var normal_def := _make_mon("PNormalTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("PDarkPlainAttacker", [TypeChart.TYPE_NORMAL])

	_chk("S17.01 a Prankster-boosted status move is blocked by a Dark-type target",
			AbilityManager.blocks_prankster_move(pr, dark_def, growl))
	_chk("S17.02 discriminator: the SAME Prankster user's status move is NOT " +
			"blocked by a non-Dark-type target",
			not AbilityManager.blocks_prankster_move(pr, normal_def, growl))
	_chk("S17.03 discriminator: a DAMAGING move from the same Prankster user is " +
			"never blocked (category gate — Prankster never elevates it in the first place)",
			not AbilityManager.blocks_prankster_move(pr, dark_def, tackle))
	_chk("S17.04 discriminator: a non-Prankster attacker's status move is NOT " +
			"blocked by the same Dark-type target",
			not AbilityManager.blocks_prankster_move(plain, dark_def, growl))
	_chk("S17.05 null move -> false (defensive guard)",
			not AbilityManager.blocks_prankster_move(pr, dark_def, null))

	# Full-battle: Growl (Attack -1) fails outright against a Dark-type target.
	var pr_battle := _make_mon("PDarkBattle", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	pr_battle.ability = prankster
	pr_battle.add_move(growl)
	var dark_target := _make_mon("PDarkBattleTarget", [TypeChart.TYPE_DARK], 100, 60, 60, 60, 60, 30)
	dark_target.add_move(tackle)

	var stat_events := []
	var failed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.stat_stage_changed.connect(func(m, stat, actual): stat_events.push_back([m, stat, actual]))
	bm.move_effect_failed.connect(func(m, reason): failed_events.push_back([m, reason]))
	bm.start_battle_with_parties(BattleParty.single(pr_battle), BattleParty.single(dark_target))

	_chk("S17.06 full-battle: Growl never lowers the Dark-type target's Attack " +
			"(blocked before the stat-change pipeline is ever reached)",
			stat_events.filter(func(e): return e[0] == dark_target).is_empty())
	_chk("S17.07 full-battle: move_effect_failed fired with the prankster_dark_immune reason",
			failed_events.any(func(e): return e[0] == dark_target and e[1] == "prankster_dark_immune"))

	bm.queue_free()

	# Discriminator: the same Prankster holder's Growl against a NON-Dark target
	# succeeds normally.
	var pr_battle2 := _make_mon("PDarkBattle2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	pr_battle2.ability = prankster
	pr_battle2.add_move(growl)
	var normal_target := _make_mon("PDarkBattleTarget2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	normal_target.add_move(tackle)

	var stat_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2.stat_stage_changed.connect(func(m, stat, actual): stat_events2.push_back([m, stat, actual]))
	bm2.start_battle_with_parties(BattleParty.single(pr_battle2), BattleParty.single(normal_target))

	_chk("S17.08 discriminator: full-battle, Growl DOES lower a non-Dark target's Attack",
			stat_events2.any(func(e): return e[0] == normal_target))

	bm2.queue_free()
