extends Node

# [EFFECT_STAT_CHANGE audit] Every already-implemented foe/selected-targeting
# move whose real script maps to BattleScript_EffectStatChange (the same
# typecalc-free script backing Toxic Thread(635)/Venom Drench(599), fixed in
# [D4 Bundle 6]) has now been individually re-checked against source and this
# project's own TypeChart.TABLE. 16 were confirmed genuinely affected (a real
# 0.0x matchup exists for the move's type and it was reaching the general
# foe-targeting type-immunity gate unexempted): Sand Attack(28, vs Flying),
# Tail Whip(39)/Leer(43)/Growl(45)/Screech(103)/Smokescreen(108)/Flash(148)/
# Scary Face(184)/Sweet Scent(230)/Tickle(321)/Noble Roar(568)/Play Nice(589)/
# Confide(590)/Tearful Look(669) (all Normal-type, vs Ghost), Kinesis(134, vs
# Dark), Eerie Impulse(598, vs Ground). Each now carries the new shared
# MoveData.stat_change_bypasses_type_gate flag.
#
# The other 9 candidates in the same source family (String Shot/Cotton Spore/
# Charm/Feather Dance/Fake Tears/Metal Sound/Baby-Doll Eyes/Decorate/Spicy
# Extract) share the identical latent gap in principle but are provably
# UNREACHABLE — their own type has no 0.0x row anywhere in this project's
# chart — so, matching the established Memento precedent, they're
# deliberately left unexempted; no test coverage needed for a no-op.
#
# Ground truth: src/data/battle_move_effects.h (EFFECT_STAT_CHANGE /
# EFFECT_STAT_CHANGE_ON_STATUS / EFFECT_TOXIC_THREAD / EFFECT_STAT_CHANGE_
# MAGNETIC all map to the literal same BattleScript_EffectStatChange);
# src/battle_script_commands.c :: Cmd_trymovestatchanges (L10744-10752);
# src/battle_move_resolution.c :: DoStatChange (L4823-4863) — neither
# contains a type-effectiveness call.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_sand_attack_vs_flying()
	_test_tail_whip_vs_ghost()
	_test_leer_vs_ghost()
	_test_growl_vs_ghost()
	_test_screech_vs_ghost()
	_test_smokescreen_vs_ghost()
	_test_kinesis_vs_dark()
	_test_flash_vs_ghost()
	_test_scary_face_vs_ghost()
	_test_sweet_scent_vs_ghost()
	_test_tickle_vs_ghost()
	_test_noble_roar_vs_ghost()
	_test_play_nice_vs_ghost()
	_test_confide_vs_ghost()
	_test_eerie_impulse_vs_ground()
	_test_tearful_look_vs_ghost()
	_test_negative_control()

	var total := _pass + _fail
	print("effect_stat_change_audit_test: %d/%d passed" % [_pass, total])
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


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var ids := {
		28: "Sand Attack", 39: "Tail Whip", 43: "Leer", 45: "Growl",
		103: "Screech", 108: "Smokescreen", 134: "Kinesis", 148: "Flash",
		184: "Scary Face", 230: "Sweet Scent", 321: "Tickle",
		568: "Noble Roar", 589: "Play Nice", 590: "Confide",
		598: "Eerie Impulse", 669: "Tearful Look",
	}
	for id in ids.keys():
		var m := _load_move(id)
		_chk("A.%d %s carries stat_change_bypasses_type_gate=true" % [id, ids[id]],
				m.stat_change_bypasses_type_gate == true)


# ── Section B: one full-battle discriminator per newly-exempted move ────
# Each proves the stat change now lands against the exact type that would
# previously have made the general gate silently block the move outright.

func _run_stat_discriminator(label: String, move_id: int, target_type: int,
		expect_stat: int, expect_delta: int) -> void:
	var move := _load_move(move_id)
	var atk := _make_mon("Atk%d" % move_id, 200, 60, 60, 60, 60, 60)
	atk.add_move(move)
	var def := _make_mon("Def%d" % move_id, 200, 60, 60, 60, 60, 60, target_type)
	var bm := _make_bm()
	bm._force_hit = true
	var changed := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == expect_stat and delta == expect_delta:
			changed[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk(label, changed[0] == true)


func _test_sand_attack_vs_flying() -> void:
	_run_stat_discriminator(
			"B.28 REQUIRED: Sand Attack still lowers Accuracy vs a Flying-immune target",
			28, TypeChart.TYPE_FLYING, BattlePokemon.STAGE_ACCURACY, -1)


func _test_tail_whip_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.39 REQUIRED: Tail Whip still lowers Defense vs a Ghost-immune target",
			39, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_DEF, -1)


func _test_leer_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.43 REQUIRED: Leer still lowers Defense vs a Ghost-immune target",
			43, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_DEF, -1)


func _test_growl_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.45 REQUIRED: Growl still lowers Attack vs a Ghost-immune target",
			45, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_ATK, -1)


func _test_screech_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.103 REQUIRED: Screech still lowers Defense vs a Ghost-immune target",
			103, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_DEF, -2)


func _test_smokescreen_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.108 REQUIRED: Smokescreen still lowers Accuracy vs a Ghost-immune target",
			108, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_ACCURACY, -1)


func _test_kinesis_vs_dark() -> void:
	_run_stat_discriminator(
			"B.134 REQUIRED: Kinesis still lowers Accuracy vs a Dark-immune target",
			134, TypeChart.TYPE_DARK, BattlePokemon.STAGE_ACCURACY, -1)


func _test_flash_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.148 REQUIRED: Flash still lowers Accuracy vs a Ghost-immune target",
			148, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_ACCURACY, -1)


