extends Node

# M16d test suite — Tier D move effects (entry hazards + Trick Room)
# EFFECT_SPIKES (layered, grounded-only, maxHP fraction scales with layers)
# EFFECT_TOXIC_SPIKES (layered, grounded-only, poison/toxic threshold, Poison-type absorb)
# EFFECT_STEALTH_ROCK (single application, Rock-type effectiveness, hits Flying too)
# EFFECT_RAPID_SPIN (damaging move that clears one hazard on the user's own side)
# EFFECT_TRICK_ROOM (field-wide speed-tiebreak reversal, toggles, 5 turns)
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_spikes()
	_test_section_3_toxic_spikes()
	_test_section_4_stealth_rock()
	_test_section_5_rapid_spin()
	_test_section_6_trick_room()

	var total := _pass + _fail
	print("m16d_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_move(id: int) -> MoveData:
	var path := "res://data/moves/move_%04d.tres" % id
	return load(path) as MoveData


func _load_ability(id: int) -> AbilityData:
	var path := "res://data/abilities/ability_%04d.tres" % id
	return load(path) as AbilityData


func _make_mon(species_name: String, level: int, types: Array[int],
		base_hp: int = 80, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_speed: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = species_name
	sp.types = types
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed = base_speed
	return BattlePokemon.from_species(sp, level)


# ── Section 1: Move data spot-checks ─────────────────────────────────────────

func _test_section_1_move_data() -> void:
	var spikes := _load_move(191)
	_chk("S1.01 Spikes is_spikes=true",    spikes.is_spikes == true)
	_chk("S1.02 Spikes accuracy=0",        spikes.accuracy == 0)
	_chk("S1.03 Spikes pp=20",             spikes.pp == 20)
	_chk("S1.04 Spikes ignores_protect",   spikes.ignores_protect == true)
	_chk("S1.05 Spikes type=GROUND",       spikes.type == TypeChart.TYPE_GROUND)

	var toxic_spikes := _load_move(390)
	_chk("S1.06 Toxic Spikes is_toxic_spikes=true", toxic_spikes.is_toxic_spikes == true)
	_chk("S1.07 Toxic Spikes accuracy=0",           toxic_spikes.accuracy == 0)
	_chk("S1.08 Toxic Spikes pp=20",                toxic_spikes.pp == 20)
	_chk("S1.09 Toxic Spikes type=POISON",          toxic_spikes.type == TypeChart.TYPE_POISON)

	var stealth_rock := _load_move(446)
	_chk("S1.10 Stealth Rock is_stealth_rock=true", stealth_rock.is_stealth_rock == true)
	_chk("S1.11 Stealth Rock accuracy=0",           stealth_rock.accuracy == 0)
	_chk("S1.12 Stealth Rock pp=20",                stealth_rock.pp == 20)
	_chk("S1.13 Stealth Rock type=ROCK",            stealth_rock.type == TypeChart.TYPE_ROCK)

	var rapid_spin := _load_move(229)
	_chk("S1.14 Rapid Spin is_rapid_spin=true", rapid_spin.is_rapid_spin == true)
	_chk("S1.15 Rapid Spin power=50",           rapid_spin.power == 50)
	_chk("S1.16 Rapid Spin accuracy=100",       rapid_spin.accuracy == 100)
	_chk("S1.17 Rapid Spin makes_contact",      rapid_spin.makes_contact == true)
	_chk("S1.18 Rapid Spin category=PHYS",      rapid_spin.category == 0)

	var trick_room := _load_move(433)
	_chk("S1.19 Trick Room is_trick_room=true", trick_room.is_trick_room == true)
	_chk("S1.20 Trick Room accuracy=0",         trick_room.accuracy == 0)
	_chk("S1.21 Trick Room pp=5",               trick_room.pp == 5)
	_chk("S1.22 Trick Room priority=-7",        trick_room.priority == -7)
	_chk("S1.23 Trick Room type=PSYCHIC",       trick_room.type == TypeChart.TYPE_PSYCHIC)

	# BattleManager defaults
	var bm := BattleManager.new()
	add_child(bm)
	_chk("S1.24 spikes_layers defaults 0",       bm._side_conditions[0]["spikes_layers"] == 0)
	_chk("S1.25 toxic_spikes_layers defaults 0",
			bm._side_conditions[0]["toxic_spikes_layers"] == 0)
	_chk("S1.26 stealth_rock defaults false",    bm._side_conditions[0]["stealth_rock"] == false)
	_chk("S1.27 side 1 hazards default zeroed",  bm._side_conditions[1]["spikes_layers"] == 0)
	_chk("S1.28 trick_room_turns defaults 0",    bm.trick_room_turns == 0)
	bm.queue_free()


# ── Section 2: EFFECT_SPIKES ──────────────────────────────────────────────────

func _test_section_2_spikes() -> void:
	var spikes := _load_move(191)
	var tackle := _load_move(33)

	# S2.01 Spikes targets the OPPONENT's side, not the caster's own — layers 1,2,3 stack,
	# fails at 3. Player (side 0) casts Spikes 4 times; should land on side 1 (opponent).
	var player1 := _make_mon("Sp_A", 50, [TypeChart.TYPE_GROUND], 300, 80, 300, 80, 300, 100)
	var opp1    := _make_mon("Sp_B", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player1.add_move(spikes)
	opp1.add_move(tackle)
	var set_events1: Array = []
	var fail_events1: Array[String] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_hit = true
	bm1.hazard_set.connect(func(side: int, name_: String, layers: int):
		set_events1.append([side, name_, layers]))
	bm1.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail_events1.append(r))
	for _t in range(4):
		bm1.queue_move(1, 0)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S2.01 Spikes targets opponent's side (side 1)",
			[1, "spikes", 1] in set_events1)
	_chk("S2.02 Spikes stacks to layer 2", [1, "spikes", 2] in set_events1)
	_chk("S2.03 Spikes stacks to layer 3", [1, "spikes", 3] in set_events1)
	_chk("S2.04 4th Spikes use fails (spikes_maxed)", "spikes_maxed" in fail_events1)

	# S2.05 Switch-in damage scales with layer count: 1 layer=1/8, 2=1/6, 3=1/4 of max HP.
	# Pre-set hazard layers directly, then let the battle-start send-out trigger the hit —
	# avoids any multi-turn recast pitfalls (M16c lesson): this is a single deterministic
	# event captured via signal, not inspected after the battle completes.
	for layers in [1, 2, 3]:
		var mon := _make_mon("Sp_L%d" % layers, 50, [TypeChart.TYPE_NORMAL], 800, 80, 80, 80, 80, 100)
		var opp := _make_mon("Sp_O%d" % layers, 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
		mon.add_move(tackle)
		opp.add_move(tackle)
		var expected_denom: int = (5 - layers) * 2
		var expected_dmg: int = mon.max_hp / expected_denom
		var captured: Array[int] = []
		var bm := BattleManager.new()
		add_child(bm)
		bm._side_conditions[0]["spikes_layers"] = layers
		bm.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
			if p == mon and hz == "spikes":
				captured.append(amount))
		bm.start_battle(mon, opp)
		bm.queue_free()
		_chk("S2.06.%d Spikes layer %d damage == maxHP/%d" % [layers, layers, expected_denom],
				captured.size() > 0 and captured[0] == expected_dmg)

	# S2.07 Grounded check: a Flying-type is immune to Spikes damage.
	var flying_mon := _make_mon("Sp_Fly", 50, [TypeChart.TYPE_FLYING], 300, 80, 80, 80, 80, 100)
	var opp7 := _make_mon("Sp_O7", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	flying_mon.add_move(tackle)
	opp7.add_move(tackle)
	var captured7: Array[int] = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._side_conditions[0]["spikes_layers"] = 3
	bm7.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == flying_mon and hz == "spikes":
			captured7.append(amount))
	bm7.start_battle(flying_mon, opp7)
	bm7.queue_free()
	_chk("S2.08 Flying-type takes no Spikes damage (ungrounded)", captured7.is_empty())

	# S2.09 Grounded check: a Levitate-ability holder is immune to Spikes damage.
	var levitate_ability := _load_ability(26)
	var lev_mon := _make_mon("Sp_Lev", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 100)
	lev_mon.ability = levitate_ability
	var opp9 := _make_mon("Sp_O9", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	lev_mon.add_move(tackle)
	opp9.add_move(tackle)
	var captured9: Array[int] = []
	var bm9 := BattleManager.new()
	add_child(bm9)
	bm9._side_conditions[0]["spikes_layers"] = 3
	bm9.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == lev_mon and hz == "spikes":
			captured9.append(amount))
	bm9.start_battle(lev_mon, opp9)
	bm9.queue_free()
	_chk("S2.10 Levitate holder takes no Spikes damage (ungrounded)", captured9.is_empty())

	# S2.11 Persistence across switch: Spikes stays on side 0 after a mid-battle voluntary
	# switch, and damages the newly-switched-in Pokémon too (side-bound, not battler-bound).
	var mon1_11 := _make_mon("Sp_M1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 300, 80, 300, 100)
	var mon2_11 := _make_mon("Sp_M2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 300, 80, 300, 90)
	mon1_11.add_move(tackle)
	mon2_11.add_move(tackle)
	var opp11 := _make_mon("Sp_O11", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	opp11.add_move(tackle)
	var player_party11 := BattleParty.new()
	player_party11.members = [mon1_11, mon2_11]
	player_party11.active_index = 0
	var captured11: Array[int] = []
	var bm11 := BattleManager.new()
	add_child(bm11)
	bm11._side_conditions[0]["spikes_layers"] = 1
	bm11.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == mon2_11 and hz == "spikes":
			captured11.append(amount))
	bm11.queue_switch(0, 1)  # turn 1: switch to mon2
	bm11.queue_move(1, 0)
	bm11.start_battle_with_parties(player_party11, BattleParty.single(opp11))
	bm11.queue_free()
	_chk("S2.12 Spikes persists across switch and damages the incoming Pokémon",
			captured11.size() > 0 and captured11[0] == mon2_11.max_hp / 8)


# ── Section 3: EFFECT_TOXIC_SPIKES ───────────────────────────────────────────

func _test_section_3_toxic_spikes() -> void:
	var toxic_spikes := _load_move(390)
	var tackle := _load_move(33)

	# S3.01 1 layer poisons a grounded switch-in.
	var mon1 := _make_mon("TS_A", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 100)
	var opp1 := _make_mon("TS_B", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	mon1.add_move(tackle)
	opp1.add_move(tackle)
	var status_events1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._side_conditions[0]["toxic_spikes_layers"] = 1
	bm1.hazard_status_applied.connect(func(p: BattlePokemon, status: int):
		if p == mon1:
			status_events1.append(status))
	bm1.start_battle(mon1, opp1)
	bm1.queue_free()
	_chk("S3.01 1 layer inflicts regular poison",
			status_events1 == [BattlePokemon.STATUS_POISON])

	# S3.02 2 layers badly poisons (toxic) a grounded switch-in.
	var mon2 := _make_mon("TS_C", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 100)
	var opp2 := _make_mon("TS_D", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	mon2.add_move(tackle)
	opp2.add_move(tackle)
	var status_events2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._side_conditions[0]["toxic_spikes_layers"] = 2
	bm2.hazard_status_applied.connect(func(p: BattlePokemon, status: int):
		if p == mon2:
			status_events2.append(status))
	bm2.start_battle(mon2, opp2)
	bm2.queue_free()
	_chk("S3.02 2 layers inflict badly poisoned (toxic)",
			status_events2 == [BattlePokemon.STATUS_TOXIC])

	# S3.03 A grounded Poison-type switch-in ABSORBS (clears) Toxic Spikes instead of
	# being poisoned itself.
	var poison_mon := _make_mon("TS_E", 50, [TypeChart.TYPE_POISON], 300, 80, 80, 80, 80, 100)
	var opp3 := _make_mon("TS_F", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	poison_mon.add_move(tackle)
	opp3.add_move(tackle)
	var absorbed_events3: Array = []
	var status_events3: Array = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._side_conditions[0]["toxic_spikes_layers"] = 2
	bm3.hazard_absorbed.connect(func(side: int, hz: String): absorbed_events3.append([side, hz]))
	bm3.hazard_status_applied.connect(func(p: BattlePokemon, status: int):
		if p == poison_mon:
			status_events3.append(status))
	bm3.start_battle(poison_mon, opp3)
	_chk("S3.04 Poison-type switch-in absorbs Toxic Spikes",
			[0, "toxic_spikes"] in absorbed_events3)
	_chk("S3.05 Toxic Spikes layers cleared to 0 after absorb",
			bm3._side_conditions[0]["toxic_spikes_layers"] == 0)
	_chk("S3.06 Absorbing Pokémon itself is NOT poisoned", status_events3.is_empty())
	bm3.queue_free()

	# S3.07 Steel-type switch-in (grounded) is immune to the poison itself (reuses
	# StatusManager.try_apply_status's existing Poison/Steel immunity) — hazard remains up
	# since it wasn't absorbed (only Poison-type absorbs).
	var steel_mon := _make_mon("TS_G", 50, [TypeChart.TYPE_STEEL], 300, 80, 80, 80, 80, 100)
	var opp7 := _make_mon("TS_H", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	steel_mon.add_move(tackle)
	opp7.add_move(tackle)
	var status_events7: Array = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._side_conditions[0]["toxic_spikes_layers"] = 1
	bm7.hazard_status_applied.connect(func(p: BattlePokemon, status: int):
		if p == steel_mon:
			status_events7.append(status))
	bm7.start_battle(steel_mon, opp7)
	bm7.queue_free()
	_chk("S3.08 Steel-type switch-in is not poisoned (type immunity)", status_events7.is_empty())
	_chk("S3.09 Toxic Spikes hazard NOT cleared by a non-absorbing immune switch-in",
			bm7._side_conditions[0]["toxic_spikes_layers"] == 1)

	# S3.10 Ungrounded (Flying-type) switch-in is entirely unaffected — no poison, no absorb
	# even though not Poison-type.
	var flying_mon := _make_mon("TS_I", 50, [TypeChart.TYPE_FLYING], 300, 80, 80, 80, 80, 100)
	var opp10 := _make_mon("TS_J", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	flying_mon.add_move(tackle)
	opp10.add_move(tackle)
	var status_events10: Array = []
	var bm10 := BattleManager.new()
	add_child(bm10)
	bm10._side_conditions[0]["toxic_spikes_layers"] = 1
	bm10.hazard_status_applied.connect(func(p: BattlePokemon, status: int):
		if p == flying_mon:
			status_events10.append(status))
	bm10.start_battle(flying_mon, opp10)
	bm10.queue_free()
	_chk("S3.11 Flying-type switch-in unaffected by Toxic Spikes", status_events10.is_empty())
	_chk("S3.12 Toxic Spikes hazard untouched by ungrounded switch-in",
			bm10._side_conditions[0]["toxic_spikes_layers"] == 1)

	# S3.13 Setup: layers cap at 2, fails on 3rd use.
	var player13 := _make_mon("TS_K", 50, [TypeChart.TYPE_POISON], 300, 80, 300, 80, 300, 100)
	var opp13    := _make_mon("TS_L", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player13.add_move(toxic_spikes)
	opp13.add_move(tackle)
	var fail_events13: Array[String] = []
	var bm13 := BattleManager.new()
	add_child(bm13)
	bm13._force_hit = true
	bm13.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail_events13.append(r))
	for _t in range(3):
		bm13.queue_move(1, 0)
	bm13.start_battle(player13, opp13)
	bm13.queue_free()
	_chk("S3.14 3rd Toxic Spikes use fails (toxic_spikes_maxed)",
			"toxic_spikes_maxed" in fail_events13)


# ── Section 4: EFFECT_STEALTH_ROCK ────────────────────────────────────────────

func _test_section_4_stealth_rock() -> void:
	var stealth_rock := _load_move(446)
	var tackle := _load_move(33)

	# S4.01 Setup: single application, fails if already up.
	var player1 := _make_mon("SR_A", 50, [TypeChart.TYPE_ROCK], 300, 80, 300, 80, 300, 100)
	var opp1    := _make_mon("SR_B", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player1.add_move(stealth_rock)
	opp1.add_move(tackle)
	var set_events1: Array = []
	var fail_events1: Array[String] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_hit = true
	bm1.hazard_set.connect(func(side: int, name_: String, layers: int):
		set_events1.append([side, name_, layers]))
	bm1.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail_events1.append(r))
	for _t in range(2):
		bm1.queue_move(1, 0)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S4.01 Stealth Rock set on opponent's side", [1, "stealth_rock", 1] in set_events1)
	_chk("S4.02 2nd Stealth Rock use fails (already set)",
			"stealth_rock_already_set" in fail_events1)

	# S4.03 Neutral (1x) damage == maxHP/8.
	var normal_mon := _make_mon("SR_C", 50, [TypeChart.TYPE_NORMAL], 800, 80, 80, 80, 80, 100)
	var opp3 := _make_mon("SR_D", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	normal_mon.add_move(tackle)
	opp3.add_move(tackle)
	var captured3: Array[int] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._side_conditions[0]["stealth_rock"] = true
	bm3.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == normal_mon and hz == "stealth_rock":
			captured3.append(amount))
	bm3.start_battle(normal_mon, opp3)
	bm3.queue_free()
	_chk("S4.04 Normal-type Stealth Rock damage == maxHP/8",
			captured3.size() > 0 and captured3[0] == normal_mon.max_hp / 8)

	# S4.05 4x-weak dual type (Bug/Flying — both individually 2x weak to Rock) takes maxHP/2.
	var quadweak_mon := _make_mon("SR_E", 50, [TypeChart.TYPE_BUG, TypeChart.TYPE_FLYING],
			800, 80, 80, 80, 80, 100)
	var opp5 := _make_mon("SR_F", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	quadweak_mon.add_move(tackle)
	opp5.add_move(tackle)
	var captured5: Array[int] = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._side_conditions[0]["stealth_rock"] = true
	bm5.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == quadweak_mon and hz == "stealth_rock":
			captured5.append(amount))
	bm5.start_battle(quadweak_mon, opp5)
	bm5.queue_free()
	_chk("S4.06 4x-weak (Bug/Flying) Stealth Rock damage == maxHP/2",
			captured5.size() > 0 and captured5[0] == quadweak_mon.max_hp / 2)

	# S4.07 Resistant type (Fighting, 0.5x vs Rock) takes maxHP/16.
	var resist_mon := _make_mon("SR_G", 50, [TypeChart.TYPE_FIGHTING], 800, 80, 80, 80, 80, 100)
	var opp7 := _make_mon("SR_H", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	resist_mon.add_move(tackle)
	opp7.add_move(tackle)
	var captured7: Array[int] = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._side_conditions[0]["stealth_rock"] = true
	bm7.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == resist_mon and hz == "stealth_rock":
			captured7.append(amount))
	bm7.start_battle(resist_mon, opp7)
	bm7.queue_free()
	_chk("S4.08 Resistant (Fighting) Stealth Rock damage == maxHP/16",
			captured7.size() > 0 and captured7[0] == resist_mon.max_hp / 16)

	# S4.09 Stealth Rock DOES hit a Flying-type switch-in (unlike Spikes) — not grounded-gated.
	var flying_mon := _make_mon("SR_I", 50, [TypeChart.TYPE_FLYING], 800, 80, 80, 80, 80, 100)
	var opp9 := _make_mon("SR_J", 50, [TypeChart.TYPE_NORMAL], 80, 5, 80, 80, 80, 50)
	flying_mon.add_move(tackle)
	opp9.add_move(tackle)
	var captured9: Array[int] = []
	var bm9 := BattleManager.new()
	add_child(bm9)
	bm9._side_conditions[0]["stealth_rock"] = true
	bm9.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == flying_mon and hz == "stealth_rock":
			captured9.append(amount))
	bm9.start_battle(flying_mon, opp9)
	bm9.queue_free()
	# Flying is 2x weak to Rock (single-type) → maxHP/4.
	_chk("S4.10 Stealth Rock hits Flying-type switch-in (maxHP/4, 2x weak)",
			captured9.size() > 0 and captured9[0] == flying_mon.max_hp / 4)


# ── Section 5: EFFECT_RAPID_SPIN ──────────────────────────────────────────────

func _test_section_5_rapid_spin() -> void:
	var rapid_spin := _load_move(229)
	var tackle := _load_move(33)
	var substitute := _load_move(164)

	# S5.01 Rapid Spin clears Spikes from the USER's own side after dealing damage.
	var player1 := _make_mon("RS_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("RS_B", 50, [TypeChart.TYPE_NORMAL], 300, 30, 300, 80, 300, 50)
	player1.add_move(rapid_spin)
	opp1.add_move(tackle)
	var cleared_events1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._side_conditions[0]["spikes_layers"] = 2
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.hazards_cleared.connect(func(side: int, hz: String): cleared_events1.append([side, hz]))
	bm1.queue_move(1, 0)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S5.01 Rapid Spin clears Spikes on user's own side", [0, "spikes"] in cleared_events1)
	_chk("S5.02 spikes_layers reset to 0", bm1._side_conditions[0]["spikes_layers"] == 0)

	# S5.03 With multiple hazard types up, Rapid Spin clears only ONE per use (Spikes first).
	# player3's ONLY move is Rapid Spin, so it keeps firing every turn once auto-select
	# takes over — a long-running battle would eventually clear Toxic Spikes and Stealth
	# Rock too (M16c-style pitfall), so this snapshots state via the FIRST hazards_cleared
	# signal rather than reading _side_conditions after the whole battle completes.
	var player3 := _make_mon("RS_C", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("RS_D", 50, [TypeChart.TYPE_NORMAL], 300, 30, 300, 80, 300, 50)
	player3.add_move(rapid_spin)
	opp3.add_move(tackle)
	var first_clear3: Array = []
	var snapshot3: Array[Dictionary] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._side_conditions[0]["spikes_layers"] = 1
	bm3._side_conditions[0]["toxic_spikes_layers"] = 2
	bm3._side_conditions[0]["stealth_rock"] = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.hazards_cleared.connect(func(side: int, hz: String):
		if first_clear3.is_empty():
			first_clear3.append([side, hz])
			snapshot3.append({
				"spikes": bm3._side_conditions[0]["spikes_layers"],
				"toxic": bm3._side_conditions[0]["toxic_spikes_layers"],
				"rock": bm3._side_conditions[0]["stealth_rock"],
			}))
	bm3.queue_move(1, 0)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S5.04 Only Spikes cleared (first in order)",
			first_clear3 == [[0, "spikes"]])
	_chk("S5.05 Spikes reads 0 at the moment of that clear",
			snapshot3.size() > 0 and snapshot3[0]["spikes"] == 0)
	_chk("S5.06 Toxic Spikes still 2 at that same moment",
			snapshot3.size() > 0 and snapshot3[0]["toxic"] == 2)
	_chk("S5.07 Stealth Rock still active at that same moment",
			snapshot3.size() > 0 and snapshot3[0]["rock"] == true)

	# S5.07 A missed Rapid Spin clears nothing.
	var player7 := _make_mon("RS_E", 50, [TypeChart.TYPE_NORMAL], 300, 80, 300, 80, 300, 100)
	var opp7    := _make_mon("RS_F", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player7.add_move(rapid_spin)
	opp7.add_move(tackle)
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._side_conditions[0]["spikes_layers"] = 1
	bm7._force_hit = false
	var cleared_events7: Array = []
	bm7.hazards_cleared.connect(func(side: int, hz: String): cleared_events7.append([side, hz]))
	bm7.start_battle(player7, opp7)
	bm7.queue_free()
	_chk("S5.08 Missed Rapid Spin clears nothing", cleared_events7.is_empty())

	# S5.09 Rapid Spin still clears the user's own hazards even when the hit lands on the
	# DEFENDER's Substitute (INCLUDING_SUBSTITUTES in source). Opponent must be FASTER so
	# its Substitute is already up before player's Rapid Spin fires within the same turn —
	# if player acted first, Rapid Spin would hit opp directly (no sub yet) and clear the
	# hazard from that direct hit instead, failing to isolate the substitute case at all.
	var player9 := _make_mon("RS_G", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp9    := _make_mon("RS_H", 50, [TypeChart.TYPE_NORMAL], 300, 30, 300, 80, 300, 100)
	player9.add_move(rapid_spin)
	opp9.add_move(substitute)
	var bm9 := BattleManager.new()
	add_child(bm9)
	bm9._side_conditions[0]["spikes_layers"] = 1
	bm9._force_roll = 100
	bm9._force_crit = false
	bm9.queue_move(1, 0)  # opp (faster) sets up Substitute turn 1, before player acts
	bm9.start_battle(player9, opp9)
	bm9.queue_free()
	_chk("S5.10 Rapid Spin clears own-side hazard even hitting a Substitute",
			bm9._side_conditions[0]["spikes_layers"] == 0)


# ── Section 6: EFFECT_TRICK_ROOM ──────────────────────────────────────────────

func _test_section_6_trick_room() -> void:
	var trick_room := _load_move(433)
	var tackle := _load_move(33)
	var quick_attack := _load_move(98)  # priority=1

	# S6.01 Using Trick Room activates it (trick_room_turns=5) and emits trick_room_set.
	# player1's ONLY move is Trick Room, and it TOGGLES — a long-running battle would fire
	# trick_room_set/trick_room_ended repeatedly as it cycles on/off/on/off (M16c-style
	# pitfall), so this only counts/snapshots the FIRST occurrence rather than asserting an
	# exact count over the whole battle.
	var player1 := _make_mon("TR_A", 50, [TypeChart.TYPE_PSYCHIC], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("TR_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(trick_room)
	opp1.add_move(tackle)
	var set_events1: Array[int] = []
	var turns_at_set1: Array[int] = [-1]
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.trick_room_set.connect(func():
		if set_events1.is_empty():
			set_events1.append(1)
			turns_at_set1[0] = bm1.trick_room_turns)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S6.01 trick_room_set emitted on first activation", set_events1.size() == 1)
	_chk("S6.02 trick_room_turns == 5 right after activation", turns_at_set1[0] == 5)

	# S6.03 Speed-order reversal: a deliberately SLOWER Pokémon moves first while Trick
	# Room is active (pre-set before battle so it's already in effect for turn 1's order).
	var fast_mon := _make_mon("TR_C", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 150)
	var slow_mon := _make_mon("TR_D", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 30)
	fast_mon.add_move(tackle)
	slow_mon.add_move(tackle)
	var order3: Array[BattlePokemon] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.trick_room_turns = 5
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, _mv: MoveData, _dmg: int):
		if order3.size() < 2:
			order3.append(a))
	bm3.start_battle(fast_mon, slow_mon)
	bm3.queue_free()
	_chk("S6.04 Slower Pokémon acts first under Trick Room",
			order3.size() == 2 and order3[0] == slow_mon and order3[1] == fast_mon)

	# S6.05 Sanity check: WITHOUT Trick Room, the same matchup has the faster mon act first
	# (confirms S6.04 is really Trick Room's doing, not some other ordering quirk).
	var fast_mon5 := _make_mon("TR_E", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 150)
	var slow_mon5 := _make_mon("TR_F", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 30)
	fast_mon5.add_move(tackle)
	slow_mon5.add_move(tackle)
	var order5: Array[BattlePokemon] = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_roll = 100
	bm5._force_crit = false
	bm5.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, _mv: MoveData, _dmg: int):
		if order5.size() < 2:
			order5.append(a))
	bm5.start_battle(fast_mon5, slow_mon5)
	bm5.queue_free()
	_chk("S6.06 Without Trick Room, faster Pokémon acts first",
			order5.size() == 2 and order5[0] == fast_mon5 and order5[1] == slow_mon5)

	# S6.07 Priority still overrides Trick Room: the naturally-faster mon using a priority
	# move still acts first, even though Trick Room would otherwise reverse the speed order.
	var fast_priority_mon := _make_mon("TR_G", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 150)
	var slow_mon7 := _make_mon("TR_H", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 30)
	fast_priority_mon.add_move(quick_attack)
	slow_mon7.add_move(tackle)
	var order7: Array[BattlePokemon] = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7.trick_room_turns = 5
	bm7._force_roll = 100
	bm7._force_crit = false
	bm7.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, _mv: MoveData, _dmg: int):
		if order7.size() < 2:
			order7.append(a))
	bm7.start_battle(fast_priority_mon, slow_mon7)
	bm7.queue_free()
	_chk("S6.08 Priority move still goes first despite Trick Room",
			order7.size() == 2 and order7[0] == fast_priority_mon)

	# S6.09 Toggle off: using Trick Room again while active cancels it immediately
	# (trick_room_turns -> 0, NOT refreshed to 5), emits trick_room_ended.
	# player9's ONLY move is Trick Room, so a long-running battle would keep toggling it
	# on/off/on/off — snapshot the FIRST trick_room_ended (the toggle-off from this test's
	# specific preset) rather than counting occurrences over the whole battle.
	var player9 := _make_mon("TR_I", 50, [TypeChart.TYPE_PSYCHIC], 300, 80, 300, 80, 300, 100)
	var opp9    := _make_mon("TR_J", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player9.add_move(trick_room)
	opp9.add_move(tackle)
	var ended_events9: Array[int] = []
	var turns_at_end9: Array[int] = [-1]
	var bm9 := BattleManager.new()
	add_child(bm9)
	bm9.trick_room_turns = 5  # already active from a prior (simulated) use
	bm9.trick_room_ended.connect(func():
		if ended_events9.is_empty():
			ended_events9.append(1)
			turns_at_end9[0] = bm9.trick_room_turns)
	bm9.start_battle(player9, opp9)
	bm9.queue_free()
	_chk("S6.10 Re-using Trick Room while active toggles it off immediately (turns -> 0)",
			turns_at_end9[0] == 0)
	_chk("S6.11 trick_room_ended emitted on toggle-off", ended_events9.size() == 1)

	# S6.12 Natural expiry: trick_room_turns decrements 5→4→3→2→1→0 over 5 end-of-turns,
	# and trick_room_ended fires when it reaches 0. Uses a Pokémon whose only move is
	# harmless (Tackle) so nothing else complicates the countdown, and the phase_changed
	# capture is bounded to exactly 5 entries to avoid the M16c-style long-battle pitfall.
	var player12 := _make_mon("TR_K", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 100)
	var opp12    := _make_mon("TR_L", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player12.add_move(tackle)
	opp12.add_move(tackle)
	var turns_seq12: Array[int] = []
	var ended_events12: Array = []
	var bm12 := BattleManager.new()
	add_child(bm12)
	bm12.trick_room_turns = 5
	bm12.trick_room_ended.connect(func():
		if ended_events12.size() < 1:
			ended_events12.append(true))
	bm12.phase_changed.connect(func(p: BattleManager.BattlePhase):
		if p == BattleManager.BattlePhase.SWITCH_PROMPT and turns_seq12.size() < 5:
			turns_seq12.append(bm12.trick_room_turns))
	for _t in range(5):
		bm12.queue_move(1, 0)
	bm12.start_battle(player12, opp12)
	bm12.queue_free()
	_chk("S6.13 trick_room_turns sequence 4,3,2,1,0 over 5 end-of-turns",
			turns_seq12 == [4, 3, 2, 1, 0])
	_chk("S6.14 trick_room_ended fired on natural expiry", ended_events12.size() == 1)
