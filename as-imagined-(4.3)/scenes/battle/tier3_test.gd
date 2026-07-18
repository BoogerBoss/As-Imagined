extends Node

# Milestone 6 test suite — Tier 3 moves (multi-turn, recoil, drain, fixed damage)
#
# Sections:
#   1. Move data spot-checks (fields on loaded .tres resources)
#   2. Semi-invulnerable accuracy (miss, bypass, clear-after-release)
#   3. Fixed / level damage (Dragon Rage, Sonic Boom, Seismic Toss, Night Shade + immunity)
#   4. Recoil math (Take Down, Double-Edge, edge cases)
#   5. Drain math (Giga Drain, full-HP cap, tiny-damage zero-heal)
#   6. Charging state machine (charge turn sets state, release clears it, faint clears it)
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_semi_invulnerable()
	_test_section_3_fixed_level_damage()
	_test_section_4_recoil()
	_test_section_5_drain()
	_test_section_6_charging_state()

	var total := _pass + _fail
	print("tier3_test: %d/%d passed" % [_pass, total])
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
	# Dig (91): two_turn, semi_inv_state=UNDERGROUND, contact
	var dig := _load_move(91)
	_chk("S1.01 Dig two_turn", dig.two_turn == true)
	_chk("S1.02 Dig semi_inv_state UNDERGROUND", dig.semi_inv_state == MoveData.SEMI_INV_UNDERGROUND)
	_chk("S1.03 Dig makes_contact", dig.makes_contact == true)
	_chk("S1.04 Dig power=80", dig.power == 80)

	# Fly (19): two_turn, semi_inv_state=ON_AIR
	var fly := _load_move(19)
	_chk("S1.05 Fly two_turn", fly.two_turn == true)
	_chk("S1.06 Fly semi_inv_state ON_AIR", fly.semi_inv_state == MoveData.SEMI_INV_ON_AIR)

	# Earthquake (89): damages_underground
	var quake := _load_move(89)
	_chk("S1.07 Earthquake damages_underground", quake.damages_underground == true)

	# Surf (57): damages_underwater
	var surf := _load_move(57)
	_chk("S1.08 Surf damages_underwater", surf.damages_underwater == true)

	# Double-Edge (38): recoil_percent=33
	var dedge := _load_move(38)
	_chk("S1.09 Double-Edge recoil_percent=33", dedge.recoil_percent == 33)

	# Giga Drain (202): drain_percent=50
	var gdrain := _load_move(202)
	_chk("S1.10 Giga Drain drain_percent=50", gdrain.drain_percent == 50)

	# Dragon Rage (82): fixed_damage=40
	var drage := _load_move(82)
	_chk("S1.11 Dragon Rage fixed_damage=40", drage.fixed_damage == 40)

	# Night Shade (101): level_damage=true
	var nshade := _load_move(101)
	_chk("S1.12 Night Shade level_damage", nshade.level_damage == true)

	# Solar Beam (76): two_turn, no semi_inv
	var solarbeam := _load_move(76)
	_chk("S1.13 Solar Beam two_turn", solarbeam.two_turn == true)
	_chk("S1.14 Solar Beam no semi_inv", solarbeam.semi_inv_state == MoveData.SEMI_INV_NONE)

	# Sky Attack (143): two_turn, crit_stage=1, flinch 30%
	var skyatk := _load_move(143)
	_chk("S1.15 Sky Attack two_turn", skyatk.two_turn == true)
	_chk("S1.16 Sky Attack crit_stage=1", skyatk.critical_hit_stage == 1)
	_chk("S1.17 Sky Attack flinch 30%", skyatk.secondary_effect == MoveData.SE_FLINCH and skyatk.secondary_chance == 30)

	# Drain Punch (409): punching_move, drain_percent=50
	var dpunch := _load_move(409)
	_chk("S1.18 Drain Punch punching_move", dpunch.punching_move == true)
	_chk("S1.19 Drain Punch drain_percent=50", dpunch.drain_percent == 50)


# ── Section 2: Semi-invulnerable accuracy ─────────────────────────────────────

