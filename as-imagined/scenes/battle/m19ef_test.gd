extends Node

# [M19e] Weather-conditional heal family: Morning Sun(234), Synthesis(235),
# Moonlight(236), Shore Up(622).
# [M19f] Escape-prevention family: Spider Web(169), Mean Look(212),
# Block(335), Spirit Shackle(625), Jaw Lock(692) — resolves
# M19-trap-secondary's own gate (Spirit Shackle folded in per its own
# "should be folded into M19f once built" note), and completes M19f's own
# originally-scoped 4-status-move-family + Jaw Lock's bidirectional variant.
#
# Ground truth: reference/pokeemerald_expansion/src/battle_script_commands.c
# (Cmd_recoverbasedonsunlight L8622-8689; MOVE_EFFECT_PREVENT_ESCAPE
# L2518-2525), src/data/battle_scripts_1.s (BattleScript_EffectMeanLook
# L2100-2112), src/data/moves_info.h, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_weather_heal_amount()
	_test_weather_heal_full_battle()
	_test_escape_prevention_unit()
	_test_is_trapped_and_shed_shell()
	_test_mean_look_full_battle()
	_test_spirit_shackle_full_battle()
	_test_jaw_lock_full_battle()
	_test_switch_actually_blocked()
	_test_clear_volatiles_reciprocal()

	var total := _pass + _fail
	print("m19ef_test: %d/%d passed" % [_pass, total])
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


# ── Section A: data integrity (all 8 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var morning_sun := _load_move(234)
	_chk("234 Morning Sun: Normal/status/pp5, heals_based_on_weather, boost=SUN, quarter_branch",
			morning_sun.move_name == "Morning Sun" and morning_sun.type == TypeChart.TYPE_NORMAL
					and morning_sun.pp == 5 and morning_sun.heals_based_on_weather
					and morning_sun.weather_heal_boost_type == DamageCalculator.WEATHER_SUN
					and morning_sun.weather_heal_has_quarter_branch)
	var synthesis := _load_move(235)
	_chk("235 Synthesis: Grass/status/pp5, same weather-heal shape as Morning Sun",
			synthesis.type == TypeChart.TYPE_GRASS and synthesis.pp == 5
					and synthesis.heals_based_on_weather
					and synthesis.weather_heal_boost_type == DamageCalculator.WEATHER_SUN
					and synthesis.weather_heal_has_quarter_branch)
	var moonlight := _load_move(236)
	_chk("236 Moonlight: Fairy (GEN6+) /status/pp5, same weather-heal shape",
			moonlight.type == TypeChart.TYPE_FAIRY and moonlight.pp == 5
					and moonlight.heals_based_on_weather
					and moonlight.weather_heal_boost_type == DamageCalculator.WEATHER_SUN
					and moonlight.weather_heal_has_quarter_branch)
	var shore_up := _load_move(622)
	_chk("622 Shore Up: Ground/status/pp5 (GEN9), boost=SANDSTORM, NO quarter branch",
			shore_up.type == TypeChart.TYPE_GROUND and shore_up.pp == 5
					and shore_up.heals_based_on_weather
					and shore_up.weather_heal_boost_type == DamageCalculator.WEATHER_SANDSTORM
					and not shore_up.weather_heal_has_quarter_branch)

	var spider_web := _load_move(169)
	_chk("169 Spider Web: Bug/status/pp10, is_mean_look, bounceable, NOT ignores_protect",
			spider_web.type == TypeChart.TYPE_BUG and spider_web.pp == 10
					and spider_web.is_mean_look and spider_web.bounceable
					and not spider_web.ignores_protect)
	var mean_look := _load_move(212)
	_chk("212 Mean Look: Normal/status/pp5, is_mean_look, bounceable, ignores_protect=TRUE",
			mean_look.type == TypeChart.TYPE_NORMAL and mean_look.pp == 5
					and mean_look.is_mean_look and mean_look.bounceable
					and mean_look.ignores_protect)
	var block := _load_move(335)
	_chk("335 Block: Normal/status/pp5, is_mean_look, bounceable, ignores_protect=TRUE",
			block.type == TypeChart.TYPE_NORMAL and block.pp == 5
					and block.is_mean_look and block.bounceable and block.ignores_protect)
	var spirit_shackle := _load_move(625)
	_chk("625 Spirit Shackle: 80/100/10 Ghost physical, SE_PREVENT_ESCAPE @100%%",
			spirit_shackle.power == 80 and spirit_shackle.accuracy == 100
					and spirit_shackle.pp == 10 and spirit_shackle.type == TypeChart.TYPE_GHOST
					and spirit_shackle.category == 0
					and spirit_shackle.secondary_effect == MoveData.SE_PREVENT_ESCAPE
					and spirit_shackle.secondary_chance == 100)
	var jaw_lock := _load_move(692)
	_chk("692 Jaw Lock: 80/100/10 Dark physical, contact+biting, SE_TRAP_BOTH @0%% (guaranteed)",
			jaw_lock.power == 80 and jaw_lock.accuracy == 100 and jaw_lock.pp == 10
					and jaw_lock.type == TypeChart.TYPE_DARK and jaw_lock.category == 0
					and jaw_lock.makes_contact and jaw_lock.biting_move
					and jaw_lock.secondary_effect == MoveData.SE_TRAP_BOTH
					and jaw_lock.secondary_chance == 0)


