extends Node

# [M19.5 Task 1] Ban-flag audit fixes — cross-referenced moves_info.h's 14
# ban-flag struct fields against gen_moves.py's ban_flags bitmask for every
# implemented move. Only 8 of the 14 flags are actually CONSULTED anywhere in
# battle_manager.gd (BAN_MIRROR_MOVE/BAN_INSTRUCT/BAN_GRAVITY have ZERO read
# sites — confirmed by grep, deliberately NOT populated as part of this fix,
# since doing so would be pure documentation with no behavioral effect).
#
# Of those 8 LIVE flags, this session's audit found REAL gaps in 5:
#   - BAN_METRONOME: ~70 moves missing (mostly LGPE/signature/legendary
#     moves shipped across many D4 bundles) — confirmed live impact, since
#     _pick_metronome_move() scans every .tres on disk.
#   - BAN_SLEEP_TALK: ~15 moves missing (mostly two-turn/charge moves).
#   - BAN_ENCORE: missing on Metronome/Mirror Move/Struggle/Copycat.
#   - BAN_ASSIST: missing on Snatch.
#   - BAN_SKETCH: missing on Hyperspace Fury.
# PLUS the reverse direction: 4 moves (Bide/Substitute/Encore/Burning
# Bulwark) incorrectly carried BAN_METRONOME with no source basis at all —
# removed in the same pass.
#
# The remaining 3 live flags (BAN_MIMIC, BAN_COPYCAT, BAN_ME_FIRST) had ZERO
# gaps — already fully correct before this session (BAN_MIMIC was fixed
# retroactively during the earlier [Mimic/Sketch] session). Sections G/H/I
# below are REGRESSION GUARDS confirming continued correctness, not fixes.
#
# Ground truth: pokeemerald_expansion include/move.h (the 14-field ban-flag
# struct layout) and src/data/moves_info.h (per-move values).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_ban_metronome_dispatch()
	_test_ban_sleep_talk_dispatch()
	_test_ban_encore_dispatch()
	_test_ban_assist_dispatch()
	_test_ban_sketch_dispatch()
	_test_ban_mimic_regression()
	_test_ban_copycat_regression()
	_test_ban_me_first_regression()

	var total := _pass + _fail
	print("ban_flag_audit_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Direct single-dispatch helper — resolves exactly ONE _phase_move_execution()
# call, matching the convention established across the M19 test suites.
func _dispatch_move(combatants: Array[BattlePokemon], attacker_idx: int, move: MoveData) -> BattleManager:
	var bm := _make_bm()
	bm._combatants = combatants
	bm._active_per_side = combatants.size() / 2
	var actor_indices := {}
	for i in range(combatants.size()):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	var chosen_moves: Array = []
	for i in range(combatants.size()):
		chosen_moves.append(move if i == attacker_idx else null)
	bm._chosen_moves = chosen_moves
	var chosen_switch_slots: Array[int] = []
	for i in range(combatants.size()):
		chosen_switch_slots.append(-1)
	bm._chosen_switch_slots = chosen_switch_slots
	var other_idx: int = 1 if attacker_idx == 0 else 0
	var chosen_targets: Array[int] = []
	for i in range(combatants.size()):
		chosen_targets.append(other_idx if i == attacker_idx else attacker_idx)
	bm._chosen_targets = chosen_targets
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = attacker_idx
	bm._phase_move_execution()
	return bm


# ── Section A: data integrity — spot-check the fix directly against .tres ──

func _test_data_integrity() -> void:
	# Representative newly-added BAN_METRONOME entries (across the whole
	# family this gap spanned: legendary signatures, LGPE partner moves,
	# ordinary multi-hit/utility moves added across many D4 bundles).
	var rage_fist := _load_move(815)
	_chk("A.01 Rage Fist now carries BAN_METRONOME",
			(rage_fist.ban_flags & MoveData.BAN_METRONOME) != 0)
	var zippy_zap := _load_move(676)
	_chk("A.02 Zippy Zap now carries BAN_METRONOME",
			(zippy_zap.ban_flags & MoveData.BAN_METRONOME) != 0)
	var dragon_ascent := _load_move(620)
	_chk("A.03 Dragon Ascent now carries BAN_METRONOME",
			(dragon_ascent.ban_flags & MoveData.BAN_METRONOME) != 0)
	var body_press := _load_move(704)
	_chk("A.04 Body Press now carries BAN_METRONOME",
			(body_press.ban_flags & MoveData.BAN_METRONOME) != 0)

	# Representative newly-added BAN_SLEEP_TALK entries (two-turn/charge family).
	var fly := _load_move(19)
	_chk("A.05 Fly now carries BAN_SLEEP_TALK",
			(fly.ban_flags & MoveData.BAN_SLEEP_TALK) != 0)
	var solar_beam := _load_move(76)
	_chk("A.06 Solar Beam now carries BAN_SLEEP_TALK",
			(solar_beam.ban_flags & MoveData.BAN_SLEEP_TALK) != 0)

	# BAN_ENCORE additions.
	var metronome_data := _load_move(118)
	_chk("A.07 Metronome now carries BAN_ENCORE",
			(metronome_data.ban_flags & MoveData.BAN_ENCORE) != 0)
	var mirror_move := _load_move(119)
	_chk("A.08 Mirror Move now carries BAN_ENCORE",
			(mirror_move.ban_flags & MoveData.BAN_ENCORE) != 0)
	var struggle := _load_move(165)
	_chk("A.09 Struggle now carries BAN_ENCORE",
			(struggle.ban_flags & MoveData.BAN_ENCORE) != 0)
	var copycat_data := _load_move(383)
	_chk("A.10 Copycat now carries BAN_ENCORE",
			(copycat_data.ban_flags & MoveData.BAN_ENCORE) != 0)

	# BAN_ASSIST addition.
	var snatch := _load_move(289)
	_chk("A.11 Snatch now carries BAN_ASSIST",
			(snatch.ban_flags & MoveData.BAN_ASSIST) != 0)

	# BAN_SKETCH addition.
	var hyperspace_fury := _load_move(621)
	_chk("A.12 Hyperspace Fury now carries BAN_SKETCH",
			(hyperspace_fury.ban_flags & MoveData.BAN_SKETCH) != 0)

	# The 4 confirmed extras — removed, since source doesn't set
	# metronomeBanned for any of these at all.
	var bide := _load_move(117)
	_chk("A.13 Bide no longer carries BAN_METRONOME (confirmed extra, removed)",
			(bide.ban_flags & MoveData.BAN_METRONOME) == 0)
	var substitute := _load_move(164)
	_chk("A.14 Substitute no longer carries BAN_METRONOME (confirmed extra, removed)",
			(substitute.ban_flags & MoveData.BAN_METRONOME) == 0)
	var encore := _load_move(227)
	_chk("A.15 Encore no longer carries BAN_METRONOME (confirmed extra, removed)",
			(encore.ban_flags & MoveData.BAN_METRONOME) == 0)
	var burning_bulwark := _load_move(836)
	_chk("A.16 Burning Bulwark no longer carries BAN_METRONOME (confirmed extra, removed)",
			(burning_bulwark.ban_flags & MoveData.BAN_METRONOME) == 0)
	# Encore's own genuine ban (BAN_ENCORE) must survive the BAN_METRONOME removal.
	_chk("A.17 Encore still carries its own genuine BAN_ENCORE",
			(encore.ban_flags & MoveData.BAN_ENCORE) != 0)


# ── Section B: BAN_METRONOME dispatch ──────────────────────────────────────
# _pick_metronome_move() re-scans and RE-LOADS every .tres on disk on every
# single call — calling it hundreds of times for a statistical pool-exclusion
# proof would be prohibitively slow (700+ resource loads per call). The real
# discriminator is Section A's direct data check (the dispatch's own filter
# is a one-line `(m.ban_flags & MoveData.BAN_METRONOME) == 0`, already read
# directly from source during this audit); here we only confirm the function
# itself still executes correctly post-fix (non-null, doesn't crash).

func _test_ban_metronome_dispatch() -> void:
	var bm := _make_bm()
	var picked: MoveData = bm._pick_metronome_move()
	_chk("B.01 _pick_metronome_move still returns a valid move post-fix",
			picked != null and picked is MoveData)
	bm.queue_free()


# ── Section C: BAN_SLEEP_TALK dispatch ─────────────────────────────────────
# _pick_sleep_talk_move only scans the ATTACKER's OWN (small) moveset, no
# disk I/O — cheap enough for a real statistical exclusion proof.

func _test_ban_sleep_talk_dispatch() -> void:
	var fly := _load_move(19)
	var tackle := _load_move(33)
	var attacker := _make_mon("SleepTalkAtk")
	attacker.add_move(fly)
	attacker.add_move(tackle)
	attacker.status = BattlePokemon.STATUS_SLEEP

	var bm := _make_bm()
	var saw_fly := false
	var saw_tackle := false
	for _i in range(100):
		var picked: MoveData = bm._pick_sleep_talk_move(attacker, false)
		if picked == fly:
			saw_fly = true
		elif picked == tackle:
			saw_tackle = true
	_chk("C.01 Sleep Talk NEVER picks Fly across 100 trials (now BAN_SLEEP_TALK)",
			not saw_fly)
	_chk("C.02 Sleep Talk DOES pick Tackle (sanity — the pool isn't vacuously empty)",
			saw_tackle)
	bm.queue_free()


# ── Section D: BAN_ENCORE dispatch ─────────────────────────────────────────

func _test_ban_encore_dispatch() -> void:
	var encore := _load_move(227)
	var metronome_move := _load_move(118)
	var tackle := _load_move(33)

	# D.01: target's last move was Metronome (now BAN_ENCORE) — Encore fails.
	var atk1 := _make_mon("EncoreAtk1")
	atk1.add_move(encore)
	var tgt1 := _make_mon("EncoreTgt1")
	tgt1.add_move(metronome_move)
	tgt1.last_move_used = metronome_move
	var bm1 := _dispatch_move([atk1, tgt1], 0, encore)
	_chk("D.01 Encore fails against a target whose last move was Metronome (now BAN_ENCORE)",
			tgt1.encored_move == null)
	bm1.queue_free()

	# D.02: positive control — target's last move was Tackle (not BAN_ENCORE) — succeeds.
	var atk2 := _make_mon("EncoreAtk2")
	atk2.add_move(encore)
	var tgt2 := _make_mon("EncoreTgt2")
	tgt2.add_move(tackle)
	tgt2.last_move_used = tackle
	var bm2 := _dispatch_move([atk2, tgt2], 0, encore)
	_chk("D.02 Encore succeeds against a target whose last move was Tackle (not BAN_ENCORE)",
			tgt2.encored_move == tackle)
	bm2.queue_free()


# ── Section E: BAN_ASSIST dispatch ─────────────────────────────────────────
# _pick_assist_move scans the ATTACKER's OWN BENCH (non-active party members).

func _test_ban_assist_dispatch() -> void:
	var assist_move := _load_move(274)  # Assist
	var snatch := _load_move(289)
	var tackle := _load_move(33)

	# E.01: bench mon's ONLY move is Snatch (now BAN_ASSIST) — pool is empty, Assist fails.
	var active1 := _make_mon("AssistActive1")
	active1.add_move(assist_move)
	var bench1 := _make_mon("AssistBench1")
	bench1.add_move(snatch)
	var player_party1 := BattleParty.new()
	player_party1.members = [active1, bench1]
	player_party1.active_indices = [0]
	var opp1 := _make_mon("AssistOpp1")

	var bm1 := _make_bm()
	bm1._active_per_side = 1
	bm1._parties = [player_party1]
	bm1._combatants = [active1]
	var picked1: MoveData = bm1._pick_assist_move(active1)
	_chk("E.01 Assist's pool is empty when the only bench move is Snatch (now BAN_ASSIST)",
			picked1 == null)
	bm1.queue_free()

	# E.02: positive control — bench mon knows Tackle instead — pool succeeds.
	var active2 := _make_mon("AssistActive2")
	active2.add_move(assist_move)
	var bench2 := _make_mon("AssistBench2")
	bench2.add_move(tackle)
	var player_party2 := BattleParty.new()
	player_party2.members = [active2, bench2]
	player_party2.active_indices = [0]

	var bm2 := _make_bm()
	bm2._active_per_side = 1
	bm2._parties = [player_party2]
	bm2._combatants = [active2]
	var picked2: MoveData = bm2._pick_assist_move(active2)
	_chk("E.02 Assist's pool includes Tackle when it's the bench mon's only move",
			picked2 == tackle)
	bm2.queue_free()


# ── Section F: BAN_SKETCH dispatch ─────────────────────────────────────────

func _test_ban_sketch_dispatch() -> void:
	var sketch := _load_move(166)
	var hyperspace_fury := _load_move(621)
	var tackle := _load_move(33)

	# F.01: target's last move was Hyperspace Fury (now BAN_SKETCH) — Sketch fails.
	var atk1 := _make_mon("SketchAtk1")
	atk1.add_move(sketch)
	var tgt1 := _make_mon("SketchTgt1")
	tgt1.last_move_used = hyperspace_fury
	var bm1 := _dispatch_move([atk1, tgt1], 0, sketch)
	_chk("F.01 Sketch fails against a target whose last move was Hyperspace Fury (now BAN_SKETCH)",
			atk1.moves[0] == sketch)
	bm1.queue_free()

	# F.02: positive control — target's last move was Tackle — Sketch succeeds.
	var atk2 := _make_mon("SketchAtk2")
	atk2.add_move(sketch)
	var tgt2 := _make_mon("SketchTgt2")
	tgt2.last_move_used = tackle
	var bm2 := _dispatch_move([atk2, tgt2], 0, sketch)
	_chk("F.02 Sketch succeeds against a target whose last move was Tackle",
			atk2.moves[0] == tackle)
	bm2.queue_free()


# ── Section G: BAN_MIMIC regression guard (already correct — NOT a fix from
# this session, confirmed retroactively during the earlier [Mimic/Sketch]
# session) ──────────────────────────────────────────────────────────────────

func _test_ban_mimic_regression() -> void:
	var mimic := _load_move(102)
	var metronome_move := _load_move(118)

	var atk := _make_mon("MimicAtk")
	atk.add_move(mimic)
	var tgt := _make_mon("MimicTgt")
	tgt.last_move_used = metronome_move
	var bm := _dispatch_move([atk, tgt], 0, mimic)
	_chk("G.01 Mimic fails against a target whose last move was Metronome " +
			"(already-correct BAN_MIMIC, regression guard only)",
			atk.moves[0] == mimic)
	bm.queue_free()


# ── Section H: BAN_COPYCAT regression guard (already correct) ─────────────

func _test_ban_copycat_regression() -> void:
	var copycat := _load_move(383)
	var metronome_move := _load_move(118)

	var atk := _make_mon("CopycatAtk")
	atk.add_move(copycat)
	var bm := _make_bm()
	bm._last_landed_move_anyone = metronome_move
	var picked: MoveData = bm._pick_copycat_move()
	_chk("H.01 Copycat refuses to copy Metronome (already-correct BAN_COPYCAT, " +
			"regression guard only)", picked == null)
	bm.queue_free()


# ── Section I: BAN_ME_FIRST regression guard (already correct) ────────────

func _test_ban_me_first_regression() -> void:
	var me_first := _load_move(382)
	var counter := _load_move(68)  # non-status, already BAN_ME_FIRST-flagged

	var atk := _make_mon("MeFirstAtk")
	atk.add_move(me_first)
	var tgt := _make_mon("MeFirstTgt")
	tgt.add_move(counter)

	var bm := _make_bm()
	bm._combatants = [atk, tgt]
	bm._active_per_side = 1
	bm._actor_indices = {atk: 0, tgt: 1}
	bm._chosen_moves = [me_first, counter]
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_targets = [1, 0]
	bm._turn_order = [atk, tgt]
	bm._current_actor_index = 0
	bm._phase_move_execution()
	_chk("I.01 Me First refuses to steal Counter (already-correct BAN_ME_FIRST, " +
			"regression guard only — Counter is non-status, so this isn't just " +
			"the category exclusion firing instead)",
			atk.moves[0] == me_first)
	bm.queue_free()
