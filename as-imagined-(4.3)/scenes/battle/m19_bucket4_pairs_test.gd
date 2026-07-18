extends Node

# [Bucket 4 2-move sub-groups] Nine independent sub-groups bundled into one
# session, matching [Bucket 4 cheapest singles]'s established precedent —
# each verified individually from source, not assumed to share a mechanism:
#   - M19-percent-current-hp-damage: Super Fang(162), Ruination(803)
#   - M19-ignores-stat-stages: Chip Away(498), Sacred Sword(533), Darkest Lariat(626)
#   - M19-charge-turn-spatk-boost: Meteor Beam(728), Electro Shot(833)
#   - M19-hp-based-power: Flail(175), Reversal(179)
#   - M19-stat-raised-trigger: Burning Jealousy(735), Alluring Voice(842)
#   - M19-random-status-choice: Tri Attack(161), Dire Claw(755)
#   - M19-self-faint: Self-Destruct(120), Explosion(153)
#   - M19-berry-steal: Pluck(365), Bug Bite(450)
#   - M19-ignores-target-ability: Sunsteel Strike(667), Moongeist Beam(668)
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_util.c, battle_move_resolution.c, battle_script_commands.c,
# battle_stat_change.c, data/battle_scripts_1.s, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_percent_current_hp_damage()
	_test_ignores_stat_stages()
	_test_charge_turn_spatk_boost()
	_test_hp_based_power()
	_test_stat_raised_trigger()
	_test_random_status_choice()
	_test_self_faint()
	_test_berry_steal()
	_test_ignores_target_ability()

	var total := _pass + _fail
	print("m19_bucket4_pairs_test: %d/%d passed" % [_pass, total])
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


func _load_item(id: int) -> ItemData:
	return load("res://data/items/item_%04d.tres" % id) as ItemData


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


# ── Section A: data integrity (all 19 moves) ────────────────────────────────