# ── Section B: M19e — _weather_heal_amount direct unit tests ───────────────

func _test_weather_heal_amount() -> void:
	var morning_sun := _load_move(234)
	var shore_up := _load_move(622)
	var mon := _make_mon("WHMon", [TypeChart.TYPE_NORMAL], 300)
	# The HP stat formula adds +level+10 on top of base_hp (level 50, IV/EV=0
	# here) — max_hp is NOT base_hp directly, so expected values are computed
	# from the mon's own real max_hp rather than hardcoded against base_hp.
	var mhp: int = mon.max_hp
	var two_thirds: int = max(1, mhp * 2 / 3)
	var half: int = max(1, mhp / 2)
	var quarter: int = max(1, mhp / 4)

	# (i) Sun-based moves: sun=2/3, no-weather=1/2, other-weather(rain/sand/hail)=1/4.
	var bm_sun := _make_bm()
	bm_sun.weather = BattleManager.WEATHER_SUN
	bm_sun.weather_duration = 5
	_chk("B.01 Morning Sun in sun heals 2/3 max HP (%d*2/3=%d)" % [mhp, two_thirds],
			bm_sun._weather_heal_amount(mon, morning_sun, false) == two_thirds)

	var bm_none := _make_bm()
	_chk("B.02 Morning Sun with no weather heals 1/2 max HP (%d/2=%d)" % [mhp, half],
			bm_none._weather_heal_amount(mon, morning_sun, false) == half)

	var bm_rain := _make_bm()
	bm_rain.weather = BattleManager.WEATHER_RAIN
	bm_rain.weather_duration = 5
	_chk("B.03 Morning Sun in RAIN (not its own boost weather) heals 1/4 max HP (%d/4=%d)" % [mhp, quarter],
			bm_rain._weather_heal_amount(mon, morning_sun, false) == quarter)

	var bm_sand := _make_bm()
	bm_sand.weather = BattleManager.WEATHER_SANDSTORM
	bm_sand.weather_duration = 5
	_chk("B.04 Morning Sun in Sandstorm ALSO heals 1/4 (%d) — the 'other weather' branch " % [quarter] +
			"is not sun-specific",
			bm_sand._weather_heal_amount(mon, morning_sun, false) == quarter)

	# (ii) Strong Winds treated as "no weather" for the 3 sun-based moves (source:
	# healingWeather strips Strong Winds before the ANY check).
	var bm_sw := _make_bm()
	bm_sw.weather = DamageCalculator.WEATHER_STRONG_WINDS
	bm_sw.weather_duration = 5
	_chk("B.05 Morning Sun in Strong Winds heals 1/2 (%d), NOT 1/4 — Strong Winds is " % [half] +
			"treated as no-weather for this formula specifically",
			bm_sw._weather_heal_amount(mon, morning_sun, false) == half)

	# (iii) Utility Umbrella strips SUN/RAIN specifically (not sand/hail) for the 3
	# sun-based moves.
	var umbrella_mon := _make_mon("WHUmbrellaMon", [TypeChart.TYPE_NORMAL], 300)
	umbrella_mon.held_item = _load_item(513)  # Utility Umbrella
	_chk("B.06 Morning Sun + Utility Umbrella in SUN heals 1/2 (%d), not the boosted 2/3 " % [half] +
			"— Umbrella strips the sun boost",
			bm_sun._weather_heal_amount(umbrella_mon, morning_sun, false) == half)
	_chk("B.07 Morning Sun + Utility Umbrella in RAIN heals 1/2 (%d), not the reduced " % [half] +
			"1/4 — Umbrella also neutralizes rain's own reduction",
			bm_rain._weather_heal_amount(umbrella_mon, morning_sun, false) == half)
	_chk("B.08 discriminator: Morning Sun + Utility Umbrella in SANDSTORM still heals " +
			"1/4 (%d) — Umbrella does NOT strip sand/hail, only sun/rain" % [quarter],
			bm_sand._weather_heal_amount(umbrella_mon, morning_sun, false) == quarter)

	# (iv) Shore Up: sandstorm=2/3, else=1/2, NO 1/4 branch at all — a real
	# non-uniformity within this sub-group.
	_chk("B.09 Shore Up in Sandstorm heals 2/3 (%d)" % [two_thirds],
			bm_sand._weather_heal_amount(mon, shore_up, false) == two_thirds)
	_chk("B.10 Shore Up with no weather heals 1/2 (%d)" % [half],
			bm_none._weather_heal_amount(mon, shore_up, false) == half)
	_chk("B.11 discriminator: Shore Up in RAIN (NOT its own boost weather, and Shore Up " +
			"has no 1/4 branch at all) still heals the plain 1/2 (%d), unlike Morning " % [half] +
			"Sun's own 1/4 in the same weather",
			bm_rain._weather_heal_amount(mon, shore_up, false) == half)
	_chk("B.12 Shore Up + Utility Umbrella in Sandstorm is UNAFFECTED (still 2/3=%d) — " % [two_thirds] +
			"source's own Shore Up branch never references Umbrella at all",
			bm_sand._weather_heal_amount(umbrella_mon, shore_up, false) == two_thirds)


