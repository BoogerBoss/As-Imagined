extends Node

# [M19-bucket1] Bulk move implementation, Bucket 1 (pure damage, zero
# additional effect), per docs/m19_subtier_plan.md's mechanism-based
# re-bucketing (`[M19-rescope]`).
#
# Of the 67 moves the plan classified into Bucket 1, Step 0 individually
# re-verified every one against moves_info.h (not trusting the classifier's
# own bucketing blindly, matching [M19a-gen1]'s precedent). 61 confirmed
# genuinely pure EFFECT_HIT / zero-additionalEffects data-entry against
# already-generalized pipelines (DamageCalculator's power/type/category
# dispatch; makes_contact/punching_move/biting_move/sound_move/slicing_move/
# ballistic_move/pulse_move for ability hooks; critical_hit_stage/
# always_critical_hit for crit math; damages_airborne for the semi-
# invulnerable bypass; is_spread for doubles multi-target; priority for turn
# order). 6 were found to need a mechanism this project doesn't have and are
# explicitly OUT OF SCOPE — see docs/decisions.md's [M19-bucket1] entry:
#   Chip Away(498)/Sacred Sword(533)/Darkest Lariat(626) — ignoresTargetDefenseEvasionStages
#   Sunsteel Strike(667)/Moongeist Beam(668) — ignoresTargetAbility
#   Blood Moon(829) — cantUseTwice
#
# critical_hit_stage/damages_airborne/priority are NOT re-proven functionally
# here, matching CLAUDE.md's testing-scope convention already established by
# [M19a-gen1]: force_crit bypasses crit-STAGE math entirely, the semi-
# invulnerable bypass is already covered by two_turn_test.gd, and general
# priority-ordering is already covered by battle_test.gd — Section A's data-
# integrity check is the correctly-scoped confirmation for all three on these
# specific moves.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h. All
# power/accuracy/critical_hit_stage values reflect this project's GEN_LATEST
# config (every ternary resolved to its highest-gen branch).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_move_data()
	_test_section_b_functional()

	var total := _pass + _fail
	print("m19_bucket1_test: %d/%d passed" % [_pass, total])
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


# ── Section A: Move data spot-checks (all 61 in-scope moves) ────────────────
# [id, name, type, category(0=PHYS/1=SPEC), power, accuracy(0=always), pp,
#  makes_contact, extra flag tokens]

