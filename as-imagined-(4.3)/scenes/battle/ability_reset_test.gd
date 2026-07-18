extends Node

# [Ability-reset fix] — bugfix, not new scope. Corrects a real gap in
# already-shipped code ([M17h] 2026-07-03, [D2 batch] 2026-07-09): source's
# SwitchInClearSetData unconditionally re-derives `.ability` from species on
# EVERY switch-in (battle_main.c), but this project's own `_reset_mon_type`
# (called at every switch-in site) only ever reset `species.types` — `.ability`
# was never reset anywhere except the one Primal-Reversion switch-in trigger
# (M18w). This meant Trace/Mummy/Wandering Spirit/Lingering Aroma/Skill Swap/
# Role Play's ability overwrites persisted PERMANENTLY across switch-outs.
#
# Fix: `BattlePokemon.ability` gained a custom setter that captures
# `original_ability` on the FIRST assignment only (this project has no
# per-instance "ability slot index" the way source's `abilityNum` field does,
# so re-deriving from species+slot the way source literally does isn't
# possible here — capturing the first-ever assignment is the equivalent).
# New `BattleManager._reset_mon_ability(mon)`, a sibling to `_reset_mon_type`
# (not folded into it — that function's own name/scope is specifically
# about type), called at the same 5 switch-in sites `_reset_mon_type`
# already occupies.
#
# Neither m17h_test.gd nor d2_batch_test.gd (the two origin suites for these
# 6 abilities) has any switch-out-and-back-in test for any of them —
# confirmed via grep before writing this fix — so nothing there was
# asserting the old (buggy) persist-forever behavior; both suites reran
# unchanged (64/64, 82/82).
#
# Ground truth: pokeemerald_expansion src/battle_main.c ::
#   SwitchInClearSetData (`ability = GetAbilityBySpecies(species, abilityNum)`).
#
# Sections:
#   S1: original_ability capture/setter unit tests
#   S2: Trace reverts on switch-out+in, THEN re-traces on the same switch-in
#       (proving _reset_mon_ability runs BEFORE _apply_switch_in_abilities)
#   S3: Mummy/Lingering Aroma — attacker's overwritten ability reverts
#   S4: Wandering Spirit — BOTH sides independently revert
#   S5: Skill Swap — BOTH sides independently revert
#   S6: Role Play — attacker's copied ability reverts, target untouched
#   S7: Primal Reversion (M18w) ordering — re-applies correctly after a
#       switch-out+in, not left at the mon's own natural ability

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_s1_setter_capture()
	_test_s2_trace_reverts_and_retraces()
	_test_s3_mummy_lingering_aroma_reverts()
	_test_s4_wandering_spirit_reverts_both_sides()
	_test_s5_skill_swap_reverts_both_sides()
	_test_s6_role_play_reverts()
	_test_s7_primal_reversion_ordering()

	var total := _pass + _fail
	print("ability_reset_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, mon_type: int = TypeChart.TYPE_NORMAL,
		hp: int = 100, atk: int = 80, def_stat: int = 80, spatk: int = 80,
		spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── S1: setter/capture unit tests ────────────────────────────────────────────

func _test_s1_setter_capture() -> void:
	var mon := _make_mon("S1Mon")
	_chk("S1.01 original_ability starts null (never assigned yet)",
			mon.original_ability == null)

	var insomnia := _load_ability(15)
	mon.ability = insomnia
	_chk("S1.02 first assignment captures original_ability",
			mon.original_ability == insomnia)

	var intimidate := _load_ability(22)
	mon.ability = intimidate
	_chk("S1.03 second assignment does NOT re-capture original_ability",
			mon.original_ability == insomnia)
	_chk("S1.04 second assignment still updates the live .ability field",
			mon.ability == intimidate)

	var bm := _make_bm()
	bm._reset_mon_ability(mon)
	_chk("S1.05 _reset_mon_ability restores .ability to original_ability",
			mon.ability == insomnia)
	bm.queue_free()


# ── S2: Trace ────────────────────────────────────────────────────────────────

func _test_s2_trace_reverts_and_retraces() -> void:
	var trace := _load_ability(36)
	var intimidate := _load_ability(22)

	var tracer := _make_mon("Tracer")
	tracer.ability = trace  # captured as original_ability

	var opp_intimidate := _make_mon("OppIntimidate")
	opp_intimidate.ability = intimidate

	var traced_id: int = AbilityManager.try_trace(tracer, [opp_intimidate])
	_chk("S2.01 Trace copied Intimidate", traced_id == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S2.02 tracer's live ability is now Intimidate", tracer.ability == intimidate)
	_chk("S2.03 tracer's original_ability is still Trace (untouched)",
			tracer.original_ability == trace)

	# Real switch-out + back-in via a full battle.
	var bench := _make_mon("Bench")
	var player_party := BattleParty.new()
	player_party.members = [tracer, bench]
	player_party.active_index = 0

	var bm := _make_bm()
	bm.queue_switch(0, 1)  # Turn 1: switch tracer out to bench.
	bm.queue_switch(0, 0)  # Turn 2: switch back to tracer.
	bm.start_battle_with_parties(player_party, BattleParty.single(opp_intimidate))

	_chk("S2.04 Trace reverted to its own natural ability after switch-out+in, " +
			"AND immediately re-traced Intimidate (proving the reset runs BEFORE " +
			"switch-in abilities re-apply, not after)",
			tracer.ability == intimidate and tracer.original_ability == trace)
	bm.queue_free()


# ── S3: Mummy / Lingering Aroma ──────────────────────────────────────────────

func _test_s3_mummy_lingering_aroma_reverts() -> void:
	for case in [
		{"tag": "S3a", "id": 152, "name": "Mummy"},
		{"tag": "S3b", "id": 268, "name": "Lingering Aroma"},
	]:
		var holder := _make_mon(case["name"] + "Holder")
		holder.ability = _load_ability(case["id"])

		var overheat_natural := _load_ability(15)  # Insomnia, arbitrary natural ability
		var attacker := _make_mon(case["name"] + "Attacker")
		attacker.ability = overheat_natural

		var tackle := _load_move(33)
		var overwritten_id: int = AbilityManager.try_mummy_overwrite(
				holder, attacker, tackle, 10, false)
		_chk(case["tag"] + ".01 " + case["name"] + " overwrote the attacker's ability",
				overwritten_id == case["id"])
		_chk(case["tag"] + ".02 attacker's original_ability is still its own natural one",
				attacker.original_ability == overheat_natural)
		_chk(case["tag"] + ".03 holder's own ability is untouched (one-directional)",
				holder.ability.ability_id == case["id"])

		var bench := _make_mon(case["name"] + "Bench")
		var player_party := BattleParty.new()
		player_party.members = [attacker, bench]
		player_party.active_index = 0

		var bm := _make_bm()
		bm.queue_switch(0, 1)
		bm.queue_switch(0, 0)
		bm.start_battle_with_parties(player_party, BattleParty.single(_make_mon("S3Opp")))

		_chk(case["tag"] + ".04 attacker's ability reverted to natural after switch-out+in",
				attacker.ability == overheat_natural)
		bm.queue_free()


# ── S4: Wandering Spirit — bidirectional, both sides revert independently ──

func _test_s4_wandering_spirit_reverts_both_sides() -> void:
	var wandering_spirit := _load_ability(254)
	var insomnia := _load_ability(15)

	var holder := _make_mon("WSHolder")
	holder.ability = wandering_spirit
	var attacker := _make_mon("WSAttacker")
	attacker.ability = insomnia

	var tackle := _load_move(33)
	var swapped: bool = AbilityManager.try_wandering_spirit_swap(
			holder, attacker, tackle, 10, false)
	_chk("S4.01 Wandering Spirit swap occurred", swapped)
	_chk("S4.02 attacker now holds Wandering Spirit", attacker.ability == wandering_spirit)
	_chk("S4.03 holder now holds Insomnia", holder.ability == insomnia)
	_chk("S4.04 attacker's original_ability is still its own natural (Insomnia)",
			attacker.original_ability == insomnia)
	_chk("S4.05 holder's original_ability is still its own natural (Wandering Spirit)",
			holder.original_ability == wandering_spirit)

	# Switch the ATTACKER out and back in — should revert to Insomnia.
	var bench_a := _make_mon("WSBenchA")
	var attacker_party := BattleParty.new()
	attacker_party.members = [attacker, bench_a]
	attacker_party.active_index = 0
	var bm_a := _make_bm()
	bm_a.queue_switch(0, 1)
	bm_a.queue_switch(0, 0)
	bm_a.start_battle_with_parties(attacker_party, BattleParty.single(_make_mon("S4OppA")))
	_chk("S4.06 attacker's ability reverted to Insomnia after its own switch-out+in",
			attacker.ability == insomnia)
	bm_a.queue_free()

	# Switch the HOLDER out and back in — should revert to Wandering Spirit
	# (and, matching S2's Trace finding, does NOT re-trigger anything extra —
	# Wandering Spirit itself has no switch-in dispatch, unlike Trace).
	var bench_h := _make_mon("WSBenchH")
	var holder_party := BattleParty.new()
	holder_party.members = [holder, bench_h]
	holder_party.active_index = 0
	var bm_h := _make_bm()
	bm_h.queue_switch(0, 1)
	bm_h.queue_switch(0, 0)
	bm_h.start_battle_with_parties(holder_party, BattleParty.single(_make_mon("S4OppH")))
	_chk("S4.07 holder's ability reverted to Wandering Spirit after its own switch-out+in",
			holder.ability == wandering_spirit)
	bm_h.queue_free()


# ── S5: Skill Swap — bidirectional, both sides revert independently ────────

func _test_s5_skill_swap_reverts_both_sides() -> void:
	var levitate := _load_ability(26)
	var insomnia := _load_ability(15)

	var attacker := _make_mon("SSAttacker")
	attacker.ability = insomnia
	var target := _make_mon("SSTarget")
	target.ability = levitate

	var swapped: bool = AbilityManager.try_skill_swap(attacker, target)
	_chk("S5.01 Skill Swap occurred", swapped)
	_chk("S5.02 attacker now holds Levitate", attacker.ability == levitate)
	_chk("S5.03 target now holds Insomnia", target.ability == insomnia)

	var bench_a := _make_mon("SSBenchA")
	var attacker_party := BattleParty.new()
	attacker_party.members = [attacker, bench_a]
	attacker_party.active_index = 0
	var bm_a := _make_bm()
	bm_a.queue_switch(0, 1)
	bm_a.queue_switch(0, 0)
	bm_a.start_battle_with_parties(attacker_party, BattleParty.single(_make_mon("S5OppA")))
	_chk("S5.04 attacker's ability reverted to Insomnia after its own switch-out+in",
			attacker.ability == insomnia)
	bm_a.queue_free()

	var bench_t := _make_mon("SSBenchT")
	var target_party := BattleParty.new()
	target_party.members = [target, bench_t]
	target_party.active_index = 0
	var bm_t := _make_bm()
	bm_t.queue_switch(0, 1)
	bm_t.queue_switch(0, 0)
	bm_t.start_battle_with_parties(target_party, BattleParty.single(_make_mon("S5OppT")))
	_chk("S5.05 target's ability reverted to Levitate after its own switch-out+in",
			target.ability == levitate)
	bm_t.queue_free()


# ── S6: Role Play — one-directional, only the attacker changes/reverts ─────

func _test_s6_role_play_reverts() -> void:
	var levitate := _load_ability(26)
	var insomnia := _load_ability(15)

	var attacker := _make_mon("RPAttacker")
	attacker.ability = insomnia
	var target := _make_mon("RPTarget")
	target.ability = levitate

	var copied: bool = AbilityManager.try_role_play(attacker, target)
	_chk("S6.01 Role Play copy occurred", copied)
	_chk("S6.02 attacker now holds Levitate", attacker.ability == levitate)
	_chk("S6.03 target's own ability is untouched", target.ability == levitate and
			target.original_ability == levitate)

	var bench := _make_mon("RPBench")
	var attacker_party := BattleParty.new()
	attacker_party.members = [attacker, bench]
	attacker_party.active_index = 0
	var bm := _make_bm()
	bm.queue_switch(0, 1)
	bm.queue_switch(0, 0)
	bm.start_battle_with_parties(attacker_party, BattleParty.single(_make_mon("S6Opp")))
	_chk("S6.04 attacker's ability reverted to Insomnia after switch-out+in",
			attacker.ability == insomnia)
	bm.queue_free()


# ── S7: Primal Reversion (M18w) ordering ────────────────────────────────────
# Confirms _reset_mon_ability (which runs first) doesn't leave the Orb holder
# stuck on its own natural ability — _apply_switch_in_abilities (which runs
# right after) must still re-apply the Primal ability every switch-in.

func _test_s7_primal_reversion_ordering() -> void:
	var kyogre_sp := PokemonSpecies.new()
	kyogre_sp.species_name = "Kyogre"
	kyogre_sp.national_dex_num = 382
	kyogre_sp.types = [TypeChart.TYPE_WATER]
	kyogre_sp.base_hp = 100
	kyogre_sp.base_attack = 80
	kyogre_sp.base_defense = 80
	kyogre_sp.base_sp_attack = 80
	kyogre_sp.base_sp_defense = 80
	kyogre_sp.base_speed = 80
	var kyogre := BattlePokemon.from_species(kyogre_sp, 50)
	kyogre.ability = _load_ability(2)  # Drizzle — Kyogre's own natural ability
	kyogre.held_item = load("res://data/items/item_0291.tres") as ItemData  # Blue Orb

	var bench := _make_mon("S7Bench")
	var player_party := BattleParty.new()
	player_party.members = [kyogre, bench]
	player_party.active_index = 0

	var bm := _make_bm()
	bm.queue_switch(0, 1)
	bm.queue_switch(0, 0)
	bm.start_battle_with_parties(player_party, BattleParty.single(_make_mon("S7Opp")))

	_chk("S7.01 Primal Reversion's Primordial Sea is still applied after switch-out+in " +
			"(NOT reverted to Kyogre's own natural Drizzle and left there)",
			kyogre.ability != null and
			kyogre.ability.ability_id == AbilityManager.ABILITY_PRIMORDIAL_SEA)
	bm.queue_free()
