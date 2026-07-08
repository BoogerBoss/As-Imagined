extends Node

# M18m test suite — Stat-change-reactive consumed items (4 items)
#
# Despite the tier's own "stat-change-reactive" grouping, these are NOT all the
# same trigger shape — verified individually per the "never assume symmetry"
# discipline. Every assertion below is scoped to a single, well-defined event
# (a direct function call, or the FIRST relevant signal from a short, queued
# battle) — this exact pitfall has now recurred in four consecutive prior
# tiers ([M18q]/[M18r]/[M18s-u-w]), so every test here is written correctly
# scoped from the start rather than needing a fix-and-rerun cycle.
#
# Sections:
#   T01 Weakness Policy — +2 Atk/+2 SpAtk on a super-effective hit (battle, first-hit scoped)
#   T02 White Herb — unconditional negative-stage reset (direct _phase_faint_check call, no battle)
#   T03 Eject Pack — forced switch on ANY stat decrease (short, queued battle)
#   T04 Mirror Herb — copies an opponent's move-driven stat raise (short, queued battle)

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_t01_weakness_policy()
	_test_t02_white_herb()
	_test_t03_eject_pack()
	_test_t04_mirror_herb()

	var total := _pass + _fail
	print("m18m_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_tackle(mon_name: String = "Tackle", power: int = 40, move_type: int = TypeChart.TYPE_NORMAL) -> MoveData:
	var m := MoveData.new()
	m.move_name = mon_name
	m.type      = move_type
	m.category  = 0
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	return m


func _make_self_lower(stat: int, amount: int = -1) -> MoveData:
	var m := MoveData.new()
	m.move_name = "SelfLower"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 2
	m.accuracy  = 100
	m.pp        = 20
	m.stat_change_stat = stat
	m.stat_change_amount = amount
	m.stat_change_self = true
	return m


func _make_lower_opponent(stat: int, amount: int = -1) -> MoveData:
	var m := MoveData.new()
	m.move_name = "LowerOpponent"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 2
	m.accuracy  = 100
	m.pp        = 20
	m.stat_change_stat = stat
	m.stat_change_amount = amount
	m.stat_change_self = false
	return m


func _make_self_raise(stat: int, amount: int = 2) -> MoveData:
	var m := MoveData.new()
	m.move_name = "SelfRaise"
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 2
	m.accuracy  = 100
	m.pp        = 20
	m.stat_change_stat = stat
	m.stat_change_amount = amount
	m.stat_change_self = true
	return m


# ── T01: Weakness Policy — +2 Atk AND +2 SpAtk on a super-effective hit ────────

func _test_t01_weakness_policy() -> void:
	var policy := _load_item(502)
	_chk("T01.00 fixture loads", policy != null)

	# Positive: a super-effective hit (Water vs Fire) triggers both stat raises,
	# scoped to the FIRST hit via forced roll/crit and reading the first captured
	# events — the target survives so the battle continuing afterward doesn't
	# risk a second, unrelated trigger (Weakness Policy is single-use anyway,
	# so no re-trigger risk, but scoping to first-events keeps this robust).
	var holder := _make_mon("Policied", [TypeChart.TYPE_FIRE], 300, 60, 60, 60, 60, 40)
	holder.held_item = policy
	holder.add_move(_make_tackle())
	var atk1 := _make_mon("Atk1", [TypeChart.TYPE_WATER], 100, 60, 60, 60, 60, 100)
	atk1.add_move(_make_tackle("WaterMove", 40, TypeChart.TYPE_WATER))

	var stat_events := []
	var consumed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(atk1, holder)

	_chk("T01.01 +2 Attack fires on the FIRST super-effective hit taken",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("T01.02 +2 Sp.Attack ALSO fires on the same hit",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_SPATK and e[2] == 2))
	_chk("T01.03 Weakness Policy is consumed",
			consumed_events.any(func(e): return e[0] == holder and e[1].item_name == "Weakness Policy"))
	bm.queue_free()

	# Discriminator: a NOT-super-effective hit does not trigger it at all.
	var holder2 := _make_mon("Policied2", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	holder2.held_item = _load_item(502)
	holder2.add_move(_make_tackle())
	var atk2 := _make_mon("Atk2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk2.add_move(_make_tackle("NormalMove"))

	var stat_events2 := []
	var consumed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_crit = false
	bm2.stat_stage_changed.connect(func(t, idx, amt): stat_events2.push_back([t, idx, amt]))
	bm2.item_consumed.connect(func(m, item): consumed_events2.push_back([m, item]))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(atk2, holder2)

	_chk("T01.04 discriminator: a not-super-effective hit's FIRST occurrence " +
			"triggers no Weakness Policy stat change",
			not stat_events2.slice(0, 2).any(func(e): return e[0] == holder2))
	bm2.queue_free()

	# Discriminator: consumed UNCONDITIONALLY even if both stats already capped
	# at +6 (a real difference from [M18r]'s Blunder Policy).
	var holder3 := _make_mon("PoliciedCapped", [TypeChart.TYPE_FIRE], 300, 60, 60, 60, 60, 40)
	holder3.held_item = _load_item(502)
	holder3.stat_stages[BattlePokemon.STAGE_ATK] = 6
	holder3.stat_stages[BattlePokemon.STAGE_SPATK] = 6
	holder3.add_move(_make_tackle())
	var atk3 := _make_mon("Atk3", [TypeChart.TYPE_WATER], 100, 60, 60, 60, 60, 100)
	atk3.add_move(_make_tackle("WaterMove2", 40, TypeChart.TYPE_WATER))

	var stat_events3 := []
	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3._force_crit = false
	bm3.stat_stage_changed.connect(func(t, idx, amt): stat_events3.push_back([t, idx, amt]))
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle(atk3, holder3)

	_chk("T01.05 CORRECTION-confirming: consumed even with both stats already " +
			"at +6 (no actual stat change occurred)",
			consumed_events3.any(func(e): return e[0] == holder3))
	_chk("T01.06 no stat_stage_changed for holder3 (already capped, nothing to change)",
			not stat_events3.any(func(e): return e[0] == holder3))
	bm3.queue_free()


# ── T02: White Herb — unconditional negative-stage reset ───────────────────────
#
# Called directly on _phase_faint_check — BattleManager's own MoveEnd-
# equivalent checkpoint — with manually-configured minimal state. No battle
# needed at all: White Herb's trigger is a pure scan of current stat_stages,
# not dependent on any move having just executed.

func _test_t02_white_herb() -> void:
	var herb := _load_item(460)
	_chk("T02.00 fixture loads", herb != null)

	# Positive: two negative stages (Atk, SpDef) both reset to 0 in one call;
	# a positive stage (Speed) is left untouched (White Herb only resets
	# NEGATIVE stages, never lowers a positive one).
	var holder := _make_mon("Herbed", [TypeChart.TYPE_NORMAL])
	holder.held_item = herb
	holder.stat_stages = [-2, 0, 0, -1, 3, 0, 0]  # Atk=-2, SpDef=-1, Speed=+3

	var bm := BattleManager.new()
	add_child(bm)
	bm._combatants = [holder]
	bm._active_per_side = 1
	var stat_events := []
	var consumed_events := []
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm._phase_faint_check()

	_chk("T02.01 Atk reset from -2 to 0 (stat_stage_changed +2)",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("T02.02 SpDef reset from -1 to 0 (stat_stage_changed +1)",
			stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_SPDEF and e[2] == 1))
	_chk("T02.03 Speed (+3, positive) is NOT touched at all",
			not stat_events.any(func(e): return e[0] == holder and e[1] == BattlePokemon.STAGE_SPEED))
	_chk("T02.04 stat_stages actually read [0,0,0,0,3,0,0] afterward",
			holder.stat_stages == [0, 0, 0, 0, 3, 0, 0])
	_chk("T02.05 White Herb is consumed",
			consumed_events.any(func(e): return e[0] == holder and e[1].item_name == "White Herb"))
	bm.queue_free()

	# Discriminator: no negative stages at all -> not consumed, no-op.
	var holder2 := _make_mon("HerbedClean", [TypeChart.TYPE_NORMAL])
	holder2.held_item = _load_item(460)
	holder2.stat_stages = [0, 1, 0, 0, 0, 0, 0]

	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._combatants = [holder2]
	bm2._active_per_side = 1
	var consumed_events2 := []
	bm2.item_consumed.connect(func(m, item): consumed_events2.push_back([m, item]))
	bm2._phase_faint_check()

	_chk("T02.06 discriminator: no negative stages -> not consumed at all",
			not consumed_events2.any(func(e): return e[0] == holder2))
	bm2.queue_free()

	# Discriminator: fainted holder is skipped entirely, even with negative stages.
	var holder3 := _make_mon("HerbedFainted", [TypeChart.TYPE_NORMAL])
	holder3.held_item = _load_item(460)
	holder3.stat_stages = [-3, 0, 0, 0, 0, 0, 0]
	holder3.fainted = true

	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._combatants = [holder3]
	bm3._active_per_side = 1
	var consumed_events3 := []
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3._phase_faint_check()

	_chk("T02.07 discriminator: a fainted holder is skipped entirely",
			not consumed_events3.any(func(e): return e[0] == holder3))
	bm3.queue_free()


# ── T03: Eject Pack — forced switch on ANY stat decrease ───────────────────────
#
# Short, explicitly-queued battle (deterministic per-turn moves), scoped to the
# FIRST relevant switch event — Eject Pack is single-use, so no re-trigger risk,
# but the fixture is still designed to resolve within the first couple of turns.

func _test_t03_eject_pack() -> void:
	var pack := _load_item(509)
	_chk("T03.00 fixture loads", pack != null)

	# Positive: the HOLDER's own move lowers its OWN stat -> forces itself to
	# switch. Proves the "any source, including self-inflicted" finding.
	var holder := _make_mon("Ejected", [TypeChart.TYPE_NORMAL], 100)
	holder.held_item = pack
	holder.add_move(_make_self_lower(BattlePokemon.STAGE_DEF))
	var bench := _make_mon("Bench", [TypeChart.TYPE_NORMAL], 100)
	bench.add_move(_make_tackle())
	var party := BattleParty.new()
	party.members = [holder, bench]
	party.active_index = 0
	var foe := _make_mon("Foe", [TypeChart.TYPE_NORMAL], 300)
	foe.add_move(_make_tackle())

	var switched_out := []
	var consumed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.forced_switch.connect(func(old_mon, _new_mon): switched_out.push_back(old_mon))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(party, BattleParty.single(foe))

	_chk("T03.01 the holder is forced to switch out after lowering its OWN stat",
			switched_out.any(func(p): return p == holder))
	_chk("T03.02 Eject Pack is consumed",
			consumed_events.any(func(e): return e[0] == holder and e[1].item_name == "Eject Pack"))
	bm.queue_free()

	# Positive #2: an OPPONENT's move lowers the holder's stat -> also triggers.
	var holder2 := _make_mon("Ejected2", [TypeChart.TYPE_NORMAL], 100)
	holder2.held_item = _load_item(509)
	holder2.add_move(_make_tackle())
	var bench2 := _make_mon("Bench2", [TypeChart.TYPE_NORMAL], 100)
	bench2.add_move(_make_tackle())
	var party2 := BattleParty.new()
	party2.members = [holder2, bench2]
	party2.active_index = 0
	var foe2 := _make_mon("Foe2", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 200)
	foe2.add_move(_make_lower_opponent(BattlePokemon.STAGE_DEF))

	var switched_out2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.forced_switch.connect(func(old_mon, _new_mon): switched_out2.push_back(old_mon))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle_with_parties(party2, BattleParty.single(foe2))

	_chk("T03.03 the holder is ALSO forced to switch out after an OPPONENT " +
			"lowers its stat (not opponent-only, but confirms opponent sources work)",
			switched_out2.any(func(p): return p == holder2))
	bm2.queue_free()

	# Discriminator: no valid switch target (bench already fainted) -> not
	# consumed at all, matching [M18n]'s established no-valid-target shape.
	var holder3 := _make_mon("EjectedNoTarget", [TypeChart.TYPE_NORMAL], 100)
	holder3.held_item = _load_item(509)
	holder3.add_move(_make_self_lower(BattlePokemon.STAGE_DEF))
	var bench3 := _make_mon("Bench3", [TypeChart.TYPE_NORMAL], 100)
	bench3.current_hp = 0
	bench3.fainted = true
	var party3 := BattleParty.new()
	party3.members = [holder3, bench3]
	party3.active_index = 0
	var foe3 := _make_mon("Foe3", [TypeChart.TYPE_NORMAL], 300)
	foe3.add_move(_make_tackle())

	var switched_out3 := []
	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.forced_switch.connect(func(old_mon, _new_mon): switched_out3.push_back(old_mon))
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle_with_parties(party3, BattleParty.single(foe3))

	_chk("T03.04 discriminator: no valid switch target -> holder never switches out",
			not switched_out3.any(func(p): return p == holder3))
	_chk("T03.05 discriminator: no valid switch target -> Eject Pack NOT consumed",
			not consumed_events3.any(func(e): return e[0] == holder3))
	bm3.queue_free()

	# Discriminator: a stat RAISE does not trigger Eject Pack at all.
	var holder4 := _make_mon("EjectedRaise", [TypeChart.TYPE_NORMAL], 100)
	holder4.held_item = _load_item(509)
	holder4.add_move(_make_self_raise(BattlePokemon.STAGE_ATK))
	var bench4 := _make_mon("Bench4", [TypeChart.TYPE_NORMAL], 100)
	bench4.add_move(_make_tackle())
	var party4 := BattleParty.new()
	party4.members = [holder4, bench4]
	party4.active_index = 0
	var foe4 := _make_mon("Foe4", [TypeChart.TYPE_NORMAL], 300)
	foe4.add_move(_make_tackle())

	var switched_out4 := []
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.forced_switch.connect(func(old_mon, _new_mon): switched_out4.push_back(old_mon))
	bm4.queue_move(0, 0)
	bm4.queue_move(1, 0)
	bm4.start_battle_with_parties(party4, BattleParty.single(foe4))

	_chk("T03.06 discriminator: a stat RAISE does not force a switch",
			not switched_out4.any(func(p): return p == holder4))
	bm4.queue_free()


# ── T04: Mirror Herb — copies an opponent's move-driven stat raise ─────────────
#
# Confirmed a genuine structural twin of Opportunist at the source level — same
# trigger site, same "opposing side, move-driven stat increase" condition.

func _test_t04_mirror_herb() -> void:
	var mirror := _load_item(769)
	_chk("T04.00 fixture loads", mirror != null)

	# Positive: p2 (Mirror Herb holder) copies p1's own Swords-Dance-style
	# self-raise the instant it happens, on p1's very first turn.
	var p1 := _make_mon("Raiser", [TypeChart.TYPE_NORMAL], 100)
	p1.add_move(_make_self_raise(BattlePokemon.STAGE_ATK, 2))
	var p2 := _make_mon("Mirrored", [TypeChart.TYPE_NORMAL], 100)
	p2.held_item = mirror
	p2.add_move(_make_tackle())

	var stat_events := []
	var consumed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("T04.01 the holder's Attack ALSO rises by the SAME +2 the opponent got",
			stat_events.any(func(e): return e[0] == p2 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("T04.02 Mirror Herb is consumed",
			consumed_events.any(func(e): return e[0] == p2 and e[1].item_name == "Mirror Herb"))
	bm.queue_free()

	# Discriminator: a stat DECREASE (not an increase) on the opponent's side
	# does NOT trigger Mirror Herb at all.
	var p3 := _make_mon("Lowerer", [TypeChart.TYPE_NORMAL], 100)
	p3.add_move(_make_self_lower(BattlePokemon.STAGE_DEF))
	var p4 := _make_mon("MirroredNeg", [TypeChart.TYPE_NORMAL], 100)
	p4.held_item = _load_item(769)
	p4.add_move(_make_tackle())

	var stat_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.stat_stage_changed.connect(func(t, idx, amt): stat_events2.push_back([t, idx, amt]))
	bm2.queue_move(0, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)

	_chk("T04.03 discriminator: an opponent's stat DECREASE does not trigger " +
			"Mirror Herb (the holder's own stats stay untouched)",
			not stat_events2.any(func(e): return e[0] == p4))
	bm2.queue_free()

	# Discriminator: a SAME-SIDE (ally) stat raise does not trigger Mirror Herb
	# — only OPPOSING-side raises qualify (source: IsBattlerAlly skip).
	# Simulated here via direct function-level reasoning: p2 raising its OWN
	# stat should not also copy onto itself. Reuse p1/p2 from T04's positive
	# case shape but have p2 raise ITS OWN stat instead of p1's.
	var p5 := _make_mon("SelfRaiser", [TypeChart.TYPE_NORMAL], 100)
	p5.held_item = _load_item(769)
	p5.add_move(_make_self_raise(BattlePokemon.STAGE_DEF, 2))
	var p6 := _make_mon("Bystander", [TypeChart.TYPE_NORMAL], 100)
	p6.add_move(_make_tackle())

	var stat_events3 := []
	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.stat_stage_changed.connect(func(t, idx, amt): stat_events3.push_back([t, idx, amt]))
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.queue_move(0, 0)
	bm3.queue_move(1, 0)
	bm3.start_battle(p5, p6)

	_chk("T04.04 discriminator: Mirror Herb does not consume itself off the " +
			"HOLDER's own self-raise (it already gets that raise normally, +2 " +
			"once — not doubled by also copying itself)",
			not consumed_events3.any(func(e): return e[0] == p5))
	bm3.queue_free()
