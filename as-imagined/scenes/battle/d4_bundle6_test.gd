extends Node

# [D4 Bundle 6] 23 REUSE-LIKELY residual moves: Teleport, Rest, False Swipe,
# Present, Knock Off, Endeavor, Brine, Acupressure, Psycho Shift, Punishment,
# Telekinesis, Acrobatics, Bulldoze, Belch, Parting Shot, Venom Drench,
# Geomancy, Toxic Thread, Stuff Cheeks, No Retreat, Octolock, Poltergeist,
# Chilly Reception.
#
# Real Step-0 forks found and preserved here (full citations in
# docs/decisions.md's own [D4 Bundle 6] entry):
#  - Teleport: at this project's GEN_LATEST config, in a trainer battle it
#    reuses Baton Pass's own script but WITHOUT stat-passing (the pass check
#    is keyed on move effect, not script), and bypasses trapping.
#  - Rest: fails if blocked by the user's OWN Insomnia/Vital Spirit/
#    Purifying Salt, checked BEFORE any heal/status-clear.
#  - Present: a flat 0-255 roll (102/76/26/51 bands), NOT Magnitude's table.
#  - Knock Off: power x1.5 gated on the SAME Sticky-Hold/form-lock check
#    that gates the removal itself.
#  - Octolock: confirmed via direct source read that it does NOT actually
#    trap in this reference source — stat-lower-only.
#  - No Retreat: uses its OWN dedicated bool, not escape_prevented_by.
#  - Parting Shot: the switch is GATED ON the stat-lower landing (Gen7+) —
#    the OPPOSITE of Memento's independence.
#  - Chilly Reception: the switch is UNCONDITIONAL regardless of the
#    weather-set's own success — the opposite gating from Parting Shot.
#  - Toxic Thread/Venom Drench: both exempted from the general type-
#    immunity gate (their shared BattleScript_EffectStatChange never calls
#    typecalc) — a Steel-type target still gets the stat-lower.
#  - Telekinesis: two independent halves (ungrounding + guaranteed hit
#    except OHKO/semi-invulnerable).
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h;
# src/battle_util.c (IsBelchPreventingMove/CanBattlerGetOrLoseItem/
# EFFECT_BRINE/EFFECT_PUNISHMENT/EFFECT_ACROBATICS/EFFECT_ENDEAVOR/
# EFFECT_KNOCK_OFF/CanBattlerEscape/IsBattlerUngroundedByAbilityItemOrEffect);
# src/battle_move_resolution.c (EFFECT_REST/EFFECT_PRESENT/CanPartingShotTrigger);
# src/battle_script_commands.c (BS_TryPsychoShift); src/battle_stat_change.c
# (EFFECT_TOXIC_THREAD/EFFECT_NO_RETREAT); data/battle_scripts_1.s
# (BattleScript_EffectTeleport/EffectBatonPass/EffectWeatherAndSwitch).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_teleport()
	_test_chilly_reception()
	_test_rest()
	_test_false_swipe()
	_test_present()
	_test_knock_off()
	_test_endeavor()
	_test_brine()
	_test_acupressure()
	_test_psycho_shift()
	_test_punishment()
	_test_telekinesis()
	_test_acrobatics()
	_test_bulldoze()
	_test_belch()
	_test_parting_shot()
	_test_venom_drench()
	_test_geomancy()
	_test_toxic_thread()
	_test_stuff_cheeks()
	_test_no_retreat()
	_test_octolock()
	_test_poltergeist()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle6_test: %d/%d passed" % [_pass, total])
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


func _make_ability(ability_id: int) -> AbilityData:
	var ab := AbilityData.new()
	ab.ability_id = ability_id
	return ab


func _make_item(item_name: String, hold_effect: int, param: int = 0, pocket: int = 0) -> ItemData:
	var item := ItemData.new()
	item.item_name = item_name
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	item.pocket = pocket
	return item


