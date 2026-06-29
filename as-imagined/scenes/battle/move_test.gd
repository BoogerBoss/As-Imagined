extends Node

# Milestone 4 Tier-1 verification: move data pipeline and freeze-thaw hooks.
# Tests three things independently:
#   1. MoveRegistry loads .tres correctly — spot-check key fields against source values.
#   2. DamageCalculator produces correct results with loaded MoveData — covers
#      STAB, super-effective, not-very-effective, and neutral-no-STAB hits.
#   3. StatusManager thaw hooks fire correctly (target-thaw on Fire hit; user-thaw
#      hook wired but no Tier-1 move exercises it — documented in decisions.md).
#
# Expected values are derived from the formula below, NOT copied from .tres:
#   base = power * atk_staged * (2*level/5+2) / def_staged / 50 + 2
#   → roll → STAB (×1.5 if match) → type eff (combined UQ4.12, applied once)
#
# Source: pokeemerald_expansion (GEN_LATEST config)
#
# Run: godot --headless --path /path/to/project scenes/battle/move_test.tscn


var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== Milestone 4 Tier-1: Move Data Pipeline & Freeze-Thaw Hooks ===")
	print("")

	# ─── Test Pokémon ─────────────────────────────────────────────────────────
	# Charmander L50: Fire | base hp=39 atk=52 def=43 spatk=60 spdef=50 spd=65
	#   hp=99  atk=57 def=48 spatk=65 sdef=55
	var charmander := _make_mon("Charmander", [TypeChart.TYPE_FIRE], 39, 52, 43, 60, 50, 65)

	# Squirtle L50: Water | base hp=44 atk=48 def=65 spatk=50 spdef=64 spd=43
	#   hp=104 atk=53 def=70 spatk=55 sdef=69
	var squirtle := _make_mon("Squirtle", [TypeChart.TYPE_WATER], 44, 48, 65, 50, 64, 43)

	# ─── SECTION 1: Move data spot-checks ────────────────────────────────────
	print("--- Section 1: MoveRegistry / .tres data integrity ---")

	# Flamethrower (id=53): Fire/Special/90/100/pp=15, no thaws_user
	var fthr := MoveRegistry.get_move(53)
	_check_notnull("S1.flamethrower loaded",           fthr)
	_check_exact("S1.flamethrower type=FIRE(11)",      fthr.type,     TypeChart.TYPE_FIRE)
	_check_exact("S1.flamethrower category=Special(1)", fthr.category, 1)
	_check_exact("S1.flamethrower power=90",            fthr.power,    90)
	_check_exact("S1.flamethrower accuracy=100",        fthr.accuracy, 100)
	_check_exact("S1.flamethrower pp=15",               fthr.pp,       15)
	_check_exact("S1.flamethrower thaws_user=false",    int(fthr.thaws_user), 0)

	# Karate Chop (id=2): Fighting/Physical/50/100/pp=25, crit_stage=1
	var kchop := MoveRegistry.get_move(2)
	_check_notnull("S1.karate_chop loaded",              kchop)
	_check_exact("S1.karate_chop type=FIGHTING(2)",      kchop.type,              TypeChart.TYPE_FIGHTING)
	_check_exact("S1.karate_chop category=Physical(0)",  kchop.category,          0)
	_check_exact("S1.karate_chop power=50",              kchop.power,             50)
	_check_exact("S1.karate_chop pp=25",                 kchop.pp,                25)
	_check_exact("S1.karate_chop critical_hit_stage=1",  kchop.critical_hit_stage, 1)
	_check_exact("S1.karate_chop makes_contact=true",    int(kchop.makes_contact),  1)

	# Water Gun (id=55): Water/Special/40/100/pp=25
	var wgun := MoveRegistry.get_move(55)
	_check_notnull("S1.water_gun loaded",           wgun)
	_check_exact("S1.water_gun type=WATER(12)",     wgun.type,     TypeChart.TYPE_WATER)
	_check_exact("S1.water_gun category=Special(1)", wgun.category, 1)
	_check_exact("S1.water_gun power=40",            wgun.power,    40)

	# Aerial Ace (id=332): Flying/Physical/60/always-hits(acc=0)/pp=20
	var ace := MoveRegistry.get_move(332)
	_check_notnull("S1.aerial_ace loaded",               ace)
	_check_exact("S1.aerial_ace type=FLYING(3)",          ace.type,     TypeChart.TYPE_FLYING)
	_check_exact("S1.aerial_ace category=Physical(0)",    ace.category, 0)
	_check_exact("S1.aerial_ace power=60",                ace.power,    60)
	_check_exact("S1.aerial_ace accuracy=0 (always hits)", ace.accuracy, 0)

	# Quick Attack (id=98): Normal/Physical/40/100/pp=30/priority=1
	var qatk := MoveRegistry.get_move(98)
	_check_notnull("S1.quick_attack loaded",            qatk)
	_check_exact("S1.quick_attack priority=1",           qatk.priority,    1)
	_check_exact("S1.quick_attack makes_contact=true",   int(qatk.makes_contact), 1)

	# Swift (id=129): Normal/Special/60/always-hits/pp=20
	var swift := MoveRegistry.get_move(129)
	_check_notnull("S1.swift loaded",                  swift)
	_check_exact("S1.swift category=Special(1)",        swift.category, 1)
	_check_exact("S1.swift accuracy=0 (always hits)",   swift.accuracy, 0)

	# ─── SECTION 2: Damage calculation with loaded moves ─────────────────────
	print("")
	print("--- Section 2: Damage formula with loaded MoveData ---")

	# T2a: STAB + super-effective
	# Squirtle (Water) uses Water Gun (Water/Sp/40) vs Charmander (Fire)
	# SpAtk=55, Charmander SpDef=55. Water→Fire = 2×.
	# base = 40*55*22/55/50+2 = 19
	# roll=100 → 19 → STAB: (19*6144+2047)/4096=28 → 2×: (28*8192+2047)/4096=56
	var r2a := DamageCalculator.calculate(squirtle, charmander, wgun, 100, false)
	_check_exact("T2a STAB+SE: Water Gun Sqtl→Char (expect 56)", r2a["damage"], 56)

	# T2b: STAB + not-very-effective
	# Squirtle (Water) uses Surf (Water/Sp/90) vs Squirtle (Water)
	# SpAtk=55, SpDef=69. Water→Water = 0.5×.
	# base = 90*55*22/69/50+2 = 33
	# roll=100 → 33 → STAB: (33*6144+2047)/4096=49 → 0.5×: (49*2048+2047)/4096=24
	var surf := MoveRegistry.get_move(57)
	var sq2  := _clone(squirtle)   # separate instance as defender
	var r2b  := DamageCalculator.calculate(squirtle, sq2, surf, 100, false)
	_check_exact("T2b STAB+NVE: Surf Sqtl→Sqtl (expect 24)", r2b["damage"], 24)

	# T2c: Neutral, no STAB
	# Charmander (Fire) uses Scratch (Normal/Ph/40) vs Squirtle (Water)
	# Normal→Water = 1×, Fire≠Normal so no STAB.
	# Charmander Atk=57, Squirtle Def=70.
	# base = 40*57*22/70/50+2 = 50160/70/50+2 = 716/50+2 = 16
	# roll=100 → 16 (no STAB, neutral eff)
	var scratch := MoveRegistry.get_move(10)
	var r2c     := DamageCalculator.calculate(charmander, squirtle, scratch, 100, false)
	_check_exact("T2c Neutral no-STAB: Scratch Char→Sqtl (expect 16)", r2c["damage"], 16)

	# T2d: Super-effective, no STAB
	# Charmander (Fire) uses Surf (Water/Sp/90) vs Charmander (Fire)
	# Fire≠Water so no STAB. Water→Fire = 2×.
	# SpAtk=65, Charmander SpDef=55.
	# base = 90*65*22/55/50+2 = 129000/55/50+2 = 2345/50+2 = 48
	# roll=100 → 48 → 2×: (48*8192+2047)/4096=96
	var ch2 := _clone(charmander)
	var r2d := DamageCalculator.calculate(charmander, ch2, surf, 100, false)
	_check_exact("T2d SE no-STAB: Surf Char→Char (expect 96)", r2d["damage"], 96)

	# Sanity: roll=85 on T2a (lowest roll)
	# base=19 → 85%: 19*85/100=16 → STAB: (16*6144+2047)/4096=24 → 2×: (24*8192+2047)/4096=48
	var r2a_lo := DamageCalculator.calculate(squirtle, charmander, wgun, 85, false)
	_check_exact("T2a roll=85 (expect 48)", r2a_lo["damage"], 48)

	# ─── SECTION 3: Freeze-thaw hooks ────────────────────────────────────────
	print("")
	print("--- Section 3: Freeze-thaw hooks ---")

	# T3a: Target-thaw — Fire-type damaging move clears freeze on the defender.
	# Source: StatusManager.check_target_thaw (wrapping CanFireMoveThawTarget L11036)
	#   condition: move.type==FIRE && move.power>0 && damage>0 && defender.status==FREEZE
	# Charmander uses Flamethrower (Fire/Sp/90) vs frozen Squirtle.
	# Damage: SpAtk=65, SpDef=69. STAB. Fire→Water 0.5×.
	# base=39 → r100=39 → stab=58 → 0.5×=29. damage=29 > 0 → thaw fires.
	var sq_frozen := _clone(squirtle)
	StatusManager.try_apply_status(sq_frozen, BattlePokemon.STATUS_FREEZE)
	_check_exact("T3a setup: Squirtle is frozen", sq_frozen.status, BattlePokemon.STATUS_FREEZE)

	var r3a   := DamageCalculator.calculate(charmander, sq_frozen, fthr, 100, false)
	var dmg3a: int = r3a["damage"]
	_check_exact("T3a Flamethrower damage > 0 (expect 29)", dmg3a, 29)

	var thawed_a := StatusManager.check_target_thaw(sq_frozen, fthr, dmg3a)
	_check_exact("T3a check_target_thaw returns true",       int(thawed_a),       1)
	_check_exact("T3a Squirtle status cleared to NONE",      sq_frozen.status,    BattlePokemon.STATUS_NONE)

	# T3b: Non-Fire move does NOT thaw frozen target.
	# Squirtle uses Water Gun (Water/Sp/40) vs frozen Squirtle.
	var sq_frozen2 := _clone(squirtle)
	StatusManager.try_apply_status(sq_frozen2, BattlePokemon.STATUS_FREEZE)
	var r3b      := DamageCalculator.calculate(squirtle, sq_frozen2, wgun, 100, false)
	var thawed_b := StatusManager.check_target_thaw(sq_frozen2, wgun, r3b["damage"])
	_check_exact("T3b Water Gun does NOT thaw (returns false)", int(thawed_b),     0)
	_check_exact("T3b status remains FREEZE",                   sq_frozen2.status, BattlePokemon.STATUS_FREEZE)

	# T3c: Fire move with damage=0 (immunity) does NOT thaw.
	# Artificial: pass damage=0 explicitly to verify the guard.
	var sq_frozen3 := _clone(squirtle)
	StatusManager.try_apply_status(sq_frozen3, BattlePokemon.STATUS_FREEZE)
	var thawed_c := StatusManager.check_target_thaw(sq_frozen3, fthr, 0)
	_check_exact("T3c damage=0 (immunity) does NOT thaw", int(thawed_c), 0)

	# T3d: User-thaw hook — check_user_thaw returns false for any Tier-1 move
	# because no Tier-1 move has thaws_user=true. Wired for future moves.
	# Source: StatusManager.check_user_thaw (wrapping CancelerThaw L586)
	var ch_frozen := _clone(charmander)
	StatusManager.try_apply_status(ch_frozen, BattlePokemon.STATUS_FREEZE)
	var thawed_d := StatusManager.check_user_thaw(ch_frozen, fthr)
	_check_exact("T3d Flamethrower.thaws_user=false → check_user_thaw=false", int(thawed_d), 0)
	_check_exact("T3d attacker status unchanged (still FREEZE)", ch_frozen.status, BattlePokemon.STATUS_FREEZE)

	# T3e: User-thaw with Flame Wheel (thaws_user=true) — closes the M4 gap.
	# A frozen attacker using Flame Wheel must thaw before acting this turn.
	# Source: StatusManager.check_user_thaw (wrapping CancelerThaw L586)
	var flame_wheel := MoveRegistry.get_move(172)
	var ch_frozen2 := _clone(charmander)
	StatusManager.try_apply_status(ch_frozen2, BattlePokemon.STATUS_FREEZE)
	var thawed_e := StatusManager.check_user_thaw(ch_frozen2, flame_wheel)
	_check_exact("T3e Flame Wheel.thaws_user=true → check_user_thaw=true", int(thawed_e), 1)
	_check_exact("T3e attacker status cleared to NONE", ch_frozen2.status, BattlePokemon.STATUS_NONE)

	# ─── SECTION 4: BattleManager integration — freeze-thaw wiring ───────────────
	print("")
	print("--- Section 4: BattleManager freeze-thaw wiring (integration) ---")

	# T4a: Frozen attacker using Flame Wheel — full BattleManager turn wiring.
	# Verifies that _phase_pre_move_checks skips the freeze canceler (attacker can move),
	# then _phase_move_execution's check_user_thaw fires pokemon_thawed.
	# T3e tests check_user_thaw in isolation; T4a tests the BattleManager phase wiring —
	# the gap that existed before the !MoveThawsUser gate was ported into pre_move_check.
	# Source: battle_move_resolution.c L172 !MoveThawsUser gate + CancelerThaw L586-622.
	var flame_wheel4a := MoveRegistry.get_move(172)
	var wgun4a        := MoveRegistry.get_move(55)
	var atk4a := _make_mon("FrzChar", [TypeChart.TYPE_FIRE],  39, 52, 43, 60, 50, 100)
	var def4a := _make_mon("FrzSqtl", [TypeChart.TYPE_WATER], 44, 48, 65, 50, 64, 50)
	atk4a.add_move(flame_wheel4a)
	def4a.add_move(wgun4a)
	StatusManager.try_apply_status(atk4a, BattlePokemon.STATUS_FREEZE)
	def4a.current_hp = 1  # Flame Wheel KOs def4a on turn 1 — keeps battle finite
	var thaw_count4a    := [0]
	var thawed_correct4a := [false]
	var fw_damage4a     := [0]
	var bm4a := BattleManager.new()
	add_child(bm4a)
	bm4a.pokemon_thawed.connect(func(mon: BattlePokemon):
		thaw_count4a[0] += 1
		thawed_correct4a[0] = (mon == atk4a))
	bm4a.move_executed.connect(func(exec_atk: BattlePokemon, _exec_def: BattlePokemon,
			mv: MoveData, dmg: int):
		if mv == flame_wheel4a and exec_atk == atk4a:
			fw_damage4a[0] = dmg)
	bm4a.start_battle(atk4a, def4a)
	bm4a.queue_free()
	_check_exact("T4a pokemon_thawed fired exactly once",             thaw_count4a[0],          1)
	_check_exact("T4a thawed mon is the frozen attacker",             int(thawed_correct4a[0]), 1)
	_check_exact("T4a attacker status NONE after turn",               atk4a.status,             BattlePokemon.STATUS_NONE)
	_check_exact("T4a Flame Wheel dealt damage > 0 (attacker acted)", int(fw_damage4a[0] > 0),  1)

	# ─── RESULTS ──────────────────────────────────────────────────────────────
	print("")
	print("=== Results: " + str(_pass) + " passed, " + str(_fail) + " failed ===")
	get_tree().quit(0 if _fail == 0 else 1)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _check_exact(label: String, got: int, expected: int) -> void:
	if got == expected:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  expected=" + str(expected) + " got=" + str(got))
		_fail += 1


func _check_notnull(label: String, obj: Object) -> void:
	if obj != null:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  (got null)")
		_fail += 1


func _make_mon(name: String, types: Array[int], base_hp: int, base_atk: int,
		base_def: int, base_satk: int, base_sdef: int, base_spd: int) -> BattlePokemon:
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
	return BattlePokemon.from_species(sp, 50)


func _clone(mon: BattlePokemon) -> BattlePokemon:
	var bp := BattlePokemon.from_species(mon.species, mon.level)
	bp.status          = mon.status
	bp.sleep_turns     = mon.sleep_turns
	bp.toxic_counter   = mon.toxic_counter
	bp.confusion_turns = mon.confusion_turns
	bp.stat_stages     = mon.stat_stages.duplicate()
	return bp
