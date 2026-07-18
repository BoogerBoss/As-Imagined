extends Node

# [Mimic/Sketch] Mimic(102), Sketch(166) — the last 2 of D4's 4 confirmed
# NOVEL-MECHANISM moves (Transform(144)/Perish Song(195) remain, per the
# Step 0 recon's recommendation to give Transform its own dedicated
# session). Full Step-0 findings recorded in docs/decisions.md's own
# [Mimic/Sketch] entry; summarized here:
#
#  - Both copy the target's last-used move (this project's existing
#    `BattlePokemon.last_move_used`, confirmed equivalent to source's
#    gLastMoves/gLastPrintedMoves for every reachable scenario — no new
#    move-tracking state needed).
#  - Mimic: TEMPORARY overwrite of its OWN slot, PP capped at min(realPP, 5),
#    restored to "Mimic" itself (via `mimicked_slot`/`mimicked_original_move`/
#    `mimicked_original_pp`) at the mon's NEXT switch-in (matching source's
#    switch-IN-time party-data restoration, not a switch-out one).
#  - Sketch: PERMANENT overwrite, full real PP (no cap), never restored.
#    Its own "already known" check excludes OTHER Sketch-carrying slots from
#    the comparison (confirmed from source, not assumed symmetric with
#    Mimic).
#  - Both fail if the target's last move is BAN_MIMIC/BAN_SKETCH-flagged
#    (bitmask fields that already existed dormant in MoveData, same class
#    of pre-anticipated-but-unpopulated field as TARGET_ALL_BATTLERS) or
#    already known by the attacker.
#  - Source's "attacker already Transformed" fail condition is NOT modeled
#    for either move — Transform isn't implemented in this project yet.
#    Metronome/Mirror Move are used here as the BAN_MIMIC discriminator
#    instead (both needed the flag added — it was missing from both
#    entries despite existing as a dormant constant already).
#
# Ground truth: pokeemerald_expansion src/battle_script_commands.c ::
#   Cmd_mimicattackcopy (L7843-7879), Cmd_copymovepermanently (L8101-8144);
#   src/data/moves_info.h :: MOVE_MIMIC (L2741-2769), MOVE_SKETCH
#   (L4550-4579).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_mimic()
	_test_sketch()
	_test_negative_control()

	var total := _pass + _fail
	print("mimic_sketch_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, speed: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = speed
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var mimic := _load_move(102)
	_chk("A.01 Mimic loads", mimic != null)
	if mimic != null:
		_chk("A.02 Mimic is_mimic=true", mimic.is_mimic == true)
		_chk("A.03 Mimic is_sketch=false", mimic.is_sketch == false)
		_chk("A.04 Mimic carries BAN_MIMIC (self)",
				(mimic.ban_flags & MoveData.BAN_MIMIC) != 0)
		_chk("A.05 Mimic accuracy=0 (no accuracy check)", mimic.accuracy == 0)
		_chk("A.06 Mimic pp=10", mimic.pp == 10)
		_chk("A.07 Mimic ignores_substitute=true", mimic.ignores_substitute == true)

	var sketch := _load_move(166)
	_chk("A.08 Sketch loads", sketch != null)
	if sketch != null:
		_chk("A.09 Sketch is_sketch=true", sketch.is_sketch == true)
		_chk("A.10 Sketch is_mimic=false", sketch.is_mimic == false)
		_chk("A.11 Sketch carries BAN_SKETCH (self)",
				(sketch.ban_flags & MoveData.BAN_SKETCH) != 0)
		_chk("A.12 Sketch carries BAN_MIMIC too", (sketch.ban_flags & MoveData.BAN_MIMIC) != 0)
		_chk("A.13 Sketch carries BAN_MIRROR_MOVE too",
				(sketch.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0)
		_chk("A.14 Sketch accuracy=0", sketch.accuracy == 0)
		_chk("A.15 Sketch pp=1", sketch.pp == 1)
		_chk("A.16 Sketch ignores_protect=true", sketch.ignores_protect == true)
		_chk("A.17 Sketch ignores_substitute=true", sketch.ignores_substitute == true)

	# The 2 pre-existing moves that needed BAN_MIMIC added (a real gap found
	# at Step 0 — dormant constant existed, just never populated on these).
	var metronome := _load_move(118)
	_chk("A.18 Metronome now carries BAN_MIMIC (was missing)",
			(metronome.ban_flags & MoveData.BAN_MIMIC) != 0)
	var mirror_move := _load_move(119)
	_chk("A.19 Mirror Move now carries BAN_MIMIC (was missing)",
			(mirror_move.ban_flags & MoveData.BAN_MIMIC) != 0)

	# A real asymmetry caught while writing Section C's own BAN_SKETCH test:
	# Sleep Talk is mimicBanned but NOT sketchBanned in source, despite both
	# lists sharing most other members — locked in here as a permanent
	# regression guard, not just fixed silently in the test.
	var sleep_talk := _load_move(214)
	_chk("A.20 Sleep Talk carries BAN_MIMIC", (sleep_talk.ban_flags & MoveData.BAN_MIMIC) != 0)
	_chk("A.21 Sleep Talk does NOT carry BAN_SKETCH (a real, confirmed asymmetry)",
			(sleep_talk.ban_flags & MoveData.BAN_SKETCH) == 0)
	var struggle := _load_move(165)
	_chk("A.22 Struggle carries BAN_SKETCH", (struggle.ban_flags & MoveData.BAN_SKETCH) != 0)


# A single-call dispatch helper: builds a minimal BattleManager and resolves
# exactly ONE _phase_move_execution() call (attacker uses `move` against
# defender), then returns immediately — no further turns ever run. Avoids
# the whole-battle-aggregation pitfall entirely (CLAUDE.md's own documented
# convention) rather than needing to snapshot PP via signals across a full,
# open-ended battle where a successful copy would keep getting re-used
# (and its PP further consumed) by auto-select on every subsequent turn.
func _dispatch_move(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData) -> BattleManager:
	var bm := _make_bm()
	bm._combatants = [attacker, defender]
	bm._actor_indices = {attacker: 0, defender: 1}
	bm._active_per_side = 1
	bm._chosen_moves = [move, null]
	bm._chosen_targets = [1, 0]
	bm._turn_order = [attacker, defender]
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


# ── Section B: Mimic ──────────────────────────────────────────────────────

func _test_mimic() -> void:
	var mimic := _load_move(102)
	var ember := _load_move(52)   # pp=25, not banned — the copy target
	var sleep_talk := _load_move(214)  # BAN_MIMIC-flagged (stand-in for Transform)

	# B.01-B.04: successful copy — Mimic's own slot becomes Ember, PP capped
	# at 5, mimicked_slot/mimicked_original_move recorded correctly.
	var atk1 := _make_mon("MimicAtk1")
	var opp1 := _make_mon("MimicOpp1")
	atk1.add_move(mimic)
	opp1.last_move_used = ember
	var bm1 := _dispatch_move(atk1, opp1, mimic)
	_chk("B.01 Mimic copied Ember into its own slot", atk1.moves[0] == ember)
	_chk("B.02 Mimic's copied PP is capped at 5 (Ember's real PP is 25)",
			atk1.current_pp[0] == 5)
	_chk("B.03 mimicked_slot recorded as 0", atk1.mimicked_slot == 0)
	_chk("B.04 mimicked_original_move recorded as Mimic itself",
			atk1.mimicked_original_move == mimic)
	_chk("B.04b mimicked_original_pp snapshotted as 9 (Mimic's own 10 PP, " +
			"minus the 1 PP its own cast just deducted)",
			atk1.mimicked_original_pp == 9)
	bm1.queue_free()

	# B.05: already-known-move fail — attacker already knows Ember elsewhere.
	var atk2 := _make_mon("MimicAtk2")
	var opp2 := _make_mon("MimicOpp2")
	atk2.add_move(ember)
	atk2.add_move(mimic)
	opp2.last_move_used = ember
	var b205_failed := [false]
	var bm2 := _make_bm()
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "mimic_failed":
			b205_failed[0] = true)
	bm2._combatants = [atk2, opp2]
	bm2._actor_indices = {atk2: 0, opp2: 1}
	bm2._active_per_side = 1
	bm2._chosen_moves = [mimic, null]
	bm2._chosen_targets = [1, 0]
	bm2._turn_order = [atk2, opp2]
	bm2._current_actor_index = 0
	bm2._phase_move_execution()
	_chk("B.05 Mimic fails when the attacker already knows the target's move",
			b205_failed[0] == true)
	_chk("B.05b Mimic's own slot is unchanged on failure", atk2.moves[1] == mimic)
	bm2.queue_free()

	# B.06: BAN_MIMIC fail — target's last move is banned from being copied.
	var atk3 := _make_mon("MimicAtk3")
	var opp3 := _make_mon("MimicOpp3")
	atk3.add_move(mimic)
	opp3.last_move_used = sleep_talk
	var b3_failed := [false]
	var bm3 := _make_bm()
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "mimic_failed":
			b3_failed[0] = true)
	bm3._combatants = [atk3, opp3]
	bm3._actor_indices = {atk3: 0, opp3: 1}
	bm3._active_per_side = 1
	bm3._chosen_moves = [mimic, null]
	bm3._chosen_targets = [1, 0]
	bm3._turn_order = [atk3, opp3]
	bm3._current_actor_index = 0
	bm3._phase_move_execution()
	_chk("B.06 Mimic fails to copy a BAN_MIMIC-flagged move (Sleep Talk, standing in for " +
			"Transform's own not-yet-implemented ban)", b3_failed[0] == true)
	bm3.queue_free()

	# B.07-B.10: switch-in restoration — after a successful copy, the SAME
	# reset function called at every real switch-in site (_reset_mon_
	# mimicked_move) reverts the slot to Mimic itself, with Mimic's OWN
	# remaining PP (9, not full 10 and not Ember's PP) — matching the
	# [Ability-reset fix] test convention exactly (direct call to the
	# extracted, directly-testable reset function).
	var atk4 := _make_mon("MimicAtk4")
	var opp4 := _make_mon("MimicOpp4")
	atk4.add_move(mimic)
	opp4.last_move_used = ember
	var bm4 := _dispatch_move(atk4, opp4, mimic)
	_chk("B.07 pre-check: Mimic copied Ember before testing restoration",
			atk4.moves[0] == ember and atk4.current_pp[0] == 5)
	bm4._reset_mon_mimicked_move(atk4)
	_chk("B.08 Mimic's slot reverted to Mimic itself after switch-in restoration",
			atk4.moves[0] == mimic)
	_chk("B.09 Mimic's PP reverted to 9 (its own post-cast PP, not full 10 or Ember's)",
			atk4.current_pp[0] == 9)
	_chk("B.10 mimicked_slot cleared back to -1", atk4.mimicked_slot == -1)
	bm4.queue_free()