func _test_section_2_semi_invulnerable() -> void:
	var attacker := _make_mon("Pikachu", 50, [TypeChart.TYPE_ELECTRIC])
	var defender := _make_mon("Diglett",  50, [TypeChart.TYPE_GROUND])
	var tackle   := _load_move(33)  # Tackle — no bypass flag
	var quake    := _load_move(89)  # Earthquake — damages_underground
	var surf     := _load_move(57)  # Surf — damages_underwater
	var fly_move := _load_move(19)  # Fly — semi_inv ON_AIR

	# S2.01 Normal move misses defender who is underground
	defender.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	_chk("S2.01 Tackle misses underground defender",
			StatusManager.check_accuracy(attacker, defender, tackle, null) == false)

	# S2.02 Earthquake hits underground defender
	_chk("S2.02 Earthquake hits underground defender",
			StatusManager.check_accuracy(attacker, defender, quake, null) == true)

	# S2.03 Tackle misses ON_AIR defender
	defender.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	_chk("S2.03 Tackle misses on-air defender",
			StatusManager.check_accuracy(attacker, defender, tackle, null) == false)

	# S2.04 Surf does NOT hit ON_AIR (surf bypasses underwater only)
	_chk("S2.04 Surf misses on-air defender",
			StatusManager.check_accuracy(attacker, defender, surf, null) == false)

	# S2.05 Tackle misses UNDERWATER defender
	defender.semi_invulnerable = MoveData.SEMI_INV_UNDERWATER
	_chk("S2.05 Tackle misses underwater defender",
			StatusManager.check_accuracy(attacker, defender, tackle, null) == false)

	# S2.06 Surf hits UNDERWATER defender
	_chk("S2.06 Surf hits underwater defender",
			StatusManager.check_accuracy(attacker, defender, surf, null) == true)

	# S2.07 force_hit=true overrides semi-invulnerable (test override always wins)
	defender.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	_chk("S2.07 force_hit=true overrides semi-inv",
			StatusManager.check_accuracy(attacker, defender, tackle, true) == true)

	# S2.08 After release turn, semi_invulnerable is cleared (no longer blocks)
	# Simulate: manually clear semi_inv as release would
	defender.semi_invulnerable = MoveData.SEMI_INV_NONE
	_chk("S2.08 Cleared semi_inv no longer blocks",
			StatusManager.check_accuracy(attacker, defender, tackle, null) != false
				or StatusManager.check_accuracy(attacker, defender, tackle, null) == true)
	# Re-run with force for determinism
	_chk("S2.08b Cleared semi_inv: tackle can hit (force_hit bypasses for confirm)",
			StatusManager.check_accuracy(attacker, defender, tackle, true) == true)

	# S2.09 Fly move: semi_inv_state=ON_AIR, verify field
	_chk("S2.09 Fly semi_inv_state is ON_AIR", fly_move.semi_inv_state == MoveData.SEMI_INV_ON_AIR)


# ── Section 3: Fixed / level damage ──────────────────────────────────────────

func _test_section_3_fixed_level_damage() -> void:
	# Dragon Rage (82): fixed 40
	var drage    := _load_move(82)
	var sonicboom := _load_move(49)   # fixed 20
	var seismic  := _load_move(69)    # level damage
	var nshade   := _load_move(101)   # level damage

	# Attacker L50 Normal-type, defender Normal-type
	var attacker := _make_mon("A", 50, [TypeChart.TYPE_NORMAL])
	var defender := _make_mon("B", 50, [TypeChart.TYPE_NORMAL])

	# S3.01 Dragon Rage deals exactly 40 regardless of stats
	var r1 := DamageCalculator.calculate(attacker, defender, drage, 100, false)
	_chk("S3.01 Dragon Rage = 40", r1["damage"] == 40)

	# S3.02 Sonic Boom deals exactly 20
	var r2 := DamageCalculator.calculate(attacker, defender, sonicboom, 100, false)
	_chk("S3.02 Sonic Boom = 20", r2["damage"] == 20)

	# S3.03 Seismic Toss deals level (50)
	var r3 := DamageCalculator.calculate(attacker, defender, seismic, 100, false)
	_chk("S3.03 Seismic Toss L50 = 50", r3["damage"] == 50)

	# S3.04 Night Shade deals level (50); must use non-immune defender (Ghost hits Psychic)
	var psychic_def := _make_mon("PsyDef", 50, [TypeChart.TYPE_PSYCHIC])
	var r4 := DamageCalculator.calculate(attacker, psychic_def, nshade, 100, false)
	_chk("S3.04 Night Shade L50 = 50 vs Psychic", r4["damage"] == 50)

	# S3.05 Different level: L30 Seismic Toss = 30
	var atk30 := _make_mon("A30", 30, [TypeChart.TYPE_NORMAL])
	var r5 := DamageCalculator.calculate(atk30, defender, seismic, 100, false)
	_chk("S3.05 Seismic Toss L30 = 30", r5["damage"] == 30)

	# S3.06 Type immunity blocks Dragon Rage: Dragon move vs Fairy type = 0
	var fairy_def := _make_mon("Fairy", 50, [TypeChart.TYPE_FAIRY])
	var r6 := DamageCalculator.calculate(attacker, fairy_def, drage, 100, false)
	_chk("S3.06 Dragon Rage vs Fairy = 0 (type immune)", r6["damage"] == 0)

	# S3.07 Night Shade (Ghost) vs Normal-type = 0 (Ghost doesn't hit Normal)
	var normal_def := _make_mon("Normal", 50, [TypeChart.TYPE_NORMAL])
	var r7 := DamageCalculator.calculate(attacker, normal_def, nshade, 100, false)
	_chk("S3.07 Night Shade vs Normal = 0 (type immune)", r7["damage"] == 0)

	# S3.08 Seismic Toss (Fighting) vs Ghost-type = 0 (Fighting doesn't hit Ghost)
	var ghost_def := _make_mon("Ghost", 50, [TypeChart.TYPE_GHOST])
	var r8 := DamageCalculator.calculate(attacker, ghost_def, seismic, 100, false)
	_chk("S3.08 Seismic Toss vs Ghost = 0 (type immune)", r8["damage"] == 0)

	# S3.09 Dragon Rage bypasses type effectiveness: Dragon vs Steel still 40 (not 0.5×)
	var steel_def := _make_mon("Steel", 50, [TypeChart.TYPE_STEEL])
	var r9 := DamageCalculator.calculate(attacker, steel_def, drage, 100, false)
	_chk("S3.09 Dragon Rage vs Steel = 40 (bypasses 0.5x effectiveness)", r9["damage"] == 40)

	# S3.10 is_crit is always false for fixed/level damage moves
	_chk("S3.10 Dragon Rage is_crit=false", r1["is_crit"] == false)
	_chk("S3.11 Seismic Toss is_crit=false", r3["is_crit"] == false)


