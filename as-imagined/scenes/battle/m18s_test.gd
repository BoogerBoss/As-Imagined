extends Node

# M18s test suite — Eviolite + Assault Vest
#
# Both live in ItemManager.defense_stat_modifier_uq412 — the SAME pipeline stage
# ([M18g]'s Deep Sea Scale/Metal Powder already occupy, source: CalcDefenseStat,
# battle_util.c L7160-7189), tested via direct function calls per the testing-
# scope convention's preference for function-level tests over full battles where
# the mechanism allows it (both are pure, stateless damage-modifier reads).
# Assault Vest's move-restriction half genuinely requires the move-execution
# phase machinery (fail-at-execution via move_skipped, matching this project's
# established Disable pattern — see ItemManager.holds_assault_vest's own doc
# comment for why this is NOT a menu-legality filter), so that half uses a
# minimal single-turn battle.
#
# Sections:
#   S01 Eviolite — mid-evolution-line boost + fully-evolved/zero-evolution discriminators
#   S02 Assault Vest — SpDef-only damage reduction
#   S03 Assault Vest — status-move restriction (fail-at-execution)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_s01_eviolite()
	_test_s02_assault_vest_damage()
	_test_s03_assault_vest_status_restriction()

	var total := _pass + _fail
	print("m18s_test: %d/%d passed" % [_pass, total])
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

func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


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


func _make_tackle(power: int = 40) -> MoveData:
	var m := MoveData.new()
	m.move_name = "Tackle"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 0
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	return m


# ── S01: Eviolite — +50% Def AND SpDef if CanEvolve(species) ───────────────────

func _test_s01_eviolite() -> void:
	var eviolite := _load_item(494)
	var tackle := _make_tackle()  # physical
	var water_gun := _load_move(55)  # special
	_chk("S01.00 fixtures load", eviolite != null and water_gun != null)

	# Fixture check: PokemonRegistry.get_evolutions confirms Ivysaur(2) has a
	# further evolution (Venusaur), Venusaur(3) has none, Ditto(132) has none.
	_chk("S01.01 fixture check: Ivysaur(2) CanEvolve (has a further evolution)",
			not PokemonRegistry.get_evolutions(2).is_empty())
	_chk("S01.02 fixture check: Venusaur(3) is fully evolved (no further evolution)",
			PokemonRegistry.get_evolutions(3).is_empty())
	_chk("S01.03 fixture check: Ditto(132) has ZERO possible evolutions",
			PokemonRegistry.get_evolutions(132).is_empty())

	# Positive: Ivysaur (mid-evolution-line) holding Eviolite -> 1.5x reduction,
	# BOTH categories (unconditional on move.category, unlike Deep Sea Scale/
	# Metal Powder above it in the same function).
	var ivysaur := _make_mon("Ivysaur", 2, TypeChart.TYPE_GRASS)
	ivysaur.held_item = eviolite
	_chk("S01.04 Ivysaur+Eviolite: physical hits reduced 1.5x",
			ItemManager.defense_stat_modifier_uq412(ivysaur, tackle) == ItemManager.UQ412_CHOICE_MULT)
	_chk("S01.05 Ivysaur+Eviolite: special hits ALSO reduced 1.5x",
			ItemManager.defense_stat_modifier_uq412(ivysaur, water_gun) == ItemManager.UQ412_CHOICE_MULT)

	# Discriminator: Venusaur (fully evolved) holding Eviolite -> no boost at all.
	var venusaur := _make_mon("Venusaur", 3, TypeChart.TYPE_GRASS)
	venusaur.held_item = eviolite
	_chk("S01.06 discriminator: fully-evolved Venusaur+Eviolite -> NO boost (physical)",
			ItemManager.defense_stat_modifier_uq412(venusaur, tackle) == 4096)
	_chk("S01.07 discriminator: fully-evolved Venusaur+Eviolite -> NO boost (special)",
			ItemManager.defense_stat_modifier_uq412(venusaur, water_gun) == 4096)

	# Discriminator: Ditto (ZERO possible evolutions, a genuinely different
	# condition from "fully evolved") holding Eviolite -> also no boost, same
	# code path as the fully-evolved case (both produce an empty evolutions list).
	var ditto := _make_mon("Ditto", 132, TypeChart.TYPE_NORMAL)
	ditto.held_item = eviolite
	_chk("S01.08 discriminator: zero-evolution Ditto+Eviolite -> NO boost " +
			"(same non-boost outcome as fully-evolved, confirmed via the SAME " +
			"empty-list code path, not a separate special case)",
			ItemManager.defense_stat_modifier_uq412(ditto, tackle) == 4096)

	# Discriminator: no item at all -> no boost, regardless of species.
	var ivysaur_bare := _make_mon("IvysaurBare", 2, TypeChart.TYPE_GRASS)
	_chk("S01.09 discriminator: Ivysaur WITHOUT Eviolite -> no boost",
			ItemManager.defense_stat_modifier_uq412(ivysaur_bare, tackle) == 4096)


