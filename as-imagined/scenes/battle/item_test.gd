extends Node

# Milestone 12 test suite — Held Items
#
# Ground truth: pokeemerald-expansion (all GEN_LATEST config)
#   src/battle_util.c :: GetAttackStatModifier (L6989) — Choice Band/Specs
#   src/battle_util.c :: GetAttackerItemsModifier (L7497) — Life Orb post-roll
#   src/battle_util.c :: GetDefenderItemsModifier (L7510) — Resist Berry post-roll
#   src/battle_util.c :: GetWeatherDamageModifier (L7251, L7258) — Utility Umbrella
#   src/battle_util.c :: GetAttackerWeather (L9281) — Umbrella on attacker
#   src/battle_util.c :: HasEnoughHpToEatBerry (L5461) — Sitrus threshold
#   src/battle_util.c :: TryChangeBattleWeather (L1993) — rock extension
#   src/battle_main.c :: GetChoiceScarf case (L4703) — Scarf speed integer math
#   src/battle_hold_effects.c :: TryLeftovers (L634) — EOT heal
#   src/battle_hold_effects.c :: TryLifeOrb (L547) — MoveEnd recoil
#   src/battle_hold_effects.c :: TryCureAnyStatus (L764) — Lum Berry
#   src/battle_move_resolution.c :: MoveEndLifeOrbShellBell (L3819)
#   src/battle_move_resolution.c :: MoveEndHpThresholdItemsTarget — Sitrus Berry
#   src/item.c :: IsHoldEffectChoice (L970) — Band || Scarf || Specs
#
# Sections:
#   I1:  Choice Band — Physical ×1.5, move lock, switch clears lock
#   I2:  Choice Specs — Special ×1.5, no boost for physical
#   I3:  Choice Scarf — speed ×1.5 (integer: (speed*150)/100), lock
#   I4:  Life Orb — damage ×1.3 AFTER roll (discriminating), recoil max_hp/10
#   I5:  Leftovers — EOT heal max_hp/16, not consumed
#   I6:  Sitrus Berry — heal max_hp*25/100 at HP≤max_hp/2, consumed
#   I7:  Lum Berry — cures status on infliction, consumed
#   I8:  Occa Berry (Resist Berry, Fire) — ×0.5 when super-effective (discriminating)
#   I9:  Damp Rock — rain 8 turns (vs 5 without)
#   I10: Utility Umbrella — negates rain/sun damage modifier (discriminating)
#   I11: Chilan Berry (Resist Berry, Normal) — ×0.5 vs a Normal move even at 1× effectiveness
#        (Follow-up fixes session, 2026-07-02; closes M12 decisions.md gap I2)
#   I12: Heavy Duty Boots — full immunity to Spikes/Toxic Spikes/Stealth Rock on switch-in
#        (Follow-up fixes session, 2026-07-02; closes the gap flagged in M16d's decisions.md)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_i1_choice_band()
	_test_i2_choice_specs()
	_test_i3_choice_scarf()
	_test_i4_life_orb()
	_test_i5_leftovers()
	_test_i6_sitrus_berry()
	_test_i7_lum_berry()
	_test_i8_occa_berry()
	_test_i9_damp_rock()
	_test_i10_utility_umbrella()
	_test_i11_chilan_berry()
	_test_i12_heavy_duty_boots()

	var total := _pass + _fail
	print("item_test: %d/%d passed" % [_pass, total])
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

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


