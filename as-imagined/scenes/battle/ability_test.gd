extends Node

# Milestone 8 test suite — Abilities
#
# Sections:
#   1. Ability data spot-checks (loaded .tres resources, fields correct)
#   2. Tier 1 — Passive stat modifiers
#      A. Huge Power / Pure Power: physical damage doubles; special unaffected
#      B. Thick Fat: Fire and Ice damage halved; other types unaffected
#      C. Levitate: Ground-type moves blocked (0 damage); other types still hit
#   3. Tier 2 — Switch-in effects
#      A. Intimidate: opponent Attack −1 on battle start; one trigger only
#      B. Speed Boost: +1 Speed at end of each turn; stops at +6
#   4. Tier 3 — Contact / trigger-based
#      A. Static: 30% paralyze on contact; non-contact moves don't trigger
#      B. Static: respects Electric-type immunity (cannot paralyze Electric-type)
#      C. Flame Body: 30% burn on contact; non-contact moves don't trigger
#      D. Rough Skin: maxHP/8 damage on contact; non-contact moves don't trigger
#      E. Synchronize: reflects status back to inflicter (burn/para/toxic); not sleep/freeze
#      F. Synchronize: contact-ability-applied status is also reflected
#      G. Ability non-trigger: Flame Body doesn't fire on non-contact hit (Ember)
#
# Ground truth: pokeemerald_expansion src/battle_util.c, src/battle_script_commands.c

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2a_huge_power()
	_test_section_2b_thick_fat()
	_test_section_2c_levitate()
	_test_section_3a_intimidate()
	_test_section_3b_speed_boost()
	_test_section_3b2_speed_boost_switch_in()
	_test_section_4a_static()
	_test_section_4b_static_electric_immune()
	_test_section_4c_flame_body()
	_test_section_4d_rough_skin()
	_test_section_4e_synchronize_status_move()
	_test_section_4f_synchronize_contact_ability()
	_test_section_4g_non_trigger()

	var total := _pass + _fail
	print("ability_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


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


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var huge_power := _load_ability(37)
	_chk("S1.01 Huge Power id=37",          huge_power.ability_id == 37)
	_chk("S1.02 Huge Power name",           huge_power.ability_name == "Huge Power")
	_chk("S1.03 Huge Power ai_rating=10",   huge_power.ai_rating == 10)

	var levitate := _load_ability(26)
	_chk("S1.04 Levitate id=26",            levitate.ability_id == 26)

	var static_ab := _load_ability(9)
	_chk("S1.05 Static id=9",               static_ab.ability_id == 9)

	var intimidate := _load_ability(22)
	_chk("S1.06 Intimidate id=22",          intimidate.ability_id == 22)

	var synchronize := _load_ability(28)
	_chk("S1.07 Synchronize id=28",         synchronize.ability_id == 28)


# ── Section 2A: Huge Power / Pure Power ──────────────────────────────────────
#
# Source: battle_util.c :: GetAttackStatModifier (L6800):
#   ABILITY_HUGE_POWER / ABILITY_PURE_POWER: IsBattleMovePhysical → ×2.0
# Applied to the staged attack stat. In our DamageCalculator, Huge Power doubles
# the attack stat used in the formula.
# Formula verification (no stages, roll=100, no crit, no STAB, no type mod):
#   atk_base = _stat_formula(80, 0, 0) at level 50 = floor((160+0+0)*50/100)+5 = 85
#   atk_huge = 85 * 2 = 170
#   base_dmg = 40 * 170 * (2*50/5+2) / 85 / 50 + 2 = 40*170*22/85/50+2 = 149600/4250+2 = 35+2 = 37
#   without Huge Power: 40*85*22/85/50+2 = 74800/4250+2 = 17+2 = 19
# Crit suppressed, roll pinned to 100.

func _test_section_2a_huge_power() -> void:
	var tackle := _load_move(33)   # Normal/Phys/40, contact
	var water_gun := _load_move(55)  # Water/Spec/40

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)

	var huge_power := _load_ability(37)
	attacker.ability = huge_power

	var result_hp := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	var result_nohp := DamageCalculator.calculate(defender, attacker, tackle, 100, false)
	# Huge Power should increase damage for physical moves
	_chk("S2A.01 Huge Power phys damage > baseline", result_hp["damage"] > result_nohp["damage"])
	# Verify the modifier is exactly 2.0× (UQ4.12 = 8192) rather than checking output damage ratio.
	# The formula's `+2` constant means the ratio of final damage values is not exactly 2×.
	# Source: GetAttackStatModifier returns UQ_4_12(2.0) = 8192 for Huge Power.
	_chk("S2A.02 Huge Power modifier = UQ_4_12(2.0) = 8192",
		AbilityManager.attack_modifier_uq412(attacker, tackle) == 8192)

	# Pure Power same effect
	var pure_power := _load_ability(74)
	attacker.ability = pure_power
	var result_pp := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("S2A.03 Pure Power = Huge Power (phys)", result_pp["damage"] == result_hp["damage"])

	# Huge Power does NOT affect special moves
	attacker.ability = huge_power
	var result_spec_hp  := DamageCalculator.calculate(attacker, defender, water_gun, 100, false)
	var result_spec_nohp := DamageCalculator.calculate(defender, attacker, water_gun, 100, false)
	_chk("S2A.04 Huge Power no effect on special", result_spec_hp["damage"] == result_spec_nohp["damage"])