# ── S02: Assault Vest — +50% SpDef ONLY (special hits) ──────────────────────────

func _test_s02_assault_vest_damage() -> void:
	var vest := _load_item(503)
	var tackle := _make_tackle()  # physical
	var water_gun := _load_move(55)  # special
	_chk("S02.00 fixture loads", vest != null)

	var holder := _make_mon("Vested", 1, TypeChart.TYPE_NORMAL)
	holder.held_item = vest
	_chk("S02.01 Assault Vest holder: special hits reduced 1.5x",
			ItemManager.defense_stat_modifier_uq412(holder, water_gun) == ItemManager.UQ412_CHOICE_MULT)
	_chk("S02.02 discriminator: Assault Vest holder: physical hits UNAFFECTED",
			ItemManager.defense_stat_modifier_uq412(holder, tackle) == 4096)

	# Discriminator: no item -> no boost.
	var bare := _make_mon("Bare", 1, TypeChart.TYPE_NORMAL)
	_chk("S02.03 discriminator: no Assault Vest -> no boost (special)",
			ItemManager.defense_stat_modifier_uq412(bare, water_gun) == 4096)


# ── S03: Assault Vest — status-category moves are unusable (fail-at-execution) ──
#
# Source: CheckMoveLimitations's unusableMoves bitmask (battle_util.c L1622-1624)
# is a true menu-legality restriction in source; this project has no such
# architecture, so it's implemented via move_skipped at execution time, matching
# the established Disable pattern exactly (same signal, same early-return shape).

func _test_s03_assault_vest_status_restriction() -> void:
	var vest := _load_item(503)
	var swords_dance := _load_move(14)  # status
	var tackle := _make_tackle()        # damaging, not status
	_chk("S03.00 fixtures load", vest != null and swords_dance != null)
	_chk("S03.00b fixture check: Swords Dance category == 2 (status)",
			swords_dance.category == 2)

	# Positive: Assault Vest holder using a status move -> skipped.
	var p1 := _make_mon("Vested1", 1, TypeChart.TYPE_NORMAL)
	p1.held_item = vest
	p1.add_move(swords_dance)
	var p2 := _make_mon("Foe1", 1, TypeChart.TYPE_NORMAL, 300)
	p2.add_move(_make_tackle(5))

	var skipped_events := []
	var executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_skipped.connect(func(a, reason): skipped_events.push_back([a, reason]))
	bm.move_executed.connect(func(a, _d, _m, _dmg): executed_events.push_back(a))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("S03.01 Assault Vest holder's status move is skipped with reason " +
			"'assault_vest'",
			skipped_events.any(func(e): return e[0] == p1 and e[1] == "assault_vest"))
	_chk("S03.02 the status move never actually executed for p1",
			not executed_events.any(func(a): return a == p1))
	bm.queue_free()

	# Discriminator: WITHOUT Assault Vest, the same status move executes normally.
	var p3 := _make_mon("Bare1", 1, TypeChart.TYPE_NORMAL)
	p3.add_move(swords_dance)
	var p4 := _make_mon("Foe2", 1, TypeChart.TYPE_NORMAL, 300)
	p4.add_move(_make_tackle(5))

	var skipped_events2 := []
	var executed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_skipped.connect(func(a, reason): skipped_events2.push_back([a, reason]))
	bm2.move_executed.connect(func(a, _d, _m, _dmg): executed_events2.push_back(a))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)

	_chk("S03.03 discriminator: WITHOUT Assault Vest, Swords Dance executes normally",
			executed_events2.any(func(a): return a == p3))
	_chk("S03.04 discriminator: never skipped for 'assault_vest' without the item",
			not skipped_events2.any(func(e): return e[0] == p3 and e[1] == "assault_vest"))
	bm2.queue_free()

	# Discriminator: an Assault Vest holder using a NON-status (damaging) move is
	# NOT blocked — proves the restriction is category-scoped, not a full lockout.
	var p5 := _make_mon("Vested2", 1, TypeChart.TYPE_NORMAL)
	p5.held_item = vest
	p5.add_move(tackle)
	var p6 := _make_mon("Foe3", 1, TypeChart.TYPE_NORMAL, 300)
	p6.add_move(_make_tackle(5))

	var executed_events3 := []
	var skipped_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_skipped.connect(func(a, reason): skipped_events3.push_back([a, reason]))
	bm3.move_executed.connect(func(a, _d, _m, _dmg): executed_events3.push_back(a))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle(p5, p6)

	_chk("S03.05 discriminator: Assault Vest holder's DAMAGING move is NOT blocked",
			executed_events3.any(func(a): return a == p5))
	_chk("S03.06 discriminator: never skipped for 'assault_vest' on a non-status move",
			not skipped_events3.any(func(e): return e[0] == p5 and e[1] == "assault_vest"))
	bm3.queue_free()
