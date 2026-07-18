extends Node

# [M19-rampage] Thrash(37)/Petal Dance(80)/Outrage(200)/Raging Fury(761)
# (is_rampage) + Uproar(253) (is_uproar) — Bucket 4's core rampage-lock
# mechanism, with Uproar folded in per Rob's confirmation (shares the same
# underlying forced-move-repeat lock field, distinct counter/end behavior).
#
# Step 0 findings (see move_data.gd's is_rampage/is_uproar doc comments for
# full source citations):
#   - All 4 "true" rampage moves are structurally IDENTICAL in source (same
#     MOVE_EFFECT_THRASH additionalEffect, same 2-3 turn range) — no per-move
#     behavior difference, confirmed rather than assumed.
#   - The lock is a genuine FORCED REPEAT (selection is bypassed entirely),
#     not "user-selected-but-can't-switch" — reproduced by extending this
#     project's existing charging_move-style _phase_move_selection override
#     with a new, separate locked_move field (per Rob's confirmed design:
#     kept distinct from charging_move, matching this project's own
#     one-field-per-lock convention).
#   - Accuracy is rolled independently every turn; a MISS does NOT cancel a
#     continuing lock (still decrements, still confuses on schedule).
#   - A type-IMMUNE hit against a continuing lock cancels it WITHOUT
#     self-confuse — a real, distinct rule from a miss.
#   - Target-faints-mid-rampage and attacker-faints/switches-mid-lock both
#     need zero special-case code — confirmed free from this project's
#     existing _default_target (recomputed fresh every turn) and
#     _clear_volatiles (already called at every faint/switch site).
#   - Uproar shares the SAME lock field but its own counter (uproar_turns,
#     flat 3 at this project's Gen5+ config) and a genuinely different
#     end-of-lock behavior: NO self-confuse. Its sleep-block is FIELD-WIDE
#     (both sides, not just the user's own team) and only blocks NEW sleep at
#     this Gen5+ config — it does not wake already-sleeping mons (that half
#     is pre-Gen5-only, dead code here).
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c, battle_move_resolution.c, battle_util.c,
# battle_end_turn.c, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_forced_repeat()
	_test_lock_init_range()
	_test_confuse_on_lock_end()
	_test_miss_still_decrements_and_confuses()
	_test_immune_cancels_without_confuse()
	_test_first_use_immune_never_locks()
	_test_uproar_lock_no_confuse()
	_test_uproar_field_wide_sleep_block()
	_test_uproar_does_not_wake_sleepers()

	var total := _pass + _fail
	print("m19_rampage_test: %d/%d passed" % [_pass, total])
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
	# [Flaky-test rollover fix, Phase 4e] Pinned nature/IVs — this file
	# shares the identical latent unpinned-fixture vulnerability flagged
	# (but not fixed) while root-causing m18_5g_test.gd's own flake: without
	# forcing, every mon here got a genuinely random nature (±10% Attack)
	# and random IVs (0-31 per stat) on every run, exposing any exact-value
	# assertion to a threshold flake it just hadn't hit yet. Matches the
	# established convention (doubles_test.gd/d4_bundle6_test.gd/
	# m18_5g_test.gd).
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 5 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var thrash := _load_move(37)
	_chk("37 Thrash loads", thrash != null)
	_chk("37 name/type/category/power/accuracy/pp",
			thrash.move_name == "Thrash" and thrash.type == TypeChart.TYPE_NORMAL
					and thrash.category == 0 and thrash.power == 120
					and thrash.accuracy == 100 and thrash.pp == 10)
	_chk("37 makes_contact + is_rampage, no is_uproar",
			thrash.makes_contact and thrash.is_rampage and not thrash.is_uproar)

	var petal_dance := _load_move(80)
	_chk("80 Petal Dance loads", petal_dance != null)
	_chk("80 name/type/category/power/accuracy/pp",
			petal_dance.move_name == "Petal Dance" and petal_dance.type == TypeChart.TYPE_GRASS
					and petal_dance.category == 1 and petal_dance.power == 120
					and petal_dance.accuracy == 100 and petal_dance.pp == 10)
	_chk("80 makes_contact + is_rampage", petal_dance.makes_contact and petal_dance.is_rampage)

	var outrage := _load_move(200)
	_chk("200 Outrage loads", outrage != null)
	_chk("200 name/type/category/power/accuracy/pp",
			outrage.move_name == "Outrage" and outrage.type == TypeChart.TYPE_DRAGON
					and outrage.category == 0 and outrage.power == 120
					and outrage.accuracy == 100 and outrage.pp == 10)
	_chk("200 makes_contact + is_rampage", outrage.makes_contact and outrage.is_rampage)

	var raging_fury := _load_move(761)
	_chk("761 Raging Fury loads", raging_fury != null)
	_chk("761 name/type/category/power/accuracy/pp",
			raging_fury.move_name == "Raging Fury" and raging_fury.type == TypeChart.TYPE_FIRE
					and raging_fury.category == 0 and raging_fury.power == 120
					and raging_fury.accuracy == 100 and raging_fury.pp == 10)
	_chk("761 is_rampage, deliberately NO makes_contact (confirmed absent from source, " +
			"unlike the other 3 rampage moves)",
			raging_fury.is_rampage and not raging_fury.makes_contact)

	var uproar := _load_move(253)
	_chk("253 Uproar loads", uproar != null)
	_chk("253 name/type/category/power/accuracy/pp",
			uproar.move_name == "Uproar" and uproar.type == TypeChart.TYPE_NORMAL
					and uproar.category == 1 and uproar.power == 90
					and uproar.accuracy == 100 and uproar.pp == 10)
	_chk("253 sound_move + ignores_substitute + is_uproar, no is_rampage",
			uproar.sound_move and uproar.ignores_substitute and uproar.is_uproar
					and not uproar.is_rampage)