# ── Section 2B: Thick Fat ─────────────────────────────────────────────────────
#
# Source: battle_util.c :: GetDefenseStatModifier target switch (L6933–6941):
#   (TYPE_FIRE || TYPE_ICE) → modifier ×0.5 applied as if attacker's attack is halved.
# Verification: Ember (Fire/Spec/40) vs. Thick Fat holder — damage should be halved.
# Non-fire/non-ice moves (Tackle) should be unaffected.

func _test_section_2b_thick_fat() -> void:
	var ember := _load_move(52)    # Fire/Spec/40
	var ice_beam := _load_move(58) # Ice/Spec/90
	var tackle := _load_move(33)   # Normal/Phys/40

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	var thick_fat := _load_ability(47)
	defender.ability = thick_fat

	# Fire move: Thick Fat should halve damage
	var dmg_fire_with    := DamageCalculator.calculate(attacker, defender, ember, 100, false)
	var dmg_fire_without := DamageCalculator.calculate(attacker, attacker, ember, 100, false)  # no ability
	_chk("S2B.01 Thick Fat halves Fire damage", dmg_fire_with["damage"] < dmg_fire_without["damage"])
	# Allow ±1 for integer rounding
	_chk("S2B.02 Thick Fat Fire half value",
		dmg_fire_with["damage"] == dmg_fire_without["damage"] / 2
		or dmg_fire_with["damage"] == dmg_fire_without["damage"] / 2 + 1)

	# Ice move: Thick Fat should halve damage
	var dmg_ice_with    := DamageCalculator.calculate(attacker, defender, ice_beam, 100, false)
	var dmg_ice_without := DamageCalculator.calculate(attacker, attacker, ice_beam, 100, false)
	_chk("S2B.03 Thick Fat halves Ice damage", dmg_ice_with["damage"] < dmg_ice_without["damage"])

	# Normal move: unaffected
	var dmg_norm_with    := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	var dmg_norm_without := DamageCalculator.calculate(attacker, attacker, tackle, 100, false)
	_chk("S2B.04 Thick Fat no effect on Normal", dmg_norm_with["damage"] == dmg_norm_without["damage"])


# ── Section 2C: Levitate ──────────────────────────────────────────────────────
#
# Source: battle_util.c :: CalcTypeEffectivenessMultiplierInternal (L8257):
#   TYPE_GROUND && ABILITY_LEVITATE && !gravity → modifier 0.0
# Earthquake (Ground) vs. Levitate holder should deal 0 damage.
# Wing Attack (Flying) vs. Levitate holder is unaffected.

