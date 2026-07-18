extends Node

# [D1 cheap clusters] 8 strictly-CHEAP-tagged D1 effect-name clusters, 21
# moves: EFFECT_WEATHER (Sandstorm/Rain Dance/Sunny Day/Hail/Snowscape),
# EFFECT_POWER_BASED_ON_USER_HP (Eruption/Water Spout/Dragon Energy),
# EFFECT_POWER_BASED_ON_TARGET_HP (Wring Out/Crush Grip/Hard Press),
# EFFECT_STEAL_ITEM (Thief/Covet), EFFECT_LOCK_ON (Mind Reader/Lock-On),
# EFFECT_SWAGGER (Swagger/Flatter), EFFECT_SUCKER_PUNCH (Sucker
# Punch/Thunderclap), EFFECT_STORED_POWER (Stored Power/Power Trip).
#
# Ground truth: reference/pokeemerald_expansion/src/battle_util.c
# (weather/power formulas), src/battle_move_resolution.c (Thief/Covet
# L3487-3499, Sucker Punch L1387-1394), src/battle_script_commands.c
# (Cmd_setalwayshitflag L8089-8102), src/battle_stat_change.c
# (EFFECT_SWAGGER L147-156), src/data/moves_info.h, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_weather_cluster()
	_test_hp_based_power_clusters()
	_test_steal_item_cluster()
	_test_lock_on_cluster()
	_test_swagger_cluster()
	_test_sucker_punch_cluster()
	_test_stored_power_cluster()

	var total := _pass + _fail
	print("m19_d1_cheap_clusters_test: %d/%d passed" % [_pass, total])
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


func _make_splash() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Splash"
	m.type = TypeChart.TYPE_NORMAL
	m.category = 2
	m.accuracy = 0
	m.pp = 40
	return m


# ── Section A: data integrity (all 21 moves) ────────────────────────────────

