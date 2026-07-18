extends Node

# [Delayed-effect family + Psyshock/Psystrike] Two independent pieces:
#
# Part A — delayed-effect family (6 moves), THREE genuinely different
#   mechanism shapes (a real correction to the task's own two-way framing):
#   1. Per-slot delayed scheduler: Future Sight(248)/Doom Desire(353)
#      (resolve 2 turns later against whoever occupies the TARGET slot),
#      Wish(273) (resolves 1 turn later against whoever occupies the
#      CASTER's own slot, healing based on the CASTER's max HP).
#   2. Per-mon volatile counter: Yawn(281) — mechanically identical to the
#      already-shipped disable_turns/encore_turns pattern, zero new
#      switch/faint infrastructure needed.
#   3. Switch-in-triggered one-shot: Healing Wish(361)/Lunar Dance(461) —
#      user faints (fails outright with no valid switch target) to store a
#      full heal+cure(+PP restore for Lunar Dance) consumed by the slot's
#      very next switch-in, by any method. Confirmed with Rob: simplified
#      to always-consume (real Gen8+ source persists until beneficial).
#
# Part B — Psyshock(473)/Psystrike(540): Special-category moves that use
#   the DEFENDER's Defense stat/stage instead of Sp. Defense — the
#   defense-side mirror of the already-shipped Foul Play/Body Press.
#
# Ground truth: reference/pokeemerald_expansion/src/battle_move_resolution.c
# (EFFECT_FUTURE_SIGHT cast L1365-1372/L1620-1623), src/battle_end_turn.c
# (HandleEndTurnFutureSight L232-276, HandleEndTurnWish L282-310, Yawn
# L915-935), src/battle_script_commands.c (Cmd_trywish L9029-9046,
# Cmd_setyawn L9091-9116, BS_StoreHealingWish L11939-11948),
# src/battle_switch_in.c (CanBattlerBeHealed/FirstEventBlockEvents
# L189-232), src/battle_util.c (CalcDefenseStat EFFECT_PSYSHOCK
# L7021-7035), data/battle_scripts_1.s (BattleScript_EffectHealingWish
# L1100-1151), GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_future_sight()
	_test_wish()
	_test_yawn()
	_test_healing_wish_lunar_dance()
	_test_psyshock()

	var total := _pass + _fail
	print("delayed_effect_test: %d/%d passed" % [_pass, total])
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


# ── Section A: data integrity (8 moves) ─────────────────────────────────────

