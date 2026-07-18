extends Node

# [Perish Song] Perish Song(195) — the LAST move in D4's own residual pool
# that's cheap enough to ship without its own dedicated session (Transform
# remains, per the Step 0 recon's own recommendation). Full Step-0 findings
# recorded in docs/decisions.md's own [Perish Song] entry; summarized here:
#
#  - The FIRST move in this project needing genuine ALL-BATTLERS dispatch.
#    `MoveData.TARGET_ALL_BATTLERS` existed as a dormant constant (read
#    only by AbilityManager's Pressure PP-cost calc) — this move is the
#    first to actually set `.target` to it.
#  - Cast: loops over EVERY currently-active combatant, both sides,
#    including the caster itself. Per-target exclusions confirmed from
#    source: already counting down; Soundproof (reuses the existing
#    `blocks_move_flag` gate, since Perish Song is a sound move);
#    Prankster-boosted-and-Dark-type-blocked (reuses `blocks_prankster_move`,
#    checked per-target). `ignoresProtect`/`ignoresSubstitute` are both TRUE
#    in source, so neither is checked. Source's own `IsBattlerUnaffectedByMove`
#    check was traced and confirmed NOT reachable from this move's own
#    dispatch (its script never runs through the pipeline that sets that
#    flag) — not modeled. Fails outright ONLY if every single combatant was
#    already excluded.
#  - End of turn: checked BEFORE decrementing (matching source's own
#    off-by-one shape) — a timer of 3 ticks 3→2→1→0 across 3 passes
#    (message-only), the 4TH pass (timer already 0) deals the fatal blow —
#    a direct HP-zero, the same shape Self-Destruct/Explosion already use.
#  - PERISH BODY: `perish_song_active`/`perish_song_timer` now exist and are
#    exactly what Perish Body's own contact-reactive mechanism would reuse
#    (confirmed mechanically trivial once these fields exist, per the
#    original Step 0 finding) — NOT implemented this session, flagged for
#    Rob's own future call on reopening its exclusion.
#
# Ground truth: pokeemerald_expansion src/battle_script_commands.c ::
#   Cmd_trysetperishsong (L8400-8424); src/battle_end_turn.c ::
#   HandleEndTurnPerishSong (L979-996); src/data/moves_info.h ::
#   MOVE_PERISH_SONG (L5341-5362).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_cast_dispatch()
	_test_end_of_turn_countdown()
	_test_doubles_reachability()
	_test_negative_control()

	var total := _pass + _fail
	print("perish_song_test: %d/%d passed" % [_pass, total])
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, mon_type: int = TypeChart.TYPE_NORMAL,
		hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = hp
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Direct single-dispatch helper — resolves exactly ONE _phase_move_execution()
# call, avoiding the whole-battle-aggregation pitfall entirely (matching the
# convention established for Mimic/Sketch's own tests).
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
	# Default target doesn't matter for an all-battlers move, but must be
	# a valid index for _phase_move_execution's own defender lookup.
	var other_idx: int = 1 if attacker_idx == 0 else 0
	var chosen_targets: Array[int] = []
	for i in range(combatants.size()):
		chosen_targets.append(other_idx if i == attacker_idx else attacker_idx)
	bm._chosen_targets = chosen_targets
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = attacker_idx
	bm._phase_move_execution()
	return bm


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var ps := _load_move(195)
	_chk("A.01 Perish Song loads", ps != null)
	if ps == null:
		return
	_chk("A.02 is_perish_song=true", ps.is_perish_song == true)
	_chk("A.03 target=TARGET_ALL_BATTLERS", ps.target == MoveData.TARGET_ALL_BATTLERS)
	_chk("A.04 accuracy=0 (no accuracy check)", ps.accuracy == 0)
	_chk("A.05 pp=5", ps.pp == 5)
	_chk("A.06 ignores_protect=true", ps.ignores_protect == true)
	_chk("A.07 ignores_substitute=true", ps.ignores_substitute == true)
	_chk("A.08 sound_move=true (Soundproof-blockable)", ps.sound_move == true)
	_chk("A.09 carries BAN_MIRROR_MOVE", (ps.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0)


# ── Section B: cast dispatch ──────────────────────────────────────────────

func _test_cast_dispatch() -> void:
	var ps := _load_move(195)

	# B.01/B.02: hits BOTH sides, including the caster itself.
	var caster := _make_mon("PSCaster")
	caster.add_move(ps)
	var opp := _make_mon("PSOpp")
	var bm1 := _dispatch_move([caster, opp], 0, ps)
	_chk("B.01 The caster itself is affected", caster.perish_song_active and caster.perish_song_timer == 3)
	_chk("B.02 The opponent is also affected", opp.perish_song_active and opp.perish_song_timer == 3)
	bm1.queue_free()

	# B.03: a mon already counting down is unaffected by a second cast (its
	# own timer is untouched, not reset back to 3).
	var caster2 := _make_mon("PSCaster2")
	caster2.add_move(ps)
	var opp2 := _make_mon("PSOpp2")
	opp2.perish_song_active = true
	opp2.perish_song_timer = 1
	var bm2 := _dispatch_move([caster2, opp2], 0, ps)
	_chk("B.03 Caster2 (not yet counting) IS affected by this cast",
			caster2.perish_song_active and caster2.perish_song_timer == 3)
	_chk("B.03b Opp2 (already counting from before) keeps its OWN timer, not reset to 3",
			opp2.perish_song_timer == 1)
	bm2.queue_free()

	# B.04: all-unaffected fail — every combatant already counting down.
	var caster3 := _make_mon("PSCaster3")
	caster3.add_move(ps)
	caster3.perish_song_active = true
	caster3.perish_song_timer = 2
	var opp3 := _make_mon("PSOpp3")
	opp3.perish_song_active = true
	opp3.perish_song_timer = 1
	var ps_failed := [false]
	var bm3 := _make_bm()
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == caster3 and reason == "perish_song_failed":
			ps_failed[0] = true)
	bm3._combatants = [caster3, opp3]
	bm3._active_per_side = 1
	bm3._actor_indices = {caster3: 0, opp3: 1}
	bm3._chosen_moves = [ps, null]
	bm3._chosen_switch_slots = [-1, -1]
	bm3._chosen_targets = [1, 0]
	bm3._turn_order = [caster3, opp3]
	bm3._current_actor_index = 0
	bm3._phase_move_execution()
	_chk("B.04 Fails outright when every combatant is already unaffected",
			ps_failed[0] == true)
	_chk("B.04b Neither combatant's own timer was disturbed by the failed cast",
			caster3.perish_song_timer == 2 and opp3.perish_song_timer == 1)
	bm3.queue_free()

	# B.05: Soundproof exclusion — a Soundproof holder is skipped, but the
	# move still succeeds overall (the caster itself is still affected).
	var caster4 := _make_mon("PSCaster4")
	caster4.add_move(ps)
	var soundproof_opp := _make_mon("PSSoundproofOpp")
	soundproof_opp.ability = _load_ability(43)  # Soundproof
	var bm4 := _dispatch_move([caster4, soundproof_opp], 0, ps)
	_chk("B.05 A Soundproof holder is NOT affected", not soundproof_opp.perish_song_active)
	_chk("B.05b The caster itself is still affected (move succeeded overall)",
			caster4.perish_song_active)
	bm4.queue_free()


