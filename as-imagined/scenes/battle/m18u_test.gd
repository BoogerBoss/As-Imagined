extends Node

# M18u test suite — Berserk Gene + Metronome item
#
# Two genuinely unrelated mechanic families sharing this tier only for
# scheduling efficiency.
#
# Berserk Gene fires ONLY on switch-in (hold_effects.h: .onSwitchIn=TRUE, no
# .onEffect) — single-use, so a full `start_battle` checking for the trigger's
# presence at battle start is safe (no re-trigger risk to conflate with a later
# event, unlike the probabilistic/rate-measurement pitfalls CLAUDE.md documents).
#
# Metronome item's ramp VALUE is tested via direct ItemManager.
# post_roll_modifier_uq412 calls with metronome_item_counter preset (a pure,
# stateless function — no battle needed). The COUNTER-UPDATE mechanism itself
# (increment on same move, reset on different move) genuinely requires the
# move-execution phase machinery, so that half uses a deterministically-queued
# short battle (multiple queue_move calls, one per turn, so every turn's move
# choice is explicit) with per-turn signal snapshots — explicitly scoped to each
# exact use-count being tested, per this tier's own extra-suspicion instruction
# given [M18r]'s two recent whole-battle-aggregation violations.
#
# Sections:
#   U01 Berserk Gene — +2 Atk + infinite self-confusion, +6-cap and Own-Tempo discriminators
#   U02 Metronome item — ramp value at counter 0/1/4/5/10 (direct calls)
#   U03 Metronome item — counter increments on same move, resets on a different move

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_u01_berserk_gene()
	_test_u02_metronome_ramp_value()
	_test_u03_metronome_counter_update()

	var total := _pass + _fail
	print("m18u_test: %d/%d passed" % [_pass, total])
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