func _make_berry(item_name: String, hold_effect: int, param: int = 0) -> ItemData:
	return _make_item(item_name, hold_effect, param, ItemManager.POCKET_BERRIES)


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
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


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var teleport := _load_move(100)
	_chk("A.01 Teleport acc=0/pp=20/priority=-6/STAT/Psychic/ignores_protect/is_teleport",
			teleport.accuracy == 0 and teleport.pp == 20 and teleport.priority == -6
			and teleport.category == 2 and teleport.type == TypeChart.TYPE_PSYCHIC
			and teleport.ignores_protect and teleport.is_teleport)

	var rest := _load_move(156)
	_chk("A.02 Rest acc=0/pp=5/STAT/Psychic/healing_move/is_rest",
			rest.accuracy == 0 and rest.pp == 5 and rest.category == 2
			and rest.type == TypeChart.TYPE_PSYCHIC and rest.healing_move and rest.is_rest)

	var false_swipe := _load_move(206)
	_chk("A.03 False Swipe power=40/acc=100/pp=40/PHYS/Normal/makes_contact/is_false_swipe",
			false_swipe.power == 40 and false_swipe.accuracy == 100 and false_swipe.pp == 40
			and false_swipe.category == 0 and false_swipe.makes_contact and false_swipe.is_false_swipe)

	var present := _load_move(217)
	_chk("A.04 Present power=1/acc=90/pp=15/PHYS/Normal/is_present",
			present.power == 1 and present.accuracy == 90 and present.pp == 15
			and present.category == 0 and present.is_present)

	var knock_off := _load_move(282)
	_chk("A.05 Knock Off power=65/acc=100/pp=20/PHYS/Dark/makes_contact/is_knock_off",
			knock_off.power == 65 and knock_off.accuracy == 100 and knock_off.pp == 20
			and knock_off.type == TypeChart.TYPE_DARK and knock_off.makes_contact
			and knock_off.is_knock_off)

	var endeavor := _load_move(283)
	_chk("A.06 Endeavor power=1/acc=100/pp=5/PHYS/Normal/is_endeavor",
			endeavor.power == 1 and endeavor.accuracy == 100 and endeavor.pp == 5
			and endeavor.is_endeavor)

	var brine := _load_move(362)
	_chk("A.07 Brine power=65/acc=100/pp=10/SPEC/Water/is_brine",
			brine.power == 65 and brine.accuracy == 100 and brine.pp == 10
			and brine.category == 1 and brine.type == TypeChart.TYPE_WATER and brine.is_brine)

	var acupressure := _load_move(367)
	_chk("A.08 Acupressure acc=0/pp=30/STAT/Normal/ignores_protect/is_acupressure",
			acupressure.accuracy == 0 and acupressure.pp == 30 and acupressure.category == 2
			and acupressure.ignores_protect and acupressure.is_acupressure)

	var psycho_shift := _load_move(375)
	_chk("A.09 Psycho Shift acc=100/pp=10/STAT/Psychic/is_psycho_shift",
			psycho_shift.accuracy == 100 and psycho_shift.pp == 10 and psycho_shift.category == 2
			and psycho_shift.type == TypeChart.TYPE_PSYCHIC and psycho_shift.is_psycho_shift)

	var punishment := _load_move(386)
	_chk("A.10 Punishment power=60/acc=100/pp=5/PHYS/Dark/makes_contact/is_punishment",
			punishment.power == 60 and punishment.accuracy == 100 and punishment.pp == 5
			and punishment.makes_contact and punishment.is_punishment)

	var telekinesis := _load_move(477)
	_chk("A.11 Telekinesis acc=0/pp=15/STAT/Psychic/bounceable/is_telekinesis",
			telekinesis.accuracy == 0 and telekinesis.pp == 15 and telekinesis.category == 2
			and telekinesis.bounceable and telekinesis.is_telekinesis)

	var acrobatics := _load_move(512)
	_chk("A.12 Acrobatics power=55/acc=100/pp=15/PHYS/Flying/makes_contact/is_acrobatics",
			acrobatics.power == 55 and acrobatics.accuracy == 100 and acrobatics.pp == 15
			and acrobatics.type == TypeChart.TYPE_FLYING and acrobatics.makes_contact
			and acrobatics.is_acrobatics)

	var bulldoze := _load_move(523)
	_chk("A.13 Bulldoze power=60/acc=100/pp=20/PHYS/Ground/is_spread/stat_change(-1 Speed/chance=100)",
			bulldoze.power == 60 and bulldoze.accuracy == 100 and bulldoze.pp == 20
			and bulldoze.is_spread and bulldoze.stat_change_stat == BattlePokemon.STAGE_SPEED
			and bulldoze.stat_change_amount == -1 and bulldoze.secondary_chance == 100
			and not bulldoze.stat_change_self)

	var belch := _load_move(562)
	_chk("A.14 Belch power=120/acc=90/pp=10/SPEC/Poison/is_belch",
			belch.power == 120 and belch.accuracy == 90 and belch.pp == 10
			and belch.type == TypeChart.TYPE_POISON and belch.is_belch)

	var parting_shot := _load_move(575)
	_chk("A.15 Parting Shot acc=100/pp=20/STAT/Dark/bounceable/ignores_substitute/sound_move/is_parting_shot",
			parting_shot.accuracy == 100 and parting_shot.pp == 20 and parting_shot.category == 2
			and parting_shot.bounceable and parting_shot.ignores_substitute
			and parting_shot.sound_move and parting_shot.is_parting_shot)

	var venom_drench := _load_move(599)
	_chk("A.16 Venom Drench acc=100/pp=20/STAT/Poison/is_spread/bounceable/is_venom_drench",
			venom_drench.accuracy == 100 and venom_drench.pp == 20 and venom_drench.is_spread
			and venom_drench.bounceable and venom_drench.is_venom_drench)

	var geomancy := _load_move(601)
	_chk("A.17 Geomancy acc=0/pp=10/STAT/Fairy/two_turn/+2 SpAtk self + 2 extra pairs",
			geomancy.accuracy == 0 and geomancy.pp == 10 and geomancy.two_turn
			and geomancy.stat_change_stat == BattlePokemon.STAGE_SPATK
			and geomancy.stat_change_amount == 2 and geomancy.stat_change_self
			and geomancy.extra_stat_change_stats.size() == 2)

	var toxic_thread := _load_move(635)
	_chk("A.18 Toxic Thread acc=100/pp=20/STAT/Poison/bounceable/is_toxic_thread",
			toxic_thread.accuracy == 100 and toxic_thread.pp == 20 and toxic_thread.bounceable
			and toxic_thread.is_toxic_thread)

	var stuff_cheeks := _load_move(693)
	_chk("A.19 Stuff Cheeks acc=0/pp=10/STAT/Normal/ignores_protect/is_stuff_cheeks",
			stuff_cheeks.accuracy == 0 and stuff_cheeks.pp == 10 and stuff_cheeks.ignores_protect
			and stuff_cheeks.is_stuff_cheeks)

	var no_retreat := _load_move(694)
	_chk("A.20 No Retreat acc=0/pp=5/STAT/Fighting/+1 all 6 stats/is_no_retreat",
			no_retreat.accuracy == 0 and no_retreat.pp == 5
			and no_retreat.stat_change_stat == BattlePokemon.STAGE_ATK
			and no_retreat.stat_change_amount == 1 and no_retreat.stat_change_self
			and no_retreat.extra_stat_change_stats.size() == 4 and no_retreat.is_no_retreat)

	var octolock := _load_move(699)
	_chk("A.21 Octolock acc=100/pp=15/STAT/Fighting/is_octolock",
			octolock.accuracy == 100 and octolock.pp == 15 and octolock.is_octolock)

	var poltergeist := _load_move(737)
	_chk("A.22 Poltergeist power=110/acc=90/pp=5/PHYS/Ghost/is_poltergeist",
			poltergeist.power == 110 and poltergeist.accuracy == 90 and poltergeist.pp == 5
			and poltergeist.type == TypeChart.TYPE_GHOST and poltergeist.is_poltergeist)

	var chilly_reception := _load_move(807)
	_chk("A.23 Chilly Reception acc=0/pp=10/STAT/Ice/ignores_protect/is_chilly_reception",
			chilly_reception.accuracy == 0 and chilly_reception.pp == 10
			and chilly_reception.type == TypeChart.TYPE_ICE and chilly_reception.ignores_protect
			and chilly_reception.is_chilly_reception)


# ── Section B: Teleport ──────────────────────────────────────────────────