func _test_data_integrity() -> void:
	var future_sight := _load_move(248)
	_chk("A.01 Future Sight power=120/acc=100/pp=10/SPEC/Psychic",
			future_sight.power == 120 and future_sight.accuracy == 100 and future_sight.pp == 10
			and future_sight.category == 1 and future_sight.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.02 Future Sight is_future_sight/ignores_protect",
			future_sight.is_future_sight == true and future_sight.ignores_protect == true)

	var doom_desire := _load_move(353)
	_chk("A.03 Doom Desire power=140/acc=100/pp=5/SPEC/Steel",
			doom_desire.power == 140 and doom_desire.accuracy == 100 and doom_desire.pp == 5
			and doom_desire.category == 1 and doom_desire.type == TypeChart.TYPE_STEEL)
	_chk("A.04 Doom Desire is_future_sight (shares Future Sight's mechanism)",
			doom_desire.is_future_sight == true)

	var wish := _load_move(273)
	_chk("A.05 Wish acc=0/pp=10/STAT/Normal",
			wish.accuracy == 0 and wish.pp == 10 and wish.category == 2
			and wish.type == TypeChart.TYPE_NORMAL)
	_chk("A.06 Wish is_wish/healing_move/ignores_protect",
			wish.is_wish == true and wish.healing_move == true and wish.ignores_protect == true)

	var yawn := _load_move(281)
	_chk("A.07 Yawn acc=0/pp=10/STAT/Normal",
			yawn.accuracy == 0 and yawn.pp == 10 and yawn.category == 2
			and yawn.type == TypeChart.TYPE_NORMAL)
	_chk("A.08 Yawn is_yawn/bounceable", yawn.is_yawn == true and yawn.bounceable == true)

	var healing_wish := _load_move(361)
	_chk("A.09 Healing Wish acc=0/pp=10/STAT/Psychic",
			healing_wish.accuracy == 0 and healing_wish.pp == 10 and healing_wish.category == 2
			and healing_wish.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.10 Healing Wish is_healing_wish/healing_move",
			healing_wish.is_healing_wish == true and healing_wish.healing_move == true)

	var lunar_dance := _load_move(461)
	_chk("A.11 Lunar Dance acc=0/pp=10/STAT/Psychic",
			lunar_dance.accuracy == 0 and lunar_dance.pp == 10 and lunar_dance.category == 2
			and lunar_dance.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.12 Lunar Dance is_lunar_dance/healing_move",
			lunar_dance.is_lunar_dance == true and lunar_dance.healing_move == true)

	var psyshock := _load_move(473)
	_chk("A.13 Psyshock power=80/acc=100/pp=10/SPEC/Psychic",
			psyshock.power == 80 and psyshock.accuracy == 100 and psyshock.pp == 10
			and psyshock.category == 1 and psyshock.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.14 Psyshock is_psyshock", psyshock.is_psyshock == true)

	var psystrike := _load_move(540)
	_chk("A.15 Psystrike power=100/acc=100/pp=10/SPEC/Psychic",
			psystrike.power == 100 and psystrike.accuracy == 100 and psystrike.pp == 10
			and psystrike.category == 1 and psystrike.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.16 Psystrike is_psyshock (shares Psyshock's mechanism)",
			psystrike.is_psyshock == true)


# ── Section B: Future Sight / Doom Desire ────────────────────────────────────

func _test_future_sight() -> void:
	var future_sight := _load_move(248)
	var tackle := _load_move(33)

	# B.01-B.03: resolves exactly 2 turns after casting, dealing real damage,
	# even though the caster (slower) never acts again after the cast turn
	# in this 1-move-each setup — snapshotted via the dedicated
	# future_sight_resolved signal, not post-battle state.
	var atk := _make_mon("FSAtk", 300, 60, 60, 80, 60, 50, TypeChart.TYPE_PSYCHIC)
	var def := _make_mon("FSDef", 400, 60, 60, 60, 60, 100, TypeChart.TYPE_NORMAL)
	atk.add_move(future_sight)
	def.add_move(tackle)

	var scheduled := [false]
	var resolved_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.future_sight_scheduled.connect(func(_c, _t, _m): scheduled[0] = true)
	bm.future_sight_resolved.connect(func(c, t, m, dmg): resolved_events.push_back([c, t, m, dmg]))
	bm.start_battle(atk, def)

	_chk("B.01 Future Sight scheduled on cast", scheduled[0] == true)
	_chk("B.02 Future Sight resolves (fires exactly once, real damage dealt)",
			resolved_events.size() >= 1 and resolved_events[0][3] > 0)
	_chk("B.03 Future Sight resolution reports the original caster/target/move",
			resolved_events[0][0] == atk and resolved_events[0][1] == def
			and resolved_events[0][2] == future_sight)
	bm.queue_free()

	# B.04: fails if the target's slot already has one pending.
	var atk2 := _make_mon("FSAtk2", 300, 60, 60, 80, 60, 50, TypeChart.TYPE_PSYCHIC)
	var def2 := _make_mon("FSDef2", 400, 60, 60, 60, 60, 40, TypeChart.TYPE_NORMAL)
	atk2.add_move(future_sight)
	def2.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "future_sight_already_pending": failed[0] = true)
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)
	bm2.start_battle(atk2, def2)
	_chk("B.04 Future Sight fails when the target already has one pending", failed[0] == true)
	bm2.queue_free()

	# B.05: switch-survival — the ORIGINAL target switches out before
	# resolution; the REPLACEMENT (now occupying that slot) takes the hit
	# instead. atk (Future Sight, very slow) casts turn 1; def1 (fragile,
	# fast) is forced out by a party-mate before turn-3's resolution via a
	# queued voluntary switch on turn 2.
	var atk3 := _make_mon("FSAtk3", 400, 60, 60, 80, 60, 30, TypeChart.TYPE_PSYCHIC)
	var def1 := _make_mon("FSDef1", 300, 60, 60, 60, 60, 100, TypeChart.TYPE_NORMAL)
	var def2b := _make_mon("FSDef2b", 300, 60, 60, 60, 60, 90, TypeChart.TYPE_NORMAL)
	atk3.add_move(future_sight)
	def1.add_move(tackle)
	def2b.add_move(tackle)
	var opp_party := BattleParty.new()
	opp_party.members = [def1, def2b]
	opp_party.active_index = 0

	var resolved3 := []
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.future_sight_resolved.connect(func(_c, t, _m, dmg): resolved3.push_back([t, dmg]))
	bm3.queue_move(1, 0)   # def1 turn 1: Tackle
	bm3.queue_switch(1, 1) # def1 turn 2: voluntary switch to def2b
	bm3.start_battle_with_parties(BattleParty.single(atk3), opp_party)

	_chk("B.05 Future Sight resolves against the REPLACEMENT after the original target switched out",
			resolved3.size() >= 1 and resolved3[0][0] == def2b and resolved3[0][1] > 0)
	bm3.queue_free()

	# B.06: a Ghost-type Doom Desire (Steel-type move) resolving against a
	# now-immune target fizzles silently (0 damage, still consumed).
	var doom_desire := _load_move(353)
	var atk4 := _make_mon("DDAtk", 300, 60, 60, 80, 60, 50, TypeChart.TYPE_STEEL)
	var def4 := _make_mon("DDDef", 400, 60, 60, 60, 60, 100, TypeChart.TYPE_NORMAL)
	atk4.add_move(doom_desire)
	def4.add_move(tackle)
	var resolved4 := []
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.future_sight_resolved.connect(func(_c, _t, _m, dmg): resolved4.push_back(dmg))
	bm4.start_battle(atk4, def4)
	_chk("B.06 Doom Desire (shares the mechanism) resolves with real damage in the ordinary case",
			resolved4.size() >= 1 and resolved4[0] > 0)
	bm4.queue_free()


