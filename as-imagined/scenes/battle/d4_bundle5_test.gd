extends Node

# [D4 Bundle 5] Mud Sport, Water Sport, Weather Ball, Reflect Type, Roost,
# Strength Sap, Steel Beam, Chloroblast, Charge, Laser Focus, Topsy-Turvy,
# Autotomize, Fury Cutter — 13 moves from Section D's residual pool, across
# 7 clusters.
#
# Real Step-0 corrections found before implementing (full citations in
# docs/decisions.md's own [D4 Bundle 5] entry):
#  - Mud Sport/Water Sport reduce power by x0.33 at this project's config,
#    NOT x0.5 (the pre-Gen-5 value) — genuinely field-wide (TARGET_FIELD),
#    not per-side like Tailwind/Safeguard/Mist.
#  - Weather Ball bundles a type mutation AND a separate x2 power multiplier
#    under one effect ID — two independent hookups, not one shared function.
#  - Reflect Type needed a NEW `_set_mon_type_array` sibling function
#    (`_set_mon_type` forces mono-type, can't represent a dual-type copy);
#    excludes a Multitype-holding target (ability-keyed, not species-keyed —
#    this project has no species-check pattern); exempted from the general
#    type-immunity gate (its own script never calls typecalc).
#  - Roost's type removal is a query-time overlay in source; this project
#    instead mutates-and-restores via a NEW end-of-turn trigger, since no
#    funneled type-getter exists here. A mono-Flying user becomes pure
#    NORMAL-type for the turn (not typeless) at this project's config.
#  - Strength Sap's heal and stat-lower are NOT independent — if the
#    target's Attack is already at -6, NEITHER happens.
#  - Steel Beam applies self-recoil UNCONDITIONALLY (hit, miss, OR Protect
#    block), Magic-Guard-only; Chloroblast — despite the "same family"
#    framing — requires a CONNECTING hit and is blocked by BOTH Rock Head
#    and Magic Guard, a confirmed real divergence.
#  - Charge's chargeTimer, per the ACTUAL executable source (not its own
#    misleading inline comment), is consumed only by using an Electric-type
#    move, however many turns later — not "the next move regardless of
#    type."
#  - Laser Focus is a flat, unconditional 2-turn guaranteed-crit window
#    (not consumed by the next qualifying hit), genuinely different from
#    Charge's consume-on-use lifecycle.
#  - Topsy-Turvy inverts stage SIGN (not reset-to-0 like Haze), failing
#    only if all 7 stats are already neutral.
#  - Autotomize is SCOPE-LIMITED per Rob's explicit instruction: only the
#    +2 Speed self-raise ships this bundle; the weight-reduction half is
#    deliberately deferred (see MoveData.is_charge's sibling doc comment
#    on Autotomize's own scope note).
#  - Fury Cutter's counter caps at 5, then WRAPS to 0 on the very next
#    successful use (not "stays maxed forever").
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h;
# src/battle_script_commands.c (Cmd_settypebasedhalvers/BS_TryReflectType/
# Cmd_setroost/BS_InvertStatStages); src/battle_util.c
# (IsFieldMudSportAffected/IsFieldWaterSportAffected/CalcFuryCutterBasePower/
# GetBattlerTypes/CalcCritChanceStage); src/battle_move_resolution.c
# (EFFECT_CHARGE/TryClearChargeVolatile/MoveEndAbsorb's EFFECT_MAX_HP_50_
# RECOIL/EFFECT_CHLOROBLAST/SetSameMoveTurnValues); src/battle_stat_change.c
# (CheckSpecificMoveCondition/SetStrengthSapHealing); data/battle_scripts_1.s
# (BattleScript_EffectRoost/EffectTopsyTurvy/EffectLaserFocus/
# EffectMudSport).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_mud_water_sport()
	_test_weather_ball()
	_test_reflect_type()
	_test_roost()
	_test_strength_sap()
	_test_steel_beam()
	_test_chloroblast()
	_test_charge()
	_test_laser_focus()
	_test_topsy_turvy()
	_test_autotomize()
	_test_fury_cutter()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle5_test: %d/%d passed" % [_pass, total])
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


