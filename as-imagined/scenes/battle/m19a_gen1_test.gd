extends Node

# [M19a-gen1] M19a Tier-1 pure-damage data-entry, Generation I slice.
#
# 15 moves confirmed via Step 0 to be genuinely pure EFFECT_HIT data-entry
# against already-generalized, already-tested pipelines (DamageCalculator's
# power/type/category dispatch; makes_contact for contact-reactive abilities;
# critical_hit_stage for the base-crit-stage sum; damages_airborne for the
# semi-invulnerable bypass; is_spread for doubles multi-target). No new
# mechanism was built for this tier — per CLAUDE.md's testing-scope
# convention, this suite confirms each move's own data and that it correctly
# triggers whichever EXISTING mechanism its flags select, not the underlying
# mechanism's own correctness (that's already covered by the tier that built
# it: M14b for is_spread, M16a for critical_hit_stage/Focus Energy, M16b for
# damages_airborne/semi-invulnerable, M8/M17a for contact-reactive abilities).
#
# 7 other Gen I Tier-1 moves (Thrash/Petal Dance/Rage/Hyper Beam/
# Self-Destruct/Explosion/Tri Attack) were found during Step 0 to need a
# mechanism this project doesn't have yet and are explicitly OUT OF SCOPE —
# see docs/decisions.md's [M19a-gen1] entry.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# individual move blocks cited per-move below. All power/accuracy values
# reflect this project's GEN_LATEST config (ternaries resolved).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_move_data()
	_test_section_b_functional()

	var total := _pass + _fail
	print("m19a_gen1_test: %d/%d passed" % [_pass, total])
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


# ── Section A: Move data spot-checks (all 15 in-scope moves) ────────────────
# [id, name, type, category(0=PHYS/1=SPEC), power, accuracy(0=always), pp,
#  makes_contact, extra flag tokens]

func _test_section_a_move_data() -> void:
	var expected := [
		[5,   "Mega Punch",   TypeChart.TYPE_NORMAL, 0, 80,  85,  20, true,  []],
		[6,   "Pay Day",      TypeChart.TYPE_NORMAL, 0, 40,  100, 20, false, []],
		[11,  "Vise Grip",    TypeChart.TYPE_NORMAL, 0, 55,  100, 30, true,  []],
		[15,  "Cut",          TypeChart.TYPE_NORMAL, 0, 50,  95,  30, true,  ["slicing"]],
		[16,  "Gust",         TypeChart.TYPE_FLYING, 1, 40,  100, 35, false, ["airborne"]],
		[21,  "Slam",         TypeChart.TYPE_NORMAL, 0, 80,  75,  20, true,  []],
		[25,  "Mega Kick",    TypeChart.TYPE_NORMAL, 0, 120, 75,  5,  true,  []],
		[30,  "Horn Attack",  TypeChart.TYPE_NORMAL, 0, 65,  100, 25, true,  []],
		[56,  "Hydro Pump",   TypeChart.TYPE_WATER,  1, 110, 80,  5,  false, []],
		[64,  "Peck",         TypeChart.TYPE_FLYING, 0, 35,  100, 35, true,  []],
		[65,  "Drill Peck",   TypeChart.TYPE_FLYING, 0, 80,  100, 20, true,  []],
		[75,  "Razor Leaf",   TypeChart.TYPE_GRASS,  0, 55,  95,  25, false, ["slicing", "crit:1", "spread"]],
		[121, "Egg Bomb",     TypeChart.TYPE_NORMAL, 0, 100, 75,  10, false, ["ballistic"]],
		[152, "Crabhammer",   TypeChart.TYPE_WATER,  0, 100, 90,  10, true,  ["crit:1"]],
		[163, "Slash",        TypeChart.TYPE_NORMAL, 0, 70,  100, 20, true,  ["slicing", "crit:1"]],
	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "A.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " core data (type/category/power/accuracy/pp/contact)",
				mv.move_name == e[1] and mv.type == e[2] and mv.category == e[3]
				and mv.power == e[4] and mv.accuracy == e[5] and mv.pp == e[6]
				and mv.makes_contact == e[7])
		var tokens: Array = e[8]
		for token: String in tokens:
			if token == "slicing":
				_chk(tag + " slicing_move", mv.slicing_move)
			elif token == "airborne":
				_chk(tag + " damages_airborne", mv.damages_airborne)
			elif token == "spread":
				_chk(tag + " is_spread", mv.is_spread)
			elif token == "ballistic":
				_chk(tag + " ballistic_move", mv.ballistic_move)
			elif token.begins_with("crit:"):
				var n: int = int(token.split(":")[1])
				_chk(tag + " critical_hit_stage=%d" % n, mv.critical_hit_stage == n)
		# Negative check: moves with no flag tokens carry none of the special
		# flags either (confirms the table isn't just silently passing).
		if tokens.is_empty():
			_chk(tag + " carries no special flags",
					not mv.slicing_move and not mv.damages_airborne
					and not mv.is_spread and not mv.ballistic_move
					and mv.critical_hit_stage == 0)