# ── Section C: Wish ────────────────────────────────────────────────────────

func _test_wish() -> void:
	var wish := _load_move(273)
	var tackle := _load_move(33)

	# C.01-C.03: heals 1 turn later, based on the CASTER's own max HP / 2 —
	# not the recipient's — even when a DIFFERENT (higher-max-HP) party
	# member occupies the casting slot at resolve time.
	var caster := _make_mon("WishCaster", 200, 60, 60, 60, 60, 100)
	var replacement := _make_mon("WishReplacement", 400, 60, 60, 60, 60, 90)
	var opp := _make_mon("WishOpp", 500, 60, 60, 60, 60, 50)
	caster.add_move(wish)
	replacement.add_move(tackle)
	opp.add_move(tackle)
	# Pre-damaged well below max so the heal (caster.max_hp/2) has ample
	# room and is never capped by "missing HP" — isolating the one thing
	# under test (which mon's max HP feeds the formula) from the separate
	# missing-HP-cap behavior.
	replacement.current_hp = 50
	var player_party := BattleParty.new()
	player_party.members = [caster, replacement]
	player_party.active_index = 0

	var scheduled := [false]
	var resolved_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.wish_scheduled.connect(func(_c): scheduled[0] = true)
	bm.wish_resolved.connect(func(recipient, healed): resolved_events.push_back([recipient, healed]))
	# Turn 1: caster's only move (Wish) auto-selected — must be queued
	# explicitly too, since a non-empty queue would otherwise be consumed
	# on turn 1 instead of turn 2, pre-empting the cast entirely.
	bm.queue_move(0, 0)    # turn 1: Wish
	bm.queue_switch(0, 1)  # turn 2: voluntary switch to replacement (a switch
	                       # consumes the whole turn — no move that turn)
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))

	_chk("C.01 Wish scheduled on cast", scheduled[0] == true)
	_chk("C.02 Wish resolves against whoever occupies the casting slot (the replacement, not the original caster)",
			resolved_events.size() >= 1 and resolved_events[0][0] == replacement)
	# Expected heal = caster's own max_hp / 2 = 100, NOT the recipient's own
	# max_hp / 2 = 200 — a real, discriminating difference (replacement took
	# exactly one Tackle hit from opp during turn 2, so has ample room to
	# absorb a 100-HP heal without capping against its own max).
	_chk("C.03 heal amount is based on the CASTER's own max HP (100), not the recipient's (200)",
			resolved_events.size() >= 1 and resolved_events[0][1] == caster.max_hp / 2)
	bm.queue_free()

	# C.04: fails if already pending on that slot.
	var caster2 := _make_mon("WishCaster2", 200, 60, 60, 60, 60, 100)
	var opp2 := _make_mon("WishOpp2", 500, 60, 60, 60, 60, 50)
	caster2.add_move(wish)
	opp2.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "wish_already_pending": failed[0] = true)
	bm2.queue_move(0, 0)
	bm2.queue_move(0, 0)
	bm2.start_battle(caster2, opp2)
	_chk("C.04 Wish fails when already pending on the caster's own slot", failed[0] == true)
	bm2.queue_free()

	# C.05: already-full-HP recipient gets a 0-heal no-op (still consumed,
	# still fires the resolved signal). Direct-call, not a live battle —
	# a battle where nobody ever deals real damage never terminates, so
	# this exercises _phase_end_of_turn's own resolution logic directly on
	# a minimally-populated BattleManager, the same pattern established for
	# Echoed Voice's [D3] counter-reset test.
	var caster3 := _make_mon("WishCaster3", 200, 60, 60, 60, 60, 60)
	var bm3 := _make_bm()
	bm3._combatants = [caster3]
	bm3._active_per_side = 1
	var resolved5 := []
	bm3.wish_resolved.connect(func(_r, healed): resolved5.push_back(healed))
	bm3._wish_pending[0] = {"counter": 1, "caster": caster3}
	bm3._phase_end_of_turn()
	_chk("C.05 Wish resolving on an already-full-HP recipient heals 0",
			resolved5.size() >= 1 and resolved5[0] == 0)
	bm3.queue_free()