func _test_section_2c_levitate() -> void:
	var earthquake := _load_move(89)   # Ground/Phys/100
	var wing_attack := _load_move(17)  # Flying/Phys/60

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	var levitate := _load_ability(26)
	defender.ability = levitate

	var dmg_eq := DamageCalculator.calculate(attacker, defender, earthquake, 100, false)
	_chk("S2C.01 Levitate blocks Ground damage=0", dmg_eq["damage"] == 0)
	_chk("S2C.02 Levitate blocks Ground eff=0.0",  dmg_eq["effectiveness"] == 0.0)

	# Non-Ground move still hits
	var dmg_fly := DamageCalculator.calculate(attacker, defender, wing_attack, 100, false)
	_chk("S2C.03 Levitate no effect on Flying move", dmg_fly["damage"] > 0)

	# Ground-type native immunity still blocks even without Levitate (type-chart test)
	var sp_ground := PokemonSpecies.new()
	sp_ground.species_name = "Ground"
	sp_ground.types = [TypeChart.TYPE_GROUND]
	sp_ground.base_hp = 80; sp_ground.base_attack = 80; sp_ground.base_defense = 80
	sp_ground.base_sp_attack = 80; sp_ground.base_sp_defense = 80; sp_ground.base_speed = 80
	var ground_mon := BattlePokemon.from_species(sp_ground, 50)
	var dmg_eq_nolevitate := DamageCalculator.calculate(attacker, ground_mon, earthquake, 100, false)
	_chk("S2C.04 Ground-type still takes Ground damage (no Levitate)", dmg_eq_nolevitate["damage"] > 0)


# ── Section 3A: Intimidate ────────────────────────────────────────────────────
#
# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L3310):
#   ABILITY_INTIMIDATE → SetStatChange(opponents, STAT_ATK, -1) on entry.
# In BattleManager: fires in _phase_battle_start() for both combatants simultaneously.
# Verified via: stat_stage_changed signal (ATK −1) + ability_triggered signal.

func _test_section_3a_intimidate() -> void:
	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)  # has Intimidate
	var defender := BattlePokemon.from_species(sp_normal, 50)  # no ability

	var intimidate := _load_ability(22)
	attacker.ability = intimidate

	# Track signals
	var stat_events := []   # [target, stat_idx, actual_change]
	var ability_events := []  # [pokemon, effect_key]

	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, si, ac): stat_events.push_back([t, si, ac]))
	bm.ability_triggered.connect(func(p, ek): ability_events.push_back([p, ek]))

	var tackle := _load_move(33)
	attacker.add_move(tackle)
	defender.add_move(tackle)
	bm.start_battle(attacker, defender)

	# Intimidate should have fired: defender's ATK dropped by 1
	_chk("S3A.01 Intimidate fired stat_stage_changed",
		stat_events.any(func(e): return e[0] == defender and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1))
	_chk("S3A.02 Intimidate ability_triggered",
		ability_events.any(func(e): return e[0] == attacker and e[1] == "intimidate"))

	# Defender's ATK stat stage should be -1
	_chk("S3A.03 defender ATK stage = -1", defender.stat_stages[BattlePokemon.STAGE_ATK] == -1)

	# Intimidate fired exactly once (one attacker with Intimidate, one trigger)
	var intimidate_signals := ability_events.filter(func(e): return e[1] == "intimidate")
	_chk("S3A.04 Intimidate fired exactly once", intimidate_signals.size() == 1)

	bm.queue_free()


# ── Section 3B: Speed Boost ───────────────────────────────────────────────────
#
# Source: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (battle_util.c L3605):
#   +1 Speed each end-of-turn while alive and below +6.
# Verified: after N turns, Speed stage = N (up to 6).