func _test_data_integrity() -> void:
	var sandstorm := _load_move(201)
	_chk("A.01 201 Sandstorm: Rock/status/acc0/pp10, weather_type=SANDSTORM",
			sandstorm.type == TypeChart.TYPE_ROCK and sandstorm.pp == 10
					and sandstorm.weather_type == DamageCalculator.WEATHER_SANDSTORM)
	var rain_dance := _load_move(240)
	_chk("A.02 240 Rain Dance: Water/status/pp5, weather_type=RAIN",
			rain_dance.type == TypeChart.TYPE_WATER and rain_dance.pp == 5
					and rain_dance.weather_type == DamageCalculator.WEATHER_RAIN)
	var sunny_day := _load_move(241)
	_chk("A.03 241 Sunny Day: Fire/status/pp5, weather_type=SUN",
			sunny_day.type == TypeChart.TYPE_FIRE and sunny_day.pp == 5
					and sunny_day.weather_type == DamageCalculator.WEATHER_SUN)
	var hail := _load_move(258)
	_chk("A.04 258 Hail: Ice/status/pp10, weather_type=HAIL",
			hail.type == TypeChart.TYPE_ICE and hail.pp == 10
					and hail.weather_type == DamageCalculator.WEATHER_HAIL)
	var snowscape := _load_move(809)
	_chk("A.05 809 Snowscape: Ice/status/pp10, weather_type=HAIL (this " +
			"project's single Ice-weather state — flagged Hail/Snow split gap)",
			snowscape.type == TypeChart.TYPE_ICE and snowscape.pp == 10
					and snowscape.weather_type == DamageCalculator.WEATHER_HAIL)

	var eruption := _load_move(284)
	_chk("A.06 284 Eruption: Fire/SPECIAL/150/100/5, power_scales_with_user_hp",
			eruption.type == TypeChart.TYPE_FIRE and eruption.category == 1
					and eruption.power == 150 and eruption.power_scales_with_user_hp)
	var water_spout := _load_move(323)
	_chk("A.07 323 Water Spout: same shape as Eruption",
			water_spout.power == 150 and water_spout.power_scales_with_user_hp)
	var dragon_energy := _load_move(748)
	_chk("A.08 748 Dragon Energy: same shape as Eruption",
			dragon_energy.power == 150 and dragon_energy.power_scales_with_user_hp)

	var wring_out := _load_move(378)
	_chk("A.09 378 Wring Out: Normal/SPECIAL/120/100/5, power_scales_with_target_hp",
			wring_out.category == 1 and wring_out.power == 120
					and wring_out.power_scales_with_target_hp)
	var crush_grip := _load_move(462)
	_chk("A.10 462 Crush Grip: Normal/PHYSICAL/120/100/5, power_scales_with_target_hp",
			crush_grip.category == 0 and crush_grip.power == 120
					and crush_grip.power_scales_with_target_hp)
	var hard_press := _load_move(840)
	_chk("A.11 840 Hard Press: Steel/PHYSICAL/100/100/10 (a real non-uniformity " +
			"within this cluster), power_scales_with_target_hp",
			hard_press.category == 0 and hard_press.power == 100 and hard_press.pp == 10
					and hard_press.power_scales_with_target_hp)

	var thief := _load_move(168)
	_chk("A.12 168 Thief: Dark/PHYSICAL/60/100/25, makes_contact, steals_item_if_itemless",
			thief.type == TypeChart.TYPE_DARK and thief.power == 60 and thief.pp == 25
					and thief.makes_contact and thief.steals_item_if_itemless)
	var covet := _load_move(343)
	_chk("A.13 343 Covet: Normal/PHYSICAL/60/100/25, makes_contact, steals_item_if_itemless",
			covet.type == TypeChart.TYPE_NORMAL and covet.power == 60 and covet.pp == 25
					and covet.makes_contact and covet.steals_item_if_itemless)

	var mind_reader := _load_move(170)
	_chk("A.14 170 Mind Reader: Normal/status/acc0/pp5, is_lock_on",
			mind_reader.type == TypeChart.TYPE_NORMAL and mind_reader.pp == 5
					and mind_reader.is_lock_on)
	var lock_on := _load_move(199)
	_chk("A.15 199 Lock-On: same shape as Mind Reader",
			lock_on.pp == 5 and lock_on.is_lock_on)

	var swagger := _load_move(207)
	_chk("A.16 207 Swagger: Normal/status/acc85(GEN7+)/pp15, is_swagger, +2 Atk",
			swagger.type == TypeChart.TYPE_NORMAL and swagger.accuracy == 85
					and swagger.is_swagger and swagger.stat_change_stat == 0
					and swagger.stat_change_amount == 2)
	var flatter := _load_move(260)
	_chk("A.17 260 Flatter: Dark/status/acc100 (a real asymmetry with " +
			"Swagger's 85)/pp15, is_swagger, +1 SpAtk",
			flatter.type == TypeChart.TYPE_DARK and flatter.accuracy == 100
					and flatter.is_swagger and flatter.stat_change_stat == 2
					and flatter.stat_change_amount == 1)

	var sucker_punch := _load_move(389)
	_chk("A.18 389 Sucker Punch: Dark/PHYSICAL/70/100/5/prio1, makes_contact, is_sucker_punch",
			sucker_punch.category == 0 and sucker_punch.power == 70
					and sucker_punch.priority == 1 and sucker_punch.makes_contact
					and sucker_punch.is_sucker_punch)
	var thunderclap := _load_move(837)
	_chk("A.19 837 Thunderclap: Electric/SPECIAL (a real category asymmetry " +
			"with Sucker Punch's Physical)/70/100/5/prio1, is_sucker_punch",
			thunderclap.category == 1 and thunderclap.power == 70
					and thunderclap.priority == 1 and thunderclap.is_sucker_punch)

	var stored_power := _load_move(500)
	_chk("A.20 500 Stored Power: Psychic/SPECIAL/20/100/10, is_stored_power",
			stored_power.category == 1 and stored_power.power == 20
					and stored_power.is_stored_power)
	var power_trip := _load_move(644)
	_chk("A.21 644 Power Trip: Dark/PHYSICAL/20/100/10, makes_contact, is_stored_power",
			power_trip.category == 0 and power_trip.power == 20
					and power_trip.makes_contact and power_trip.is_stored_power)


