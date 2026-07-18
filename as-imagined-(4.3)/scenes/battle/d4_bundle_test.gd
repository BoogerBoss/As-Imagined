extends Node

# [D4 bundle] Struggle, Helping Hand, Sleep Talk, Taunt, Assurance, Magic
# Coat — the D4 recon's own top-recommended CHEAP/FREE pick (7 moves minus
# Nature Power, pulled per its own Step 0 finding that it hits the same
# `gBattleEnvironment` blocker as Secret Power/Camouflage — deferred
# alongside them, not shipped here).
#
# Struggle/Helping Hand are FREE — their entire mechanism was already fully
# built and wired (Struggle since M1/M15's `_construct_struggle_move`-style
# hardcoded fallback; Helping Hand since `[M14b]`) and just needed a
# `.tres` data entry. Sleep Talk reuses Mirror Move/Metronome's own
# reassignment pattern, scoped to the attacker's own moveset, plus a
# genuinely NEW small mechanism (`usable_while_asleep`, bypassing
# `pre_move_check`'s sleep block). Taunt reuses the Disable/Encore/Throat-
# Chop turn-counter-volatile shape at execution time. Assurance reuses
# Revenge's own `hit_by_this_turn` tracker but keyed to "hit by anyone,"
# not the user specifically. Magic Coat shares Magic Bounce's exact
# dispatch chain (`[M17n-9]`), confirmed via direct source read.
#
# Two real Step-0-caught gaps fixed before this suite was ever run: (1)
# Helping Hand and Magic Coat both needed their own `ban_flags`
# (metronomeBanned/copycatBanned/assistBanned/mirrorMoveBanned for Helping
# Hand; mirrorMoveBanned for Magic Coat) — missed on the first data-entry
# pass, since neither had ever been callable by Metronome before this
# session; (2) Sleep Talk's own move-picking function needed an explicit
# "is the attacker actually asleep or Comatose" gate independent of
# `usable_while_asleep`'s pre_move_check bypass — source's own
# GetSleepTalkMove checks this itself, it isn't implied for free.
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h (MOVE_STRUGGLE,
# MOVE_HELPING_HAND L7403-7420, MOVE_SLEEP_TALK L(sleep_talk),
# MOVE_TAUNT L7377-7398, MOVE_ASSURANCE L10106-10120, MOVE_MAGIC_COAT
# L7598-7616); src/battle_move_resolution.c (GetSleepTalkMove L5098-5127,
# MoveEndBouncedMove L3142-3195, calledMove switch L529-552);
# src/battle_util.c (IsUsableWhileAsleepEffect L10713-10723, EFFECT_
# ASSURANCE L6196-6198, taunt block L1360-1380); src/battle_script_
# commands.c (Cmd_settaunt L8815-8845).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_struggle()
	_test_helping_hand()
	_test_sleep_talk()
	_test_taunt()
	_test_assurance()
	_test_magic_coat()

	var total := _pass + _fail
	print("d4_bundle_test: %d/%d passed" % [_pass, total])
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


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices = [0, 1]
	return p


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var struggle := _load_move(165)
	_chk("A.01 Struggle power=50/acc=0/pp=1/PHYS/Normal/contact",
			struggle.power == 50 and struggle.accuracy == 0 and struggle.pp == 1
			and struggle.category == 0 and struggle.type == TypeChart.TYPE_NORMAL
			and struggle.makes_contact)
	_chk("A.02 Struggle is_struggle",  struggle.is_struggle)
	_chk("A.03 Struggle carries every relevant ban flag",
			(struggle.ban_flags & MoveData.BAN_METRONOME) != 0
			and (struggle.ban_flags & MoveData.BAN_SLEEP_TALK) != 0
			and (struggle.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (struggle.ban_flags & MoveData.BAN_INSTRUCT) != 0
			and (struggle.ban_flags & MoveData.BAN_ASSIST) != 0
			and (struggle.ban_flags & MoveData.BAN_MIMIC) != 0
			and (struggle.ban_flags & MoveData.BAN_ME_FIRST) != 0
			and (struggle.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0
			and (struggle.ban_flags & MoveData.BAN_SKETCH) != 0)

	var hh := _load_move(270)
	_chk("A.04 Helping Hand acc=0/pp=20/priority=5/STAT/Normal",
			hh.accuracy == 0 and hh.pp == 20 and hh.priority == 5
			and hh.category == 2 and hh.type == TypeChart.TYPE_NORMAL)
	_chk("A.05 Helping Hand is_helping_hand + ignores_protect + ignores_substitute",
			hh.is_helping_hand and hh.ignores_protect and hh.ignores_substitute)
	_chk("A.06 Helping Hand carries its own ban flags (metronome/copycat/assist/mirror)",
			(hh.ban_flags & MoveData.BAN_METRONOME) != 0
			and (hh.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (hh.ban_flags & MoveData.BAN_ASSIST) != 0
			and (hh.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0)

	var st := _load_move(214)
	_chk("A.07 Sleep Talk acc=0/pp=10/STAT/Normal",
			st.accuracy == 0 and st.pp == 10 and st.category == 2
			and st.type == TypeChart.TYPE_NORMAL)
	_chk("A.08 Sleep Talk is_sleep_talk + usable_while_asleep + ignores_protect",
			st.is_sleep_talk and st.usable_while_asleep and st.ignores_protect)
	_chk("A.09 Sleep Talk carries its own ban flags",
			(st.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0
			and (st.ban_flags & MoveData.BAN_METRONOME) != 0
			and (st.ban_flags & MoveData.BAN_COPYCAT) != 0
			and (st.ban_flags & MoveData.BAN_SLEEP_TALK) != 0
			and (st.ban_flags & MoveData.BAN_INSTRUCT) != 0
			and (st.ban_flags & MoveData.BAN_MIMIC) != 0
			and (st.ban_flags & MoveData.BAN_ENCORE) != 0
			and (st.ban_flags & MoveData.BAN_ASSIST) != 0)

	var taunt := _load_move(269)
	_chk("A.10 Taunt acc=100/pp=20/STAT/Dark",
			taunt.accuracy == 100 and taunt.pp == 20 and taunt.category == 2
			and taunt.type == TypeChart.TYPE_DARK)
	_chk("A.11 Taunt is_taunt + ignores_substitute + bounceable + blocked_by_aroma_veil",
			taunt.is_taunt and taunt.ignores_substitute and taunt.bounceable
			and taunt.blocked_by_aroma_veil)

	var assurance := _load_move(372)
	_chk("A.12 Assurance power=60/acc=100/pp=10/PHYS/Dark/contact",
			assurance.power == 60 and assurance.accuracy == 100 and assurance.pp == 10
			and assurance.category == 0 and assurance.type == TypeChart.TYPE_DARK
			and assurance.makes_contact)
	_chk("A.13 Assurance is_assurance", assurance.is_assurance)

	var mc := _load_move(277)
	_chk("A.14 Magic Coat acc=0/pp=15/priority=4/STAT/Psychic",
			mc.accuracy == 0 and mc.pp == 15 and mc.priority == 4
			and mc.category == 2 and mc.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.15 Magic Coat is_magic_coat + ignores_protect",
			mc.is_magic_coat and mc.ignores_protect)
	_chk("A.16 Magic Coat carries BAN_MIRROR_MOVE",
			(mc.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0)


# ── Section B: Struggle — confirm the hardcoded fallback is untouched and
# correct, and Metronome now correctly excludes the new .tres entry ──────

func _test_struggle() -> void:
	var tackle := _load_move(33)

	# (i) forced-Struggle-on-0-PP still fires correctly (the pre-existing
	# hardcoded `_struggle_move` mechanism, unaffected by this session).
	var atk := _make_mon("StruggleAtk", 300, 60, 60, 60, 60, 100)
	var def := _make_mon("StruggleDef", 300, 60, 60, 60, 60, 50)
	var only_move := _load_move(33)
	atk.add_move(only_move)
	# current_pp is parallel to moves and tracked separately from the
	# MoveData resource's own (shared, immutable-in-practice) pp field.
	atk.current_pp[0] = 0
	def.add_move(tackle)
	var events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, _d, m, _amount):
		if a == atk and events.is_empty():
			events.append(m))
	bm.start_battle(atk, def)
	_chk("B.01 all-PP-depleted forces a Struggle-flagged move",
			events.size() == 1 and events[0].is_struggle == true)
	bm.queue_free()

	# (ii) Metronome's own pool scan (data/moves/ directory, filtered by
	# ban_flags) correctly excludes the new Struggle .tres entry now that
	# it exists on disk for the first time.
	var struggle_tres := _load_move(165)
	_chk("B.02 Struggle would be excluded from Metronome's pool",
			(struggle_tres.ban_flags & MoveData.BAN_METRONOME) != 0)


# ── Section C: Helping Hand ──────────────────────────────────────────────

func _test_helping_hand() -> void:
	var hh := _load_move(270)
	var tackle := _load_move(33)

	# (i) doubles success: ally's next damaging move is boosted 1.5x.
	var user_i := _make_mon("HHUser1", 300, 60, 60, 60, 60, 50)
	var ally_i := _make_mon("HHAlly1", 300, 100, 60, 60, 60, 40)
	var opp_a_i := _make_mon("HHOppA1", 300, 60, 60, 60, 60, 30)
	var opp_b_i := _make_mon("HHOppB1", 300, 60, 60, 60, 60, 20)
	user_i.add_move(hh)
	ally_i.add_move(tackle)
	opp_a_i.add_move(tackle)
	opp_b_i.add_move(tackle)
	var baseline: Dictionary = DamageCalculator.calculate(ally_i, opp_a_i, tackle, 100, false)

	var user_ii := _make_mon("HHUser2", 300, 60, 60, 60, 60, 50)
	var ally_ii := _make_mon("HHAlly2", 300, 100, 60, 60, 60, 40)
	var opp_a_ii := _make_mon("HHOppA2", 300, 60, 60, 60, 60, 30)
	var opp_b_ii := _make_mon("HHOppB2", 300, 60, 60, 60, 60, 20)
	user_ii.add_move(hh)
	ally_ii.add_move(tackle)
	opp_a_ii.add_move(tackle)
	opp_b_ii.add_move(tackle)
	var hh_used := [false]
	var boosted_dmg := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.helping_hand_used.connect(func(_u, _a): hh_used[0] = true)
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == ally_ii and m == tackle and boosted_dmg.is_empty():
			boosted_dmg.append(amount))
	bm1.start_battle_doubles(
			_doubles_party(user_ii, ally_ii), _doubles_party(opp_a_ii, opp_b_ii))
	bm1.queue_free()
	_chk("C.01 Helping Hand fires in doubles", hh_used[0] == true)
	_chk("C.02 the ally's next hit is boosted (strictly more than baseline)",
			boosted_dmg.size() == 1 and boosted_dmg[0] > baseline["damage"])

	# (ii) fails in singles.
	var user_iii := _make_mon("HHUser3", 300, 60, 60, 60, 60, 100)
	var opp_iii := _make_mon("HHOpp3", 300, 60, 60, 60, 60, 50)
	user_iii.add_move(hh)
	opp_iii.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "not_doubles": failed[0] = true)
	bm2.start_battle(user_iii, opp_iii)
	bm2.queue_free()
	_chk("C.03 Helping Hand fails outright in singles", failed[0] == true)

	# (iii) fails if the ally already acted. Helping Hand's own +5 priority
	# means it ALWAYS resolves before an ordinary-priority ally move
	# regardless of speed (confirmed via a debug trace during this test's
	# own first draft, which wrongly assumed a faster ally would act
	# first) — the only realistic way the ally can have already acted is
	# if the ally ALSO used Helping Hand (same +5 bracket), with the
	# slower one finding its own ally already spent.
	var user_iv := _make_mon("HHUser4", 300, 60, 60, 60, 60, 30)
	var ally_iv := _make_mon("HHAlly4", 300, 60, 60, 60, 60, 100)
	var oppa_iv := _make_mon("HHOppA4", 300, 60, 60, 60, 60, 20)
	var oppb_iv := _make_mon("HHOppB4", 300, 60, 60, 60, 60, 10)
	user_iv.add_move(hh)
	ally_iv.add_move(hh)
	oppa_iv.add_move(tackle)
	oppb_iv.add_move(tackle)
	var failed2 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason):
		if reason == "helping_hand_failed" and not failed2[0]: failed2[0] = true)
	bm3.start_battle_doubles(
			_doubles_party(user_iv, ally_iv), _doubles_party(oppa_iv, oppb_iv))
	bm3.queue_free()
	_chk("C.04 Helping Hand fails if the ally already acted this turn " +
			"(here: the ally also used Helping Hand, same +5 bracket, and went first)",
			failed2[0] == true)


# ── Section D: Sleep Talk ────────────────────────────────────────────────

func _test_sleep_talk() -> void:
	var st := _load_move(214)
	var tackle := _load_move(33)
	var solar_beam := _load_move(76)  # two-turn, must be excluded

	# (i) direct unit tests of the pool-picking function.
	var mon_i := _make_mon("STPool1")
	mon_i.add_move(tackle)
	mon_i.status = BattlePokemon.STATUS_SLEEP
	mon_i.sleep_turns = 5
	var picked: MoveData = BattleManager.new()._pick_sleep_talk_move(mon_i, false)
	_chk("D.01 picks the only usable move in the pool", picked == tackle)

	var mon_ii := _make_mon("STPool2")
	mon_ii.add_move(solar_beam)
	mon_ii.status = BattlePokemon.STATUS_SLEEP
	mon_ii.sleep_turns = 5
	var picked2: MoveData = BattleManager.new()._pick_sleep_talk_move(mon_ii, false)
	_chk("D.02 excludes a two-turn move, pool empty -> null", picked2 == null)

	var mon_iii := _make_mon("STPool3")
	mon_iii.add_move(st)  # BAN_SLEEP_TALK on itself
	mon_iii.status = BattlePokemon.STATUS_SLEEP
	mon_iii.sleep_turns = 5
	var picked3: MoveData = BattleManager.new()._pick_sleep_talk_move(mon_iii, false)
	_chk("D.03 excludes Sleep Talk itself (BAN_SLEEP_TALK), pool empty -> null",
			picked3 == null)

	var mon_iv := _make_mon("STPool4")
	mon_iv.add_move(tackle)
	mon_iv.status = BattlePokemon.STATUS_NONE
	var picked4: MoveData = BattleManager.new()._pick_sleep_talk_move(mon_iv, false)
	_chk("D.04 discriminator: returns null when NOT actually asleep (and not Comatose)",
			picked4 == null)

	# (ii) full-battle: fires while genuinely asleep, calls a valid move.
	var atk_v := _make_mon("STAtk5", 300, 60, 60, 60, 60, 60)
	var def_v := _make_mon("STDef5", 300, 60, 60, 60, 60, 50)
	atk_v.add_move(st)
	atk_v.add_move(tackle)
	atk_v.status = BattlePokemon.STATUS_SLEEP
	atk_v.sleep_turns = 5
	def_v.add_move(tackle)
	var called := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_called.connect(func(a, m):
		if a == atk_v and called.is_empty():
			called.append(m))
	bm.start_battle(atk_v, def_v)
	bm.queue_free()
	_chk("D.05 Sleep Talk fires while asleep and calls a valid move",
			called.size() == 1 and called[0] == tackle)


# ── Section E: Taunt ─────────────────────────────────────────────────────

func _test_taunt() -> void:
	var taunt := _load_move(269)
	var growl := _load_move(45)
	var tackle := _load_move(33)

	# (i) blocks a status move ALREADY QUEUED for this same turn, if Taunt
	# (faster) lands before it resolves — execution-time check, not
	# selection-time.
	var atk_i := _make_mon("TauntAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("TauntDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(taunt)
	def_i.add_move(growl)
	var skipped := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_skipped.connect(func(a, reason):
		if a == def_i and reason == "taunt" and not skipped[0]: skipped[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("E.01 Taunt blocks a status move queued the same turn it lands", skipped[0] == true)

	# (ii) discriminator: does NOT block a damaging move.
	var atk_ii := _make_mon("TauntAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("TauntDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(taunt)
	def_ii.add_move(tackle)
	var damage_events := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == def_ii and m == tackle and damage_events.is_empty():
			damage_events.append(amount))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("E.02 discriminator: Taunt does NOT block a damaging move",
			damage_events.size() == 1 and damage_events[0] > 0)

	# (iii) Oblivious blocks infliction.
	var atk_iii := _make_mon("TauntAtk3", 300, 60, 60, 60, 60, 60)
	var def_iii := _make_mon("TauntDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(taunt)
	def_iii.add_move(growl)
	var oblivious := AbilityData.new()
	oblivious.ability_id = AbilityManager.ABILITY_OBLIVIOUS
	def_iii.ability = oblivious
	var blocked3 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason):
		if reason == "oblivious_blocks": blocked3[0] = true)
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	_chk("E.03 Oblivious blocks Taunt infliction", blocked3[0] == true)
	_chk("E.04 discriminator: Oblivious holder's taunt_turns stays 0",
			def_iii.taunt_turns == 0)

	# (iv) duration: 4 turns if the target already acted this turn, 3 if not.
	# Target already acted: target is FASTER than the attacker.
	var atk_iv := _make_mon("TauntAtk4", 300, 60, 60, 60, 60, 50)
	var def_iv := _make_mon("TauntDef4", 300, 60, 60, 60, 60, 100)
	atk_iv.add_move(taunt)
	def_iv.add_move(growl)
	var turns_acted := [-1]
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.taunted.connect(func(_t, turns): if turns_acted[0] == -1: turns_acted[0] = turns)
	bm4.start_battle(atk_iv, def_iv)
	bm4.queue_free()
	_chk("E.05 duration is 4 turns when the target already acted this turn",
			turns_acted[0] == 4)

	# Target hasn't acted yet: target is SLOWER than the attacker.
	var atk_v := _make_mon("TauntAtk5", 300, 60, 60, 60, 60, 100)
	var def_v := _make_mon("TauntDef5", 300, 60, 60, 60, 60, 50)
	atk_v.add_move(taunt)
	def_v.add_move(growl)
	var turns_not_acted := [-1]
	var bm5 := _make_bm()
	bm5._force_hit = true
	bm5.taunted.connect(func(_t, turns): if turns_not_acted[0] == -1: turns_not_acted[0] = turns)
	bm5.start_battle(atk_v, def_v)
	bm5.queue_free()
	_chk("E.06 duration is 3 turns when the target has NOT yet acted this turn",
			turns_not_acted[0] == 3)


# ── Section F: Assurance ─────────────────────────────────────────────────

func _test_assurance() -> void:
	var assurance := _load_move(372)
	var tackle := _load_move(33)

	# (i) baseline: no prior hit this turn.
	var atk_base := _make_mon("AssureAtkBase", 300, 100, 60, 60, 60, 100)
	var def_base := _make_mon("AssureDefBase", 300, 60, 60, 60, 60, 90)
	atk_base.add_move(assurance)
	def_base.add_move(tackle)
	var baseline_events := []
	var bm0 := _make_bm()
	bm0._force_hit = true
	bm0._force_roll = 100
	bm0._force_crit = false
	bm0.move_executed.connect(func(a, _d, m, amount):
		if a == atk_base and m == assurance and baseline_events.is_empty():
			baseline_events.append(amount))
	bm0.start_battle(atk_base, def_base)
	bm0.queue_free()
	_chk("F.01 Assurance deals real baseline damage with no prior hit",
			baseline_events.size() == 1 and baseline_events[0] > 0)

	# (ii) doubles vs "hit by anyone this turn" — in a 2v2, the target is hit
	# by an ALLY of the Assurance user (not the user itself), confirming the
	# scope is genuinely "hit by anyone," not "hit by the user." The ally
	# must be FASTER than the Assurance user so its Tackle resolves first
	# (both moves are ordinary priority 0 here, unlike Helping Hand's own
	# +5 — plain speed order applies).
	var atk_i := _make_mon("AssureAtk1", 300, 100, 60, 60, 60, 50)
	var ally_i := _make_mon("AssureAlly1", 300, 100, 60, 60, 60, 100)
	var def_i := _make_mon("AssureDef1", 300, 60, 60, 60, 60, 10)
	var def2_i := _make_mon("AssureDef2_1", 300, 60, 60, 60, 60, 5)
	atk_i.add_move(assurance)
	ally_i.add_move(tackle)
	def_i.add_move(tackle)
	def2_i.add_move(tackle)
	var doubled_events := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.queue_move_targeted(0, 0, 2)  # atk_i's Assurance -> def_i
	bm1.queue_move_targeted(1, 0, 2)  # ally_i's Tackle -> def_i (hits it first)
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == assurance and doubled_events.is_empty():
			doubled_events.append(amount))
	bm1.start_battle_doubles(_doubles_party(atk_i, ally_i), _doubles_party(def_i, def2_i))
	bm1.queue_free()
	_chk("F.02 Assurance roughly doubles when the target was hit by an ALLY " +
			"(not the user) earlier this turn",
			doubled_events.size() == 1
			and absi(doubled_events[0] - baseline_events[0] * 2) <= 4)


# ── Section G: Magic Coat ────────────────────────────────────────────────

func _test_magic_coat() -> void:
	var magic_coat := _load_move(277)
	var growl := _load_move(45)
	var tackle := _load_move(33)

	# (i) reflects a status move back at its own original user.
	var atk_i := _make_mon("MCAtk1", 300, 60, 60, 60, 60, 60)
	var def_i := _make_mon("MCDef1", 300, 60, 60, 60, 60, 100)
	atk_i.add_move(growl)
	def_i.add_move(magic_coat)
	var bounced := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_bounced.connect(func(_holder, _origin): bounced[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("G.01 Magic Coat reflects a status move back at its user", bounced[0] == true)

	# (ii) discriminator: does NOT reflect a damaging move (not bounceable).
	var atk_ii := _make_mon("MCAtk2", 300, 60, 60, 60, 60, 60)
	var def_ii := _make_mon("MCDef2", 300, 60, 60, 60, 60, 100)
	atk_ii.add_move(tackle)
	def_ii.add_move(magic_coat)
	var bounced2 := [false]
	var damage_events := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_bounced.connect(func(_holder, _origin): bounced2[0] = true)
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk_ii and m == tackle and damage_events.is_empty():
			damage_events.append(amount))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("G.02 discriminator: Magic Coat does NOT reflect a damaging move",
			bounced2[0] == false and damage_events.size() == 1 and damage_events[0] > 0)

	# (iii) Magic-Coat-vs-Magic-Bounce interaction: a status move bounced by
	# Magic Coat onto a Magic-Bounce-holding original attacker does NOT
	# bounce a second time (single non-recursive swap, confirmed via source
	# trace to be the same guarantee Magic Bounce's own vs-Magic-Bounce test
	# already relies on). Growl/Magic Coat never deal damage, so this
	# battle legitimately runs many turns (each one producing its OWN
	# genuine bounce) — a fresh whole-battle-aggregation instance, fixed by
	# recording an ordered timeline and counting only the bounces that
	# happen before Growl's own effect FIRST actually resolves, isolating
	# the very first action instead of the whole battle.
	var atk_iii := _make_mon("MCAtk3", 300, 60, 60, 60, 60, 60)
	var def_iii := _make_mon("MCDef3", 300, 60, 60, 60, 60, 100)
	atk_iii.add_move(growl)
	def_iii.add_move(magic_coat)
	var magic_bounce := AbilityData.new()
	magic_bounce.ability_id = AbilityManager.ABILITY_MAGIC_BOUNCE
	atk_iii.ability = magic_bounce
	var timeline := []
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_bounced.connect(func(_holder, _origin): timeline.append("bounce"))
	bm3.move_executed.connect(func(_a, _d, m, _amt):
		if m == growl:
			timeline.append("executed"))
	bm3.start_battle(atk_iii, def_iii)
	bm3.queue_free()
	var first_exec_idx: int = timeline.find("executed")
	var bounces_before_first_exec: int = 0
	for i in range(first_exec_idx + 1):
		if timeline[i] == "bounce":
			bounces_before_first_exec += 1
	_chk("G.03 Magic-Coat-onto-a-Magic-Bounce-holder bounces exactly ONCE, not twice",
			first_exec_idx >= 0 and bounces_before_first_exec == 1)

	# (iv) magic_coat_active is consumed after firing, and expires at end of
	# turn if it never fires.
	var atk_iv := _make_mon("MCAtk4", 300, 60, 60, 60, 60, 60)
	var def_iv := _make_mon("MCDef4", 300, 60, 60, 60, 60, 100)
	def_iv.add_move(magic_coat)
	atk_iv.add_move(tackle)
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4._force_roll = 100
	bm4._force_crit = false
	bm4.start_battle(atk_iv, def_iv)
	bm4.queue_free()
	_chk("G.04 magic_coat_active expires by the time the battle settles " +
			"(never persists across turns)",
			def_iv.magic_coat_active == false)