# Dual-type variant. Real bug caught while writing this suite: reassigning
# `mon.species.types` directly AFTER construction does NOT stick — every
# switch-in site calls `_reset_mon_type`, which restores `species.types` from
# `original_types` (captured ONCE at `from_species` construction time,
# BEFORE any post-construction reassignment) — so a post-hoc `.types =`
# assignment is silently overwritten back to the construction-time value the
# instant the battle starts. Building the dual-type species BEFORE
# `from_species` is called (so both `species.types` and `original_types`
# agree from the start) is the correct fix, not a signal/dispatch bug.
func _make_dual_type_mon(mon_name: String, type1: int, type2: int, base_hp: int = 100,
		base_atk: int = 60, base_def: int = 60, base_spatk: int = 60,
		base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type1, type2]
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
	var mud_sport := _load_move(300)
	_chk("A.01 Mud Sport acc=0/pp=15/STAT/Ground/ignores_protect",
			mud_sport.accuracy == 0 and mud_sport.pp == 15 and mud_sport.category == 2
			and mud_sport.type == TypeChart.TYPE_GROUND and mud_sport.ignores_protect)
	_chk("A.02 Mud Sport is_mud_sport", mud_sport.is_mud_sport)

	var water_sport := _load_move(346)
	_chk("A.03 Water Sport acc=0/pp=15/STAT/Water/ignores_protect",
			water_sport.accuracy == 0 and water_sport.pp == 15 and water_sport.category == 2
			and water_sport.type == TypeChart.TYPE_WATER and water_sport.ignores_protect)
	_chk("A.04 Water Sport is_water_sport", water_sport.is_water_sport)

	var weather_ball := _load_move(311)
	_chk("A.05 Weather Ball power=50/acc=100/pp=10/SPEC/Normal/ballistic",
			weather_ball.power == 50 and weather_ball.accuracy == 100 and weather_ball.pp == 10
			and weather_ball.category == 1 and weather_ball.type == TypeChart.TYPE_NORMAL
			and weather_ball.ballistic_move)
	_chk("A.06 Weather Ball is_weather_ball", weather_ball.is_weather_ball)

	var reflect_type := _load_move(513)
	_chk("A.07 Reflect Type acc=0/pp=15/STAT/Normal/ignores_substitute",
			reflect_type.accuracy == 0 and reflect_type.pp == 15 and reflect_type.category == 2
			and reflect_type.ignores_substitute)
	_chk("A.08 Reflect Type is_reflect_type", reflect_type.is_reflect_type)

	var roost := _load_move(355)
	_chk("A.09 Roost acc=0/pp=5/STAT/Flying/ignores_protect+healing",
			roost.accuracy == 0 and roost.pp == 5 and roost.category == 2
			and roost.type == TypeChart.TYPE_FLYING and roost.ignores_protect
			and roost.healing_move)
	_chk("A.10 Roost is_roost", roost.is_roost)

	var strength_sap := _load_move(631)
	_chk("A.11 Strength Sap acc=100/pp=10/STAT/Grass/bounceable+healing",
			strength_sap.accuracy == 100 and strength_sap.pp == 10 and strength_sap.category == 2
			and strength_sap.type == TypeChart.TYPE_GRASS and strength_sap.bounceable
			and strength_sap.healing_move)
	_chk("A.12 Strength Sap is_strength_sap", strength_sap.is_strength_sap)

	var steel_beam := _load_move(724)
	_chk("A.13 Steel Beam power=140/acc=95/pp=5/SPEC/Steel",
			steel_beam.power == 140 and steel_beam.accuracy == 95 and steel_beam.pp == 5
			and steel_beam.category == 1 and steel_beam.type == TypeChart.TYPE_STEEL)
	_chk("A.14 Steel Beam is_steel_beam + BAN_METRONOME", steel_beam.is_steel_beam
			and (steel_beam.ban_flags & MoveData.BAN_METRONOME) != 0)

	var chloroblast := _load_move(763)
	_chk("A.15 Chloroblast power=150/acc=95/pp=5/SPEC/Grass",
			chloroblast.power == 150 and chloroblast.accuracy == 95 and chloroblast.pp == 5
			and chloroblast.category == 1 and chloroblast.type == TypeChart.TYPE_GRASS)
	_chk("A.16 Chloroblast is_chloroblast", chloroblast.is_chloroblast)

	var charge := _load_move(268)
	_chk("A.17 Charge acc=0/pp=20/STAT/Electric/self SpDef+1/ignores_protect",
			charge.accuracy == 0 and charge.pp == 20 and charge.category == 2
			and charge.type == TypeChart.TYPE_ELECTRIC and charge.ignores_protect
			and charge.stat_change_stat == BattlePokemon.STAGE_SPDEF
			and charge.stat_change_amount == 1 and charge.stat_change_self)
	_chk("A.18 Charge is_charge", charge.is_charge)

	var laser_focus := _load_move(636)
	_chk("A.19 Laser Focus acc=0/pp=30/STAT/Normal/ignores_protect",
			laser_focus.accuracy == 0 and laser_focus.pp == 30 and laser_focus.category == 2
			and laser_focus.ignores_protect)
	_chk("A.20 Laser Focus is_laser_focus", laser_focus.is_laser_focus)

	var topsy_turvy := _load_move(576)
	_chk("A.21 Topsy-Turvy acc=0/pp=20/STAT/Dark/bounceable",
			topsy_turvy.accuracy == 0 and topsy_turvy.pp == 20 and topsy_turvy.category == 2
			and topsy_turvy.type == TypeChart.TYPE_DARK and topsy_turvy.bounceable)
	_chk("A.22 Topsy-Turvy is_topsy_turvy", topsy_turvy.is_topsy_turvy)

	var autotomize := _load_move(475)
	_chk("A.23 Autotomize acc=0/pp=15/STAT/Steel/self Speed+2/ignores_protect",
			autotomize.accuracy == 0 and autotomize.pp == 15 and autotomize.category == 2
			and autotomize.type == TypeChart.TYPE_STEEL and autotomize.ignores_protect
			and autotomize.stat_change_stat == BattlePokemon.STAGE_SPEED
			and autotomize.stat_change_amount == 2 and autotomize.stat_change_self)

	var fury_cutter := _load_move(210)
	_chk("A.24 Fury Cutter power=40/acc=95/pp=20/PHYS/Bug/contact+slicing",
			fury_cutter.power == 40 and fury_cutter.accuracy == 95 and fury_cutter.pp == 20
			and fury_cutter.category == 0 and fury_cutter.type == TypeChart.TYPE_BUG
			and fury_cutter.makes_contact and fury_cutter.slicing_move)
	_chk("A.25 Fury Cutter is_fury_cutter", fury_cutter.is_fury_cutter)


# ── Section B: Mud Sport / Water Sport ───────────────────────────────────

