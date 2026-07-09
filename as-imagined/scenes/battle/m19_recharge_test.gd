extends Node

# [M19-recharge] Hyper Beam(63), Blast Burn(307), Hydro Cannon(308), Frenzy
# Plant(338), Giga Impact(416), Rock Wrecker(439), Roar of Time(459),
# Prismatic Laser(665), Meteor Assault(722), Eternabeam(723) — Bucket 4's
# largest remaining sub-group.
#
# Step 0 findings (see move_data.gd's is_recharge doc comment for full
# source citations):
#   - Data is NOT uniform across the 10: Prismatic Laser is 160/100/10 (not
#     150/90/5 like most); Meteor Assault is 150/100/5; Giga Impact/Rock
#     Wrecker/Meteor Assault are Physical, the rest Special; only Giga
#     Impact makes contact (Rock Wrecker is ballistic but non-contact,
#     Meteor Assault is physical but non-contact).
#   - A genuine, source-confirmed CORRECTION to the commonly-assumed "real
#     games: recharges even on a miss" folklore: none of these 10 moves set
#     `.preAttackEffect = TRUE` on their MOVE_EFFECT_RECHARGE additionalEffect,
#     so it dispatches ONLY via `Cmd_setadditionaleffects`, itself only
#     reachable via the successful-hit script path — a miss never sets the
#     recharge lock in this reference engine. Confirmed via `AskUserQuestion`
#     before implementing.
#   - Structurally a PRE-MOVE canceler (`CancelerRecharge`, running BEFORE
#     Sleep/Truant in source's own canceler chain), not a forced-move-repeat
#     lock like `[M19-rampage]`'s `locked_move` — there's no move to force,
#     the Pokémon does nothing at all on the recharge turn. A single
#     `BattlePokemon.must_recharge: bool` reproduces source's literal
#     rechargeTimer=2/decrement-twice shape exactly.
#   - Switch-out/faint clears it for free (source's rechargeTimer lives in
#     the same bulk-memset Volatiles struct every other switch-cleared
#     volatile does), mirrored by this project's existing `_clear_volatiles`.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c, battle_move_resolution.c, battle_main.c,
# GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_hit_triggers_recharge_next_turn()
	_test_miss_does_not_trigger_recharge()
	_test_clears_on_switch_out()
	_test_faint_clears_dangling_state()
	_test_recharge_checked_before_sleep()

	var total := _pass + _fail
	print("m19_recharge_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, type1: int,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 10 moves) ────────────────────────────────

func _test_data_integrity() -> void:
	var hyper_beam := _load_move(63)
	_chk("63 Hyper Beam loads", hyper_beam != null)
	_chk("63 name/type/category/power/accuracy/pp",
			hyper_beam.move_name == "Hyper Beam" and hyper_beam.type == TypeChart.TYPE_NORMAL
					and hyper_beam.category == 1 and hyper_beam.power == 150
					and hyper_beam.accuracy == 90 and hyper_beam.pp == 5)
	_chk("63 is_recharge, no makes_contact", hyper_beam.is_recharge and not hyper_beam.makes_contact)

	var blast_burn := _load_move(307)
	_chk("307 Blast Burn loads", blast_burn != null)
	_chk("307 name/type/category/power/accuracy/pp",
			blast_burn.move_name == "Blast Burn" and blast_burn.type == TypeChart.TYPE_FIRE
					and blast_burn.category == 1 and blast_burn.power == 150
					and blast_burn.accuracy == 90 and blast_burn.pp == 5)
	_chk("307 is_recharge", blast_burn.is_recharge)

	var hydro_cannon := _load_move(308)
	_chk("308 Hydro Cannon loads", hydro_cannon != null)
	_chk("308 name/type/category/power/accuracy/pp",
			hydro_cannon.move_name == "Hydro Cannon" and hydro_cannon.type == TypeChart.TYPE_WATER
					and hydro_cannon.category == 1 and hydro_cannon.power == 150
					and hydro_cannon.accuracy == 90 and hydro_cannon.pp == 5)
	_chk("308 is_recharge", hydro_cannon.is_recharge)

	var frenzy_plant := _load_move(338)
	_chk("338 Frenzy Plant loads", frenzy_plant != null)
	_chk("338 name/type/category/power/accuracy/pp",
			frenzy_plant.move_name == "Frenzy Plant" and frenzy_plant.type == TypeChart.TYPE_GRASS
					and frenzy_plant.category == 1 and frenzy_plant.power == 150
					and frenzy_plant.accuracy == 90 and frenzy_plant.pp == 5)
	_chk("338 is_recharge", frenzy_plant.is_recharge)

	var giga_impact := _load_move(416)
	_chk("416 Giga Impact loads", giga_impact != null)
	_chk("416 name/type/category/power/accuracy/pp",
			giga_impact.move_name == "Giga Impact" and giga_impact.type == TypeChart.TYPE_NORMAL
					and giga_impact.category == 0 and giga_impact.power == 150
					and giga_impact.accuracy == 90 and giga_impact.pp == 5)
	_chk("416 makes_contact + is_recharge (the ONLY one of the 10 with contact)",
			giga_impact.makes_contact and giga_impact.is_recharge)

	var rock_wrecker := _load_move(439)
	_chk("439 Rock Wrecker loads", rock_wrecker != null)
	_chk("439 name/type/category/power/accuracy/pp",
			rock_wrecker.move_name == "Rock Wrecker" and rock_wrecker.type == TypeChart.TYPE_ROCK
					and rock_wrecker.category == 0 and rock_wrecker.power == 150
					and rock_wrecker.accuracy == 90 and rock_wrecker.pp == 5)
	_chk("439 ballistic_move + is_recharge, NOT makes_contact (Physical but non-contact)",
			rock_wrecker.ballistic_move and rock_wrecker.is_recharge and not rock_wrecker.makes_contact)

	var roar_of_time := _load_move(459)
	_chk("459 Roar of Time loads", roar_of_time != null)
	_chk("459 name/type/category/power/accuracy/pp",
			roar_of_time.move_name == "Roar of Time" and roar_of_time.type == TypeChart.TYPE_DRAGON
					and roar_of_time.category == 1 and roar_of_time.power == 150
					and roar_of_time.accuracy == 90 and roar_of_time.pp == 5)
	_chk("459 is_recharge", roar_of_time.is_recharge)

	var prismatic_laser := _load_move(665)
	_chk("665 Prismatic Laser loads", prismatic_laser != null)
	_chk("665 name/type/category/power/accuracy/pp (genuinely different from the 150/90/5 norm)",
			prismatic_laser.move_name == "Prismatic Laser" and prismatic_laser.type == TypeChart.TYPE_PSYCHIC
					and prismatic_laser.category == 1 and prismatic_laser.power == 160
					and prismatic_laser.accuracy == 100 and prismatic_laser.pp == 10)
	_chk("665 is_recharge", prismatic_laser.is_recharge)

	var meteor_assault := _load_move(722)
	_chk("722 Meteor Assault loads", meteor_assault != null)
	_chk("722 name/type/category/power/accuracy/pp",
			meteor_assault.move_name == "Meteor Assault" and meteor_assault.type == TypeChart.TYPE_FIGHTING
					and meteor_assault.category == 0 and meteor_assault.power == 150
					and meteor_assault.accuracy == 100 and meteor_assault.pp == 5)
	_chk("722 is_recharge, NOT makes_contact (Physical but non-contact)",
			meteor_assault.is_recharge and not meteor_assault.makes_contact)

	var eternabeam := _load_move(723)
	_chk("723 Eternabeam loads", eternabeam != null)
	_chk("723 name/type/category/power/accuracy/pp",
			eternabeam.move_name == "Eternabeam" and eternabeam.type == TypeChart.TYPE_DRAGON
					and eternabeam.category == 1 and eternabeam.power == 160
					and eternabeam.accuracy == 90 and eternabeam.pp == 5)
	_chk("723 is_recharge", eternabeam.is_recharge)


# ── A hit triggers recharge, blocking exactly the NEXT turn ─────────────────

func _test_hit_triggers_recharge_next_turn() -> void:
	var hyper_beam := _load_move(63)
	var tackle := _load_move(33)
	var atk := _make_mon("RchAtk", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 200)
	atk.add_move(hyper_beam)
	# Weak/tanky opponent so atk survives several of its own action attempts.
	var def := _make_mon("RchDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	# Combined ordered event log of atk's own actions only (hit vs skipped),
	# guarded to the first 3 so the assertion isn't sensitive to however many
	# more turns the battle runs afterward (whole-battle-aggregation safe).
	var events := []
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk and events.size() < 3:
			events.append("hit"))
	bm.move_skipped.connect(func(a, reason):
		if a == atk and events.size() < 3:
			events.append("skipped:" + reason))
	bm.start_battle(atk, def)

	_chk("Recharge: turn 1 is a normal hit (%s)" % [events],
			events.size() >= 1 and events[0] == "hit")
	_chk("Recharge: turn 2 is FORCED to skip with reason 'recharging' (%s)" % [events],
			events.size() >= 2 and events[1] == "skipped:recharging")
	_chk("Recharge: turn 3 is a normal hit again — exactly ONE turn was blocked (%s)" % [events],
			events.size() >= 3 and events[2] == "hit")


# ── A MISS does NOT trigger recharge — the key divergence from folklore ─────

func _test_miss_does_not_trigger_recharge() -> void:
	var hyper_beam := _load_move(63)
	var tackle := _load_move(33)
	var atk := _make_mon("MissAtk", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 200)
	atk.add_move(hyper_beam)
	var def := _make_mon("MissDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = false  # guaranteed miss, every attempt
	var events := []
	bm.move_missed.connect(func(a, reason):
		if a == atk and events.size() < 3:
			events.append("missed:" + reason))
	bm.move_skipped.connect(func(a, reason):
		if a == atk and events.size() < 3:
			events.append("skipped:" + reason))
	bm.start_battle(atk, def)

	_chk(("Recharge discriminator: 3 consecutive misses, NEVER a 'recharging' " +
			"skip in between (%s) — a miss never sets the lock in this reference " +
			"engine (confirmed from source, not folklore)") % [events],
			events.size() >= 3 and events.all(func(e): return e == "missed:accuracy"))
	_chk("Recharge discriminator: must_recharge stays false after repeated misses",
			atk.must_recharge == false)


# ── Clears on switch-out ─────────────────────────────────────────────────────

func _test_clears_on_switch_out() -> void:
	var hyper_beam := _load_move(63)
	var tackle := _load_move(33)
	var atk := _make_mon("SwAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(hyper_beam)
	atk.must_recharge = true  # deterministic pre-set, matching this project's
	# established convention for testing switch-clear behavior directly.
	var bench := _make_mon("SwBench", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 50)
	bench.add_move(tackle)
	var def := _make_mon("SwDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	var party := BattleParty.new()
	party.members = [atk, bench]
	party.active_index = 0
	bm.queue_switch(0, 1)  # P1 turn 1: voluntary switch to bench (slot 1)
	# Snapshot via the pokemon_switched_out signal, guarded to the first
	# occurrence for atk specifically — this project's battles run to full
	# completion, and atk's own move is Hyper Beam (is_recharge), so if
	# bench later faints and atk gets forced back in via faint-replacement,
	# a later Hyper Beam use would legitimately re-set must_recharge, making
	# a post-battle read of atk.must_recharge flaky (confirmed: this exact
	# scenario caused an intermittent failure on the first draft of this
	# test). Reading it live inside the switch-out handler avoids that.
	var snapped := [false]
	var snap_must_recharge := [true]
	bm.pokemon_switched_out.connect(func(p, _s):
		if p == atk and not snapped[0]:
			snapped[0] = true
			snap_must_recharge[0] = atk.must_recharge)
	bm.start_battle_with_parties(party, BattleParty.single(def))

	_chk("Recharge: must_recharge clears on voluntary switch-out",
			snapped[0] == true and snap_must_recharge[0] == false)


# ── A recharge-locked Pokémon that faints leaves no dangling state ─────────

func _test_faint_clears_dangling_state() -> void:
	var hyper_beam := _load_move(63)
	var tackle := _load_move(33)
	var atk := _make_mon("FaintAtk", TypeChart.TYPE_NORMAL, 20, 60, 10, 60, 10, 10)
	atk.must_recharge = true
	atk.add_move(hyper_beam)
	var def := _make_mon("FaintDef", TypeChart.TYPE_NORMAL, 200, 100, 60, 100, 60, 200)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm.start_battle(atk, def)

	_chk("Recharge: a fainted mon's must_recharge is cleared (no dangling " +
			"truthy state left behind), even though the mon never got to " +
			"actually act this battle", atk.must_recharge == false)
	_chk("Recharge discriminator: the mon genuinely fainted (confirms this " +
			"was a real faint-clear, not a vacuous pass)", atk.fainted == true)


# ── Recharge is checked BEFORE Sleep (source's own canceler ordering) ──────

func _test_recharge_checked_before_sleep() -> void:
	var hyper_beam := _load_move(63)
	var tackle := _load_move(33)
	var atk := _make_mon("OrderAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(hyper_beam)
	atk.must_recharge = true
	atk.status = BattlePokemon.STATUS_SLEEP
	atk.sleep_turns = 3
	var def := _make_mon("OrderDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	var skipped := []
	bm.move_skipped.connect(func(a, reason):
		if a == atk and skipped.is_empty():
			skipped.append(reason))
	bm.start_battle(atk, def)

	_chk("Recharge: checked BEFORE Sleep — reason is 'recharging', not 'asleep' " +
			"(%s)" % [skipped], skipped.size() > 0 and skipped[0] == "recharging")
