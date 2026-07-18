extends Node

# M18w test suite — Red Orb / Blue Orb
#
# Source: TryPrimalReversion -> TryBattleFormChange(FORM_CHANGE_BATTLE_PRIMAL_
# REVERSION) (battle_util.c L4783-4791), gated per-species via the form-change
# table (sGroudonFormChangeTable/sKyogreFormChangeTable): Groudon+Red Orb only,
# Kyogre+Blue Orb only — NOT interchangeable. CORRECTION (see
# ItemManager.HOLD_EFFECT_PRIMAL_ORB's own doc comment): real Primal Reversion
# is a full species/stat/type swap, the same shape as Mega Evolution, which
# this project has already structurally excluded (no form-change-mid-battle
# infrastructure exists). This tier's in-scope, achievable deliverable is
# ABILITY-SET ONLY (Desolate Land / Primordial Sea on switch-in) — tested here
# accordingly, not a species/stat/type change.
#
# Switch-in is single-fire (battle start), so a full `start_battle` checking
# for the trigger's presence is safe — no re-trigger risk to conflate with a
# later event.
#
# Sections:
#   W01 Red Orb — Groudon switch-in sets Desolate Land
#   W02 Blue Orb — Kyogre switch-in sets Primordial Sea
#   W03 discriminators — wrong item/species combinations get nothing

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_w01_red_orb()
	_test_w02_blue_orb()
	_test_w03_discriminators()

	var total := _pass + _fail
	print("m18w_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon(mon_name: String, dex: int, type1: int, hp: int = 100,
		atk: int = 80, def_stat: int = 80, spatk: int = 80, spdef: int = 80,
		spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.national_dex_num = dex
	sp.types.append(type1)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_tackle() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Tackle"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 0
	m.power     = 40
	m.accuracy  = 100
	m.pp        = 40
	return m


# ── W01: Red Orb — Groudon switch-in sets Desolate Land ────────────────────────

func _test_w01_red_orb() -> void:
	var red_orb := _load_item(290)
	_chk("W01.00 fixture loads", red_orb != null)
	_chk("W01.00b fixture check: Red Orb required_species == Groudon(383)",
			red_orb.required_species == 383)

	var groudon := _make_mon("Groudon", 383, TypeChart.TYPE_GROUND, 100)
	groudon.held_item = red_orb
	groudon.add_move(_make_tackle())
	var foe := _make_mon("Foe", 1, TypeChart.TYPE_NORMAL, 300)
	foe.add_move(_make_tackle())

	var ability_events := []
	var weather_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(m, id): ability_events.push_back([m, id]))
	bm.weather_set.connect(func(m, w): weather_events.push_back([m, w]))
	bm.start_battle(groudon, foe)

	_chk("W01.01 ability_changed fires for Groudon with Desolate Land's id (190)",
			ability_events.any(func(e): return e[0] == groudon and e[1] == AbilityManager.ABILITY_DESOLATE_LAND))
	_chk("W01.02 the holder's .ability is actually Desolate Land afterward",
			groudon.ability != null and groudon.ability.ability_id == AbilityManager.ABILITY_DESOLATE_LAND)
	_chk("W01.03 composition: the newly-set Desolate Land ALSO sets harsh sun on " +
			"switch-in (proves the ability-set happens BEFORE the existing Drizzle/" +
			"Drought weather-check block runs, not after)",
			weather_events.any(func(e): return e[0] == groudon and e[1] == BattleManager.WEATHER_SUN))
	bm.queue_free()


# ── W02: Blue Orb — Kyogre switch-in sets Primordial Sea ───────────────────────

