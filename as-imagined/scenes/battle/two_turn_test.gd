extends Node

# M15 Task 5 test suite — Two-turn moves
#
# Source: battle_move_resolution.c :: CancelerCharging (L1737–1798)
#   — Charge turn: set multipleTurns=TRUE, semiInvulnerable, chargeTurn flag; return.
#   — Release turn: clear multipleTurns, clear semiInvulnerable; fall through to attack.
# Source: CanTwoTurnMoveFireThisTurn (L1664–1674)
#   — Returns FALSE for semiInvulnerableEffect moves (Fly/Dig/Bounce/Dive NEVER skip).
#   — Returns TRUE for Solar Beam when (weather & B_WEATHER_SUN) is set.
# Source: moves_info.h MOVE_SKULL_BASH :: additionalEffects
#   {MOVE_EFFECT_STAT_PLUS, .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE}
#
# Sections:
#   T1: Data spot-checks (is_solar_beam, charge_turn_defense_boost on .tres)
#   T2: Semi-inv move dodges single-target attack on the charge turn (Fly)
#   T3: Two-turn attack fires on turn 2 with damage (Dig)
#   T4: Solar Beam fires immediately in sun (no charge turn)
#   T5: Solar Beam takes two turns in rain (charge turn required)
#   T6: Skull Bash applies +1 Defense on charge turn only

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_t1_data_checks()
	_test_t2_semi_inv_dodge()
	_test_t3_release_fires_turn2()
	_test_t4_solar_beam_sun_instant()
	_test_t5_solar_beam_rain_two_turns()
	_test_t6_skull_bash_def_boost()

	var total := _pass + _fail
	print("two_turn_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, type1: int, speed: int = 80,
		base_hp: int = 200, base_atk: int = 80, base_def: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = 80
	sp.base_sp_defense = 80
	sp.base_speed      = speed
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _make_tackle(power: int = 40) -> MoveData:
	var m := MoveData.new()
	m.move_name = "Tackle"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 0
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	return m


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── T1: Data spot-checks ──────────────────────────────────────────────────────
# Verify .tres fields that M15 Task 5 depends on.

func _test_t1_data_checks() -> void:
	# Solar Beam (76): two_turn=true, is_solar_beam=true, semi_inv=NONE
	var solar := _load_move(76)
	_chk("T1.01 Solar Beam loads", solar != null)
	if solar != null:
		_chk("T1.02 Solar Beam two_turn=true",     solar.two_turn == true)
		_chk("T1.03 Solar Beam is_solar_beam=true", solar.is_solar_beam == true)
		_chk("T1.04 Solar Beam semi_inv=NONE",      solar.semi_inv_state == MoveData.SEMI_INV_NONE)

	# Skull Bash (130): two_turn=true, charge_turn_defense_boost=1
	var skull := _load_move(130)
	_chk("T1.05 Skull Bash loads", skull != null)
	if skull != null:
		_chk("T1.06 Skull Bash two_turn=true",              skull.two_turn == true)
		_chk("T1.07 Skull Bash charge_turn_defense_boost=1", skull.charge_turn_defense_boost == 1)
		_chk("T1.08 Skull Bash power=130",                   skull.power == 130)

	# Fly (19): two_turn=true, semi_inv=ON_AIR, is_solar_beam=false
	var fly := _load_move(19)
	if fly != null:
		_chk("T1.09 Fly semi_inv=ON_AIR",       fly.semi_inv_state == MoveData.SEMI_INV_ON_AIR)
		_chk("T1.10 Fly is_solar_beam=false",    fly.is_solar_beam == false)
		_chk("T1.11 Fly no def boost on charge", fly.charge_turn_defense_boost == 0)

	# Sky Attack (143): crit_stage=1 (gen-constant fix verified)
	var sky := _load_move(143)
	if sky != null:
		_chk("T1.12 Sky Attack crit_stage=1", sky.critical_hit_stage == 1)


# ── T2: Semi-inv dodge on charge turn ────────────────────────────────────────
# Fly user is ON_AIR after charge turn; opponent's Tackle should miss.
# Source: check_accuracy (StatusManager) → returns FALSE when defender is semi-inv
#   and move does not bypass (damages_airborne=false for Tackle).
# P1 (fast) uses Fly on turn 1 → becomes ON_AIR.
# P2 (slow) uses Tackle on turn 1 → Tackle fires AFTER Fly charge (speed order),
#   hits the now-ON_AIR P1 → misses → move_missed("accuracy") emitted.

func _test_t2_semi_inv_dodge() -> void:
	var fly := _load_move(19)
	_chk("T2.00 Fly loads for dodge test", fly != null)
	if fly == null:
		return

	# P1 faster so Fly charges first; then P2's Tackle hits the ON_AIR P1.
	var p1 := _make_mon("Flyer", TypeChart.TYPE_FLYING, 100)
	var p2 := _make_mon("Attacker", TypeChart.TYPE_NORMAL, 50)
	var tackle := _make_tackle(40)
	p1.add_move(fly)
	p2.add_move(tackle)
	# Queue 2 turns for each side:
	#   P1 turn 1: use Fly (index 0); turn 2 auto-locks into charging_move
	#   P2 turn 1+2: Tackle both turns
	var bm := _make_bm()
	var charge_fired := [false]
	var miss_on_turn1 := [false]
	var executed_damages: Array = []
	var turn_count := [0]

	bm.charge_started.connect(func(_a, _m): charge_fired[0] = true)
	bm.move_missed.connect(func(_a, _r): miss_on_turn1[0] = true)
	bm.move_executed.connect(func(_a, _d, _m, dmg): executed_damages.append(dmg))

	# Pre-queue: P1 one Fly action (turn 2 is auto-locked); P2 two Tackles
	bm.queue_move(0, 0)  # P1 turn 1: Fly (index 0)
	bm.queue_move(1, 0)  # P2 turn 1: Tackle
	bm.queue_move(1, 0)  # P2 turn 2: Tackle (released P1 still alive, high HP)
	bm.start_battle(p1, p2)

	_chk("T2.01 charge_started fired on turn 1", charge_fired[0])
	_chk("T2.02 Tackle missed ON_AIR P1 (move_missed emitted)", miss_on_turn1[0])
	# Fly's charge emits move_executed(0 damage); Fly's release emits move_executed(>0 damage).
	var damage_events: Array = executed_damages.filter(func(d): return d > 0)
	_chk("T2.03 Fly release dealt damage on turn 2 (move_executed with dmg>0)",
			damage_events.size() >= 1)
	bm.queue_free()


# ── T3: Two-turn release fires on turn 2 ─────────────────────────────────────
# Dig charges on turn 1 (move_executed 0 damage), fires on turn 2 (move_executed >0 damage).
# Source: CancelerCharging release branch — clears multipleTurns/semiInvulnerable,
#   falls through to the rest of _phase_move_execution.

func _test_t3_release_fires_turn2() -> void:
	var dig := _load_move(91)
	_chk("T3.00 Dig loads for release test", dig != null)
	if dig == null:
		return

	var p1 := _make_mon("Digger", TypeChart.TYPE_GROUND, 100)
	var p2 := _make_mon("Target", TypeChart.TYPE_NORMAL, 50)
	var tackle := _make_tackle(20)
	p1.add_move(dig)
	p2.add_move(tackle)

	var bm := _make_bm()
	var charge_fired := [false]
	var damage_events: Array = []

	bm.charge_started.connect(func(_a, _m): charge_fired[0] = true)
	bm.move_executed.connect(func(_a, _d, _m, dmg): damage_events.append(dmg))

	bm.queue_move(0, 0)  # P1 turn 1: Dig
	bm.queue_move(1, 0)  # P2 turn 1: Tackle
	bm.queue_move(1, 0)  # P2 turn 2: Tackle
	bm.start_battle(p1, p2)

	_chk("T3.01 charge_started fired (Dig turn 1)", charge_fired[0])
	# move_executed fires for both sides each turn; filter for P1's Dig events by damage.
	var dig_with_damage: Array = damage_events.filter(func(d): return d > 0)
	_chk("T3.02 Dig release dealt damage on turn 2",  dig_with_damage.size() >= 1)
	# Verify that the first charge event gave 0 damage (charge turn has 0 damage).
	_chk("T3.03 Dig charge turn emitted 0 damage first", damage_events.size() >= 1 and damage_events[0] == 0)
	bm.queue_free()


# ── T4: Solar Beam fires immediately in sun ───────────────────────────────────
# Source: CanTwoTurnMoveFireThisTurn → TRUE when weather==WEATHER_SUN.
# The _solar_skip flag in BattleManager causes the two-turn block to be bypassed,
# so Solar Beam fires in a single turn (no charge_started emitted).

func _test_t4_solar_beam_sun_instant() -> void:
	var solar := _load_move(76)
	_chk("T4.00 Solar Beam loads", solar != null)
	if solar == null:
		return

	var p1 := _make_mon("Sunny", TypeChart.TYPE_GRASS, 100)
	var p2 := _make_mon("Target", TypeChart.TYPE_NORMAL, 50, 400)  # very high HP
	var tackle := _make_tackle(10)
	p1.add_move(solar)
	p2.add_move(tackle)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_SUN
	# weather_duration intentionally left at 0 so sun lasts the whole battle
	# (duration=0 → EOT guard `if weather_duration > 0` never ticks → never expires).
	bm._force_roll = 100
	bm._force_crit = false
	# Solar Beam at roll=100, no crit, GRASS vs NORMAL:
	#   base=120×85×22/85/50+2=54; roll: 54; STAB: (54×6144+2047)/4096=81; eff 1.0 → 81
	p2.current_hp = 81  # p2 faints on turn 1 so the battle ends before any extra cycles

	var charge_count := [0]
	var damage_events: Array = []

	bm.charge_started.connect(func(_a, _m): charge_count[0] += 1)
	bm.move_executed.connect(func(_a, _d, _m, dmg): damage_events.append(dmg))

	bm.queue_move(0, 0)  # P1 turn 1: Solar Beam (should fire immediately)
	bm.queue_move(1, 0)  # P2 turn 1: Tackle
	bm.start_battle(p1, p2)

	_chk("T4.01 charge_started NOT fired in sun (Solar Beam fires immediately)",
			charge_count[0] == 0)
	var sunny_damage: Array = damage_events.filter(func(d): return d > 0)
	_chk("T4.02 Solar Beam dealt damage on turn 1 in sun", sunny_damage.size() >= 1)
	bm.queue_free()


# ── T5: Solar Beam takes two turns in rain ────────────────────────────────────
# Source: CanTwoTurnMoveFireThisTurn → FALSE when weather != WEATHER_SUN.
# In rain, Solar Beam must charge on turn 1 (charge_started fires, 0 damage)
# and fire on turn 2 (damage > 0).

func _test_t5_solar_beam_rain_two_turns() -> void:
	var solar := _load_move(76)
	_chk("T5.00 Solar Beam loads", solar != null)
	if solar == null:
		return

	var p1 := _make_mon("Rainy", TypeChart.TYPE_GRASS, 100)
	var p2 := _make_mon("Target", TypeChart.TYPE_NORMAL, 50, 400)
	var tackle := _make_tackle(10)
	p1.add_move(solar)
	p2.add_move(tackle)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_RAIN
	# weather_duration left at 0 (infinite) — rain never expires mid-battle.
	bm._force_roll = 100
	bm._force_crit = false
	# Solar Beam at roll=100, no crit, GRASS vs NORMAL, rain has no modifier on GRASS:
	#   base=120×85×22/85/50+2=54; roll: 54; STAB: (54×6144+2047)/4096=81; eff 1.0 → 81
	p2.current_hp = 81  # p2 faints on Solar Beam's release (turn 2) — ends battle at charge_count=1

	var charge_count := [0]
	var damage_events: Array = []

	bm.charge_started.connect(func(_a, _m): charge_count[0] += 1)
	bm.move_executed.connect(func(_a, _d, _m, dmg): damage_events.append(dmg))

	bm.queue_move(0, 0)  # P1 turn 1: Solar Beam (charge turn)
	bm.queue_move(1, 0)  # P2 turn 1: Tackle
	bm.queue_move(1, 0)  # P2 turn 2: Tackle (P1 auto-locks Solar Beam release)
	bm.start_battle(p1, p2)

	_chk("T5.01 charge_started fired once in rain", charge_count[0] == 1)
	var charged_damage: Array = damage_events.filter(func(d): return d > 0)
	_chk("T5.02 Solar Beam release dealt damage on turn 2 in rain",
			charged_damage.size() >= 1)
	_chk("T5.03 Charge turn emitted 0 damage (first move_executed has 0 damage)",
			damage_events.size() >= 1 and damage_events[0] == 0)
	bm.queue_free()


# ── T6: Skull Bash gives +1 Defense on charge turn ───────────────────────────
# Source: moves_info.h MOVE_SKULL_BASH additionalEffects
#   {MOVE_EFFECT_STAT_PLUS, .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE}
# On the charge turn, StatusManager.apply_stat_change(attacker, STAGE_DEF, 1) fires
# and stat_stage_changed(attacker, STAGE_DEF, 1) is emitted.

func _test_t6_skull_bash_def_boost() -> void:
	var skull := _load_move(130)
	_chk("T6.00 Skull Bash loads", skull != null)
	if skull == null:
		return

	var p1 := _make_mon("Bash", TypeChart.TYPE_NORMAL, 100)
	var p2 := _make_mon("Target", TypeChart.TYPE_NORMAL, 50, 400)
	var tackle := _make_tackle(10)
	p1.add_move(skull)
	p2.add_move(tackle)

	var bm := _make_bm()
	bm._force_roll = 100
	bm._force_crit = false
	# Skull Bash at roll=100, no crit, NORMAL vs NORMAL (atk=85, def=85, level 50):
	#   base=130×85×22/85/50+2=59; roll: 59; STAB: (59×6144+2047)/4096=88; eff 1.0 → 88
	p2.current_hp = 88  # p2 faints on Skull Bash's release (turn 2) — charge_count=1 only

	var def_boosts: Array = []  # array of actual_change values for STAGE_DEF
	var charge_fired := [false]

	bm.charge_started.connect(func(_a, _m): charge_fired[0] = true)
	bm.stat_stage_changed.connect(func(target, stat_idx, change):
		if target == p1 and stat_idx == BattlePokemon.STAGE_DEF:
			def_boosts.append(change))

	bm.queue_move(0, 0)  # P1 turn 1: Skull Bash (charge + def boost)
	bm.queue_move(1, 0)  # P2 turn 1: Tackle
	bm.queue_move(1, 0)  # P2 turn 2: Tackle (Skull Bash release)
	bm.start_battle(p1, p2)

	_chk("T6.01 charge_started fired", charge_fired[0])
	_chk("T6.02 stat_stage_changed fired for Defense",  def_boosts.size() >= 1)
	_chk("T6.03 Defense boost was +1 on charge turn",
			def_boosts.size() >= 1 and def_boosts[0] == 1)
	# The boost should only fire once — release turn does NOT re-apply it.
	_chk("T6.04 Defense boost fires exactly once (charge turn only)",
			def_boosts.size() == 1)
	bm.queue_free()