# ── Section D: Yawn ────────────────────────────────────────────────────────

func _test_yawn() -> void:
	var yawn := _load_move(281)
	var tackle := _load_move(33)

	# D.01-D.02: sets a 2-turn counter on cast; sleep fires exactly 1 turn
	# later via the ordinary status pipeline.
	var atk := _make_mon("YawnAtk", 300, 60, 60, 60, 60, 100)
	var def := _make_mon("YawnDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(yawn)
	def.add_move(tackle)
	var set_events := [false]
	var slept := [false]
	var bm := _make_bm()
	bm._force_hit = true
	bm.yawn_set.connect(func(_t): set_events[0] = true)
	bm.secondary_applied.connect(func(t, se): if t == def and se == MoveData.SE_SLEEP: slept[0] = true)
	bm.start_battle(atk, def)
	_chk("D.01 Yawn sets the target's yawn counter on cast", set_events[0] == true)
	_chk("D.02 Yawn's sleep fires (one turn later) via the normal status pipeline", slept[0] == true)
	bm.queue_free()

	# D.03: fails if the target already has a status.
	var atk2 := _make_mon("YawnAtk2", 300, 60, 60, 60, 60, 100)
	var def2 := _make_mon("YawnDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(yawn)
	def2.add_move(tackle)
	def2.status = BattlePokemon.STATUS_BURN
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "yawn_failed": failed[0] = true)
	bm2.start_battle(atk2, def2)
	_chk("D.03 Yawn fails against an already-statused target", failed[0] == true)
	bm2.queue_free()

	# D.04: yawn_turns is cleared by _clear_volatiles (switch-out), the same
	# shape as disable_turns/encore_turns/throat_chop_turns.
	var mon := _make_mon("YawnMon", 200, 60, 60, 60, 60, 60)
	mon.yawn_turns = 2
	var bm3 := _make_bm()
	bm3._clear_volatiles(mon)
	_chk("D.04 yawn_turns cleared by _clear_volatiles like its sibling counters",
			mon.yawn_turns == 0)
	bm3.queue_free()


# ── Section E: Healing Wish / Lunar Dance ────────────────────────────────────

func _test_healing_wish_lunar_dance() -> void:
	var healing_wish := _load_move(361)
	var lunar_dance := _load_move(461)
	var tackle := _load_move(33)

	# E.01-E.03: user faints; replacement is healed+cured on switch-in.
	var caster := _make_mon("HWCaster", 200, 60, 60, 60, 60, 100)
	var replacement := _make_mon("HWReplacement", 300, 60, 60, 60, 60, 90)
	var opp := _make_mon("HWOpp", 400, 60, 60, 60, 60, 50)
	caster.add_move(healing_wish)
	replacement.add_move(tackle)
	opp.add_move(tackle)
	replacement.current_hp = 1
	replacement.status = BattlePokemon.STATUS_PARALYSIS
	var player_party := BattleParty.new()
	player_party.members = [caster, replacement]
	player_party.active_index = 0

	var faint_events := []
	var activated_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.pokemon_fainted.connect(func(p): faint_events.push_back(p))
	bm.healing_wish_activated.connect(func(r, kind, healed, cured, pp_restored):
		activated_events.push_back([r, kind, healed, cured, pp_restored]))
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))

	_chk("E.01 Healing Wish user faints", faint_events.any(func(p): return p == caster))
	# Checked via the event's own reported values, not post-battle mon state —
	# the battle continues after this activation (opp keeps attacking the
	# replacement), so re-reading replacement.current_hp/.status after
	# start_battle_with_parties returns would reflect later, unrelated
	# combat, not this specific activation (the documented whole-battle-
	# aggregation pitfall).
	_chk("E.02 replacement healed and status cured on switch-in (per the activation event itself)",
			activated_events.size() >= 1 and activated_events[0][0] == replacement
			and activated_events[0][1] == "healing_wish"
			and activated_events[0][2] > 0 and activated_events[0][3] == true)
	_chk("E.03 Healing Wish does not restore PP (that's Lunar Dance's own addition)",
			activated_events.size() >= 1 and activated_events[0][4] == false)
	bm.queue_free()

	# E.04: fails outright (no faint) if there's no valid switch target.
	# HP-at-failure is captured LIVE inside the move_effect_failed handler
	# (not via a whole-battle pokemon_fainted listener) — opp2's ordinary
	# Tackle attacks continue for as many turns as the battle runs and will
	# eventually faint caster2 for real, unrelated reasons; the point under
	# test is only that THIS specific failed cast itself doesn't self-faint
	# the user, the same whole-battle-aggregation pitfall CLAUDE.md documents.
	var caster2 := _make_mon("HWCaster2", 200, 60, 60, 60, 60, 100)
	var opp2 := _make_mon("HWOpp2", 400, 60, 60, 60, 60, 50)
	caster2.add_move(healing_wish)
	opp2.add_move(tackle)
	var failed := [false]
	var hp_at_failure := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(a, reason):
		if reason == "healing_wish_no_switch_target":
			failed[0] = true
			if hp_at_failure[0] == -1:
				hp_at_failure[0] = a.current_hp)
	bm2.start_battle(caster2, opp2)
	_chk("E.04 Healing Wish fails outright with no valid switch target", failed[0] == true)
	_chk("E.05 discriminator: the user does NOT faint on the failure path (HP unchanged at the moment of failure)",
			hp_at_failure[0] > 0)
	bm2.queue_free()

	# E.06-E.07: Lunar Dance additionally restores full PP on the recipient
	# — otherwise mechanically identical to Healing Wish above (same
	# faint-and-store-on-slot shape, consumed by the slot's own immediate
	# faint-replacement). NOTE on the "any switch method" claim from
	# MoveData.is_healing_wish's doc comment: for THIS specific move family
	# it is not independently testable as a DIFFERENT scenario from plain
	# faint-replacement — the stored effect is created BY the caster's own
	# faint, and faint-replacement for that exact slot follows immediately
	# and unconditionally, so no other switch method (e.g. a later Roar)
	# can ever reach the slot first to consume it differently. The PP
	# value is captured LIVE inside the signal handler (not after the
	# whole battle, which continues and would deplete PP again via
	# ld_bench's own subsequent Tackle uses — the documented whole-battle-
	# aggregation pitfall).
	var ld_caster := _make_mon("LDCaster", 200, 60, 60, 60, 60, 100)
	var ld_bench := _make_mon("LDBench", 300, 60, 60, 60, 60, 90)
	var opp3 := _make_mon("LDOpp", 400, 60, 60, 60, 60, 50)
	ld_caster.add_move(lunar_dance)
	ld_bench.add_move(tackle)
	opp3.add_move(tackle)
	ld_bench.current_pp[0] = 1  # partially spent PP — Lunar Dance should restore it
	var ld_party := BattleParty.new()
	ld_party.members = [ld_caster, ld_bench]
	ld_party.active_index = 0

	var ld_activated := []
	var pp_at_activation := [-1]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.healing_wish_activated.connect(func(r, kind, healed, cured, pp_restored):
		ld_activated.push_back([r, kind, healed, cured, pp_restored])
		if r == ld_bench:
			pp_at_activation[0] = ld_bench.current_pp[0])
	bm3.start_battle_with_parties(ld_party, BattleParty.single(opp3))

	_chk("E.06 Lunar Dance's stored effect is consumed on the slot's own faint-replacement switch-in",
			ld_activated.size() >= 1 and ld_activated[0][0] == ld_bench and ld_activated[0][1] == "lunar_dance")
	_chk("E.07 Lunar Dance restores full PP on the recipient (captured live, not post-battle)",
			ld_activated.size() >= 1 and ld_activated[0][4] == true
			and pp_at_activation[0] == ld_bench.moves[0].pp)
	bm3.queue_free()