func _test_w02_blue_orb() -> void:
	var blue_orb := _load_item(291)
	_chk("W02.00 fixture loads", blue_orb != null)
	_chk("W02.00b fixture check: Blue Orb required_species == Kyogre(382)",
			blue_orb.required_species == 382)

	var kyogre := _make_mon("Kyogre", 382, TypeChart.TYPE_WATER, 100)
	kyogre.held_item = blue_orb
	kyogre.add_move(_make_tackle())
	var foe := _make_mon("Foe", 1, TypeChart.TYPE_NORMAL, 300)
	foe.add_move(_make_tackle())

	var ability_events := []
	var weather_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(m, id): ability_events.push_back([m, id]))
	bm.weather_set.connect(func(m, w): weather_events.push_back([m, w]))
	bm.start_battle(kyogre, foe)

	_chk("W02.01 ability_changed fires for Kyogre with Primordial Sea's id (189)",
			ability_events.any(func(e): return e[0] == kyogre and e[1] == AbilityManager.ABILITY_PRIMORDIAL_SEA))
	_chk("W02.02 the holder's .ability is actually Primordial Sea afterward",
			kyogre.ability != null and kyogre.ability.ability_id == AbilityManager.ABILITY_PRIMORDIAL_SEA)
	_chk("W02.03 composition: the newly-set Primordial Sea ALSO sets rain on switch-in",
			weather_events.any(func(e): return e[0] == kyogre and e[1] == BattleManager.WEATHER_RAIN))
	bm.queue_free()


# ── W03: discriminators — wrong item/species combinations get nothing ──────────

func _test_w03_discriminators() -> void:
	var red_orb := _load_item(290)
	var blue_orb := _load_item(291)

	# Groudon holding Blue Orb (the WRONG orb) -> no effect.
	var groudon_wrong := _make_mon("GroudonWrong", 383, TypeChart.TYPE_GROUND, 100)
	groudon_wrong.held_item = blue_orb
	groudon_wrong.add_move(_make_tackle())
	var foe1 := _make_mon("Foe1", 1, TypeChart.TYPE_NORMAL, 300)
	foe1.add_move(_make_tackle())

	var ability_events1 := []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.ability_changed.connect(func(m, id): ability_events1.push_back([m, id]))
	bm1.start_battle(groudon_wrong, foe1)
	_chk("W03.01 discriminator: Groudon holding Blue Orb (wrong item) -> " +
			"NOT interchangeable, no ability change at all",
			not ability_events1.any(func(e): return e[0] == groudon_wrong))
	_chk("W03.02 Groudon+Blue-Orb's ability stays null (never set)",
			groudon_wrong.ability == null)
	bm1.queue_free()

	# Kyogre holding Red Orb (the WRONG orb) -> no effect.
	var kyogre_wrong := _make_mon("KyogreWrong", 382, TypeChart.TYPE_WATER, 100)
	kyogre_wrong.held_item = red_orb
	kyogre_wrong.add_move(_make_tackle())
	var foe2 := _make_mon("Foe2", 1, TypeChart.TYPE_NORMAL, 300)
	foe2.add_move(_make_tackle())

	var ability_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.ability_changed.connect(func(m, id): ability_events2.push_back([m, id]))
	bm2.start_battle(kyogre_wrong, foe2)
	_chk("W03.03 discriminator: Kyogre holding Red Orb (wrong item) -> no " +
			"ability change at all",
			not ability_events2.any(func(e): return e[0] == kyogre_wrong))
	bm2.queue_free()

	# A non-Groudon/Kyogre holder with Red Orb -> no effect.
	var random_mon := _make_mon("RandomMon", 1, TypeChart.TYPE_NORMAL, 100)
	random_mon.held_item = red_orb
	random_mon.add_move(_make_tackle())
	var foe3 := _make_mon("Foe3", 1, TypeChart.TYPE_NORMAL, 300)
	foe3.add_move(_make_tackle())

	var ability_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.ability_changed.connect(func(m, id): ability_events3.push_back([m, id]))
	bm3.start_battle(random_mon, foe3)
	_chk("W03.04 discriminator: a non-Groudon/Kyogre holder with Red Orb -> " +
			"no ability change at all",
			not ability_events3.any(func(e): return e[0] == random_mon))
	_chk("W03.05 direct check: ItemManager.primal_orb_target_ability_id returns " +
			"-1 for a mismatched species/item pair",
			ItemManager.primal_orb_target_ability_id(random_mon) == -1)
	bm3.queue_free()