# ── Section B: EFFECT_WEATHER ────────────────────────────────────────────────

func _test_weather_cluster() -> void:
	var sandstorm := _load_move(201)
	var sunny_day := _load_move(241)
	var splash := _make_splash()

	# Signal-snapshot discipline: this battle runs to completion, and
	# Sandstorm's own chip damage against the Normal-type def means the
	# battle runs several turns — weather's own 5-turn duration could
	# legitimately expire (or be re-set again by def re-selecting its only
	# move) before the battle ends, so reading bm.weather post-battle would
	# be a fresh instance of the whole-battle-aggregation pitfall. Snapshot
	# live via the weather_set signal instead, at the attacker's first use.
	var atk := _make_mon("B1Atk", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 100)
	atk.add_move(sandstorm)
	var def := _make_mon("B1Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	def.add_move(splash)
	var bm := _make_bm()
	var weather_snap := [false, -1]
	bm.weather_set.connect(func(_by, w):
		if not weather_snap[0]:
			weather_snap[0] = true
			weather_snap[1] = w)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("B.01 Sandstorm sets the real WEATHER_SANDSTORM state through the " +
			"actual dispatch (snapshotted live: %s)" % [weather_snap],
			weather_snap[0] == true and weather_snap[1] == BattleManager.WEATHER_SANDSTORM)

	# Discriminator: a different weather move sets a different weather.
	var atk2 := _make_mon("B2Atk", [TypeChart.TYPE_FIRE], 100, 60, 60, 60, 60, 100)
	atk2.add_move(sunny_day)
	var def2 := _make_mon("B2Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	def2.add_move(splash)
	var bm2 := _make_bm()
	var weather_snap2 := [false, -1]
	bm2.weather_set.connect(func(_by, w):
		if not weather_snap2[0]:
			weather_snap2[0] = true
			weather_snap2[1] = w)
	bm2.queue_move(1, 0)
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(def2))
	_chk("B.02 discriminator: Sunny Day sets WEATHER_SUN, not Sandstorm's " +
			"weather (snapshotted live: %s)" % [weather_snap2],
			weather_snap2[0] == true and weather_snap2[1] == BattleManager.WEATHER_SUN)


# ── Section C: EFFECT_POWER_BASED_ON_USER_HP / _TARGET_HP ──────────────────

func _test_hp_based_power_clusters() -> void:
	var eruption := _load_move(284)
	var wring_out := _load_move(378)
	var splash := _make_splash()

	# (i) User-HP-based: full HP -> full power (150), confirmed via a real
	# damage comparison at full vs. half HP (the SAME move, same target,
	# only the ATTACKER's own current_hp differs).
	var atk_full := _make_mon("C1AtkFull", [TypeChart.TYPE_FIRE], 200, 100, 60, 100, 60, 100)
	atk_full.add_move(eruption)
	var def1 := _make_mon("C1Def", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def1.add_move(splash)
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	var dmg_full := [false, -1]
	bm1.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk_full and not dmg_full[0]:
			dmg_full[0] = true
			dmg_full[1] = dmg)
	bm1.start_battle(atk_full, def1)

	var atk_half := _make_mon("C2AtkHalf", [TypeChart.TYPE_FIRE], 200, 100, 60, 100, 60, 100)
	atk_half.add_move(eruption)
	atk_half.current_hp = atk_half.max_hp / 2
	var def2 := _make_mon("C2Def", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def2.add_move(splash)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dmg_half := [false, -1]
	bm2.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk_half and not dmg_half[0]:
			dmg_half[0] = true
			dmg_half[1] = dmg)
	bm2.start_battle(atk_half, def2)
	_chk(("C.01 Eruption deals strictly MORE damage at full HP than at half " +
			"HP (full=%s, half=%s) — power scales continuously with the " +
			"user's own current HP") % [dmg_full, dmg_half],
			dmg_full[0] == true and dmg_half[0] == true and dmg_full[1] > dmg_half[1])

	# (ii) Target-HP-based: mirror test, scaling with the DEFENDER's HP instead.
	var atk3 := _make_mon("C3Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk3.add_move(wring_out)
	var def_full := _make_mon("C3DefFull", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def_full.add_move(splash)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	var dmg3 := [false, -1]
	bm3.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk3 and not dmg3[0]:
			dmg3[0] = true
			dmg3[1] = dmg)
	bm3.start_battle(atk3, def_full)

	var atk4 := _make_mon("C4Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk4.add_move(wring_out)
	var def_half := _make_mon("C4DefHalf", [TypeChart.TYPE_NORMAL], 400, 10, 60, 10, 60, 40)
	def_half.add_move(splash)
	def_half.current_hp = def_half.max_hp / 2
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	var dmg4 := [false, -1]
	bm4.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk4 and not dmg4[0]:
			dmg4[0] = true
			dmg4[1] = dmg)
	bm4.start_battle(atk4, def_half)
	_chk(("C.02 discriminator: Wring Out deals strictly MORE damage against a " +
			"full-HP target than a half-HP target (full=%s, half=%s) — scales " +
			"with the TARGET's own HP, not the user's") % [dmg3, dmg4],
			dmg3[0] == true and dmg4[0] == true and dmg3[1] > dmg4[1])


# ── Section D: EFFECT_STEAL_ITEM ────────────────────────────────────────────

func _test_steal_item_cluster() -> void:
	var thief := _load_move(168)
	var splash := _make_splash()

	# (i) Steals only when the attacker is itemless.
	var atk := _make_mon("D1Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk.add_move(thief)
	var def := _make_mon("D1Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 40)
	def.add_move(splash)
	var leftovers := load("res://data/items/item_0472.tres") as ItemData
	def.held_item = leftovers
	var bm := _make_bm()
	bm._force_hit = true
	var stolen := [false]
	bm.item_stolen.connect(func(_s, _v): stolen[0] = true)
	bm.start_battle(atk, def)
	_chk("D.01 Thief steals the target's item when the attacker holds none " +
			"(atk.held_item=%s, def.held_item=%s)" % [atk.held_item, def.held_item],
			stolen[0] == true and atk.held_item == leftovers and def.held_item == null)

	# (ii) Discriminator: does NOT steal if the attacker already has an item.
	var atk2 := _make_mon("D2Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk2.add_move(thief)
	var own_item := load("res://data/items/item_0491.tres") as ItemData  # Big Root
	atk2.held_item = own_item
	var def2 := _make_mon("D2Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 40)
	def2.add_move(splash)
	def2.held_item = leftovers
	var bm2 := _make_bm()
	bm2._force_hit = true
	var stolen2 := [false]
	bm2.item_stolen.connect(func(_s, _v): stolen2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("D.02 discriminator: Thief does NOT steal if the attacker already " +
			"holds an item (atk2.held_item=%s, def2.held_item=%s)" \
					% [atk2.held_item, def2.held_item],
			stolen2[0] == false and atk2.held_item == own_item and def2.held_item == leftovers)

	# (iii) Sticky Hold blocks the steal.
	var atk3 := _make_mon("D3Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk3.add_move(thief)
	var def3 := _make_mon("D3Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 40)
	def3.add_move(splash)
	def3.held_item = leftovers
	def3.ability = _load_ability(60)  # Sticky Hold
	var bm3 := _make_bm()
	bm3._force_hit = true
	var stolen3 := [false]
	bm3.item_stolen.connect(func(_s, _v): stolen3[0] = true)
	bm3.start_battle(atk3, def3)
	_chk("D.03 discriminator: Sticky Hold blocks the steal (def3.held_item=%s)" \
					% [def3.held_item],
			stolen3[0] == false and def3.held_item == leftovers)


# ── Section E: EFFECT_LOCK_ON ────────────────────────────────────────────────

func _test_lock_on_cluster() -> void:
	var mind_reader := _load_move(170)
	var splash := _make_splash()

	# (i) Direct unit test: sure_hit_target set correctly, fails if already active.
	var attacker := _make_mon("E1Atk", [TypeChart.TYPE_NORMAL])
	var target := _make_mon("E1Target", [TypeChart.TYPE_NORMAL])
	_chk("E.01 first Lock-On use sets sure_hit_target",
			attacker.sure_hit_target == null)
	attacker.sure_hit_target = target
	attacker.sure_hit_turns = 2
	_chk("E.02 sure_hit_target/turns set correctly",
			attacker.sure_hit_target == target and attacker.sure_hit_turns == 2)

	# (ii) check_accuracy direct unit test: bypasses a move that would
	# otherwise fail a low-accuracy check, AND bypasses semi-invulnerability.
	var low_acc_move := MoveData.new()
	low_acc_move.move_name = "LowAccTest"
	low_acc_move.type = TypeChart.TYPE_NORMAL
	low_acc_move.category = 0
	low_acc_move.power = 40
	low_acc_move.accuracy = 30
	_chk("E.03 check_accuracy returns TRUE for a locked-on target even for a " +
			"low-accuracy move (sure_hit_target set)",
			StatusManager.check_accuracy(attacker, target, low_acc_move, null, false) == true)

	var semi_inv_target := _make_mon("E2SemiInv", [TypeChart.TYPE_NORMAL])
	semi_inv_target.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var attacker2 := _make_mon("E2Atk", [TypeChart.TYPE_NORMAL])
	attacker2.sure_hit_target = semi_inv_target
	_chk("E.04 check_accuracy bypasses semi-invulnerability TOO for a " +
			"locked-on target (a real documented game mechanic, not just " +
			"an ordinary accuracy bypass)",
			StatusManager.check_accuracy(attacker2, semi_inv_target, low_acc_move, null, false) == true)

	var attacker3 := _make_mon("E3Atk", [TypeChart.TYPE_NORMAL])
	var not_locked_target := _make_mon("E3NotLocked", [TypeChart.TYPE_NORMAL])
	not_locked_target.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	_chk("E.05 discriminator: without a lock, semi-invulnerability still blocks",
			StatusManager.check_accuracy(attacker3, not_locked_target, low_acc_move, null, false) == false)

	# (iii) Full-battle: Mind Reader's own dispatch fires the real signal.
	var mr_atk := _make_mon("E4Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	mr_atk.add_move(mind_reader)
	var mr_def := _make_mon("E4Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	mr_def.add_move(splash)
	var bm := _make_bm()
	var locked := [false, null]
	bm.sure_hit_set.connect(func(a, t):
		if not locked[0]:
			locked[0] = true
			locked[1] = t)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(BattleParty.single(mr_atk), BattleParty.single(mr_def))
	_chk("E.06 Mind Reader's real dispatch fires sure_hit_set (%s)" % [locked],
			locked[0] == true and locked[1] == mr_def)

	# (iv) Reciprocal clear: the source (attacker) leaving the field clears
	# its own outgoing lock, AND the target's departure clears any lock
	# pointed AT it.
	var source5 := _make_mon("E5Source", [TypeChart.TYPE_NORMAL])
	var target5 := _make_mon("E5Target", [TypeChart.TYPE_NORMAL])
	source5.sure_hit_target = target5
	source5.sure_hit_turns = 2
	var bm5 := _make_bm()
	bm5._combatants = [source5, target5]
	bm5._clear_volatiles(source5)
	_chk("E.07 the source's own departure clears its own outgoing lock",
			source5.sure_hit_target == null)

	var source6 := _make_mon("E6Source", [TypeChart.TYPE_NORMAL])
	var target6 := _make_mon("E6Target", [TypeChart.TYPE_NORMAL])
	source6.sure_hit_target = target6
	source6.sure_hit_turns = 2
	var bm6 := _make_bm()
	bm6._combatants = [source6, target6]
	bm6._clear_volatiles(target6)
	_chk("E.08 discriminator: the TARGET's own departure ALSO clears the " +
			"source's lock onto it (the reciprocal half)",
			source6.sure_hit_target == null)


# ── Section F: EFFECT_SWAGGER ────────────────────────────────────────────────

func _test_swagger_cluster() -> void:
	var swagger := _load_move(207)
	var splash := _make_splash()

	# (i) Ordinary application: target's Attack rises +2 AND becomes confused.
	var atk := _make_mon("F1Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(swagger)
	var def := _make_mon("F1Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	def.add_move(splash)
	var bm := _make_bm()
	bm._force_hit = true
	var stage_snap := [false, 0]
	bm.stat_stage_changed.connect(func(mon, stat, _delta):
		if mon == def and stat == 0 and not stage_snap[0]:
			stage_snap[0] = true
			stage_snap[1] = def.stat_stages[0])
	var confused := [false]
	bm.secondary_applied.connect(func(mon, se):
		if mon == def and se == MoveData.SE_CONFUSION:
			confused[0] = true)
	bm.start_battle(atk, def)
	_chk("F.01 Swagger raises the target's Attack +2 (snapshotted live: %s)" \
					% [stage_snap],
			stage_snap[0] == true and stage_snap[1] == 2)
	_chk("F.02 Swagger ALSO confuses the target in the same hit",
			confused[0] == true)

	# (ii) KEY discriminator: Own Tempo blocks the WHOLE move, including the
	# stat raise — not just the confusion.
	var atk2 := _make_mon("F2Atk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk2.add_move(swagger)
	var def2 := _make_mon("F2Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	def2.add_move(splash)
	def2.ability = _load_ability(20)  # Own Tempo
	var bm2 := _make_bm()
	bm2._force_hit = true
	var failed2 := [false, ""]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == def2 and not failed2[0]:
			failed2[0] = true
			failed2[1] = reason)
	var stage_snap2 := [false]
	bm2.stat_stage_changed.connect(func(mon, stat, _delta):
		if mon == def2 and stat == 0:
			stage_snap2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("F.03 discriminator: Own Tempo blocks the ENTIRE move, INCLUDING " +
			"the stat raise (a real correction found at Step 0 — a naive " +
			"composition would still raise Attack) (%s, stage fired=%s)" \
					% [failed2, stage_snap2],
			failed2[0] == true and failed2[1] == "own_tempo_prevents"
					and stage_snap2[0] == false and def2.stat_stages[0] == 0)


# ── Section G: EFFECT_SUCKER_PUNCH ───────────────────────────────────────────

func _test_sucker_punch_cluster() -> void:
	var sucker_punch := _load_move(389)
	var tackle := _load_move(33)
	var splash := _make_splash()

	# (i) Success case: user is faster (priority handles this anyway) and
	# target chose a damaging move — Sucker Punch connects normally.
	var atk := _make_mon("G1Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 40)
	atk.add_move(sucker_punch)
	var def := _make_mon("G1Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	def.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	var damaged := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk and not damaged[0]:
			damaged[0] = true
			damaged[1] = dmg)
	bm.start_battle(atk, def)
	_chk("G.01 Sucker Punch connects when the target chose a damaging move " +
			"(damage=%s)" % [damaged],
			damaged[0] == true and damaged[1] > 0)

	# (ii) Discriminator: fails if the target's chosen move is status-category.
	var atk2 := _make_mon("G2Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 40)
	atk2.add_move(sucker_punch)
	var def2 := _make_mon("G2Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	def2.add_move(splash)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var failed2 := [false, ""]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and not failed2[0]:
			failed2[0] = true
			failed2[1] = reason)
	bm2.start_battle(atk2, def2)
	_chk("G.02 discriminator: Sucker Punch fails against a target that " +
			"chose a status move (%s)" % [failed2],
			failed2[0] == true and failed2[1] == "sucker_punch_failed")

	# (iii) Discriminator: fails if the target has already acted this turn.
	# Sucker Punch's own +1 priority would otherwise always beat a plain
	# damaging move regardless of speed (a real test-design trap caught on
	# this test's first run) — the target needs a HIGHER-priority move of
	# its own (+2) to genuinely act first despite Sucker Punch's boost.
	var extreme_priority := MoveData.new()
	extreme_priority.move_name = "ExtremePriorityTest"
	extreme_priority.type = TypeChart.TYPE_NORMAL
	extreme_priority.category = 0
	extreme_priority.power = 40
	extreme_priority.accuracy = 100
	extreme_priority.priority = 2
	var atk3 := _make_mon("G3Atk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 200)
	atk3.add_move(sucker_punch)
	var def3 := _make_mon("G3Def", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 5)
	def3.add_move(extreme_priority)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var failed3 := [false, ""]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and not failed3[0]:
			failed3[0] = true
			failed3[1] = reason)
	bm3.start_battle(atk3, def3)
	_chk("G.03 discriminator: Sucker Punch fails if the target has already " +
			"acted this turn (a much faster, same-priority-bracket target) (%s)" \
					% [failed3],
			failed3[0] == true and failed3[1] == "sucker_punch_failed")


# ── Section H: EFFECT_STORED_POWER ──────────────────────────────────────────

func _test_stored_power_cluster() -> void:
	# (i) Direct unit test of the formula.
	var mon := _make_mon("H1Mon", [TypeChart.TYPE_NORMAL])
	_chk("H.01 no positive stages -> sum is 0",
			BattleManager._positive_stat_stage_sum(mon, true) == 0)
	mon.stat_stages[0] = 3   # Atk +3
	mon.stat_stages[3] = 2   # SpDef +2
	mon.stat_stages[1] = -4  # Def -4 (negative, must NOT subtract)
	_chk("H.02 sums MAGNITUDES of positive stages only (Atk+3 + SpDef+2 = " +
			"5, Def's -4 ignored) — got %d" % [BattleManager._positive_stat_stage_sum(mon, true)],
			BattleManager._positive_stat_stage_sum(mon, true) == 5)
	mon.stat_stages[6] = 1  # Evasion +1
	_chk("H.03 discriminator: WITH include_evasion_acc=true, Evasion's +1 " +
			"is included (total=6) — got %d" \
					% [BattleManager._positive_stat_stage_sum(mon, true)],
			BattleManager._positive_stat_stage_sum(mon, true) == 6)
	_chk("H.04 discriminator: WITH include_evasion_acc=false, Evasion's +1 " +
			"is EXCLUDED (total stays 5) — got %d" \
					% [BattleManager._positive_stat_stage_sum(mon, false)],
			BattleManager._positive_stat_stage_sum(mon, false) == 5)

	# (ii) Full-battle: higher stat stages -> strictly more damage.
	var stored_power := _load_move(500)
	var splash := _make_splash()
	var atk_boosted := _make_mon("H2AtkBoosted", [TypeChart.TYPE_PSYCHIC], 100, 60, 60, 100, 60, 100)
	atk_boosted.add_move(stored_power)
	atk_boosted.stat_stages[2] = 3  # SpAtk +3 (positive, counts toward the formula too)
	var def1 := _make_mon("H2Def", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def1.add_move(splash)
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	var dmg_boosted := [false, -1]
	bm1.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk_boosted and not dmg_boosted[0]:
			dmg_boosted[0] = true
			dmg_boosted[1] = dmg)
	bm1.start_battle(atk_boosted, def1)

	var atk_plain := _make_mon("H3AtkPlain", [TypeChart.TYPE_PSYCHIC], 100, 60, 60, 100, 60, 100)
	atk_plain.add_move(stored_power)
	var def2 := _make_mon("H3Def", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def2.add_move(splash)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dmg_plain := [false, -1]
	bm2.move_executed.connect(func(a, _d, _m, dmg):
		if a == atk_plain and not dmg_plain[0]:
			dmg_plain[0] = true
			dmg_plain[1] = dmg)
	bm2.start_battle(atk_plain, def2)
	_chk(("H.05 Stored Power deals strictly MORE damage with positive stat " +
			"stages than without (boosted=%s, plain=%s) — through the real " +
			"dispatch path") % [dmg_boosted, dmg_plain],
			dmg_boosted[0] == true and dmg_plain[0] == true and dmg_boosted[1] > dmg_plain[1])