func _test_scary_face_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.184 REQUIRED: Scary Face still lowers Speed vs a Ghost-immune target",
			184, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_SPEED, -2)


func _test_sweet_scent_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.230 REQUIRED: Sweet Scent still lowers Evasion vs a Ghost-immune target",
			230, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_EVASION, -2)


func _test_tickle_vs_ghost() -> void:
	# Tickle is multi-stat (primary Atk-1, extra Def-1 via [Bucket 3
	# multi-stat]'s _apply_one_stat_change_pair) — confirm BOTH pairs land.
	var move := _load_move(321)
	var atk := _make_mon("TickleAtk", 200, 60, 60, 60, 60, 60)
	atk.add_move(move)
	var def := _make_mon("TickleDef", 200, 60, 60, 60, 60, 60, TypeChart.TYPE_GHOST)
	var bm := _make_bm()
	bm._force_hit = true
	var atk_dropped := [false]
	var def_dropped := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_ATK and delta == -1:
			atk_dropped[0] = true
		if mon == def and stat == BattlePokemon.STAGE_DEF and delta == -1:
			def_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.321a REQUIRED: Tickle still lowers Attack vs a Ghost-immune target",
			atk_dropped[0] == true)
	_chk("B.321b REQUIRED: Tickle still lowers Defense vs a Ghost-immune target",
			def_dropped[0] == true)


func _test_noble_roar_vs_ghost() -> void:
	# Noble Roar is multi-stat (primary Atk-1, extra SpAtk-1).
	var move := _load_move(568)
	var atk := _make_mon("NobleRoarAtk", 200, 60, 60, 60, 60, 60)
	atk.add_move(move)
	var def := _make_mon("NobleRoarDef", 200, 60, 60, 60, 60, 60, TypeChart.TYPE_GHOST)
	var bm := _make_bm()
	bm._force_hit = true
	var atk_dropped := [false]
	var spatk_dropped := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_ATK and delta == -1:
			atk_dropped[0] = true
		if mon == def and stat == BattlePokemon.STAGE_SPATK and delta == -1:
			spatk_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.568a REQUIRED: Noble Roar still lowers Attack vs a Ghost-immune target",
			atk_dropped[0] == true)
	_chk("B.568b REQUIRED: Noble Roar still lowers Sp. Attack vs a Ghost-immune target",
			spatk_dropped[0] == true)


func _test_play_nice_vs_ghost() -> void:
	# accuracy=0 in this schema means always-hits — no _force_hit needed,
	# but harmless to leave it set for consistency with the rest of this file.
	_run_stat_discriminator(
			"B.589 REQUIRED: Play Nice still lowers Attack vs a Ghost-immune target",
			589, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_ATK, -1)


func _test_confide_vs_ghost() -> void:
	_run_stat_discriminator(
			"B.590 REQUIRED: Confide still lowers Sp. Attack vs a Ghost-immune target",
			590, TypeChart.TYPE_GHOST, BattlePokemon.STAGE_SPATK, -1)


func _test_eerie_impulse_vs_ground() -> void:
	_run_stat_discriminator(
			"B.598 REQUIRED: Eerie Impulse still lowers Sp. Attack vs a Ground-immune target",
			598, TypeChart.TYPE_GROUND, BattlePokemon.STAGE_SPATK, -2)


func _test_tearful_look_vs_ghost() -> void:
	# Tearful Look is multi-stat (primary Atk-1, extra SpAtk-1), accuracy=0.
	var move := _load_move(669)
	var atk := _make_mon("TearfulLookAtk", 200, 60, 60, 60, 60, 60)
	atk.add_move(move)
	var def := _make_mon("TearfulLookDef", 200, 60, 60, 60, 60, 60, TypeChart.TYPE_GHOST)
	var bm := _make_bm()
	var atk_dropped := [false]
	var spatk_dropped := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_ATK and delta == -1:
			atk_dropped[0] = true
		if mon == def and stat == BattlePokemon.STAGE_SPATK and delta == -1:
			spatk_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.669a REQUIRED: Tearful Look still lowers Attack vs a Ghost-immune target",
			atk_dropped[0] == true)
	_chk("B.669b REQUIRED: Tearful Look still lowers Sp. Attack vs a Ghost-immune target",
			spatk_dropped[0] == true)


# ── Section C: negative control ──────────────────────────────────────────
# Proves the harness genuinely discriminates: a synthetic Normal-type
# EFFECT_STAT_CHANGE-shaped move WITHOUT the new exemption flag is still
# correctly blocked by the general gate against a Ghost-type target — the
# same immunity the 13 Normal-type moves above would have hit before this
# fix, and would hit again if the flag were ever silently dropped.

func _test_negative_control() -> void:
	var plain := MoveData.new()
	plain.type = TypeChart.TYPE_NORMAL
	plain.category = 2  # STAT
	plain.power = 0
	plain.accuracy = 100
	plain.stat_change_stat = BattlePokemon.STAGE_DEF
	plain.stat_change_amount = -1
	plain.stat_change_self = false
	plain.stat_change_bypasses_type_gate = false  # explicit: the case under test

	var atk := _make_mon("NegAtk", 200, 60, 60, 60, 60, 60)
	atk.add_move(plain)
	var def := _make_mon("NegDef", 200, 60, 60, 60, 60, 60, TypeChart.TYPE_GHOST)
	var bm := _make_bm()
	bm._force_hit = true
	var dropped := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_DEF and delta == -1:
			dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("C.01 NEGATIVE CONTROL: a non-exempted stat-change move is still " +
			"blocked by the general gate vs a Ghost-immune target",
			dropped[0] == false)