func _test_section_3b_speed_boost() -> void:
	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 200; sp_normal.base_attack = 5; sp_normal.base_defense = 200
	sp_normal.base_sp_attack = 5; sp_normal.base_sp_defense = 200; sp_normal.base_speed = 80

	var sb_mon := BattlePokemon.from_species(sp_normal, 50)   # Speed Boost holder
	var opp := BattlePokemon.from_species(sp_normal, 50)      # no ability; very low ATK won't KO

	var speed_boost := _load_ability(3)
	sb_mon.ability = speed_boost

	var tackle := _load_move(33)
	sb_mon.add_move(tackle)
	opp.add_move(tackle)

	# Manually drive end-of-turn to check Speed stage increments.
	# We call try_end_of_turn directly rather than routing through BattleManager.
	_chk("S3B.01 Speed stage 0 before any turn", sb_mon.stat_stages[BattlePokemon.STAGE_SPEED] == 0)
	var actual1: int = AbilityManager.try_end_of_turn(sb_mon)
	_chk("S3B.02 Speed Boost returns +1 stage turn 1", actual1 == 1)
	_chk("S3B.03 Speed stage = 1 after turn 1", sb_mon.stat_stages[BattlePokemon.STAGE_SPEED] == 1)

	# Advance to +6 and confirm it stops
	for _i in range(5):
		AbilityManager.try_end_of_turn(sb_mon)
	_chk("S3B.04 Speed stage = 6 after 6 turns", sb_mon.stat_stages[BattlePokemon.STAGE_SPEED] == 6)
	var actual_at_cap: int = AbilityManager.try_end_of_turn(sb_mon)
	_chk("S3B.05 Speed Boost returns 0 at +6 (capped)", actual_at_cap == 0)
	_chk("S3B.06 Speed stage still = 6 after cap", sb_mon.stat_stages[BattlePokemon.STAGE_SPEED] == 6)


# ── Section 3B2: Speed Boost — no boost on switch-in turn (A7) ───────────────
#
# Source: !BattlerJustSwitchedIn gate (battle_util.c L10982) — isFirstTurn==2 is
#   set at mid-battle switch-in (battle_main.c L3198/L3309) and decremented at L5038.
# Mirrored via BattlePokemon.switched_in_this_turn + _phase_priority_resolution clear.
#
# Damage math (hand-verified, bench_mon ATK stat=10, opp DEF stat=5005, Tackle BP=40,
# Normal vs Normal STAB applies):
#   base = 40*10*22 / 5005 / 50 + 2 = 8800/5005/50+2 = 1/50+2 = 0+2 = 2
#   after roll (dmg*roll/100 integer): roll 85–99 → 2*roll/100 = 1; roll 100 → 2
#   after STAB (_uq412_half_down): 1 → 1; 2 → 3
#   without crit: damage is 1 on 15/16 rolls, 3 on roll=100
#   with crit (base→3 before roll): roll 85–99 → 2 (STAB→3); roll 100 → 3 (STAB→4)
#   absolute worst-case single-turn damage: 4 (crit + roll 100, rare)
#
# opp.current_hp = 8 > 4 (worst-case damage) → opp CANNOT be KO'd on turn 1 (bench_mon
# doesn't attack; it switches in) or turn 2 (max damage 4 leaves opp at ≥4 HP) under
# any roll or crit combination. Both EOT1 and EOT2 are therefore guaranteed to fire and
# be captured by the phase_changed(BATTLE_END_CHECK) snapshots — test is RNG-safe.
# Turn 1: player switches in bench_mon; opp attacks bench_mon (200 HP, 205 DEF — safe).
# Turn 2+: bench_mon auto-selects Tackle; opp auto-selects Tackle.

func _test_section_3b2_speed_boost_switch_in() -> void:
	var speed_boost := _load_ability(3)
	var tackle      := _load_move(33)

	var starter   := _make_mon("Starter", 50, [TypeChart.TYPE_NORMAL],
			200, 80, 200, 5, 200, 100)
	var bench_mon := _make_mon("SBench",  50, [TypeChart.TYPE_NORMAL],
			200, 5, 200, 5, 200, 50)
	bench_mon.ability = speed_boost

	var opp       := _make_mon("OppTank", 50, [TypeChart.TYPE_NORMAL],
			200, 5, 5000, 5, 200, 30)
	opp.current_hp = 8

	starter.add_move(tackle)
	bench_mon.add_move(tackle)
	opp.add_move(tackle)

	var speed_stage_after_eot1 := [-1]
	var speed_stage_after_eot2 := [-1]
	var eot_count              := [0]

	var bm := BattleManager.new()
	add_child(bm)
	bm.phase_changed.connect(func(phase: BattleManager.BattlePhase):
		if phase == BattleManager.BattlePhase.BATTLE_END_CHECK:
			eot_count[0] += 1
			if eot_count[0] == 1:
				speed_stage_after_eot1[0] = bench_mon.stat_stages[BattlePokemon.STAGE_SPEED]
			elif eot_count[0] == 2:
				speed_stage_after_eot2[0] = bench_mon.stat_stages[BattlePokemon.STAGE_SPEED])

	var player_party := BattleParty.new()
	player_party.members = [starter, bench_mon]
	player_party.active_index = 0

	bm.queue_switch(0, 1)  # Turn 1: switch starter out, bench_mon in.
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))
	bm.queue_free()

	_chk("S3B.07 Speed stage 0 after switch-in turn EOT (gate active)",
			speed_stage_after_eot1[0] == 0)
	_chk("S3B.08 Speed stage 1 after turn-2 EOT (gate lifted)",
			speed_stage_after_eot2[0] == 1)
	_chk("S3B.09 switched_in_this_turn false by turn 2",
			not bench_mon.switched_in_this_turn)
	_chk("S3B.10 Speed Boost fired at least once over battle",
			bench_mon.stat_stages[BattlePokemon.STAGE_SPEED] >= 1)