func _test_section_a_move_data() -> void:
	var expected := [
		[177, "Aeroblast", TypeChart.TYPE_FLYING, 1, 100, 95, 5, false, ["crit:1"]],
		[183, "Mach Punch", TypeChart.TYPE_FIGHTING, 0, 40, 100, 30, true, ["punching", "prio:1"]],
		[185, "Feint Attack", TypeChart.TYPE_DARK, 0, 60, 0, 20, true, []],
		[224, "Megahorn", TypeChart.TYPE_BUG, 0, 120, 85, 10, true, []],
		[233, "Vital Throw", TypeChart.TYPE_FIGHTING, 0, 70, 0, 10, true, ["prio:-1"]],
		[238, "Cross Chop", TypeChart.TYPE_FIGHTING, 0, 100, 80, 5, true, ["crit:1"]],
		[245, "Extreme Speed", TypeChart.TYPE_NORMAL, 0, 80, 100, 5, true, ["prio:2"]],
		[304, "Hyper Voice", TypeChart.TYPE_NORMAL, 1, 90, 100, 10, false, ["sound", "spread"]],
		[314, "Air Cutter", TypeChart.TYPE_FLYING, 1, 60, 95, 25, false, ["slicing", "spread", "crit:1"]],
		[325, "Shadow Punch", TypeChart.TYPE_GHOST, 0, 60, 0, 20, true, ["punching"]],
		[327, "Sky Uppercut", TypeChart.TYPE_FIGHTING, 0, 85, 90, 15, true, ["punching", "airborne"]],
		[337, "Dragon Claw", TypeChart.TYPE_DRAGON, 0, 80, 100, 15, true, []],
		[345, "Magical Leaf", TypeChart.TYPE_GRASS, 1, 60, 0, 20, false, []],
		[348, "Leaf Blade", TypeChart.TYPE_GRASS, 0, 90, 100, 15, true, ["slicing", "crit:1"]],
		[351, "Shock Wave", TypeChart.TYPE_ELECTRIC, 1, 60, 0, 20, false, []],
		[396, "Aura Sphere", TypeChart.TYPE_FIGHTING, 1, 80, 0, 20, false, ["ballistic", "pulse"]],
		[400, "Night Slash", TypeChart.TYPE_DARK, 0, 70, 100, 15, true, ["slicing", "crit:1"]],
		[401, "Aqua Tail", TypeChart.TYPE_WATER, 0, 90, 90, 10, true, []],
		[402, "Seed Bomb", TypeChart.TYPE_GRASS, 0, 80, 100, 15, false, ["ballistic"]],
		[404, "X-Scissor", TypeChart.TYPE_BUG, 0, 80, 100, 15, true, ["slicing"]],
		[406, "Dragon Pulse", TypeChart.TYPE_DRAGON, 1, 85, 100, 10, false, ["pulse"]],
		[408, "Power Gem", TypeChart.TYPE_ROCK, 1, 80, 100, 20, false, []],
		[410, "Vacuum Wave", TypeChart.TYPE_FIGHTING, 1, 40, 100, 30, false, ["prio:1"]],
		[418, "Bullet Punch", TypeChart.TYPE_STEEL, 0, 40, 100, 30, true, ["punching", "prio:1"]],
		[420, "Ice Shard", TypeChart.TYPE_ICE, 0, 40, 100, 30, false, ["prio:1"]],
		[421, "Shadow Claw", TypeChart.TYPE_GHOST, 0, 70, 100, 15, true, ["crit:1"]],
		[425, "Shadow Sneak", TypeChart.TYPE_GHOST, 0, 40, 100, 30, true, ["prio:1"]],
		[427, "Psycho Cut", TypeChart.TYPE_PSYCHIC, 0, 70, 100, 20, false, ["slicing", "crit:1"]],
		[438, "Power Whip", TypeChart.TYPE_GRASS, 0, 120, 85, 10, true, []],
		[443, "Magnet Bomb", TypeChart.TYPE_STEEL, 0, 60, 0, 20, false, ["ballistic"]],
		[444, "Stone Edge", TypeChart.TYPE_ROCK, 0, 100, 80, 5, false, ["crit:1"]],
		[453, "Aqua Jet", TypeChart.TYPE_WATER, 0, 40, 100, 20, true, ["prio:1"]],
		[460, "Spacial Rend", TypeChart.TYPE_DRAGON, 1, 100, 95, 5, false, ["crit:1"]],
		[480, "Storm Throw", TypeChart.TYPE_FIGHTING, 0, 60, 100, 10, true, ["always_crit"]],
		[524, "Frost Breath", TypeChart.TYPE_ICE, 1, 60, 90, 10, false, ["always_crit"]],
		[529, "Drill Run", TypeChart.TYPE_GROUND, 0, 80, 95, 10, true, ["crit:1"]],
		[572, "Petal Blizzard", TypeChart.TYPE_GRASS, 0, 90, 100, 15, false, ["spread"]],
		[574, "Disarming Voice", TypeChart.TYPE_FAIRY, 1, 40, 0, 15, false, ["sound", "spread"]],
		[584, "Fairy Wind", TypeChart.TYPE_FAIRY, 1, 40, 100, 30, false, []],
		[586, "Boomburst", TypeChart.TYPE_NORMAL, 1, 140, 100, 10, false, ["sound", "spread"]],
		[605, "Dazzling Gleam", TypeChart.TYPE_FAIRY, 1, 80, 100, 10, false, ["spread"]],
		[616, "Land's Wrath", TypeChart.TYPE_GROUND, 0, 90, 100, 10, false, ["spread"]],
		[618, "Origin Pulse", TypeChart.TYPE_WATER, 1, 110, 85, 10, false, ["spread", "pulse"]],
		[619, "Precipice Blades", TypeChart.TYPE_GROUND, 0, 120, 85, 10, false, ["spread"]],
		[630, "High Horsepower", TypeChart.TYPE_GROUND, 0, 95, 95, 10, true, []],
		[633, "Leafage", TypeChart.TYPE_GRASS, 0, 40, 100, 40, false, []],
		[647, "Smart Strike", TypeChart.TYPE_STEEL, 0, 70, 0, 10, true, []],
		[655, "Dragon Hammer", TypeChart.TYPE_DRAGON, 0, 90, 100, 15, true, []],
		[656, "Brutal Swing", TypeChart.TYPE_DARK, 0, 60, 100, 20, true, ["spread"]],
		[663, "Accelerock", TypeChart.TYPE_ROCK, 0, 40, 100, 20, true, ["prio:1"]],
		[713, "Branch Poke", TypeChart.TYPE_GRASS, 0, 40, 100, 40, true, []],
		[714, "Overdrive", TypeChart.TYPE_ELECTRIC, 1, 80, 100, 10, false, ["sound", "spread"]],
		[721, "False Surrender", TypeChart.TYPE_DARK, 0, 80, 0, 10, true, []],
		[745, "Wicked Blow", TypeChart.TYPE_DARK, 0, 75, 100, 5, true, ["punching", "always_crit"]],
		[752, "Glacial Lance", TypeChart.TYPE_ICE, 0, 120, 100, 5, false, ["spread"]],
		[753, "Astral Barrage", TypeChart.TYPE_GHOST, 1, 120, 100, 5, false, ["spread"]],
		[785, "Jet Punch", TypeChart.TYPE_WATER, 0, 60, 100, 15, true, ["punching", "prio:1"]],
		[797, "Kowtow Cleave", TypeChart.TYPE_DARK, 0, 85, 0, 10, true, ["slicing"]],
		[798, "Flower Trick", TypeChart.TYPE_GRASS, 0, 70, 0, 10, false, ["always_crit"]],
		[813, "Hyper Drill", TypeChart.TYPE_NORMAL, 0, 100, 100, 5, true, []],
		[821, "Aqua Cutter", TypeChart.TYPE_WATER, 0, 70, 100, 20, false, ["slicing", "crit:1"]],
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
		var seen_slicing := false
		var seen_ballistic := false
		var seen_punching := false
		var seen_sound := false
		var seen_spread := false
		var seen_airborne := false
		var seen_pulse := false
		var seen_always_crit := false
		var seen_crit := false
		var seen_prio := false
		for token: String in tokens:
			if token == "slicing":
				seen_slicing = true
				_chk(tag + " slicing_move", mv.slicing_move)
			elif token == "ballistic":
				seen_ballistic = true
				_chk(tag + " ballistic_move", mv.ballistic_move)
			elif token == "punching":
				seen_punching = true
				_chk(tag + " punching_move", mv.punching_move)
			elif token == "sound":
				seen_sound = true
				_chk(tag + " sound_move", mv.sound_move)
			elif token == "spread":
				seen_spread = true
				_chk(tag + " is_spread", mv.is_spread)
			elif token == "airborne":
				seen_airborne = true
				_chk(tag + " damages_airborne", mv.damages_airborne)
			elif token == "pulse":
				seen_pulse = true
				_chk(tag + " pulse_move", mv.pulse_move)
			elif token == "always_crit":
				seen_always_crit = true
				_chk(tag + " always_critical_hit", mv.always_critical_hit)
			elif token.begins_with("crit:"):
				seen_crit = true
				var n: int = int(token.split(":")[1])
				_chk(tag + " critical_hit_stage=%d" % n, mv.critical_hit_stage == n)
			elif token.begins_with("prio:"):
				seen_prio = true
				var n: int = int(token.split(":")[1])
				_chk(tag + " priority=%d" % n, mv.priority == n)
		# Negative checks: a flag not listed in this move's own token set must
		# not be silently set either (confirms the table isn't vacuously passing).
		if not seen_slicing:
			_chk(tag + " NOT slicing_move", not mv.slicing_move)
		if not seen_ballistic:
			_chk(tag + " NOT ballistic_move", not mv.ballistic_move)
		if not seen_punching:
			_chk(tag + " NOT punching_move", not mv.punching_move)
		if not seen_sound:
			_chk(tag + " NOT sound_move", not mv.sound_move)
		if not seen_spread:
			_chk(tag + " NOT is_spread", not mv.is_spread)
		if not seen_airborne:
			_chk(tag + " NOT damages_airborne", not mv.damages_airborne)
		if not seen_pulse:
			_chk(tag + " NOT pulse_move", not mv.pulse_move)
		if not seen_always_crit:
			_chk(tag + " NOT always_critical_hit", not mv.always_critical_hit)
		if not seen_crit:
			_chk(tag + " critical_hit_stage=0", mv.critical_hit_stage == 0)
		if not seen_prio:
			_chk(tag + " priority=0", mv.priority == 0)


# ── Section B: Functional confirmation — shared EFFECT_HIT dispatch, plus ──
# ── flags that gate a DIFFERENT existing mechanism a plain data row could ──
# ── silently fail to trigger. critical_hit_stage/damages_airborne/priority ──
# ── are NOT re-proven here per this tier's own Step 0 scoping note above. ──

func _test_section_b_functional() -> void:
	# B1: a representative plain move (Dragon Claw) fires and deals real,
	# nonzero damage through the actual .tres -> dispatch -> DamageCalculator
	# pipeline — a plumbing check, not a formula re-derivation (already
	# proven in general by move_test.gd/damage_test.gd).
	var dragon_claw := _load_move(337)
	var b1_atk := _make_mon("B1Atk", TypeChart.TYPE_DRAGON)
	b1_atk.add_move(dragon_claw)
	var b1_def := _make_mon("B1Def", TypeChart.TYPE_NORMAL)
	b1_def.add_move(dragon_claw)
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
	_chk("B1 Dragon Claw deals real nonzero damage through the real dispatch path",
			b1_dmg[0] > 0)

	# B2: makes_contact=true actually triggers a contact-reactive ability
	# (Rough Skin, id 24) — confirms the flag isn't inert data. Uses Megahorn
	# (makes_contact=true), matching [M18_5g]'s established Rough-Skin-via-
	# _force_contact_roll pattern.
	var megahorn := _load_move(224)
	var b2_atk := _make_mon("B2Atk", TypeChart.TYPE_BUG, 300, 60, 60, 60, 60, 100)
	b2_atk.add_move(megahorn)
	var b2_def := _make_mon("B2Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	b2_def.ability = _load_ability(24)  # Rough Skin
	b2_def.add_move(megahorn)
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
	_chk("B2 Megahorn (makes_contact=true) triggers Rough Skin recoil on the attacker",
			b2_recoil_fired[0])

	# B3: discriminator — Aura Sphere (makes_contact=false) does NOT trigger
	# Rough Skin, confirming B2 wasn't a vacuous pass.
	var aura_sphere := _load_move(396)
	var b3_atk := _make_mon("B3Atk", TypeChart.TYPE_FIGHTING, 300, 60, 60, 60, 60, 100)
	b3_atk.add_move(aura_sphere)
	var b3_def := _make_mon("B3Def", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 50)
	b3_def.ability = _load_ability(24)  # Rough Skin
	b3_def.add_move(aura_sphere)
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
	_chk("B3 Aura Sphere (makes_contact=false) does NOT trigger Rough Skin (discriminator)",
			not b3_recoil_fired[0])

	# B4: pulse_move=true actually triggers Mega Launcher's power boost. This
	# is the FIRST real move in this project's roster to carry pulse_move
	# (per ability_manager.gd's own comment at the time Mega Launcher was
	# built: "No move in this project's current roster carries pulse_move —
	# tested via a synthetic MoveData"). Confirms the flag isn't inert on
	# real data by comparing damage with vs. without Mega Launcher.
	var dragon_pulse := _load_move(406)
	var b4_atk_boosted := _make_mon("B4AtkBoosted", TypeChart.TYPE_DRAGON, 300, 60, 60, 100, 60, 60)
	b4_atk_boosted.ability = _load_ability(178)  # Mega Launcher
	b4_atk_boosted.add_move(dragon_pulse)
	var b4_def1 := _make_mon("B4Def1", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 60)
	b4_def1.add_move(dragon_pulse)
	var b4_bm1 := _make_bm()
	b4_bm1._force_hit = true
	b4_bm1._force_crit = false
	b4_bm1._force_roll = 100
	var b4_dmg_boosted := [0]
	b4_bm1.move_executed.connect(func(a, d, m, dmg):
		if b4_dmg_boosted[0] == 0 and a == b4_atk_boosted:
			b4_dmg_boosted[0] = dmg)
	b4_bm1.queue_move(0, 0)
	b4_bm1.queue_move(1, 0)
	b4_bm1.start_battle(b4_atk_boosted, b4_def1)

	var b4_atk_plain := _make_mon("B4AtkPlain", TypeChart.TYPE_DRAGON, 300, 60, 60, 100, 60, 60)
	b4_atk_plain.add_move(dragon_pulse)
	var b4_def2 := _make_mon("B4Def2", TypeChart.TYPE_NORMAL, 300, 60, 60, 60, 60, 60)
	b4_def2.add_move(dragon_pulse)
	var b4_bm2 := _make_bm()
	b4_bm2._force_hit = true
	b4_bm2._force_crit = false
	b4_bm2._force_roll = 100
	var b4_dmg_plain := [0]
	b4_bm2.move_executed.connect(func(a, d, m, dmg):
		if b4_dmg_plain[0] == 0 and a == b4_atk_plain:
			b4_dmg_plain[0] = dmg)
	b4_bm2.queue_move(0, 0)
	b4_bm2.queue_move(1, 0)
	b4_bm2.start_battle(b4_atk_plain, b4_def2)

	_chk("B4 Dragon Pulse (pulse_move=true) deals more damage with Mega Launcher than without",
			b4_dmg_boosted[0] > b4_dmg_plain[0])