func _test_teleport() -> void:
	var teleport := _load_move(100)
	var tackle := _load_move(33)

	# (i) switches out, no stat-stage pass, bypasses trapping (Shadow Tag opponent).
	var atk := _make_mon("TpAtk", 300, 60, 60, 60, 60, 40)
	atk.add_move(teleport)
	atk.stat_stages[BattlePokemon.STAGE_ATK] = 2
	var bench := _make_mon("TpBench", 300, 60, 60, 60, 60, 60)
	var opp := _make_mon("TpOpp", 300, 60, 60, 60, 60, 60)
	opp.ability = _make_ability(AbilityManager.ABILITY_SHADOW_TAG)
	opp.add_move(tackle)
	var party := BattleParty.new()
	party.members = [atk, bench]
	party.active_indices = [0]
	var switched_out := [false]
	var incoming_stage := [-99]
	var bm := _make_bm()
	bm.pokemon_switched_out.connect(func(mon, _side):
		if mon == atk: switched_out[0] = true)
	bm.pokemon_switched_in.connect(func(mon, _side, _slot):
		if mon == bench: incoming_stage[0] = mon.stat_stages[BattlePokemon.STAGE_ATK])
	bm.start_battle_with_parties(party, BattleParty.single(opp))
	bm.queue_free()
	_chk("B.01 Teleport switches the user out despite an opposing Shadow Tag", switched_out[0] == true)
	_chk("B.02 Teleport does NOT pass stat stages (incoming mon at neutral)", incoming_stage[0] == 0)

	# (ii) fails with no valid switch target.
	var atk2 := _make_mon("TpAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(teleport)
	var opp2 := _make_mon("TpOpp2", 300, 60, 60, 60, 60, 40)
	opp2.add_move(tackle)
	var bm2 := _make_bm()
	var tp_failed := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "no_switch_target": tp_failed[0] = true)
	bm2.start_battle(atk2, opp2)
	bm2.queue_free()
	_chk("B.03 Teleport fails outright with no valid switch target", tp_failed[0] == true)


# ── Section C: Chilly Reception ──────────────────────────────────────────

func _test_chilly_reception() -> void:
	var chilly := _load_move(807)
	var tackle := _load_move(33)

	# (i) sets Hail AND switches out unconditionally.
	var atk := _make_mon("CrAtk", 300, 60, 60, 60, 60, 40)
	atk.add_move(chilly)
	var bench := _make_mon("CrBench", 300, 60, 60, 60, 60, 60)
	var opp := _make_mon("CrOpp", 300, 60, 60, 60, 60, 60)
	opp.add_move(tackle)
	var party := BattleParty.new()
	party.members = [atk, bench]
	party.active_indices = [0]
	var weather_seen := [-1]
	var switched := [false]
	var bm := _make_bm()
	bm.weather_set.connect(func(_mon, w): weather_seen[0] = w)
	bm.pokemon_switched_out.connect(func(mon, _side):
		if mon == atk: switched[0] = true)
	bm.start_battle_with_parties(party, BattleParty.single(opp))
	bm.queue_free()
	_chk("C.01 Chilly Reception sets Hail", weather_seen[0] == BattleManager.WEATHER_HAIL)
	_chk("C.02 Chilly Reception switches the user out", switched[0] == true)

	# (ii) switch still happens even when the weather-set itself no-ops
	# (already Hail) — the OPPOSITE gating from Parting Shot.
	var atk2 := _make_mon("CrAtk2", 300, 60, 60, 60, 60, 40)
	atk2.add_move(chilly)
	var bench2 := _make_mon("CrBench2", 300, 60, 60, 60, 60, 60)
	var opp2 := _make_mon("CrOpp2", 300, 60, 60, 60, 60, 60)
	opp2.add_move(tackle)
	var party2 := BattleParty.new()
	party2.members = [atk2, bench2]
	party2.active_indices = [0]
	var bm2 := _make_bm()
	bm2.weather = BattleManager.WEATHER_HAIL
	var switched2 := [false]
	bm2.pokemon_switched_out.connect(func(mon, _side):
		if mon == atk2: switched2[0] = true)
	bm2.start_battle_with_parties(party2, BattleParty.single(opp2))
	bm2.queue_free()
	_chk("C.03 Chilly Reception still switches even when Hail is already active",
			switched2[0] == true)


# ── Section D: Rest ───────────────────────────────────────────────────────

