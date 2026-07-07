extends Node

# M18c test suite — Berry HP-threshold effects (Liechi/Ganlon/Salac/Petaya/Apicot/
# Lansat/Starf/Custap/Micle/Enigma)
#
# Ground truth: pokeemerald-expansion, src/battle_hold_effects.c's ItemBattleEffects
# switch (L1201-1224) for the 8 general-dispatch cases; Custap is handled entirely
# separately in battle_main.c's turn-order code.
#
# Corrections found at Step 0 (see docs/decisions.md's [M18c] entry for full detail):
#   - All 8 stat-berries/Lansat/Starf/Custap confirmed holdEffectParam=4 (25%)
#     INDIVIDUALLY via src/data/items.h, not assumed uniform.
#   - CompareStat(stat < MAX_STAT_STAGE) runs BEFORE the HP-threshold check for the
#     5 flat-stat berries and Starf — an already-maxed stat means NO trigger/consume
#     at all, not "triggers with no effect."
#   - Ripen doubles the 5 flat-stat berries (+1->+2) and Starf (+2->+4), but NOT
#     Lansat (confirmed absent from CriticalHitRatioUp in source).
#   - Lansat sets the SAME focus_energy volatile the Focus Energy MOVE sets (+2 crit
#     stage) — NOT M18e's crit_stage_bonus()/+1 item mechanism, contrary to the
#     task's own initial framing. A real, source-confirmed correction.
#   - Custap's turn-order check has NO IsUnnerveBlocked call anywhere in source — it
#     bypasses Unnerve entirely (Klutz/Gluttony still apply), unlike every other
#     item in this tier, which all route through the Unnerve-gated general dispatcher.
#   - Enigma Berry is NOT an HP threshold and NOT the resist-berry TYPE-match check —
#     it heals on the ACTUAL COMPUTED super-effective result, read from
#     DamageCalculator.calculate's own "effectiveness" field, regardless of current HP.
#
# Sections: C01-C05 flat-stat berries, C06 Starf, C07 Lansat, C08 Custap, C09 Micle,
# C10 Enigma.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_c01_liechi_berry()
	_test_c02_ganlon_berry()
	_test_c03_salac_berry()
	_test_c04_petaya_berry()
	_test_c05_apicot_berry()
	_test_c06_starf_berry()
	_test_c07_lansat_berry()
	_test_c08_custap_berry()
	_test_c09_micle_berry()
	_test_c10_enigma_berry()

	var total := _pass + _fail
	print("m18c_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18a_test.gd/m18e_test.gd's established pattern) ──────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


# base_hp=100 (this file's _make_mon default) -> max_hp = floor(2*100*50/100)+50+10
# = 100+50+10 = 160. 25% threshold = 40 (<=40 triggers, 41 does not).
const RIPEN_ID := 247


# ── C01: Liechi Berry (567) — full checks (data/trigger/threshold/maxed/Ripen) ──
func _test_c01_liechi_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_ATTACK_UP, 4)
	_chk("C01.01 Liechi Berry hold_effect=ATTACK_UP, param=4 (25%)",
			item.hold_effect == ItemManager.HOLD_EFFECT_ATTACK_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C01_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40  # exactly 25% -> triggers
	var trig: Dictionary = ItemManager.stat_raise_berry_trigger(mon)
	_chk("C01.02 Liechi triggers at <=25%% HP: stat=STAGE_ATK, amount=1",
			trig.get("stat", -1) == BattlePokemon.STAGE_ATK and trig.get("amount", -1) == 1)

	var mon2 := _make_mon("C01_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41  # just above threshold
	_chk("C01.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.stat_raise_berry_trigger(mon2).is_empty())

	var mon3 := _make_mon("C01_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	mon3.current_hp = 40
	mon3.stat_stages[BattlePokemon.STAGE_ATK] = 6  # already maxed
	_chk("C01.04 CORRECTION-confirming: does NOT trigger when Attack is already " +
			"maxed, even at/below threshold (CompareStat runs BEFORE the HP check)",
			ItemManager.stat_raise_berry_trigger(mon3).is_empty())

	var mon4 := _make_mon("C01_Mon4", TypeChart.TYPE_NORMAL)
	mon4.held_item = item
	mon4.current_hp = 40
	mon4.ability = _load_ability(RIPEN_ID)
	var trig4: Dictionary = ItemManager.stat_raise_berry_trigger(mon4)
	_chk("C01.05 Ripen doubles Liechi's amount to +2",
			trig4.get("amount", -1) == 2)


# ── C02: Ganlon Berry (568) ──────────────────────────────────────────────────
func _test_c02_ganlon_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_DEFENSE_UP, 4)
	_chk("C02.01 Ganlon Berry hold_effect=DEFENSE_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_DEFENSE_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C02_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	var trig: Dictionary = ItemManager.stat_raise_berry_trigger(mon)
	_chk("C02.02 Ganlon triggers at <=25%% HP: stat=STAGE_DEF, amount=1",
			trig.get("stat", -1) == BattlePokemon.STAGE_DEF and trig.get("amount", -1) == 1)

	var mon2 := _make_mon("C02_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C02.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.stat_raise_berry_trigger(mon2).is_empty())


# ── C03: Salac Berry (569) ───────────────────────────────────────────────────
func _test_c03_salac_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SPEED_UP, 4)
	_chk("C03.01 Salac Berry hold_effect=SPEED_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_SPEED_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C03_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	var trig: Dictionary = ItemManager.stat_raise_berry_trigger(mon)
	_chk("C03.02 Salac triggers at <=25%% HP: stat=STAGE_SPEED, amount=1",
			trig.get("stat", -1) == BattlePokemon.STAGE_SPEED and trig.get("amount", -1) == 1)

	var mon2 := _make_mon("C03_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C03.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.stat_raise_berry_trigger(mon2).is_empty())


# ── C04: Petaya Berry (570) ──────────────────────────────────────────────────
func _test_c04_petaya_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SP_ATTACK_UP, 4)
	_chk("C04.01 Petaya Berry hold_effect=SP_ATTACK_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_SP_ATTACK_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C04_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	var trig: Dictionary = ItemManager.stat_raise_berry_trigger(mon)
	_chk("C04.02 Petaya triggers at <=25%% HP: stat=STAGE_SPATK, amount=1",
			trig.get("stat", -1) == BattlePokemon.STAGE_SPATK and trig.get("amount", -1) == 1)

	var mon2 := _make_mon("C04_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C04.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.stat_raise_berry_trigger(mon2).is_empty())


# ── C05: Apicot Berry (571) ──────────────────────────────────────────────────
func _test_c05_apicot_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_SP_DEFENSE_UP, 4)
	_chk("C05.01 Apicot Berry hold_effect=SP_DEFENSE_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_SP_DEFENSE_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C05_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	var trig: Dictionary = ItemManager.stat_raise_berry_trigger(mon)
	_chk("C05.02 Apicot triggers at <=25%% HP: stat=STAGE_SPDEF, amount=1",
			trig.get("stat", -1) == BattlePokemon.STAGE_SPDEF and trig.get("amount", -1) == 1)

	var mon2 := _make_mon("C05_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C05.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.stat_raise_berry_trigger(mon2).is_empty())

	var mon3 := _make_mon("C05_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	mon3.current_hp = 40
	mon3.ability = _load_ability(RIPEN_ID)
	var trig3: Dictionary = ItemManager.stat_raise_berry_trigger(mon3)
	_chk("C05.04 Ripen doubles Apicot's amount to +2 (second independent confirmation)",
			trig3.get("amount", -1) == 2)


# ── C06: Starf Berry (573) — random stat, excludes Accuracy/Evasion ────────────
func _test_c06_starf_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_RANDOM_STAT_UP, 4)
	_chk("C06.01 Starf Berry hold_effect=RANDOM_STAT_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_RANDOM_STAT_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C06_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	var trig: Dictionary = ItemManager.random_stat_raise_berry_trigger(
			mon, false, false, null, BattlePokemon.STAGE_DEF)
	_chk("C06.02 Starf (forced_stat=STAGE_DEF) triggers at <=25%% HP: stat=STAGE_DEF, amount=2",
			trig.get("stat", -1) == BattlePokemon.STAGE_DEF and trig.get("amount", -1) == 2)

	var mon2 := _make_mon("C06_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C06.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.random_stat_raise_berry_trigger(mon2).is_empty())

	var mon3 := _make_mon("C06_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	mon3.current_hp = 40
	for i in range(5):
		mon3.stat_stages[i] = 6  # all 5 eligible stats maxed
	_chk("C06.04 discriminator: does NOT trigger when all 5 eligible stats are maxed",
			ItemManager.random_stat_raise_berry_trigger(mon3).is_empty())

	var mon4 := _make_mon("C06_Mon4", TypeChart.TYPE_NORMAL)
	mon4.held_item = item
	mon4.current_hp = 40
	mon4.ability = _load_ability(RIPEN_ID)
	var trig4: Dictionary = ItemManager.random_stat_raise_berry_trigger(
			mon4, false, false, null, BattlePokemon.STAGE_SPEED)
	_chk("C06.05 Ripen doubles Starf's amount to +4",
			trig4.get("amount", -1) == 4)

	var mon5 := _make_mon("C06_Mon5", TypeChart.TYPE_NORMAL)
	mon5.held_item = item
	mon5.current_hp = 40
	mon5.stat_stages[BattlePokemon.STAGE_ACCURACY] = -6
	mon5.stat_stages[BattlePokemon.STAGE_EVASION] = -6
	for i in range(5):
		mon5.stat_stages[i] = 6  # all 5 eligible stats maxed; only Acc/Eva remain non-maxed
	_chk("C06.06 CORRECTION-confirming: does NOT pick Accuracy/Evasion even though " +
			"they're not maxed — the pool EXCLUDES them, unlike Moody's own broader pool",
			ItemManager.random_stat_raise_berry_trigger(mon5).is_empty())


# ── C07: Lansat Berry (572) — sets focus_energy, NOT crit_stage_bonus() ────────
func _test_c07_lansat_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CRITICAL_UP, 4)
	_chk("C07.01 Lansat Berry hold_effect=CRITICAL_UP, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_CRITICAL_UP and item.hold_effect_param == 4)

	var mon := _make_mon("C07_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	_chk("C07.02 Lansat's trigger function returns the item (non-null) at <=25%% HP",
			ItemManager.lansat_berry_trigger(mon) != null)

	var mon2 := _make_mon("C07_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C07.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.lansat_berry_trigger(mon2) == null)

	var mon3 := _make_mon("C07_Mon3", TypeChart.TYPE_NORMAL)
	mon3.held_item = item
	mon3.current_hp = 40
	mon3.focus_energy = true  # already active
	_chk("C07.04 discriminator: does NOT re-trigger when focus_energy is already active",
			ItemManager.lansat_berry_trigger(mon3) == null)

	# Full-battle: confirm the actual wiring sets focus_energy=true. Engineered so
	# the Lansat holder (a) is hit once (weak, survivable, HP already <=25%
	# BEFORE the hit) and (b) guaranteed-OHKOs the opponent on its own retaliation
	# (slower, so it acts second), ending the battle after exactly one exchange
	# with the holder alive — avoids any ambiguity from a longer multi-turn battle.
	var holder := _make_mon("C07_Holder", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 200, 60, 60, 60, 10)  # slow, huge Atk for the guaranteed OHKO retaliation
	holder.held_item = item
	holder.current_hp = 40  # <=25% before the opponent's hit
	holder.add_move(_make_move("C07_Retaliate", TypeChart.TYPE_NORMAL, 0, 150))
	var opp := _make_mon("C07_Opp", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			10, 5, 60, 60, 60, 100)  # fast, tiny HP/Atk — weak hit, dies to retaliation
	opp.add_move(_make_move("C07_WeakHit", TypeChart.TYPE_NORMAL, 0, 10))

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.start_battle_with_parties(BattleParty.single(holder), BattleParty.single(opp))
	_chk("C07.05 full-battle: Lansat Berry sets focus_energy=true after the holder " +
			"is hit at <=25%% HP", holder.focus_energy == true)
	bm.queue_free()


# ── C08: Custap Berry (576) — deterministic, HP-gated, bypasses Unnerve ────────
func _test_c08_custap_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_CUSTAP_BERRY, 4)
	_chk("C08.01 Custap Berry hold_effect=CUSTAP_BERRY, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_CUSTAP_BERRY and item.hold_effect_param == 4)

	var mon := _make_mon("C08_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	_chk("C08.02 Custap activates (deterministic, no roll) at <=25%% HP",
			ItemManager.custap_berry_activates(mon) != null)

	var mon2 := _make_mon("C08_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C08.03 discriminator: does NOT activate above 25%% HP — distinguishes " +
			"Custap's HP-gated shape from Quick Claw's unconditional 20%% roll ([M18l])",
			ItemManager.custap_berry_activates(mon2) == null)

	var bare := _make_mon("C08_Bare", TypeChart.TYPE_NORMAL)
	bare.current_hp = 40
	_chk("C08.04 discriminator: holding nothing never activates",
			ItemManager.custap_berry_activates(bare) == null)

	# Full-battle: holder is SLOWER but at <=25%% HP -> acts first anyway. Custap
	# has no unnerve_active parameter at all (see the function's own signature and
	# doc comment) — a direct, structural confirmation of the Step 0 correction
	# that Custap bypasses Unnerve entirely, distinct from every other item this tier.
	var custap_mon := _make_mon("C08_Battle", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 40)
	custap_mon.held_item = item
	custap_mon.current_hp = 40  # <=25%
	custap_mon.add_move(_make_move("C08_Tackle", TypeChart.TYPE_NORMAL, 0, 5))
	var opp := _make_mon("C08_Opp", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE,
			100, 60, 60, 60, 60, 100)
	opp.add_move(_make_move("C08_Tackle2", TypeChart.TYPE_NORMAL, 0, 5))

	var events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.move_executed.connect(func(a, d, m, dmg): events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(custap_mon), BattleParty.single(opp))
	_chk("C08.05 full-battle: Custap Berry (holder at <=25%% HP, normally SLOWER) " +
			"makes the holder act FIRST",
			not events.is_empty() and events[0][0] == custap_mon)
	bm.queue_free()


# ── C09: Micle Berry (575) — one-shot ×1.2/×1.4 accuracy, then expires ─────────
func _test_c09_micle_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_MICLE_BERRY, 4)
	_chk("C09.01 Micle Berry hold_effect=MICLE_BERRY, param=4",
			item.hold_effect == ItemManager.HOLD_EFFECT_MICLE_BERRY and item.hold_effect_param == 4)

	var mon := _make_mon("C09_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	mon.current_hp = 40
	_chk("C09.02 Micle's trigger function returns the item (non-null) at <=25%% HP",
			ItemManager.micle_berry_trigger(mon) != null)

	var mon2 := _make_mon("C09_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	mon2.current_hp = 41
	_chk("C09.03 discriminator: does NOT trigger above 25%% HP",
			ItemManager.micle_berry_trigger(mon2) == null)

	var mon3 := _make_mon("C09_Mon3", TypeChart.TYPE_NORMAL)
	_chk("C09.04 accuracy modifier: 100 (no-op) when micle_boost_active is false",
			ItemManager.micle_accuracy_modifier_percent(mon3) == 100)
	mon3.micle_boost_active = true
	_chk("C09.05 accuracy modifier: 120 (×1.2) when micle_boost_active is true",
			ItemManager.micle_accuracy_modifier_percent(mon3) == 120)
	mon3.ability = _load_ability(RIPEN_ID)
	_chk("C09.06 accuracy modifier: 140 (×1.4) when micle_boost_active is true AND Ripen",
			ItemManager.micle_accuracy_modifier_percent(mon3) == 140)

	# Full-battle: confirm the one-shot flag is consumed (cleared) after exactly
	# one accuracy check, regardless of hit/miss — pre-set the flag directly
	# (isolating JUST the consumption wiring from the trigger-condition logic
	# already covered by C09.02/C09.03 above).
	var attacker := _make_mon("C09_Battle", TypeChart.TYPE_NORMAL)
	attacker.micle_boost_active = true
	attacker.add_move(_make_move("C09_Tackle", TypeChart.TYPE_NORMAL, 0, 40))
	var defender := _make_mon("C09_Def", TypeChart.TYPE_NORMAL)
	defender.add_move(_make_move("C09_Tackle2", TypeChart.TYPE_NORMAL, 0, 40))

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))
	_chk("C09.07 full-battle: micle_boost_active is cleared after the holder's " +
			"first move (one-shot, consumed regardless of hit/miss)",
			attacker.micle_boost_active == false)
	bm.queue_free()


# ── C10: Enigma Berry (574) — heals on super-effective hit, NOT an HP threshold ─
func _test_c10_enigma_berry() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_ENIGMA_BERRY)
	_chk("C10.01 Enigma Berry hold_effect=ENIGMA_BERRY, no hold_effect_param needed",
			item.hold_effect == ItemManager.HOLD_EFFECT_ENIGMA_BERRY)

	var mon := _make_mon("C10_Mon", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	mon.held_item = item
	mon.current_hp = 100  # near-full — NOT anywhere near a 25%% threshold
	_chk("C10.02 direct: heals 25%% max HP (=40 of 160) when hit super-effectively, " +
			"REGARDLESS of near-full current HP — not an HP threshold at all",
			ItemManager.enigma_berry_heal(mon, true) == 40)

	var mon2 := _make_mon("C10_Mon2", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	mon2.held_item = item
	mon2.current_hp = 100
	_chk("C10.03 discriminator: does NOT heal when the hit was NOT super-effective",
			ItemManager.enigma_berry_heal(mon2, false) == 0)

	var mon3 := _make_mon("C10_Mon3", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NONE, 100)
	mon3.held_item = item
	mon3.current_hp = 100
	mon3.ability = _load_ability(RIPEN_ID)
	_chk("C10.04 Ripen doubles Enigma's heal to 50%% max HP (=80 of 160)",
			ItemManager.enigma_berry_heal(mon3, true) == 80)

	# Full-battle: a real Water move against a genuinely 2.0x-weak Fire-type
	# Enigma holder — same Water-vs-Fire matchup this project's own resist-berry
	# tests ([M18b]) already confirmed 2.0x via type_chart.gd's TABLE.
	var fire_def := _make_mon("C10_FireDef", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			150, 60, 60, 60, 60, 60)
	fire_def.held_item = item
	fire_def.current_hp = 200  # out of max_hp=210 — near-full, NOT threshold-triggerable
	var water_atk := _make_mon("C10_WaterAtk", TypeChart.TYPE_WATER)
	water_atk.add_move(_make_move("C10_WaterMove", TypeChart.TYPE_WATER, 1, 40))

	var heal_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.item_healed.connect(func(m, amt): heal_events.push_back([m, amt]))
	bm.start_battle_with_parties(BattleParty.single(water_atk), BattleParty.single(fire_def))
	_chk("C10.05 full-battle: a super-effective Water hit against the Fire-type " +
			"Enigma holder triggers a heal, even though the holder started near-full HP",
			not heal_events.is_empty() and heal_events[0][0] == fire_def)
	bm.queue_free()

	# Discriminator: a Normal-type (1.0x, not super-effective) hit against the
	# same Fire-type holder does NOT heal.
	var fire_def2 := _make_mon("C10_FireDef2", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			150, 60, 60, 60, 60, 60)
	fire_def2.held_item = item
	fire_def2.current_hp = 200
	var normal_atk := _make_mon("C10_NormalAtk", TypeChart.TYPE_NORMAL)
	normal_atk.add_move(_make_move("C10_NormalMove", TypeChart.TYPE_NORMAL, 0, 40))

	var heal_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.item_healed.connect(func(m, amt): heal_events2.push_back([m, amt]))
	bm2.start_battle_with_parties(BattleParty.single(normal_atk), BattleParty.single(fire_def2))
	_chk("C10.06 discriminator: a non-super-effective (Normal, 1.0x) hit does NOT " +
			"trigger Enigma's heal",
			heal_events2.is_empty())
	bm2.queue_free()