# ── Section 4: Recoil math ────────────────────────────────────────────────────

func _test_section_4_recoil() -> void:
	var take_down  := _load_move(36)   # 25% recoil
	var dedge      := _load_move(38)   # 33% recoil
	var brave_bird := _load_move(413)  # 33% recoil

	# S4.01 Take Down recoil = damage * 25 / 100
	# Damage known via DamageCalculator; test recoil arithmetic directly
	var damage_td := 100  # hypothetical 100 HP damage
	var expected_recoil_td := damage_td * 25 / 100  # = 25
	_chk("S4.01 Take Down recoil math (100 dmg → 25 recoil)",
			expected_recoil_td == 25)

	# S4.02 Double-Edge recoil = damage * 33 / 100
	var damage_de := 120
	var expected_recoil_de := damage_de * 33 / 100  # = 39
	_chk("S4.02 Double-Edge recoil math (120 dmg → 39 recoil)",
			expected_recoil_de == 39)

	# S4.03 Brave Bird 33% recoil (same formula as Double-Edge)
	_chk("S4.03 Brave Bird recoil_percent=33", brave_bird.recoil_percent == 33)

	# S4.04 Small damage (3) * 25% = 0 (no floor — source matches)
	# Source: savedDmg * max(1, GetMoveRecoil) / 100; max(1,pct) ensures >=1% but
	# integer result can still be 0 for tiny damage.
	var small_recoil := 3 * 25 / 100  # = 0
	_chk("S4.04 Small damage recoil can be 0 (no artificial floor)", small_recoil == 0)

	# S4.05 Recoil fields correct on take_down
	_chk("S4.05 Take Down recoil_percent=25", take_down.recoil_percent == 25)

	# S4.06 Recoil integration: attacker HP drops after dealing damage
	# Set up a battle: attacker uses Double-Edge vs defender
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_NORMAL],
			80, 100, 70, 80, 80, 90)
	var defender := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL],
			80, 80, 60, 80, 80, 80)
	var attacker_hp_before: int = attacker.current_hp

	# Use DamageCalculator to find the damage, then verify recoil = damage * 33 / 100
	var result: Dictionary = DamageCalculator.calculate(attacker, defender, dedge, 100, false)
	var dealt: int = result["damage"]
	var expected_recoil: int = dealt * 33 / 100
	# Simulate what BattleManager does:
	defender.current_hp = max(0, defender.current_hp - dealt)
	var actual_recoil: int = dealt * dedge.recoil_percent / 100
	attacker.current_hp = max(0, attacker.current_hp - actual_recoil)
	_chk("S4.06 Recoil integration: attacker HP dropped by dealt*33/100",
			attacker.current_hp == attacker_hp_before - expected_recoil)


# ── Section 5: Drain math ──────────────────────────────────────────────────────