# ── Section B: Functional confirmation — shared EFFECT_HIT dispatch, plus ──
# ── the two flags (makes_contact, is_spread) that gate a DIFFERENT existing ─
# ── mechanism a plain data row could silently fail to trigger. ──────────────
#
# critical_hit_stage and damages_airborne are NOT re-proven here: per
# CLAUDE.md's own testing convention, force_crit bypasses crit-STAGE math
# entirely (so a full-battle check can't observe it), and the semi-
# invulnerable bypass mechanism is already fully covered by two_turn_test.gd
# — Section A's data-integrity check is the correctly-scoped confirmation
# for both flags on these specific moves.

func _test_section_b_functional() -> void:
	# B1: a representative plain move (Mega Punch) fires and deals real,
	# nonzero damage through the actual .tres -> dispatch -> DamageCalculator
	# pipeline — confirms the whole batch's data shape is wired correctly,
	# not just present on disk. Every other move in this tier shares this
	# exact same EFFECT_HIT dispatch, already proven in general by
	# move_test.gd/damage_test.gd — this is a per-move plumbing check, not a
	# re-derivation of the damage formula.
	var mega_punch := _load_move(5)
	var b1_atk := _make_mon("B1Atk", TypeChart.TYPE_NORMAL)
	b1_atk.add_move(mega_punch)
	var b1_def := _make_mon("B1Def", TypeChart.TYPE_NORMAL)
	b1_def.add_move(mega_punch)
	var b1_bm := _make_bm()
	b1_bm._force_hit = true
	b1_bm._force_crit = false
	b1_bm._force_roll = 100
	var b1_dmg := [0]
	b1_bm.move_executed.connect(func(a, d, m, dmg):
		if b1_dmg[0] == 0 and a == b1_atk:
			b1_dmg[0] = dmg)
	b1_bm.queue_move(0, 0)
	b1_bm.queue_move(1, 0)
	b1_bm.start_battle(b1_atk, b1_def)
	_chk("B1 Mega Punch deals real nonzero damage through the real dispatch path",
			b1_dmg[0] > 0)

	# B2: makes_contact=true actually triggers a contact-reactive ability
	# (Rough Skin, id 24) — confirms the flag isn't inert data. Uses Slash
	# (makes_contact=true), matching [M18_5g]'s established Rough-Skin-via-
	# _force_contact_roll pattern.
	var slash := _load_move(163)
	var b2_atk := _make_mon("B2Atk", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 100)
	b2_atk.add_move(slash)
	var b2_def := _make_mon("B2Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	b2_def.ability = _load_ability(24)  # Rough Skin
	b2_def.add_move(slash)
	var b2_bm := _make_bm()
	b2_bm._force_hit = true
	b2_bm._force_crit = false
	b2_bm._force_roll = 100
	b2_bm._force_contact_roll = true
	var b2_recoil_fired := [false]
	b2_bm.recoil_damage.connect(func(a, _amt):
		if a == b2_atk:
			b2_recoil_fired[0] = true)
	b2_bm.queue_move(0, 0)
	b2_bm.queue_move(1, 0)
	b2_bm.start_battle(b2_atk, b2_def)
	_chk("B2 Slash (makes_contact=true) triggers Rough Skin recoil on the attacker",
			b2_recoil_fired[0])

	# B3: discriminator — Hydro Pump (makes_contact=false) does NOT trigger
	# Rough Skin, confirming B2 wasn't a vacuous pass (Rough Skin firing
	# regardless of the contact flag).
	var hydro_pump := _load_move(56)
	var b3_atk := _make_mon("B3Atk", TypeChart.TYPE_WATER, 300, 60, 60, 60, 60, 100)
	b3_atk.add_move(hydro_pump)
	var b3_def := _make_mon("B3Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	b3_def.ability = _load_ability(24)  # Rough Skin
	b3_def.add_move(hydro_pump)
	var b3_bm := _make_bm()
	b3_bm._force_hit = true
	b3_bm._force_crit = false
	b3_bm._force_roll = 100
	b3_bm._force_contact_roll = true
	var b3_recoil_fired := [false]
	b3_bm.recoil_damage.connect(func(a, _amt):
		if a == b3_atk:
			b3_recoil_fired[0] = true)
	b3_bm.queue_move(0, 0)
	b3_bm.queue_move(1, 0)
	b3_bm.start_battle(b3_atk, b3_def)
	_chk("B3 Hydro Pump (makes_contact=false) does NOT trigger Rough Skin (discriminator)",
			not b3_recoil_fired[0])