func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon(mon_name: String, type1: int, hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _make_tackle(mon_name: String = "Tackle", power: int = 40) -> MoveData:
	var m := MoveData.new()
	m.move_name = mon_name
	m.type      = TypeChart.TYPE_NORMAL
	m.category  = 0
	m.power     = power
	m.accuracy  = 100
	m.pp        = 40
	return m


# ── U01: Berserk Gene — +2 Atk + infinite self-confusion, switch-in only ───────

func _test_u01_berserk_gene() -> void:
	var gene := _load_item(798)
	_chk("U01.00 fixture loads", gene != null)

	# Positive: switch-in with Berserk Gene -> +2 Atk, confusion applied,
	# item consumed. All captured at the very start of the battle (switch-in),
	# so this is a single, well-defined event, not an aggregate.
	var p1 := _make_mon("Berserked", TypeChart.TYPE_NORMAL, 100)
	p1.held_item = gene
	p1.add_move(_make_tackle())
	var p2 := _make_mon("Foe", TypeChart.TYPE_NORMAL, 300)
	p2.add_move(_make_tackle())

	# Snapshotted live, inside the signal handlers themselves — `start_battle`
	# runs the WHOLE multi-turn battle to completion (p1 is fragile and
	# permanently confused, so it very likely faints partway through), so
	# reading p1's fields AFTER `start_battle` returns would read whatever
	# state a much later, unrelated turn left behind, not the switch-in moment
	# itself (the exact whole-battle-aggregation pitfall CLAUDE.md documents).
	var stat_events := []
	var secondary_events := []
	var consumed_events := []
	var infinite_snapshot := [false]
	var confusion_turns_snapshot := [0]
	var bm := BattleManager.new()
	add_child(bm)
	bm.stat_stage_changed.connect(func(t, idx, amt): stat_events.push_back([t, idx, amt]))
	bm.secondary_applied.connect(func(t, eff):
		secondary_events.push_back([t, eff])
		if t == p1:
			infinite_snapshot[0] = t.infinite_confusion
			confusion_turns_snapshot[0] = t.confusion_turns)
	bm.item_consumed.connect(func(m, item): consumed_events.push_back([m, item]))
	bm.start_battle(p1, p2)

	_chk("U01.01 +2 Attack fires on switch-in",
			stat_events.any(func(e): return e[0] == p1 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("U01.02 confusion (SE_CONFUSION) is applied on switch-in",
			secondary_events.any(func(e): return e[0] == p1 and e[1] == MoveData.SE_CONFUSION))
	_chk("U01.03 infinite_confusion is set true (Berserk Gene's confusion never " +
			"wears off naturally), snapshotted at the moment of application",
			infinite_snapshot[0] == true and confusion_turns_snapshot[0] > 0)
	_chk("U01.04 Berserk Gene is consumed",
			consumed_events.any(func(e): return e[0] == p1 and e[1].item_name == "Berserk Gene"))
	bm.queue_free()

	# Discriminator: infinite confusion genuinely never decrements, unlike
	# ordinary confusion — a FRESH, isolated BattlePokemon (not one that just
	# went through a whole battle and may already be in an unrelated state),
	# with confusion set directly, then StatusManager.pre_move_check (a pure
	# function) called several times in a row to confirm confusion_turns is
	# unchanged.
	var isolated := _make_mon("Isolated", TypeChart.TYPE_NORMAL, 100)
	isolated.confusion_turns = 3
	isolated.infinite_confusion = true
	var turns_before: int = isolated.confusion_turns
	for _i in range(5):
		StatusManager.pre_move_check(isolated, null, null, false, null, null, false)
	_chk("U01.05 CORRECTION-confirming: infinite confusion does NOT decrement " +
			"across repeated pre-move checks (confusion_turns unchanged: %d -> %d)" %
					[turns_before, isolated.confusion_turns],
			isolated.confusion_turns == turns_before)

	# Discriminator: holder already at +6 Attack -> Berserk Gene does NOTHING at
	# all (no stat change, no confusion, no consumption) — source's CompareStat
	# guard wraps the whole function.
	var p3 := _make_mon("BerserkedCapped", TypeChart.TYPE_NORMAL, 100)
	p3.held_item = _load_item(798)
	p3.stat_stages[BattlePokemon.STAGE_ATK] = 6
	p3.add_move(_make_tackle())
	var p4 := _make_mon("Foe2", TypeChart.TYPE_NORMAL, 300)
	p4.add_move(_make_tackle())

	var stat_events2 := []
	var consumed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.stat_stage_changed.connect(func(t, idx, amt): stat_events2.push_back([t, idx, amt]))
	bm2.item_consumed.connect(func(m, item): consumed_events2.push_back([m, item]))
	bm2.start_battle(p3, p4)

	_chk("U01.06 discriminator: holder already at +6 Attack -> no stat change",
			not stat_events2.any(func(e): return e[0] == p3 and e[1] == BattlePokemon.STAGE_ATK))
	_chk("U01.07 discriminator: holder already at +6 Attack -> NOT consumed at all",
			not consumed_events2.any(func(e): return e[0] == p3))
	_chk("U01.08 discriminator: holder already at +6 Attack -> no confusion either",
			p3.confusion_turns == 0)
	bm2.queue_free()

	# Discriminator: Own Tempo blocks the confusion half, but the stat raise AND
	# consumption still happen (source: jumpifability check is INSIDE the shared
	# BattleScript_BerserkGeneRet, after trybattlerstatchange, before
	# removeitem — confirmed via direct script read, not assumed).
	var own_tempo := _load_ability(20)
	var p5 := _make_mon("BerserkedOwnTempo", TypeChart.TYPE_NORMAL, 100)
	p5.ability = own_tempo
	p5.held_item = _load_item(798)
	p5.add_move(_make_tackle())
	var p6 := _make_mon("Foe3", TypeChart.TYPE_NORMAL, 300)
	p6.add_move(_make_tackle())

	var stat_events3 := []
	var consumed_events3 := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.stat_stage_changed.connect(func(t, idx, amt): stat_events3.push_back([t, idx, amt]))
	bm3.item_consumed.connect(func(m, item): consumed_events3.push_back([m, item]))
	bm3.start_battle(p5, p6)

	_chk("U01.09 discriminator: Own Tempo holder STILL gets +2 Attack",
			stat_events3.any(func(e): return e[0] == p5 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("U01.10 discriminator: Own Tempo holder's confusion is BLOCKED",
			p5.confusion_turns == 0)
	_chk("U01.11 discriminator: Own Tempo holder's item is STILL consumed " +
			"(consumption doesn't depend on confusion actually landing)",
			consumed_events3.any(func(e): return e[0] == p5))
	bm3.queue_free()


# ── U02: Metronome item — ramp value (direct calls, no battle) ─────────────────
#
# Source: GetAttackerItemsModifier's HOLD_EFFECT_METRONOME case (battle_util.c
# L7486-7491): modifier = 1.0 + PercentToUQ4_12(param) * min(counter, 5).
# param=20 confirmed via src/data/items.h (not assumed). At the 1st consecutive
# use the counter is 0 (no boost yet); the ramp reaches its max +100% only at
# the 6th consecutive use (counter=5, capped) — a precise clarification of the
# plan's "+20%/use, up to +100% at 5 uses" shorthand, confirmed by reading
# GetAttackerItemsModifier directly.

func _test_u02_metronome_ramp_value() -> void:
	var metronome := _load_item(483)
	_chk("U02.00 fixture check: Metronome hold_effect_param == 20",
			metronome.hold_effect_param == 20)

	var holder := _make_mon("Metronomed", TypeChart.TYPE_NORMAL)
	holder.held_item = metronome

	holder.metronome_item_counter = 0
	_chk("U02.01 counter=0 (1st consecutive use): modifier == 4096 (no boost yet)",
			ItemManager.post_roll_modifier_uq412(holder, false, 1.0) == 4096)

	holder.metronome_item_counter = 1
	_chk("U02.02 counter=1 (2nd consecutive use): modifier == 4915 (+20%)",
			ItemManager.post_roll_modifier_uq412(holder, false, 1.0) == 4096 + 819)

	holder.metronome_item_counter = 4
	_chk("U02.03 counter=4 (5th consecutive use): modifier == 7372 (+80%, NOT " +
			"yet the max)",
			ItemManager.post_roll_modifier_uq412(holder, false, 1.0) == 4096 + 819 * 4)

	holder.metronome_item_counter = 5
	_chk("U02.04 counter=5 (6th consecutive use): modifier == 8191 (the max, " +
			"+100% minus source's own off-by-one rounding)",
			ItemManager.post_roll_modifier_uq412(holder, false, 1.0) == 4096 + 819 * 5)

	holder.metronome_item_counter = 10
	_chk("U02.05 counter=10 (well past 5): modifier STILL 8191 (capped, matching " +
			"counter=5 exactly — the counter itself isn't capped, only its READ is)",
			ItemManager.post_roll_modifier_uq412(holder, false, 1.0) == 4096 + 819 * 5)

	# Discriminator: no item -> always 4096 regardless of counter.
	var bare := _make_mon("Bare", TypeChart.TYPE_NORMAL)
	bare.metronome_item_counter = 5
	_chk("U02.06 discriminator: no Metronome item -> no boost regardless of counter",
			ItemManager.post_roll_modifier_uq412(bare, false, 1.0) == 4096)


# ── U03: Metronome item — counter increments on same move, resets on a ─────────
# different move (deterministically-queued battle, per-turn signal snapshots)

func _test_u03_metronome_counter_update() -> void:
	var metronome := _load_item(483)
	var tackle := _make_tackle("Tackle")
	var scratch := _make_tackle("Scratch")  # a genuinely different move object

	# Positive: the SAME move used 3 times in a row -> counter reads 0, 1, 2 at
	# each successive use (explicitly scoped to each exact use, not an aggregate).
	var p1 := _make_mon("Ramping", TypeChart.TYPE_NORMAL, 300, 60, 40)
	p1.held_item = metronome
	p1.add_move(tackle)
	var p2 := _make_mon("Punchbag", TypeChart.TYPE_NORMAL, 300, 1, 200)
	p2.add_move(tackle)

	var counter_snapshots := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(a, _d, _m, _dmg):
		if a == p1:
			counter_snapshots.push_back(a.metronome_item_counter))
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.queue_move(1, 0)
	bm.queue_move(1, 0)
	bm.start_battle(p1, p2)

	_chk("U03.01 counter reads [0, 1, 2] across 3 consecutive uses of the same " +
			"move (got %s)" % [str(counter_snapshots.slice(0, 3))],
			counter_snapshots.size() >= 3 and counter_snapshots[0] == 0 \
					and counter_snapshots[1] == 1 and counter_snapshots[2] == 2)
	bm.queue_free()

	# Discriminator: switching to a DIFFERENT move resets the counter to 0.
	var p3 := _make_mon("NotRamping", TypeChart.TYPE_NORMAL, 300, 60, 40)
	p3.held_item = _load_item(483)
	p3.add_move(tackle)
	p3.add_move(scratch)
	var p4 := _make_mon("Punchbag2", TypeChart.TYPE_NORMAL, 300, 1, 200)
	p4.add_move(tackle)

	var counter_snapshots2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_executed.connect(func(a, _d, _m, _dmg):
		if a == p3:
			counter_snapshots2.push_back(a.metronome_item_counter))
	bm2.queue_move(0, 0)  # Tackle: counter -> 0
	bm2.queue_move(0, 0)  # Tackle again: counter -> 1
	bm2.queue_move(0, 1)  # Scratch (DIFFERENT move): counter -> 0
	bm2.queue_move(1, 0)
	bm2.queue_move(1, 0)
	bm2.queue_move(1, 0)
	bm2.start_battle(p3, p4)

	_chk("U03.02 discriminator: counter reads [0, 1, 0] when the 3rd use switches " +
			"to a different move (got %s)" % [str(counter_snapshots2.slice(0, 3))],
			counter_snapshots2.size() >= 3 and counter_snapshots2[0] == 0 \
					and counter_snapshots2[1] == 1 and counter_snapshots2[2] == 0)
	bm2.queue_free()
