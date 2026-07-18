extends Node

# M18.5f test suite — Bind/Wrap-family binding-move mechanic (10 moves: Bind,
# Wrap, Fire Spin, Clamp, Whirlpool, Sand Tomb, Magma Storm, Infestation, Snap
# Trap, Thunder Cage). All 10 share the IDENTICAL real-source MOVE_EFFECT_WRAP
# additional effect (battle_script_commands.c L2465-2477) — ONE generic section
# per mechanism component below, not one section per move, matching Step 0's
# confirmed "no per-move variation beyond type/power/accuracy/category" finding.
#
# Ground truth: pokeemerald_expansion
#   Application:        battle_script_commands.c L2465-2477 (MOVE_EFFECT_WRAP case;
#                        if already wrapped, silent no-op — no re-trap, no stacking)
#   Duration roll:       battle_util.c :: SetWrapTurns L10726-10738 (RandomUniform
#                        4-5, B_BINDING_TURNS >= GEN_5 branch; Grip Claw's 7-turn
#                        fixed extension is out of scope, deferred M18.5i)
#   EOT damage/decrement: battle_end_turn.c :: HandleEndTurnWrap L649-687 — maxHP/8
#                        (B_BINDING_DAMAGE >= GEN_6), counter checked BEFORE
#                        decrementing (N turns set = N damage ticks, then one
#                        silent free "broke free" tick), counter still decrements
#                        under Magic Guard (only damage suppressed)
#   Escape block:        battle_util.c :: CanBattlerEscape L4943-4960 (Ghost-type
#                        bypass checked BEFORE the wrapped check — still takes
#                        damage, just can't be blocked from switching)
#   Source-leaves cure:   battle_main.c L3169-3170 / L3283-3284
#                        (SwitchInClearSetData/FaintClearSetData, the same two
#                        functions [M18.5d-3] already unified for infatuation —
#                        reused verbatim here)
#   No move-selection restriction: confirmed absent from every pre-move canceler
#                        in source — a wrapped Pokémon chooses and uses moves
#                        completely normally, only switching is blocked.
#
# Jaw Lock (MOVE_EFFECT_TRAP_BOTH) is deliberately excluded — a different,
# zero-damage, bidirectional, PERMANENT trap mechanic (escapePrevention, the
# Mean Look/Block family), confirmed via direct source read rather than assumed
# from name/flavor-text similarity. See move_data.gd's SE_WRAP doc comment.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_move_data()
	_test_section_b_try_apply_wrap()
	_test_section_c_is_trapped()
	_test_section_d_clear_volatiles()
	_test_section_e_end_of_turn_damage()
	_test_section_f_full_battle_integration()

	var total := _pass + _fail
	print("m18_5f_test: %d/%d passed" % [_pass, total])
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# ── Section A: Move data spot-checks (all 10 moves) ──────────────────────────
# [id, name, type, category(0=PHYS/1=SPEC), power, accuracy, pp, makes_contact]

func _test_section_a_move_data() -> void:
	var expected := [
		[20,  "Bind",         TypeChart.TYPE_NORMAL,   0, 15,  85,  20, true],
		[35,  "Wrap",         TypeChart.TYPE_NORMAL,   0, 15,  90,  20, true],
		[83,  "Fire Spin",    TypeChart.TYPE_FIRE,     1, 35,  85,  15, false],
		[128, "Clamp",        TypeChart.TYPE_WATER,    0, 35,  85,  15, true],
		[250, "Whirlpool",    TypeChart.TYPE_WATER,    1, 35,  85,  15, false],
		[328, "Sand Tomb",    TypeChart.TYPE_GROUND,   0, 35,  85,  15, false],
		[463, "Magma Storm",  TypeChart.TYPE_FIRE,     1, 100, 75,  5,  false],
		[611, "Infestation",  TypeChart.TYPE_BUG,      1, 20,  100, 20, true],
		[707, "Snap Trap",    TypeChart.TYPE_GRASS,    0, 35,  100, 15, true],
		[747, "Thunder Cage", TypeChart.TYPE_ELECTRIC, 1, 80,  90,  15, false],
	]
	for e: Array in expected:
		var id: int = e[0]
		var mv: MoveData = _load_move(id)
		var tag: String = "A.%d %s" % [id, e[1]]
		_chk(tag + " loaded", mv != null)
		if mv == null:
			continue
		_chk(tag + " name",           mv.move_name == e[1])
		_chk(tag + " type",           mv.type == e[2])
		_chk(tag + " category",       mv.category == e[3])
		_chk(tag + " power",          mv.power == e[4])
		_chk(tag + " accuracy",       mv.accuracy == e[5])
		_chk(tag + " pp",             mv.pp == e[6])
		_chk(tag + " makes_contact",  mv.makes_contact == e[7])
		_chk(tag + " secondary_effect=SE_WRAP", mv.secondary_effect == MoveData.SE_WRAP)
		_chk(tag + " secondary_chance=0 (guaranteed)", mv.secondary_chance == 0)