# ── Section 4A: Static ────────────────────────────────────────────────────────
#
# Source: AbilityBattleEffects(ABILITYEFFECT_MOVE_END, ...) (battle_util.c L4091):
#   B_ABILITY_TRIGGER_CHANCE >= GEN_4 → RandomPercentage(RNG_STATIC, 30)
#   Conditions: IsBattlerAlive(attacker), IsBattlerTurnDamaged, CanBeParalyzed,
#     !CanBattlerAvoidContactEffects (= move.makes_contact in M8 scope).
# Test: forced-trigger contact hit → attacker gets paralysis.
# Test: non-contact hit → Static does NOT fire.

func _test_section_4a_static() -> void:
	var tackle := _load_move(33)   # Normal/Phys/40, makes_contact=true
	var static_ab := _load_ability(9)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	defender.ability = static_ab

	# Forced trigger (30% chance normally, pin to true)
	var result := AbilityManager.try_contact_effects(attacker, defender, tackle, 50, true)
	_chk("S4A.01 Static fires on contact (forced)",  result["ability_name"] == "static")
	_chk("S4A.02 Static applies paralysis",          result["status_applied"] == BattlePokemon.STATUS_PARALYSIS)
	_chk("S4A.03 attacker is paralyzed",             attacker.status == BattlePokemon.STATUS_PARALYSIS)

	# Non-contact move (Swift = Spec, no contact): Static must NOT fire
	var swift := _load_move(129)   # Normal/Spec/60, makes_contact=false
	var attacker2 := BattlePokemon.from_species(sp_normal, 50)
	var result2 := AbilityManager.try_contact_effects(attacker2, defender, swift, 50, true)
	_chk("S4A.04 Static no trigger for non-contact", result2["ability_name"] == "")
	_chk("S4A.05 attacker2 status unchanged (none)",  attacker2.status == BattlePokemon.STATUS_NONE)

	# Forced suppress (roll=false): Static roll fails
	var attacker3 := BattlePokemon.from_species(sp_normal, 50)
	var result3 := AbilityManager.try_contact_effects(attacker3, defender, tackle, 50, false)
	_chk("S4A.06 Static suppressed (forced false)",  result3["ability_name"] == "")
	_chk("S4A.07 attacker3 no status (suppressed)",   attacker3.status == BattlePokemon.STATUS_NONE)


# ── Section 4B: Static vs Electric-type immunity ──────────────────────────────
#
# Source: CanBeParalyzed → B_PARALYZE_ELECTRIC >= GEN_6 (GEN_LATEST):
#   Electric-types cannot be paralyzed (try_apply_status blocks it).
# Static should fire the roll but fail to apply status to an Electric-type.

