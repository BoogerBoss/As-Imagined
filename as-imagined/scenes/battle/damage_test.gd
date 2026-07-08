extends Node

# Milestone 2 verification: damage formula + type chart.
# Each test prints "PASS" or "FAIL  expected X..Y  got Z".
# Expected values computed manually from the ported formula — see comments.
# Source cross-references in DamageCalculator and TypeChart.
#
# Run: godot --headless --path /path/to/project scenes/battle/damage_test.tscn


var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== Milestone 2 Damage Verification ===")
	print("Source: src/battle_util.c CalculateBaseDamage/DoMoveDamageCalcVars/ApplyModifiersAfterDmgRoll")
	print("")

	# --- Set up test Pokémon at level 50, 0 IV / 0 EV ---
	# Charmander: Fire | Atk=57, SpAtk=65, SpDef=55
	var charmander := _make_mon("Charmander", [TypeChart.TYPE_FIRE], 39, 52, 43, 60, 50, 65)
	# Bulbasaur: Grass + Poison | Def=54, SpDef=70
	var bulbasaur  := _make_mon("Bulbasaur",
			[TypeChart.TYPE_GRASS, TypeChart.TYPE_POISON], 45, 49, 49, 65, 65, 45)
	# Squirtle: Water | SpAtk=55
	var squirtle   := _make_mon("Squirtle",   [TypeChart.TYPE_WATER], 44, 48, 65, 50, 64, 43)
	# Gengar: Ghost + Poison
	var gengar     := _make_mon("Gengar",
			[TypeChart.TYPE_GHOST, TypeChart.TYPE_POISON], 60, 65, 60, 130, 75, 110)

	var tackle    := _make_move("Tackle",    TypeChart.TYPE_NORMAL,   0, 35)  # Physical
	var ember     := _make_move("Ember",     TypeChart.TYPE_FIRE,     1, 40)  # Special
	var water_gun := _make_move("Water Gun", TypeChart.TYPE_WATER,    1, 40)  # Special

	# --- T1: Tackle (Normal/Physical/35) — Charmander → Bulbasaur ---
	# No STAB (Fire attacker, Normal move). Effectiveness 1.0× both types (no change).
	# Atk stat = floori(2*52*50/100.0)+5=57. Def stat = floori(2*49*50/100.0)+5=54.
	# base = 35*57*22 / 54 / 50 + 2 = 43890/54/50+2 = 812/50+2 = 18
	# roll{85-100}: 18*r/100 → [15,18]; ×1.0 twice → no change
	_check_range("T1 Tackle Char→Bulb (neutral, no STAB)",
			charmander, bulbasaur, tackle, 15, 18)

	# --- T2: Ember (Fire/Special/40) — Charmander → Bulbasaur ---
	# STAB 1.5×, effectiveness: Fire→Grass 2.0× then Fire→Poison 1.0×.
	# SpAtk stat = floori(2*60*50/100.0)+5=65. SpDef stat = floori(2*65*50/100.0)+5=70.
	# base = 40*65*22 / 70 / 50 + 2 = 57200/70/50+2 = 817/50+2 = 18
	# roll85:  18*85/100=15  → STAB (15*6144+2047)/4096=22 → ×2.0 (22*8192+2047)/4096=44 → ×1.0 →44
	# roll100: 18*100/100=18 → STAB (18*6144+2047)/4096=27 → ×2.0 (27*8192+2047)/4096=54 → ×1.0 →54
	_check_range("T2 Ember Char→Bulb (STAB + 2× Fire/Grass)",
			charmander, bulbasaur, ember, 44, 54)

	# --- T3: Water Gun (Water/Special/40) — Squirtle → Charmander ---
	# STAB 1.5×, effectiveness Water→Fire 2.0×, mono-type (no second application).
	# SpAtk stat = floori(2*50*50/100.0)+5=55. SpDef stat (Char) = floori(2*50*50/100.0)+5=55.
	# base = 40*55*22 / 55 / 50 + 2 = 48400/55/50+2 = 880/50+2 = 19
	# roll85:  19*85/100=16  → STAB (16*6144+2047)/4096=24 → ×2.0 (24*8192+2047)/4096=48
	# roll100: 19*100/100=19 → STAB (19*6144+2047)/4096=28 → ×2.0 (28*8192+2047)/4096=56
	_check_range("T3 WaterGun Sqtl→Char (STAB + 2× Water/Fire)",
			squirtle, charmander, water_gun, 48, 56)

	# --- T4: Tackle → Gengar (Normal vs Ghost = immune, 0 damage) ---
	var r4 := DamageCalculator.calculate(charmander, gengar, tackle)
	_check_exact("T4 Tackle Char→Gengar (Normal→Ghost immune)", r4["damage"], 0)
	_check_float("T4 effectiveness == 0.0", r4["effectiveness"], 0.0)

	# --- T5: Forced crit — Tackle Charmander → Bulbasaur ---
	# Crit 1.5× before roll; no STAB; 1.0× type twice (no change).
	# base=18 → crit (18*6144+2047)/4096=27 → roll85: 27*85/100=22 → roll100: 27
	_check_range("T5 Tackle Char→Bulb (forced crit 1.5×)",
			charmander, bulbasaur, tackle, 22, 27, true)

	# --- T6: Pinned roll values — exact expected damage from integer path ---
	# Tackle roll=100: base=18 → roll=18 → no STAB → ×1.0 ×1.0 → 18
	# Tackle roll=85:  base=18 → roll=15 → no STAB → ×1.0 ×1.0 → 15
	# Ember roll=100: base=18 → roll=18 → STAB 27 → ×2.0 54 → ×1.0 54
	# Ember roll=85:  base=18 → roll=15 → STAB 22 → ×2.0 44 → ×1.0 44
	var r6a := DamageCalculator.calculate(charmander, bulbasaur, tackle, 100, false)
	_check_exact("T6a Tackle roll=100 (expect 18)", r6a["damage"], 18)
	var r6b := DamageCalculator.calculate(charmander, bulbasaur, tackle, 85, false)
	_check_exact("T6b Tackle roll=85  (expect 15)", r6b["damage"], 15)
	var r6c := DamageCalculator.calculate(charmander, bulbasaur, ember, 100, false)
	_check_exact("T6c Ember roll=100  (expect 54)", r6c["damage"], 54)
	var r6d := DamageCalculator.calculate(charmander, bulbasaur, ember, 85, false)
	_check_exact("T6d Ember roll=85   (expect 44)", r6d["damage"], 44)

	# --- T7: Type chart macro substitutions (GEN_LATEST config) ---
	# Source: src/data/types_info.h defines STL_RS, PSN_RS, BUG_RS, PSY_RS, FIR_RS
	_check_float("T7a Bug→Poison (PSN_RS=0.5, not Gen1's 2.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_BUG,     [TypeChart.TYPE_POISON]),  0.5)
	_check_float("T7b Ghost→Steel (STL_RS=1.0, not pre-Gen6's 0.5)",
			TypeChart.get_effectiveness(TypeChart.TYPE_GHOST,   [TypeChart.TYPE_STEEL]),   1.0)
	_check_float("T7c Ghost→Psychic (PSY_RS=2.0, not Gen1's 0.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_GHOST,   [TypeChart.TYPE_PSYCHIC]), 2.0)
	_check_float("T7d Ice→Fire (FIR_RS=0.5, not Gen1's 1.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_ICE,     [TypeChart.TYPE_FIRE]),    0.5)
	_check_float("T7e Dragon→Fairy (immune 0.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_DRAGON,  [TypeChart.TYPE_FAIRY]),   0.0)
	_check_float("T7f Electric→Ground (immune 0.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_ELECTRIC,[TypeChart.TYPE_GROUND]),  0.0)
	_check_float("T7g Poison→Bug (BUG_RS=1.0, not Gen1's 2.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_POISON,  [TypeChart.TYPE_BUG]),     1.0)

	# --- T8: Dual-type 4.0× stacking (Electric vs Water/Flying) ---
	_check_float("T8 Electric vs Water/Flying (2.0×2.0=4.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_ELECTRIC,
					[TypeChart.TYPE_WATER, TypeChart.TYPE_FLYING]), 4.0)

	# --- T9: NVE stacking 0.25× (Fire vs Water/Rock) ---
	_check_float("T9 Fire vs Water/Rock (0.5×0.5=0.25)",
			TypeChart.get_effectiveness(TypeChart.TYPE_FIRE,
					[TypeChart.TYPE_WATER, TypeChart.TYPE_ROCK]), 0.25)

	# --- T10: Mixed super/NVE = 1.0× (Fire vs Water/Grass) ---
	_check_float("T10 Fire vs Water/Grass (0.5×2.0=1.0)",
			TypeChart.get_effectiveness(TypeChart.TYPE_FIRE,
					[TypeChart.TYPE_WATER, TypeChart.TYPE_GRASS]), 1.0)

	# --- T11: Water Gun (Water/Special/40) — Squirtle → dual Water/Grass (combined 0.25×) ---
	# Water→Water = 0.5×, Water→Grass = 0.5×.  (Water→Rock would be 2.0×, not NVE.)
	# Source method: accumulate both modifiers in UQ4.12 space via uq4_12_multiply (half-UP),
	# then apply combined modifier once via uq4_12_multiply_by_int_half_down (half-DOWN).
	# Combined: uq4_12_multiply(2048, 2048) = (4194304+2048)>>12 = 1024 = UQ_4_12(0.25).
	# SpDef base 100 → stat = floori(2*100*50/100.0)+5 = 105.
	# base = 40*55*22 / 105 / 50 + 2 = 48400/105/50+2 = 460/50+2 = 11
	# roll85:  11*85/100=9  → STAB (9*6144+2047)/4096=13 → combined (13*1024+2047)/4096=3  (3.248…→3)
	# roll91:  11*91/100=10 → STAB (10*6144+2047)/4096=15 → combined (15*1024+2047)/4096=4  (3.748…→4)
	# roll100: 11*100/100=11 → STAB (11*6144+2047)/4096=16 → combined (16*1024+2047)/4096=4  (4.0→4)
	# Note: per-type application (0.5 then 0.5 separately) gives 3 for roll91 — the roll91 test
	# confirms we are using the source's combined-then-apply method, not per-type.
	var watergrass := _make_mon("WaterGrass",
			[TypeChart.TYPE_WATER, TypeChart.TYPE_GRASS], 80, 80, 80, 80, 100, 80)
	var r11a := DamageCalculator.calculate(squirtle, watergrass, water_gun, 100, false)
	_check_exact("T11a WaterGun Sqtl→Water/Grass roll=100 (expect 4)", r11a["damage"], 4)
	var r11b := DamageCalculator.calculate(squirtle, watergrass, water_gun, 85, false)
	_check_exact("T11b WaterGun Sqtl→Water/Grass roll=85  (expect 3)", r11b["damage"], 3)
	var r11c := DamageCalculator.calculate(squirtle, watergrass, water_gun, 91, false)
	_check_exact("T11c WaterGun Sqtl→Water/Grass roll=91  (expect 4, not 3)", r11c["damage"], 4)
	_check_float("T11 effectiveness == 0.25", r11a["effectiveness"], 0.25)

	print("")
	print("=== Results: " + str(_pass) + " passed, " + str(_fail) + " failed ===")
	get_tree().quit(0 if _fail == 0 else 1)


# --- Helpers ---

func _check_range(label: String, attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, lo: int, hi: int, force_crit: bool = false) -> void:
	for roll in range(85, 101):
		var r := DamageCalculator.calculate(attacker, defender, move, roll, force_crit)
		if r["damage"] < lo or r["damage"] > hi:
			print("FAIL  " + label + "  roll=" + str(roll)
					+ " expected [" + str(lo) + "," + str(hi) + "] got " + str(r["damage"]))
			_fail += 1
			return
	print("PASS  " + label + "  [" + str(lo) + "," + str(hi) + "]")
	_pass += 1


func _check_exact(label: String, got: int, expected: int) -> void:
	if got == expected:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  expected=" + str(expected) + " got=" + str(got))
		_fail += 1


func _check_float(label: String, got: float, expected: float) -> void:
	if absf(got - expected) < 0.001:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  expected=" + str(expected) + " got=" + str(got))
		_fail += 1


func _make_mon(name: String, types: Array[int], base_hp: int, base_atk: int, base_def: int,
		base_satk: int, base_sdef: int, base_spd: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name    = name
	sp.types           = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_satk
	sp.base_sp_defense = base_sdef
	sp.base_speed      = base_spd
	sp.abilities       = []
	sp.learnset        = []
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY)  # [M18.5h-1] pinned neutral -- exact-value assertions predate Nature


func _make_move(name: String, type_id: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name          = name
	m.type               = type_id
	m.category           = category  # 0=Physical, 1=Special
	m.power              = power
	m.accuracy           = 0         # not checked in M2
	m.pp                 = 10
	m.priority           = 0
	m.critical_hit_stage = 0
	return m