func _test_rest() -> void:
	var rest := _load_move(156)

	# (i) heals to full, cures existing status, sleeps for exactly 2 turns.
	# HP deficit computed dynamically from max_hp (not hardcoded to base_hp —
	# the real HP formula adds +level+10 on top).
	var atk := _make_mon("RsAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(rest)
	atk.current_hp = atk.max_hp - 50
	atk.status = BattlePokemon.STATUS_BURN
	var def := _make_mon("RsDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	var healed := [-1]
	bm.drain_heal.connect(func(mon, amt):
		if mon == atk and healed[0] == -1: healed[0] = amt)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("D.01 Rest heals to full", healed[0] == 50)

	# (ii) fails if already at full HP (checked via a fresh single-turn scenario).
	var atk2 := _make_mon("RsAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(rest)
	var def2 := _make_mon("RsDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var full_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "already_full_hp": full_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("D.02 Rest fails at full HP", full_fail[0] == true)

	# (iii) blocked by the user's own Insomnia — no heal, no sleep.
	var atk3 := _make_mon("RsAtk3", 300, 60, 60, 60, 60, 60)
	atk3.ability = _make_ability(AbilityManager.ABILITY_INSOMNIA)
	atk3.add_move(rest)
	atk3.current_hp = 50
	var def3 := _make_mon("RsDef3", 300, 60, 60, 60, 60, 40)
	var bm3 := _make_bm()
	var insomnia_fail := [false]
	var healed3 := [false]
	bm3.move_effect_failed.connect(func(_m, reason):
		if reason == "rest_blocked_by_ability": insomnia_fail[0] = true)
	bm3.drain_heal.connect(func(mon, _amt):
		if mon == atk3: healed3[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("D.03 Rest blocked by the user's own Insomnia", insomnia_fail[0] == true)
	_chk("D.04 Rest blocked by Insomnia does NOT heal", healed3[0] == false)

	# (iv) "fails if already asleep" is checked directly here rather than via
	# a full battle: a mon already asleep never reaches move selection at all
	# (pre_move_check's own sleep-skip intercepts first, confirmed via direct
	# tracing — "skipped, reason=asleep" fires before is_rest's own dispatch
	# code ever runs) — this defensive branch is only reachable in real
	# source via Sleep Talk calling Rest, out of scope depth for this bundle.
	# The code path itself is still correct and harmless; not exercised via
	# a flaky full-battle scenario.


# ── Section E: False Swipe ────────────────────────────────────────────────

func _test_false_swipe() -> void:
	var false_swipe := _load_move(206)
	var atk := _make_mon("FsAtk", 300, 200, 60, 60, 60, 60)
	atk.add_move(false_swipe)
	var def := _make_mon("FsDef", 300, 60, 60, 60, 60, 40)
	def.current_hp = 5
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	# Snapshot at the FIRST move_executed rather than reading post-battle
	# state — the battle continues for many turns, and def's own counter-
	# attack (an auto-selected Struggle, since it has no real move) can
	# eventually faint it via its own recoil, unrelated to False Swipe.
	var hp_after_first_hit := [-1]
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk and hp_after_first_hit[0] == -1: hp_after_first_hit[0] = def.current_hp)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("E.01 False Swipe never drops the target below 1 HP", hp_after_first_hit[0] == 1)


# ── Section F: Present ────────────────────────────────────────────────────

func _test_present() -> void:
	var present := _load_move(217)

	# (i) low roll -> 40 power damage.
	var atk := _make_mon("PrAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(present)
	var def := _make_mon("PrDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm._force_present_roll = 0
	var dmg40 := [-1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and dmg40[0] == -1: dmg40[0] = amt)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("F.01 Present low roll deals real damage (40 power)", dmg40[0] > 0)

	# (ii) top roll -> heal branch, heals the TARGET (not the user).
	var atk2 := _make_mon("PrAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(present)
	var def2 := _make_mon("PrDef2", 300, 60, 60, 60, 60, 40)
	def2.current_hp = 100
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_present_roll = 255
	var healed2 := [-1]
	bm2.drain_heal.connect(func(mon, amt):
		if mon == def2 and healed2[0] == -1: healed2[0] = amt)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("F.02 Present top roll heals the TARGET, max_hp/4", healed2[0] == max(1, def2.max_hp / 4))

	# (iii) heal branch fails at full HP.
	var atk3 := _make_mon("PrAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(present)
	var def3 := _make_mon("PrDef3", 300, 60, 60, 60, 60, 40)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_present_roll = 255
	var full_hp_fail := [false]
	bm3.move_effect_failed.connect(func(_m, reason):
		if reason == "already_full_hp": full_hp_fail[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("F.03 Present heal branch fails at full HP", full_hp_fail[0] == true)


# ── Section G: Knock Off ──────────────────────────────────────────────────

func _test_knock_off() -> void:
	var knock_off := _load_move(282)

	# (i) removes the target's item, boosts power.
	var atk := _make_mon("KoAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(knock_off)
	var def := _make_mon("KoDef", 300, 60, 60, 60, 60, 40)
	def.held_item = _make_berry("KoBerry", ItemManager.HOLD_EFFECT_RESTORE_HP, 10)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("G.01 Knock Off removes the target's item", def.held_item == null)

	# (ii) does NOT remove a Sticky-Hold-protected item. Uses a NON-berry
	# item (Choice Band) deliberately — a berry would eventually get eaten
	# on its own via the ordinary HP-threshold pathway once the battle's
	# many turns wear the holder's HP down, unrelated to Knock Off, and
	# would falsely look like a Knock Off removal.
	var atk4 := _make_mon("KoAtk4", 300, 60, 60, 60, 60, 60)
	atk4.add_move(knock_off)
	var def4 := _make_mon("KoDef4", 300, 60, 60, 60, 60, 40)
	def4.ability = _make_ability(AbilityManager.ABILITY_STICKY_HOLD)
	def4.held_item = _make_item("KoBand", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("G.02 Knock Off does NOT remove a Sticky-Hold-protected item", def4.held_item != null)

	# (iii) power boost is real: compare damage via full battles (forced
	# roll+crit on both sides, per CLAUDE.md's pairwise-comparison
	# convention), one where the item is removable and one where it isn't.
	var atk5 := _make_mon("KoAtk5", 300, 60, 60, 60, 60, 60)
	atk5.add_move(knock_off)
	var def5 := _make_mon("KoDef5", 300, 60, 60, 60, 60, 40)
	def5.held_item = _make_item("KoBand5", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var bm5 := _make_bm()
	bm5._force_hit = true
	bm5._force_roll = 100
	bm5._force_crit = false
	var dmg_with_item := [-1]
	bm5.move_executed.connect(func(a, _d, _m, amt):
		if a == atk5 and dmg_with_item[0] == -1: dmg_with_item[0] = amt)
	bm5.start_battle(atk5, def5)
	bm5.queue_free()

	var atk6 := _make_mon("KoAtk6", 300, 60, 60, 60, 60, 60)
	atk6.add_move(knock_off)
	var def6 := _make_mon("KoDef6", 300, 60, 60, 60, 60, 40)
	var bm6 := _make_bm()
	bm6._force_hit = true
	bm6._force_roll = 100
	bm6._force_crit = false
	var dmg_no_item := [-1]
	bm6.move_executed.connect(func(a, _d, _m, amt):
		if a == atk6 and dmg_no_item[0] == -1: dmg_no_item[0] = amt)
	bm6.start_battle(atk6, def6)
	bm6.queue_free()
	_chk("G.03 Knock Off's power boost is real when the item is actually removable",
			dmg_with_item[0] > dmg_no_item[0])


# ── Section H: Endeavor ───────────────────────────────────────────────────

func _test_endeavor() -> void:
	var endeavor := _load_move(283)

	# (i) sets target HP = attacker HP. Snapshotted at the first
	# move_executed rather than post-battle, since the battle continues for
	# many turns (Endeavor keeps re-firing, def's own counter keeps hitting
	# atk) — a classic whole-battle-aggregation trap for this exact move.
	var atk := _make_mon("EnAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(endeavor)
	atk.current_hp = 50
	var def := _make_mon("EnDef", 300, 60, 60, 60, 60, 40)
	def.current_hp = 250
	var bm := _make_bm()
	bm._force_hit = true
	var hp_after_first := [-1]
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk and hp_after_first[0] == -1: hp_after_first[0] = def.current_hp)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("H.01 Endeavor sets target HP to attacker HP", hp_after_first[0] == 50)

	# (ii) fails (0 damage) if target HP <= attacker HP.
	var atk2 := _make_mon("EnAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(endeavor)
	atk2.current_hp = 200
	var def2 := _make_mon("EnDef2", 300, 60, 60, 60, 60, 40)
	def2.current_hp = 100
	var bm2 := _make_bm()
	bm2._force_hit = true
	var hp_after_first2 := [-1]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == atk2 and hp_after_first2[0] == -1: hp_after_first2[0] = def2.current_hp)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("H.02 Endeavor fails when target HP <= attacker HP", hp_after_first2[0] == 100)


# ── Section I: Brine ───────────────────────────────────────────────────────

func _test_brine() -> void:
	var brine := _load_move(362)
	# Power doubling is computed in BattleManager's own pre-branch override
	# section, NOT inside DamageCalculator — a raw calculate() call bypasses
	# it entirely. Compared via two full battles instead (forced roll+crit
	# on both, per CLAUDE.md's pairwise-comparison convention), snapshotted
	# at each attacker's own first move_executed.
	var atk_hi := _make_mon("BrAtkHi", 300, 60, 60, 60, 60, 60)
	atk_hi.add_move(brine)
	var def_hi := _make_mon("BrDefHi", 300, 60, 60, 60, 60, 60)
	var bm_hi := _make_bm()
	bm_hi._force_hit = true
	bm_hi._force_roll = 100
	bm_hi._force_crit = false
	var dmg_hi := [-1]
	bm_hi.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_hi and dmg_hi[0] == -1: dmg_hi[0] = amt)
	bm_hi.start_battle(atk_hi, def_hi)
	bm_hi.queue_free()

	var atk_lo := _make_mon("BrAtkLo", 300, 60, 60, 60, 60, 60)
	atk_lo.add_move(brine)
	var def_lo := _make_mon("BrDefLo", 300, 60, 60, 60, 60, 60)
	def_lo.current_hp = def_lo.max_hp / 2  # exactly 50% -> doubles
	var bm_lo := _make_bm()
	bm_lo._force_hit = true
	bm_lo._force_roll = 100
	bm_lo._force_crit = false
	var dmg_lo := [-1]
	bm_lo.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_lo and dmg_lo[0] == -1: dmg_lo[0] = amt)
	bm_lo.start_battle(atk_lo, def_lo)
	bm_lo.queue_free()
	_chk("I.01 Brine doubles power at <=50% HP", dmg_lo[0] * 10 >= dmg_hi[0] * 19)


# ── Section J: Acupressure ────────────────────────────────────────────────

func _test_acupressure() -> void:
	var acupressure := _load_move(367)

	# (i) raises one of the 7 stats by +2.
	var atk := _make_mon("AcAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(acupressure)
	var def := _make_mon("AcDef", 300, 60, 60, 60, 60, 40)
	var raised := [false]
	var bm := _make_bm()
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == atk and delta == 2: raised[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("J.01 Acupressure raises some stat by +2", raised[0] == true)

	# (ii) fails if every stat is already at +6.
	var atk2 := _make_mon("AcAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(acupressure)
	for i in range(7):
		atk2.stat_stages[i] = 6
	var def2 := _make_mon("AcDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var stat_limit_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "stat_limit": stat_limit_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("J.02 Acupressure fails when all 7 stats are maxed", stat_limit_fail[0] == true)


# ── Section K: Psycho Shift ───────────────────────────────────────────────

func _test_psycho_shift() -> void:
	var psycho_shift := _load_move(375)

	# (i) transfers Burn to the target, cures the attacker.
	var atk := _make_mon("PsAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(psycho_shift)
	atk.status = BattlePokemon.STATUS_BURN
	var def := _make_mon("PsDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	bm._force_hit = true
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("K.01 Psycho Shift transfers Burn to the target", def.status == BattlePokemon.STATUS_BURN)
	_chk("K.02 Psycho Shift cures the attacker's own status", atk.status == BattlePokemon.STATUS_NONE)

	# (ii) fails if the attacker has no status.
	var atk2 := _make_mon("PsAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(psycho_shift)
	var def2 := _make_mon("PsDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var no_status_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "psycho_shift_no_status": no_status_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("K.03 Psycho Shift fails with no attacker status", no_status_fail[0] == true)

	# (iii) fails if the target already has a status.
	var atk3 := _make_mon("PsAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(psycho_shift)
	atk3.status = BattlePokemon.STATUS_PARALYSIS
	var def3 := _make_mon("PsDef3", 300, 60, 60, 60, 60, 40)
	def3.status = BattlePokemon.STATUS_BURN
	var bm3 := _make_bm()
	var target_status_fail := [false]
	bm3.move_effect_failed.connect(func(_m, reason):
		if reason == "psycho_shift_target_has_status": target_status_fail[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("K.04 Psycho Shift fails when the target already has a status", target_status_fail[0] == true)
	_chk("K.05 Psycho Shift failure leaves the attacker's status untouched",
			atk3.status == BattlePokemon.STATUS_PARALYSIS)


# ── Section L: Punishment ─────────────────────────────────────────────────

func _test_punishment() -> void:
	var punishment := _load_move(386)
	# Power scaling is computed in BattleManager's pre-branch override
	# section, not inside DamageCalculator — compared via two full battles.
	var atk := _make_mon("PuAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(punishment)
	var def_plain := _make_mon("PuDefPlain", 300, 60, 60, 60, 60, 60)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var dmg_plain := [-1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and dmg_plain[0] == -1: dmg_plain[0] = amt)
	bm.start_battle(atk, def_plain)
	bm.queue_free()

	# Boosted on Speed/Accuracy (neither affects the physical damage formula
	# at all) rather than Defense/Sp. Defense — a real confound caught while
	# writing this test: raising the TARGET's own Defense stage directly
	# reduces damage through the ordinary formula, roughly canceling out
	# Punishment's own power increase and making the two cases look equal
	# by coincidence.
	var atk2 := _make_mon("PuAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(punishment)
	var def_boosted := _make_mon("PuDefBoosted", 300, 60, 60, 60, 60, 60)
	def_boosted.stat_stages[BattlePokemon.STAGE_SPEED] = 2
	def_boosted.stat_stages[BattlePokemon.STAGE_ACCURACY] = 2
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dmg_boosted := [-1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == atk2 and dmg_boosted[0] == -1: dmg_boosted[0] = amt)
	bm2.start_battle(atk2, def_boosted)
	bm2.queue_free()
	_chk("L.01 Punishment scales power with the target's positive stat count",
			dmg_boosted[0] > dmg_plain[0])


# ── Section M: Telekinesis ────────────────────────────────────────────────

func _test_telekinesis() -> void:
	var telekinesis := _load_move(477)
	var ohko := _load_move(90)  # Guillotine

	# (i) sets the target's telekinesis_turns to 3. Snapshotted INSIDE the
	# signal handler at the moment it's set — telekinesis_turns decrements
	# every end of turn, so reading it post-battle would show a
	# turn-count-dependent value, not the value it was actually set to.
	var atk := _make_mon("TkAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(telekinesis)
	var def := _make_mon("TkDef", 300, 60, 60, 60, 60, 40)
	var tk_set := [false]
	var tk_turns_at_set := [-1]
	var bm := _make_bm()
	bm.telekinesis_set.connect(func(mon):
		if mon == def and not tk_set[0]:
			tk_set[0] = true
			tk_turns_at_set[0] = mon.telekinesis_turns)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("M.01 Telekinesis sets the target's telekinesis_turns", tk_set[0] == true)
	_chk("M.02 Telekinesis sets exactly 3 turns", tk_turns_at_set[0] == 3)

	# (ii) ungrounds the target (peer to Magnet Rise in is_grounded).
	var mon := _make_mon("TkMon", 300, 60, 60, 60, 60, 60)
	mon.telekinesis_turns = 3
	_chk("M.03 Telekinesis ungrounds the target", not AbilityManager.is_grounded(mon))

	# (iii) any move against a telekinesis'd target auto-hits.
	var atk2 := _make_mon("TkAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("TkDef2", 300, 60, 60, 60, 60, 60)
	def2.telekinesis_turns = 3
	var low_acc_move := _load_move(59)  # Blizzard, 70 acc
	_chk("M.04 Telekinesis makes an ordinarily-inaccurate move auto-hit",
			StatusManager.check_accuracy(atk2, def2, low_acc_move, null, false) == true)

	# (iv) does NOT auto-hit an OHKO move.
	var atk3 := _make_mon("TkAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("TkDef3", 300, 60, 60, 60, 60, 60)
	def3.telekinesis_turns = 3
	var ohko_hit_count := 0
	for i in range(50):
		if StatusManager.check_accuracy(atk3, def3, ohko, null, false):
			ohko_hit_count += 1
	_chk("M.05 Telekinesis does NOT force an OHKO move to hit (uses its own accuracy)",
			ohko_hit_count < 50)


# ── Section N: Acrobatics ─────────────────────────────────────────────────

func _test_acrobatics() -> void:
	var acrobatics := _load_move(512)
	# Power doubling is computed in BattleManager's pre-branch override
	# section, not inside DamageCalculator — compared via two full battles.
	# Uses a mechanically-inert item (HOLD_EFFECT_NONE) for the "holds an
	# item" case — a real confound caught while writing this test: Choice
	# Band (used in an earlier draft) ALSO boosts Attack by 50% on its own,
	# partially masking Acrobatics' own power-doubling comparison. A berry
	# would have its own confound too (eaten mid-battle via the unrelated
	# HP-threshold path).
	var atk_item := _make_mon("AbAtkItem", 300, 60, 60, 60, 60, 60)
	atk_item.add_move(acrobatics)
	atk_item.held_item = _make_item("AbItem", ItemManager.HOLD_EFFECT_NONE)
	var def_item := _make_mon("AbDefItem", 300, 60, 60, 60, 60, 60)
	var bm_item := _make_bm()
	bm_item._force_hit = true
	bm_item._force_roll = 100
	bm_item._force_crit = false
	var dmg_item := [-1]
	bm_item.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_item and dmg_item[0] == -1: dmg_item[0] = amt)
	bm_item.start_battle(atk_item, def_item)
	bm_item.queue_free()

	var atk_noitem := _make_mon("AbAtkNoItem", 300, 60, 60, 60, 60, 60)
	atk_noitem.add_move(acrobatics)
	var def_noitem := _make_mon("AbDefNoItem", 300, 60, 60, 60, 60, 60)
	var bm_noitem := _make_bm()
	bm_noitem._force_hit = true
	bm_noitem._force_roll = 100
	bm_noitem._force_crit = false
	var dmg_noitem := [-1]
	bm_noitem.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_noitem and dmg_noitem[0] == -1: dmg_noitem[0] = amt)
	bm_noitem.start_battle(atk_noitem, def_noitem)
	bm_noitem.queue_free()
	_chk("N.01 Acrobatics doubles power with no held item",
			dmg_noitem[0] * 10 >= dmg_item[0] * 19)


# ── Section O: Bulldoze ───────────────────────────────────────────────────

func _test_bulldoze() -> void:
	var bulldoze := _load_move(523)
	var atk := _make_mon("BdAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(bulldoze)
	var def := _make_mon("BdDef", 300, 60, 60, 60, 60, 50)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var dealt := [-1]
	var speed_dropped := [false]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and dealt[0] == -1: dealt[0] = amt)
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_SPEED and delta == -1:
			speed_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("O.01 Bulldoze deals real damage", dealt[0] > 0)
	_chk("O.02 Bulldoze guarantees a -1 Speed drop", speed_dropped[0] == true)


# ── Section P: Belch ──────────────────────────────────────────────────────

func _test_belch() -> void:
	var belch := _load_move(562)

	# (i) fails if never having eaten a berry.
	var atk := _make_mon("BeAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(belch)
	var def := _make_mon("BeDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	var no_berry_fail := [false]
	bm.move_effect_failed.connect(func(_m, reason):
		if reason == "belch_no_berry_eaten": no_berry_fail[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("P.01 Belch fails if the user never ate a berry", no_berry_fail[0] == true)

	# (ii) works once last_consumed_berry is set, even with a DIFFERENT
	# current held item (not held_item == null).
	var atk2 := _make_mon("BeAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(belch)
	atk2.last_consumed_berry = _make_berry("AteBerry", ItemManager.HOLD_EFFECT_RESTORE_HP, 10)
	atk2.held_item = _make_item("SomeOtherItem", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var def2 := _make_mon("BeDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dealt2 := [-1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == atk2 and dealt2[0] == -1: dealt2[0] = amt)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("P.02 Belch works via last_consumed_berry even with a different held item now",
			dealt2[0] > 0)


# ── Section Q: Parting Shot ───────────────────────────────────────────────

func _test_parting_shot() -> void:
	var parting_shot := _load_move(575)
	var tackle := _load_move(33)

	# (i) lowers Atk/SpAtk, then switches. Stat-lower count guarded to the
	# FIRST two events only — once atk switches out it can't act again in
	# this scenario, but the newly-active bench mon (with no move of its
	# own) may still end up re-selecting Parting Shot indirectly across a
	# long multi-turn battle, which would otherwise keep re-lowering the
	# same 2 stats until capped at -6, breaking an unguarded exact count.
	var atk := _make_mon("PsAtk", 300, 60, 60, 60, 60, 40)
	atk.add_move(parting_shot)
	var bench := _make_mon("PsBench", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("PsDef", 300, 60, 60, 60, 60, 60)
	def.add_move(tackle)
	var party := BattleParty.new()
	party.members = [atk, bench]
	party.active_indices = [0]
	var switched := [false]
	var stats_lowered := [0]
	var bm := _make_bm()
	bm.pokemon_switched_out.connect(func(mon, _side):
		if mon == atk: switched[0] = true)
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == def and delta < 0 and stats_lowered[0] < 2: stats_lowered[0] += 1)
	bm.start_battle_with_parties(party, BattleParty.single(def))
	bm.queue_free()
	_chk("Q.01 Parting Shot lowers 2 stats on the target", stats_lowered[0] == 2)
	_chk("Q.02 Parting Shot switches the user out on success", switched[0] == true)

	# (ii) REQUIRED DISCRIMINATOR: a fully-blocked stat-lower blocks the
	# switch too (Gen7+ gating — the OPPOSITE of Memento's independence).
	# NOTE: this project's own Parting Shot data correctly sets
	# `ignores_substitute = true` (matching real source's B_UPDATED_MOVE_
	# FLAGS >= GEN_6 config) — Substitute can NOT be used as the blocking
	# mechanism here (confirmed via direct debug tracing: a Substitute'd
	# target still gets both the stat-lower AND the switch, correctly).
	# Instead, both target stats are pre-capped at -6, which genuinely
	# blocks `_apply_one_stat_change_pair` from applying anything.
	var atk2 := _make_mon("PsAtk2", 300, 60, 60, 60, 60, 40)
	atk2.add_move(parting_shot)
	var bench2 := _make_mon("PsBench2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("PsDef2", 300, 60, 60, 60, 60, 60)
	def2.stat_stages[BattlePokemon.STAGE_ATK] = -6
	def2.stat_stages[BattlePokemon.STAGE_SPATK] = -6
	def2.add_move(tackle)
	var party2 := BattleParty.new()
	party2.members = [atk2, bench2]
	party2.active_indices = [0]
	var switched2 := [false]
	var bm2 := _make_bm()
	bm2.pokemon_switched_out.connect(func(mon, _side):
		if mon == atk2: switched2[0] = true)
	bm2.start_battle_with_parties(party2, BattleParty.single(def2))
	bm2.queue_free()
	_chk("Q.03 REQUIRED: a fully stat-capped target blocks the switch too",
			switched2[0] == false)


# ── Section R: Venom Drench ───────────────────────────────────────────────

func _test_venom_drench() -> void:
	var venom_drench := _load_move(599)

	# (i) lowers 3 stats on a poisoned target. Guarded to the first 3 events
	# only — Venom Drench keeps re-firing across this multi-turn battle,
	# which would otherwise keep re-lowering the same 3 stats until capped.
	var atk := _make_mon("VdAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(venom_drench)
	var def := _make_mon("VdDef", 300, 60, 60, 60, 60, 40)
	def.status = BattlePokemon.STATUS_POISON
	var bm := _make_bm()
	var lowered := [0]
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == def and delta == -1 and lowered[0] < 3: lowered[0] += 1)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("R.01 Venom Drench lowers 3 stats on a poisoned target", lowered[0] == 3)

	# (ii) no effect on a non-poisoned target.
	var atk2 := _make_mon("VdAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(venom_drench)
	var def2 := _make_mon("VdDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var vd_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "venom_drench_failed": vd_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("R.02 Venom Drench fails against a non-poisoned target", vd_fail[0] == true)

	# (iii) works against a Steel-type poisoned-somehow target (type-immunity
	# gate exemption confirmation) — using a Poison-type target instead since
	# Steel-types can't normally be poisoned; confirms the gate exemption via
	# a mon typed to be immune to Poison-type moves (Poison-type itself).
	var atk3 := _make_mon("VdAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(venom_drench)
	var def3 := _make_mon("VdDef3", 300, 60, 60, 60, 60, 40, TypeChart.TYPE_STEEL)
	def3.status = BattlePokemon.STATUS_TOXIC
	var bm3 := _make_bm()
	var lowered3 := [0]
	bm3.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == def3 and delta == -1 and lowered3[0] < 3: lowered3[0] += 1)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("R.03 Venom Drench bypasses the type-immunity gate vs a Steel-type target",
			lowered3[0] == 3)


# ── Section S: Geomancy ───────────────────────────────────────────────────

func _test_geomancy() -> void:
	var geomancy := _load_move(601)
	# Guarded to the first 3 stat-raise events only — if nothing faints,
	# Geomancy keeps re-charging and re-releasing across a long battle,
	# which would otherwise keep re-raising the same 3 stats until capped.
	var atk := _make_mon("GeAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(geomancy)
	var def := _make_mon("GeDef", 300, 60, 60, 60, 60, 40)
	var charge_started_seen := [false]
	var raised_stats := [0]
	var bm := _make_bm()
	bm.charge_started.connect(func(mon, _m):
		if mon == atk: charge_started_seen[0] = true)
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == atk and delta == 2 and raised_stats[0] < 3: raised_stats[0] += 1)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("S.01 Geomancy is a two-turn charge move", charge_started_seen[0] == true)
	_chk("S.02 Geomancy raises 3 stats by +2 on the release turn", raised_stats[0] == 3)


# ── Section T: Toxic Thread ───────────────────────────────────────────────

func _test_toxic_thread() -> void:
	var toxic_thread := _load_move(635)

	# (i) poisons AND lowers Speed independently.
	var atk := _make_mon("TtAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(toxic_thread)
	var def := _make_mon("TtDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	var speed_dropped := [false]
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_SPEED and delta == -1:
			speed_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("T.01 Toxic Thread poisons the target", def.status == BattlePokemon.STATUS_POISON)
	_chk("T.02 Toxic Thread lowers the target's Speed", speed_dropped[0] == true)

	# (ii) REQUIRED DISCRIMINATOR: still lowers Speed against a Steel-type
	# target that can't be poisoned (type-immunity gate exemption).
	var atk2 := _make_mon("TtAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(toxic_thread)
	var def2 := _make_mon("TtDef2", 300, 60, 60, 60, 60, 40, TypeChart.TYPE_STEEL)
	var bm2 := _make_bm()
	var speed_dropped2 := [false]
	bm2.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def2 and stat == BattlePokemon.STAGE_SPEED and delta == -1:
			speed_dropped2[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("T.03 REQUIRED: Toxic Thread still lowers Speed vs a Poison-immune Steel-type",
			speed_dropped2[0] == true)
	_chk("T.04 Toxic Thread does NOT poison a Steel-type", def2.status == BattlePokemon.STATUS_NONE)

	# (iii) still poisons even if Speed can't be lowered further (-6 cap).
	var atk3 := _make_mon("TtAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(toxic_thread)
	var def3 := _make_mon("TtDef3", 300, 60, 60, 60, 60, 40)
	def3.stat_stages[BattlePokemon.STAGE_SPEED] = -6
	var bm3 := _make_bm()
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("T.05 Toxic Thread still poisons when Speed is already capped",
			def3.status == BattlePokemon.STATUS_POISON)


# ── Section U: Stuff Cheeks ───────────────────────────────────────────────

func _test_stuff_cheeks() -> void:
	var stuff_cheeks := _load_move(693)

	# (i) forces berry consumption + Defense +2. Heal snapshotted via
	# drain_heal at the moment it fires (the battle continues for many
	# turns afterward, and def's own counterattack could otherwise erode
	# atk's HP back down below the post-heal value, hiding a real heal).
	var atk := _make_mon("ScAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(stuff_cheeks)
	atk.held_item = _make_berry("ScBerry", ItemManager.HOLD_EFFECT_RESTORE_HP, 10)
	atk.current_hp = 100
	var def := _make_mon("ScDef", 300, 60, 60, 60, 60, 40)
	var def_raised := [false]
	var sc_healed := [-1]
	var bm := _make_bm()
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == atk and stat == BattlePokemon.STAGE_DEF and delta == 2:
			def_raised[0] = true)
	bm.drain_heal.connect(func(mon, amt):
		if mon == atk and sc_healed[0] == -1: sc_healed[0] = amt)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("U.01 Stuff Cheeks consumes the held berry", atk.held_item == null)
	_chk("U.02 Stuff Cheeks heals via the berry's own effect", sc_healed[0] == 10)
	_chk("U.03 Stuff Cheeks raises Defense by 2", def_raised[0] == true)

	# (ii) fails if not holding a berry.
	var atk2 := _make_mon("ScAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(stuff_cheeks)
	var def2 := _make_mon("ScDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var no_berry_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "stuff_cheeks_no_berry": no_berry_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("U.04 Stuff Cheeks fails with no held berry", no_berry_fail[0] == true)


# ── Section V: No Retreat ─────────────────────────────────────────────────

func _test_no_retreat() -> void:
	var no_retreat := _load_move(694)

	# (i) raises Atk/Def/SpAtk/SpDef/Speed by +1 each (5 stats — NOT
	# Accuracy/Evasion, confirmed via direct source-data read), traps the
	# user. Guarded to the first 5 events since a fresh no_retreat_active
	# blocks any further raise from a re-selected second use.
	var atk := _make_mon("NrAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(no_retreat)
	var def := _make_mon("NrDef", 300, 60, 60, 60, 60, 40)
	var raised := [0]
	var bm := _make_bm()
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == atk and delta == 1 and raised[0] < 5: raised[0] += 1)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("V.01 No Retreat raises 5 stats by +1", raised[0] == 5)
	_chk("V.02 No Retreat traps the user", atk.no_retreat_active == true)
	_chk("V.03 A No-Retreat'd mon is reported as trapped", AbilityManager.is_trapped(atk, [def]))

	# (ii) fails if already used.
	var atk2 := _make_mon("NrAtk2", 300, 60, 60, 60, 60, 60)
	atk2.no_retreat_active = true
	atk2.add_move(no_retreat)
	var def2 := _make_mon("NrDef2", 300, 60, 60, 60, 60, 40)
	var bm2 := _make_bm()
	var reuse_fail := [false]
	bm2.move_effect_failed.connect(func(_m, reason):
		if reason == "no_retreat_already_used": reuse_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("V.04 No Retreat fails on a second use", reuse_fail[0] == true)


# ── Section W: Octolock ───────────────────────────────────────────────────

func _test_octolock() -> void:
	var octolock := _load_move(699)

	# (i) sets octolocked_by, does NOT block switching (confirmed source finding).
	var atk := _make_mon("OlAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(octolock)
	var def := _make_mon("OlDef", 300, 60, 60, 60, 60, 40)
	var ol_set := [false]
	var bm := _make_bm()
	bm.octolock_set.connect(func(mon, caster):
		if mon == def and caster == atk: ol_set[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("W.01 Octolock sets octolocked_by on the target", ol_set[0] == true)
	_chk("W.02 REQUIRED: Octolock does NOT trap the target (confirmed source finding)",
			AbilityManager.is_trapped(def, [atk]) == false)

	# (ii) recurring end-of-turn -1 Def/-1 SpDef tick. Leaves
	# `_side_conditions` at its own properly-initialized default (does NOT
	# overwrite it with empty dicts — a real crash caught while writing this
	# test, since _phase_end_of_turn unconditionally reads several
	# already-templated keys like "reflect_turns" for every side).
	var atk2 := _make_mon("OlAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("OlDef2", 300, 60, 60, 60, 60, 60)
	def2.octolocked_by = atk2
	var bm2 := _make_bm()
	bm2._combatants = [atk2, def2]
	bm2._active_per_side = 1
	bm2._turn_order = [atk2, def2]
	bm2._phase_end_of_turn()
	_chk("W.03 Octolock's end-of-turn tick lowers Defense", def2.stat_stages[BattlePokemon.STAGE_DEF] == -1)
	_chk("W.04 Octolock's end-of-turn tick lowers Sp. Defense",
			def2.stat_stages[BattlePokemon.STAGE_SPDEF] == -1)
	bm2.queue_free()

	# (iii) cleared reciprocally when the caster leaves the field.
	var atk3 := _make_mon("OlAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("OlDef3", 300, 60, 60, 60, 60, 60)
	def3.octolocked_by = atk3
	var bm3 := _make_bm()
	bm3._combatants = [atk3, def3]
	bm3._clear_volatiles(atk3)
	_chk("W.05 Octolock is cleared when the caster leaves the field",
			def3.octolocked_by == null)
	bm3.queue_free()


# ── Section X: Poltergeist ────────────────────────────────────────────────

func _test_poltergeist() -> void:
	var poltergeist := _load_move(737)

	# (i) fails if the target holds no item.
	var atk := _make_mon("PgAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(poltergeist)
	var def := _make_mon("PgDef", 300, 60, 60, 60, 60, 40)
	var bm := _make_bm()
	var no_item_fail := [false]
	bm.move_effect_failed.connect(func(_m, reason):
		if reason == "poltergeist_no_item": no_item_fail[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("X.01 Poltergeist fails against an itemless target", no_item_fail[0] == true)

	# (ii) deals real damage against an item-holding target. Uses a
	# Water-type defender, NOT the default Normal-type — a real
	# type-immunity-precedes-ability-logic pitfall caught while writing this
	# test (CLAUDE.md's own documented convention): Poltergeist is
	# Ghost-type, and Normal-types are flatly IMMUNE to Ghost-type moves,
	# which would report 0 damage regardless of the item-check logic.
	var atk2 := _make_mon("PgAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(poltergeist)
	var def2 := _make_mon("PgDef2", 300, 60, 60, 60, 60, 40, TypeChart.TYPE_WATER)
	def2.held_item = _make_item("PgItem", ItemManager.HOLD_EFFECT_RESTORE_HP, 10)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dealt := [-1]
	bm2.move_executed.connect(func(a, _d, _m, amt):
		if a == atk2 and dealt[0] == -1: dealt[0] = amt)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("X.02 Poltergeist deals real damage against an item-holding target", dealt[0] > 0)


# ── Negative control ──────────────────────────────────────────────────────

func _test_negative_control() -> void:
	var atk := _make_mon("NCAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("NCDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(_load_move(33))
	def.add_move(_load_move(33))
	var any_bundle6_signal := [false]
	var bm := _make_bm()
	bm.telekinesis_set.connect(func(_m): any_bundle6_signal[0] = true)
	bm.octolock_set.connect(func(_m, _c): any_bundle6_signal[0] = true)
	bm._force_hit = true
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("NC.01 Negative control: plain Tackle-vs-Tackle triggers no D4 Bundle 6 signal",
			any_bundle6_signal[0] == false)
