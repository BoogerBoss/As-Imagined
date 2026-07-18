extends Node

# [M19-break-protect] Feint(364), Shadow Force(467), Phantom Force(566),
# Hyperspace Hole(593) — Bucket 4 sub-group.
#
# Step 0 findings (see move_data.gd's breaks_protect doc comment for full
# source citations):
#   - All 4 moves share the LITERAL SAME MOVE_EFFECT_FEINT additionalEffect
#     in source — genuinely uniform mechanism, despite Feint's name and its
#     historically-lower power suggesting it might be structurally distinct
#     from the other 3 (which are two-turn semi-invulnerable attacks).
#     Power/accuracy/pp/type/category/priority are NOT uniform, though.
#   - `ignores_protect` (pre-existing field) and `breaks_protect` (new) are
#     genuinely different mechanisms: ignores only lets THIS move's own hit
#     bypass an already-up Protect; breaks additionally CLEARS the target's
#     protect_active + resets protect_consecutive (the Gen5+ 1/3^n
#     fail-chance ramp) as a POST-HIT side effect. All 4 moves set both.
#   - POST-HIT ONLY: none of the 4 set `.preAttackEffect`, so a MISS does
#     NOT break Protect — the same shape `[M19-recharge]` already
#     established for this project's is_recharge.
#   - Source's side-wide-Protect-on-the-partner half (Wide Guard/Quick
#     Guard/Crafty Shield) is NOT modeled — this project has zero side-wide
#     protect moves implemented, so that half of source's own logic has
#     nothing to act on. Single-target scope only.
#   - Shadow Force/Phantom Force needed a genuinely NEW semi-invulnerable
#     state (SEMI_INV_VANISH) — source's STATE_PHANTOM_FORCE explicitly
#     returns FALSE from CanBreakThroughSemiInvulnerablityInternal (nothing
#     hits through it), a DIFFERENT branch from that function's own default
#     (STATE_NONE/unknown → TRUE) — and this project's own
#     _can_hit_semi_invulnerable helper defaults an unrecognized state to
#     TRUE too, the opposite of what's needed, so an explicit case was
#     required rather than relying on the default.
#   - No King's Shield/Spiky Shield/Baneful Bunker/Obstruct/Silk
#     Trap/Crafty Shield exist in this project (only Protect/Detect) — the
#     "does this bypass every Protect-family move uniformly" question is
#     moot for now.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c, battle_util.c, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_semi_inv_direct()
	_test_breaking_move_connects_through_protect()
	_test_normal_move_still_blocked_by_protect()
	_test_break_clears_protect_state()
	_test_miss_does_not_break_protect()
	_test_two_turn_semi_inv_unaffected()

	var total := _pass + _fail
	print("m19_break_protect_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, 50)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: data integrity (all 4 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var feint := _load_move(364)
	_chk("364 Feint loads", feint != null)
	_chk("364 name/type/category/power/accuracy/pp/priority",
			feint.move_name == "Feint" and feint.type == TypeChart.TYPE_NORMAL
					and feint.category == 0 and feint.power == 30
					and feint.accuracy == 100 and feint.pp == 10 and feint.priority == 2)
	_chk("364 ignores_protect + breaks_protect, NOT makes_contact (Feint is non-contact)",
			feint.ignores_protect and feint.breaks_protect and not feint.makes_contact)

	var shadow_force := _load_move(467)
	_chk("467 Shadow Force loads", shadow_force != null)
	_chk("467 name/type/category/power/accuracy/pp",
			shadow_force.move_name == "Shadow Force" and shadow_force.type == TypeChart.TYPE_GHOST
					and shadow_force.category == 0 and shadow_force.power == 120
					and shadow_force.accuracy == 100 and shadow_force.pp == 5)
	_chk("467 makes_contact + two_turn + SEMI_INV_VANISH + ignores_protect + breaks_protect",
			shadow_force.makes_contact and shadow_force.two_turn
					and shadow_force.semi_inv_state == MoveData.SEMI_INV_VANISH
					and shadow_force.ignores_protect and shadow_force.breaks_protect)

	var phantom_force := _load_move(566)
	_chk("566 Phantom Force loads", phantom_force != null)
	_chk("566 name/type/category/power/accuracy/pp (genuinely different power from Shadow Force)",
			phantom_force.move_name == "Phantom Force" and phantom_force.type == TypeChart.TYPE_GHOST
					and phantom_force.category == 0 and phantom_force.power == 90
					and phantom_force.accuracy == 100 and phantom_force.pp == 10)
	_chk("566 makes_contact + two_turn + SEMI_INV_VANISH + ignores_protect + breaks_protect",
			phantom_force.makes_contact and phantom_force.two_turn
					and phantom_force.semi_inv_state == MoveData.SEMI_INV_VANISH
					and phantom_force.ignores_protect and phantom_force.breaks_protect)

	var hyperspace_hole := _load_move(593)
	_chk("593 Hyperspace Hole loads", hyperspace_hole != null)
	_chk("593 name/type/category/power/accuracy/pp (accuracy=0, never misses)",
			hyperspace_hole.move_name == "Hyperspace Hole" and hyperspace_hole.type == TypeChart.TYPE_PSYCHIC
					and hyperspace_hole.category == 1 and hyperspace_hole.power == 80
					and hyperspace_hole.accuracy == 0 and hyperspace_hole.pp == 5)
	_chk("593 ignores_protect + ignores_substitute + breaks_protect, NOT makes_contact",
			hyperspace_hole.ignores_protect and hyperspace_hole.ignores_substitute
					and hyperspace_hole.breaks_protect and not hyperspace_hole.makes_contact)


# ── SEMI_INV_VANISH: direct unit test of the exact fix (explicit case, not
# the default-true fallthrough) ─────────────────────────────────────────────

func _test_semi_inv_direct() -> void:
	var tackle := _load_move(33)
	var fissure := _load_move(90)  # an OHKO move, damages_underground likely false
	_chk("SEMI_INV_VANISH blocks an ordinary move (Tackle) — the exact fix under test",
			StatusManager._can_hit_semi_invulnerable(tackle, MoveData.SEMI_INV_VANISH) == false)
	_chk("SEMI_INV_NONE still permits any move (regression control, unaffected by the new case)",
			StatusManager._can_hit_semi_invulnerable(tackle, MoveData.SEMI_INV_NONE) == true)
	_chk("SEMI_INV_VANISH blocks even an OHKO move (no move flag reaches this state)",
			StatusManager._can_hit_semi_invulnerable(fissure, MoveData.SEMI_INV_VANISH) == false)


# ── A Protect-breaking move actually connects against a Protect-using target ─

func _test_breaking_move_connects_through_protect() -> void:
	var feint := _load_move(364)
	var protect := _load_move(182)
	var atk := _make_mon("BrkAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(feint)
	var def := _make_mon("BrkDef", TypeChart.TYPE_NORMAL, 200, 10, 60, 10, 60, 40)
	def.add_move(protect)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var protect_ok := [false]
	bm.protected.connect(func(mon):
		if mon == def and not protect_ok[0]:
			protect_ok[0] = true)
	var feint_result := [false, -1]  # [fired, damage]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not feint_result[0]:
			feint_result[0] = true
			feint_result[1] = amt)
	bm.start_battle(atk, def)

	_chk("Protect actually succeeded first (baseline, not a vacuous setup)", protect_ok[0] == true)
	_chk("Feint connects and deals real damage THROUGH an active Protect (%s)" % [feint_result],
			feint_result[0] == true and feint_result[1] > 0)


# ── Discriminator: a normal move WITHOUT the flag is still blocked by the
# same Protect — proves the above isn't a vacuous pass (Protect itself works) ─

func _test_normal_move_still_blocked_by_protect() -> void:
	var tackle := _load_move(33)
	var protect := _load_move(182)
	var atk := _make_mon("NoBrkAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(tackle)
	var def := _make_mon("NoBrkDef", TypeChart.TYPE_NORMAL, 200, 10, 60, 10, 60, 40)
	def.add_move(protect)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	var events := []
	bm.move_missed.connect(func(a, reason):
		if a == atk and events.is_empty():
			events.append("missed:" + reason))
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and events.is_empty():
			events.append("hit:%d" % amt))
	bm.start_battle(atk, def)

	_chk("Discriminator: plain Tackle (no ignores/breaks_protect) is blocked by Protect (%s)" % [events],
			events.size() > 0 and events[0] == "missed:protected")


# ── Breaking clears BOTH protect_active and protect_consecutive ─────────────

func _test_break_clears_protect_state() -> void:
	var feint := _load_move(364)
	var protect := _load_move(182)
	var atk := _make_mon("ClrAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(feint)
	var def := _make_mon("ClrDef", TypeChart.TYPE_NORMAL, 200, 10, 60, 10, 60, 40)
	def.add_move(protect)

	var bm := _make_bm()
	bm._force_hit = true
	bm._force_crit = false
	# protect_active is unconditionally cleared at the START of every turn
	# (battle_manager.gd's per-turn volatile reset), so a pre-set before
	# start_battle() would be wiped before Feint ever fires — must set it up
	# via a REAL Protect use instead. protect_consecutive is NOT touched by
	# that per-turn reset, so once Protect's own success sets it to 1, the
	# `protected` handler bumps it further to 5 (simulating deep into a
	# consecutive-use streak) right before Feint (lower priority, resolves
	# after Protect within the same turn) breaks it.
	bm.protected.connect(func(mon):
		if mon == def:
			mon.protect_consecutive = 5)
	var snap := [false, true, -1]  # [fired, protect_active_after, protect_consecutive_after]
	bm.protect_broken.connect(func(mon):
		if mon == def and not snap[0]:
			snap[0] = true
			snap[1] = mon.protect_active
			snap[2] = mon.protect_consecutive)
	bm.start_battle(atk, def)

	_chk("protect_broken fired for the defender", snap[0] == true)
	_chk("Breaking clears protect_active to false (%s)" % [snap], snap[1] == false)
	_chk("Breaking resets protect_consecutive to 0, un-ramping the Gen5+ fail chance (%s)" % [snap],
			snap[2] == 0)


# ── A MISS does NOT break Protect — the key divergence, verified not assumed ─

func _test_miss_does_not_break_protect() -> void:
	var feint := _load_move(364)
	var protect := _load_move(182)
	var atk := _make_mon("MissAtk", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	atk.add_move(feint)
	var def := _make_mon("MissDef", TypeChart.TYPE_NORMAL, 200, 10, 60, 10, 60, 40)
	def.add_move(protect)

	var bm := _make_bm()
	bm._force_hit = false  # guaranteed miss for atk's own Feint attempts
	# Same real-Protect-use setup as _test_break_clears_protect_state (see
	# its own comment): protect_active can't be pre-set before start_battle,
	# it's cleared at the start of every turn. def.protect_consecutive
	# defaults to 0, so Protect's own success roll is guaranteed (1/1).
	var protect_ok := [false, -1]  # [fired, protect_active_snapshot]
	bm.protected.connect(func(mon):
		if mon == def and not protect_ok[0]:
			protect_ok[0] = true
			protect_ok[1] = mon.protect_active
	)
	var missed := [false]
	bm.move_missed.connect(func(a, reason):
		if a == atk and not missed[0] and reason == "accuracy":
			missed[0] = true)
	var broke := [false]
	bm.protect_broken.connect(func(mon):
		if mon == def:
			broke[0] = true)
	bm.start_battle(atk, def)

	_chk("Protect actually succeeded first (baseline, not a vacuous setup)",
			protect_ok[0] == true and protect_ok[1] == true)
	_chk("Feint genuinely missed (confirms this isn't a vacuous pass)", missed[0] == true)
	_chk("protect_broken never fired on a miss", broke[0] == false)


# ── Shadow Force's own two-turn/semi-invulnerable turn is unaffected by
# adding breaks_protect — confirmed via the NEW SEMI_INV_VANISH state
# actually blocking an ordinary move during the charge turn ─────────────────

func _test_two_turn_semi_inv_unaffected() -> void:
	var shadow_force := _load_move(467)
	var tackle := _load_move(33)
	# atk faster, so its own charge-turn semi-invulnerability is set BEFORE
	# def's Tackle resolves within the same turn.
	var atk := _make_mon("VanAtk", TypeChart.TYPE_GHOST, 100, 60, 60, 60, 60, 200)
	atk.add_move(shadow_force)
	var def := _make_mon("VanDef", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 10)
	def.add_move(tackle)

	var bm := _make_bm()
	# No _force_hit override here — the semi-invulnerable gate must block
	# Tackle deterministically on its own, independent of any accuracy roll.
	var charge_seen := [false]
	bm.charge_started.connect(func(mon, _m):
		if mon == atk:
			charge_seen[0] = true)
	var def_missed := [false, ""]
	bm.move_missed.connect(func(a, reason):
		if a == def and not def_missed[0]:
			def_missed[0] = true
			def_missed[1] = reason)
	bm.start_battle(atk, def)

	# Note: unlike the OHKO branch (which emits a distinct "semi_invulnerable"
	# reason), the general damaging-move path routes through
	# StatusManager.check_accuracy and the caller labels any false return
	# "accuracy" regardless of cause. This is still a valid, deterministic
	# discriminator: Tackle's own accuracy is 100 (calc=100, "randi()%100<100"
	# is always true under real RNG), so the ONLY way it can report a miss
	# here at all is the semi-invulnerable gate inside check_accuracy.
	_chk("Shadow Force still enters its charge turn (two_turn mechanism intact)", charge_seen[0] == true)
	_chk("Def's Tackle is blocked by the charging user's new semi-invulnerable state (%s)" % [def_missed],
			def_missed[0] == true and def_missed[1] == "accuracy")
