extends Node

# [Bucket 3] Completes Bucket 3 (30/30): the two remaining clusters.
#
# Cluster 1 (combined secondary effects): Thunder Fang(422), Ice Fang(423),
# Fire Fang(424). Step 0 confirmed each is EFFECT_HIT with TWO SEPARATE
# ADDITIONAL_EFFECTS blocks: a 10% status roll (paralysis/freeze-or-frostbite/
# burn) and a 10% flinch roll, independently rolled — confirmed from source's
# Cmd_setadditionaleffects loop, which rolls each additionalEffect with its
# own RNG index (RNG_SECONDARY_EFFECT + counter), own Serene-Grace doubling,
# and own Shield-Dust/Covert-Cloak/Sheer-Force gate (CalcSecondaryEffectChance/
# MoveIsAffectedBySheerForce both operate per-effect, not per-move). Design:
# new secondary_effect_2/secondary_chance_2 fields on MoveData (status stays in
# the existing slot 1; flinch in the new slot 2), dispatched via a SECOND
# try_secondary_effect call on a shallow-duplicated MoveData (M17n-6's
# "duplicate and substitute" pattern) rather than changing that function's own
# signature — this composes every existing gate (Serene Grace/Shield Dust/
# Covert Cloak/Sheer Force) correctly for free, checked independently per
# slot. King's Rock/Razor Fang's own mutual-exclusion gate (M18k) is extended
# to check BOTH slots for SE_FLINCH, since a move's native flinch can now live
# in slot 2 instead of slot 1.
#
# Cluster 2 (screen+damage): Glitzy Glow(683), Baddy Bad(684). Step 0
# confirmed both are EFFECT_HIT damage moves whose additionalEffects carries a
# GUARANTEED (no .chance field), SELF-targeted MOVE_EFFECT_LIGHT_SCREEN/
# MOVE_EFFECT_REFLECT — the exact same TrySetReflect/TrySetLightScreen source
# calls the pure-status is_reflect/is_light_screen moves already use, just
# unreachable from a damaging move's dispatch path before this tier (that
# early-return branch never deals damage at all). New sets_reflect_on_hit/
# sets_light_screen_on_hit MoveData flags, dispatched inside _do_damaging_hit
# (unconditional on damage > 0, not routed through try_secondary_effect at all
# since Shield Dust/Sheer Force/Serene Grace only ever gate TRUE/chance>0
# secondaries) — reusing the same already-up no-refresh check and Light Clay
# duration extension.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c, battle_util.c, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_cluster1_functional()
	_test_cluster2_functional()

	var total := _pass + _fail
	print("m19_bucket3_cluster12_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 5 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var tf := _load_move(422)
	_chk("422 Thunder Fang loads", tf != null)
	_chk("422 name", tf.move_name == "Thunder Fang")
	_chk("422 type/category/power/accuracy/pp",
			tf.type == TypeChart.TYPE_ELECTRIC and tf.category == 0 and tf.power == 65
					and tf.accuracy == 95 and tf.pp == 15)
	_chk("422 makes_contact + biting_move", tf.makes_contact and tf.biting_move)
	_chk("422 slot 1 = paralysis 10%",
			tf.secondary_effect == MoveData.SE_PARALYSIS and tf.secondary_chance == 10)
	_chk("422 slot 2 = flinch 10%",
			tf.secondary_effect_2 == MoveData.SE_FLINCH and tf.secondary_chance_2 == 10)

	var icf := _load_move(423)
	_chk("423 Ice Fang loads", icf != null)
	_chk("423 name", icf.move_name == "Ice Fang")
	_chk("423 type/category/power/accuracy/pp",
			icf.type == TypeChart.TYPE_ICE and icf.category == 0 and icf.power == 65
					and icf.accuracy == 95 and icf.pp == 15)
	_chk("423 makes_contact + biting_move", icf.makes_contact and icf.biting_move)
	_chk("423 slot 1 = freeze 10%",
			icf.secondary_effect == MoveData.SE_FREEZE and icf.secondary_chance == 10)
	_chk("423 slot 2 = flinch 10%",
			icf.secondary_effect_2 == MoveData.SE_FLINCH and icf.secondary_chance_2 == 10)

	var fif := _load_move(424)
	_chk("424 Fire Fang loads", fif != null)
	_chk("424 name", fif.move_name == "Fire Fang")
	_chk("424 type/category/power/accuracy/pp",
			fif.type == TypeChart.TYPE_FIRE and fif.category == 0 and fif.power == 65
					and fif.accuracy == 95 and fif.pp == 15)
	_chk("424 makes_contact + biting_move", fif.makes_contact and fif.biting_move)
	_chk("424 slot 1 = burn 10%",
			fif.secondary_effect == MoveData.SE_BURN and fif.secondary_chance == 10)
	_chk("424 slot 2 = flinch 10%",
			fif.secondary_effect_2 == MoveData.SE_FLINCH and fif.secondary_chance_2 == 10)

	var gg := _load_move(683)
	_chk("683 Glitzy Glow loads", gg != null)
	_chk("683 name", gg.move_name == "Glitzy Glow")
	_chk("683 type/category/power/accuracy/pp",
			gg.type == TypeChart.TYPE_PSYCHIC and gg.category == 1 and gg.power == 80
					and gg.accuracy == 95 and gg.pp == 15)
	_chk("683 sets_light_screen_on_hit only", gg.sets_light_screen_on_hit and not gg.sets_reflect_on_hit)
	_chk("683 no pure-status Reflect/Light Screen flag (this is a damage move)",
			not gg.is_reflect and not gg.is_light_screen)

	var bb := _load_move(684)
	_chk("684 Baddy Bad loads", bb != null)
	_chk("684 name", bb.move_name == "Baddy Bad")
	_chk("684 type/category/power/accuracy/pp",
			bb.type == TypeChart.TYPE_DARK and bb.category == 1 and bb.power == 80
					and bb.accuracy == 95 and bb.pp == 15)
	_chk("684 sets_reflect_on_hit only", bb.sets_reflect_on_hit and not bb.sets_light_screen_on_hit)
	_chk("684 no pure-status Reflect/Light Screen flag (this is a damage move)",
			not bb.is_reflect and not bb.is_light_screen)


# ── Section B: Cluster 1 functional checks ──────────────────────────────────

func _test_cluster1_functional() -> void:
	_test_c1_slot1_status_direct()
	_test_c1_slot2_flinch_direct()
	_test_c1_slots_independent()
	_test_c1_sheer_force_suppresses_both()
	_test_c1_shield_dust_blocks_both()
	_test_c1_full_battle_both_fire_together()
	_test_c1_kings_rock_mutual_exclusion()


# C1.1: slot 1 (paralysis) fires via a direct try_secondary_effect call with
# force_secondary=true — this project's established convention for
# deterministic secondary-chance testing (no full-battle forcing seam exists
# for the chance roll itself).
func _test_c1_slot1_status_direct() -> void:
	var tf := _load_move(422)
	var atk := _make_mon("C1SAtk", TypeChart.TYPE_ELECTRIC)
	var def := _make_mon("C1SDef", TypeChart.TYPE_NORMAL)

	var fired := StatusManager.try_secondary_effect(atk, def, tf, true)
	_chk("C1.1 Thunder Fang slot 1 (paralysis) fires when forced", fired == true)
	_chk("C1.1 defender is actually paralyzed", def.status == BattlePokemon.STATUS_PARALYSIS)


# C1.2: slot 2 (flinch) is dispatched via a shallow-duplicated MoveData with
# secondary_effect/secondary_chance overridden to the slot-2 values — the
# SAME substitution BattleManager._do_damaging_hit performs internally.
# try_secondary_effect returns true (the flinch "roll succeeded" signal); it
# does not itself set .flinched (the caller — BattleManager — decides based
# on turn order), matching SE_FLINCH's existing documented contract.
func _test_c1_slot2_flinch_direct() -> void:
	var tf := _load_move(422)
	var slot2_move: MoveData = tf.duplicate()
	slot2_move.secondary_effect = tf.secondary_effect_2
	slot2_move.secondary_chance = tf.secondary_chance_2
	var atk := _make_mon("C1FAtk", TypeChart.TYPE_ELECTRIC)
	var def := _make_mon("C1FDef", TypeChart.TYPE_NORMAL)

	var fired := StatusManager.try_secondary_effect(atk, def, slot2_move, true)
	_chk("C1.2 Thunder Fang slot 2 (flinch), dispatched via a duplicated MoveData, " +
			"fires when forced", fired == true)


# C1.3: the two slots roll independently — forcing slot 1 to MISS while
# forcing slot 2 to HIT (via two separate calls) must not affect each other.
func _test_c1_slots_independent() -> void:
	var tf := _load_move(422)
	var slot2_move: MoveData = tf.duplicate()
	slot2_move.secondary_effect = tf.secondary_effect_2
	slot2_move.secondary_chance = tf.secondary_chance_2
	var atk := _make_mon("C1IAtk", TypeChart.TYPE_ELECTRIC)
	var def := _make_mon("C1IDef", TypeChart.TYPE_NORMAL)

	var slot1_missed := StatusManager.try_secondary_effect(atk, def, tf, false)
	var slot2_hit := StatusManager.try_secondary_effect(atk, def, slot2_move, true)
	_chk("C1.3 slot 1 forced to miss actually misses (no status applied)",
			slot1_missed == false and def.status == BattlePokemon.STATUS_NONE)
	_chk("C1.3 slot 2 independently forced to hit still fires despite slot 1 missing",
			slot2_hit == true)


# C1.4: Sheer Force suppresses BOTH rolls independently — matching source's
# MoveIsAffectedBySheerForce, which flags the whole move once ANY additional
# effect has chance > 0, and try_secondary_effect's existing attacker-keyed
# Sheer Force gate, checked per call.
func _test_c1_sheer_force_suppresses_both() -> void:
	var tf := _load_move(422)
	var slot2_move: MoveData = tf.duplicate()
	slot2_move.secondary_effect = tf.secondary_effect_2
	slot2_move.secondary_chance = tf.secondary_chance_2
	var sheer_force := _load_ability(125)
	var atk := _make_mon("C1SFAtk", TypeChart.TYPE_ELECTRIC)
	atk.ability = sheer_force
	var def := _make_mon("C1SFDef", TypeChart.TYPE_NORMAL)

	_chk("C1.4 Sheer Force suppresses slot 1 (paralysis) even when forced true",
			StatusManager.try_secondary_effect(atk, def, tf, true) == false)
	_chk("C1.4 Sheer Force ALSO suppresses slot 2 (flinch) even when forced true",
			StatusManager.try_secondary_effect(atk, def, slot2_move, true) == false)


# C1.5: Shield Dust (defender-keyed) blocks BOTH rolls independently — the
# same "blanket per-effect gate" source confirms via IsMoveEffectBlockedByTarget.
func _test_c1_shield_dust_blocks_both() -> void:
	var tf := _load_move(422)
	var slot2_move: MoveData = tf.duplicate()
	slot2_move.secondary_effect = tf.secondary_effect_2
	slot2_move.secondary_chance = tf.secondary_chance_2
	var shield_dust := _load_ability(19)
	var atk := _make_mon("C1SDAtk", TypeChart.TYPE_ELECTRIC)
	var def := _make_mon("C1SDDef", TypeChart.TYPE_NORMAL)
	def.ability = shield_dust

	_chk("C1.5 Shield Dust blocks slot 1 (paralysis) even when forced true",
			StatusManager.try_secondary_effect(atk, def, tf, true) == false)
	_chk("C1.5 Shield Dust ALSO blocks slot 2 (flinch) even when forced true",
			StatusManager.try_secondary_effect(atk, def, slot2_move, true) == false)


# C1.6: full-battle integration — confirms BattleManager._do_damaging_hit's
# REAL dispatch (not a standalone try_secondary_effect call) actually wires
# both slots and both fire together on the same hit. Synthetic MoveData with
# both chances forced to 100%, matching this project's established
# "MoveData.new() with secondary_chance=100" precedent (m17b_test.gd's
# Steadfast test) for deterministic full-battle secondary-effect proof.
func _test_c1_full_battle_both_fire_together() -> void:
	var combo := MoveData.new()
	combo.move_name = "TestComboMove"
	combo.type = TypeChart.TYPE_NORMAL
	combo.category = 0
	combo.power = 40
	combo.accuracy = 100
	combo.pp = 20
	combo.secondary_effect = MoveData.SE_PARALYSIS
	combo.secondary_chance = 100
	combo.secondary_effect_2 = MoveData.SE_FLINCH
	combo.secondary_chance_2 = 100

	var tackle := _load_move(33)
	var atk := _make_mon("C1FBAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(combo)
	var def := _make_mon("C1FBDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var skipped := []
	bm.move_skipped.connect(func(m, reason): skipped.append([m, reason]))
	bm.start_battle(atk, def)

	_chk("C1.6 full-battle: the slower target is BOTH paralyzed AND flinched from " +
			"the same single hit — both slots dispatched by the real _do_damaging_hit " +
			"call, not just try_secondary_effect standalone",
			def.status == BattlePokemon.STATUS_PARALYSIS
					and skipped.any(func(s): return s[0] == def and s[1] == "flinched"))


# C1.7: King's Rock mutual exclusion, extended to slot 2 — with the item's
# own roll FORCED true every trial, the observed flinch rate on the target
# must track Thunder Fang's own unforced ~10% NATIVE (slot 2) chance, not the
# ~100% a stacked independent King's-Rock roll would produce if the mutual-
# exclusion gate failed to recognize slot 2's native SE_FLINCH. Statistical
# rate test mirroring m18k_test.gd's own K03 precedent (an uncontrolled
# number of battle turns would compound the rate, so only the target's very
# first action attempt is sampled per trial).
func _test_c1_kings_rock_mutual_exclusion() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FLINCH, 10)
	var thunder_fang := _load_move(422)

	var n := 300
	var flinch_count := 0
	for _i in range(n):
		var kr := _make_mon("C1KR_Battle", TypeChart.TYPE_ELECTRIC, 100, 60, 60, 60, 60, 100)
		kr.held_item = item
		kr.add_move(thunder_fang)
		var opp := _make_mon("C1KR_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
		opp.add_move(thunder_fang)

		var timeline := []
		var bm := BattleManager.new()
		add_child(bm)
		bm._force_kings_rock_roll = true
		bm.move_executed.connect(func(a, d, m, dmg): timeline.push_back(["moved", a]))
		bm.move_skipped.connect(func(m, reason): timeline.push_back(["skipped", m, reason]))
		bm.start_battle_with_parties(BattleParty.single(kr), BattleParty.single(opp))
		for event in timeline:
			if event[1] == opp:
				if event[0] == "skipped" and event[2] == "flinched":
					flinch_count += 1
				break
		bm.queue_free()

	var rate: float = float(flinch_count) / n
	_chk("C1.7 mutual exclusion CONFIRMED for slot 2: with King's Rock's own roll " +
			"forced true on a Thunder-Fang user, the observed flinch rate tracks " +
			"Thunder Fang's OWN unforced ~10%% native (slot 2) chance -- NOT the " +
			"~100%% a stacked independent roll would produce -- proving the item " +
			"contributes nothing extra when the move's native flinch lives in slot 2 " +
			"(n=%d, observed=%.3f)" % [n, rate],
			rate > 0.02 and rate < 0.30)


# ── Section C: Cluster 2 functional checks ──────────────────────────────────

func _test_cluster2_functional() -> void:
	_test_c2_glitzy_glow_sets_light_screen_and_damages()
	_test_c2_baddy_bad_sets_reflect_and_damages()
	_test_c2_screen_lands_on_attacker_side_not_target_side()
	_test_c2_already_up_no_refresh()


# C2.1: Glitzy Glow deals real damage AND sets Light Screen on the attacker's
# own side in the same hit.
func _test_c2_glitzy_glow_sets_light_screen_and_damages() -> void:
	var glitzy_glow := _load_move(683)
	var tackle := _load_move(33)
	var atk := _make_mon("C2GGAtk", TypeChart.TYPE_PSYCHIC)
	atk.add_move(glitzy_glow)
	var def := _make_mon("C2GGDef", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var set_events := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.screen_set.connect(func(side, name_): set_events.append([side, name_]))
	bm.start_battle(atk, def)

	_chk("C2.1 Glitzy Glow deals real nonzero damage", dmg[0] > 0)
	_chk("C2.1 Glitzy Glow ALSO sets Light Screen on the attacker's own side (0)",
			[0, "light_screen"] in set_events)
	_chk("C2.1 Glitzy Glow does NOT set Reflect", not set_events.any(func(e): return e[1] == "reflect"))


# C2.2: Baddy Bad deals real damage AND sets Reflect on the attacker's own side.
func _test_c2_baddy_bad_sets_reflect_and_damages() -> void:
	var baddy_bad := _load_move(684)
	var tackle := _load_move(33)
	var atk := _make_mon("C2BBAtk", TypeChart.TYPE_DARK)
	atk.add_move(baddy_bad)
	var def := _make_mon("C2BBDef", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var dmg := [0]
	var set_events := []
	bm.move_executed.connect(func(a, _d, _m, amount):
		if a == atk and dmg[0] == 0:
			dmg[0] = amount)
	bm.screen_set.connect(func(side, name_): set_events.append([side, name_]))
	bm.start_battle(atk, def)

	_chk("C2.2 Baddy Bad deals real nonzero damage", dmg[0] > 0)
	_chk("C2.2 Baddy Bad ALSO sets Reflect on the attacker's own side (0)",
			[0, "reflect"] in set_events)
	_chk("C2.2 Baddy Bad does NOT set Light Screen",
			not set_events.any(func(e): return e[1] == "light_screen"))


# C2.3: dispatch order/side check — confirms the screen lands on the SETTER's
# (attacker's) own side, never the target's side, using start_battle's own
# established side-index convention (first arg = side 0).
func _test_c2_screen_lands_on_attacker_side_not_target_side() -> void:
	var glitzy_glow := _load_move(683)
	var tackle := _load_move(33)
	var atk := _make_mon("C2SideAtk", TypeChart.TYPE_PSYCHIC)
	atk.add_move(glitzy_glow)
	var def := _make_mon("C2SideDef", TypeChart.TYPE_NORMAL)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var set_events := []
	bm.screen_set.connect(func(side, name_): set_events.append([side, name_]))
	bm.start_battle(atk, def)

	_chk("C2.3 screen_set fires with side == 0 (the attacker's own side), never side 1",
			set_events.size() > 0 and set_events.all(func(e): return e[0] == 0))


# C2.4: already-up no-refresh — reuses the exact TrySetReflect/TrySetLightScreen
# fail behavior the pure-status moves already have (move_effect_failed emitted,
# no duration refresh), confirmed reachable from the damage-dispatch path too.
func _test_c2_already_up_no_refresh() -> void:
	var glitzy_glow := _load_move(683)
	var tackle := _load_move(33)
	var atk := _make_mon("C2NRAtk", TypeChart.TYPE_PSYCHIC, 100, 60, 60, 60, 60, 100)
	atk.add_move(glitzy_glow)
	var def := _make_mon("C2NRDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	# Pre-set Light Screen already up on the attacker's own side (0).
	bm._side_conditions[0]["light_screen_turns"] = 5
	var failed_events := []
	bm.move_effect_failed.connect(func(m, reason): failed_events.append([m, reason]))
	bm.start_battle(atk, def)

	_chk("C2.4 move_effect_failed('already_light_screen') emitted when Light Screen " +
			"is already up on the setter's side",
			failed_events.any(func(e): return e[0] == atk and e[1] == "already_light_screen"))