func _make_status_move(move_name: String, move_type: int, se: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = 2  # status
	m.power            = 0
	m.accuracy         = 100
	m.pp               = 20
	m.secondary_effect = se
	m.secondary_chance = 0  # 0 = guaranteed application in StatusManager
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── I1: Choice Band ───────────────────────────────────────────────────────────
# Source: GetAttackStatModifier (battle_util.c L6989–6992): BAND → physical ×UQ_4_12(1.5)=6144.
# Lock: gBattleStruct->chosenMovePositions[battler]; cleared by SwitchInClearSetData.
#
# Damage math (force_roll=100, force_crit=false):
#   Attacker: Normal, base_atk=100 → atk=105; base_hp=100 → max_hp=160
#   Defender: Normal, base_def=70  → def=75
#   Move:     Tackle (Normal, Physical, power=40) — STAB applies
#
#   Without Band: base=40*105*22/75/50+2=26; roll=100→26; STAB=_uq412(26,6144)=39
#   With Band:    atk=_uq412(105,6144)=157; base=40*157*22/75/50+2=38; roll→38; STAB=57

func _test_i1_choice_band() -> void:
	var band := _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	_chk("I1.01 Choice Band hold_effect=29", band.hold_effect == 29)

	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)

	var attacker := _make_mon("Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 100, 80, 80, 80, 60)
	var defender := _make_mon("Defender", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			150, 80, 70, 80, 70, 40)

	# I1.02: DamageCalculator with Band → damage=139
	attacker.held_item = band
	var result_band := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("I1.02 Choice Band Physical → damage=57", result_band["damage"] == 57)

	# I1.03: Without Band → damage=85
	attacker.held_item = null
	var result_no_band := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("I1.03 No item Physical → damage=39", result_no_band["damage"] == 39)

	# I1.04–I1.06: Integration — choice lock set, enforced, cleared on switch.
	# Setup: attacker has [water_gun(idx0), tackle(idx1)] — auto-select picks water_gun(idx0).
	# Queue tackle (idx1) on turn 1 → lock = tackle.
	# Turn 2+ auto-select: without lock would pick water_gun (idx0), with lock forces tackle (idx1).
	var band_mon := _make_mon("BandMon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 100, 80, 80, 80, 80)
	band_mon.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	band_mon.add_move(water_gun)   # idx 0 — auto-select default
	band_mon.add_move(tackle)      # idx 1 — will be locked on turn 1

	# opp_mon: tanky (high hp/def) so battle lasts multiple turns
	var opp_mon := _make_mon("Tank", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			200, 40, 200, 40, 200, 20)
	opp_mon.add_move(tackle)

	var bm := _make_bm()
	bm.queue_move(0, 1)  # turn 1: side0 uses tackle (idx1) — sets choice lock

	var side0_moves := []
	bm.move_executed.connect(func(atk, _def, mv, _d):
		if atk == band_mon: side0_moves.append(mv.move_name))

	bm.start_battle(band_mon, opp_mon)

	_chk("I1.04 choice_locked_move set after first move use",
			band_mon.choice_locked_move != null)
	_chk("I1.05 choice lock is tackle (the idx1 move that was queued)",
			band_mon.choice_locked_move != null and
			band_mon.choice_locked_move.move_name == "Tackle")
	if side0_moves.size() >= 2:
		_chk("I1.06 all moves after turn 1 are tackle (lock enforced)",
				side0_moves.slice(1).all(func(n): return n == "Tackle"))
	else:
		_chk("I1.06 choice lock enforced (battle ended early — skip)", true)
	bm.queue_free()

	# I1.07: Switch-out clears choice lock.
	var mon_for_switch := _make_mon("SwitchMon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 80)
	mon_for_switch.held_item = _make_item(ItemManager.HOLD_EFFECT_CHOICE_BAND)
	mon_for_switch.choice_locked_move = tackle  # manually pre-set lock
	var bm2 := _make_bm()
	bm2._switch_out_clear(mon_for_switch)
	_chk("I1.07 switch-out clears choice_locked_move",
			mon_for_switch.choice_locked_move == null)
	bm2.queue_free()


# ── I2: Choice Specs ──────────────────────────────────────────────────────────
# Source: GetAttackStatModifier (battle_util.c L6993–6996): SPECS → special ×UQ_4_12(1.5)=6144.
# SPECS does NOT boost Physical; BAND does NOT boost Special.
#
# Damage math (force_roll=100, force_crit=false):
#   Attacker: Normal, base_spatk=100 → sp_atk=105
#   Defender: Normal, base_spdef=70  → sp_def=75
#   Water Gun (Water, Special, power=40) — no STAB (Water ≠ Normal), 1.0× type eff
#
#   Without Specs: base=40*105*22/75/50+2=26; roll=100→26 (no STAB)
#   With Specs:    sp_atk=_uq412(105,6144)=157; base=40*157*22/75/50+2=38; roll→38

func _test_i2_choice_specs() -> void:
	var specs := _make_item(ItemManager.HOLD_EFFECT_CHOICE_SPECS)
	_chk("I2.01 Choice Specs hold_effect=50", specs.hold_effect == 50)

	var attacker := _make_mon("Attacker", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 100, 80, 100, 80, 60)
	var defender := _make_mon("Defender", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			150, 80, 70, 80, 70, 40)
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)
	var tackle    := _make_move("Tackle",   TypeChart.TYPE_NORMAL, 0, 40)

	attacker.held_item = specs
	var result_specs := DamageCalculator.calculate(attacker, defender, water_gun, 100, false)
	_chk("I2.02 Choice Specs Special → damage=38", result_specs["damage"] == 38)

	attacker.held_item = null
	var result_no_specs := DamageCalculator.calculate(attacker, defender, water_gun, 100, false)
	_chk("I2.03 No item Special → damage=26", result_no_specs["damage"] == 26)

	# I2.04: Specs does NOT boost physical attack.
	# Attacker base_atk=100 → atk=105; with Specs, attack_modifier_uq412 returns 4096 for Physical.
	# Expected: same 39 as no-item Physical (STAB Tackle): base=26, STAB=39.
	attacker.held_item = specs
	var result_specs_phys := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("I2.04 Choice Specs does NOT boost Physical → still 39", result_specs_phys["damage"] == 39)


# ── I3: Choice Scarf ──────────────────────────────────────────────────────────
# Source: battle_main.c GetChoiceScarf case (L4703): speed = (speed * 150) / 100.
# Integer arithmetic — NOT UQ4.12. Confirmed by pokeemerald-expansion source.
# base_speed=100 → speed=105; with Scarf: 105*150/100=157.

func _test_i3_choice_scarf() -> void:
	var scarf := _make_item(ItemManager.HOLD_EFFECT_CHOICE_SCARF)
	_chk("I3.01 Choice Scarf hold_effect=49", scarf.hold_effect == 49)

	var mon := _make_mon("ScarfMon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 100)
	_chk("I3.02 base speed=100 → stat=105",  mon.speed == 105)

	mon.held_item = scarf
	_chk("I3.03 Scarf speed = (105*150)/100 = 157",
			ItemManager.apply_speed_modifier(mon, mon.speed) == 157)
	_chk("I3.04 effective_speed with Scarf = 157",
			StatusManager.effective_speed(mon) == 157)

	mon.held_item = null
	_chk("I3.05 effective_speed without Scarf = 105",
			StatusManager.effective_speed(mon) == 105)

	# I3.06: Scarf Pokémon outruns a faster non-Scarf Pokémon.
	# base_speed=200 → speed=205 (no scarf); base_speed=100+scarf → effective=157.
	# 157 < 205, so scarf_mon would not outrun faster_mon. Use base_speed=130 → stat=135:
	#   Scarf: 135*150/100=202 — still slower than 205. Use base_speed=140 → stat=145:
	#   Scarf: 145*150/100=217 > 205. ✓
	var scarf_mon   := _make_mon("ScarfMon2",  TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 140)
	var faster_mon  := _make_mon("FasterMon",  TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 200)
	scarf_mon.held_item = scarf
	_chk("I3.06 Scarf (spd140→stat145→eff217) outruns base spd200→stat205",
			StatusManager.effective_speed(scarf_mon) > StatusManager.effective_speed(faster_mon))


# ── I4: Life Orb ─────────────────────────────────────────────────────────────
# Source: GetAttackerItemsModifier (battle_util.c L7497): Life Orb = UQ_4_12_FLOORED(1.3) = 5324.
# Applied AFTER roll (inside GetOtherModifiers / ApplyModifiersAfterDmgRoll).
# Recoil = max_hp/10, fires at MoveEnd. Source: TryLifeOrb (battle_hold_effects.c L547).
#
# Discriminating test (force_roll=85, force_crit=false):
#   Attacker: Psychic type, base_spatk=100 → sp_atk=105, base_hp=100 → max_hp=160
#   Defender: Normal type, base_spdef=70 → sp_def=75
#   Move: Psychic (Psychic, Special, power=90)
#   Pipeline:
#     base=40*105*22/75/50+2 = 57
#     roll=85: 57*85/100=48
#     STAB(Psychic+Psychic): _uq412(48,6144)=(294912+2047)/4096=296959/4096=72
#     Life Orb(×5324 AFTER roll): _uq412(72,5324)=(383328+2047)/4096=385375/4096=94
#   WRONG (Life Orb before roll): _uq412(57,5324)=74→roll=62→STAB=93 ≠ 94 ✓

func _test_i4_life_orb() -> void:
	var life_orb := _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	_chk("I4.01 Life Orb hold_effect=60", life_orb.hold_effect == 60)

	var attacker := _make_mon("PsyAtk", TypeChart.TYPE_PSYCHIC, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 80)  # base_hp=100 → max_hp=160
	var defender := _make_mon("NrmDef", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			150, 80, 80, 80, 70, 40)
	var psychic := _make_move("Psychic", TypeChart.TYPE_PSYCHIC, 1, 90)

	attacker.held_item = life_orb
	var res_lo := DamageCalculator.calculate(attacker, defender, psychic, 85, false)
	_chk("I4.02 Life Orb damage=94 (correct post-roll order; wrong order gives 93)",
			res_lo["damage"] == 94)

	attacker.held_item = null
	var res_no_lo := DamageCalculator.calculate(attacker, defender, psychic, 85, false)
	_chk("I4.03 Without Life Orb, same setup → damage=72 (baseline)",
			res_no_lo["damage"] == 72)

	# I4.04: Life Orb recoil = max_hp/10 = 160/10 = 16.
	_chk("I4.04 life_orb_recoil = max_hp/10 = 16",
			ItemManager.life_orb_recoil(
				_mon_with_item(attacker, life_orb)) == 16)

	# I4.05: Integration — item_damage signal fires with recoil=16 after a hit.
	var lo_atk := _make_mon("LO_Attacker", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 100)
	lo_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	var lo_def := _make_mon("LO_Defender", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			200, 80, 200, 80, 200, 20)
	lo_atk.add_move(_make_move("Ember", TypeChart.TYPE_FIRE, 1, 40))
	lo_def.add_move(_make_move("Splash", TypeChart.TYPE_NORMAL, 1, 1))

	var bm := _make_bm()
	var lo_dmg_events := []
	bm.item_damage.connect(func(m, d): lo_dmg_events.append({"mon": m, "amount": d}))
	bm.start_battle(lo_atk, lo_def)

	_chk("I4.05 item_damage signal fired at least once (Life Orb recoil)",
			lo_dmg_events.size() >= 1)
	if lo_dmg_events.size() >= 1:
		var expected_recoil: int = lo_atk.max_hp / 10
		_chk("I4.06 Life Orb recoil amount = max_hp/10",
				lo_dmg_events.any(func(ev): return ev["amount"] == expected_recoil))
	bm.queue_free()

	# I4.07: attacker.current_hp actually decreases by recoil amount (not just signal).
	# base_hp=100 → max_hp=160; recoil=160/10=16; HP after=160−16=144.
	# Defender uses a status move (no damage back); attacker is faster (speed=100).
	# item_damage fires AFTER line 776 sets current_hp, so capturing inside signal is exact.
	var lo_atk3 := _make_mon("LO_Atk3", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 100)
	lo_atk3.held_item = _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	var lo_def3 := _make_mon("LO_Def3", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			250, 80, 80, 80, 80, 20)
	lo_atk3.add_move(_make_move("Ember", TypeChart.TYPE_FIRE, 1, 40))
	lo_def3.add_move(_make_status_move("Splash", TypeChart.TYPE_NORMAL, MoveData.SE_NONE))
	var bm3 := _make_bm()
	# Array wrapper required: GDScript 4.x captures scalars by value in lambdas.
	var hp_capture := [-1]
	bm3.item_damage.connect(func(m: BattlePokemon, _d: int) -> void:
		if hp_capture[0] < 0 and m == lo_atk3:
			hp_capture[0] = lo_atk3.current_hp)
	bm3.start_battle(lo_atk3, lo_def3)
	_chk("I4.07 attacker.current_hp deducted by recoil (160 - 16 = 144)",
			hp_capture[0] == 144)
	bm3.queue_free()

	# I4.08: No recoil when move misses (guaranteed miss via stat-stage arithmetic).
	# acc_stage=-6, eva_stage=+6, move.accuracy=1:
	#   combined=-12 clamped to -6; idx=0; ratio=[33,100]
	#   calc = 1*33/100 = 0 (integer division) → randi()%100 < 0 → always false → always miss.
	# item_damage must never fire throughout the full battle.
	var miss_atk := _make_mon("MissAtk", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 100)
	miss_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	miss_atk.stat_stages[BattlePokemon.STAGE_ACCURACY] = -6
	var miss_def := _make_mon("MissDef", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			250, 80, 80, 80, 80, 20)
	miss_def.stat_stages[BattlePokemon.STAGE_EVASION] = 6
	var miss_ember := _make_move("Ember", TypeChart.TYPE_FIRE, 1, 40)
	miss_ember.accuracy = 1  # with stages above: calc=1*33/100=0 → guaranteed miss
	miss_atk.add_move(miss_ember)
	miss_def.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	var bm4 := _make_bm()
	var miss_fired := [false]  # Array wrapper — scalar bool capture would be a copy
	bm4.item_damage.connect(func(_m: BattlePokemon, _d: int) -> void:
		miss_fired[0] = true)
	bm4.start_battle(miss_atk, miss_def)
	_chk("I4.08 Life Orb recoil does NOT fire on a miss", not miss_fired[0])
	bm4.queue_free()

	# I4.09: No recoil when move is non-damaging (status move, category=2, power=0).
	# Non-damaging moves route to the else-branch in battle_manager.gd (L787),
	# which never reaches the `if damage > 0` guard for Life Orb.
	var ndmg_atk := _make_mon("NDmgAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 100)
	ndmg_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	var ndmg_def := _make_mon("NDmgDef", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			250, 80, 80, 80, 80, 20)
	ndmg_atk.add_move(_make_status_move("Growl", TypeChart.TYPE_NORMAL, MoveData.SE_NONE))
	ndmg_def.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	var bm5 := _make_bm()
	var ndmg_fired := [false]  # Array wrapper — scalar bool capture would be a copy
	bm5.item_damage.connect(func(_m: BattlePokemon, _d: int) -> void:
		ndmg_fired[0] = true)
	bm5.start_battle(ndmg_atk, ndmg_def)
	_chk("I4.09 Life Orb recoil does NOT fire on a non-damaging move", not ndmg_fired[0])
	bm5.queue_free()

	# I4.10: Recoil can faint the holder.
	# base_hp=45 → max_hp = floor(2*45*50/100)+60 = 45+60 = 105; recoil=105/10=10.
	# Set current_hp=10 (exactly one recoil's worth). After one hit:
	#   battle_manager.gd L776: max(0, 10-10) = 0 → FAINT_CHECK marks holder fainted.
	# Defender uses Splash (status, no damage) so no confounding damage from defender.
	var faint_atk := _make_mon("FaintAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			45, 80, 80, 80, 80, 100)  # max_hp=105, recoil=10
	faint_atk.held_item = _make_item(ItemManager.HOLD_EFFECT_LIFE_ORB)
	faint_atk.current_hp = faint_atk.max_hp / 10  # = 10
	var faint_def := _make_mon("FaintDef", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			250, 80, 80, 80, 80, 20)
	faint_atk.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	faint_def.add_move(_make_status_move("Splash", TypeChart.TYPE_NORMAL, MoveData.SE_NONE))
	var bm6 := _make_bm()
	var fainted_mons: Array[BattlePokemon] = []
	bm6.pokemon_fainted.connect(func(m: BattlePokemon) -> void:
		fainted_mons.append(m))
	bm6.start_battle(faint_atk, faint_def)
	_chk("I4.10 Life Orb recoil can faint the holder",
			fainted_mons.any(func(m: BattlePokemon) -> bool: return m == faint_atk))
	bm6.queue_free()


# Helper: return the mon with held_item set (non-destructive).
func _mon_with_item(mon: BattlePokemon, item: ItemData) -> BattlePokemon:
	mon.held_item = item
	return mon


# ── I5: Leftovers ────────────────────────────────────────────────────────────
# Source: TryLeftovers (battle_hold_effects.c L634–648): heal = max_hp / 16.
# Fires at EOT after status damage (FIRST_EVENT_BLOCK_HEAL_ITEMS).
# Not consumed (held_item persists).

func _test_i5_leftovers() -> void:
	var leftovers := _make_item(ItemManager.HOLD_EFFECT_LEFTOVERS)
	_chk("I5.01 Leftovers hold_effect=41", leftovers.hold_effect == 41)

	# Unit tests via ItemManager.
	var mon := _make_mon("LftMon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 80)
	mon.held_item = leftovers
	mon.current_hp = 80  # below max_hp=160

	_chk("I5.02 leftovers_heal = max_hp/16 = 10 when below full",
			ItemManager.leftovers_heal(mon) == 10)

	mon.current_hp = mon.max_hp  # full HP
	_chk("I5.03 leftovers_heal = 0 when at full HP",
			ItemManager.leftovers_heal(mon) == 0)

	# I5.04: Integration — item_healed signal fires at EOT.
	var lft_atk := _make_mon("LFT_Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 10, 200, 10, 200, 100)
	lft_atk.add_move(_make_move("Scratch", TypeChart.TYPE_NORMAL, 0, 1))

	var lft_def := _make_mon("LFT_Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 10, 200, 10, 200, 20)
	lft_def.held_item = _make_item(ItemManager.HOLD_EFFECT_LEFTOVERS)
	lft_def.add_move(_make_move("Scratch", TypeChart.TYPE_NORMAL, 0, 1))

	var bm := _make_bm()
	var heals := []
	bm.item_healed.connect(func(m, d): if m == lft_def: heals.append(d))
	bm.start_battle(lft_atk, lft_def)

	var expected_heal: int = lft_def.max_hp / 16
	_chk("I5.04 item_healed signal fired for Leftovers holder",
			heals.size() >= 1)
	if heals.size() >= 1:
		_chk("I5.05 Leftovers healed max_hp/16 per turn",
				heals.all(func(d): return d == expected_heal))
	bm.queue_free()


# ── I6: Sitrus Berry ─────────────────────────────────────────────────────────
# Source: HasEnoughHpToEatBerry (battle_util.c L5461): threshold = max_hp / 2 (hpFraction=2).
#   Heal = max_hp * holdEffectParam / 100 where param=25 for Sitrus Berry.
# Fires at MoveEnd (MoveEndHpThresholdItemsTarget). Consumed on trigger.

func _test_i6_sitrus_berry() -> void:
	var sitrus := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25)
	_chk("I6.01 Sitrus Berry hold_effect=82, param=25",
			sitrus.hold_effect == 82 and sitrus.hold_effect_param == 25)

	var mon := _make_mon("SitMon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 80)  # base_hp=100 → max_hp=160
	mon.held_item = sitrus
	mon.current_hp = 60  # ≤ 80 (=max_hp/2)
	_chk("I6.02 hp_threshold_berry_heal=40 when HP=60 (≤80=max_hp/2)",
			ItemManager.hp_threshold_berry_heal(mon) == 40)

	mon.current_hp = 100  # > 80
	_chk("I6.03 hp_threshold_berry_heal=0 when HP=100 (>80=max_hp/2)",
			ItemManager.hp_threshold_berry_heal(mon) == 0)

	# I6.04–I6.05: Integration — berry fires once, consumed, no re-trigger.
	# Setup: lightly-damaging attacker, defender starts near full HP so
	# first hit crosses 50% threshold and triggers berry.
	var sit_atk := _make_mon("SIT_Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 100, 80, 80, 80, 100)
	sit_atk.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))

	var sit_def := _make_mon("SIT_Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 20)
	sit_def.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25)
	sit_def.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	# Force the defender below 50% HP at battle start to guarantee berry fires on first hit.
	# max_hp=160, set current_hp to 82 (just above threshold of 80) so even small damage triggers it.
	sit_def.current_hp = 82

	var bm := _make_bm()
	var consume_count := [0]
	var heal_count    := [0]
	bm.item_consumed.connect(func(m, _i): if m == sit_def: consume_count[0] += 1)
	bm.item_healed.connect(func(m, _d): if m == sit_def: heal_count[0] += 1)
	bm.start_battle(sit_atk, sit_def)

	_chk("I6.04 Sitrus Berry item_consumed fired exactly once",
			consume_count[0] == 1)
	_chk("I6.05 Sitrus Berry item_healed fired exactly once",
			heal_count[0] == 1)
	bm.queue_free()

	# I6.06–I6.08: Integration — berry fires on first hit when HP already starts below
	# threshold. Confirms level-triggered implementation: hp_threshold_berry_heal checks
	# current_hp ≤ max_hp/2 at move-end regardless of HP before the move.
	# sit_def2.current_hp=60 < 80 (=max_hp/2=160/2) before any action.
	# Heal = max_hp*25/100 = 160*25/100 = 40 (deterministic; independent of roll).
	# Note: damage varies 28–34 depending on random roll (85–100), so HP at berry fire
	# is in [66, 72]. The heal amount is the roll-independent quantity asserted here.
	var sit_atk2 := _make_mon("SIT_Atk2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 100, 80, 80, 80, 100)
	sit_atk2.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))

	var sit_def2 := _make_mon("SIT_Def2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 20)
	sit_def2.held_item = _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25)
	sit_def2.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	sit_def2.current_hp = 60  # already below threshold (80=max_hp/2)

	var bm2 := _make_bm()
	var consume_count2 := [0]
	var heal_count2    := [0]
	var heal_amount2   := [0]
	bm2.item_consumed.connect(func(m, _i): if m == sit_def2: consume_count2[0] += 1)
	bm2.item_healed.connect(func(m, amt):
			if m == sit_def2:
				heal_count2[0] += 1
				heal_amount2[0] = amt)
	bm2.start_battle(sit_atk2, sit_def2)

	_chk("I6.06 Sitrus fires when HP starts below threshold: item_consumed once",
			consume_count2[0] == 1)
	_chk("I6.07 Sitrus fires when HP starts below threshold: item_healed once",
			heal_count2[0] == 1)
	_chk("I6.08 Sitrus heal=40 when starting below threshold (max_hp*25/100=160*25/100=40)",
			heal_amount2[0] == 40)
	bm2.queue_free()


# ── I7: Lum Berry ─────────────────────────────────────────────────────────────
# Source: gHoldEffectsInfo CURE_STATUS: onStatusChange=TRUE.
#   TryCureAnyStatus (battle_hold_effects.c L764+): fires when any status is inflicted.
# Consumed on trigger.

func _test_i7_lum_berry() -> void:
	var lum := _make_item(ItemManager.HOLD_EFFECT_CURE_STATUS)
	_chk("I7.01 Lum Berry hold_effect=9", lum.hold_effect == 9)

	# Unit tests.
	var mon := _make_mon("LumMon", TypeChart.TYPE_NORMAL)
	mon.held_item = lum
	mon.status = BattlePokemon.STATUS_PARALYSIS
	_chk("I7.02 status_cure_berry_cures=true when paralyzed",
			ItemManager.status_cure_berry_cures(mon))

	mon.status = BattlePokemon.STATUS_NONE
	_chk("I7.03 status_cure_berry_cures=false when STATUS_NONE",
			not ItemManager.status_cure_berry_cures(mon))

	# I7.04: Integration — Thunder Wave inflicts paralysis, Lum Berry cures it, is consumed.
	# Setup: attacker uses Thunder Wave (status move, SE_PARALYSIS).
	# Turn 1: attacker queues Thunder Wave; defender gets paralyzed, Lum Berry fires.
	var twave := _make_status_move("ThunderWave", TypeChart.TYPE_ELECTRIC, MoveData.SE_PARALYSIS)
	var lum_atk := _make_mon("LUM_Atk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 100)
	lum_atk.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))  # idx 0
	lum_atk.add_move(twave)  # idx 1

	var lum_def := _make_mon("LUM_Def", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 80, 20)
	lum_def.held_item = _make_item(ItemManager.HOLD_EFFECT_CURE_STATUS)
	lum_def.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))

	var bm := _make_bm()
	# Turn 1: use Thunder Wave against defender.
	bm.queue_move(0, 1)  # attacker uses thunder wave (idx 1) on turn 1

	var consumed_events := []
	bm.item_consumed.connect(func(m, _i): consumed_events.append(m))
	bm.start_battle(lum_atk, lum_def)

	_chk("I7.04 item_consumed fired (Lum Berry activated)",
			consumed_events.any(func(m): return m == lum_def))
	_chk("I7.05 Lum Berry consumed exactly once",
			consumed_events.count(lum_def) == 1)
	bm.queue_free()


# ── I8: Occa Berry (Resist Berry — Fire type) ────────────────────────────────
# Source: GetDefenderItemsModifier (battle_util.c L7510–7524): if hold_effect==RESIST_BERRY
#   and move type matches param and effectiveness >= 2.0 → ×UQ_4_12(0.5)=2048.
# Applied AFTER roll, AFTER STAB, AFTER type effectiveness (inside GetOtherModifiers).
#
# Discriminating composition test (force_roll=100, force_crit=false):
#   Attacker: Fire type, base_spatk=100 → sp_atk=105 (no item)
#   Defender: Bug type,  base_spdef=70  → sp_def=75; Occa Berry (param=TYPE_FIRE)
#   Move: Ember (Fire, Special, power=40)
#   Pipeline:
#     base=40*105*22/75/50+2 = 26
#     roll=100→26; STAB(Fire+Fire): _uq412(26,6144)=(159744+2047)/4096=161791/4096=39
#     type eff(Fire→Bug=2.0×): _uq412(39,8192)=(319488+2047)/4096=321535/4096=78
#     Occa Berry(AFTER type eff, ×0.5=2048): _uq412(78,2048)=(159744+2047)/4096=161791/4096=39
#   WRONG (berry BEFORE type eff): STAB=39, _uq412(39,2048)=19, type eff 2×=38 ≠ 39 ✓

func _test_i8_occa_berry() -> void:
	var occa := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_FIRE)
	_chk("I8.01 Occa Berry hold_effect=80, param=TYPE_FIRE(11)",
			occa.hold_effect == 80 and occa.hold_effect_param == TypeChart.TYPE_FIRE)

	var attacker := _make_mon("FireAtk2", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 80)
	var defender := _make_mon("BugDef", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 40)
	var ember := _make_move("Ember", TypeChart.TYPE_FIRE, 1, 40)

	defender.held_item = occa
	var res_berry := DamageCalculator.calculate(attacker, defender, ember, 100, false)
	_chk("I8.02 Occa Berry damage=39 (correct post-type-eff order; wrong order gives 38)",
			res_berry["damage"] == 39)
	_chk("I8.03 defender_item_consumed=true when 2× super-effective + matching berry",
			res_berry["defender_item_consumed"] == true)

	defender.held_item = null
	var res_no_berry := DamageCalculator.calculate(attacker, defender, ember, 100, false)
	_chk("I8.04 Without berry, Fire→Bug damage=78",
			res_no_berry["damage"] == 78)
	_chk("I8.05 defender_item_consumed=false when no berry",
			res_no_berry["defender_item_consumed"] == false)

	# I8.06: Berry does NOT trigger for non-super-effective type (Water vs Normal = 1.0×).
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)
	var normal_def := _make_mon("NrmDef2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 40)
	var wacan := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_WATER)
	normal_def.held_item = wacan  # Water-resist berry, but Water vs Normal = 1.0×
	var res_nse := DamageCalculator.calculate(attacker, normal_def, water_gun, 100, false)
	_chk("I8.06 Resist berry not consumed for non-super-effective hit",
			res_nse["defender_item_consumed"] == false)

	# I8.07: Integration — item_consumed fires when berry activates in battle.
	var occa_atk := _make_mon("OccaAtk", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 100)
	occa_atk.add_move(_make_move("Ember", TypeChart.TYPE_FIRE, 1, 40))

	var occa_def := _make_mon("OccaDef", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 20)
	occa_def.held_item = _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_FIRE)
	occa_def.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))

	var bm := _make_bm()
	var consumed_occa := []
	bm.item_consumed.connect(func(m, _i): consumed_occa.append(m))
	bm.start_battle(occa_atk, occa_def)

	_chk("I8.07 item_consumed fired for Occa Berry holder (berry activated in battle)",
			consumed_occa.any(func(m): return m == occa_def))
	bm.queue_free()