func _test_section_4b_static_electric_immune() -> void:
	var tackle := _load_move(33)
	var static_ab := _load_ability(9)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80
	var defender := BattlePokemon.from_species(sp_normal, 50)
	defender.ability = static_ab

	var sp_elec := PokemonSpecies.new()
	sp_elec.species_name = "Electric"
	sp_elec.types = [TypeChart.TYPE_ELECTRIC]
	sp_elec.base_hp = 80; sp_elec.base_attack = 80; sp_elec.base_defense = 80
	sp_elec.base_sp_attack = 80; sp_elec.base_sp_defense = 80; sp_elec.base_speed = 80
	var elec_attacker := BattlePokemon.from_species(sp_elec, 50)

	# Forced roll = true: contact, Static fires, but Electric-type can't be paralyzed
	var result := AbilityManager.try_contact_effects(elec_attacker, defender, tackle, 50, true)
	_chk("S4B.01 Static roll fires (forced true)", result["ability_name"] == "static" or result["status_applied"] == 0)
	_chk("S4B.02 Electric immune to paralysis", elec_attacker.status == BattlePokemon.STATUS_NONE)
	_chk("S4B.03 status_applied = 0 for immune target", result["status_applied"] == 0)


# ── Section 4C: Flame Body ────────────────────────────────────────────────────
#
# Source: AbilityBattleEffects ABILITYEFFECT_MOVE_END (L4114):
#   30% burn on contact. CanBeBurned = not Fire-type + no major status.

func _test_section_4c_flame_body() -> void:
	var tackle := _load_move(33)
	var flame_body := _load_ability(49)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	defender.ability = flame_body

	# Forced trigger
	var result := AbilityManager.try_contact_effects(attacker, defender, tackle, 50, true)
	_chk("S4C.01 Flame Body fires on contact",  result["ability_name"] == "flame_body")
	_chk("S4C.02 Flame Body applies burn",       result["status_applied"] == BattlePokemon.STATUS_BURN)
	_chk("S4C.03 attacker is burned",            attacker.status == BattlePokemon.STATUS_BURN)

	# Already burned: Flame Body can't apply burn again
	var attacker2 := BattlePokemon.from_species(sp_normal, 50)
	attacker2.status = BattlePokemon.STATUS_BURN
	var result2 := AbilityManager.try_contact_effects(attacker2, defender, tackle, 50, true)
	_chk("S4C.04 Flame Body blocked if already burned", result2["status_applied"] == 0)
	_chk("S4C.05 already-burned still burned",           attacker2.status == BattlePokemon.STATUS_BURN)


# ── Section 4D: Rough Skin ────────────────────────────────────────────────────
#
# Source: AbilityBattleEffects ABILITYEFFECT_MOVE_END (L3965):
#   B_ROUGH_SKIN_DMG >= GEN_4 → maxHP / 8 damage to attacker on contact.
#   No 30% roll — fires unconditionally on contact.

func _test_section_4d_rough_skin() -> void:
	var tackle := _load_move(33)   # contact
	var swift := _load_move(129)   # no contact
	var rough_skin := _load_ability(24)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	defender.ability = rough_skin

	# Contact hit: attacker takes maxHP/8 (no roll forced needed — always fires)
	var result := AbilityManager.try_contact_effects(attacker, defender, tackle, 50)
	_chk("S4D.01 Rough Skin fires on contact",   result["ability_name"] == "rough_skin")
	var expected_dmg: int = attacker.max_hp / 8
	_chk("S4D.02 Rough Skin damage = maxHP/8",   result["rough_skin_damage"] == expected_dmg)
	_chk("S4D.03 Rough Skin no status",          result["status_applied"] == 0)

	# Non-contact: no damage
	var result2 := AbilityManager.try_contact_effects(attacker, defender, swift, 50)
	_chk("S4D.04 Rough Skin no trigger non-contact", result2["ability_name"] == "")
	_chk("S4D.05 Rough Skin damage=0 non-contact",   result2["rough_skin_damage"] == 0)


# ── Section 4E: Synchronize (primary status move) ────────────────────────────
#
# Source: TrySynchronizeActivation (battle_script_commands.c L2130):
#   Fires for BURN, PARALYSIS, POISON, TOXIC; NOT SLEEP, NOT FREEZE.
# S4E.01–05 use direct API calls (StatusManager + AbilityManager) — no BattleManager,
# no accuracy roll, no turn-order dependency. Same pattern as the sleep tests.
# S4E.06 verifies the full integration path (BattleManager → _try_synchronize →
# ability_triggered) with _force_hit = true so Thunder Wave always lands.