# ── Section B: StatusManager.try_apply_wrap — direct unit tests ─────────────

func _test_section_b_try_apply_wrap() -> void:
	var inflictor := _make_mon("B_Inflictor", TypeChart.TYPE_NORMAL)
	var victim := _make_mon("B_Victim", TypeChart.TYPE_NORMAL)

	_chk("B1 fresh application succeeds",
			StatusManager.try_apply_wrap(victim, inflictor))
	_chk("B2 wrapped_by set to the inflictor", victim.wrapped_by == inflictor)
	_chk("B3 wrapped_turns in [4,5] (random duration, no force)",
			victim.wrapped_turns == 4 or victim.wrapped_turns == 5)

	# B4/B5: force_wrap_turns seam pins an exact value, both ends of the range.
	var v4 := _make_mon("B_V4", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(v4, inflictor, 4)
	_chk("B4 force_wrap_turns=4 pins exactly 4", v4.wrapped_turns == 4)
	var v5 := _make_mon("B_V5", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(v5, inflictor, 5)
	_chk("B5 force_wrap_turns=5 pins exactly 5", v5.wrapped_turns == 5)

	# B6: already-wrapped is a silent no-op — no re-trap, original inflictor preserved.
	var second_attacker := _make_mon("B_Second", TypeChart.TYPE_FIRE)
	var reapply_result: bool = StatusManager.try_apply_wrap(victim, second_attacker, 5)
	_chk("B6 re-applying to an already-wrapped victim returns false",
			not reapply_result)
	_chk("B6b original inflictor is preserved (not overwritten by the second attacker)",
			victim.wrapped_by == inflictor)

	# B7: no Ghost-type gate on infliction — a Ghost-type victim still gets trapped
	# (the Ghost exemption is switch-only, via is_trapped(), confirmed in Section C).
	var ghost_victim := _make_mon("B_Ghost", TypeChart.TYPE_GHOST)
	_chk("B7 Ghost-type CAN be wrapped (trap volatile still applies)",
			StatusManager.try_apply_wrap(ghost_victim, inflictor))
	_chk("B7b Ghost-type victim's wrapped_by is set", ghost_victim.wrapped_by == inflictor)


# ── Section C: AbilityManager.is_trapped() — wrapped_by extension ───────────

func _test_section_c_is_trapped() -> void:
	var trapped := _make_mon("C_Trapped", TypeChart.TYPE_NORMAL)
	var inflictor := _make_mon("C_Inflictor", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(trapped, inflictor, 5)
	_chk("C1 wrapped mon (no trapping ability needed) is_trapped == true",
			AbilityManager.is_trapped(trapped, []))

	var ghost_trapped := _make_mon("C_GhostTrapped", TypeChart.TYPE_GHOST)
	StatusManager.try_apply_wrap(ghost_trapped, inflictor, 5)
	_chk("C2 wrapped Ghost-type is_trapped == false (Ghost bypass, checked before wrapped)",
			not AbilityManager.is_trapped(ghost_trapped, []))

	var plain := _make_mon("C_Plain", TypeChart.TYPE_NORMAL)
	_chk("C3 negative control: unwrapped mon, no trapping opponents, is_trapped == false",
			not AbilityManager.is_trapped(plain, []))


# ── Section D: BattleManager._clear_volatiles — reciprocal-scan parity with
# [M18.5d-3]'s infatuated_by fix (the exact same two source functions, the exact
# same call sites, the exact same shape — reused, not reinvented) ───────────

func _test_section_d_clear_volatiles() -> void:
	# D1: the SOURCE battler leaving the field cures the VICTIM's trap.
	var d1_bm := _make_bm()
	var d1_source := _make_mon("D1Source", TypeChart.TYPE_NORMAL)
	var d1_victim := _make_mon("D1Victim", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(d1_victim, d1_source, 5)
	d1_bm._combatants = [d1_victim, d1_source]
	d1_bm._clear_volatiles(d1_source)  # the SOURCE leaves, not the victim
	_chk("D1 the SOURCE battler leaving the field cures the VICTIM's trap",
			d1_victim.wrapped_by == null)
	_chk("D1b wrapped_turns also reset to 0", d1_victim.wrapped_turns == 0)
	d1_bm.queue_free()

	# D2: discriminator — an unrelated THIRD battler leaving does NOT cure it.
	var d2_bm := _make_bm()
	var d2_source := _make_mon("D2Source", TypeChart.TYPE_NORMAL)
	var d2_victim := _make_mon("D2Victim", TypeChart.TYPE_NORMAL)
	var d2_bystander := _make_mon("D2Bystander", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(d2_victim, d2_source, 5)
	d2_bm._combatants = [d2_victim, d2_source, d2_bystander]
	d2_bm._clear_volatiles(d2_bystander)
	_chk("D2 discriminator: an unrelated third battler leaving does NOT cure the trap",
			d2_victim.wrapped_by == d2_source)
	d2_bm.queue_free()

	# D3: the victim's OWN switch-out/faint clears its own trap (regression of the
	# pre-existing "mon's own half", same shape as [M18.5d-3]'s A14).
	var d3_bm := _make_bm()
	var d3_source := _make_mon("D3Source", TypeChart.TYPE_NORMAL)
	var d3_victim := _make_mon("D3Victim", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(d3_victim, d3_source, 5)
	d3_bm._combatants = [d3_victim, d3_source]
	d3_bm._clear_volatiles(d3_victim)  # the VICTIM leaves
	_chk("D3 the victim's own switch-out/faint clears its own trap",
			d3_victim.wrapped_by == null)
	d3_bm.queue_free()

	# D4: fainting the SOURCE battler also cures the victim (both real source
	# trigger functions — SwitchInClearSetData AND FaintClearSetData — collapse
	# into this same one chokepoint, so no separate faint-specific test path exists
	# in this project; calling _clear_volatiles directly already covers both).
	var d4_bm := _make_bm()
	var d4_source := _make_mon("D4Source", TypeChart.TYPE_NORMAL)
	var d4_victim := _make_mon("D4Victim", TypeChart.TYPE_NORMAL)
	StatusManager.try_apply_wrap(d4_victim, d4_source, 5)
	d4_bm._combatants = [d4_victim, d4_source]
	d4_source.current_hp = 0
	d4_source.fainted = true
	d4_bm._clear_volatiles(d4_source)
	_chk("D4 fainting the SOURCE battler also cures the victim's trap",
			d4_victim.wrapped_by == null)
	d4_bm.queue_free()


# ── Section E: end-of-turn damage tick + duration expiry ────────────────────
# Calls bm._phase_end_of_turn() directly on a manually-constructed BattleManager
# (matching [M18.5d-3]'s established precedent for calling private BattleManager
# functions directly for targeted, RNG-free unit testing) rather than driving a
# full randomized-duration battle, so exact tick counts can be verified precisely.

func _test_section_e_end_of_turn_damage() -> void:
	# E1: first tick deals exactly max(1, maxHP/8), signal-snapshotted.
	# base_hp=100 -> max_hp = base_hp + 60 at level 50/iv0/ev0 (2*base*50/100 = base
	# exactly), giving a clean max_hp=160, 160/8=20 — verified via BattlePokemon's
	# own _hp_formula rather than assumed equal to base_hp.
	var e1_bm := _make_bm()
	var e1_source := _make_mon("E1Source", TypeChart.TYPE_NORMAL)
	var e1_victim := _make_mon("E1Victim", TypeChart.TYPE_NORMAL, 100)
	StatusManager.try_apply_wrap(e1_victim, e1_source, 4)
	e1_bm._combatants = [e1_victim, e1_source]
	e1_bm._turn_order = [e1_victim, e1_source]
	var e1_dmg_log := []
	e1_bm.wrap_damage.connect(func(m, amt): e1_dmg_log.append([m, amt]))
	e1_bm._phase_end_of_turn()
	_chk("E1 wrap_damage fired exactly once on tick 1", e1_dmg_log.size() == 1)
	_chk("E1z max_hp is 160 as expected (100 base + 60 level offset)",
			e1_victim.max_hp == 160)
	if e1_dmg_log.size() == 1:
		_chk("E1b wrap_damage amount == maxHP/8 (160/8=20)", e1_dmg_log[0][1] == 20)
		_chk("E1c wrap_damage target is the victim", e1_dmg_log[0][0] == e1_victim)
	_chk("E1d current_hp reduced by that amount", e1_victim.current_hp == 140)
	_chk("E1e wrapped_turns decremented 4->3", e1_victim.wrapped_turns == 3)
	e1_bm.queue_free()

	# E2: a fresh 4-turn trap deals damage on exactly 4 separate end-of-turns, then
	# breaks free (wrap_ended, no damage) on the 5th — the off-by-one Step 0
	# confirmed directly from HandleEndTurnWrap's check-before-decrement ordering.
	var e2_bm := _make_bm()
	var e2_source := _make_mon("E2Source", TypeChart.TYPE_NORMAL)
	var e2_victim := _make_mon("E2Victim", TypeChart.TYPE_NORMAL, 8000)
	StatusManager.try_apply_wrap(e2_victim, e2_source, 4)
	e2_bm._combatants = [e2_victim, e2_source]
	e2_bm._turn_order = [e2_victim, e2_source]
	# Array wrappers throughout — lambda-captured scalars are snapshots, not
	# references (this project's own established GDScript gotcha).
	var e2_dmg_ticks := [0]
	var e2_ended := [false]
	e2_bm.wrap_damage.connect(func(m, amt): e2_dmg_ticks[0] += 1)
	e2_bm.wrap_ended.connect(func(m): e2_ended[0] = true)
	for i in range(4):
		e2_bm._phase_end_of_turn()
	_chk("E2 4-turn trap dealt damage on exactly 4 end-of-turns", e2_dmg_ticks[0] == 4)
	_chk("E2b still wrapped after the 4th damage tick (not yet freed)",
			e2_victim.wrapped_by != null)
	_chk("E2c wrap_ended has NOT fired yet", not e2_ended[0])
	e2_bm._phase_end_of_turn()  # the 5th, free tick
	_chk("E2d the 5th tick dealt NO additional damage", e2_dmg_ticks[0] == 4)
	_chk("E2e wrap_ended fired on the 5th tick", e2_ended[0])
	_chk("E2f wrapped_by cleared after the free tick", e2_victim.wrapped_by == null)
	e2_bm.queue_free()

	# E3: Magic Guard — the turn counter still decrements and the trap still
	# expires on schedule, but zero damage is taken across every tick.
	var e3_bm := _make_bm()
	var e3_source := _make_mon("E3Source", TypeChart.TYPE_NORMAL)
	var e3_victim := _make_mon("E3Victim", TypeChart.TYPE_NORMAL, 8000)
	e3_victim.ability = _load_ability(98)  # Magic Guard
	var e3_starting_hp: int = e3_victim.current_hp
	StatusManager.try_apply_wrap(e3_victim, e3_source, 4)
	e3_bm._combatants = [e3_victim, e3_source]
	e3_bm._turn_order = [e3_victim, e3_source]
	var e3_dmg_ticks := [0]
	e3_bm.wrap_damage.connect(func(m, amt): e3_dmg_ticks[0] += 1)
	for i in range(4):
		e3_bm._phase_end_of_turn()
	_chk("E3 Magic Guard: zero damage ticks across the full trap duration",
			e3_dmg_ticks[0] == 0)
	_chk("E3b Magic Guard: HP untouched", e3_victim.current_hp == e3_starting_hp)
	_chk("E3c Magic Guard: still wrapped after the 4th tick (counter reached 0 but " +
			"the free tick hasn't run yet — same timing as the non-Magic-Guard case)",
			e3_victim.wrapped_by != null)
	e3_bm._phase_end_of_turn()
	_chk("E3d Magic Guard: trap still expires on the 5th (free) tick, same as normal " +
			"(the counter ticked down on schedule despite zero damage ever landing)",
			e3_victim.wrapped_by == null)
	e3_bm.queue_free()

	# E4: lethal wrap damage faints the victim.
	var e4_bm := _make_bm()
	var e4_source := _make_mon("E4Source", TypeChart.TYPE_NORMAL)
	var e4_victim := _make_mon("E4Victim", TypeChart.TYPE_NORMAL, 8)
	StatusManager.try_apply_wrap(e4_victim, e4_source, 4)
	e4_victim.current_hp = 1
	e4_bm._combatants = [e4_victim, e4_source]
	e4_bm._turn_order = [e4_victim, e4_source]
	var e4_fainted := [false]
	e4_bm.pokemon_fainted.connect(func(m): e4_fainted[0] = (m == e4_victim))
	e4_bm._phase_end_of_turn()
	_chk("E4 lethal wrap damage faints the victim", e4_victim.fainted)
	_chk("E4b pokemon_fainted fired for the victim", e4_fainted[0])
	e4_bm.queue_free()


# ── Section F: full-battle integration — real move-execution dispatch ───────

func _test_section_f_full_battle_integration() -> void:
	var wrap_move := _load_move(35)  # Wrap
	var dummy := MoveData.new()
	dummy.move_name = "F_Dummy"
	dummy.type = TypeChart.TYPE_NORMAL
	dummy.category = 0
	dummy.power = 0
	dummy.accuracy = 0
	dummy.pp = 30

	var attacker := _make_mon("F_Attacker", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 100)
	attacker.add_move(wrap_move)
	var defender := _make_mon("F_Defender", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	defender.add_move(dummy)

	var bm := _make_bm()
	bm._force_hit = true  # Wrap's 90% accuracy would otherwise flake this assertion
	var applied_log := []
	bm.secondary_applied.connect(func(t, eff):
		if eff == MoveData.SE_WRAP:
			applied_log.append(t))
	bm.queue_move(0, 0)  # attacker: Wrap
	bm.queue_move(1, 0)  # defender: dummy 0-power move
	bm.start_battle(attacker, defender)

	_chk("F1 SE_WRAP secondary_applied fired for the defender (real dispatch path)",
			applied_log.size() >= 1 and applied_log[0] == defender)

	# F2: the wired-up switch block — a trapped opponent's voluntary switch attempt
	# fails and falls back to using a move instead (same shape as [M17f]'s own
	# Shadow-Tag-blocks-switch integration test).
	var f2_trapper := _make_mon("F2Trapper", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 100)
	f2_trapper.add_move(wrap_move)
	var f2_trapped := _make_mon("F2Trapped", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	f2_trapped.add_move(dummy)
	var f2_bench := _make_mon("F2Bench", TypeChart.TYPE_NORMAL, 200, 60, 60, 60, 60, 50)
	f2_bench.add_move(dummy)

	var f2_bm := _make_bm()
	f2_bm._force_hit = true  # same accuracy-flake fix as F1 — Wrap must land on turn 1
	var f2_switched_out := []
	f2_bm.pokemon_switched_out.connect(func(p, s): f2_switched_out.append(p))
	var f2_party := BattleParty.new()
	f2_party.members = [f2_trapped, f2_bench]
	f2_party.active_index = 0

	f2_bm.queue_move(0, 0)     # Turn 1, side 0: trapper uses Wrap.
	f2_bm.queue_move(1, 0)     # Turn 1, side 1: trapped uses its dummy move (not yet switching).
	f2_bm.queue_switch(1, 1)   # Turn 2, side 1: NOW attempts to switch — Wrap already landed turn 1.
	f2_bm.start_battle_with_parties(BattleParty.single(f2_trapper), f2_party)

	_chk("F2 a trapped opponent's voluntary switch never actually occurred",
			not f2_switched_out.any(func(p): return p == f2_trapped))
	f2_bm.queue_free()