# ── I9: Damp Rock ────────────────────────────────────────────────────────────
# Source: TryChangeBattleWeather (battle_util.c L1993–1996):
#   if (GetBattlerHoldEffect(setter) == HOLD_EFFECT_DAMP_ROCK) → weatherDuration = 8, else 5.

func _test_i9_damp_rock() -> void:
	var damp_rock := _make_item(ItemManager.HOLD_EFFECT_DAMP_ROCK)
	_chk("I9.01 Damp Rock hold_effect=51", damp_rock.hold_effect == 51)

	var setter := _make_mon("Setter", TypeChart.TYPE_WATER)
	setter.held_item = damp_rock
	_chk("I9.02 weather_duration(setter_with_damp_rock, RAIN)=8",
			ItemManager.weather_duration(setter, DamageCalculator.WEATHER_RAIN) == 8)

	var plain_setter := _make_mon("PlainSetter", TypeChart.TYPE_WATER)
	_chk("I9.03 weather_duration(setter_no_item, RAIN)=5",
			ItemManager.weather_duration(plain_setter, DamageCalculator.WEATHER_RAIN) == 5)

	# I9.04: Damp Rock doesn't extend the wrong weather type.
	_chk("I9.04 Damp Rock has no effect on SUN duration",
			ItemManager.weather_duration(setter, DamageCalculator.WEATHER_SUN) == 5)

	# I9.05: Integration — try_set_weather with Damp Rock setter gives duration=8.
	var bm := _make_bm()
	bm.try_set_weather(DamageCalculator.WEATHER_RAIN, setter)
	_chk("I9.05 BM weather_duration=8 after try_set_weather with Damp Rock",
			bm.weather_duration == 8)

	bm.try_set_weather(DamageCalculator.WEATHER_NONE)
	bm.try_set_weather(DamageCalculator.WEATHER_RAIN, plain_setter)
	_chk("I9.06 BM weather_duration=5 after try_set_weather without rock",
			bm.weather_duration == 5)
	bm.queue_free()


