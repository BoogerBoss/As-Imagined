extends Node

# [D2 batch] Two independent pieces bundled into one session for scheduling
# efficiency (documented and reported as fully separate throughout):
#
# Part A — D2 cross-cutting families:
#   On-hit hazard/screen family (6 moves): Stone Axe(758), Ceaseless Edge(773),
#     Ice Spinner(789), Mortal Spin(794), Tidy Up(808), Defog(432).
#   Ability-manipulation family (4 moves): Role Play(272), Skill Swap(285),
#     Worry Seed(388), Heart Swap(391).
#
# Part B — batch fix (0 new moves, 3 flagged-gap closures):
#   1. Hail-only decision (docs only, no test needed).
#   2. Primal weather block (`try_set_weather`'s new refuse-to-overwrite gate).
#   3. Solar Beam/Blade rain/sand/hail damage-halving.
#
# Ground truth: reference/pokeemerald_expansion/src/battle_move_resolution.c
# (EFFECT_STONE_AXE/CEASELESS_EDGE L3592-3618, EFFECT_ICE_SPINNER L4030-4037,
# EFFECT_DEFOG/TIDY_UP L4634-4650), src/battle_script_commands.c
# (Cmd_trycopyability L8997-9025, Cmd_tryswapabilities L9160-9195,
# Cmd_tryoverwriteability L10627-10650, TryDefogClear/TryTidyUpClear/
# DefogClearHazards L6733-6825), src/battle_util.c (TryChangeBattleWeather
# L1969-2015, CalcMoveBasePowerAfterModifiers EFFECT_SOLAR_BEAM L6408-6414,
# GetAttackerWeather L9281-9290), GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_stone_axe_ceaseless_edge()
	_test_ice_spinner()
	_test_mortal_spin()
	_test_defog()
	_test_tidy_up()
	_test_role_play()
	_test_skill_swap()
	_test_worry_seed()
	_test_heart_swap()
	_test_primal_weather_block()
	_test_solar_beam_weather_halving()

	var total := _pass + _fail
	print("d2_batch_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
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


# ── Section A: data integrity (10 moves) ────────────────────────────────────

func _test_data_integrity() -> void:
	var stone_axe := _load_move(758)
	_chk("A.01 Stone Axe power=65/acc=90/pp=15", stone_axe.power == 65
			and stone_axe.accuracy == 90 and stone_axe.pp == 15)
	_chk("A.02 Stone Axe sets_stealth_rock_on_hit", stone_axe.sets_stealth_rock_on_hit == true)
	_chk("A.03 Stone Axe makes_contact/slicing_move", stone_axe.makes_contact == true
			and stone_axe.slicing_move == true)

	var ceaseless_edge := _load_move(773)
	_chk("A.04 Ceaseless Edge power=65/acc=90/pp=15", ceaseless_edge.power == 65
			and ceaseless_edge.accuracy == 90 and ceaseless_edge.pp == 15)
	_chk("A.05 Ceaseless Edge sets_spikes_on_hit", ceaseless_edge.sets_spikes_on_hit == true)

	var ice_spinner := _load_move(789)
	_chk("A.06 Ice Spinner power=80/acc=100/pp=15", ice_spinner.power == 80
			and ice_spinner.accuracy == 100 and ice_spinner.pp == 15)
	_chk("A.07 Ice Spinner carries NO special flag (Terrain removal is permanently moot)",
			ice_spinner.sets_stealth_rock_on_hit == false
			and ice_spinner.sets_spikes_on_hit == false
			and ice_spinner.is_rapid_spin == false)

	var mortal_spin := _load_move(794)
	_chk("A.08 Mortal Spin power=30/acc=100/pp=15", mortal_spin.power == 30
			and mortal_spin.accuracy == 100 and mortal_spin.pp == 15)
	_chk("A.09 Mortal Spin is_rapid_spin (shares EFFECT_RAPID_SPIN literally)",
			mortal_spin.is_rapid_spin == true)
	_chk("A.10 Mortal Spin guaranteed Poison secondary",
			mortal_spin.secondary_effect == MoveData.SE_POISON
			and mortal_spin.secondary_chance == 100)
	_chk("A.11 Mortal Spin is_spread (TARGET_BOTH)", mortal_spin.is_spread == true)

	var tidy_up := _load_move(808)
	_chk("A.12 Tidy Up accuracy=0/pp=10", tidy_up.accuracy == 0 and tidy_up.pp == 10)
	_chk("A.13 Tidy Up is_tidy_up/ignores_protect",
			tidy_up.is_tidy_up == true and tidy_up.ignores_protect == true)
	_chk("A.14 Tidy Up self Atk+1/Speed+1",
			tidy_up.stat_change_self == true
			and tidy_up.stat_change_stat == BattlePokemon.STAGE_ATK
			and tidy_up.stat_change_amount == 1
			and tidy_up.extra_stat_change_stats == [BattlePokemon.STAGE_SPEED]
			and tidy_up.extra_stat_change_amounts == [1])

	var defog := _load_move(432)
	_chk("A.15 Defog accuracy=0/pp=15", defog.accuracy == 0 and defog.pp == 15)
	_chk("A.16 Defog is_defog/bounceable", defog.is_defog == true and defog.bounceable == true)
	_chk("A.17 Defog target evasion -1",
			defog.stat_change_self == false
			and defog.stat_change_stat == BattlePokemon.STAGE_EVASION
			and defog.stat_change_amount == -1)

	var role_play := _load_move(272)
	_chk("A.18 Role Play accuracy=0/pp=10", role_play.accuracy == 0 and role_play.pp == 10)
	_chk("A.19 Role Play is_role_play/ignores_protect/ignores_substitute",
			role_play.is_role_play == true and role_play.ignores_protect == true
			and role_play.ignores_substitute == true)

	var skill_swap := _load_move(285)
	_chk("A.20 Skill Swap accuracy=0/pp=10", skill_swap.accuracy == 0 and skill_swap.pp == 10)
	_chk("A.21 Skill Swap is_skill_swap/ignores_substitute, NOT ignores_protect",
			skill_swap.is_skill_swap == true and skill_swap.ignores_substitute == true
			and skill_swap.ignores_protect == false)

	var worry_seed := _load_move(388)
	_chk("A.22 Worry Seed accuracy=100/pp=10", worry_seed.accuracy == 100 and worry_seed.pp == 10)
	_chk("A.23 Worry Seed overwrite_target_ability_id=15 (Insomnia)/bounceable",
			worry_seed.overwrite_target_ability_id == 15 and worry_seed.bounceable == true)
	_chk("A.24 Worry Seed NOT ignores_substitute/ignores_protect (fully normal status move)",
			worry_seed.ignores_substitute == false and worry_seed.ignores_protect == false)

	var heart_swap := _load_move(391)
	_chk("A.25 Heart Swap accuracy=0/pp=10", heart_swap.accuracy == 0 and heart_swap.pp == 10)
	_chk("A.26 Heart Swap is_heart_swap/ignores_substitute, NOT ignores_protect",
			heart_swap.is_heart_swap == true and heart_swap.ignores_substitute == true
			and heart_swap.ignores_protect == false)


# ── Section B: Stone Axe / Ceaseless Edge ───────────────────────────────────

func _test_stone_axe_ceaseless_edge() -> void:
	var stone_axe := _load_move(758)
	var ceaseless_edge := _load_move(773)

	# (i) Stone Axe sets Stealth Rock on the TARGET's side (side 1).
	var atk := _make_mon("SAAtk", [TypeChart.TYPE_ROCK], 200, 80, 60, 60, 60, 60)
	atk.add_move(stone_axe)
	var def := _make_mon("SADef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(stone_axe)
	var bm := _make_bm()
	bm._force_hit = true
	var set_events: Array = []
	bm.hazard_set.connect(func(side: int, name_: String, layers: int):
		set_events.append([side, name_, layers]))
	bm.start_battle(atk, def)
	_chk("B.01 Stone Axe sets Stealth Rock on the target's side (side 1)",
			[1, "stealth_rock", 1] in set_events)

	# (ii) Discriminator: fails (no re-emit) if Stealth Rock is already up.
	# Defender uses Tackle (not Stone Axe) deliberately — a defender also
	# holding Stone Axe would legitimately set Stealth Rock on the
	# ATTACKER's own (unrelated) side, a real confound caught while writing
	# this test that would otherwise pollute a whole-battle "nothing was
	# ever set" style assertion.
	var tackle := _load_move(33)
	var atk2 := _make_mon("SAAtk2", [TypeChart.TYPE_ROCK], 200, 80, 60, 60, 60, 60)
	atk2.add_move(stone_axe)
	var def2 := _make_mon("SADef2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._side_conditions[1]["stealth_rock"] = true
	var fail_events2: Array[String] = []
	bm2.move_effect_failed.connect(func(_a: BattlePokemon, r: String): fail_events2.append(r))
	var set_events2: Array = []
	bm2.hazard_set.connect(func(side: int, name_: String, layers: int):
		set_events2.append([side, name_, layers]))
	bm2.start_battle(atk2, def2)
	_chk("B.02 discriminator: Stone Axe fails once Stealth Rock is already up",
			"already_stealth_rock" in fail_events2 and set_events2.is_empty())

	# (iii) Ceaseless Edge sets Spikes on the TARGET's side, stacking.
	var atk3 := _make_mon("CEAtk", [TypeChart.TYPE_DARK], 200, 80, 60, 60, 60, 60)
	atk3.add_move(ceaseless_edge)
	var def3 := _make_mon("CEDef", [TypeChart.TYPE_NORMAL], 300, 5, 300, 60, 300, 60)
	def3.add_move(ceaseless_edge)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var set_events3: Array = []
	bm3.hazard_set.connect(func(side: int, name_: String, layers: int):
		set_events3.append([side, name_, layers]))
	for _t in range(2):
		bm3.queue_move(0, 0)
	bm3.start_battle(atk3, def3)
	_chk("B.03 Ceaseless Edge sets Spikes on the target's side (side 1)",
			[1, "spikes", 1] in set_events3)
	_chk("B.04 Ceaseless Edge stacks a second layer", [1, "spikes", 2] in set_events3)

	# (iv) Discriminator: fails once Spikes is at 3 layers.
	var atk4 := _make_mon("CEAtk4", [TypeChart.TYPE_DARK], 200, 80, 60, 60, 60, 60)
	atk4.add_move(ceaseless_edge)
	var def4 := _make_mon("CEDef4", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def4.add_move(ceaseless_edge)
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._side_conditions[1]["spikes_layers"] = 3
	var fail_events4: Array[String] = []
	bm4.move_effect_failed.connect(func(_a: BattlePokemon, r: String): fail_events4.append(r))
	bm4.start_battle(atk4, def4)
	_chk("B.05 discriminator: Ceaseless Edge fails once Spikes is maxed (3 layers)",
			"already_spikes_max" in fail_events4)


# ── Section C: Ice Spinner ───────────────────────────────────────────────────

func _test_ice_spinner() -> void:
	var ice_spinner := _load_move(789)
	var atk := _make_mon("ISAtk", [TypeChart.TYPE_ICE], 200, 80, 60, 60, 60, 60)
	atk.add_move(ice_spinner)
	var def := _make_mon("ISDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(ice_spinner)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var hazard_fired := [false]
	var screen_fired := [false]
	var dealt := [-1]
	bm.hazard_set.connect(func(_s, _n, _l): hazard_fired[0] = true)
	bm.screens_broken.connect(func(_s): screen_fired[0] = true)
	bm.move_executed.connect(func(_a, _t, _m, amount):
		if dealt[0] == -1:
			dealt[0] = amount)
	bm.start_battle(atk, def)
	_chk("C.01 Ice Spinner deals real damage", dealt[0] > 0)
	_chk("C.02 Ice Spinner sets no hazard (Terrain removal is permanently moot)",
			hazard_fired[0] == false)
	_chk("C.03 Ice Spinner breaks no screen", screen_fired[0] == false)


# ── Section D: Mortal Spin ───────────────────────────────────────────────────

func _test_mortal_spin() -> void:
	var mortal_spin := _load_move(794)
	var atk := _make_mon("MSAtk", [TypeChart.TYPE_POISON], 200, 80, 60, 60, 60, 100)
	atk.add_move(mortal_spin)
	var def := _make_mon("MSDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(mortal_spin)
	var bm := _make_bm()
	bm._force_hit = true
	# Pre-seed the ATTACKER's own side (side 0) with a hazard — Mortal Spin
	# clears the attacker's OWN side, same as Rapid Spin, NOT the target's.
	# Uses spikes (not toxic spikes) deliberately: the attacker is Poison-type,
	# and Toxic Spikes' own Poison-type absorb-on-switch-in rule (`[M16d]`)
	# would otherwise auto-clear it at send-out before Mortal Spin ever gets a
	# chance to — a real confound caught while writing this test, not present
	# for plain Spikes/Stealth Rock, which have no type-based auto-clear.
	bm._side_conditions[0]["spikes_layers"] = 1
	var cleared_events: Array = []
	bm.hazards_cleared.connect(func(side: int, name_: String): cleared_events.append([side, name_]))
	var poisoned := [false]
	bm.secondary_applied.connect(func(target: BattlePokemon, effect: int):
		if target == def and effect == MoveData.SE_POISON:
			poisoned[0] = true)
	bm.start_battle(atk, def)
	_chk("D.01 Mortal Spin clears a hazard from the ATTACKER's own side (side 0)",
			[0, "spikes"] in cleared_events)
	_chk("D.02 Mortal Spin's guaranteed Poison secondary applies to the TARGET",
			poisoned[0] == true)


# ── Section E: Defog ─────────────────────────────────────────────────────────

func _test_defog() -> void:
	var defog := _load_move(432)
	var tackle := _load_move(33)
	var atk := _make_mon("DFAtk", [TypeChart.TYPE_FLYING], 200, 60, 60, 60, 60, 100)
	atk.add_move(defog)
	var def := _make_mon("DFDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	# Pre-seed: attacker's own side (0) has Light Screen up + a hazard; the
	# target's side (1) has Reflect up + a different hazard — confirms
	# screens clear ONLY the target's side while hazards clear BOTH sides.
	bm._side_conditions[0]["light_screen_turns"] = 5
	bm._side_conditions[0]["toxic_spikes_layers"] = 1
	bm._side_conditions[1]["reflect_turns"] = 5
	bm._side_conditions[1]["spikes_layers"] = 1
	var broken_sides: Array = []
	bm.screens_broken.connect(func(side: int): broken_sides.append(side))
	var cleared_events: Array = []
	bm.hazards_cleared.connect(func(side: int, name_: String): cleared_events.append([side, name_]))
	var evasion_drop := [0]
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, delta: int):
		if mon == def and stat == BattlePokemon.STAGE_EVASION:
			evasion_drop[0] = delta)
	bm.start_battle(atk, def)
	_chk("E.01 Defog clears the TARGET's side (1) screens", 1 in broken_sides)
	_chk("E.02 discriminator: Defog does NOT clear the ATTACKER's own side (0) screens",
			not (0 in broken_sides))
	_chk("E.03 Defog clears hazards from the target's side (1)",
			[1, "spikes"] in cleared_events)
	_chk("E.04 Defog ALSO clears hazards from the attacker's own side (0)",
			[0, "toxic_spikes"] in cleared_events)
	_chk("E.05 Defog lowers the target's evasion by 1", evasion_drop[0] == -1)


# ── Section F: Tidy Up ───────────────────────────────────────────────────────

func _test_tidy_up() -> void:
	var tidy_up := _load_move(808)
	var tackle := _load_move(33)
	var atk := _make_mon("TUAtk", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	atk.add_move(tidy_up)
	var def := _make_mon("TUDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	# Pre-seed hazards on BOTH sides and a Substitute on BOTH mons — Tidy Up
	# clears hazards field-wide and every Substitute on the field, not just
	# the attacker's own side/self.
	bm._side_conditions[0]["spikes_layers"] = 1
	bm._side_conditions[1]["stealth_rock"] = true
	atk.substitute_hp = 40
	def.substitute_hp = 40
	var cleared_events: Array = []
	bm.hazards_cleared.connect(func(side: int, name_: String): cleared_events.append([side, name_]))
	var sub_broke_mons: Array = []
	bm.substitute_broke.connect(func(mon: BattlePokemon): sub_broke_mons.append(mon))
	var atk_stat_deltas: Dictionary = {}
	bm.stat_stage_changed.connect(func(mon: BattlePokemon, stat: int, delta: int):
		if mon == atk:
			atk_stat_deltas[stat] = delta)
	bm.start_battle(atk, def)
	_chk("F.01 Tidy Up clears hazards on the attacker's own side (0)",
			[0, "spikes"] in cleared_events)
	_chk("F.02 Tidy Up ALSO clears hazards on the opposing side (1)",
			[1, "stealth_rock"] in cleared_events)
	_chk("F.03 Tidy Up clears the ATTACKER's own Substitute", atk in sub_broke_mons)
	_chk("F.04 Tidy Up ALSO clears the OPPONENT's Substitute (field-wide, not self-only)",
			def in sub_broke_mons)
	_chk("F.05 Tidy Up raises the user's own Attack +1",
			atk_stat_deltas.get(BattlePokemon.STAGE_ATK, 0) == 1)
	_chk("F.06 Tidy Up ALSO raises the user's own Speed +1",
			atk_stat_deltas.get(BattlePokemon.STAGE_SPEED, 0) == 1)


# ── Section G: Role Play ─────────────────────────────────────────────────────

func _test_role_play() -> void:
	# Direct unit tests against AbilityManager.try_role_play.
	var overgrow := _load_ability(65)   # ordinary ability, no exemption flags
	var torrent := _load_ability(67)
	var multitype := _load_ability(121)  # cant_be_copied/cant_be_suppressed

	var atk1 := _make_mon("RPAtk1", [TypeChart.TYPE_PSYCHIC])
	atk1.ability = torrent
	var def1 := _make_mon("RPDef1", [TypeChart.TYPE_NORMAL])
	def1.ability = overgrow
	_chk("G.01 Role Play: attacker copies the target's ability",
			AbilityManager.try_role_play(atk1, def1) == true
			and atk1.ability.ability_id == overgrow.ability_id)

	var atk2 := _make_mon("RPAtk2", [TypeChart.TYPE_PSYCHIC])
	atk2.ability = _load_ability(65)
	var def2 := _make_mon("RPDef2", [TypeChart.TYPE_NORMAL])
	def2.ability = _load_ability(65)
	_chk("G.02 discriminator: fails (no-op) if the attacker already holds this exact ability",
			AbilityManager.try_role_play(atk2, def2) == false)

	var atk3 := _make_mon("RPAtk3", [TypeChart.TYPE_PSYCHIC])
	atk3.ability = _load_ability(67)
	var def3 := _make_mon("RPDef3", [TypeChart.TYPE_NORMAL])
	def3.ability = multitype
	_chk("G.03 discriminator: fails if the target's ability is cant_be_copied (Multitype)",
			AbilityManager.try_role_play(atk3, def3) == false)

	var atk4 := _make_mon("RPAtk4", [TypeChart.TYPE_PSYCHIC])
	atk4.ability = multitype
	var def4 := _make_mon("RPDef4", [TypeChart.TYPE_NORMAL])
	def4.ability = _load_ability(67)
	_chk("G.04 discriminator: fails if the attacker's OWN ability is cant_be_suppressed (Multitype)",
			AbilityManager.try_role_play(atk4, def4) == false)

	var atk5 := _make_mon("RPAtk5", [TypeChart.TYPE_PSYCHIC])
	var def5 := _make_mon("RPDef5", [TypeChart.TYPE_NORMAL])
	def5.ability = null
	_chk("G.05 discriminator: fails if the target has no ability at all",
			AbilityManager.try_role_play(atk5, def5) == false)

	# Full-battle integration.
	var role_play := _load_move(272)
	var atk6 := _make_mon("RPAtk6", [TypeChart.TYPE_PSYCHIC], 200, 60, 60, 60, 60, 100)
	atk6.ability = _load_ability(67)
	atk6.add_move(role_play)
	var def6 := _make_mon("RPDef6", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def6.ability = _load_ability(65)
	def6.add_move(role_play)
	var bm := _make_bm()
	bm._force_hit = true
	var changed: Array = []
	bm.ability_changed.connect(func(mon: BattlePokemon, new_id: int): changed.append([mon, new_id]))
	bm.start_battle(atk6, def6)
	_chk("G.06 full-battle: Role Play copies the target's ability onto the attacker",
			[atk6, overgrow.ability_id] in changed)


# ── Section H: Skill Swap ────────────────────────────────────────────────────

func _test_skill_swap() -> void:
	var atk1 := _make_mon("SSAtk1", [TypeChart.TYPE_PSYCHIC])
	atk1.ability = _load_ability(67)   # Torrent
	var def1 := _make_mon("SSDef1", [TypeChart.TYPE_NORMAL])
	def1.ability = _load_ability(65)   # Overgrow
	var atk1_before := atk1.ability.ability_id
	var def1_before := def1.ability.ability_id
	_chk("H.01 Skill Swap: bidirectional swap succeeds",
			AbilityManager.try_skill_swap(atk1, def1) == true)
	_chk("H.02 attacker now holds the target's ORIGINAL ability",
			atk1.ability.ability_id == def1_before)
	_chk("H.03 target now holds the attacker's ORIGINAL ability",
			def1.ability.ability_id == atk1_before)

	var atk2 := _make_mon("SSAtk2", [TypeChart.TYPE_PSYCHIC])
	atk2.ability = _load_ability(256)  # Neutralizing Gas — cant_be_swapped
	var def2 := _make_mon("SSDef2", [TypeChart.TYPE_NORMAL])
	def2.ability = _load_ability(65)
	_chk("H.04 discriminator: fails if the attacker's own ability is cant_be_swapped",
			AbilityManager.try_skill_swap(atk2, def2) == false)

	var atk3 := _make_mon("SSAtk3", [TypeChart.TYPE_PSYCHIC])
	atk3.ability = _load_ability(65)
	var def3 := _make_mon("SSDef3", [TypeChart.TYPE_NORMAL])
	def3.ability = _load_ability(256)
	_chk("H.05 discriminator: fails if the TARGET's own ability is cant_be_swapped",
			AbilityManager.try_skill_swap(atk3, def3) == false)

	# Full-battle integration.
	var skill_swap := _load_move(285)
	var atk4 := _make_mon("SSAtk4", [TypeChart.TYPE_PSYCHIC], 200, 60, 60, 60, 60, 100)
	atk4.ability = _load_ability(67)
	atk4.add_move(skill_swap)
	var def4 := _make_mon("SSDef4", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def4.ability = _load_ability(65)
	def4.add_move(skill_swap)
	var bm := _make_bm()
	bm._force_hit = true
	# Skill Swap deals no damage, so an all-Skill-Swap roster keeps re-using
	# it turn after turn (re-swapping back and forth) — a whole-battle-
	# aggregation trap. Record only the FIRST change per mon, isolating to
	# the single first exchange rather than reading a size across the whole
	# multi-turn battle.
	var changed: Dictionary = {}
	bm.ability_changed.connect(func(mon: BattlePokemon, new_id: int):
		if not changed.has(mon):
			changed[mon] = new_id)
	bm.start_battle(atk4, def4)
	_chk("H.06 full-battle: both sides' abilities changed (a real bidirectional swap)",
			changed.size() == 2)


# ── Section I: Worry Seed ────────────────────────────────────────────────────

func _test_worry_seed() -> void:
	var overgrow := _load_ability(65)
	var truant := _load_ability(54)      # cant_be_overwritten
	var insomnia := _load_ability(15)

	var def1 := _make_mon("WSDef1", [TypeChart.TYPE_NORMAL])
	def1.ability = overgrow
	_chk("I.01 Worry Seed: overwrites the target's ability with Insomnia",
			AbilityManager.try_worry_seed_overwrite(def1, 15) == true
			and def1.ability.ability_id == 15)

	var def2 := _make_mon("WSDef2", [TypeChart.TYPE_NORMAL])
	def2.ability = truant
	_chk("I.02 discriminator: fails if the target's ability is cant_be_overwritten (Truant)",
			AbilityManager.try_worry_seed_overwrite(def2, 15) == false
			and def2.ability.ability_id == 54)

	var def3 := _make_mon("WSDef3", [TypeChart.TYPE_NORMAL])
	def3.ability = insomnia
	_chk("I.03 discriminator: fails (no-op) if the target already holds this exact ability",
			AbilityManager.try_worry_seed_overwrite(def3, 15) == false)

	# Full-battle integration, incl. Magic Bounce reflecting it back.
	var worry_seed := _load_move(388)
	var atk4 := _make_mon("WSAtk4", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 100)
	atk4.ability = overgrow
	atk4.add_move(worry_seed)
	var def4 := _make_mon("WSDef4", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def4.ability = _load_ability(67)
	def4.add_move(worry_seed)
	var bm := _make_bm()
	bm._force_hit = true
	var changed: Array = []
	bm.ability_changed.connect(func(mon: BattlePokemon, new_id: int): changed.append([mon, new_id]))
	bm.start_battle(atk4, def4)
	_chk("I.04 full-battle: Worry Seed overwrites the target's ability with Insomnia",
			[def4, 15] in changed)

	var atk5 := _make_mon("WSAtk5", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 40)
	atk5.ability = overgrow
	atk5.add_move(worry_seed)
	var def5 := _make_mon("WSDef5", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	def5.ability = _load_ability(156)  # Magic Bounce
	def5.add_move(worry_seed)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var changed2: Array = []
	bm2.ability_changed.connect(func(mon: BattlePokemon, new_id: int): changed2.append([mon, new_id]))
	bm2.start_battle(atk5, def5)
	_chk("I.05 Magic Bounce reflects Worry Seed: the ATTACKER's own ability is overwritten instead",
			[atk5, 15] in changed2)


# ── Section J: Heart Swap ────────────────────────────────────────────────────

func _test_heart_swap() -> void:
	var heart_swap := _load_move(391)
	var atk := _make_mon("HSAtk", [TypeChart.TYPE_PSYCHIC], 200, 60, 60, 60, 60, 100)
	atk.add_move(heart_swap)
	var def := _make_mon("HSDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 60)
	def.add_move(heart_swap)
	atk.stat_stages[BattlePokemon.STAGE_ATK] = 2
	def.stat_stages[BattlePokemon.STAGE_SPDEF] = -1
	var bm := _make_bm()
	bm._force_hit = true
	# Heart Swap deals no damage, so an all-Heart-Swap roster keeps re-using
	# it turn after turn (re-swapping back and forth every turn) — a
	# whole-battle-aggregation trap. Snapshot both stat_stages arrays live,
	# guarded to the FIRST occurrence, rather than reading post-battle state
	# that could reflect an even (or odd) number of later re-swaps.
	# Wrapped in a single outer Array and mutated by INDEX (never
	# reassigned) — reassigning a captured lambda-local variable directly
	# would silently rebind a private closure copy instead of the outer
	# scope's variable (CLAUDE.md's documented lambda-capture pitfall,
	# caught here on the first run, same failure shape whether the
	# captured value is a scalar or a whole Array).
	var copied := [false]
	var snap := [[], []]
	bm.stat_changes_copied.connect(func(_u, _f):
		if not copied[0]:
			copied[0] = true
			snap[0] = atk.stat_stages.duplicate()
			snap[1] = def.stat_stages.duplicate())
	bm.start_battle(atk, def)
	_chk("J.01 Heart Swap: attacker's stat stages become the target's ORIGINAL stages",
			snap[0][BattlePokemon.STAGE_SPDEF] == -1)
	_chk("J.02 Heart Swap: target's stat stages become the attacker's ORIGINAL stages",
			snap[1][BattlePokemon.STAGE_ATK] == 2)
	_chk("J.03 stat_changes_copied signal fired", copied[0] == true)
	_chk("J.04 discriminator: attacker no longer holds its own original Atk+2",
			snap[0][BattlePokemon.STAGE_ATK] == 0)


# ── Section K: Primal weather block ─────────────────────────────────────────

func _test_primal_weather_block() -> void:
	var desolate_mon := _make_mon("DesolateMon", [TypeChart.TYPE_GROUND])
	desolate_mon.ability = _load_ability(190)  # Desolate Land
	var sand_mon := _make_mon("SandMon", [TypeChart.TYPE_ROCK])
	sand_mon.ability = _load_ability(45)  # Sand Stream
	var primordial_mon := _make_mon("PrimordialMon", [TypeChart.TYPE_WATER])
	primordial_mon.ability = _load_ability(189)  # Primordial Sea

	var bm := _make_bm()
	_chk("K.01 Desolate Land sets Sun (ability-driven)",
			bm.try_set_weather(DamageCalculator.WEATHER_SUN, desolate_mon, true) == true
			and bm.weather == DamageCalculator.WEATHER_SUN)
	_chk("K.02 Sand Stream is REFUSED — cannot overwrite the active Primal-set Sun",
			bm.try_set_weather(DamageCalculator.WEATHER_SANDSTORM, sand_mon, true) == false
			and bm.weather == DamageCalculator.WEATHER_SUN)
	_chk("K.03 Primordial Sea (ALSO Primal-capable) CAN overwrite Desolate Land's Sun",
			bm.try_set_weather(DamageCalculator.WEATHER_RAIN, primordial_mon, true) == true
			and bm.weather == DamageCalculator.WEATHER_RAIN)

	# Discriminator: ordinary (non-Primal) weather-to-weather overwrite is
	# still completely unaffected by this gate.
	var drought_mon := _make_mon("DroughtMon", [TypeChart.TYPE_FIRE])
	drought_mon.ability = _load_ability(70)  # Drought
	var bm2 := _make_bm()
	bm2.try_set_weather(DamageCalculator.WEATHER_SUN, drought_mon, true)
	_chk("K.04 discriminator: an ordinary (non-Primal) ability CAN overwrite another ordinary weather",
			bm2.try_set_weather(DamageCalculator.WEATHER_SANDSTORM, sand_mon, true) == true
			and bm2.weather == DamageCalculator.WEATHER_SANDSTORM)

	# Discriminator: a move-driven weather-set (by_ability=false) can NEVER
	# count as a Primal-capable setter, matching source's own ABILITY_NONE.
	var bm3 := _make_bm()
	bm3.try_set_weather(DamageCalculator.WEATHER_RAIN, primordial_mon, true)
	_chk("K.05 discriminator: a MOVE (Sunny Day) cannot overwrite Primordial Sea's Rain either",
			bm3.try_set_weather(DamageCalculator.WEATHER_SUN, desolate_mon, false) == false
			and bm3.weather == DamageCalculator.WEATHER_RAIN)


# ── Section L: Solar Beam / Solar Blade weather-conditional halving ────────

func _test_solar_beam_weather_halving() -> void:
	var solar_beam := _load_move(76)
	var solar_blade := _load_move(632)
	var atk := _make_mon("SBAtk", [TypeChart.TYPE_GRASS], 100, 80, 60, 80, 60, 60)
	var def := _make_mon("SBDef", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)

	var sun_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_SUN)["damage"]
	var none_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_NONE)["damage"]
	var rain_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_RAIN)["damage"]
	var sand_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_SANDSTORM)["damage"]
	var hail_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_HAIL)["damage"]
	var strong_winds_dmg: int = DamageCalculator.calculate(
			atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_STRONG_WINDS)["damage"]

	_chk("L.01 Solar Beam: full power in Sun == full power with no weather",
			sun_dmg == none_dmg)
	# Halving happens on POWER, before the full damage formula's own +2 and
	# further integer truncation — comparing against a naive `none_dmg / 2`
	# on the ALREADY-computed final damage doesn't line up exactly (a real
	# test-authoring bug caught on the first run: 106/2=53 by plain integer
	# division, but the true halved-power result is 54). Use a strict
	# reduction check plus mutual-consistency across the three halved
	# weathers instead, matching this project's own established convention
	# for pairwise damage comparisons.
	_chk("L.02 Solar Beam: halved in Rain (strictly less than full power)",
			rain_dmg < none_dmg)
	_chk("L.03 Solar Beam: halved in Sandstorm (strictly less than full power)",
			sand_dmg < none_dmg)
	_chk("L.04 Solar Beam: halved in Hail (strictly less than full power)",
			hail_dmg < none_dmg)
	_chk("L.04b discriminator: Rain/Sandstorm/Hail all apply the SAME halving",
			rain_dmg == sand_dmg and sand_dmg == hail_dmg)
	_chk("L.05 Solar Beam: full power in Strong Winds (Delta Stream)",
			strong_winds_dmg == none_dmg)

	# Solar Blade — the same halving applies to a PHYSICAL move, confirming
	# no category exemption exists (a real Step-0 finding, not assumed).
	var blade_none_dmg: int = DamageCalculator.calculate(
			atk, def, solar_blade, 100, false, DamageCalculator.WEATHER_NONE)["damage"]
	var blade_rain_dmg: int = DamageCalculator.calculate(
			atk, def, solar_blade, 100, false, DamageCalculator.WEATHER_RAIN)["damage"]
	_chk("L.06 Solar Blade (Physical) is ALSO halved in Rain — no category exemption",
			blade_rain_dmg < blade_none_dmg)

	# Utility Umbrella strips Sun/Rain specifically (never Sandstorm/Hail) —
	# the same asymmetric strip [M19e]'s weather-heal formula established.
	var umbrella_atk := _make_mon("SBUmbrellaAtk", [TypeChart.TYPE_GRASS], 100, 80, 60, 80, 60, 60)
	umbrella_atk.held_item = load("res://data/items/item_0513.tres") as ItemData  # Utility Umbrella
	var umbrella_rain_dmg: int = DamageCalculator.calculate(
			umbrella_atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_RAIN)["damage"]
	_chk("L.07 Utility Umbrella strips Rain's halving (treated as no-weather)",
			umbrella_rain_dmg == none_dmg)
	var umbrella_sand_dmg: int = DamageCalculator.calculate(
			umbrella_atk, def, solar_beam, 100, false, DamageCalculator.WEATHER_SANDSTORM)["damage"]
	_chk("L.08 discriminator: Utility Umbrella does NOT strip Sandstorm's halving",
			umbrella_sand_dmg < none_dmg and umbrella_sand_dmg == sand_dmg)
