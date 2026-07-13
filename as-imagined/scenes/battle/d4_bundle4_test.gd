extends Node

# [D4 Bundle 4] Tailwind, Sticky Web, Safeguard, Mist, Copycat, Me First,
# Assist, Heal Pulse, Life Dew, Stockpile, Spit Up, Swallow — 12 moves from
# Section D's residual pool, across 4 clusters.
#
# Real Step-0 corrections found before implementing (full citations in
# docs/decisions.md's own [D4 Bundle 4] entry):
#  - Sticky Web's own -1 Speed switch-in effect routes through the FULL
#    generic stat-change pipeline (Defiant/Competitive/Mirror Armor/
#    Opportunist/Mirror Herb all react to it), NOT a raw hazard tick like
#    Spikes/Toxic Spikes/Stealth Rock.
#  - Mist/Safeguard both bypass an opposing Infiltrator holder — a real,
#    previously-anticipated-but-unwired extension of
#    AbilityManager.bypasses_infiltrator_barriers.
#  - Me First needs NO turn-order pre-emption at all — confirmed via direct
#    source read (GetMeFirstMove) it's a passive "has the target already
#    acted" check, reusing the existing _has_target_already_acted primitive.
#  - Copycat's own "last move used by anyone" tracker
#    (_last_landed_move_anyone) is genuinely distinct from the existing
#    per-mon `last_move_used` (gated on the move actually LANDING, not
#    merely being attempted) — a disclosed simplification: only ordinary
#    damaging hits update it (this project has no single dispatch
#    chokepoint every status-move effect passes through).
#  - Heal Pulse's Mega Launcher boost (75% vs 50%) is a hardcoded special
#    case inside the heal calc itself, not the generic pulse-move damage
#    multiplier.
#  - Stockpile's own `stockpile_count` (scaling counter, always increments)
#    and `stockpile_def_added`/`stockpile_spdef_added` (only the ACTUAL
#    stat rise, 0 if capped or Contrary-inverted) are genuinely separate
#    trackers — release removes exactly the tracked amount via a RAW,
#    ungated stat decrease, and fires even when Swallow's own heal "fails"
#    at full HP.
#  - Populated BAN_COPYCAT/BAN_ME_FIRST/BAN_ASSIST across 22 already-
#    implemented moves that needed them per source (many — Struggle, Sleep
#    Talk, Helping Hand, Feint, Shadow Force, Phantom Force, Follow Me,
#    Rage Powder, Thief, Covet — already had them correctly from earlier
#    tiers; confirmed via direct per-move source cross-check, not assumed).
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h;
# src/battle_script_commands.c (Cmd_settailwind/Cmd_setstickyweb/
# Cmd_setsafeguard/Cmd_setmist/BS_TryHealPulse/Cmd_stockpiletohpheal);
# src/battle_move_resolution.c (CancelerCallSubmove/GetCopycatMove/
# GetMeFirstMove/GetAssistMove, EFFECT_STOCKPILE/EFFECT_SPIT_UP/
# EFFECT_SWALLOW, MoveEndMoveBlock); src/battle_stat_change.c
# (IsMistProtected, CanDecreaseStat, StatChanged's stockpileDef/SpDef
# increment); src/battle_util.c (IsSafeguardProtected, CalcMoveBase
# PowerAfterModifiers's Me-First ×1.5, CanSetNonVolatileStatus/
# CanBeConfused); src/battle_switch_in.c (Sticky Web's switch-in effect);
# data/battle_scripts_1.s (BattleScript_EffectLifeDew).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_ban_flags_population()
	_test_tailwind()
	_test_safeguard()
	_test_mist()
	_test_sticky_web()
	_test_copycat()
	_test_me_first()
	_test_assist()
	_test_heal_pulse()
	_test_life_dew()
	_test_stockpile_family()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle4_test: %d/%d passed" % [_pass, total])
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


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var tailwind := _load_move(366)
	_chk("A.01 Tailwind acc=0/pp=15/STAT/Flying/ignores_protect",
			tailwind.accuracy == 0 and tailwind.pp == 15 and tailwind.category == 2
			and tailwind.type == TypeChart.TYPE_FLYING and tailwind.ignores_protect)
	_chk("A.02 Tailwind is_tailwind", tailwind.is_tailwind)

	var sticky_web := _load_move(564)
	_chk("A.03 Sticky Web acc=0/pp=20/STAT/Bug/bounceable",
			sticky_web.accuracy == 0 and sticky_web.pp == 20 and sticky_web.category == 2
			and sticky_web.type == TypeChart.TYPE_BUG and sticky_web.bounceable)
	_chk("A.04 Sticky Web is_sticky_web", sticky_web.is_sticky_web)

	var safeguard := _load_move(219)
	_chk("A.05 Safeguard acc=0/pp=25/STAT/Normal", safeguard.accuracy == 0
			and safeguard.pp == 25 and safeguard.category == 2)
	_chk("A.06 Safeguard is_safeguard", safeguard.is_safeguard)

	var mist := _load_move(54)
	_chk("A.07 Mist acc=0/pp=30/STAT/Ice", mist.accuracy == 0 and mist.pp == 30
			and mist.category == 2 and mist.type == TypeChart.TYPE_ICE)
	_chk("A.08 Mist is_mist", mist.is_mist)

	var copycat := _load_move(383)
	_chk("A.09 Copycat acc=0/pp=20/STAT/Normal", copycat.accuracy == 0
			and copycat.pp == 20 and copycat.category == 2)
	_chk("A.10 Copycat is_copycat + banned from itself", copycat.is_copycat
			and (copycat.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (copycat.ban_flags & MoveData.BAN_ASSIST) != 0)

	var me_first := _load_move(382)
	_chk("A.11 Me First acc=0/pp=20/STAT/Normal/ignores_substitute",
			me_first.accuracy == 0 and me_first.pp == 20 and me_first.category == 2
			and me_first.ignores_substitute)
	_chk("A.12 Me First is_me_first + banned from itself", me_first.is_me_first
			and (me_first.ban_flags & MoveData.BAN_ME_FIRST) != 0
			and (me_first.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (me_first.ban_flags & MoveData.BAN_ASSIST) != 0)

	var assist := _load_move(274)
	_chk("A.13 Assist acc=0/pp=20/STAT/Normal", assist.accuracy == 0
			and assist.pp == 20 and assist.category == 2)
	_chk("A.14 Assist is_assist + banned from itself", assist.is_assist
			and (assist.ban_flags & MoveData.BAN_ASSIST) != 0
			and (assist.ban_flags & MoveData.BAN_COPYCAT) != 0)

	var heal_pulse := _load_move(505)
	_chk("A.15 Heal Pulse acc=0/pp=10/STAT/Psychic/pulse+healing+bounceable",
			heal_pulse.accuracy == 0 and heal_pulse.pp == 10 and heal_pulse.category == 2
			and heal_pulse.type == TypeChart.TYPE_PSYCHIC and heal_pulse.pulse_move
			and heal_pulse.healing_move and heal_pulse.bounceable)
	_chk("A.16 Heal Pulse is_heal_pulse", heal_pulse.is_heal_pulse)

	var life_dew := _load_move(719)
	_chk("A.17 Life Dew acc=0/pp=10/STAT/Water/ignores_protect+substitute+healing",
			life_dew.accuracy == 0 and life_dew.pp == 10 and life_dew.category == 2
			and life_dew.type == TypeChart.TYPE_WATER and life_dew.ignores_protect
			and life_dew.ignores_substitute and life_dew.healing_move)
	_chk("A.18 Life Dew is_life_dew", life_dew.is_life_dew)

	var stockpile := _load_move(254)
	_chk("A.19 Stockpile acc=0/pp=20/STAT/Normal/self-targeted",
			stockpile.accuracy == 0 and stockpile.pp == 20 and stockpile.category == 2
			and stockpile.stat_change_self)
	_chk("A.20 Stockpile is_stockpile", stockpile.is_stockpile)

	var spit_up := _load_move(255)
	_chk("A.21 Spit Up power=1/acc=100/pp=10/SPEC/Normal", spit_up.power == 1
			and spit_up.accuracy == 100 and spit_up.pp == 10 and spit_up.category == 1)
	_chk("A.22 Spit Up is_spit_up", spit_up.is_spit_up)

	var swallow := _load_move(256)
	_chk("A.23 Swallow acc=0/pp=10/STAT/Normal/healing", swallow.accuracy == 0
			and swallow.pp == 10 and swallow.category == 2 and swallow.healing_move)
	_chk("A.24 Swallow is_swallow", swallow.is_swallow)


# ── Section A2: ban_flags population across pre-existing moves ──────────

func _test_ban_flags_population() -> void:
	var metronome := _load_move(118)
	_chk("A2.01 Metronome now copycat+assist banned",
			(metronome.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (metronome.ban_flags & MoveData.BAN_ASSIST) != 0
			and (metronome.ban_flags & MoveData.BAN_METRONOME) != 0)

	var protect := _load_move(182)
	_chk("A2.02 Protect now copycat+assist banned",
			(protect.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (protect.ban_flags & MoveData.BAN_ASSIST) != 0)

	var whirlwind := _load_move(18)
	_chk("A2.03 Whirlwind now copycat+assist banned",
			(whirlwind.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (whirlwind.ban_flags & MoveData.BAN_ASSIST) != 0)

	var counter := _load_move(68)
	_chk("A2.04 Counter now copycat+assist+mefirst banned",
			(counter.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (counter.ban_flags & MoveData.BAN_ASSIST) != 0
			and (counter.ban_flags & MoveData.BAN_ME_FIRST) != 0)

	var mirror_coat := _load_move(243)
	_chk("A2.05 Mirror Coat assist+mefirst banned, NOT copycat (GEN<=8 false at GEN_LATEST=GEN_9)",
			(mirror_coat.ban_flags & MoveData.BAN_ASSIST) != 0
			and (mirror_coat.ban_flags & MoveData.BAN_ME_FIRST) != 0
			and (mirror_coat.ban_flags & MoveData.BAN_COPYCAT) == 0)

	var metal_burst := _load_move(368)
	_chk("A2.06 Metal Burst mefirst-only banned",
			(metal_burst.ban_flags & MoveData.BAN_ME_FIRST) != 0
			and (metal_burst.ban_flags & MoveData.BAN_COPYCAT) == 0
			and (metal_burst.ban_flags & MoveData.BAN_ASSIST) == 0)

	var dig := _load_move(91)
	_chk("A2.07 Dig assist-only banned (two-turn family)",
			(dig.ban_flags & MoveData.BAN_ASSIST) != 0
			and (dig.ban_flags & MoveData.BAN_COPYCAT) == 0)

	var circle_throw := _load_move(509)
	_chk("A2.08 Circle Throw now copycat+assist banned",
			(circle_throw.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (circle_throw.ban_flags & MoveData.BAN_ASSIST) != 0)

	var trick := _load_move(271)
	_chk("A2.09 Trick now copycat+assist banned",
			(trick.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (trick.ban_flags & MoveData.BAN_ASSIST) != 0)

	var endure := _load_move(203)
	_chk("A2.10 Endure now copycat+assist banned",
			(endure.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (endure.ban_flags & MoveData.BAN_ASSIST) != 0)

	# Already correctly set by prior tiers — confirm untouched, not newly broken.
	var struggle := _load_move(165)
	_chk("A2.11 Struggle already had copycat+assist+mefirst (untouched)",
			(struggle.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (struggle.ban_flags & MoveData.BAN_ASSIST) != 0
			and (struggle.ban_flags & MoveData.BAN_ME_FIRST) != 0)
	var sleep_talk := _load_move(214)
	_chk("A2.12 Sleep Talk already had copycat+assist (untouched)",
			(sleep_talk.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (sleep_talk.ban_flags & MoveData.BAN_ASSIST) != 0)


# ── Section B: Tailwind ───────────────────────────────────────────────────

func _test_tailwind() -> void:
	var tailwind := _load_move(366)
	var atk := _make_mon("TWAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("TWDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(tailwind)
	def.add_move(_load_move(33))

	var set_side := [-1]
	var bm := _make_bm()
	bm.side_condition_set.connect(func(side, name):
		if name == "tailwind" and set_side[0] == -1: set_side[0] = side)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.01 Tailwind sets side 0", set_side[0] == 0)

	# (ii) already-up fails.
	var atk2 := _make_mon("TWAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("TWDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(tailwind)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	bm2._side_conditions[0]["tailwind_turns"] = 4
	var already_failed := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "already_tailwind": already_failed[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("B.02 Tailwind already-up fails", already_failed[0] == true)

	# (iii) doubles speed — a naturally slower mon acts first while Tailwind
	# is active on its side. Direct StatusManager call, fully deterministic.
	var slow := _make_mon("TWSlow", 300, 60, 60, 60, 60, 30)
	var fast := _make_mon("TWFast", 300, 60, 60, 60, 60, 45)
	var slow_speed_normal := StatusManager.effective_speed(slow, DamageCalculator.WEATHER_NONE, false, false)
	var slow_speed_tailwind := StatusManager.effective_speed(slow, DamageCalculator.WEATHER_NONE, false, true)
	_chk("B.03 Tailwind doubles effective speed", slow_speed_tailwind == slow_speed_normal * 2)
	_chk("B.04 Tailwind-boosted slow mon now outpaces fast mon",
			slow_speed_tailwind > StatusManager.effective_speed(fast, DamageCalculator.WEATHER_NONE, false, false))


# ── Section C: Safeguard ─────────────────────────────────────────────────

func _test_safeguard() -> void:
	var safeguard := _load_move(219)
	var twave := _load_move(86)  # Thunder Wave

	# (i) blocks a status move from an opponent.
	var atk := _make_mon("SGAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("SGDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(safeguard)
	atk.add_move(twave)
	def.add_move(twave)
	var bm := _make_bm()
	bm.queue_move(0, 0)  # turn 1: set Safeguard
	var blocked := [false]
	bm.move_effect_failed.connect(func(mon, reason):
		if mon == atk and reason == "already_status" or reason == "immune":
			pass  # not the signal we care about here
	)
	var status_applied_after_sg := [false]
	bm.secondary_applied.connect(func(mon, _eff):
		if mon == atk: status_applied_after_sg[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("C.01 Safeguard blocks Thunder Wave from opponent",
			status_applied_after_sg[0] == false and atk.status == BattlePokemon.STATUS_NONE)

	# (ii) blocks confusion too.
	var confuse_ray := _load_move(109)
	var atk2 := _make_mon("SGAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("SGDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(safeguard)
	atk2.add_move(twave)
	def2.add_move(confuse_ray)
	var bm2 := _make_bm()
	bm2.queue_move(0, 0)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("C.02 Safeguard blocks Confuse Ray (confusion)", atk2.confusion_turns == 0)

	# (iii) already-up fails.
	var atk3 := _make_mon("SGAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("SGDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(safeguard)
	def3.add_move(_load_move(33))
	var bm3 := _make_bm()
	bm3._side_conditions[0]["safeguard_turns"] = 5
	var sg_already := [false]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "already_safeguard": sg_already[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("C.03 Safeguard already-up fails", sg_already[0] == true)

	# (iv) direct unit test of the resolved helper — Infiltrator bypasses it.
	var bm4 := _make_bm()
	bm4._side_conditions[0]["safeguard_turns"] = 5
	var infiltrator_atk := _make_mon("SGInfiltrator", 300, 60, 60, 60, 60, 60)
	infiltrator_atk.ability = _make_ability(AbilityManager.ABILITY_INFILTRATOR)
	var sg_target := _make_mon("SGTarget", 300, 60, 60, 60, 60, 60)
	bm4._combatants = [sg_target, infiltrator_atk]
	bm4._active_per_side = 1
	_chk("C.04 Safeguard blocks a plain opposing attacker (no Infiltrator)",
			bm4._is_safeguard_active_for(sg_target, sg_target, false) == true)
	_chk("C.05 Safeguard bypassed by an opposing Infiltrator holder",
			bm4._is_safeguard_active_for(infiltrator_atk, sg_target, false) == false)
	bm4.queue_free()


# ── Section D: Mist ───────────────────────────────────────────────────────

func _test_mist() -> void:
	var mist := _load_move(54)
	var growl := _load_move(45)

	# (i) blocks an opponent's stat-lowering move.
	var atk := _make_mon("MistAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("MistDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(mist)
	atk.add_move(_load_move(33))
	def.add_move(growl)
	var bm := _make_bm()
	bm.queue_move(0, 0)  # turn 1: set Mist
	bm._force_hit = true
	var atk_stage_after_growl := [0]
	var mist_snapshot_done := [false]
	bm.move_executed.connect(func(a, _d, m, _amt):
		if a == def and m == growl and not mist_snapshot_done[0]:
			atk_stage_after_growl[0] = atk.stat_stages[BattlePokemon.STAGE_ATK]
			mist_snapshot_done[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("D.01 Mist blocks Growl's Attack drop", atk_stage_after_growl[0] == 0)

	# (ii) already-up fails.
	var atk2 := _make_mon("MistAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("MistDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(mist)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	bm2._side_conditions[0]["mist_turns"] = 5
	var mist_already := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "already_mist": mist_already[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("D.02 Mist already-up fails", mist_already[0] == true)

	# (iii) direct unit test: a non-ally, non-Infiltrator opponent is blocked;
	# a non-ally Infiltrator opponent bypasses it.
	var bm3 := _make_bm()
	bm3._active_per_side = 1
	var mist_holder := _make_mon("MistHolder", 300, 60, 60, 60, 60, 60)
	var plain_opp := _make_mon("MistPlainOpp", 300, 60, 60, 60, 60, 60)
	var infil_opp := _make_mon("MistInfilOpp", 300, 60, 60, 60, 60, 60)
	infil_opp.ability = _make_ability(AbilityManager.ABILITY_INFILTRATOR)
	bm3._combatants = [mist_holder, plain_opp]
	bm3._actor_indices = {mist_holder: 0, plain_opp: 1}
	bm3._side_conditions[0]["mist_turns"] = 5
	# `.duplicate()` — `_load_move` returns a cached, SHARED Resource;
	# mutating it directly (rather than a duplicate) would silently corrupt
	# Growl's real data for the rest of this whole test run.
	var mv := _load_move(45).duplicate()
	mv.stat_change_self = false
	var d3_actual: int = bm3._apply_one_stat_change_pair(
			plain_opp, mist_holder, mv, BattlePokemon.STAGE_ATK, -1, false)
	_chk("D.03 Mist blocks a plain opponent's stat-lowering pair", d3_actual == 0
			and mist_holder.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	bm3._combatants = [mist_holder, infil_opp]
	bm3._actor_indices = {mist_holder: 0, infil_opp: 1}
	mist_holder.stat_stages[BattlePokemon.STAGE_ATK] = 0
	var d3b_actual: int = bm3._apply_one_stat_change_pair(
			infil_opp, mist_holder, mv, BattlePokemon.STAGE_ATK, -1, false)
	_chk("D.04 Mist bypassed by an opposing Infiltrator holder", d3b_actual == -1
			and mist_holder.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	bm3.queue_free()


# ── Section E: Sticky Web ─────────────────────────────────────────────────

func _test_sticky_web() -> void:
	# (i) sets the opponent's side, fails if already set.
	var sticky_web := _load_move(564)
	var atk := _make_mon("SWAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("SWDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(sticky_web)
	def.add_move(_load_move(33))
	var hz_side := [-1]
	var bm := _make_bm()
	bm.hazard_set.connect(func(side, name, _layers):
		if name == "sticky_web" and hz_side[0] == -1: hz_side[0] = side)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("E.01 Sticky Web sets side 1 (opponent's side)", hz_side[0] == 1)

	# (ii) direct switch-in unit test: grounded target takes -1 Speed via the
	# FULL stat-change pipeline — confirmed by checking Defiant triggers too.
	var bm2 := _make_bm()
	bm2._active_per_side = 1
	var setter := _make_mon("SWSetter", 300, 60, 60, 60, 60, 60)
	var new_mon := _make_mon("SWSwitchIn", 300, 60, 60, 60, 60, 60)
	new_mon.ability = _make_ability(AbilityManager.ABILITY_DEFIANT)
	bm2._combatants = [setter, new_mon]
	bm2._actor_indices = {setter: 0, new_mon: 1}
	bm2._side_conditions[1]["sticky_web"] = true
	bm2._side_conditions[1]["sticky_web_setter"] = setter
	var atk_stage_seen := [-99]
	bm2.stat_stage_changed.connect(func(mon, stat, actual):
		if mon == new_mon and stat == BattlePokemon.STAGE_ATK: atk_stage_seen[0] = actual)
	bm2._apply_switch_in_hazards(new_mon, 1)
	_chk("E.02 Sticky Web -1 Speed applied to grounded switch-in",
			new_mon.stat_stages[BattlePokemon.STAGE_SPEED] == -1)
	_chk("E.03 Sticky Web's drop triggers Defiant (+2 Atk reactive)",
			atk_stage_seen[0] == 2 and new_mon.stat_stages[BattlePokemon.STAGE_ATK] == 2)
	bm2.queue_free()

	# (iii) ungrounded (Flying-type) switch-in is immune.
	var bm3 := _make_bm()
	bm3._active_per_side = 1
	var setter3 := _make_mon("SWSetter3", 300, 60, 60, 60, 60, 60)
	var flying_mon := _make_mon("SWFlying", 300, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	bm3._combatants = [setter3, flying_mon]
	bm3._actor_indices = {setter3: 0, flying_mon: 1}
	bm3._side_conditions[1]["sticky_web"] = true
	bm3._side_conditions[1]["sticky_web_setter"] = setter3
	bm3._apply_switch_in_hazards(flying_mon, 1)
	_chk("E.04 Sticky Web does not affect a Flying-type (ungrounded)",
			flying_mon.stat_stages[BattlePokemon.STAGE_SPEED] == 0)
	bm3.queue_free()


# ── Section F: Copycat ────────────────────────────────────────────────────

func _test_copycat() -> void:
	var copycat := _load_move(383)
	var tackle := _load_move(33)

	# (i) direct unit test: no landed move yet -> fails.
	var bm := _make_bm()
	_chk("F.01 Copycat fails with no landed move yet", bm._pick_copycat_move() == null)

	# (ii) after a damaging hit lands, Copycat repeats it.
	bm._last_landed_move_anyone = tackle
	_chk("F.02 Copycat repeats the last landed move", bm._pick_copycat_move() == tackle)

	# (iii) a copycatBanned move (e.g. Metronome) can't be repeated.
	bm._last_landed_move_anyone = _load_move(118)
	_chk("F.03 Copycat can't repeat a copycatBanned move", bm._pick_copycat_move() == null)
	bm.queue_free()

	# (iv) full-battle integration: attacker uses Copycat turn 2, after the
	# opponent's Tackle landed turn 1.
	var atk := _make_mon("CCAtk", 300, 60, 60, 60, 60, 40)
	var def := _make_mon("CCDef", 300, 60, 60, 60, 60, 100)
	atk.add_move(copycat)
	def.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var copycat_called := [null]
	bm2.move_called.connect(func(a, called_move):
		if a == atk and copycat_called[0] == null: copycat_called[0] = called_move)
	bm2.start_battle(atk, def)
	bm2.queue_free()
	_chk("F.04 Copycat calls Tackle after the opponent's Tackle landed",
			copycat_called[0] == tackle)

	# (v) state-scoping: a FRESH BattleManager never leaks a prior battle's
	# _last_landed_move_anyone — confirmed via a brand-new instance.
	var bm3 := _make_bm()
	_chk("F.05 A fresh BattleManager's _last_landed_move_anyone starts null",
			bm3._last_landed_move_anyone == null)
	bm3.queue_free()

	# (vi) assignment timing: a MISSED hit does NOT update the tracker (only
	# a hit that actually lands does).
	var atk4 := _make_mon("CCAtk4", 300, 60, 60, 60, 60, 60)
	var def4 := _make_mon("CCDef4", 300, 60, 60, 60, 60, 60)
	atk4.add_move(tackle)
	def4.add_move(tackle)
	var bm4 := _make_bm()
	bm4._force_hit = false  # every hit misses
	bm4.start_battle(atk4, def4)
	_chk("F.06 A missed hit never updates _last_landed_move_anyone",
			bm4._last_landed_move_anyone == null)
	bm4.queue_free()

	# (vii) HIGH SCRUTINY discriminator, RESOLVED: Me First calling a target
	# move that is itself a move-reassignment effect (Metronome/Sleep Talk).
	# Real finding, caught by this exact test's first run: this scenario is
	# actually IMPOSSIBLE, not merely "handled cleanly" — Metronome, Sleep
	# Talk, Mirror Move, Copycat, and Assist are ALL `category == STAT`
	# (status) in this project's schema, and Me First's own gate
	# (`mf_target_move.category == 2`) excludes status moves entirely,
	# BEFORE the reassignment logic is ever reached. So Me First can NEVER
	# chain into any member of the call-a-different-move family — confirmed
	# here directly rather than assumed, closing the exact edge case Step 0
	# flagged as unresolved. Consequently `BAN_ME_FIRST` is deliberately
	# OMITTED from Metronome/Mirror Move/Sleep Talk/Copycat/Assist's own
	# ban_flags in gen_moves.py (unlike BAN_COPYCAT/BAN_ASSIST, which ARE
	# populated on them) — source's `meFirstBanned` flag on these moves is
	# redundant with the category check above, so it is not mirrored here,
	# not "faithfully populated per source" as an earlier draft of this
	# comment claimed.
	# Both scenarios scope to atk's OWN FIRST action only — Me First's PP
	# (20) eventually exhausts over this many auto-repeated turns, at which
	# point the mon falls back to Struggle, which ALSO emits `move_called`
	# in this project's dispatch (a fresh whole-battle-aggregation
	# instance, caught by this exact test's first run: an unguarded
	# "did move_called ever fire for atk" check would incorrectly see
	# Struggle's own later call and misreport it as Me First having
	# somehow succeeded).
	var me_first := _load_move(382)
	var metronome := _load_move(118)
	var atk5 := _make_mon("MFAtk5", 300, 60, 60, 60, 60, 100)
	var def5 := _make_mon("MFDef5", 300, 60, 60, 60, 60, 40)
	atk5.add_move(me_first)
	def5.add_move(metronome)
	var bm5 := _make_bm()
	bm5._force_hit = true
	var mf5_first_action := [""]
	bm5.move_called.connect(func(a, _called_move):
		if a == atk5 and mf5_first_action[0] == "": mf5_first_action[0] = "called")
	bm5.move_effect_failed.connect(func(mon, reason):
		if mon == atk5 and mf5_first_action[0] == "": mf5_first_action[0] = reason)
	bm5.start_battle(atk5, def5)
	bm5.queue_free()
	_chk("F.07 Me First can NEVER chain into Metronome (status-category, excluded upfront)",
			mf5_first_action[0] == "me_first_failed")

	# (viii) same confirmation with Sleep Talk as the (attempted) borrowed
	# move — same category-gate refusal, not a deeper interaction.
	var sleep_talk := _load_move(214)
	var atk6 := _make_mon("MFAtk6", 300, 60, 60, 60, 60, 100)
	var def6 := _make_mon("MFDef6", 300, 60, 60, 60, 60, 40)
	atk6.add_move(me_first)
	def6.add_move(sleep_talk)
	var bm6 := _make_bm()
	bm6._force_hit = true
	var mf6_first_action := [""]
	bm6.move_called.connect(func(a, _called_move):
		if a == atk6 and mf6_first_action[0] == "": mf6_first_action[0] = "called")
	bm6.move_effect_failed.connect(func(mon, reason):
		if mon == atk6 and mf6_first_action[0] == "": mf6_first_action[0] = reason)
	bm6.start_battle(atk6, def6)
	bm6.queue_free()
	_chk("F.09 Me First can NEVER chain into Sleep Talk (status-category, excluded upfront)",
			mf6_first_action[0] == "me_first_failed")


# ── Section G: Me First ───────────────────────────────────────────────────

func _test_me_first() -> void:
	var me_first := _load_move(382)
	var tackle := _load_move(33)
	var growl := _load_move(45)

	# (i) fails if the target's chosen move is a status move.
	var atk := _make_mon("MFAtk", 300, 60, 60, 60, 60, 100)
	var def := _make_mon("MFDef", 300, 60, 60, 60, 60, 40)
	atk.add_move(me_first)
	def.add_move(growl)
	var bm := _make_bm()
	var mf_status_fail := [false]
	bm.move_effect_failed.connect(func(mon, reason):
		if mon == atk and reason == "me_first_failed": mf_status_fail[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("G.01 Me First fails against a status move target", mf_status_fail[0] == true)

	# (ii) fails if the target has already acted this turn (attacker slower).
	var atk2 := _make_mon("MFAtk2", 300, 60, 60, 60, 60, 30)
	var def2 := _make_mon("MFDef2", 300, 60, 60, 60, 60, 100)
	atk2.add_move(me_first)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var mf_late_fail := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "me_first_failed": mf_late_fail[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("G.02 Me First fails when the target already acted (attacker slower)", mf_late_fail[0] == true)

	# (iii) succeeds when faster, borrows the move, and deals MORE damage
	# than the same move used plainly (the ×1.5 boost) — both scenarios use
	# a forced roll AND forced non-crit for a clean pairwise comparison.
	var atk3 := _make_mon("MFAtk3", 300, 60, 60, 60, 60, 100)
	var def3 := _make_mon("MFDef3", 300, 60, 60, 60, 60, 40)
	atk3.add_move(me_first)
	def3.add_move(tackle)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	var mf_boosted_dmg := [-1]
	bm3.move_executed.connect(func(a, _d, m, amt):
		if a == atk3 and m == tackle and mf_boosted_dmg[0] == -1: mf_boosted_dmg[0] = amt)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()

	var atk4 := _make_mon("MFAtk4", 300, 60, 60, 60, 60, 100)
	var def4 := _make_mon("MFDef4", 300, 60, 60, 60, 60, 40)
	atk4.add_move(tackle)
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	var plain_dmg := [-1]
	bm4.move_executed.connect(func(a, _d, m, amt):
		if a == atk4 and m == tackle and plain_dmg[0] == -1: plain_dmg[0] = amt)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("G.03 Me First borrows Tackle and boosts its power ×1.5",
			mf_boosted_dmg[0] > 0 and plain_dmg[0] > 0 and mf_boosted_dmg[0] > plain_dmg[0])

	# (iv) fails if the borrowed move is meFirstBanned (e.g. target chose
	# Counter, which is meFirstBanned).
	var counter := _load_move(68)
	var atk5 := _make_mon("MFAtk5", 300, 60, 60, 60, 60, 100)
	var def5 := _make_mon("MFDef5", 300, 60, 60, 60, 60, 40)
	atk5.add_move(me_first)
	def5.add_move(counter)
	var bm5 := _make_bm()
	var mf_banned_fail := [false]
	bm5.move_effect_failed.connect(func(mon, reason):
		if mon == atk5 and reason == "me_first_failed": mf_banned_fail[0] = true)
	bm5.start_battle(atk5, def5)
	bm5.queue_free()
	_chk("G.04 Me First fails against a meFirstBanned move (Counter)", mf_banned_fail[0] == true)


# ── Section H: Assist ─────────────────────────────────────────────────────

func _test_assist() -> void:
	var assist := _load_move(274)
	var tackle := _load_move(33)

	# (i) direct unit test: picks a move from the bench, excludes active mon.
	var bm := _make_bm()
	bm._active_per_side = 1
	var active_mon := _make_mon("AsActive", 300, 60, 60, 60, 60, 60)
	var bench_mon := _make_mon("AsBench", 300, 60, 60, 60, 60, 60)
	bench_mon.add_move(tackle)
	var opp := _make_mon("AsOpp", 300, 60, 60, 60, 60, 60)
	var party := BattleParty.new()
	party.members = [active_mon, bench_mon]
	party.active_indices = [0]
	bm._parties = [party, BattleParty.single(opp)]
	bm._combatants = [active_mon, opp]
	bm._actor_indices = {active_mon: 0, opp: 1}
	_chk("H.01 Assist picks the bench mon's move", bm._pick_assist_move(active_mon) == tackle)
	bm.queue_free()

	# (ii) no eligible bench move -> fails.
	var bm2 := _make_bm()
	bm2._active_per_side = 1
	var active2 := _make_mon("AsActive2", 300, 60, 60, 60, 60, 60)
	var empty_bench := _make_mon("AsEmptyBench", 300, 60, 60, 60, 60, 60)
	var opp2 := _make_mon("AsOpp2", 300, 60, 60, 60, 60, 60)
	var party2 := BattleParty.new()
	party2.members = [active2, empty_bench]
	party2.active_indices = [0]
	bm2._parties = [party2, BattleParty.single(opp2)]
	bm2._combatants = [active2, opp2]
	bm2._actor_indices = {active2: 0, opp2: 1}
	_chk("H.02 Assist fails with no eligible bench move", bm2._pick_assist_move(active2) == null)
	bm2.queue_free()

	# (iii) full-battle integration: Assist calls the bench mon's Tackle.
	var atk := _make_mon("AsAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(assist)
	var bench3 := _make_mon("AsBench3", 300, 60, 60, 60, 60, 60)
	bench3.add_move(tackle)
	var def := _make_mon("AsDef", 300, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	var player_party := BattleParty.new()
	player_party.members = [atk, bench3]
	player_party.active_indices = [0]
	var bm3 := _make_bm()
	bm3._force_hit = true
	var assist_called := [null]
	bm3.move_called.connect(func(a, called_move):
		if a == atk and assist_called[0] == null: assist_called[0] = called_move)
	bm3.start_battle_with_parties(player_party, BattleParty.single(def))
	bm3.queue_free()
	_chk("H.03 Assist calls the bench mon's Tackle in a full battle", assist_called[0] == tackle)

	# (iv) excludes an assistBanned bench move (e.g. Metronome).
	var metronome := _load_move(118)
	var bm4 := _make_bm()
	bm4._active_per_side = 1
	var active4 := _make_mon("AsActive4", 300, 60, 60, 60, 60, 60)
	var bench4 := _make_mon("AsBench4", 300, 60, 60, 60, 60, 60)
	bench4.add_move(metronome)
	var opp4 := _make_mon("AsOpp4", 300, 60, 60, 60, 60, 60)
	var party4 := BattleParty.new()
	party4.members = [active4, bench4]
	party4.active_indices = [0]
	bm4._parties = [party4, BattleParty.single(opp4)]
	bm4._combatants = [active4, opp4]
	bm4._actor_indices = {active4: 0, opp4: 1}
	_chk("H.04 Assist excludes an assistBanned bench move (Metronome)",
			bm4._pick_assist_move(active4) == null)
	bm4.queue_free()


# ── Section I: Heal Pulse ─────────────────────────────────────────────────

func _test_heal_pulse() -> void:
	var heal_pulse := _load_move(505)

	# (i) heals the TARGET (not the user) 50% max HP.
	var atk := _make_mon("HPAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("HPDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(heal_pulse)
	def.add_move(_load_move(33))
	def.current_hp = def.max_hp - 100
	var hp_before := def.current_hp
	var healed := [-1]
	var bm := _make_bm()
	bm._force_hit = true
	bm.drain_heal.connect(func(mon, amount):
		if mon == def and healed[0] == -1: healed[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("I.01 Heal Pulse heals the TARGET, not the user",
			healed[0] == max(1, def.max_hp / 2) and def.current_hp > hp_before)

	# (ii) fails at full HP.
	var atk2 := _make_mon("HPAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("HPDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(heal_pulse)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	var failed_full := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == def2 and reason == "already_full_hp": failed_full[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("I.02 Heal Pulse fails at full HP", failed_full[0] == true)

	# (iii) Mega Launcher boosts the heal to 75%, not the generic pulse-move
	# damage multiplier (Heal Pulse has power=0, this path is independent).
	var atk3 := _make_mon("HPAtk3", 300, 60, 60, 60, 60, 60)
	atk3.ability = _make_ability(AbilityManager.ABILITY_MEGA_LAUNCHER)
	var def3 := _make_mon("HPDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(heal_pulse)
	def3.add_move(_load_move(33))
	def3.current_hp = def3.max_hp - 250
	var healed3 := [-1]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.drain_heal.connect(func(mon, amount):
		if mon == def3 and healed3[0] == -1: healed3[0] = amount)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("I.03 Mega Launcher boosts Heal Pulse to 75% max HP",
			healed3[0] == int(def3.max_hp * 0.75))

	# (iv) discriminator: Mega Launcher does NOT boost Heal Pulse if the
	# move somehow isn't flagged pulse_move (confirms the gate reads
	# move.pulse_move, not just the ability alone).
	var non_pulse_heal := heal_pulse.duplicate()
	non_pulse_heal.pulse_move = false
	var atk4 := _make_mon("HPAtk4", 300, 60, 60, 60, 60, 60)
	atk4.ability = _make_ability(AbilityManager.ABILITY_MEGA_LAUNCHER)
	var def4 := _make_mon("HPDef4", 300, 60, 60, 60, 60, 50)
	atk4.add_move(non_pulse_heal)
	def4.add_move(_load_move(33))
	def4.current_hp = def4.max_hp - 250
	var healed4 := [-1]
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.drain_heal.connect(func(mon, amount):
		if mon == def4 and healed4[0] == -1: healed4[0] = amount)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("I.04 Mega Launcher does NOT boost a non-pulse-flagged heal (50% only)",
			healed4[0] == max(1, def4.max_hp / 2))


# ── Section J: Life Dew ───────────────────────────────────────────────────

func _test_life_dew() -> void:
	var life_dew := _load_move(719)

	# (i) heals the user 25% max HP in singles (no-op ally-heal, not a
	# partial failure). Snapshotted via signal at the FIRST occurrence —
	# the battle runs many more turns after this (Tackle vs. repeated Life
	# Dew), so a post-battle HP read would reflect accumulated later state,
	# not this specific heal.
	var atk := _make_mon("LDAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("LDDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(life_dew)
	def.add_move(_load_move(33))
	atk.current_hp = atk.max_hp - 200
	var user_healed := [-1]
	var bm := _make_bm()
	bm._force_hit = true
	bm.drain_heal.connect(func(mon, amount):
		if mon == atk and user_healed[0] == -1: user_healed[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("J.01 Life Dew heals the user 25% max HP", user_healed[0] == max(1, atk.max_hp / 4))

	# (ii) fails only when user is full AND there's no ally to heal.
	var atk2 := _make_mon("LDAtk2", 300, 60, 60, 60, 60, 60)
	var def2 := _make_mon("LDDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(life_dew)
	def2.add_move(_load_move(33))
	var bm2 := _make_bm()
	var failed_full := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "already_full_hp": failed_full[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("J.02 Life Dew fails when user is full HP (no ally in singles)", failed_full[0] == true)

	# (iii) doubles: heals BOTH user and ally independently.
	var bm3 := _make_bm()
	var d_atk := _make_mon("LDAtkD", 300, 60, 60, 60, 60, 60)
	d_atk.add_move(life_dew)
	var d_ally := _make_mon("LDAllyD", 300, 60, 60, 60, 60, 60)
	d_atk.current_hp = d_atk.max_hp - 100
	d_ally.current_hp = d_ally.max_hp - 100
	var d_opp1 := _make_mon("LDOpp1", 300, 60, 60, 60, 60, 60)
	var d_opp2 := _make_mon("LDOpp2", 300, 60, 60, 60, 60, 60)
	d_opp1.add_move(_load_move(33))
	d_opp2.add_move(_load_move(33))
	var pp := BattleParty.new(); pp.members = [d_atk, d_ally]; pp.active_indices = [0, 1]
	var op := BattleParty.new(); op.members = [d_opp1, d_opp2]; op.active_indices = [0, 1]
	var user_healed3 := [-1]
	var ally_healed3 := [-1]
	bm3.drain_heal.connect(func(mon, amount):
		if mon == d_atk and user_healed3[0] == -1: user_healed3[0] = amount
		elif mon == d_ally and ally_healed3[0] == -1: ally_healed3[0] = amount)
	bm3.queue_move_targeted(0, 0, 2)
	bm3.queue_move_targeted(1, 0, 2)
	bm3.queue_move_targeted(2, 0, 0)
	bm3.queue_move_targeted(3, 0, 0)
	bm3._force_hit = true
	bm3.start_battle_doubles(pp, op)
	bm3.queue_free()
	_chk("J.03 Life Dew heals both user and ally in doubles",
			user_healed3[0] == max(1, d_atk.max_hp / 4)
			and ally_healed3[0] == max(1, d_ally.max_hp / 4))


# ── Section K: Stockpile / Spit Up / Swallow ──────────────────────────────

func _test_stockpile_family() -> void:
	var stockpile := _load_move(254)
	var spit_up := _load_move(255)
	var swallow := _load_move(256)
	var tackle := _load_move(33)

	# (i) raises Def+SpDef +1 each per use, increments stockpile_count.
	# Snapshotted via signal at the FIRST occurrence — atk's only move is
	# Stockpile, so the battle auto-repeats it turn after turn (per this
	# project's own established "repeatable move re-selects" convention),
	# and a post-battle stat_stages read would reflect the MAXED (+3) state
	# instead of this specific first use.
	var atk := _make_mon("StAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(stockpile)
	var def := _make_mon("StDef", 400, 60, 60, 60, 60, 30)
	def.add_move(tackle)
	var bm := _make_bm()
	bm.queue_move(0, 0)
	var gained_snapshot := [-1]
	var def_stage_snapshot := [-99]
	var spdef_stage_snapshot := [-99]
	bm.stockpile_gained.connect(func(mon, count):
		if mon == atk and gained_snapshot[0] == -1:
			gained_snapshot[0] = count
			def_stage_snapshot[0] = atk.stat_stages[BattlePokemon.STAGE_DEF]
			spdef_stage_snapshot[0] = atk.stat_stages[BattlePokemon.STAGE_SPDEF])
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("K.01 Stockpile raises Def+SpDef +1 each, count=1",
			def_stage_snapshot[0] == 1 and spdef_stage_snapshot[0] == 1
			and gained_snapshot[0] == 1)

	# (ii) maxes at 3 stacks, fails on a 4th use.
	var atk2 := _make_mon("StAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(stockpile)
	var def2 := _make_mon("StDef2", 400, 60, 60, 60, 60, 30)
	def2.add_move(tackle)
	var bm2 := _make_bm()
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)  # 4th use should fail
	var maxed_failed := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "stockpile_maxed": maxed_failed[0] = true)
	# Snapshot the count the instant it reaches 3 (before a later auto-repeat
	# could push it further or reset it via Spit Up/Swallow — there is none
	# here, but the discipline still applies).
	var count_at_3 := [-1]
	bm2.stockpile_gained.connect(func(mon, count):
		if mon == atk2 and count == 3 and count_at_3[0] == -1: count_at_3[0] = count)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("K.02 Stockpile caps at 3 and a 4th use fails",
			count_at_3[0] == 3 and maxed_failed[0] == true)

	# (iii) Spit Up fails at 0 stacks.
	var atk3 := _make_mon("StAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(spit_up)
	var def3 := _make_mon("StDef3", 300, 60, 60, 60, 60, 30)
	def3.add_move(tackle)
	var bm3 := _make_bm()
	var empty_failed := [false]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "stockpile_empty": empty_failed[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("K.03 Spit Up fails at 0 stacks", empty_failed[0] == true)

	# (iv) Spit Up's power scales with stack count (100 * count) — queue
	# Stockpile x2 then Spit Up, forced roll+crit for a clean read.
	var atk4 := _make_mon("StAtk4", 300, 60, 60, 60, 60, 60)
	atk4.add_move(stockpile)
	atk4.add_move(spit_up)
	var def4 := _make_mon("StDef4", 500, 60, 60, 60, 60, 30)
	def4.add_move(tackle)
	var bm4 := _make_bm()
	bm4.queue_move(0, 0)
	bm4.queue_move(0, 0)
	bm4.queue_move(0, 1)  # Spit Up at 2 stacks
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	var spitup_dmg := [-1]
	var released_count := [-1]
	# [D4 Bundle 4] Snapshotted at the moment of release — after this, the
	# queue drains and atk4 auto-repeats Stockpile (its own moves[0])
	# indefinitely for the rest of the battle, which would silently rebuild
	# stockpile_count/def_added/spdef_added above 0 well before the battle
	# actually ends.
	var count_reset_snapshot := [-1]
	var def_added_reset_snapshot := [-1]
	var spdef_added_reset_snapshot := [-1]
	var def_stage_reset_snapshot := [-99]
	var spdef_stage_reset_snapshot := [-99]
	bm4.move_executed.connect(func(a, _d, m, amt):
		if a == atk4 and m == spit_up and spitup_dmg[0] == -1: spitup_dmg[0] = amt)
	bm4.stockpile_released.connect(func(mon, count):
		if mon == atk4 and released_count[0] == -1:
			released_count[0] = count
			count_reset_snapshot[0] = atk4.stockpile_count
			def_added_reset_snapshot[0] = atk4.stockpile_def_added
			spdef_added_reset_snapshot[0] = atk4.stockpile_spdef_added
			def_stage_reset_snapshot[0] = atk4.stat_stages[BattlePokemon.STAGE_DEF]
			spdef_stage_reset_snapshot[0] = atk4.stat_stages[BattlePokemon.STAGE_SPDEF])
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("K.04 Spit Up released from exactly 2 stacks", released_count[0] == 2)
	_chk("K.05 Spit Up deals real damage (power = 100*count = 200)", spitup_dmg[0] > 0)

	# (v) release removes exactly the tracked Def/SpDef added, resetting
	# stockpile_count/def_added/spdef_added to 0.
	_chk("K.06 Stockpile stacks/boosts fully reset after Spit Up",
			count_reset_snapshot[0] == 0 and def_added_reset_snapshot[0] == 0
			and spdef_added_reset_snapshot[0] == 0
			and def_stage_reset_snapshot[0] == 0 and spdef_stage_reset_snapshot[0] == 0)

	# (vi) Swallow's heal scales with stack count (1 stack = 25%).
	var atk5 := _make_mon("StAtk5", 300, 60, 60, 60, 60, 60)
	atk5.add_move(stockpile)
	atk5.add_move(swallow)
	var def5 := _make_mon("StDef5", 300, 60, 60, 60, 60, 30)
	def5.add_move(tackle)
	var bm5 := _make_bm()
	bm5.queue_move(0, 0)
	bm5.queue_move(0, 1)  # Swallow at 1 stack
	bm5._force_hit = true
	var swallow_heal := [-1]
	bm5.drain_heal.connect(func(mon, amount):
		if mon == atk5 and swallow_heal[0] == -1: swallow_heal[0] = amount)
	# Damage atk5 first so Swallow has something to heal.
	atk5.current_hp = atk5.max_hp - 100
	bm5.start_battle(atk5, def5)
	bm5.queue_free()
	_chk("K.07 Swallow at 1 stack heals 25% max HP",
			swallow_heal[0] == max(1, atk5.max_hp / 4))

	# (vii) HIGH-VALUE finding: Swallow at full HP still resets the stacks
	# even though the heal itself "fails" — confirmed via direct calls to
	# avoid the whole-battle-aggregation pitfall entirely.
	var bm6 := _make_bm()
	var atk6 := _make_mon("StAtk6", 300, 60, 60, 60, 60, 60)
	var def6 := _make_mon("StDef6", 300, 60, 60, 60, 60, 30)
	atk6.stockpile_count = 2
	atk6.stockpile_def_added = 2
	atk6.stockpile_spdef_added = 2
	atk6.stat_stages[BattlePokemon.STAGE_DEF] = 2
	atk6.stat_stages[BattlePokemon.STAGE_SPDEF] = 2
	bm6._active_per_side = 1
	bm6._combatants = [atk6, def6]
	bm6._actor_indices = {atk6: 0, def6: 1}
	bm6._chosen_targets = [1, 0]
	bm6._chosen_moves = [swallow, tackle]
	bm6._turn_order = [atk6, def6]
	bm6._current_actor_index = 0
	var swallow_full_hp_failed := [false]
	bm6.move_effect_failed.connect(func(mon, reason):
		if mon == atk6 and reason == "already_full_hp": swallow_full_hp_failed[0] = true)
	bm6._phase_move_execution()
	_chk("K.08 Swallow at full HP fails to heal but STILL resets stacks",
			swallow_full_hp_failed[0] == true and atk6.stockpile_count == 0
			and atk6.stockpile_def_added == 0 and atk6.stockpile_spdef_added == 0
			and atk6.stat_stages[BattlePokemon.STAGE_DEF] == 0
			and atk6.stat_stages[BattlePokemon.STAGE_SPDEF] == 0)
	bm6.queue_free()

	# (viii) REQUIRED discriminator: a Contrary-holding Pokémon using
	# Stockpile has its Def/SpDef LOWERED (not raised), and
	# stockpile_def_added/stockpile_spdef_added do NOT increment — even
	# though stockpile_count still does (confirmed via source: the counter
	# increments unconditionally, but the per-stat "added" trackers only
	# increment on an ACTUAL rise, `st->stage > 0`, which Contrary inverts
	# to a decrease).
	# Snapshotted via signal at the FIRST use — contrary_atk's only move is
	# Stockpile, so (same as K.01) the battle auto-repeats it, and a
	# post-battle read would reflect a LATER use (up to 3), not this first
	# one specifically.
	var bm7 := _make_bm()
	var contrary_atk := _make_mon("StContrary", 300, 60, 60, 60, 60, 60)
	contrary_atk.ability = _make_ability(AbilityManager.ABILITY_CONTRARY)
	var def7 := _make_mon("StDef7", 300, 60, 60, 60, 60, 30)
	contrary_atk.add_move(stockpile)
	def7.add_move(tackle)
	bm7.queue_move(0, 0)
	var c_count := [-1]
	var c_def_stage := [-99]
	var c_spdef_stage := [-99]
	var c_def_added := [-1]
	var c_spdef_added := [-1]
	bm7.stockpile_gained.connect(func(mon, count):
		if mon == contrary_atk and c_count[0] == -1:
			c_count[0] = count
			c_def_stage[0] = contrary_atk.stat_stages[BattlePokemon.STAGE_DEF]
			c_spdef_stage[0] = contrary_atk.stat_stages[BattlePokemon.STAGE_SPDEF]
			c_def_added[0] = contrary_atk.stockpile_def_added
			c_spdef_added[0] = contrary_atk.stockpile_spdef_added)
	bm7.start_battle(contrary_atk, def7)
	bm7.queue_free()
	_chk("K.09 Contrary+Stockpile LOWERS Def/SpDef instead of raising",
			c_def_stage[0] == -1 and c_spdef_stage[0] == -1)
	_chk("K.10 Contrary+Stockpile still increments stockpile_count (scaling counter)",
			c_count[0] == 1)
	_chk("K.11 Contrary+Stockpile does NOT increment stockpile_def_added/spdef_added",
			c_def_added[0] == 0 and c_spdef_added[0] == 0)

	# (ix) release-amount-divergence: if Def is independently lowered by an
	# opponent's move AFTER Stockpile raised it, Spit Up/Swallow's release
	# still removes exactly what STOCKPILE itself added (stockpile_def_added),
	# not "subtract 3" or re-derive from the current stage — confirmed via a
	# direct, deterministic scenario.
	var bm8 := _make_bm()
	var atk8 := _make_mon("StAtk8", 300, 60, 60, 60, 60, 60)
	var def8 := _make_mon("StDef8", 300, 60, 60, 60, 60, 30)
	atk8.stockpile_count = 2
	atk8.stockpile_def_added = 2
	atk8.stockpile_spdef_added = 2
	atk8.stat_stages[BattlePokemon.STAGE_DEF] = 1  # an opponent's move lowered it by 1 in between
	atk8.stat_stages[BattlePokemon.STAGE_SPDEF] = 2
	bm8._active_per_side = 1
	bm8._combatants = [atk8, def8]
	bm8._actor_indices = {atk8: 0, def8: 1}
	bm8._chosen_targets = [1, 0]
	bm8._chosen_moves = [swallow, tackle]
	bm8._turn_order = [atk8, def8]
	bm8._current_actor_index = 0
	atk8.current_hp = atk8.max_hp - 50
	bm8._phase_move_execution()
	_chk("K.12 Release removes exactly the tracked amount (Def: 1-2=-1), not a blind reset",
			atk8.stat_stages[BattlePokemon.STAGE_DEF] == -1
			and atk8.stat_stages[BattlePokemon.STAGE_SPDEF] == 0)
	bm8.queue_free()


# ── Section L: negative control ───────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon("NegAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("NegDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(tackle)
	def.add_move(tackle)
	var any_side_condition_set := [false]
	var any_stockpile_gained := [false]
	var bm := _make_bm()
	bm.side_condition_set.connect(func(_side, _name): any_side_condition_set[0] = true)
	bm.stockpile_gained.connect(func(_mon, _count): any_stockpile_gained[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("L.01 Negative control: plain Tackle battle triggers none of this bundle's signals",
			any_side_condition_set[0] == false and any_stockpile_gained[0] == false)