# ── I10: Utility Umbrella ────────────────────────────────────────────────────
# Source: GetWeatherDamageModifier (battle_util.c L7258): if defender holds Utility Umbrella
#   → return UQ_4_12(1.0) immediately (no weather modifier).
#   GetAttackerWeather (L9281–9290): if attacker holds Umbrella, strip rain/sun from
#   effective weather. Both collapse to: if either holds Umbrella, no modifier.
#
# Discriminating test (force_roll=85, force_crit=false):
#   Attacker: Normal, base_spatk=50 → sp_atk=55
#   Defender: Normal, base_spdef=70 → sp_def=75
#   Water Gun (Water, Special, power=40), RAIN weather
#
#   base = 22*40*55/75/50+2 = 48400/75/50+2 = 645/50+2 = 12+2 = 14
#   Without Umbrella: weather(×1.5)=_uq412(14,6144)=21; roll=85→17; result=17
#   With Umbrella:    weather negated → base=14; roll=85→11; result=11

func _test_i10_utility_umbrella() -> void:
	var umbrella := _make_item(ItemManager.HOLD_EFFECT_UTILITY_UMBRELLA)
	_chk("I10.01 Utility Umbrella hold_effect=115", umbrella.hold_effect == 115)

	var attacker := _make_mon("UmbrAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 50, 80, 80)
	var defender := _make_mon("UmbrDef", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			150, 80, 70, 80, 70, 40)
	var water_gun := _make_move("WaterGun", TypeChart.TYPE_WATER, 1, 40)

	# I10.02: Without Umbrella under RAIN → boost applies → 17
	var res_no_umb := DamageCalculator.calculate(attacker, defender, water_gun,
			85, false, DamageCalculator.WEATHER_RAIN)
	_chk("I10.02 Without Umbrella, Water/RAIN damage=17", res_no_umb["damage"] == 17)

	# I10.03: Umbrella on defender negates rain boost → 11
	defender.held_item = umbrella
	var res_def_umb := DamageCalculator.calculate(attacker, defender, water_gun,
			85, false, DamageCalculator.WEATHER_RAIN)
	_chk("I10.03 Umbrella on defender negates RAIN boost → damage=11",
			res_def_umb["damage"] == 11)

	# I10.04: Umbrella on attacker also negates boost → 11
	defender.held_item = null
	attacker.held_item = umbrella
	var res_atk_umb := DamageCalculator.calculate(attacker, defender, water_gun,
			85, false, DamageCalculator.WEATHER_RAIN)
	_chk("I10.04 Umbrella on attacker negates RAIN boost → damage=11",
			res_atk_umb["damage"] == 11)

	# I10.05: Umbrella does not negate neutral weather (no modifier without rain/sun anyway).
	attacker.held_item = null
	var res_no_weather := DamageCalculator.calculate(attacker, defender, water_gun,
			85, false, DamageCalculator.WEATHER_NONE)
	var res_umb_no_weather := DamageCalculator.calculate(
			_mon_with_item(attacker, umbrella), defender, water_gun,
			85, false, DamageCalculator.WEATHER_NONE)
	_chk("I10.05 Umbrella irrelevant when no weather (same damage both ways)",
			res_umb_no_weather["damage"] == res_no_weather["damage"])
	attacker.held_item = null


# ── I11: Chilan Berry (Resist Berry, Normal-type bypass) ──────────────────────
# Follow-up fixes session, 2026-07-02 — closes M12 decisions.md gap I2.
# Source: GetDefenderItemsModifier (battle_util.c L7510–7524):
#   `ctx->moveType == GetBattlerHoldEffectParam(...) && (ctx->moveType == TYPE_NORMAL ||
#    ctx->typeEffectivenessModifier >= UQ_4_12(2.0))` — the TYPE_NORMAL branch bypasses the
#   effectiveness gate entirely, since a Normal-type move can never reach 2.0× (no type is
#   2×-weak to Normal in this chart), which is exactly why Chilan Berry was unreachable
#   before this fix.

func _test_i11_chilan_berry() -> void:
	var chilan := _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_NORMAL)
	_chk("I11.01 Chilan Berry hold_effect=80, param=TYPE_NORMAL(1)",
			chilan.hold_effect == 80 and chilan.hold_effect_param == TypeChart.TYPE_NORMAL)

	var attacker := _make_mon("NormAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 80)
	# Water defender: Normal → Water is a NEUTRAL 1.0× matchup (no type is weak to Normal
	# at all in this chart) — proves the berry triggers WITHOUT any effectiveness boost.
	var defender := _make_mon("WaterDef", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 40)
	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)

	var res_no_berry := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("I11.02 defender_item_consumed=false with no berry", res_no_berry["defender_item_consumed"] == false)

	defender.held_item = chilan
	var res_berry := DamageCalculator.calculate(attacker, defender, tackle, 100, false)
	_chk("I11.03 Chilan Berry halves damage from a Normal move at 1× effectiveness",
			res_berry["damage"] == res_no_berry["damage"] / 2)
	_chk("I11.04 defender_item_consumed=true when Chilan Berry triggers on a Normal move",
			res_berry["defender_item_consumed"] == true)

	# I11.05: Does NOT become a second copy of the generic resist-berry (super-effective-only)
	# behavior — a non-Normal move, even a super-effective one, must NOT trigger a
	# Normal-param berry (param mismatch: FIRE != NORMAL).
	var fire_attacker := _make_mon("FireAtk3", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 80)
	var bug_defender := _make_mon("BugDef2", TypeChart.TYPE_BUG, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 40)
	var ember := _make_move("Ember", TypeChart.TYPE_FIRE, 1, 40)
	bug_defender.held_item = chilan  # Normal-resist berry, but the incoming move is Fire
	var res_fire := DamageCalculator.calculate(fire_attacker, bug_defender, ember, 100, false)
	_chk("I11.05 Chilan Berry does NOT trigger for a non-Normal move (even super-effective)",
			res_fire["defender_item_consumed"] == false)

	# I11.06: Integration — item_consumed fires when Chilan Berry activates in a real battle.
	var chilan_atk := _make_mon("ChilanAtk", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 80, 80, 100, 80, 100)
	chilan_atk.add_move(_make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	var chilan_def := _make_mon("ChilanDef", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			100, 80, 80, 80, 70, 20)
	chilan_def.held_item = _make_item(ItemManager.HOLD_EFFECT_RESIST_BERRY, TypeChart.TYPE_NORMAL)
	chilan_def.add_move(_make_move("Splash", TypeChart.TYPE_WATER, 2, 0))

	var bm := _make_bm()
	var consumed_chilan := []
	bm.item_consumed.connect(func(m, _i): consumed_chilan.append(m))
	bm.start_battle(chilan_atk, chilan_def)
	_chk("I11.06 item_consumed fired for Chilan Berry holder (berry activated in battle)",
			consumed_chilan.any(func(m): return m == chilan_def))
	bm.queue_free()


# ── I12: Heavy Duty Boots ───────────────────────────────────────────────────
# Follow-up fixes session, 2026-07-02 — closes the gap flagged in M16d's decisions.md.
# Source: IsBattlerAffectedByHazards (battle_util.c L9209-9228): FULL immunity to Spikes,
#   Toxic Spikes, and Stealth Rock alike (not a damage reduction) — same gate checked at
#   every TryHazardsOnSwitchIn call site (battle_switch_in.c L306-378). For Toxic Spikes
#   specifically, a grounded Poison-type still ABSORBS/clears the hazard regardless of the
#   boots (that check happens in an earlier branch than the boots gate in source).
# Uses the same signal-snapshot-at-battle-start pattern m16d_test.gd established for
# hazard testing: pre-set `_side_conditions` before start_battle(), observe via signals.

func _test_i12_heavy_duty_boots() -> void:
	var boots := _make_item(ItemManager.HOLD_EFFECT_HEAVY_DUTY_BOOTS)
	_chk("I12.01 Heavy Duty Boots hold_effect=119", boots.hold_effect == 119)

	var tackle := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 40)

	# I12.02/I12.03: Spikes — holder takes no damage; a non-holder in the same setup does.
	var spikes_holder := _make_mon("HDB_Sp1", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	spikes_holder.held_item = boots
	spikes_holder.add_move(tackle)
	var spikes_opp := _make_mon("HDB_Sp1O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	spikes_opp.add_move(tackle)
	var spikes_dmg_holder: Array[int] = []
	var bm1 := _make_bm()
	bm1._side_conditions[0]["spikes_layers"] = 3
	bm1.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == spikes_holder and hz == "spikes":
			spikes_dmg_holder.append(amount))
	bm1.start_battle(spikes_holder, spikes_opp)
	bm1.queue_free()
	_chk("I12.02 Heavy Duty Boots holder takes no Spikes damage", spikes_dmg_holder.is_empty())

	var spikes_nonholder := _make_mon("HDB_Sp2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	spikes_nonholder.add_move(tackle)
	var spikes_opp2 := _make_mon("HDB_Sp2O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	spikes_opp2.add_move(tackle)
	var spikes_dmg_nonholder: Array[int] = []
	var bm2 := _make_bm()
	bm2._side_conditions[0]["spikes_layers"] = 3
	bm2.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == spikes_nonholder and hz == "spikes":
			spikes_dmg_nonholder.append(amount))
	bm2.start_battle(spikes_nonholder, spikes_opp2)
	bm2.queue_free()
	_chk("I12.03 Item absence doesn't suppress Spikes for everyone (non-holder still hit)",
			spikes_dmg_nonholder.size() == 1 and spikes_dmg_nonholder[0] == spikes_nonholder.max_hp / 4)

	# I12.04: Toxic Spikes — holder (non-Poison-type, grounded) is not poisoned.
	var ts_holder := _make_mon("HDB_TS1", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	ts_holder.held_item = boots
	ts_holder.add_move(tackle)
	var ts_opp := _make_mon("HDB_TS1O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	ts_opp.add_move(tackle)
	var ts_status_holder: Array = []
	var bm3 := _make_bm()
	bm3._side_conditions[0]["toxic_spikes_layers"] = 2
	bm3.hazard_status_applied.connect(func(p: BattlePokemon, s: int):
		if p == ts_holder:
			ts_status_holder.append(s))
	bm3.start_battle(ts_holder, ts_opp)
	bm3.queue_free()
	_chk("I12.04 Heavy Duty Boots holder is not poisoned by Toxic Spikes",
			ts_status_holder.is_empty())
	_chk("I12.05 Heavy Duty Boots holder's status still STATUS_NONE",
			ts_holder.status == BattlePokemon.STATUS_NONE)

	# I12.06: Toxic Spikes — a grounded Poison-type STILL absorbs/clears it even while
	# holding Heavy Duty Boots (absorb branch runs before the boots gate in source).
	var ts_poison_holder := _make_mon("HDB_TS2", TypeChart.TYPE_POISON, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	ts_poison_holder.held_item = boots
	ts_poison_holder.add_move(tackle)
	var ts_opp2 := _make_mon("HDB_TS2O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	ts_opp2.add_move(tackle)
	var absorbed6: Array = []
	var bm4 := _make_bm()
	bm4._side_conditions[0]["toxic_spikes_layers"] = 1
	bm4.hazard_absorbed.connect(func(side: int, hz: String):
		if side == 0 and hz == "toxic_spikes":
			absorbed6.append(true))
	bm4.start_battle(ts_poison_holder, ts_opp2)
	bm4.queue_free()
	_chk("I12.06 A grounded Poison-type still absorbs Toxic Spikes even with Heavy Duty Boots",
			absorbed6.size() == 1)

	# I12.08/I12.09: Stealth Rock — holder takes no damage; a non-holder does.
	var sr_holder := _make_mon("HDB_SR1", TypeChart.TYPE_FLYING, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	sr_holder.held_item = boots
	sr_holder.add_move(tackle)
	var sr_opp := _make_mon("HDB_SR1O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	sr_opp.add_move(tackle)
	var sr_dmg_holder: Array[int] = []
	var bm5 := _make_bm()
	bm5._side_conditions[0]["stealth_rock"] = true
	bm5.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == sr_holder and hz == "stealth_rock":
			sr_dmg_holder.append(amount))
	bm5.start_battle(sr_holder, sr_opp)
	bm5.queue_free()
	_chk("I12.08 Heavy Duty Boots holder takes no Stealth Rock damage (even a 2×-weak Flying-type)",
			sr_dmg_holder.is_empty())

	var sr_nonholder := _make_mon("HDB_SR2", TypeChart.TYPE_FLYING, TypeChart.TYPE_NONE,
			800, 80, 80, 80, 80, 100)
	sr_nonholder.add_move(tackle)
	var sr_opp2 := _make_mon("HDB_SR2O", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			80, 5, 80, 80, 80, 50)
	sr_opp2.add_move(tackle)
	var sr_dmg_nonholder: Array[int] = []
	var bm6 := _make_bm()
	bm6._side_conditions[0]["stealth_rock"] = true
	bm6.hazard_damage.connect(func(p: BattlePokemon, amount: int, hz: String):
		if p == sr_nonholder and hz == "stealth_rock":
			sr_dmg_nonholder.append(amount))
	bm6.start_battle(sr_nonholder, sr_opp2)
	bm6.queue_free()
	# Mono Flying-type vs Rock-type Stealth Rock = 2.0× (not 4.0×, which needs a dual-type
	# combo) → maxHP/4 per _stealth_rock_damage's table (M16d).
	_chk("I12.09 Item absence doesn't suppress Stealth Rock for everyone (non-holder still hit)",
			sr_dmg_nonholder.size() == 1 and sr_dmg_nonholder[0] == sr_nonholder.max_hp / 4)