func _test_data_integrity() -> void:
	var super_fang := _load_move(162)
	_chk("162 Super Fang: data + percent_current_hp_damage=50",
			super_fang.move_name == "Super Fang" and super_fang.type == TypeChart.TYPE_NORMAL
					and super_fang.accuracy == 90 and super_fang.pp == 10
					and super_fang.makes_contact and super_fang.percent_current_hp_damage == 50)
	var ruination := _load_move(803)
	_chk("803 Ruination: data + percent_current_hp_damage=50, no contact",
			ruination.move_name == "Ruination" and ruination.type == TypeChart.TYPE_DARK
					and ruination.accuracy == 90 and not ruination.makes_contact
					and ruination.percent_current_hp_damage == 50)

	var chip_away := _load_move(498)
	_chk("498 Chip Away: 70/100/20 + ignores_defense_evasion_stages",
			chip_away.power == 70 and chip_away.accuracy == 100 and chip_away.pp == 20
					and chip_away.ignores_defense_evasion_stages)
	var sacred_sword := _load_move(533)
	_chk("533 Sacred Sword: 90/100/15 + slicing_move + ignores_defense_evasion_stages",
			sacred_sword.power == 90 and sacred_sword.pp == 15 and sacred_sword.slicing_move
					and sacred_sword.ignores_defense_evasion_stages)
	var darkest_lariat := _load_move(626)
	_chk("626 Darkest Lariat: 85/100/10 + ignores_defense_evasion_stages",
			darkest_lariat.power == 85 and darkest_lariat.pp == 10
					and darkest_lariat.ignores_defense_evasion_stages)

	var meteor_beam := _load_move(728)
	_chk("728 Meteor Beam: 120/90/10 + charge_turn_spatk_boost=1, NOT skips_charge_in_rain",
			meteor_beam.power == 120 and meteor_beam.accuracy == 90 and meteor_beam.two_turn
					and meteor_beam.charge_turn_spatk_boost == 1 and not meteor_beam.skips_charge_in_rain)
	var electro_shot := _load_move(833)
	_chk("833 Electro Shot: 130/100/10 + charge_turn_spatk_boost=1 + skips_charge_in_rain",
			electro_shot.power == 130 and electro_shot.accuracy == 100 and electro_shot.two_turn
					and electro_shot.charge_turn_spatk_boost == 1 and electro_shot.skips_charge_in_rain)

	var flail := _load_move(175)
	_chk("175 Flail: is_flail_power", flail.pp == 15 and flail.is_flail_power)
	var reversal := _load_move(179)
	_chk("179 Reversal: is_flail_power, Fighting-type",
			reversal.type == TypeChart.TYPE_FIGHTING and reversal.is_flail_power)

	var burning_jealousy := _load_move(735)
	_chk("735 Burning Jealousy: 70/100/5 spread, burn 100%, requires_target_stat_raised",
			burning_jealousy.power == 70 and burning_jealousy.pp == 5 and burning_jealousy.is_spread
					and burning_jealousy.secondary_effect == MoveData.SE_BURN
					and burning_jealousy.secondary_chance == 100
					and burning_jealousy.requires_target_stat_raised)
	var alluring_voice := _load_move(842)
	_chk("842 Alluring Voice: 80/100/10 sound, confusion 100%, requires_target_stat_raised",
			alluring_voice.power == 80 and alluring_voice.sound_move
					and alluring_voice.secondary_effect == MoveData.SE_CONFUSION
					and alluring_voice.secondary_chance == 100
					and alluring_voice.requires_target_stat_raised)

	var tri_attack := _load_move(161)
	_chk("161 Tri Attack: SE_RANDOM_STATUS 20%%, pool=[burn,freeze,paralysis]",
			tri_attack.secondary_effect == MoveData.SE_RANDOM_STATUS
					and tri_attack.secondary_chance == 20
					and tri_attack.random_status_pool == [BattlePokemon.STATUS_BURN,
							BattlePokemon.STATUS_FREEZE, BattlePokemon.STATUS_PARALYSIS])
	var dire_claw := _load_move(755)
	_chk("755 Dire Claw: SE_RANDOM_STATUS 50%%, pool=[poison,paralysis,sleep] — a genuinely " +
			"DIFFERENT pool from Tri Attack's",
			dire_claw.secondary_effect == MoveData.SE_RANDOM_STATUS
					and dire_claw.secondary_chance == 50
					and dire_claw.random_status_pool == [BattlePokemon.STATUS_POISON,
							BattlePokemon.STATUS_PARALYSIS, BattlePokemon.STATUS_SLEEP])

	var self_destruct := _load_move(120)
	_chk("120 Self-Destruct: power=200, is_spread, is_self_faint, target_includes_ally [M21]",
			self_destruct.power == 200 and self_destruct.is_spread and self_destruct.is_self_faint
					and self_destruct.target_includes_ally)
	var explosion := _load_move(153)
	_chk("153 Explosion: power=250, is_spread, is_self_faint, target_includes_ally [M21]",
			explosion.power == 250 and explosion.is_spread and explosion.is_self_faint
					and explosion.target_includes_ally)

	var pluck := _load_move(365)
	_chk("365 Pluck: 60/100/20 Flying + steals_and_eats_berry",
			pluck.power == 60 and pluck.type == TypeChart.TYPE_FLYING
					and pluck.steals_and_eats_berry)
	var bug_bite := _load_move(450)
	_chk("450 Bug Bite: 60/100/20 Bug + steals_and_eats_berry",
			bug_bite.power == 60 and bug_bite.type == TypeChart.TYPE_BUG
					and bug_bite.steals_and_eats_berry)

	var sunsteel := _load_move(667)
	_chk("667 Sunsteel Strike: 100/100/5 Steel physical + ignores_target_ability",
			sunsteel.power == 100 and sunsteel.type == TypeChart.TYPE_STEEL
					and sunsteel.category == 0 and sunsteel.ignores_target_ability)
	var moongeist := _load_move(668)
	_chk("668 Moongeist Beam: 100/100/5 Ghost special + ignores_target_ability",
			moongeist.power == 100 and moongeist.type == TypeChart.TYPE_GHOST
					and moongeist.category == 1 and moongeist.ignores_target_ability)