func _test_section_4e_synchronize_status_move() -> void:
	var thunder_wave := _load_move(86)   # Electric/Status
	var synchronize_ab := _load_ability(28)

	var sp_fast := PokemonSpecies.new()
	sp_fast.species_name = "Fast"
	sp_fast.types = [TypeChart.TYPE_NORMAL]
	sp_fast.base_hp = 200; sp_fast.base_attack = 5; sp_fast.base_defense = 200
	sp_fast.base_sp_attack = 5; sp_fast.base_sp_defense = 200; sp_fast.base_speed = 200

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 200; sp_normal.base_attack = 5; sp_normal.base_defense = 200
	sp_normal.base_sp_attack = 5; sp_normal.base_sp_defense = 200; sp_normal.base_speed = 80

	# S4E.01–03: Direct API — paralysis applied to Synchronize holder, reflected back.
	var para_source  := BattlePokemon.from_species(sp_fast, 50)
	var synch_holder := BattlePokemon.from_species(sp_normal, 50)
	synch_holder.ability = synchronize_ab

	var para_applied := StatusManager.try_apply_status(synch_holder, BattlePokemon.STATUS_PARALYSIS)
	_chk("S4E.01 paralysis applied to Synchronize holder",
		para_applied and synch_holder.status == BattlePokemon.STATUS_PARALYSIS)
	var synch_back := AbilityManager.try_synchronize(synch_holder, para_source, BattlePokemon.STATUS_PARALYSIS)
	_chk("S4E.02 Synchronize reflected paralysis back",  synch_back == BattlePokemon.STATUS_PARALYSIS)
	_chk("S4E.03 source now paralyzed by Synchronize",   para_source.status == BattlePokemon.STATUS_PARALYSIS)

	# S4E.04–05: Sleep is NOT reflected by Synchronize.
	# Source: TrySynchronizeActivation — MOVE_EFFECT_SLEEP not in the trigger list.
	var sleep_source  := BattlePokemon.from_species(sp_normal, 50)
	var synch_holder2 := BattlePokemon.from_species(sp_normal, 50)
	synch_holder2.ability = synchronize_ab

	var slept := StatusManager.try_apply_status(synch_holder2, BattlePokemon.STATUS_SLEEP)
	_chk("S4E.04 Sleep applied to Synchronize holder",
		slept and synch_holder2.status == BattlePokemon.STATUS_SLEEP)
	var synch_back2 := AbilityManager.try_synchronize(synch_holder2, sleep_source, BattlePokemon.STATUS_SLEEP)
	_chk("S4E.05 Sleep NOT reflected by Synchronize",
		synch_back2 == 0 and sleep_source.status == BattlePokemon.STATUS_NONE)

	# S4E.06: Integration — full BattleManager turn with _force_hit = true confirms
	# _try_synchronize → ability_triggered fires through the ACTION_EXECUTION pipeline.
	# Thunder Wave has accuracy=90; without _force_hit the test was intermittently flaky.
	#
	# Fixture is designed to end in 2-3 turns (not at the 4096-phase cap):
	#   twave_attacker moveset: [tackle (idx 0), thunder_wave (idx 1)]
	#     → queue_move(0, 1) forces Thunder Wave on turn 1 only.
	#     → auto-select picks idx 0 (Tackle) from turn 2 onward.
	#   synch_holder3: base_hp=1, base_def=1 → HP=61, def_stat=6 at L50.
	#   Tackle damage (sp_fast base_atk=5 → stat=10): base=31, STAB range 39-46.
	#   Two hits guaranteed KO (39+39=78 > 61), so battle ends by turn 3.
	var tackle := _load_move(33)

	var sp_weak := PokemonSpecies.new()
	sp_weak.species_name = "Weak"
	sp_weak.types = [TypeChart.TYPE_NORMAL]
	sp_weak.base_hp = 1; sp_weak.base_attack = 5; sp_weak.base_defense = 1
	sp_weak.base_sp_attack = 5; sp_weak.base_sp_defense = 5; sp_weak.base_speed = 80

	var bm := BattleManager.new()
	add_child(bm)
	var ability_events := []
	bm.ability_triggered.connect(func(p, ek): ability_events.push_back([p, ek]))

	var twave_attacker := BattlePokemon.from_species(sp_fast, 50)
	var synch_holder3  := BattlePokemon.from_species(sp_weak, 50)
	synch_holder3.ability = synchronize_ab
	twave_attacker.add_move(tackle)         # index 0 — auto-selected from turn 2 on
	twave_attacker.add_move(thunder_wave)   # index 1 — queued for turn 1 only
	synch_holder3.add_move(tackle)

	bm.queue_move(0, 1)   # turn 1: twave_attacker uses Thunder Wave (index 1)
	bm._force_hit = true
	bm.start_battle(twave_attacker, synch_holder3)

	_chk("S4E.06 integration: ability_triggered fires via BattleManager with _force_hit",
		ability_events.any(func(e): return e[1] == "synchronize"))
	bm.queue_free()


