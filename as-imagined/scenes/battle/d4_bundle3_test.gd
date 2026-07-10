extends Node

# [D4 bundle 3] Splash, Refresh, Purify, Memento, Belly Drum, Fillet Away,
# Clangorous Soul, Nightmare, Spite, Recycle, Facade, Take Heart — 12 more
# moves from D4's singleton pool.
#
# Real Step-0 corrections found before implementing (full citations in
# docs/decisions.md's own [D4 bundle 3] entry): Refresh cures Burn/Poison/
# Toxic/Paralysis ONLY, confirmed NOT Sleep/Freeze (STATUS1_CAN_MOVE);
# Take Heart raises Attack + Sp.Atk (source's own data table), NOT
# Sp.Atk/Sp.Def as folklore would suggest; Belly Drum/Fillet Away/
# Clangorous Soul all hard-fail with ZERO HP cost unless the stat change
# would genuinely do something AND the HP payment can be made (an AND
# gate, not "always pay, sometimes no boost"); Recycle restores a
# genuinely BROADER `last_used_item` field (any item, not just berries),
# confirmed distinct from Harvest/Cud Chew's own berry-only tracker, with
# an explicit Air-Balloon-pop exclusion mirroring source's own "cannot be
# restored by any means" carve-out; Facade's burn-halving bypass is a
# separate, independent mechanism from Guts', not conditioned on it.
#
# A real, previously-flagged-as-open bug was also resolved this session:
# Purify/Nightmare/Spite were all found (via direct source read) to share
# Foresight's own "the move's script never calls typecalc" gap — this
# project's general foe-targeting type-immunity gate was incorrectly
# blocking them (most consequentially for Nightmare, a Ghost-type move
# whose own primary use case — an asleep Normal-type target — is exactly
# the Ghost-vs-Normal immunity class Foresight's own bug already
# demonstrated). Fixed by extending the existing exemption list.
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h; src/battle_
# move_resolution.c (EFFECT_TAKE_HEART/EFFECT_MEMENTO/EFFECT_BELLY_DRUM/
# EFFECT_STAT_CHANGE_HALF_HP/EFFECT_CLANGOROUS_SOUL, TryBellyDrum/
# TryHalfHp/CutThirdOfHp); src/battle_script_commands.c
# (Cmd_curestatuswithmove/Cmd_tryspiteppreduce/Cmd_tryrecycleitem/
# Cmd_removeitem); src/battle_util.c (EFFECT_FACADE,
# GetBurnOrFrostBiteModifier); src/battle_end_turn.c
# (HandleEndTurnNightmare); data/battle_scripts_1.s
# (BattleScript_EffectDoNothing/EffectPurify/EffectMemento/EffectNightmare).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_splash()
	_test_refresh()
	_test_purify()
	_test_memento()
	_test_hp_cost_stat_boost()
	_test_nightmare()
	_test_spite()
	_test_recycle()
	_test_facade()
	_test_take_heart()

	var total := _pass + _fail
	print("d4_bundle3_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


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
	var splash := _load_move(150)
	_chk("A.01 Splash acc=0/pp=40/STAT/Normal",
			splash.accuracy == 0 and splash.pp == 40 and splash.category == 2
			and splash.type == TypeChart.TYPE_NORMAL)
	_chk("A.02 Splash is_do_nothing + ignores_protect", splash.is_do_nothing and splash.ignores_protect)

	var refresh := _load_move(287)
	_chk("A.03 Refresh acc=0/pp=20/STAT/Normal",
			refresh.accuracy == 0 and refresh.pp == 20 and refresh.category == 2)
	_chk("A.04 Refresh is_refresh", refresh.is_refresh)

	var purify := _load_move(648)
	_chk("A.05 Purify acc=0/pp=20/STAT/Poison",
			purify.accuracy == 0 and purify.pp == 20 and purify.category == 2
			and purify.type == TypeChart.TYPE_POISON)
	_chk("A.06 Purify is_purify + healing_move + bounceable",
			purify.is_purify and purify.healing_move and purify.bounceable)

	var memento := _load_move(262)
	_chk("A.07 Memento acc=100/pp=10/STAT/Dark",
			memento.accuracy == 100 and memento.pp == 10 and memento.category == 2
			and memento.type == TypeChart.TYPE_DARK)
	_chk("A.08 Memento is_memento + stat drop -2/-2 Atk/SpAtk",
			memento.is_memento and memento.stat_change_stat == BattlePokemon.STAGE_ATK
			and memento.stat_change_amount == -2
			and memento.extra_stat_change_stats == [BattlePokemon.STAGE_SPATK]
			and memento.extra_stat_change_amounts == [-2])

	var belly_drum := _load_move(187)
	_chk("A.09 Belly Drum hp_cost_stat_boost/divisor=2/Atk+12",
			belly_drum.hp_cost_stat_boost and belly_drum.hp_cost_divisor == 2
			and belly_drum.stat_change_stat == BattlePokemon.STAGE_ATK
			and belly_drum.stat_change_amount == 12)

	var fillet_away := _load_move(796)
	_chk("A.10 Fillet Away hp_cost_stat_boost/divisor=2/Atk+2+SpAtk+2+Speed+2",
			fillet_away.hp_cost_stat_boost and fillet_away.hp_cost_divisor == 2
			and fillet_away.stat_change_stat == BattlePokemon.STAGE_ATK
			and fillet_away.stat_change_amount == 2
			and fillet_away.extra_stat_change_stats == [BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPEED]
			and fillet_away.extra_stat_change_amounts == [2, 2])

	var clangorous_soul := _load_move(703)
	_chk("A.11 Clangorous Soul hp_cost_stat_boost/divisor=3/all-5-stats+1",
			clangorous_soul.hp_cost_stat_boost and clangorous_soul.hp_cost_divisor == 3
			and clangorous_soul.stat_change_stat == BattlePokemon.STAGE_ATK
			and clangorous_soul.stat_change_amount == 1
			and clangorous_soul.extra_stat_change_stats == [BattlePokemon.STAGE_DEF,
					BattlePokemon.STAGE_SPATK, BattlePokemon.STAGE_SPDEF, BattlePokemon.STAGE_SPEED]
			and clangorous_soul.extra_stat_change_amounts == [1, 1, 1, 1])

	var nightmare := _load_move(171)
	_chk("A.12 Nightmare acc=100/pp=15/STAT/Ghost", nightmare.accuracy == 100 and nightmare.pp == 15
			and nightmare.category == 2 and nightmare.type == TypeChart.TYPE_GHOST)
	_chk("A.13 Nightmare is_nightmare + does NOT ignore protect",
			nightmare.is_nightmare and not nightmare.ignores_protect)

	var spite := _load_move(180)
	_chk("A.14 Spite acc=100/pp=10/STAT/Ghost", spite.accuracy == 100 and spite.pp == 10
			and spite.category == 2 and spite.type == TypeChart.TYPE_GHOST)
	_chk("A.15 Spite is_spite + ignores_substitute + bounceable",
			spite.is_spite and spite.ignores_substitute and spite.bounceable)

	var recycle := _load_move(278)
	_chk("A.16 Recycle acc=0/pp=10/STAT/Normal", recycle.accuracy == 0 and recycle.pp == 10
			and recycle.category == 2)
	_chk("A.17 Recycle is_recycle", recycle.is_recycle)

	var facade := _load_move(263)
	_chk("A.18 Facade power=70/acc=100/pp=20/PHYS/Normal/contact",
			facade.power == 70 and facade.accuracy == 100 and facade.pp == 20
			and facade.category == 0 and facade.makes_contact)
	_chk("A.19 Facade is_facade", facade.is_facade)

	var take_heart := _load_move(778)
	_chk("A.20 Take Heart acc=0/pp=10/STAT/Psychic", take_heart.accuracy == 0 and take_heart.pp == 10
			and take_heart.category == 2 and take_heart.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.21 Take Heart is_take_heart", take_heart.is_take_heart)


# ── Section B: Splash ────────────────────────────────────────────────────

func _test_splash() -> void:
	var splash := _load_move(150)
	var atk := _make_mon("SplashAtk", 300, 60, 60, 60, 60, 60)
	var def := _make_mon("SplashDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(splash)
	def.add_move(_load_move(45))
	# Scoped to the FIRST Splash execution only — the opponent's own Growl
	# repeatedly lowering atk's OWN Attack stat over many turns will
	# eventually emit its own unrelated `move_effect_failed(atk,
	# "stat_limit")` once Attack bottoms out at -6, which would otherwise
	# collide with a same-identity, ungated failure check here.
	var dealt := [-1]
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, _d, m, amt):
		if a == atk and m == splash and dealt[0] == -1: dealt[0] = amt)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.01 Splash executes and deals 0 damage", dealt[0] == 0)


# ── Section C: Refresh ───────────────────────────────────────────────────

func _test_refresh() -> void:
	var refresh := _load_move(287)

	# (i) cures Paralysis.
	var atk_i := _make_mon("RefAtk1", 300, 60, 60, 60, 60, 60)
	var def_i := _make_mon("RefDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(refresh)
	def_i.add_move(_load_move(45))
	atk_i.status = BattlePokemon.STATUS_PARALYSIS
	var cured := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.status_cured.connect(func(mon): if mon == atk_i: cured[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("C.01 Refresh cures Paralysis", cured[0] == true and atk_i.status == BattlePokemon.STATUS_NONE)

	# (ii) discriminator: does NOT cure Sleep. Note a genuinely asleep mon
	# can never even ATTEMPT Refresh (Refresh lacks usable_while_asleep, so
	# pre_move_check's normal sleep block applies upstream of this move's
	# own dispatch entirely) — the only reachable proxy is the turn a mon
	# wakes up and acts: by the time is_refresh's own check runs,
	# `status` has ALREADY been cleared to NONE by pre_move_check, so
	# Refresh correctly still fails (no curable status present), rather
	# than retroactively "counting" the just-cleared Sleep as cured.
	var atk_ii := _make_mon("RefAtk2", 300, 60, 60, 60, 60, 60)
	var def_ii := _make_mon("RefDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(refresh)
	def_ii.add_move(_load_move(45))
	atk_ii.status = BattlePokemon.STATUS_SLEEP
	atk_ii.sleep_turns = 1  # wakes deterministically turn 1, no RNG forcing needed
	var failed2 := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(a, reason):
		if a == atk_ii and reason == "refresh_failed": failed2[0] = true)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("C.02 discriminator: Refresh still fails on the turn a mon wakes " +
			"from Sleep (status already cleared, not retroactively curable)",
			failed2[0] == true)


# ── Section D: Purify ────────────────────────────────────────────────────

func _test_purify() -> void:
	var purify := _load_move(648)

	# (i) cures the target's status and heals the user, since the target had one.
	var atk_i := _make_mon("PurAtk1", 300, 60, 60, 60, 60, 60)
	var def_i := _make_mon("PurDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(purify)
	def_i.add_move(_load_move(45))
	def_i.status = BattlePokemon.STATUS_BURN
	atk_i.current_hp = 100
	var cured := [false]
	var healed := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.status_cured.connect(func(mon): if mon == def_i: cured[0] = true)
	bm1.drain_heal.connect(func(mon, amount): if mon == atk_i and healed[0] == -1: healed[0] = amount)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("D.01 Purify cures the target's status", cured[0] == true and def_i.status == BattlePokemon.STATUS_NONE)
	_chk("D.02 Purify heals the user, since the cure happened",
			healed[0] == max(1, atk_i.max_hp / 2))

	# (ii) discriminator: fails outright, no heal attempt, if target has no status.
	var atk_ii := _make_mon("PurAtk2", 300, 60, 60, 60, 60, 60)
	var def_ii := _make_mon("PurDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(purify)
	def_ii.add_move(_load_move(45))
	atk_ii.current_hp = 100
	var failed_ii := [false]
	var healed_ii := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "purify_failed": failed_ii[0] = true)
	bm2.drain_heal.connect(func(mon, _amt): if mon == atk_ii: healed_ii[0] = true)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("D.03 discriminator: Purify fails outright against a status-free target " +
			"(no heal attempt)", failed_ii[0] == true and healed_ii[0] == false)

	# (iii) real bug fix confirmation: connects against a Normal-type target
	# despite being Poison-type (would be a flat 0x immunity under the
	# generic foe-targeting type-immunity gate if not exempted).
	var atk_iii := _make_mon("PurAtk3", 300, 60, 60, 60, 60, 100)
	var def_iii := _make_mon("PurDef3", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_STEEL)
	atk_iii.add_move(purify)
	def_iii.add_move(_load_move(45))
	def_iii.status = BattlePokemon.STATUS_POISON
	var cured_iii := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.status_cured.connect(func(mon): if mon == def_iii: cured_iii[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("D.04 Purify (Poison-type) is exempt from the type-immunity gate " +
			"against a Steel-type target (would otherwise be a 0x wall)",
			cured_iii[0] == true)


# ── Section E: Memento ───────────────────────────────────────────────────

func _test_memento() -> void:
	var memento := _load_move(262)

	var atk_i := _make_mon("MemAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("MemDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(memento)
	def_i.add_move(_load_move(45))
	var drops := []
	var fainted := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == def_i: drops.append([stage, delta]))
	bm1.pokemon_fainted.connect(func(mon): if mon == atk_i: fainted[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("E.01 Memento lowers the target's Attack and Sp.Atk by 2 each",
			drops.has([BattlePokemon.STAGE_ATK, -2]) and drops.has([BattlePokemon.STAGE_SPATK, -2]))
	_chk("E.02 Memento faints the user", fainted[0] == true)

	# (ii) discriminator: Substitute blocks the stat-drop specifically, but
	# the self-faint still happens regardless — Substitute protects the
	# TARGET from a move's effects, but the self-faint is a USER-targeted
	# consequence Substitute has no bearing on (matching this move's own
	# well-established real-game behavior: the user always faints from
	# Memento even when the stat-drop itself is blocked/prevented).
	var atk_ii := _make_mon("MemAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("MemDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(memento)
	def_ii.add_move(_load_move(45))
	def_ii.substitute_hp = 999999
	var drops_ii := []
	var fainted_ii := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == def_ii: drops_ii.append([stage, delta]))
	bm2.pokemon_fainted.connect(func(mon): if mon == atk_ii: fainted_ii[0] = true)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("E.03 discriminator: Substitute blocks Memento's stat-drop but " +
			"NOT the user's own self-faint",
			drops_ii.is_empty() and fainted_ii[0] == true)


# ── Section F: Belly Drum / Fillet Away / Clangorous Soul ────────────────

func _test_hp_cost_stat_boost() -> void:
	var belly_drum := _load_move(187)
	var fillet_away := _load_move(796)
	var clangorous_soul := _load_move(703)
	var tackle := _load_move(33)  # deliberately NOT Growl — avoids any
			# stat-stage interference across the multiple turns this
			# battle legitimately runs beyond the one under test.

	# (i) Belly Drum: pays half HP, maxes Attack (+12 delta clamps to +6
	# from any starting stage).
	var atk_i := _make_mon("BDAtk1", 300, 60, 60, 60, 60, 60)
	var def_i := _make_mon("BDDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(belly_drum)
	def_i.add_move(tackle)
	var hp_before := atk_i.current_hp
	var boost_i := [-999]
	var lost_i := [-1]
	var hp_after_cost := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_i and stage == BattlePokemon.STAGE_ATK and boost_i[0] == -999:
			boost_i[0] = delta)
	# Snapshotted live — atk_i takes further Tackle damage from def_i later
	# THIS SAME turn (and on every later turn once Belly Drum starts
	# failing), so reading current_hp after start_battle() returns would
	# reflect accumulated chip damage, not the HP-cost moment under test.
	bm1.passive_hp_lost.connect(func(mon, amount):
		if mon == atk_i and lost_i[0] == -1:
			lost_i[0] = amount
			hp_after_cost[0] = atk_i.current_hp)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("F.01 Belly Drum raises Attack to exactly +6", boost_i[0] == 6)
	_chk("F.02 Belly Drum costs exactly half max HP", lost_i[0] == atk_i.max_hp / 2
			and hp_before - lost_i[0] == hp_after_cost[0])

	# (ii) discriminator: fails with ZERO HP cost at exactly half HP
	# (current_hp must be STRICTLY greater than half).
	var atk_ii := _make_mon("BDAtk2", 300, 60, 60, 60, 60, 60)
	var def_ii := _make_mon("BDDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(belly_drum)
	def_ii.add_move(tackle)
	atk_ii.current_hp = atk_ii.max_hp / 2
	var hp_before_ii := atk_ii.current_hp
	var failed_ii := [false]
	var lost_ii := [false]
	var hp_at_fail := [-1]
	var stage_at_fail := [-99]
	var bm2 := _make_bm()
	bm2._force_hit = true
	# Snapshotted live inside the signal handler — def_ii's own Tackle
	# still connects later THIS SAME turn (atk_ii is faster but not
	# invulnerable), and the battle legitimately runs many more turns
	# beyond this one, so reading state after start_battle() returns would
	# reflect accumulated chip damage, not the moment under test.
	bm2.move_effect_failed.connect(func(a, reason):
		if a == atk_ii and reason == "stat_change_failed" and not failed_ii[0]:
			failed_ii[0] = true
			hp_at_fail[0] = atk_ii.current_hp
			stage_at_fail[0] = atk_ii.stat_stages[BattlePokemon.STAGE_ATK])
	bm2.passive_hp_lost.connect(func(mon, _amt): if mon == atk_ii: lost_ii[0] = true)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("F.03 discriminator: Belly Drum fails with ZERO HP cost at exactly half HP",
			failed_ii[0] == true and lost_ii[0] == false
			and hp_at_fail[0] == hp_before_ii and stage_at_fail[0] == 0)

	# (iii) discriminator: also fails if Attack is already at +6 (even with
	# plenty of HP).
	var atk_iii := _make_mon("BDAtk3", 300, 60, 60, 60, 60, 60)
	var def_iii := _make_mon("BDDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(belly_drum)
	def_iii.add_move(tackle)
	atk_iii.stat_stages[BattlePokemon.STAGE_ATK] = 6
	var failed_iii := [false]
	var lost_iii := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(a, reason):
		if a == atk_iii and reason == "stat_change_failed": failed_iii[0] = true)
	bm3.passive_hp_lost.connect(func(mon, _amt): if mon == atk_iii: lost_iii[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("F.04 discriminator: Belly Drum fails with ZERO HP cost when Attack is already +6",
			failed_iii[0] == true and lost_iii[0] == false)

	# (iv) Fillet Away: pays half HP, +2 to Atk/SpAtk/Speed each.
	var atk_iv := _make_mon("FAAtk4", 300, 60, 60, 60, 60, 60)
	var def_iv := _make_mon("FADef4", 300, 60, 60, 60, 60, 50)
	atk_iv.add_move(fillet_away)
	def_iv.add_move(tackle)
	var boosts_iv := []
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_iv and boosts_iv.size() < 3: boosts_iv.append([stage, delta]))
	bm4.start_battle(atk_iv, def_iv)
	bm4.queue_free()
	_chk("F.05 Fillet Away raises Atk/SpAtk/Speed by 2 each",
			boosts_iv.has([BattlePokemon.STAGE_ATK, 2]) and boosts_iv.has([BattlePokemon.STAGE_SPATK, 2])
			and boosts_iv.has([BattlePokemon.STAGE_SPEED, 2]))

	# (v) Clangorous Soul: pays a THIRD of HP (genuinely different divisor
	# from Belly Drum/Fillet Away's half), +1 to all 5 stats.
	var atk_v := _make_mon("CSAtk5", 300, 60, 60, 60, 60, 60)
	var def_v := _make_mon("CSDef5", 300, 60, 60, 60, 60, 50)
	atk_v.add_move(clangorous_soul)
	def_v.add_move(tackle)
	var boosts_v := []
	var lost_v := [-1]
	var bm5 := _make_bm()
	bm5._force_hit = true
	bm5.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_v and boosts_v.size() < 5: boosts_v.append([stage, delta]))
	bm5.passive_hp_lost.connect(func(mon, amount): if mon == atk_v and lost_v[0] == -1: lost_v[0] = amount)
	bm5.start_battle(atk_v, def_v)
	bm5.queue_free()
	_chk("F.06 Clangorous Soul costs exactly a third of max HP (not half)",
			lost_v[0] == atk_v.max_hp / 3)
	_chk("F.07 Clangorous Soul raises all 5 stats by 1 each",
			boosts_v.size() == 5 and boosts_v.has([BattlePokemon.STAGE_ATK, 1])
			and boosts_v.has([BattlePokemon.STAGE_DEF, 1]) and boosts_v.has([BattlePokemon.STAGE_SPATK, 1])
			and boosts_v.has([BattlePokemon.STAGE_SPDEF, 1]) and boosts_v.has([BattlePokemon.STAGE_SPEED, 1]))


# ── Section G: Nightmare ─────────────────────────────────────────────────

func _test_nightmare() -> void:
	var nightmare := _load_move(171)

	# (i) fails against a non-sleeping target.
	var atk_i := _make_mon("NMAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("NMDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(nightmare)
	def_i.add_move(_load_move(45))
	var failed_i := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_effect_failed.connect(func(_a, reason): if reason == "nightmare_failed": failed_i[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("G.01 Nightmare fails against a non-sleeping target",
			failed_i[0] == true and def_i.nightmare_active == false)

	# (ii) applies against a sleeping target and deals maxHP/4 at end of turn.
	var atk_ii := _make_mon("NMAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("NMDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(nightmare)
	def_ii.add_move(_load_move(45))
	def_ii.status = BattlePokemon.STATUS_SLEEP
	def_ii.sleep_turns = 5
	var applied := [false]
	var dmg := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.nightmare_set.connect(func(mon): if mon == def_ii: applied[0] = true)
	bm2.nightmare_damage.connect(func(mon, amount): if mon == def_ii and dmg[0] == -1: dmg[0] = amount)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("G.02 Nightmare applies against a sleeping target", applied[0] == true)
	_chk("G.03 Nightmare deals maxHP/4 at end of turn", dmg[0] == max(1, def_ii.max_hp / 4))

	# (iii) real bug fix confirmation: connects against a Normal-type
	# target despite being Ghost-type (would be a flat 0x immunity under
	# the generic gate if not exempted).
	var atk_iii := _make_mon("NMAtk3", 300, 60, 60, 60, 60, 100)
	var def_iii := _make_mon("NMDef3", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_NORMAL)
	atk_iii.add_move(nightmare)
	def_iii.add_move(_load_move(45))
	def_iii.status = BattlePokemon.STATUS_SLEEP
	def_iii.sleep_turns = 5
	var applied_iii := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.nightmare_set.connect(func(mon): if mon == def_iii: applied_iii[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("G.04 Nightmare (Ghost-type) is exempt from the type-immunity gate " +
			"against a Normal-type target (would otherwise be a 0x wall)",
			applied_iii[0] == true)

	# (iv) recurring tick re-checks sleep every turn: once the target wakes
	# up, the tick silently stops (no more damage), rather than persisting.
	var atk_iv := _make_mon("NMAtk4", 300, 60, 60, 60, 60, 100)
	var def_iv := _make_mon("NMDef4", 300, 60, 60, 60, 60, 50)
	atk_iv.add_move(_load_move(45))  # Growl, filler after Nightmare's own single application
	def_iv.add_move(_load_move(45))
	def_iv.status = BattlePokemon.STATUS_SLEEP
	def_iv.sleep_turns = 1  # wakes deterministically on turn 1 (1-1=0), no RNG forcing needed
	def_iv.nightmare_active = true
	var bm4 := _make_bm()
	bm4._force_hit = true
	var tick_after_wake := [false]
	bm4.nightmare_damage.connect(func(_mon, _amt): tick_after_wake[0] = true)
	bm4.start_battle(atk_iv, def_iv)
	bm4.queue_free()
	_chk("G.05 Nightmare's recurring tick stops (no damage) once the target wakes up",
			tick_after_wake[0] == false and def_iv.nightmare_active == false)


# ── Section H: Spite ─────────────────────────────────────────────────────

func _test_spite() -> void:
	var spite := _load_move(180)
	var tackle := _load_move(33)

	# (i) reduces the target's last-used move's PP by 4. ATK is FASTER and
	# def_i's own last_move_used/current_pp are pre-set directly (as if
	# used on a PRIOR turn) so Spite's own read isn't confounded by def's
	# own turn-1 move use also deducting PP first.
	var atk_i := _make_mon("SpAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("SpDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(spite)
	def_i.add_move(tackle)
	def_i.last_move_used = tackle
	var reduced := [-1]
	var pp_after := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.pp_reduced.connect(func(mon, m, amount):
		if mon == def_i and m == tackle and reduced[0] == -1:
			reduced[0] = amount
			pp_after[0] = def_i.current_pp[0])
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("H.01 Spite reduces the target's last-used move's PP by 4",
			reduced[0] == 4 and pp_after[0] == tackle.pp - 4)

	# (ii) floored at 0 — reduces by only what remains, not below 0.
	# Pre-set last_move_used/current_pp directly (last_move_used has no
	# special reset-on-battle-start logic, only on switch-out, so a
	# pre-battle value survives into turn 1's dispatch) rather than
	# orchestrating an actual prior turn, for full determinism. ATK is
	# FASTER here (unlike (i)) so Spite reads current_pp BEFORE def's own
	# turn-1 Tackle use would otherwise deduct it first.
	var atk_ii := _make_mon("SpAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("SpDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(spite)
	def_ii.add_move(tackle)
	def_ii.last_move_used = tackle
	def_ii.current_pp[0] = 2
	var reduced_ii := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.pp_reduced.connect(func(mon, m, amount):
		if mon == def_ii and m == tackle and reduced_ii[0] == -1: reduced_ii[0] = amount)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("H.02 Spite floors at 0 (reduces by only what remains when < 4 PP left)",
			reduced_ii[0] == 2 and def_ii.current_pp[0] == 0)

	# (iii) fails if the target has no last-used move (confirms the
	# switched-in exemption is already free via last_move_used's own
	# switch-out clear, no dedicated flag needed).
	var atk_iii := _make_mon("SpAtk3", 300, 60, 60, 60, 60, 50)
	var def_iii := _make_mon("SpDef3", 300, 60, 60, 60, 60, 100)
	atk_iii.add_move(spite)
	def_iii.add_move(tackle)
	_chk("H.03 a fresh mon's last_move_used is null (Spite's own fail case " +
			"needs no dedicated switched-in exemption)",
			def_iii.last_move_used == null)


# ── Section I: Recycle ───────────────────────────────────────────────────

func _test_recycle() -> void:
	var recycle := _load_move(278)
	var tackle := _load_move(33)
	var sitrus := _make_item(ItemManager.HOLD_EFFECT_RESTORE_PCT_HP, 25)

	# (i) end-to-end: a real Sitrus Berry consumption (via the existing
	# HP-threshold trigger) populates last_used_item for free, through the
	# actual _consume_item chokepoint — not a hand-set field. Recycle then
	# restores it on a later turn.
	var atk_i := _make_mon("RcAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("RcDef1", 300, 60, 60, 60, 60, 50)
	atk_i.held_item = sitrus
	# Below Sitrus's 50% threshold (triggers consumption on the incoming
	# hit) but with enough of a buffer above 0 to survive a moderate Tackle.
	atk_i.current_hp = atk_i.max_hp / 4
	atk_i.add_move(recycle)
	def_i.add_move(tackle)
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	var recycled_i := [null]
	bm1.item_recycled.connect(func(mon, item): if mon == atk_i and recycled_i[0] == null: recycled_i[0] = item)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("I.01 Recycle restores a genuinely-consumed Sitrus Berry on a later turn",
			recycled_i[0] == sitrus)

	# (ii) direct unit test of the actual restore, bypassing timing
	# ambiguity: manually populate last_used_item (as _consume_item would)
	# and confirm Recycle restores it correctly.
	var atk_ii := _make_mon("RcAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("RcDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.last_used_item = sitrus
	atk_ii.held_item = null
	atk_ii.add_move(recycle)
	def_ii.add_move(_load_move(45))
	var recycled := [null]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.item_recycled.connect(func(mon, item): if mon == atk_ii: recycled[0] = item)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("I.02 Recycle restores the last-used item to held_item",
			recycled[0] == sitrus and atk_ii.held_item == sitrus and atk_ii.last_used_item == null)

	# (iii) discriminator: fails if the user already holds an item.
	var atk_iii := _make_mon("RcAtk3", 300, 60, 60, 60, 60, 100)
	var def_iii := _make_mon("RcDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.last_used_item = sitrus
	atk_iii.held_item = _make_item(ItemManager.HOLD_EFFECT_FOCUS_SASH)
	atk_iii.add_move(recycle)
	def_iii.add_move(_load_move(45))
	var failed_iii := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason): if reason == "recycle_failed": failed_iii[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("I.03 discriminator: Recycle fails if the user already holds an item",
			failed_iii[0] == true)

	# (iv) discriminator: a popped Air Balloon is never recorded for Recycle.
	var atk_iv := _make_mon("RcAtk4", 300, 60, 60, 60, 60, 50)
	var def_iv := _make_mon("RcDef4", 300, 60, 60, 60, 60, 100)
	atk_iv.add_move(tackle)
	def_iv.held_item = _make_item(ItemManager.HOLD_EFFECT_AIR_BALLOON)
	def_iv.add_move(_load_move(45))
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.start_battle(atk_iv, def_iv)
	bm4.queue_free()
	_chk("I.04 discriminator: a popped Air Balloon is never recorded in last_used_item",
			def_iv.last_used_item == null)


# ── Section J: Facade ────────────────────────────────────────────────────

func _test_facade() -> void:
	var facade := _load_move(263)

	# (i) doubles power when the user is poisoned.
	var atk_i := _make_mon("FacAtk1", 300, 100, 60, 60, 60, 100)
	var def_i := _make_mon("FacDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(facade)
	def_i.add_move(_load_move(45))
	var dealt_statused := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == facade and dealt_statused.is_empty():
			dealt_statused.append(amount))
	atk_i.status = BattlePokemon.STATUS_POISON
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()

	var atk_ii := _make_mon("FacAtk2", 300, 100, 60, 60, 60, 100)
	var def_ii := _make_mon("FacDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(facade)
	def_ii.add_move(_load_move(45))
	var dealt_baseline := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk_ii and m == facade and dealt_baseline.is_empty():
			dealt_baseline.append(amount))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("J.01 Facade deals roughly double damage when the user is poisoned vs. healthy",
			dealt_statused.size() == 1 and dealt_baseline.size() == 1
			and absi(dealt_statused[0] - dealt_baseline[0] * 2) <= 2)

	# (ii) discriminator: burn does NOT halve Facade's own damage (the
	# independent bypass), unlike an ordinary physical move.
	var atk_iii := _make_mon("FacAtk3", 300, 100, 60, 60, 60, 100)
	var def_iii := _make_mon("FacDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(facade)
	def_iii.add_move(_load_move(45))
	atk_iii.status = BattlePokemon.STATUS_BURN
	var dealt_burned := []
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a, _d, m, amount):
		if a == atk_iii and m == facade and dealt_burned.is_empty():
			dealt_burned.append(amount))
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	# Burned Facade should match the poisoned-Facade damage (both are the
	# doubled, non-halved case), NOT the halved amount an ordinary
	# physical move would take under burn.
	_chk("J.02 discriminator: burn does NOT halve Facade's own damage " +
			"(independent bypass from the power-double)",
			dealt_burned.size() == 1 and absi(dealt_burned[0] - dealt_statused[0]) <= 2)

	# (iii) Sleep is confirmed excluded from Facade's power-double list by
	# Step 0 (source's own STATUS1_BURN|PSN_ANY|PARALYSIS|FROSTBITE mask
	# has no Sleep bit) — but this is NOT independently testable via a full
	# battle in this project: a genuinely sleeping attacker can never
	# execute Facade at all (it lacks usable_while_asleep, so
	# pre_move_check's normal sleep block applies), and on the one turn it
	# DOES wake up and act, `status` is already cleared to NONE by the time
	# Facade's own power check runs — the same "provably unreachable"
	# shape already noted for Memento's own Dark-type-immunity gap.
	# Deliberately not asserted here as a discriminator for that reason.


# ── Section K: Take Heart ────────────────────────────────────────────────

func _test_take_heart() -> void:
	var take_heart := _load_move(778)

	# (i) cures status AND boosts, when both apply.
	var atk_i := _make_mon("THAtk1", 300, 60, 60, 60, 60, 60)
	var def_i := _make_mon("THDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(take_heart)
	def_i.add_move(_load_move(45))
	atk_i.status = BattlePokemon.STATUS_POISON
	var cured := [false]
	var boosts := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.status_cured.connect(func(mon): if mon == atk_i: cured[0] = true)
	bm1.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_i: boosts.append([stage, delta]))
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("K.01 Take Heart cures the user's own status", cured[0] == true)
	_chk("K.02 Take Heart raises Attack AND Sp.Atk by 1 each (not Sp.Def)",
			boosts.has([BattlePokemon.STAGE_ATK, 1]) and boosts.has([BattlePokemon.STAGE_SPATK, 1])
			and not boosts.has([BattlePokemon.STAGE_SPDEF, 1]))

	# (ii) discriminator: still succeeds (boosts) with no status to cure.
	var atk_ii := _make_mon("THAtk2", 300, 60, 60, 60, 60, 60)
	var def_ii := _make_mon("THDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(take_heart)
	def_ii.add_move(_load_move(45))
	var boosts_ii := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_ii: boosts_ii.append([stage, delta]))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("K.03 discriminator: Take Heart still boosts with no status present",
			boosts_ii.has([BattlePokemon.STAGE_ATK, 1]))

	# (iii) discriminator: still cures status even with both stages already maxed.
	var atk_iii := _make_mon("THAtk3", 300, 60, 60, 60, 60, 60)
	var def_iii := _make_mon("THDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(take_heart)
	def_iii.add_move(_load_move(45))
	atk_iii.status = BattlePokemon.STATUS_BURN
	atk_iii.stat_stages[BattlePokemon.STAGE_ATK] = 6
	atk_iii.stat_stages[BattlePokemon.STAGE_SPATK] = 6
	var cured_iii := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.status_cured.connect(func(mon): if mon == atk_iii: cured_iii[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("K.04 discriminator: Take Heart still cures status even when both " +
			"stages are already maxed (OR-gated, not AND-gated like the " +
			"HP-cost family)", cured_iii[0] == true)
