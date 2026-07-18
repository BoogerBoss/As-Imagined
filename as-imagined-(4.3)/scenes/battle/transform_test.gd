extends Node

# [Transform] Transform(144) — the LAST move in all of M19's residual pool.
# Full Step-0 findings recorded in docs/decisions.md's own [Transform] entry;
# summarized here:
#
#  - Confirmed the largest lift in the residual pool, per Step 0. Copies onto
#    the attacker: species (duplicated, NOT a bare reference — the
#    shared-Resource-mutation hazard this suite's Section E specifically
#    regression-tests), the 5 computed stats, stat_stages (confirmed WITHIN
#    source's copied byte range — a real, easy-to-miss detail), ability (a
#    RAW reference copy, deliberately NOT through effective_ability_id — see
#    Section H), types (comes along free via the species duplicate), and
#    moves+PP (capped at min(realPP, 5) per slot). `times_hit` is a separate,
#    explicit, PERMANENT special-case copy (source: GetBattlerPartyState) —
#    confirmed real source behavior, not reverted on switch-out (Section G).
#  - `pre_transform_moves`/`pre_transform_pp` are a CAST-TIME snapshot (not
#    construction-time, unlike original_species/original_attack/etc.), since
#    PP is consumed as the battle progresses.
#  - Fails if: target semi-invulnerable, target already Transformed, attacker
#    already Transformed, or Substitute blocks it (`ignores_substitute=false`
#    at this project's GEN_LATEST config — confirmed, not assumed).
#    `ignores_protect=true` bypasses Protect entirely (Section I).
#  - Mimic/Sketch's own "attacker already Transformed" fail condition (a real
#    source-confirmed check, previously flagged as unmodeled since Transform
#    didn't exist) is now closed as a byproduct of this session.
#  - Instruct's own hardcoded exclusion list gained `is_transform` (Section J)
#    — Transform has no dormant ban_flags-based exclusion in this codebase.
#
# Ground truth: pokeemerald_expansion src/battle_script_commands.c ::
#   Cmd_transformdataexecution (L7747-7823); include/pokemon.h ::
#   struct BattlePokemon (L338-372, the copied-byte-range field order).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_basic_transform()
	_test_fail_conditions()
	_test_stat_stages_copied()
	_test_shared_resource_hazard()
	_test_switch_out_restoration()
	_test_times_hit_permanence()
	_test_ability_copy_bypasses_suppression()
	_test_bypasses_protect()
	_test_instruct_cannot_repeat_transform()
	_test_negative_control()

	var total := _pass + _fail
	print("transform_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, mon_types: Array = [TypeChart.TYPE_NORMAL],
		base_atk: int = 60, base_def: int = 60, base_spa: int = 60,
		base_spd: int = 60, base_spe: int = 60, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	var t: Array[int] = []
	for x in mon_types:
		t.append(x)
	sp.types = t
	sp.base_hp = hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_spa
	sp.base_sp_defense = base_spd
	sp.base_speed = base_spe
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Direct single-dispatch helper — resolves exactly ONE _phase_move_execution()
# call, avoiding the whole-battle-aggregation pitfall entirely (matching the
# convention established for Mimic/Sketch/Perish Song's own tests).
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


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var xf := _load_move(144)
	_chk("A.01 Transform loads", xf != null)
	if xf == null:
		return
	_chk("A.02 is_transform=true", xf.is_transform == true)
	_chk("A.03 accuracy=0 (no accuracy check)", xf.accuracy == 0)
	_chk("A.04 pp=10", xf.pp == 10)
	_chk("A.05 ignores_protect=true", xf.ignores_protect == true)
	_chk("A.06 ignores_substitute=false (Substitute DOES block it at GEN_LATEST)",
			xf.ignores_substitute == false)
	_chk("A.07 carries BAN_MIRROR_MOVE", (xf.ban_flags & MoveData.BAN_MIRROR_MOVE) != 0)
	_chk("A.08 carries BAN_MIMIC", (xf.ban_flags & MoveData.BAN_MIMIC) != 0)
	_chk("A.09 carries BAN_METRONOME", (xf.ban_flags & MoveData.BAN_METRONOME) != 0)
	_chk("A.10 carries BAN_COPYCAT", (xf.ban_flags & MoveData.BAN_COPYCAT) != 0)
	_chk("A.11 carries BAN_INSTRUCT", (xf.ban_flags & MoveData.BAN_INSTRUCT) != 0)
	_chk("A.12 carries BAN_ENCORE", (xf.ban_flags & MoveData.BAN_ENCORE) != 0)
	_chk("A.13 carries BAN_ASSIST", (xf.ban_flags & MoveData.BAN_ASSIST) != 0)
	_chk("A.14 does NOT carry BAN_SKETCH (Sketch can legitimately copy Transform)",
			(xf.ban_flags & MoveData.BAN_SKETCH) == 0)


# ── Section B: basic successful Transform ─────────────────────────────────

func _test_basic_transform() -> void:
	var xf := _load_move(144)
	var tackle := _load_move(33)   # pp=35 — proves the PP-cap-at-5 direction
	var sketch := _load_move(166)  # pp=1  — proves PP is NOT raised above a lower base

	var attacker := _make_mon("XformAtk", [TypeChart.TYPE_NORMAL], 40, 40, 40, 40, 40, 120)
	attacker.add_move(xf)
	var atk_own_attack := attacker.attack
	var atk_own_speed := attacker.speed

	var target := _make_mon("XformTarget", [TypeChart.TYPE_WATER, TypeChart.TYPE_FLYING],
			90, 70, 110, 80, 130, 200)
	target.add_move(tackle)
	target.add_move(sketch)

	var bm := _dispatch_move([attacker, target], 0, xf)

	_chk("B.01 attacker.transformed == true", attacker.transformed == true)
	_chk("B.02 species copied (species_name matches target's)",
			attacker.species.species_name == target.species.species_name)
	_chk("B.03 species is a DIFFERENT object (duplicated, not a shared reference)",
			attacker.species != target.species)
	_chk("B.04 types copied (both slots)",
			attacker.species.types[0] == TypeChart.TYPE_WATER
			and attacker.species.types[1] == TypeChart.TYPE_FLYING)
	_chk("B.05 attack copied from target (differs from attacker's own pre-Transform value)",
			attacker.attack == target.attack and attacker.attack != atk_own_attack)
	_chk("B.06 defense copied from target", attacker.defense == target.defense)
	_chk("B.07 sp_attack copied from target", attacker.sp_attack == target.sp_attack)
	_chk("B.08 sp_defense copied from target", attacker.sp_defense == target.sp_defense)
	_chk("B.09 speed copied from target (differs from attacker's own pre-Transform value)",
			attacker.speed == target.speed and attacker.speed != atk_own_speed)
	_chk("B.10 attacker's own original_attack is UNCHANGED by the copy (still its true value)",
			attacker.original_attack == atk_own_attack)
	_chk("B.11 moves copied (slot 0 is target's Tackle)", attacker.moves[0] == tackle)
	_chk("B.12 moves copied (slot 1 is target's Sketch)", attacker.moves[1] == sketch)
	_chk("B.13 PP capped at 5 for a move with base PP > 5 (Tackle, real pp=35)",
			attacker.current_pp[0] == 5)
	_chk("B.14 PP NOT raised above a move's own lower base PP (Sketch, real pp=1)",
			attacker.current_pp[1] == 1)
	bm.queue_free()


# ── Section C: all 4 fail conditions, independently ───────────────────────

func _test_fail_conditions() -> void:
	var xf := _load_move(144)

	# C1: target semi-invulnerable.
	var atk1 := _make_mon("FailAtk1")
	atk1.add_move(xf)
	var tgt1 := _make_mon("FailTgt1")
	tgt1.semi_invulnerable = MoveData.SEMI_INV_ON_AIR
	var bm1 := _dispatch_move([atk1, tgt1], 0, xf)
	_chk("C1 fails when the target is semi-invulnerable", not atk1.transformed)
	bm1.queue_free()

	# C2: target already Transformed.
	var atk2 := _make_mon("FailAtk2")
	atk2.add_move(xf)
	var tgt2 := _make_mon("FailTgt2")
	tgt2.transformed = true
	var bm2 := _dispatch_move([atk2, tgt2], 0, xf)
	_chk("C2 fails when the target is already Transformed", not atk2.transformed)
	bm2.queue_free()

	# C3: attacker already Transformed.
	var atk3 := _make_mon("FailAtk3")
	atk3.add_move(xf)
	atk3.transformed = true
	var atk3_species_before := atk3.species
	var tgt3 := _make_mon("FailTgt3")
	var bm3 := _dispatch_move([atk3, tgt3], 0, xf)
	_chk("C3 fails when the attacker is already Transformed " +
			"(species left unchanged by this failed second attempt)",
			atk3.species == atk3_species_before)
	bm3.queue_free()

	# C4: Substitute-blocked.
	var atk4 := _make_mon("FailAtk4")
	atk4.add_move(xf)
	var tgt4 := _make_mon("FailTgt4")
	tgt4.substitute_hp = 50
	var bm4 := _dispatch_move([atk4, tgt4], 0, xf)
	_chk("C4 fails when Substitute blocks it " +
			"(ignores_substitute=false at this project's GEN_LATEST config)",
			not atk4.transformed)
	bm4.queue_free()


# ── Section D: stat_stages ARE copied from the target ─────────────────────

func _test_stat_stages_copied() -> void:
	var xf := _load_move(144)
	var attacker := _make_mon("StageAtk")
	attacker.add_move(xf)
	attacker.stat_stages[BattlePokemon.STAGE_ATK] = 2  # attacker's own pre-Transform boost

	var target := _make_mon("StageTarget")
	target.stat_stages[BattlePokemon.STAGE_SPEED] = -3
	target.stat_stages[BattlePokemon.STAGE_DEF] = 1

	var bm := _dispatch_move([attacker, target], 0, xf)
	_chk("D.01 attacker's stat_stages now match target's, NOT its own pre-Transform +2 Atk",
			attacker.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	_chk("D.02 attacker copied target's -3 Speed stage",
			attacker.stat_stages[BattlePokemon.STAGE_SPEED] == -3)
	_chk("D.03 attacker copied target's +1 Defense stage",
			attacker.stat_stages[BattlePokemon.STAGE_DEF] == 1)
	bm.queue_free()


# ── Section E: shared-Resource mutation hazard regression ─────────────────
# The exact corruption Step 0 flagged: a naive `attacker.species = target.species`
# (bare reference, no duplicate) would let a LATER type-mutating move on the
# transformed attacker corrupt the REAL target's own species.types in place.

func _test_shared_resource_hazard() -> void:
	var xf := _load_move(144)
	var conversion := _load_move(160)

	var electric_move := MoveData.new()
	electric_move.type = TypeChart.TYPE_ELECTRIC
	electric_move.category = 1  # Special — irrelevant to Conversion's own dispatch
	electric_move.pp = 10

	var attacker := _make_mon("HazardAtk")
	attacker.add_move(xf)

	var target := _make_mon("HazardTarget", [TypeChart.TYPE_WATER])
	target.add_move(electric_move)

	var bm1 := _dispatch_move([attacker, target], 0, xf)
	_chk("E.01 attacker transformed and now has the target's Water type",
			attacker.species.types[0] == TypeChart.TYPE_WATER)
	bm1.queue_free()

	# The now-TRANSFORMED attacker uses Conversion. Its own first move slot
	# (copied from the target) is the synthetic Electric-type move — different
	# from its current (copied Water) type, so Conversion genuinely changes it.
	var bm2 := _dispatch_move([attacker, target], 0, conversion)
	_chk("E.02 Conversion changed the TRANSFORMED attacker's own type to Electric",
			attacker.species.types[0] == TypeChart.TYPE_ELECTRIC)
	_chk("E.03 THE REAL TARGET's own species.types is UNTOUCHED (still Water) " +
			"— the regression test for the shared-Resource-mutation hazard Step 0 flagged",
			target.species.types[0] == TypeChart.TYPE_WATER)
	bm2.queue_free()


# ── Section F: switch-out restoration ──────────────────────────────────────
# Uses _do_voluntary_switch directly (bypassing _phase_battle_start's own
# leads-loop reset entirely), so this isolates the SWITCH-triggered reset
# specifically — confirming both that switching OUT does NOT immediately
# revert the OUTGOING mon (the reset runs on the INCOMING mon at every real
# call site) and that switching back IN does.

func _test_switch_out_restoration() -> void:
	var xf := _load_move(144)
	var tackle := _load_move(33)
	var overgrow := _load_ability(65)   # Overgrow
	var levitate := _load_ability(26)   # Levitate

	var attacker := _make_mon("RevertAtk", [TypeChart.TYPE_NORMAL], 40, 40, 40, 40, 40, 500)
	attacker.add_move(xf)
	attacker.ability = overgrow

	var target := _make_mon("RevertTarget", [TypeChart.TYPE_WATER, TypeChart.TYPE_FLYING],
			90, 70, 110, 80, 130, 200)
	target.add_move(tackle)
	target.ability = levitate

	var atk_true_species_name := attacker.species.species_name
	var atk_true_type0 := attacker.species.types[0]
	var atk_true_attack := attacker.attack
	var atk_true_speed := attacker.speed
	var atk_true_moves := attacker.moves.duplicate()

	var bm1 := _dispatch_move([attacker, target], 0, xf)
	_chk("F.00 setup: attacker really did Transform",
			attacker.transformed and attacker.species.species_name == target.species.species_name)
	# The correct restore target for PP is `pre_transform_pp` itself — NOT a
	# naive pre-dispatch snapshot. Transform's own cast deducts its own 1 PP
	# (like any move) BEFORE this project's dispatch code snapshots
	# `pre_transform_pp`, so the true value to restore to is 9/10, not a
	# fresh 10/10 — matching how a real Ditto's Transform slot correctly
	# shows 9/10 after using it once, reverting to 9 (not 10) on switch-out.
	var atk_true_pp := attacker.pre_transform_pp.duplicate()
	bm1.queue_free()

	var bench := _make_mon("RevertBench")
	var party := BattleParty.new()
	party.members = [attacker, bench]

	var bm2 := _make_bm()
	bm2._active_per_side = 1
	bm2._parties = [party]
	bm2._combatants = [attacker]

	bm2._do_voluntary_switch(0, 1)  # switch attacker OUT to bench
	_chk("F.00b immediately after switching OUT, attacker is STILL Transformed " +
			"(the reset runs on the INCOMING mon at every real call site, not the outgoing one)",
			attacker.transformed == true)

	bm2._do_voluntary_switch(0, 0)  # switch BACK to attacker — now the incoming mon
	_chk("F.01 species reverted", attacker.species.species_name == atk_true_species_name)
	_chk("F.02 types reverted", attacker.species.types[0] == atk_true_type0)
	_chk("F.03 attack stat reverted", attacker.attack == atk_true_attack)
	_chk("F.04 speed stat reverted", attacker.speed == atk_true_speed)
	_chk("F.05 ability reverted", attacker.ability == overgrow)
	_chk("F.06 moves reverted", attacker.moves == atk_true_moves)
	_chk("F.07 PP reverted", attacker.current_pp == atk_true_pp)
	_chk("F.08 transformed flag cleared", attacker.transformed == false)
	bm2.queue_free()


# ── Section G: times_hit permanence ─────────────────────────────────────────
# The one deliberate divergence from every other restored field — confirmed
# real source behavior (GetBattlerPartyState writes directly into the
# attacker's own persistent record, with no restoration anywhere).

func _test_times_hit_permanence() -> void:
	var xf := _load_move(144)
	var attacker := _make_mon("HitAtk")
	attacker.add_move(xf)
	attacker.times_hit = 2

	var target := _make_mon("HitTarget")
	target.times_hit = 7

	var bm1 := _dispatch_move([attacker, target], 0, xf)
	_chk("G.01 times_hit copied from target on Transform", attacker.times_hit == 7)
	bm1.queue_free()

	var bench := _make_mon("HitBench")
	var party := BattleParty.new()
	party.members = [attacker, bench]

	var bm2 := _make_bm()
	bm2._active_per_side = 1
	bm2._parties = [party]
	bm2._combatants = [attacker]
	bm2._do_voluntary_switch(0, 1)
	bm2._do_voluntary_switch(0, 0)
	_chk("G.02 times_hit is NOT reverted by switch-out+in — permanent, matching " +
			"source's real (surprising but confirmed) behavior",
			attacker.times_hit == 7)
	bm2.queue_free()


# ── Section H: ability copy correctness under Neutralizing Gas ────────────

func _test_ability_copy_bypasses_suppression() -> void:
	var xf := _load_move(144)
	var overgrow := _load_ability(65)

	var attacker := _make_mon("NGAtk")
	attacker.add_move(xf)
	var target := _make_mon("NGTarget")
	target.ability = overgrow

	_chk("H.00 sanity: effective_ability_id resolves the target's ability to NONE " +
			"when NG is forced active — confirms the risk this test guards against is real",
			AbilityManager.effective_ability_id(target, true) == AbilityManager.ABILITY_NONE)

	var bm := _dispatch_move([attacker, target], 0, xf)
	_chk("H.01 attacker's RAW .ability is the target's TRUE ability (Overgrow), " +
			"NOT ABILITY_NONE — the copy is a raw field read, not routed through " +
			"effective_ability_id",
			attacker.ability == overgrow)
	_chk("H.02 once copied, it resolves correctly via the normal accessor when NG is NOT active",
			AbilityManager.effective_ability_id(attacker, false) == AbilityManager.ABILITY_OVERGROW)
	_chk("H.03 and correctly suppresses too if NG becomes active LATER " +
			"(suppression is a live per-read check, not baked in at copy time)",
			AbilityManager.effective_ability_id(attacker, true) == AbilityManager.ABILITY_NONE)
	bm.queue_free()


# ── Section I: Transform bypasses Protect ──────────────────────────────────

func _test_bypasses_protect() -> void:
	var xf := _load_move(144)
	var attacker := _make_mon("ProtectAtk")
	attacker.add_move(xf)
	var target := _make_mon("ProtectTarget")
	target.protect_active = true

	var bm := _dispatch_move([attacker, target], 0, xf)
	_chk("I.01 Transform succeeds against a Protect-active target " +
			"(ignores_protect=true bypasses the general _is_protected_from gate)",
			attacker.transformed == true)
	bm.queue_free()


# ── Section J: Instruct cannot force a re-use of Transform ─────────────────

func _test_instruct_cannot_repeat_transform() -> void:
	var xf := _load_move(144)
	var instruct := _load_move(652)

	var attacker := _make_mon("InstructAtk")
	attacker.add_move(instruct)
	var target := _make_mon("InstructTarget")
	target.add_move(xf)
	target.current_pp[0] = 5
	target.last_move_used = xf

	var bm := _dispatch_move([attacker, target], 0, instruct)
	_chk("J.01 Instruct fails to force a re-use of the target's last move (Transform)",
			not attacker.transformed)
	_chk("J.02 the target's own PP is untouched (Instruct never actually re-executed Transform)",
			target.current_pp[0] == 5)
	bm.queue_free()


# ── Section K: negative control ────────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := _load_move(33)
	_chk("K.01 Tackle carries is_transform=false", tackle.is_transform == false)

	var atk := _make_mon("NegAtk")
	var def := _make_mon("NegDef")
	atk.add_move(tackle)
	var bm := _dispatch_move([atk, def], 0, tackle)
	_chk("K.02 An ordinary Tackle never sets transformed on anyone",
			not atk.transformed and not def.transformed)
	bm.queue_free()