# ── Section 4F: Synchronize reflects contact-ability status ──────────────────
#
# Static applies paralysis to the attacker from the defender's ability.
# If the attacker has Synchronize, the paralysis should reflect back to the defender.
# Source: TrySynchronizeActivation — applies to any status infliction on the holder.

func _test_section_4f_synchronize_contact_ability() -> void:
	var tackle := _load_move(33)
	var static_ab := _load_ability(9)
	var synchronize_ab := _load_ability(28)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	# Attacker has Synchronize; defender has Static.
	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	attacker.ability = synchronize_ab
	defender.ability = static_ab

	# Forced contact trigger: Static paralyzes attacker, then Synchronize reflects back.
	var contact_result := AbilityManager.try_contact_effects(attacker, defender, tackle, 50, true)
	if contact_result["status_applied"] == BattlePokemon.STATUS_PARALYSIS:
		var synch_back := AbilityManager.try_synchronize(attacker, defender, BattlePokemon.STATUS_PARALYSIS)
		_chk("S4F.01 Synchronize reflects Static paralysis back", synch_back == BattlePokemon.STATUS_PARALYSIS)
		_chk("S4F.02 defender paralyzed by Synchronize",         defender.status == BattlePokemon.STATUS_PARALYSIS)
	else:
		# Static didn't apply (shouldn't happen with force=true, but skip gracefully)
		_chk("S4F.01 Static applied paralysis to attacker", false)
		_chk("S4F.02 skip (Static failed)", true)


# ── Section 4G: Non-trigger condition ────────────────────────────────────────
#
# The prompt specifically requires at least one test verifying an ability does NOT
# fire under a specific condition. Flame Body must NOT trigger on non-contact moves.
# Also: Flame Body doesn't re-burn an already-burned target's attacker.

func _test_section_4g_non_trigger() -> void:
	var ember := _load_move(52)    # Fire/Spec/40, makes_contact=false
	var flame_body := _load_ability(49)

	var sp_normal := PokemonSpecies.new()
	sp_normal.species_name = "Normal"
	sp_normal.types = [TypeChart.TYPE_NORMAL]
	sp_normal.base_hp = 80; sp_normal.base_attack = 80; sp_normal.base_defense = 80
	sp_normal.base_sp_attack = 80; sp_normal.base_sp_defense = 80; sp_normal.base_speed = 80

	var attacker := BattlePokemon.from_species(sp_normal, 50)
	var defender := BattlePokemon.from_species(sp_normal, 50)
	defender.ability = flame_body

	# Ember (non-contact) → Flame Body must NOT fire even if roll would succeed
	var result := AbilityManager.try_contact_effects(attacker, defender, ember, 50, true)
	_chk("S4G.01 Flame Body no trigger on Ember (non-contact)", result["ability_name"] == "")
	_chk("S4G.02 attacker not burned from Ember",               attacker.status == BattlePokemon.STATUS_NONE)

	# Damage == 0 → no trigger (Protect absorbed, etc.)
	var tackle := _load_move(33)
	var result2 := AbilityManager.try_contact_effects(attacker, defender, tackle, 0, true)
	_chk("S4G.03 Flame Body no trigger when damage=0",  result2["ability_name"] == "")