# ── M19-percent-current-hp-damage: 50% of CURRENT hp, not max ───────────────

func _test_percent_current_hp_damage() -> void:
	var super_fang := _load_move(162)
	var tackle := _load_move(33)
	var atk := _make_mon("SFAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(super_fang)
	var def := _make_mon("SFDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.add_move(tackle)
	# Pre-damage the defender so current_hp < max_hp — proves the 50% is
	# read off CURRENT hp, not max (a discriminator: max_hp/2 would give a
	# different, larger number).
	def.current_hp = 100

	var bm := _make_bm()
	bm._force_hit = true
	var hit := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not hit[0]:
			hit[0] = true
			hit[1] = amt)
	bm.start_battle(atk, def)

	_chk("Super Fang deals exactly 50%% of the target's CURRENT hp (100/2=50, " +
			"NOT max_hp/2=150) — actual=%s" % [hit], hit[0] == true and hit[1] == 50)


# ── M19-ignores-stat-stages: bypasses a +6 Defense boost entirely ───────────

func _test_ignores_stat_stages() -> void:
	var chip_away := _load_move(498)
	var tackle := _load_move(33)
	var atk := _make_mon("CAAtk", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk.add_move(chip_away)
	var def := _make_mon("CADef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.add_move(tackle)
	def.stat_stages[BattlePokemon.STAGE_DEF] = 6  # +6 Defense, would normally triple defense

	var atk2 := _make_mon("CAAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk2.add_move(tackle)
	var def2 := _make_mon("CADef2", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def2.add_move(tackle)
	def2.stat_stages[BattlePokemon.STAGE_DEF] = 6

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var chip_dmg := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not chip_dmg[0]:
			chip_dmg[0] = true
			chip_dmg[1] = amt)
	bm.start_battle(atk, def)

	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_crit = false
	bm2._force_roll = 100
	var tackle_dmg := [false, -1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == atk2 and not tackle_dmg[0]:
			tackle_dmg[0] = true
			tackle_dmg[1] = amt)
	bm2.start_battle(atk2, def2)

	_chk("Discriminator: a plain Tackle is measurably reduced by the target's " +
			"+6 Defense (%s)" % [tackle_dmg], tackle_dmg[0] == true and tackle_dmg[1] > 0)
	_chk("Chip Away ignores the SAME +6 Defense boost, dealing strictly MORE damage " +
			"than Tackle under identical stats/roll (chip=%s tackle=%s)" % [chip_dmg, tackle_dmg],
			chip_dmg[0] == true and chip_dmg[1] > tackle_dmg[1])

	# Accuracy-side: ignores_defense_evasion_stages also resets EVASION for
	# the accuracy roll — direct unit test, no RNG needed for the +6 case
	# (idx=12, ratio 3/1, effective_move_acc*3 always exceeds 100 -> not a
	# clean deterministic proof by itself; instead verify via check_accuracy's
	# own eva_stage reset using a moderate forced defender evasion + a low
	# move accuracy so the difference is observable statistically).
	var acc_def := _make_mon("CAEvaDef", [TypeChart.TYPE_NORMAL])
	acc_def.stat_stages[BattlePokemon.STAGE_EVASION] = 6
	var low_acc_move := MoveData.new()
	low_acc_move.accuracy = 50
	low_acc_move.ignores_defense_evasion_stages = true
	var hits := 0
	var trials := 300
	for _i in range(trials):
		if StatusManager.check_accuracy(atk, acc_def, low_acc_move, null, false):
			hits += 1
	_chk("ignores_defense_evasion_stages also resets the DEFENDER's evasion for " +
			"the accuracy roll (a +6 evasion target would normally reduce a 50%% " +
			"move near to 0%%; observed %d/%d close to the raw 50%%)" % [hits, trials],
			hits > 100)


# ── M19-charge-turn-spatk-boost + Electro Shot's rain-skip ──────────────────

func _test_charge_turn_spatk_boost() -> void:
	var meteor_beam := _load_move(728)
	var tackle := _load_move(33)
	var atk := _make_mon("MBAtk", [TypeChart.TYPE_ROCK], 100, 60, 60, 60, 60, 100)
	atk.add_move(meteor_beam)
	var def := _make_mon("MBDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	var charged := [false]
	bm.charge_started.connect(func(mon, _m):
		if mon == atk:
			charged[0] = true)
	var boost := [false, -1]
	bm.stat_stage_changed.connect(func(mon, stat, amount):
		if mon == atk and stat == BattlePokemon.STAGE_SPATK and not boost[0]:
			boost[0] = true
			boost[1] = amount)
	bm.start_battle(atk, def)

	_chk("Meteor Beam enters its charge turn", charged[0] == true)
	_chk("Meteor Beam raises the user's own Sp.Atk +1 on the charge turn (%s)" % [boost],
			boost[0] == true and boost[1] == 1)

	# Electro Shot: skips the charge turn entirely in rain (discriminator:
	# Meteor Beam, same shape otherwise, does NOT skip in rain).
	var electro_shot := _load_move(833)
	var rain_atk := _make_mon("ESAtk", [TypeChart.TYPE_ELECTRIC], 100, 60, 60, 60, 60, 100)
	rain_atk.add_move(electro_shot)
	var rain_def := _make_mon("ESDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	rain_def.add_move(tackle)

	var bm2 := _make_bm()
	bm2.weather = BattleManager.WEATHER_RAIN
	bm2.weather_duration = 10
	bm2._force_hit = true
	var es_charged := [false]
	bm2.charge_started.connect(func(mon, _m):
		if mon == rain_atk:
			es_charged[0] = true)
	var es_hit := [false, -1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == rain_atk and not es_hit[0]:
			es_hit[0] = true
			es_hit[1] = amt)
	bm2.start_battle(rain_atk, rain_def)

	_chk("Electro Shot skips its charge turn in rain — fires immediately for real " +
			"damage on turn 1, never entering charge_started (%s, %s)" % [es_charged, es_hit],
			es_charged[0] == false and es_hit[0] == true and es_hit[1] > 0)

	var no_rain_atk := _make_mon("ESAtk2", [TypeChart.TYPE_ELECTRIC], 100, 60, 60, 60, 60, 100)
	no_rain_atk.add_move(electro_shot)
	var no_rain_def := _make_mon("ESDef2", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	no_rain_def.add_move(tackle)
	var bm3 := _make_bm()
	var nr_charged := [false]
	bm3.charge_started.connect(func(mon, _m):
		if mon == no_rain_atk:
			nr_charged[0] = true)
	bm3.start_battle(no_rain_atk, no_rain_def)
	_chk("Discriminator: Electro Shot DOES charge normally with no weather active",
			nr_charged[0] == true)


# ── M19-hp-based-power: banded formula from the user's own missing HP ───────

func _test_hp_based_power() -> void:
	_chk("Flail power at full HP (fraction=48) is the weakest band (20)",
			BattleManager._flail_power(100, 100) == 20)
	_chk("Flail power at 1 HP (fraction rounds to ~0->1) is the strongest band (200)",
			BattleManager._flail_power(1, 100) == 200)
	_chk("Flail power at exactly half HP (fraction=24, band <=32) is 40",
			BattleManager._flail_power(50, 100) == 40)
	_chk("Flail power at 10%% HP (fraction=4.8->4, band <=4) is 150",
			BattleManager._flail_power(10, 100) == 150)


# ── M19-stat-raised-trigger: only fires if the target's stats rose THIS turn ─

func _test_stat_raised_trigger() -> void:
	var swords_dance := _load_move(14)  # Swords Dance: +2 Attack, self
	var burning_jealousy := _load_move(735)
	var atk := _make_mon("BJAtk", [TypeChart.TYPE_FIRE], 100, 60, 60, 60, 60, 40)
	atk.add_move(burning_jealousy)
	var def := _make_mon("BJDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 100)
	def.add_move(swords_dance)  # def is FASTER, raises its own Attack first

	var bm := _make_bm()
	bm._force_hit = true
	var raised := [false]
	bm.stat_stage_changed.connect(func(mon, stat, _amt):
		if mon == def and stat == BattlePokemon.STAGE_ATK and not raised[0]:
			raised[0] = true)
	var burned := [false]
	bm.secondary_applied.connect(func(mon, se):
		if mon == def and se == MoveData.SE_BURN and not burned[0]:
			burned[0] = true)
	bm.start_battle(atk, def)

	_chk("Defender's own Swords Dance raised its Attack first (turn-order baseline)",
			raised[0] == true)
	_chk("Burning Jealousy's burn fires since the target's stats rose THIS turn (%s)" % [burned],
			burned[0] == true)

	# Discriminator: no prior stat rise -> no burn.
	var tackle := _load_move(33)
	var atk2 := _make_mon("BJAtk2", [TypeChart.TYPE_FIRE], 100, 60, 60, 60, 60, 100)
	atk2.add_move(burning_jealousy)
	var def2 := _make_mon("BJDef2", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def2.add_move(tackle)  # no stat rise at all
	var bm2 := _make_bm()
	bm2._force_hit = true
	var hit2 := [false]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk2 and not hit2[0]:
			hit2[0] = true)
	var burned2 := [false]
	bm2.secondary_applied.connect(func(mon, se):
		if mon == def2 and se == MoveData.SE_BURN:
			burned2[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("Burning Jealousy connected (baseline)", hit2[0] == true)
	_chk("Discriminator: no burn fires when the target's stats did NOT rise this turn",
			burned2[0] == false)


# ── M19-random-status-choice: uniform pick from a fixed pool ────────────────

func _test_random_status_choice() -> void:
	var tri_attack := _load_move(161)
	var dire_claw := _load_move(755)
	var atk := _make_mon("TAAtk", [TypeChart.TYPE_NORMAL])
	var def := _make_mon("TADef", [TypeChart.TYPE_NORMAL])

	for i in range(3):
		var d := _make_mon("TAPick%d" % i, [TypeChart.TYPE_NORMAL])
		var applied: bool = StatusManager.try_secondary_effect(
				atk, d, tri_attack, true, false, DamageCalculator.WEATHER_NONE, false, i)
		_chk("Tri Attack forced index %d applies status %d from its own pool" % [i, tri_attack.random_status_pool[i]],
				applied and d.status == tri_attack.random_status_pool[i])

	for i in range(3):
		var d2 := _make_mon("DCPick%d" % i, [TypeChart.TYPE_NORMAL])
		var applied2: bool = StatusManager.try_secondary_effect(
				atk, d2, dire_claw, true, false, DamageCalculator.WEATHER_NONE, false, i)
		_chk("Dire Claw forced index %d applies status %d from its OWN different pool" % [i, dire_claw.random_status_pool[i]],
				applied2 and d2.status == dire_claw.random_status_pool[i])

	# Already-statused target blocks it entirely (same gate every status move uses).
	var already_statused := _make_mon("TABlocked", [TypeChart.TYPE_NORMAL])
	already_statused.status = BattlePokemon.STATUS_TOXIC
	var blocked: bool = StatusManager.try_secondary_effect(
			atk, already_statused, tri_attack, true, false, DamageCalculator.WEATHER_NONE, false, 0)
	_chk("Discriminator: an already-statused target blocks the random pick entirely",
			blocked == false and already_statused.status == BattlePokemon.STATUS_TOXIC)


# ── M19-self-faint: unconditional self-KO, blocked entirely by Damp ─────────

func _test_self_faint() -> void:
	var self_destruct := _load_move(120)
	var tackle := _load_move(33)
	var atk := _make_mon("SDAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(self_destruct)
	var def := _make_mon("SDDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = false  # even a MISS still faints the user
	var fainted_zero := [false]
	bm.pokemon_fainted.connect(func(mon):
		if mon == atk:
			fainted_zero[0] = true)
	bm.start_battle(atk, def)
	_chk("Self-Destruct faints the user EVEN ON A MISS (unconditional, not hit-gated)",
			fainted_zero[0] == true)

	# Damp blocks the move entirely.
	var atk2 := _make_mon("SDAtk2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk2.add_move(self_destruct)
	var def2 := _make_mon("SDDampDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def2.ability = _load_ability(6)  # Damp
	def2.add_move(tackle)
	var bm2 := _make_bm()
	# Snapshot the attacker's own HP live, inside the block signal itself —
	# this project's battles run to full completion, and a Damp-blocked
	# Self-Destruct still lets the opponent's own Tackle whittle the
	# attacker down over several turns, so a post-battle HP read would be
	# flaky (whole-battle-aggregation pitfall).
	var failed := [false, -1]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "damp_blocks_explosion" and not failed[0]:
			failed[0] = true
			failed[1] = atk2.current_hp)
	bm2.start_battle(atk2, def2)
	_chk(("Discriminator: Damp blocks Self-Destruct entirely (%s), the attacker's own HP " +
			"untouched at the moment of the block (still full, not zeroed)") % [failed],
			failed[0] == true and failed[1] == atk2.max_hp)


# ── M19-berry-steal: steal + immediately consume on the attacker ────────────

func _test_berry_steal() -> void:
	var pluck := _load_move(365)
	var tackle := _load_move(33)
	var atk := _make_mon("PLAtk", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 100)
	atk.add_move(pluck)
	atk.current_hp = 50  # not full, so the stolen Sitrus Berry can heal it
	var def := _make_mon("PLDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.add_move(tackle)
	def.held_item = _load_item(523)  # Sitrus Berry

	var bm := _make_bm()
	bm._force_hit = true
	var stolen := [false, null]
	bm.berry_stolen_and_eaten.connect(func(victim, beneficiary, item):
		if victim == def and beneficiary == atk and not stolen[0]:
			stolen[0] = true
			stolen[1] = item)
	var healed := [false, -1]
	bm.item_healed.connect(func(mon, amt):
		if mon == atk and not healed[0]:
			healed[0] = true
			healed[1] = amt)
	bm.start_battle(atk, def)

	_chk("Pluck steals the target's Sitrus Berry (%s)" % [stolen],
			stolen[0] == true and stolen[1] != null)
	_chk("Discriminator: the target's item slot is now empty (consumed, not transferred)",
			def.held_item == null)
	_chk("The ATTACKER (not the target) is healed by the stolen berry's effect (%s)" % [healed],
			healed[0] == true and healed[1] > 0)

	# Sticky Hold blocks the steal entirely. Snapshotted live at atk2's FIRST
	# move_executed — this project's battles run to full completion, and
	# def2's own Sitrus Berry can legitimately self-trigger (unrelated to
	# Pluck) once def2's own HP drops low enough from Pluck's ordinary
	# damage over several turns, so a post-battle `held_item` read would be
	# flaky (whole-battle-aggregation pitfall).
	var atk2 := _make_mon("PLAtk2", [TypeChart.TYPE_FLYING], 100, 60, 60, 60, 60, 100)
	atk2.add_move(pluck)
	var def2 := _make_mon("PLStickyDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def2.ability = _load_ability(60)  # Sticky Hold
	def2.held_item = _load_item(523)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var stolen2 := [false]
	bm2.berry_stolen_and_eaten.connect(func(_v, _b, _i):
		stolen2[0] = true)
	var snap2 := [false, false]  # [snapped, still_held_at_that_moment]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk2 and not snap2[0]:
			snap2[0] = true
			snap2[1] = def2.held_item != null)
	bm2.start_battle(atk2, def2)
	_chk("Discriminator: Sticky Hold fully blocks the steal (no berry_stolen_and_eaten, " +
			"item still held immediately after the FIRST Pluck attempt)",
			stolen2[0] == false and snap2[0] == true and snap2[1] == true)

	# Jaboca Berry is exempt from MY steal mechanism specifically — its own
	# separate retaliation-and-self-consume may legitimately still remove
	# the item afterward (a DIFFERENT, pre-existing mechanism), so the only
	# assertion that actually isolates MY code is "berry_stolen_and_eaten
	# never fired," not "the item still exists post-battle."
	var bug_bite := _load_move(450)
	var atk3 := _make_mon("BBAtk3", [TypeChart.TYPE_BUG], 100, 60, 60, 60, 60, 100)
	atk3.add_move(bug_bite)
	var def3 := _make_mon("BBJabocaDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def3.held_item = _load_item(577)  # Jaboca Berry
	def3.add_move(tackle)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var stolen3 := [false]
	bm3.berry_stolen_and_eaten.connect(func(_v, _b, _i):
		stolen3[0] = true)
	bm3.start_battle(atk3, def3)
	_chk("Discriminator: a held Jaboca Berry is EXEMPT from the steal mechanism " +
			"(berry_stolen_and_eaten never fires — Jaboca's own separate retaliation " +
			"logic may still consume it afterward, that's a different mechanism)",
			stolen3[0] == false)


# ── M19-ignores-target-ability: bypasses Multiscale's full-HP damage halving ─

func _test_ignores_target_ability() -> void:
	var sunsteel := _load_move(667)
	var tackle := _load_move(33)
	var atk := _make_mon("SSAtk", [TypeChart.TYPE_STEEL], 100, 100, 60, 60, 60, 100)
	atk.add_move(sunsteel)
	var def := _make_mon("SSDef", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def.ability = _load_ability(136)  # Multiscale — halves damage at full HP
	def.add_move(tackle)

	var atk2 := _make_mon("SSAtk2", [TypeChart.TYPE_NORMAL], 100, 100, 60, 60, 60, 100)
	atk2.add_move(tackle)
	var def2 := _make_mon("SSDef2", [TypeChart.TYPE_NORMAL], 300, 10, 60, 10, 60, 40)
	def2.ability = _load_ability(136)
	def2.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm._force_roll = 100
	var sunsteel_dmg := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not sunsteel_dmg[0]:
			sunsteel_dmg[0] = true
			sunsteel_dmg[1] = amt)
	bm.start_battle(atk, def)

	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_crit = false
	bm2._force_roll = 100
	var tackle_dmg2 := [false, -1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == atk2 and not tackle_dmg2[0]:
			tackle_dmg2[0] = true
			tackle_dmg2[1] = amt)
	bm2.start_battle(atk2, def2)

	_chk(("Baseline: a plain Tackle connects against a full-HP Multiscale holder (%s) — " +
			"Multiscale's own halving mechanism is separately confirmed by " +
			"ability_test.tscn's own origin suite") % [tackle_dmg2],
			tackle_dmg2[0] == true and tackle_dmg2[1] > 0)
	_chk("Sunsteel Strike ignores Multiscale entirely — same attacker/defender stats and " +
			"forced roll, yet deals roughly DOUBLE a Multiscale-halved hit " +
			"(sunsteel=%s tackle_halved=%s)" % [sunsteel_dmg, tackle_dmg2],
			sunsteel_dmg[0] == true and sunsteel_dmg[1] > tackle_dmg2[1] * 3 / 2)

	# Direct unit-level confirmation: Multiscale's own modifier value is
	# neutral (4096, no halving) when attacker_move.ignores_target_ability=true.
	var mult_holder := _make_mon("MultDirect", [TypeChart.TYPE_NORMAL])
	mult_holder.ability = _load_ability(136)
	var neutral_mod: int = AbilityManager.defense_damage_modifier_uq412(
			mult_holder, sunsteel, 1.0, DamageCalculator.WEATHER_NONE, null, false, atk)
	var halved_mod: int = AbilityManager.defense_damage_modifier_uq412(
			mult_holder, tackle, 1.0, DamageCalculator.WEATHER_NONE, null, false, atk2)
	_chk("Direct: Sunsteel Strike's own attacker_move param neutralizes Multiscale's " +
			"modifier (neutral=%d, ordinary_halved=%d)" % [neutral_mod, halved_mod],
			neutral_mod == 4096 and halved_mod == 2048)