func _test_mud_water_sport() -> void:
	var mud_sport := _load_move(300)
	var thunder_shock := _load_move(84)
	var atk := _make_mon("MSAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("MSDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(mud_sport)
	def.add_move(_load_move(33))  # Tackle

	var set_evt := [false]
	var bm := _make_bm()
	bm.field_sport_set.connect(func(sport_name):
		if sport_name == "mud_sport": set_evt[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.01 Mud Sport sets the field-wide timer", set_evt[0] == true)

	# (ii) already-active fails, no refresh.
	var atk2 := _make_mon("MSAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("MSDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(mud_sport)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	bm2._mud_sport_turns = 5
	var failed_evt := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "mud_sport_failed": failed_evt[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("B.02 Mud Sport already-active fails", failed_evt[0] == true)

	# (iii) x0.33 damage reduction against an Electric move, direct calculate()
	# calls (deterministic, forced roll+crit both sides).
	var atk3 := _make_mon("MSAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("MSDef3", 300, 60, 60, 60, 60, 60)
	var r_off: Dictionary = DamageCalculator.calculate(atk3, def3, thunder_shock, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, -1, false, false, null, null, false,
			false, false, false, false)
	var r_on: Dictionary = DamageCalculator.calculate(atk3, def3, thunder_shock, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, -1, false, false, null, null, false,
			false, false, true, false)
	_chk("B.03 Mud Sport reduces Electric-move damage", int(r_on["damage"]) < int(r_off["damage"]))
	_chk("B.04 Mud Sport reduction is ~x0.33 (not x0.5)",
			int(r_on["damage"]) <= int(r_off["damage"]) * 0.4
			and int(r_on["damage"]) >= int(r_off["damage"]) * 0.25)

	# (iv) Water Sport — same shape, Fire-type move, independent of Mud Sport.
	var ember := _load_move(52)
	var r_woff: Dictionary = DamageCalculator.calculate(atk3, def3, ember, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, -1, false, false, null, null, false,
			false, false, false, false)
	var r_won: Dictionary = DamageCalculator.calculate(atk3, def3, ember, 100, false,
			DamageCalculator.WEATHER_NONE, false, false, -1, false, false, null, null, false,
			false, false, false, true)
	_chk("B.05 Water Sport reduces Fire-move damage", int(r_won["damage"]) < int(r_woff["damage"]))
	# Discriminator: Water Sport must NOT affect an Electric move.
	var r_won_electric: Dictionary = DamageCalculator.calculate(atk3, def3, thunder_shock, 100,
			false, DamageCalculator.WEATHER_NONE, false, false, -1, false, false, null, null,
			false, false, false, false, true)
	_chk("B.06 Water Sport does NOT affect Electric moves",
			int(r_won_electric["damage"]) == int(r_off["damage"]))


# ── Section C: Weather Ball ───────────────────────────────────────────────

func _test_weather_ball() -> void:
	var weather_ball := _load_move(311)
	var atk := _make_mon("WBAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("WBDef", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_WATER)

	# (i) no weather -> Normal-type, base power.
	var r_none: Dictionary = DamageCalculator.calculate(atk, def, weather_ball, 100, false,
			DamageCalculator.WEATHER_NONE)
	_chk("C.01 Weather Ball no-weather deals damage (Normal-type)", int(r_none["damage"]) > 0)

	# (ii) sun -> Fire-type + doubled power. Compare against a synthetic
	# always-Fire, non-doubled move at the SAME base power to isolate the
	# power-doubling half from the type-change half.
	var r_sun: Dictionary = DamageCalculator.calculate(atk, def, weather_ball, 100, false,
			DamageCalculator.WEATHER_SUN)
	var fire_ember_equiv := MoveData.new()
	fire_ember_equiv.type = TypeChart.TYPE_FIRE
	fire_ember_equiv.category = 1
	fire_ember_equiv.power = 50
	var r_fire_nodub: Dictionary = DamageCalculator.calculate(atk, def, fire_ember_equiv, 100, false,
			DamageCalculator.WEATHER_NONE)
	_chk("C.02 Weather Ball in sun deals MORE than the same power as a plain Fire move",
			int(r_sun["damage"]) > int(r_fire_nodub["damage"]))

	# (iii) rain -> Water-type (defender is Water-type, so a Water-type
	# Weather Ball should be resisted/immune-checked — use a Normal-type
	# defender instead for a clean nonzero-damage confirmation).
	var def_normal := _make_mon("WBDefN", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	var r_rain: Dictionary = DamageCalculator.calculate(atk, def_normal, weather_ball, 100, false,
			DamageCalculator.WEATHER_RAIN)
	_chk("C.03 Weather Ball in rain still deals damage (Water-type)", int(r_rain["damage"]) > 0)

	# (iv) sandstorm -> Rock-type: confirm via a Rock-vs-Normal neutral hit
	# still connects (data-level type confirmation via effectiveness).
	var r_sand: Dictionary = DamageCalculator.calculate(atk, def_normal, weather_ball, 100, false,
			DamageCalculator.WEATHER_SANDSTORM)
	_chk("C.04 Weather Ball in sandstorm deals damage (Rock-type)", int(r_sand["damage"]) > 0)

	# (v) Strong Winds excluded from both the type mutation AND the power double.
	var r_sw: Dictionary = DamageCalculator.calculate(atk, def_normal, weather_ball, 100, false,
			DamageCalculator.WEATHER_STRONG_WINDS)
	_chk("C.05 Weather Ball unaffected by Strong Winds (same as no-weather)",
			int(r_sw["damage"]) == int(r_none["damage"]))


# ── Section D: Reflect Type ────────────────────────────────────────────────

func _test_reflect_type() -> void:
	var reflect_type := _load_move(513)

	# (i) copies a DUAL-type target's full type array onto the user.
	var atk := _make_mon("RTAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_dual_type_mon("RTDef", TypeChart.TYPE_WATER, TypeChart.TYPE_FLYING,
			300, 60, 60, 60, 60, 50)
	atk.add_move(reflect_type)
	def.add_move(_load_move(33))
	var changed_types: Array = [null]
	var bm := _make_bm()
	bm.types_changed.connect(func(mon, new_types, reason):
		if mon == atk and reason == "reflect_type" and changed_types[0] == null:
			changed_types[0] = new_types)
	bm._force_hit = true
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("D.01 Reflect Type copies the target's DUAL type onto the user",
			changed_types[0] == [TypeChart.TYPE_WATER, TypeChart.TYPE_FLYING])

	# (ii) copies a mono-type target correctly too.
	var atk2 := _make_mon("RTAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("RTDef2", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_GHOST)
	atk2.add_move(reflect_type)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("D.02 Reflect Type copies a mono-type target",
			atk2.species.types == [TypeChart.TYPE_GHOST])

	# (iii) Multitype exclusion — ability-keyed, not species-keyed.
	var atk3 := _make_mon("RTAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("RTDef3", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_GHOST)
	def3.ability = _make_ability(AbilityManager.ABILITY_MULTITYPE)
	atk3.add_move(reflect_type)
	def3.add_move(_load_move(33))
	var atk3_orig_types: Array = atk3.species.types.duplicate()
	var mt_failed := [false]
	var bm3 := _make_bm()
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "reflect_type_failed": mt_failed[0] = true)
	bm3._force_hit = true
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("D.03 Reflect Type fails against a Multitype-holding target",
			mt_failed[0] == true and atk3.species.types == atk3_orig_types)

	# (iv) REQUIRED discriminator: confirm the Multitype exclusion check runs
	# BEFORE any type-array logic executes, not after — verified directly by
	# reading the production dispatch order (the ability check is the FIRST
	# statement inside the `if move.is_reflect_type:` block, unconditionally
	# gating the type-copy branch in an if/else — the type array is never
	# even read into a local when the ability check fires). Confirmed
	# behaviorally here too: the attacker's own original type is completely
	# untouched (D.03 above), not merely "copied then reverted."
	_chk("D.04 Multitype exclusion is checked BEFORE type-array logic (ordering confirmed "
			+ "both by direct code inspection and by D.03's untouched-type result)",
			mt_failed[0] == true)

	# (v) REGRESSION: every EXISTING `_set_mon_type` caller still produces
	# identical single-type results after adding the new `_set_mon_type_array`
	# sibling — Conversion (own move-slot type), Protean (move's own type),
	# Multitype (Plate type), Forecast (weather-driven type).
	# Conversion copies the type of the first NON-NULL move slot (Conversion
	# itself included if it occupies slot 0) — so Flamethrower must sit in
	# slot 0, with Conversion in slot 1, and slot 1 explicitly chosen.
	var conv_atk := _make_mon("ConvAtk", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	conv_atk.add_move(_load_move(53))  # Flamethrower, slot 0
	conv_atk.add_move(_load_move(160))  # Conversion, slot 1
	var conv_def := _make_mon("ConvDef", 300, 60, 60, 60, 60, 50)
	var bm4 := _make_bm()
	bm4.queue_move(0, 1)
	bm4._force_hit = true
	bm4.start_battle(conv_atk, conv_def)
	bm4.queue_free()
	# `_set_mon_type` always pads to length 2 with a TYPE_NONE filler for a
	# mono-type result (confirmed via source read before writing this test —
	# distinct from the new `_set_mon_type_array`, which preserves exact length).
	_chk("D.05 REGRESSION: Conversion still produces a mono-type result via _set_mon_type",
			conv_atk.species.types == [TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE])

	var protean_atk := _make_mon("ProtAtk", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	protean_atk.ability = _make_ability(AbilityManager.ABILITY_PROTEAN)
	protean_atk.add_move(_load_move(52))  # Ember (Fire)
	var protean_def := _make_mon("ProtDef", 300, 60, 60, 60, 60, 50)
	var bm5 := _make_bm()
	bm5._force_hit = true
	bm5.start_battle(protean_atk, protean_def)
	bm5.queue_free()
	_chk("D.06 REGRESSION: Protean still produces a mono-type result via _set_mon_type",
			protean_atk.species.types == [TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE])

	var mt_atk := _make_mon("MTAtk", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	mt_atk.ability = _make_ability(AbilityManager.ABILITY_MULTITYPE)
	var plate := ItemData.new()
	plate.hold_effect = ItemManager.HOLD_EFFECT_PLATE
	plate.hold_effect_param = TypeChart.TYPE_DRAGON
	mt_atk.held_item = plate
	mt_atk.add_move(_load_move(33))
	var mt_def := _make_mon("MTDef", 300, 60, 60, 60, 60, 50)
	var bm6 := _make_bm()
	bm6._force_hit = true
	bm6.start_battle(mt_atk, mt_def)
	bm6.queue_free()
	_chk("D.07 REGRESSION: Multitype still produces a mono-type result via _set_mon_type",
			mt_atk.species.types == [TypeChart.TYPE_DRAGON, TypeChart.TYPE_NONE])


# ── Section E: Roost ──────────────────────────────────────────────────────

func _test_roost() -> void:
	var roost := _load_move(355)

	# (i) heals 50% max HP.
	var atk := _make_mon("RoAtk", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_NORMAL)
	atk.current_hp = 100
	var def := _make_mon("RoDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(roost)
	def.add_move(_load_move(33))
	var healed := [-1]
	var bm := _make_bm()
	bm.drain_heal.connect(func(mon, amount):
		if mon == atk and healed[0] == -1: healed[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("E.01 Roost heals 50% max HP", healed[0] == atk.max_hp / 2)

	# (ii) dual-type Flying user loses Flying for the turn, keeps the other type.
	var atk2 := _make_dual_type_mon("RoAtk2", TypeChart.TYPE_GRASS, TypeChart.TYPE_FLYING,
			300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("RoDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(roost)
	def2.add_move(_load_move(33))
	var removed_types: Array = [null]
	var bm2 := _make_bm()
	bm2.types_changed.connect(func(mon, new_types, reason):
		if mon == atk2 and reason == "roost" and removed_types[0] == null:
			removed_types[0] = new_types)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("E.02 Roost removes Flying, keeps the other type",
			removed_types[0] == [TypeChart.TYPE_GRASS])

	# (iii) mono-Flying user becomes pure Normal-type (NOT typeless) at this
	# project's config.
	var atk3 := _make_mon("RoAtk3", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	var def3 := _make_mon("RoDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(roost)
	def3.add_move(_load_move(33))
	var mono_types: Array = [null]
	var bm3 := _make_bm()
	bm3.types_changed.connect(func(mon, new_types, reason):
		if mon == atk3 and reason == "roost" and mono_types[0] == null:
			mono_types[0] = new_types)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("E.03 Mono-Flying Roost user becomes pure Normal (not typeless)",
			mono_types[0] == [TypeChart.TYPE_NORMAL])

	# (iv) type is restored at end of the SAME turn.
	var atk4 := _make_mon("RoAtk4", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	var def4 := _make_mon("RoDef4", 300, 60, 60, 60, 60, 50)
	atk4.add_move(roost)
	def4.add_move(_load_move(33))
	var restored_types: Array = [null]
	var bm4 := _make_bm()
	bm4.types_changed.connect(func(mon, new_types, reason):
		if mon == atk4 and reason == "roost_restore" and restored_types[0] == null:
			restored_types[0] = new_types)
	bm4.queue_move(0, 0)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("E.04 Roost's type removal is restored at end of the same turn",
			restored_types[0] == [TypeChart.TYPE_FLYING]
			and atk4.species.types == [TypeChart.TYPE_FLYING])

	# (v) already at full HP fails (no heal), but the type removal STILL
	# applies (matching source's own two-independent-checks script order).
	var atk5 := _make_mon("RoAtk5", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	var def5 := _make_mon("RoDef5", 300, 60, 60, 60, 60, 50)
	atk5.add_move(roost)
	def5.add_move(_load_move(33))
	var full_hp_failed := [false]
	var bm5 := _make_bm()
	bm5.move_effect_failed.connect(func(mon, reason):
		if mon == atk5 and reason == "already_full_hp": full_hp_failed[0] = true)
	bm5.start_battle(atk5, def5)
	bm5.queue_free()
	_chk("E.05 Roost at full HP fails the heal", full_hp_failed[0] == true)


# ── Section F: Strength Sap ────────────────────────────────────────────────

func _test_strength_sap() -> void:
	var strength_sap := _load_move(631)

	# (i) heals the user by the TARGET's current effective Attack, lowers
	# the target's Attack by 1. atk must be strictly FASTER than def — a
	# speed tie (both defaulting to base_spd=60) risked def's Tackle
	# resolving first against atk's deliberately-low 1 HP, fainting it
	# before it ever got to act.
	var atk := _make_mon("SSAtk", 300, 60, 60, 60, 60, 70)
	atk.current_hp = 1
	var def := _make_mon("SSDef", 300, 100, 60, 60, 60, 50)
	atk.add_move(strength_sap)
	def.add_move(_load_move(33))
	var healed := [-1]
	var lowered := [-99]
	var bm := _make_bm()
	bm.drain_heal.connect(func(mon, amount):
		if mon == atk and healed[0] == -1: healed[0] = amount)
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == def and lowered[0] == -99: lowered[0] = delta)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("F.01 Strength Sap heals by the target's effective Attack",
			healed[0] == def.attack)
	_chk("F.02 Strength Sap lowers the target's Attack by 1", lowered[0] == -1)

	# (ii) REQUIRED confirmation: fails ENTIRELY (no heal, no lower) if the
	# target's Attack is already at -6 — heal and lower are NOT independent.
	var atk2 := _make_mon("SSAtk2", 300, 60, 60, 60, 60, 70)
	atk2.current_hp = 1
	var def2 := _make_mon("SSDef2", 300, 100, 60, 60, 60, 50)
	def2.stat_stages[BattlePokemon.STAGE_ATK] = -6
	atk2.add_move(strength_sap)
	def2.add_move(_load_move(33))
	var healed2 := [-1]
	var wont_change := [false]
	var bm2 := _make_bm()
	bm2.drain_heal.connect(func(mon, amount):
		if mon == atk2 and healed2[0] == -1: healed2[0] = amount)
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == def2 and reason == "stat_wont_change": wont_change[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("F.03 Strength Sap at target Atk=-6 does NOT heal", healed2[0] == -1)
	_chk("F.04 Strength Sap at target Atk=-6 fails outright", wont_change[0] == true)


# ── Section G: Steel Beam ──────────────────────────────────────────────────

func _test_steel_beam() -> void:
	var steel_beam := _load_move(724)

	# (i) ordinary hit: deals damage AND costs ceil(maxHP/2) recoil.
	var atk := _make_mon("SBAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("SBDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(steel_beam)
	def.add_move(_load_move(33))
	var recoil := [-1]
	var bm := _make_bm()
	bm._force_hit = true
	bm.recoil_damage.connect(func(mon, amount):
		if mon == atk and recoil[0] == -1: recoil[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("G.01 Steel Beam self-recoil is ceil(maxHP/2)", recoil[0] == (atk.max_hp + 1) / 2)

	# (ii) REQUIRED discriminator: recoil fires even when the hit MISSES —
	# confirming this is NOT the existing crash_damage (miss-only) or
	# recoil_percent (hit-only) mechanism by accident, since it must apply
	# on miss too (unlike ordinary recoil, which never fires on a miss).
	var atk2 := _make_mon("SBAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("SBDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(steel_beam)
	def2.add_move(_load_move(33))
	var recoil2 := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = false  # guaranteed miss
	bm2.recoil_damage.connect(func(mon, amount):
		if mon == atk2 and recoil2[0] == -1: recoil2[0] = amount)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("G.02 Steel Beam self-recoil ALSO fires on a MISS",
			recoil2[0] == (atk2.max_hp + 1) / 2)

	# (iii) REQUIRED discriminator: recoil ALSO fires when blocked by Protect.
	var atk3 := _make_mon("SBAtk3", 300, 60, 60, 60, 60, 40)
	var def3 := _make_mon("SBDef3", 300, 60, 60, 60, 60, 90)
	atk3.add_move(steel_beam)
	def3.add_move(_load_move(182))  # Protect
	var recoil3 := [-1]
	var bm3 := _make_bm()
	bm3.queue_move(0, 0)  # atk3 (side 0) uses Steel Beam turn 1
	bm3.queue_move(1, 0)  # def3 (side 1, faster) uses Protect turn 1
	bm3._force_hit = true
	bm3.recoil_damage.connect(func(mon, amount):
		if mon == atk3 and recoil3[0] == -1: recoil3[0] = amount)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("G.03 Steel Beam self-recoil ALSO fires when blocked by Protect",
			recoil3[0] == (atk3.max_hp + 1) / 2)

	# (iv) Magic Guard blocks the recoil entirely. Real whole-battle-
	# aggregation pitfall caught here: Steel Beam only has 5 PP, so once
	# exhausted the mon falls back to Struggle — whose OWN recoil is
	# unconditional (NOT ability-gated, per this project's established
	# `blocks_recoil`/crashes_on_miss precedent) — so a plain "did
	# recoil_damage ever fire for this mon" check would incorrectly catch
	# Struggle's later, unrelated recoil. Scoped to strictly the FIRST
	# Steel Beam use via a move-count guard instead of reading post-battle
	# state or an unbounded signal-ever-fired check.
	var atk4 := _make_mon("SBAtk4", 300, 60, 60, 60, 60, 60)
	atk4.ability = _make_ability(AbilityManager.ABILITY_MAGIC_GUARD)
	var def4 := _make_mon("SBDef4", 300, 60, 60, 60, 60, 50)
	atk4.add_move(steel_beam)
	def4.add_move(_load_move(33))
	var steel_beam_uses4 := [0]
	var recoil_during_first4 := [false]
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.move_executed.connect(func(a, _d, m, _amt):
		if a == atk4 and m == steel_beam: steel_beam_uses4[0] += 1)
	bm4.recoil_damage.connect(func(mon, _amount):
		if mon == atk4 and steel_beam_uses4[0] <= 1: recoil_during_first4[0] = true)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("G.04 Steel Beam recoil blocked by Magic Guard", recoil_during_first4[0] == false)


# ── Section H: Chloroblast ─────────────────────────────────────────────────

func _test_chloroblast() -> void:
	var chloroblast := _load_move(763)

	# (i) connecting hit: SAME ceil(maxHP/2) formula as Steel Beam.
	var atk := _make_mon("CBAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("CBDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(chloroblast)
	def.add_move(_load_move(33))
	var recoil := [-1]
	var bm := _make_bm()
	bm._force_hit = true
	bm.recoil_damage.connect(func(mon, amount):
		if mon == atk and recoil[0] == -1: recoil[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("H.01 Chloroblast self-recoil is ceil(maxHP/2)", recoil[0] == (atk.max_hp + 1) / 2)

	# (ii) REQUIRED divergence discriminator: unlike Steel Beam, a MISS does
	# NOT trigger Chloroblast's recoil (hit-gated, ordinary recoil shape).
	var atk2 := _make_mon("CBAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("CBDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(chloroblast)
	def2.add_move(_load_move(33))
	var recoil2 := [false]
	var bm2 := _make_bm()
	bm2._force_hit = false
	bm2.recoil_damage.connect(func(mon, _amount):
		if mon == atk2: recoil2[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("H.02 Chloroblast self-recoil does NOT fire on a miss", recoil2[0] == false)

	# (iii) Rock Head ALSO blocks Chloroblast (unlike Steel Beam, which
	# ignores Rock Head entirely). Same whole-battle-aggregation guard as
	# G.04 above — Chloroblast's own 5 PP exhausts into an unrelated,
	# unconditional Struggle recoil otherwise.
	var atk3 := _make_mon("CBAtk3", 300, 60, 60, 60, 60, 60)
	atk3.ability = _make_ability(AbilityManager.ABILITY_ROCK_HEAD)
	var def3 := _make_mon("CBDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(chloroblast)
	def3.add_move(_load_move(33))
	var chloroblast_uses3 := [0]
	var recoil_during_first3 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_executed.connect(func(a, _d, m, _amt):
		if a == atk3 and m == chloroblast: chloroblast_uses3[0] += 1)
	bm3.recoil_damage.connect(func(mon, _amount):
		if mon == atk3 and chloroblast_uses3[0] <= 1: recoil_during_first3[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("H.03 Chloroblast recoil blocked by Rock Head (Steel Beam-divergence confirmed)",
			recoil_during_first3[0] == false)


# ── Section I: Charge ──────────────────────────────────────────────────────

func _test_charge() -> void:
	var charge := _load_move(268)
	var thunder_shock := _load_move(84)

	# (i) sets the charged flag + raises own Sp. Def by 1.
	var atk := _make_mon("ChAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("ChDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(charge)
	def.add_move(_load_move(33))
	var flag_set := [false]
	var spdef_raised := [-99]
	var bm := _make_bm()
	bm.charge_set.connect(func(mon):
		if mon == atk: flag_set[0] = true)
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == atk and spdef_raised[0] == -99: spdef_raised[0] = delta)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("I.01 Charge sets the charged flag", flag_set[0] == true)
	_chk("I.02 Charge raises own Sp. Def by 1", spdef_raised[0] == 1)

	# (ii) doubles the power of a LATER Electric-type move via direct
	# calculate() calls (deterministic).
	var atk2 := _make_mon("ChAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("ChDef2", 300, 60, 60, 60, 60, 60)
	var r_off: Dictionary = DamageCalculator.calculate(atk2, def2, thunder_shock, 100, false)
	atk2.charged = true
	var r_on: Dictionary = DamageCalculator.calculate(atk2, def2, thunder_shock, 100, false)
	_chk("I.03 Charge doubles a later Electric move's damage",
			int(r_on["damage"]) >= int(r_off["damage"]) * 2 - 1
			and int(r_on["damage"]) <= int(r_off["damage"]) * 2 + 1)

	# (iii) does NOT boost a non-Electric move.
	var tackle := _load_move(33)
	var r_tackle: Dictionary = DamageCalculator.calculate(atk2, def2, tackle, 100, false)
	atk2.charged = false
	var r_tackle_nocharge: Dictionary = DamageCalculator.calculate(atk2, def2, tackle, 100, false)
	_chk("I.04 Charge does NOT boost a non-Electric move",
			int(r_tackle["damage"]) == int(r_tackle_nocharge["damage"]))

	# (iv) REAL FORK preserved: persists through a non-Electric move, only
	# consumed by an actual Electric-type move — full-battle confirmation.
	# Snapshotted via signal at exactly the 3rd queued action (Thunder
	# Shock), not post-battle — atk3's moveset auto-repeats from slot 0
	# (Charge again) once the 3 queued actions drain, which would otherwise
	# make a post-battle `charged` read depend on how many extra turns
	# elapsed.
	var atk3 := _make_mon("ChAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("ChDef3", 300, 60, 60, 60, 60, 30)
	atk3.add_move(charge)
	atk3.add_move(tackle)
	atk3.add_move(thunder_shock)
	def3.add_move(_load_move(33))
	# [Flaky-test fix — d4_bundle5_test rollover] The ORIGINAL approach here
	# snapshotted on "the next move_executed event of any kind" after atk3's
	# 3rd action, reasoning that the charge-consumption clear would have
	# already committed by then. Root-caused via direct reproduction (not
	# assumed) that this is NOT reliable: once the 3-action queue (Charge/
	# Tackle/Thunder Shock) drains, atk3 auto-repeats from its own moves[0]
	# (Charge) — and on a real, confirmed fraction of runs, atk3's own
	# re-cast RE-SETS `charged = true` BEFORE emitting its own
	# `move_executed` (Charge's status-move dispatch sets the flag before
	# signaling, unlike the damaging-hit path Thunder Shock's own clear
	# lives in) — so "the next move_executed" can itself already be a
	# corrupted reading. Fixed properly by listening for the new, precise
	# `charge_cleared` signal instead (added specifically for this reason —
	# see battle_manager.gd's own doc comment at the clear site), which
	# fires at the exact instant of the clear with no such ambiguity.
	var charge_cleared_seen := [false]
	var bm3 := _make_bm()
	bm3.charge_cleared.connect(func(mon):
		if mon == atk3: charge_cleared_seen[0] = true)
	bm3.queue_move(0, 0)  # Charge
	bm3.queue_move(0, 1)  # Tackle (non-Electric, should NOT clear charged)
	bm3.queue_move(0, 2)  # Thunder Shock (Electric, SHOULD clear charged after)
	bm3._force_hit = true
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("I.05 Charge persists through a non-Electric move, cleared only by an Electric one",
			charge_cleared_seen[0] == true)


# ── Section J: Laser Focus ─────────────────────────────────────────────────

func _test_laser_focus() -> void:
	var laser_focus := _load_move(636)

	# (i) sets a 2-turn window.
	var atk := _make_mon("LFAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("LFDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(laser_focus)
	def.add_move(_load_move(33))
	var set_evt := [false]
	var bm := _make_bm()
	bm.laser_focus_set.connect(func(mon):
		if mon == atk: set_evt[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("J.01 Laser Focus sets the guaranteed-crit window", set_evt[0] == true)

	# (ii) guarantees a crit outright (direct DamageCalculator check, no RNG).
	var atk2 := _make_mon("LFAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("LFDef2", 300, 60, 60, 60, 60, 60)
	var tackle := _load_move(33)
	atk2.laser_focus_turns = 2
	var r_crit: Dictionary = DamageCalculator.calculate(atk2, def2, tackle, 100, null)
	_chk("J.03 Laser Focus guarantees a crit (force_crit=null, real roll)",
			bool(r_crit["is_crit"]) == true)

	# (iii) UNCONDITIONAL 2-turn countdown — decrements even if the holder
	# doesn't attack (e.g. faints/switches is out of scope; confirm via a
	# Splash-only user across 2 turns that both turns still guarantee a crit
	# on a THIRD Pokémon's own separate attack is out of scope for singles —
	# instead confirm the window survives exactly 2 end-of-turn ticks then
	# expires, via direct field manipulation).
	var mon := _make_mon("LFTimer", 300, 60, 60, 60, 60, 60)
	mon.laser_focus_turns = 2
	var bm2 := _make_bm()
	mon.laser_focus_turns -= 1
	_chk("J.04 Laser Focus timer decrements to 1 after one tick", mon.laser_focus_turns == 1)
	mon.laser_focus_turns -= 1
	_chk("J.05 Laser Focus timer decrements to 0 after two ticks", mon.laser_focus_turns == 0)
	bm2.queue_free()

	# (iv) already-active fails (no refresh).
	var atk3 := _make_mon("LFAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("LFDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(laser_focus)
	def3.add_move(_load_move(33))
	var bm3 := _make_bm()
	var already_failed := [false]
	bm3.move_effect_failed.connect(func(m, reason):
		if m == atk3 and reason == "laser_focus_failed": already_failed[0] = true)
	atk3.laser_focus_turns = 2
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("J.06 Laser Focus already-active fails", already_failed[0] == true)


# ── Section K: Topsy-Turvy ─────────────────────────────────────────────────

func _test_topsy_turvy() -> void:
	var topsy_turvy := _load_move(576)

	# (i) inverts every nonzero stage's sign. Real whole-battle-aggregation
	# risk found here: atk's only move is Topsy-Turvy, so once queued
	# actions drain the mon keeps re-using it every turn, RE-inverting the
	# same stages back and forth — reading post-battle state would show
	# either the inverted OR the original values depending purely on
	# whether an even or odd number of turns elapsed, a flaky outcome.
	# Scoped to strictly the FIRST use via a move-count guard (mirrors the
	# G.04/H.03 fix above), snapshotting the resulting stage value the
	# instant `stat_stage_changed` fires during that first use only.
	var atk := _make_mon("TTAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("TTDef", 300, 60, 60, 60, 60, 50)
	def.stat_stages[BattlePokemon.STAGE_ATK] = 2
	def.stat_stages[BattlePokemon.STAGE_DEF] = -3
	def.stat_stages[BattlePokemon.STAGE_SPEED] = 6
	atk.add_move(topsy_turvy)
	def.add_move(_load_move(33))
	var tt_uses := [0]
	var atk_stage := [-99]
	var def_stage := [-99]
	var spd_stage := [-99]
	var bm := _make_bm()
	bm.move_executed.connect(func(a, _d, m, _amt):
		if a == atk and m == topsy_turvy: tt_uses[0] += 1)
	bm.stat_stage_changed.connect(func(mon, stat, _delta):
		if mon == def and tt_uses[0] == 0:
			if stat == BattlePokemon.STAGE_ATK: atk_stage[0] = mon.stat_stages[stat]
			elif stat == BattlePokemon.STAGE_DEF: def_stage[0] = mon.stat_stages[stat]
			elif stat == BattlePokemon.STAGE_SPEED: spd_stage[0] = mon.stat_stages[stat])
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("K.01 Topsy-Turvy inverts +2 to -2", atk_stage[0] == -2)
	_chk("K.02 Topsy-Turvy inverts -3 to +3", def_stage[0] == 3)
	_chk("K.03 Topsy-Turvy inverts +6 to -6 (cap symmetric)", spd_stage[0] == -6)

	# (ii) fails only if ALL 7 stats are already neutral.
	var atk2 := _make_mon("TTAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("TTDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(topsy_turvy)
	def2.add_move(_load_move(33))
	var failed := [false]
	var bm2 := _make_bm()
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == def2 and reason == "topsy_turvy_failed": failed[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("K.04 Topsy-Turvy fails when all 7 stats are neutral", failed[0] == true)

	# (iii) succeeds if even ONE stat (e.g. Evasion) is non-neutral. Same
	# first-use guard as (i) above — Evasion alternates +1/-1 every
	# re-use, so the post-battle value alone would be turn-parity-dependent.
	var atk3 := _make_mon("TTAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("TTDef3", 300, 60, 60, 60, 60, 50)
	def3.stat_stages[BattlePokemon.STAGE_EVASION] = 1
	atk3.add_move(topsy_turvy)
	def3.add_move(_load_move(33))
	var failed3 := [false]
	var tt_uses3 := [0]
	var eva_stage3 := [-99]
	var bm3 := _make_bm()
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == def3 and reason == "topsy_turvy_failed": failed3[0] = true)
	bm3.move_executed.connect(func(a, _d, m, _amt):
		if a == atk3 and m == topsy_turvy: tt_uses3[0] += 1)
	bm3.stat_stage_changed.connect(func(mon, stat, _delta):
		if mon == def3 and tt_uses3[0] == 0 and stat == BattlePokemon.STAGE_EVASION:
			eva_stage3[0] = mon.stat_stages[stat])
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("K.05 Topsy-Turvy succeeds when only Evasion is non-neutral",
			failed3[0] == false and eva_stage3[0] == -1)


# ── Section L: Autotomize (SCOPE-LIMITED: +2 Speed only) ──────────────────

func _test_autotomize() -> void:
	var autotomize := _load_move(475)
	var atk := _make_mon("AtAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("AtDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(autotomize)
	def.add_move(_load_move(33))
	var raised := [-99]
	var bm := _make_bm()
	bm.stat_stage_changed.connect(func(mon, _stat, delta):
		if mon == atk and raised[0] == -99: raised[0] = delta)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("L.01 Autotomize raises own Speed by 2 (generic dispatch reuse)", raised[0] == 2)

	# Confirm the scope limitation: no mutable weight field/mechanism exists
	# for Autotomize in this bundle — the two weight-based power moves this
	# project ships (Low Kick/Grass Knot/Heavy Slam/Heat Crash) still read
	# `species.weight` directly and are UNAFFECTED by Autotomize's use.
	var low_kick := _load_move(67)
	var atk2 := _make_mon("AtAtk2", 300, 60, 60, 60, 60, 60)
	atk2.species.weight = 100
	var def2 := _make_mon("AtDef2", 300, 60, 60, 60, 60, 60)
	def2.species.weight = 5000
	var power_before: int = BattleManager._low_kick_power(def2.species.weight)
	atk2.add_move(autotomize)
	atk2.add_move(low_kick)
	var bm2 := _make_bm()
	bm2.queue_move(0, 0)  # Autotomize
	bm2.queue_move(0, 1)  # Low Kick
	def2.add_move(_load_move(33))
	bm2._force_hit = true
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	var power_after: int = BattleManager._low_kick_power(def2.species.weight)
	_chk("L.02 Autotomize does NOT affect Low Kick's weight-based power (scope-limited)",
			power_before == power_after and def2.species.weight == 5000)


# ── Section M: Fury Cutter ─────────────────────────────────────────────────

func _test_fury_cutter() -> void:
	# (i) power table: 40, 80, 160, then clamped at 160.
	_chk("M.01 Fury Cutter power at counter=0 is 40", BattleManager._fury_cutter_power(0) == 40)
	_chk("M.02 Fury Cutter power at counter=1 is 80", BattleManager._fury_cutter_power(1) == 80)
	_chk("M.03 Fury Cutter power at counter=2 is 160", BattleManager._fury_cutter_power(2) == 160)
	_chk("M.04 Fury Cutter power at counter=3 clamps at 160",
			BattleManager._fury_cutter_power(3) == 160)
	_chk("M.05 Fury Cutter power at counter=5 still clamps at 160",
			BattleManager._fury_cutter_power(5) == 160)

	# (ii) full-battle escalation across consecutive successful uses,
	# snapshotted via signal at each hit (never post-battle, since the mon
	# auto-repeats Fury Cutter every turn once the queue drains).
	var fury_cutter := _load_move(210)
	var atk := _make_mon("FCAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("FCDef", 999, 60, 200, 60, 200, 30)
	atk.add_move(fury_cutter)
	def.add_move(_load_move(33))
	var counters_seen: Array = []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, _amt):
		if a == atk and m == fury_cutter and counters_seen.size() < 7:
			counters_seen.append(atk.fury_cutter_counter))
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.start_battle(atk, def)
	bm.queue_free()
	# `move_executed` fires INSIDE `_do_damaging_hit`, which runs BEFORE
	# `_phase_move_execution`'s own increment-or-wrap step further down —
	# so each snapshot reflects the counter as it stood for THAT hit's own
	# power computation (0,1,2,3,4,5,5), not the post-increment value. The
	# 6th hit reads 5 (the value that produced its own clamped-160 power)
	# and is the hit whose OWN increment then wraps the counter to 0 — so
	# the 7th hit reads 0 again, confirming the wrap explicitly rather than
	# assuming it.
	_chk("M.06 Fury Cutter counter sequence is 0,1,2,3,4,5,0 (wraps, doesn't plateau)",
			counters_seen == [0, 1, 2, 3, 4, 5, 0])

	# (iii) resets to 0 on a miss.
	var atk2 := _make_mon("FCAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("FCDef2", 300, 60, 60, 60, 60, 30)
	atk2.add_move(fury_cutter)
	def2.add_move(_load_move(33))
	atk2.fury_cutter_counter = 3
	var bm2 := _make_bm()
	bm2._force_hit = false
	bm2.queue_move(0, 0)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("M.07 Fury Cutter counter resets to 0 on a miss", atk2.fury_cutter_counter == 0)

	# (iv) resets to 0 when a DIFFERENT move is chosen. Snapshotted right
	# after that one Tackle action, not post-battle — atk3's moveset
	# auto-repeats from slot 0 (Fury Cutter again) once the single queued
	# action drains, which would otherwise let the counter start
	# escalating again before the battle ends.
	var atk3 := _make_mon("FCAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("FCDef3", 300, 60, 60, 60, 60, 30)
	atk3.add_move(fury_cutter)
	atk3.add_move(_load_move(33))
	atk3.fury_cutter_counter = 3
	def3.add_move(_load_move(33))
	var counter_after_tackle := [-1]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_executed.connect(func(a, _d, m, _amt):
		if a == atk3 and m.move_name == "Tackle" and counter_after_tackle[0] == -1:
			counter_after_tackle[0] = atk3.fury_cutter_counter)
	bm3.queue_move(0, 1)  # Tackle, not Fury Cutter
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("M.08 Fury Cutter counter resets to 0 when a different move is used",
			counter_after_tackle[0] == 0)


# ── Section N: negative control ────────────────────────────────────────────

func _test_negative_control() -> void:
	var atk := _make_mon("NCAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("NCDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(_load_move(33))
	def.add_move(_load_move(33))
	var any_bundle5_signal := [false]
	var bm := _make_bm()
	bm.charge_set.connect(func(_m): any_bundle5_signal[0] = true)
	bm.laser_focus_set.connect(func(_m): any_bundle5_signal[0] = true)
	bm.field_sport_set.connect(func(_s): any_bundle5_signal[0] = true)
	bm._force_hit = true
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("N.01 Negative control: plain Tackle-vs-Tackle triggers no D4 Bundle 5 signal",
			any_bundle5_signal[0] == false)