func _test_weather_heal_full_battle() -> void:
	var morning_sun := _load_move(234)
	var tackle := _load_move(33)
	var atk := _make_mon("WHFullAtk", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	atk.add_move(morning_sun)
	atk.current_hp = 50
	var def := _make_mon("WHFullDef", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm.weather = BattleManager.WEATHER_SUN
	bm.weather_duration = 5
	var healed := [false, -1]
	bm.drain_heal.connect(func(mon, amt):
		if mon == atk and not healed[0]:
			healed[0] = true
			healed[1] = amt)
	bm.start_battle(atk, def)
	var expected_heal: int = max(1, atk.max_hp * 2 / 3)
	_chk("C.01 Morning Sun heals the real dispatch path for 2/3 max HP in sun (%d*2/3=%d, %s)" \
			% [atk.max_hp, expected_heal, healed],
			healed[0] == true and healed[1] == expected_heal)

	# Discriminator: fails outright at full HP.
	var atk2 := _make_mon("WHFullAtk2", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
	atk2.add_move(morning_sun)
	var def2 := _make_mon("WHFullDef2", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	var failed := [false, ""]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and not failed[0]:
			failed[0] = true
			failed[1] = reason)
	bm2.start_battle(atk2, def2)
	_chk("C.02 Discriminator: at full HP, Morning Sun fails outright (%s)" % [failed],
			failed[0] == true and failed[1] == "already_full_hp")


# ── Section D: M19f — try_apply_escape_prevention direct unit tests ────────

func _test_escape_prevention_unit() -> void:
	var victim := _make_mon("EPVictim", [TypeChart.TYPE_NORMAL])
	var source := _make_mon("EPSource", [TypeChart.TYPE_NORMAL])
	_chk("D.01 first application succeeds",
			StatusManager.try_apply_escape_prevention(victim, source) == true)
	_chk("D.02 escape_prevented_by now points at the source",
			victim.escape_prevented_by == source)

	var other_source := _make_mon("EPOther", [TypeChart.TYPE_NORMAL])
	_chk("D.03 discriminator: already-trapped is a silent no-op (returns false, does " +
			"NOT overwrite the existing source)",
			StatusManager.try_apply_escape_prevention(victim, other_source) == false
					and victim.escape_prevented_by == source)


func _test_is_trapped_and_shed_shell() -> void:
	var trapped := _make_mon("ITTrapped", [TypeChart.TYPE_NORMAL])
	var source := _make_mon("ITSource", [TypeChart.TYPE_NORMAL])
	trapped.escape_prevented_by = source
	_chk("E.01 is_trapped() returns true for a mon with escape_prevented_by set",
			AbilityManager.is_trapped(trapped, [], false) == true)

	var not_trapped := _make_mon("ITNotTrapped", [TypeChart.TYPE_NORMAL])
	_chk("E.02 discriminator: is_trapped() returns false with no trap source at all",
			AbilityManager.is_trapped(not_trapped, [], false) == false)

	# Ghost-type gate covers escape_prevented_by too (the same blanket gate wrapped_by
	# already uses), even if the field happens to be set (relevant since Spirit
	# Shackle's own dispatch has no Ghost-type check, unlike the 3 status moves).
	var ghost_trapped := _make_mon("ITGhostTrapped", [TypeChart.TYPE_GHOST])
	ghost_trapped.escape_prevented_by = source
	_chk("E.03 a Ghost-type mon is exempt from is_trapped() even with " +
			"escape_prevented_by explicitly set",
			AbilityManager.is_trapped(ghost_trapped, [], false) == false)

	# Shed Shell bypasses trapping entirely at the _phase_move_selection call site
	# (ItemManager.holds_shed_shell, gated BEFORE is_trapped() is even consulted) —
	# a full-battle discriminator, since this exemption lives outside is_trapped()
	# itself.
	var tackle := _load_move(33)
	var trapper := _make_mon("SSTrapper", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper.add_move(_load_move(212))  # Mean Look
	var shed_shell_holder := _make_mon("SSHolder", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	shed_shell_holder.held_item = _load_item(490)  # Shed Shell
	shed_shell_holder.add_move(tackle)
	var bench := _make_mon("SSBench", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var switched_out := []
	var bm := _make_bm()
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back(p))
	var opp_party := BattleParty.new()
	opp_party.members = [shed_shell_holder, bench]
	opp_party.active_index = 0
	bm.queue_move(1, 0)          # turn 1: shed_shell_holder Tackles (trapper Mean Looks it)
	bm.queue_switch(1, 1)        # turn 2: shed_shell_holder tries to voluntarily switch
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)
	_chk("E.04 a Shed Shell holder switches freely even after being Mean Look'd " +
			"(bypasses trapping at the selection-time gate, regardless of source)",
			switched_out.any(func(p): return p == shed_shell_holder))


# ── Section F: M19f full-battle — Mean Look family ──────────────────────────

func _test_mean_look_full_battle() -> void:
	var mean_look := _load_move(212)
	var tackle := _load_move(33)

	# (i) Ordinary application.
	var atk := _make_mon("MLAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(mean_look)
	var def := _make_mon("MLDef", [TypeChart.TYPE_WATER], 200, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	var bm := _make_bm()
	var trapped := [false, null]
	bm.escape_prevented.connect(func(target, source):
		if target == def and not trapped[0]:
			trapped[0] = true
			trapped[1] = source)
	bm.start_battle(atk, def)
	_chk("F.01 Mean Look sets the target's escape_prevented_by via the real dispatch (%s)" % [trapped],
			trapped[0] == true and trapped[1] == atk)

	# (ii) Ghost-type immunity — a MOVE-SCRIPT-level check, confirmed via a
	# Normal-type Mean Look against a Ghost-type target (Normal is already 0x vs
	# Ghost on the type chart too, so this is consistent either way, but is_mean_look's
	# own explicit check is what actually fires here since Mean Look never reaches
	# the general type-immunity gate at all — it's a self-contained early return).
	var atk2 := _make_mon("MLGhostAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk2.add_move(mean_look)
	var ghost_def := _make_mon("MLGhostDef", [TypeChart.TYPE_GHOST], 200, 60, 60, 60, 60, 40)
	ghost_def.add_move(tackle)
	var bm2 := _make_bm()
	var failed2 := [false, ""]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == ghost_def and not failed2[0]:
			failed2[0] = true
			failed2[1] = reason)
	bm2.start_battle(atk2, ghost_def)
	_chk("F.02 Mean Look fails outright against a Ghost-type target (%s)" % [failed2],
			failed2[0] == true and failed2[1] == "ghost_immune")
	_chk("F.03 discriminator: the Ghost-type target's escape_prevented_by was never set",
			ghost_def.escape_prevented_by == null)

	# (iii) Spider Web against a Ghost-type target — the KEY discriminator this
	# sub-group's own doc comment flags: Bug-type is only NOT-VERY-EFFECTIVE
	# (0.5x) vs Ghost on the type chart (not a 0x immunity), so is_mean_look's
	# OWN explicit Ghost check is what blocks it, not the general type gate.
	var spider_web := _load_move(169)
	var atk3 := _make_mon("SWGhostAtk", [TypeChart.TYPE_BUG], 100, 60, 60, 60, 60, 100)
	atk3.add_move(spider_web)
	var ghost_def3 := _make_mon("SWGhostDef", [TypeChart.TYPE_GHOST], 200, 60, 60, 60, 60, 40)
	ghost_def3.add_move(tackle)
	var bm3 := _make_bm()
	var failed3 := [false, ""]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == ghost_def3 and not failed3[0]:
			failed3[0] = true
			failed3[1] = reason)
	bm3.start_battle(atk3, ghost_def3)
	_chk("F.04 Spider Web (Bug-type, only 0.5x vs Ghost — NOT a chart immunity) still " +
			"fails against a Ghost-type target via its own explicit Ghost check (%s)" % [failed3],
			failed3[0] == true and failed3[1] == "ghost_immune")

	# (iv) Already-trapped failure.
	var atk4 := _make_mon("MLAlreadyAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk4.add_move(mean_look)
	var def4 := _make_mon("MLAlreadyDef", [TypeChart.TYPE_WATER], 200, 60, 60, 60, 60, 40)
	def4.add_move(tackle)
	var other_source := _make_mon("MLOtherSource", [TypeChart.TYPE_NORMAL])
	def4.escape_prevented_by = other_source
	var bm4 := _make_bm()
	var failed4 := [false, ""]
	bm4.move_effect_failed.connect(func(mon, reason):
		if mon == def4 and not failed4[0]:
			failed4[0] = true
			failed4[1] = reason)
	bm4.start_battle(atk4, def4)
	_chk("F.05 Mean Look fails against an already-trapped target (%s)" % [failed4],
			failed4[0] == true and failed4[1] == "already_trapped")
	_chk("F.06 discriminator: the existing trap source is NOT overwritten",
			def4.escape_prevented_by == other_source)


func _test_spirit_shackle_full_battle() -> void:
	var spirit_shackle := _load_move(625)
	var tackle := _load_move(33)

	# (i) Ordinary application via a damaging hit.
	var atk := _make_mon("SSAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk.add_move(spirit_shackle)
	var def := _make_mon("SSDef", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	var trapped := [false, null]
	bm.escape_prevented.connect(func(target, source):
		if target == def and not trapped[0]:
			trapped[0] = true
			trapped[1] = source)
	var damaged := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not damaged[0]:
			damaged[0] = true
			damaged[1] = amt)
	bm.start_battle(atk, def)
	_chk("G.01 Spirit Shackle deals real damage AND sets escape_prevented_by (%s, %s)" % [damaged, trapped],
			damaged[0] == true and damaged[1] > 0 and trapped[0] == true and trapped[1] == atk)

	# (ii) KEY discriminator vs Mean Look family: Spirit Shackle has NO Ghost-type
	# immunity — it can trap a Ghost-type target (its own dispatch never checks
	# defender type at all for this purpose).
	var atk2 := _make_mon("SSGhostAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk2.add_move(spirit_shackle)
	var ghost_def := _make_mon("SSGhostDef", [TypeChart.TYPE_GHOST], 300, 60, 60, 60, 60, 40)
	ghost_def.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var trapped2 := [false]
	bm2.escape_prevented.connect(func(target, _source):
		if target == ghost_def:
			trapped2[0] = true)
	bm2.start_battle(atk2, ghost_def)
	_chk("G.02 discriminator: Spirit Shackle DOES trap a Ghost-type target, unlike " +
			"Mean Look/Block/Spider Web's own explicit Ghost immunity",
			trapped2[0] == true)


func _test_jaw_lock_full_battle() -> void:
	var jaw_lock := _load_move(692)
	var tackle := _load_move(33)

	# (i) Bidirectional application: BOTH the attacker and the defender end up
	# trapped from one hit.
	var atk := _make_mon("JLAtk", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk.add_move(jaw_lock)
	var def := _make_mon("JLDef", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	# Signal-snapshot discipline: this project's battles run to full completion,
	# and a low-Defense def taking repeated Jaw Lock hits over several turns
	# will eventually faint, at which point _clear_volatiles(def)'s own base
	# case (a battler's own departure clears its own escape_prevented_by)
	# would silently zero the very field J.02 checks — a fresh instance of the
	# whole-battle-aggregation pitfall. Snapshot both fields live, right after
	# the second (of exactly two) escape_prevented events fires on turn 1.
	var bm := _make_bm()
	bm._force_hit = true
	var events := []
	var snap := [null, null]  # [def.escape_prevented_by, atk.escape_prevented_by] at 2 events
	bm.escape_prevented.connect(func(target, source):
		events.push_back([target, source])
		if events.size() == 2:
			snap[0] = def.escape_prevented_by
			snap[1] = atk.escape_prevented_by)
	bm.start_battle(atk, def)
	var first_two := events.slice(0, 2)
	_chk("J.01 Jaw Lock traps BOTH the defender and the attacker from one hit (%s)" % [first_two],
			first_two.size() == 2
					and first_two.any(func(e): return e[0] == def and e[1] == atk)
					and first_two.any(func(e): return e[0] == atk and e[1] == def))
	_chk("J.02 both battlers' escape_prevented_by fields are set to EACH OTHER " +
			"(snapshotted live, not read post-battle)",
			snap[0] == atk and snap[1] == def)

	# (ii) Discriminator: if EITHER battler is already trapped by someone else,
	# the whole bidirectional application is skipped (source's all-or-nothing
	# guard — neither side's trap is set, not a partial application). Snapshotted
	# at atk2's own FIRST move_executed, same aggregation-avoidance reasoning
	# as above.
	var atk2 := _make_mon("JLAtk2", [TypeChart.TYPE_DARK], 100, 100, 60, 60, 60, 100)
	atk2.add_move(jaw_lock)
	var def2 := _make_mon("JLDef2", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	def2.add_move(tackle)
	var other_source := _make_mon("JLOtherSource", [TypeChart.TYPE_NORMAL])
	def2.escape_prevented_by = other_source  # defender already trapped by someone else
	var bm2 := _make_bm()
	bm2._force_hit = true
	var events2 := []
	bm2.escape_prevented.connect(func(target, source): events2.push_back([target, source]))
	var snap2 := [false, null, null]  # [snapped, atk2_field, def2_field]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk2 and not snap2[0]:
			snap2[0] = true
			snap2[1] = atk2.escape_prevented_by
			snap2[2] = def2.escape_prevented_by)
	bm2.start_battle(atk2, def2)
	_chk("J.03 discriminator: if the defender is already trapped by someone else, " +
			"Jaw Lock's bidirectional application is skipped entirely (no new events)",
			not events2.any(func(e): return e[0] == atk2))
	_chk("J.04 discriminator: the attacker itself is NOT trapped either — the guard " +
			"is all-or-nothing, not a partial one-sided fallback (snapshotted live: %s)" % [snap2],
			snap2[0] == true and snap2[1] == null)
	_chk("J.05 discriminator: the defender's PRE-EXISTING trap source is untouched " +
			"(snapshotted live)",
			snap2[0] == true and snap2[2] == other_source)


# ── Section H: the trap actually blocks a voluntary switch ─────────────────

func _test_switch_actually_blocked() -> void:
	var mean_look := _load_move(212)
	var tackle := _load_move(33)

	var trapper := _make_mon("HTrapper", [TypeChart.TYPE_NORMAL], 100, 60, 40, 60, 40, 100)
	trapper.add_move(mean_look)
	var trapped := _make_mon("HTrapped", [TypeChart.TYPE_WATER], 100, 60, 40, 60, 40, 50)
	trapped.add_move(tackle)
	var bench := _make_mon("HBench", [TypeChart.TYPE_WATER], 100, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var switched_out := []
	var moves_used := []
	var bm := _make_bm()
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back(p))
	bm.move_executed.connect(func(a, d, m, dmg): moves_used.push_back(a))

	var opp_party := BattleParty.new()
	opp_party.members = [trapped, bench]
	opp_party.active_index = 0

	bm.queue_move(1, 0)     # Turn 1: trapped uses Tackle (trapper Mean Looks it same turn).
	bm.queue_switch(1, 1)   # Turn 2: trapped tries to voluntarily switch to bench.
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)

	_chk("H.01 the Mean Look'd Pokémon never voluntarily switched out",
			not switched_out.any(func(p): return p == trapped))
	_chk("H.02 the blocked switch fell back to a move instead",
			moves_used.any(func(a): return a == trapped))


# ── Section I: reciprocal clear — the SOURCE leaving the field cures the trap ─

func _test_clear_volatiles_reciprocal() -> void:
	var source := _make_mon("I1Source", [TypeChart.TYPE_NORMAL])
	var victim := _make_mon("I1Victim", [TypeChart.TYPE_NORMAL])
	victim.escape_prevented_by = source
	var bm := _make_bm()
	bm._combatants = [victim, source]
	bm._clear_volatiles(source)  # the SOURCE leaves, not the victim
	_chk("I.01 the SOURCE battler leaving the field cures the VICTIM's escape prevention",
			victim.escape_prevented_by == null)

	# Discriminator: an unrelated third battler leaving does NOT cure it.
	var source2 := _make_mon("I2Source", [TypeChart.TYPE_NORMAL])
	var victim2 := _make_mon("I2Victim", [TypeChart.TYPE_NORMAL])
	var bystander2 := _make_mon("I2Bystander", [TypeChart.TYPE_NORMAL])
	victim2.escape_prevented_by = source2
	var bm2 := _make_bm()
	bm2._combatants = [victim2, source2, bystander2]
	bm2._clear_volatiles(bystander2)
	_chk("I.02 discriminator: an unrelated third battler leaving does NOT cure the trap",
			victim2.escape_prevented_by == source2)

	# The victim's OWN departure also clears its own field (base case, unrelated
	# to the reciprocal scan).
	var source3 := _make_mon("I3Source", [TypeChart.TYPE_NORMAL])
	var victim3 := _make_mon("I3Victim", [TypeChart.TYPE_NORMAL])
	victim3.escape_prevented_by = source3
	var bm3 := _make_bm()
	bm3._combatants = [victim3, source3]
	bm3._clear_volatiles(victim3)  # the VICTIM's own departure
	_chk("I.03 the victim's own departure clears its own escape_prevented_by",
			victim3.escape_prevented_by == null)