# ── Forced repeat: the lock overrides whatever is queued ────────────────────

func _test_forced_repeat() -> void:
	var thrash := _load_move(37)
	var tackle := _load_move(33)
	var atk := _make_mon("RampAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 200)
	atk.add_move(thrash)
	atk.add_move(tackle)
	# Huge HP so it survives being auto-attacked while locked; irrelevant type
	# (Normal) so Thrash is never accidentally immune here.
	var def := _make_mon("RampDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	bm.queue_move(0, 0)  # turn 1: Thrash
	bm.queue_move(0, 1)  # turn 2: Tackle QUEUED — should be overridden
	var moves_used := []
	bm.move_executed.connect(func(a, _d, m, _amt):
		if a == atk:
			moves_used.append(m))
	bm.start_battle(atk, def)

	_chk("Rampage: turn 1 uses the queued Thrash",
			moves_used.size() >= 1 and moves_used[0] == thrash)
	_chk("Rampage: turn 2 is FORCED to Thrash again despite Tackle being queued " +
			"(rampage_turns is guaranteed >= 2 on init, so turn 2 is always still locked)",
			moves_used.size() >= 2 and moves_used[1] == thrash)


# ── Lock init range: rampage_turns is randi_range(2,3) at initiation ────────

func _test_lock_init_range() -> void:
	var thrash := _load_move(37)
	var tackle := _load_move(33)
	var seen := {}
	for i in range(30):
		var atk := _make_mon("RangeAtk%d" % i, TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 200)
		atk.add_move(thrash)
		var def := _make_mon("RangeDef%d" % i, TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
		def.add_move(tackle)
		var bm := _make_bm()
		bm._force_hit = true
		bm._force_crit = false
		var raw := [-1]
		# Snapshot rampage_turns AT the rampage_lock_started signal — fires
		# right after the raw randi_range(2,3) assignment, BEFORE this
		# project's own immediate same-turn decrement runs.
		bm.rampage_lock_started.connect(func(a, _m):
			if a == atk and raw[0] == -1:
				raw[0] = atk.rampage_turns)
		bm.start_battle(atk, def)
		seen[raw[0]] = true
	_chk("Rampage lock init: only 2 or 3 ever observed across 30 trials (%s)" % [seen.keys()],
			seen.keys().all(func(v): return v == 2 or v == 3))
	_chk("Rampage lock init: both 2 and 3 occurred across 30 trials (non-degenerate range)",
			seen.has(2) and seen.has(3))


# ── Confuse on lock end (deterministic via direct field pre-set) ────────────

func _test_confuse_on_lock_end() -> void:
	var thrash := _load_move(37)
	var tackle := _load_move(33)
	var atk := _make_mon("ConfAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 200)
	atk.add_move(thrash)
	atk.locked_move = thrash
	atk.rampage_turns = 1  # this turn's hit is the LAST turn of the lock
	var def := _make_mon("ConfDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	# Snapshot via rampage_lock_ended, guarded to the FIRST occurrence — atk's
	# only move is Thrash, so a later turn could legitimately start and end a
	# SECOND rampage cycle before the whole battle finishes; reading state
	# after start_battle() returns would risk observing that later cycle
	# instead of the one under test (the documented whole-battle-aggregation
	# pitfall).
	var ended := [false]
	var snap_locked_null := [false]
	var snap_turns_zero := [false]
	var snap_confused := [false]
	bm.rampage_lock_ended.connect(func(a, _m, confused):
		if a == atk and not ended[0]:
			ended[0] = true
			snap_locked_null[0] = (atk.locked_move == null)
			snap_turns_zero[0] = (atk.rampage_turns == 0)
			snap_confused[0] = confused)
	bm.start_battle(atk, def)

	_chk("Rampage: lock clears when rampage_turns hits 0", snap_locked_null[0])
	_chk("Rampage: rampage_turns is 0 after the lock-ending hit", snap_turns_zero[0])
	_chk("Rampage: the attacker self-confuses the SAME turn the lock ends",
			snap_confused[0])


# ── A miss still decrements and still confuses on schedule ──────────────────

func _test_miss_still_decrements_and_confuses() -> void:
	var thrash := _load_move(37)
	var tackle := _load_move(33)
	var atk := _make_mon("MissAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 200)
	atk.add_move(thrash)
	atk.locked_move = thrash
	atk.rampage_turns = 1
	var def := _make_mon("MissDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = false  # guaranteed miss
	var missed := []
	var ended := [false]
	var snap_locked_null := [false]
	var snap_turns_zero := [false]
	var snap_confused := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk:
			missed.append(reason))
	bm.rampage_lock_ended.connect(func(a, _m, confused):
		if a == atk and not ended[0]:
			ended[0] = true
			snap_locked_null[0] = (atk.locked_move == null)
			snap_turns_zero[0] = (atk.rampage_turns == 0)
			snap_confused[0] = confused)
	bm.start_battle(atk, def)

	_chk("Rampage discriminator: the hit genuinely missed (accuracy)",
			"accuracy" in missed)
	_chk("Rampage: a MISS on the lock's final turn still clears the lock",
			snap_locked_null[0] and snap_turns_zero[0])
	_chk("Rampage: a MISS on the lock's final turn still self-confuses " +
			"(source: MoveEndRampage's decrement runs independent of accuracy outcome)",
			snap_confused[0])


# ── Type-immune hit cancels a CONTINUING lock WITHOUT confuse ────────────────

func _test_immune_cancels_without_confuse() -> void:
	var thrash := _load_move(37)  # Normal-type
	var tackle := _load_move(33)
	var atk := _make_mon("ImmAtk", TypeChart.TYPE_NORMAL, 30, 60, 60, 60, 60, 200)
	atk.add_move(thrash)
	atk.locked_move = thrash
	atk.rampage_turns = 1  # would confuse this turn if the hit landed normally
	# Ghost-type: flatly immune to Normal-type moves.
	var def := _make_mon("ImmDef", TypeChart.TYPE_GHOST, 100, 60, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var ended := [false]
	var snap_locked_null := [false]
	var snap_turns_zero := [false]
	var snap_confused := [false]
	bm.rampage_lock_ended.connect(func(a, _m, confused):
		if a == atk and not ended[0]:
			ended[0] = true
			snap_locked_null[0] = (atk.locked_move == null)
			snap_turns_zero[0] = (atk.rampage_turns == 0)
			snap_confused[0] = confused)
	bm.start_battle(atk, def)

	_chk("Rampage: a type-immune hit against a CONTINUING lock cancels it",
			snap_locked_null[0] and snap_turns_zero[0])
	_chk("Rampage: the type-immune cancel does NOT self-confuse " +
			"(distinct from the normal end-of-lock case)",
			not snap_confused[0])


# ── A first-use immune hit never sets the lock at all ────────────────────────

func _test_first_use_immune_never_locks() -> void:
	var thrash := _load_move(37)
	var tackle := _load_move(33)
	var atk := _make_mon("FirstImmAtk", TypeChart.TYPE_NORMAL, 30, 60, 60, 60, 60, 200)
	atk.add_move(thrash)
	# Fresh attacker, no pre-existing lock.
	var def := _make_mon("FirstImmDef", TypeChart.TYPE_GHOST, 100, 60, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	var started := []
	bm.rampage_lock_started.connect(func(a, _m): started.append(a))
	bm.start_battle(atk, def)

	_chk("Rampage: a first-use immune hit never initiates the lock at all " +
			"(additionalEffects never runs for a 0x hit in source)",
			atk.locked_move == null and atk.rampage_turns == 0 and not (atk in started))


# ── Uproar: lock forces repeat, but NO self-confuse at lock end ─────────────

func _test_uproar_lock_no_confuse() -> void:
	var uproar := _load_move(253)
	var tackle := _load_move(33)
	var atk := _make_mon("UproarAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 200)
	atk.add_move(uproar)
	atk.locked_move = uproar
	atk.uproar_turns = 1  # this turn's use is the LAST turn of the lock
	var def := _make_mon("UproarDef", TypeChart.TYPE_NORMAL, 400, 10, 200, 10, 200, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var ended := [false]
	var snap_locked_null := [false]
	var snap_turns_zero := [false]
	var snap_confused := [false]
	bm.rampage_lock_ended.connect(func(a, _m, confused):
		if a == atk and not ended[0]:
			ended[0] = true
			snap_locked_null[0] = (atk.locked_move == null)
			snap_turns_zero[0] = (atk.uproar_turns == 0)
			snap_confused[0] = confused)
	bm.start_battle(atk, def)

	_chk("Uproar: lock clears when uproar_turns hits 0",
			snap_locked_null[0] and snap_turns_zero[0])
	_chk("Uproar discriminator: unlike rampage, NO self-confuse ever fires at lock end",
			not snap_confused[0])


# ── Uproar: field-wide new-sleep block (both sides) ──────────────────────────
# Snapshotted via move_executed on P2's FIRST action only, guarded to the
# first occurrence — this project's Uproar lock cycles (3 turns active, then
# one turn where the counter has just hit 0 before the NEXT auto-reselected
# Uproar re-initiates it), so reading state after the whole battle runs to
# completion would risk sampling a later, transiently-unlocked turn instead
# of the one under test (the documented whole-battle-aggregation pitfall).

func _test_uproar_field_wide_sleep_block() -> void:
	var sleep_powder := _load_move(79)  # guaranteed (secondary_chance=0) sleep
	var uproar := _load_move(253)
	var tackle := _load_move(33)
	# P1 has the active Uproar lock; P2 attempts to inflict sleep on P1 with
	# Sleep Powder — field-wide scope means P1's OWN uproar_turns blocks
	# sleep being inflicted on IT, not just on P2's side. P1 faster than P2 so
	# P1's own Uproar use resolves before P2's Sleep Powder each turn.
	var p1 := _make_mon("UproarHolder", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 200)
	p1.uproar_turns = 3
	p1.add_move(uproar)
	var p2 := _make_mon("SleepAtkr", TypeChart.TYPE_GRASS, 200, 60, 60, 60, 60, 10)
	p2.add_move(sleep_powder)

	var bm := _make_bm()
	bm._force_hit = true
	var snapped := [false]
	var snap_status := [-1]
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == p2 and not snapped[0]:
			snapped[0] = true
			snap_status[0] = p1.status)
	bm.start_battle(p1, p2)

	_chk("Uproar: field-wide block prevents Sleep Powder from putting the " +
			"Uproar-locked mon to sleep, sampled at P2's first Sleep Powder attempt",
			snap_status[0] != BattlePokemon.STATUS_SLEEP)

	# Discriminator: without any Uproar active anywhere (P1b uses Tackle, not
	# Uproar at all — deliberately keeping Uproar completely out of the
	# picture, not just un-triggered), the SAME Sleep Powder succeeds.
	var p1b := _make_mon("NoUproarHolder", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 10)
	p1b.add_move(tackle)
	var p2b := _make_mon("SleepAtkr2", TypeChart.TYPE_GRASS, 200, 60, 60, 60, 60, 10)
	p2b.add_move(sleep_powder)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var snapped2 := [false]
	var snap_status2 := [-1]
	bm2.move_executed.connect(func(a, _d, _m, _amt):
		if a == p2b and not snapped2[0]:
			snapped2[0] = true
			snap_status2[0] = p1b.status)
	bm2.start_battle(p1b, p2b)
	_chk("Uproar discriminator: the SAME Sleep Powder succeeds with no Uproar " +
			"active anywhere on the field", snap_status2[0] == BattlePokemon.STATUS_SLEEP)


# ── Uproar: does NOT wake an already-sleeping mon (Gen5+ config) ────────────

func _test_uproar_does_not_wake_sleepers() -> void:
	var uproar := _load_move(253)
	var tackle := _load_move(33)
	var p1 := _make_mon("AlreadyAsleep", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 10)
	p1.status = BattlePokemon.STATUS_SLEEP
	p1.sleep_turns = 3
	p1.add_move(tackle)
	var p2 := _make_mon("Uproarer", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 200)
	p2.add_move(uproar)
	p2.uproar_turns = 3

	var bm := _make_bm()
	bm._force_hit = true
	var snapped := [false]
	var snap_status := [-1]
	bm.move_executed.connect(func(a, _d, _m, _amt):
		if a == p2 and not snapped[0]:
			snapped[0] = true
			snap_status[0] = p1.status)
	bm.start_battle(p1, p2)

	_chk("Uproar: an already-sleeping mon is NOT woken by an active Uproar " +
			"lock at this project's Gen5+ config (that half of source is dead " +
			"code here), sampled at P2's first Uproar use",
			snap_status[0] == BattlePokemon.STATUS_SLEEP)