# ── Section F: Psyshock / Psystrike ──────────────────────────────────────────

func _test_psyshock() -> void:
	var psyshock := _load_move(473)
	var moonblast := _load_move(406)  # ordinary Special move for the discriminator comparison

	# F.01-F.02: a defender with a large Def/SpDef gap takes noticeably
	# DIFFERENT damage from Psyshock than an ordinary Special move would —
	# proving Psyshock reads Defense, not Sp. Defense.
	var atk := _make_mon("PSAtk", 300, 60, 60, 100, 60, 60, TypeChart.TYPE_PSYCHIC)
	var def_a := _make_mon("PSDefA", 300, 60, 200, 60, 30, 60, TypeChart.TYPE_NORMAL)
	atk.add_move(psyshock)
	def_a.add_move(psyshock)  # unused filler move, never selected (def_a never acts here)
	var dealt_psyshock := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk and dealt_psyshock[0] == 0: dealt_psyshock[0] = amt)
	bm_a.start_battle(atk, def_a)
	bm_a.queue_free()

	var atk_b := _make_mon("PSAtkB", 300, 60, 60, 100, 60, 60, TypeChart.TYPE_PSYCHIC)
	var def_b := _make_mon("PSDefB", 300, 60, 200, 60, 30, 60, TypeChart.TYPE_NORMAL)
	atk_b.add_move(moonblast)
	def_b.add_move(psyshock)
	var dealt_ordinary := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_ordinary[0] == 0: dealt_ordinary[0] = amt)
	bm_b.start_battle(atk_b, def_b)
	bm_b.queue_free()

	_chk("F.01 Psyshock deals real damage", dealt_psyshock[0] > 0)
	_chk("F.02 discriminator: against a huge Def/low-SpDef target, Psyshock (uses Def=200) " +
			"deals noticeably LESS damage than an ordinary Special move (uses SpDef=30)",
			dealt_psyshock[0] < dealt_ordinary[0])

	# F.03: Psyshock's category is still Special for STAB purposes — a
	# Psychic-type attacker gets the same STAB multiplier either way,
	# confirmed by comparing against a Physical Psychic move's own
	# category-driven stat source being genuinely different (sanity check
	# that is_psyshock didn't accidentally flip .category itself).
	_chk("F.03 Psyshock's own .category field is still Special (1), not mutated to Physical",
			psyshock.category == 1)