# ── Section C: end-of-turn countdown ──────────────────────────────────────

func _test_end_of_turn_countdown() -> void:
	var mon := _make_mon("PSCountdown", TypeChart.TYPE_NORMAL, 300)
	mon.perish_song_active = true
	mon.perish_song_timer = 3
	var opp := _make_mon("PSCountdownOpp")
	var bm := _make_bm()
	bm._combatants = [mon, opp]
	bm._active_per_side = 1
	bm._turn_order = [mon, opp]

	bm._phase_end_of_turn()
	_chk("C.01 Tick 1: timer 3→2, no faint yet", mon.perish_song_timer == 2 and not mon.fainted)

	bm._phase_end_of_turn()
	_chk("C.02 Tick 2: timer 2→1, no faint yet", mon.perish_song_timer == 1 and not mon.fainted)

	bm._phase_end_of_turn()
	_chk("C.03 Tick 3: timer 1→0, no faint yet (checked BEFORE decrementing " +
			"— this is the last count-down-only tick)", mon.perish_song_timer == 0 and not mon.fainted)

	bm._phase_end_of_turn()
	_chk("C.04 Tick 4: timer was already 0 — instant guaranteed faint",
			mon.fainted == true and mon.current_hp == 0)
	_chk("C.04b perish_song_active cleared after the faint", mon.perish_song_active == false)
	bm.queue_free()


# ── Section D: doubles reachability ────────────────────────────────────────

func _test_doubles_reachability() -> void:
	var ps := _load_move(195)
	var caster := _make_mon("PSDoublesCaster")
	caster.add_move(ps)
	var ally := _make_mon("PSDoublesAlly")
	var opp1 := _make_mon("PSDoublesOpp1")
	var opp2 := _make_mon("PSDoublesOpp2")
	var combatants: Array[BattlePokemon] = [caster, ally, opp1, opp2]
	var bm := _dispatch_move(combatants, 0, ps)
	_chk("D.01 All 4 doubles combatants are affected by a single cast (caster)",
			caster.perish_song_active)
	_chk("D.02 All 4 doubles combatants are affected by a single cast (ally)",
			ally.perish_song_active)
	_chk("D.03 All 4 doubles combatants are affected by a single cast (opp1)",
			opp1.perish_song_active)
	_chk("D.04 All 4 doubles combatants are affected by a single cast (opp2)",
			opp2.perish_song_active)
	bm.queue_free()


# ── Section E: negative control ────────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := _load_move(33)
	_chk("E.01 Tackle carries is_perish_song=false", tackle.is_perish_song == false)
	_chk("E.02 Tackle's target is NOT TARGET_ALL_BATTLERS", tackle.target != MoveData.TARGET_ALL_BATTLERS)

	var atk := _make_mon("NegAtk")
	var def := _make_mon("NegDef")
	atk.add_move(tackle)
	var bm := _dispatch_move([atk, def], 0, tackle)
	_chk("E.03 An ordinary Tackle never sets perish_song_active on anyone",
			not atk.perish_song_active and not def.perish_song_active)
	bm.queue_free()