# ── Section C: Sketch ─────────────────────────────────────────────────────

func _test_sketch() -> void:
	var sketch := _load_move(166)
	var ember := _load_move(52)   # pp=25
	var growl := _load_move(45)
	# Struggle(165), not Sleep Talk — confirmed from source's real sketchBanned
	# list (MOVE_STRUGGLE/MOVE_SKETCH/MOVE_CHATTER only; Sleep Talk is
	# mimicBanned but NOT sketchBanned, a real asymmetry between the two
	# moves' ban lists, not assumed shared).
	var struggle := _load_move(165)

	# C.01/C.02: successful copy — full real PP, not capped.
	var atk1 := _make_mon("SketchAtk1")
	var opp1 := _make_mon("SketchOpp1")
	atk1.add_move(sketch)
	opp1.last_move_used = ember
	var bm1 := _dispatch_move(atk1, opp1, sketch)
	_chk("C.01 Sketch copied Ember into its own slot", atk1.moves[0] == ember)
	_chk("C.02 Sketch's copied PP is the FULL real value (25), not capped at 5",
			atk1.current_pp[0] == 25)
	bm1.queue_free()

	# C.03: already-known-move fail (a genuine different known move, not a
	# Sketch slot).
	var atk2 := _make_mon("SketchAtk2")
	var opp2 := _make_mon("SketchOpp2")
	atk2.add_move(ember)
	atk2.add_move(sketch)
	opp2.last_move_used = ember
	var c3_failed := [false]
	var bm2 := _make_bm()
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "sketch_failed":
			c3_failed[0] = true)
	bm2._combatants = [atk2, opp2]
	bm2._actor_indices = {atk2: 0, opp2: 1}
	bm2._active_per_side = 1
	bm2._chosen_moves = [sketch, null]
	bm2._chosen_targets = [1, 0]
	bm2._turn_order = [atk2, opp2]
	bm2._current_actor_index = 0
	bm2._phase_move_execution()
	_chk("C.03 Sketch fails when the attacker already knows the target's move",
			c3_failed[0] == true)
	bm2.queue_free()

	# C.04: BAN_SKETCH fail.
	var atk3 := _make_mon("SketchAtk3")
	var opp3 := _make_mon("SketchOpp3")
	atk3.add_move(sketch)
	opp3.last_move_used = struggle
	var c4_failed := [false]
	var bm3 := _make_bm()
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "sketch_failed":
			c4_failed[0] = true)
	bm3._combatants = [atk3, opp3]
	bm3._actor_indices = {atk3: 0, opp3: 1}
	bm3._active_per_side = 1
	bm3._chosen_moves = [sketch, null]
	bm3._chosen_targets = [1, 0]
	bm3._turn_order = [atk3, opp3]
	bm3._current_actor_index = 0
	bm3._phase_move_execution()
	_chk("C.04 Sketch fails to copy a BAN_SKETCH-flagged move", c4_failed[0] == true)
	bm3.queue_free()

	# C.05: own-slot-exclusion — a second, still-unused Sketch slot doesn't
	# block sketching a brand-new move (source explicitly skips comparing
	# against slots that still hold Sketch itself).
	var atk4 := _make_mon("SketchAtk4")
	var opp4 := _make_mon("SketchOpp4")
	atk4.add_move(sketch)  # slot 0: about to be used
	atk4.add_move(sketch)  # slot 1: a second, still-unused Sketch slot
	opp4.last_move_used = growl
	var bm4 := _dispatch_move(atk4, opp4, sketch)
	_chk("C.05 Sketch succeeds despite a second unused Sketch slot present",
			atk4.moves[0] == growl)
	_chk("C.05b the other Sketch slot is untouched", atk4.moves[1] == sketch)
	bm4.queue_free()

	# C.06: permanence across switch-out+in — Sketch's own overwrite is NEVER
	# restored, unlike Mimic's. Confirmed by calling the exact same reset
	# functions real switch-in sites use, and showing they leave Sketch's
	# slot untouched (there is no `_reset_mon_sketched_move`-equivalent at
	# all — nothing exists to call, which is itself the point).
	var atk5 := _make_mon("SketchAtk5")
	var opp5 := _make_mon("SketchOpp5")
	atk5.add_move(sketch)
	opp5.last_move_used = ember
	var bm5 := _dispatch_move(atk5, opp5, sketch)
	_chk("C.06 pre-check: Sketch copied Ember", atk5.moves[0] == ember and atk5.current_pp[0] == 25)
	bm5._reset_mon_type(atk5)
	bm5._reset_mon_ability(atk5)
	bm5._reset_mon_mimicked_move(atk5)  # a no-op here — atk5 never used Mimic
	_chk("C.07 Sketch's copy PERSISTS through the real switch-in reset functions (permanent)",
			atk5.moves[0] == ember)
	_chk("C.07b PP still the full real value after switch-in resets run", atk5.current_pp[0] == 25)
	bm5.queue_free()


# ── Section D: negative control ──────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := _load_move(33)
	_chk("D.01 Tackle carries neither is_mimic nor is_sketch",
			tackle.is_mimic == false and tackle.is_sketch == false)
	_chk("D.02 Tackle carries none of the BAN_MIMIC/BAN_SKETCH flags",
			(tackle.ban_flags & (MoveData.BAN_MIMIC | MoveData.BAN_SKETCH)) == 0)

	var atk := _make_mon("NegAtk", 90)
	var def := _make_mon("NegDef", 60)
	atk.add_move(tackle)
	def.add_move(tackle)
	var bm := _make_bm()
	var learned_fired := [false]
	bm.move_learned.connect(func(_m, _s, _mv): learned_fired[0] = true)
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("D.03 An ordinary Tackle exchange never fires move_learned",
			learned_fired[0] == false)
	bm.queue_free()