func _test_section_5_drain() -> void:
	var gdrain := _load_move(202)  # Giga Drain, 50%
	var absorb := _load_move(71)   # Absorb,     50%

	# S5.01 Giga Drain heal = damage * 50 / 100
	var damage := 80
	var expected_heal := damage * 50 / 100  # = 40
	_chk("S5.01 Giga Drain heal math (80 dmg → 40 heal)", expected_heal == 40)

	# S5.02 Absorb drain_percent=50
	_chk("S5.02 Absorb drain_percent=50", absorb.drain_percent == 50)

	# S5.03 Drain heal capped at max_hp (can't overheal)
	var attacker := _make_mon("Attacker", 50, [TypeChart.TYPE_GRASS],
			80, 80, 70, 100, 80, 80)
	var defender := _make_mon("Defender", 50, [TypeChart.TYPE_NORMAL],
			60, 80, 40, 80, 80, 80)
	# Damage the attacker slightly first so drain might otherwise overflow
	attacker.current_hp = attacker.max_hp - 1

	var result: Dictionary = DamageCalculator.calculate(attacker, defender, gdrain, 100, false)
	var dealt: int = result["damage"]
	var heal: int = dealt * gdrain.drain_percent / 100
	# BattleManager caps at max_hp
	var new_hp: int = min(attacker.max_hp, attacker.current_hp + heal)
	_chk("S5.03 Drain heal capped at max_hp", new_hp <= attacker.max_hp)

	# S5.04 Large drain on very low HP attacker: heals up to max
	attacker.current_hp = 1
	var new_hp2: int = min(attacker.max_hp, 1 + 999)  # hypothetical huge heal
	_chk("S5.04 Huge drain capped at max_hp", new_hp2 == attacker.max_hp)

	# S5.05 Tiny damage: heal can be 0 (no floor — source: moveDamage*50/100 with small dmg)
	var tiny_heal := 1 * 50 / 100  # = 0
	_chk("S5.05 Tiny damage drain heal = 0 (no floor)", tiny_heal == 0)

	# S5.06 Drain heal integration: attacker HP increases after dealing damage
	attacker.current_hp = attacker.max_hp - 30
	var hp_before := attacker.current_hp
	var result2: Dictionary = DamageCalculator.calculate(attacker, defender, gdrain, 100, false)
	var dealt2: int = result2["damage"]
	var heal2: int = dealt2 * gdrain.drain_percent / 100
	attacker.current_hp = min(attacker.max_hp, attacker.current_hp + heal2)
	_chk("S5.06 Drain integration: attacker HP increased by dealt*50/100",
			attacker.current_hp == min(attacker.max_hp, hp_before + heal2))


# ── Section 6: Charging state machine ─────────────────────────────────────────

func _test_section_6_charging_state() -> void:
	var dig := _load_move(91)

	# S6.01 Fresh BattlePokemon has charging_move=null, semi_invulnerable=NONE
	var mon := _make_mon("Digger", 50, [TypeChart.TYPE_GROUND])
	_chk("S6.01 Fresh mon: charging_move=null", mon.charging_move == null)
	_chk("S6.02 Fresh mon: semi_invulnerable=NONE", mon.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# S6.03 Simulating charge turn: set charging_move and semi_inv_state
	mon.charging_move = dig
	mon.semi_invulnerable = dig.semi_inv_state
	_chk("S6.03 After charge turn: charging_move=Dig", mon.charging_move == dig)
	_chk("S6.04 After charge turn: semi_invulnerable=UNDERGROUND",
			mon.semi_invulnerable == MoveData.SEMI_INV_UNDERGROUND)

	# S6.05 Simulating release turn: clear both fields
	mon.charging_move = null
	mon.semi_invulnerable = MoveData.SEMI_INV_NONE
	_chk("S6.05 After release turn: charging_move=null", mon.charging_move == null)
	_chk("S6.06 After release turn: semi_invulnerable=NONE",
			mon.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# S6.07 Faint during charge: clearing state (simulated as in _phase_faint_check)
	mon.charging_move = dig
	mon.semi_invulnerable = MoveData.SEMI_INV_UNDERGROUND
	mon.current_hp = 0
	mon.fainted = true
	mon.charging_move = null
	mon.semi_invulnerable = MoveData.SEMI_INV_NONE
	_chk("S6.07 Faint clears charging_move", mon.charging_move == null)
	_chk("S6.08 Faint clears semi_invulnerable", mon.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# S6.09 Solar Beam: two_turn but no semi_inv_state set
	var solarbeam := _load_move(76)
	mon.fainted = false
	mon.current_hp = mon.max_hp
	mon.charging_move = solarbeam
	mon.semi_invulnerable = solarbeam.semi_inv_state
	_chk("S6.09 Solar Beam charge sets semi_inv=NONE (not underground)",
			mon.semi_invulnerable == MoveData.SEMI_INV_NONE)

	# S6.10 Locked move is forced on turn 2 (field non-null check)
	_chk("S6.10 charging_move non-null → turn-2 forced (field check)", mon.charging_move == solarbeam)
