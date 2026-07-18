extends Node

# M17k test suite — Priority-move-block check (new infrastructure): Dazzling, Queenly
# Majesty, Armor Tail.
#
# Scope: the 3 abilities locked in docs/decisions.md [M17k] (Step 0 re-verified all
# three IDs against Section 13's exclusion sweep — none needed correction). Confirmed
# from source (IsDazzlingAbility, battle_move_resolution.c L1499-1509) all three share
# the EXACT SAME dispatch (CancelerPriorityBlock, L1511-1548) — a single shared
# mechanic, not three near-identical-but-subtly-different implementations.
#
# New infrastructure: AbilityManager.blocks_priority_move(defender, defender_ally,
# attacker, move, ng_active) -> bool. Source-verified as an EXECUTION-TIME gate (a
# "Canceler," dispatched before CancelerAccuracyCheck in source's canceler chain), not a
# selection-time block — the move is chosen normally, then FAILS. Gated on
# move.priority > 0 only. SIDE-WIDE: checks both the move's actual target and that
# target's doubles partner (source's loop checks every opposing battler, not just the
# chosen target) — this is why Queenly Majesty's own source description says "protects
# from priority" without restricting to the holder itself. Does NOT affect the holder's
# OWN priority moves — the function is only ever consulted against the OPPOSING side.
#
# All three abilities carry breakable=true in source, genuinely reachable here (unlike
# Sticky Hold's non-applicable case in [M17j] — the attacker and the Dazzling-family
# holder are always different battlers), so a Mold-Breaker-holding attacker correctly
# bypasses the block.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: all full-battle scenarios use Normal-type
#     attackers/defenders with Normal-type moves (Quick Attack/Tackle), avoiding any
#     incidental type interaction.
#
# Ground truth: pokeemerald_expansion src/battle_move_resolution.c ::
#   IsDazzlingAbility (L1499-1509), CancelerPriorityBlock (L1511-1548),
#   sMoveSuccessOrderCancelers (L2420-2448, confirms PRIORITY_BLOCK precedes
#   ACCURACY_CHECK).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_blocks_priority_move_unit()
	_test_section_3_priority_blocked_full_battle()
	_test_section_4_zero_priority_not_blocked_full_battle()
	_test_section_5_side_wide_doubles_full_battle()
	_test_section_6_holder_own_priority_move_unaffected()
	_test_section_7_no_ability_negative_case()

	var total := _pass + _fail
	print("m17k_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


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


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var queenly_majesty := _load_ability(214)
	_chk("S1.01 Queenly Majesty id=214", queenly_majesty.ability_id == 214)
	_chk("S1.02 Queenly Majesty breakable=true", queenly_majesty.breakable)

	var dazzling := _load_ability(219)
	_chk("S1.03 Dazzling id=219", dazzling.ability_id == 219)
	_chk("S1.04 Dazzling breakable=true", dazzling.breakable)

	var armor_tail := _load_ability(296)
	_chk("S1.05 Armor Tail id=296", armor_tail.ability_id == 296)
	_chk("S1.06 Armor Tail breakable=true", armor_tail.breakable)

	_chk("S1.07 none of the three carry any cant_be_* flag",
			not queenly_majesty.cant_be_suppressed and not dazzling.cant_be_suppressed
			and not armor_tail.cant_be_suppressed)


# ── Section 2: AbilityManager.blocks_priority_move — direct unit tests ───────

func _test_section_2_blocks_priority_move_unit() -> void:
	var quick_attack := _load_move(98)
	var tackle := _load_move(33)
	var queenly_majesty := _load_ability(214)
	var dazzling := _load_ability(219)
	var armor_tail := _load_ability(296)
	var mold_breaker := _load_ability(104)
	var intimidate := _load_ability(22)

	# (i) Each of the three blocks a priority-positive move.
	var attacker_i := _make_mon("Atk1", [TypeChart.TYPE_NORMAL])
	var def_qm := _make_mon("DefQM", [TypeChart.TYPE_NORMAL])
	def_qm.ability = queenly_majesty
	_chk("S2.01 Queenly Majesty blocks Quick Attack",
			AbilityManager.blocks_priority_move(def_qm, null, attacker_i, quick_attack))

	var def_dz := _make_mon("DefDZ", [TypeChart.TYPE_NORMAL])
	def_dz.ability = dazzling
	_chk("S2.02 Dazzling blocks Quick Attack",
			AbilityManager.blocks_priority_move(def_dz, null, attacker_i, quick_attack))

	var def_at := _make_mon("DefAT", [TypeChart.TYPE_NORMAL])
	def_at.ability = armor_tail
	_chk("S2.03 Armor Tail blocks Quick Attack",
			AbilityManager.blocks_priority_move(def_at, null, attacker_i, quick_attack))

	# (ii) None block a priority-zero move.
	_chk("S2.04 Dazzling does NOT block a priority-zero move (Tackle)",
			not AbilityManager.blocks_priority_move(def_dz, null, attacker_i, tackle))

	# (iii) Non-holder: no-op.
	var def_none := _make_mon("DefNone", [TypeChart.TYPE_NORMAL])
	def_none.ability = intimidate
	_chk("S2.05 non-holder does NOT block a priority move",
			not AbilityManager.blocks_priority_move(def_none, null, attacker_i, quick_attack))

	# (iv) Side-wide: the ally holds it, the direct target does not.
	var def_plain := _make_mon("DefPlain", [TypeChart.TYPE_NORMAL])
	var ally_dz := _make_mon("AllyDZ", [TypeChart.TYPE_NORMAL])
	ally_dz.ability = dazzling
	_chk("S2.06 side-wide: an ally holding Dazzling blocks a priority move aimed at the other slot",
			AbilityManager.blocks_priority_move(def_plain, ally_dz, attacker_i, quick_attack))

	# (v) A fainted ally does not extend protection.
	var ally_dz_fainted := _make_mon("AllyDZFainted", [TypeChart.TYPE_NORMAL])
	ally_dz_fainted.ability = dazzling
	ally_dz_fainted.fainted = true
	_chk("S2.07 a FAINTED ally holding Dazzling does NOT block",
			not AbilityManager.blocks_priority_move(def_plain, ally_dz_fainted, attacker_i, quick_attack))

	# (vi) Mold Breaker bypasses the block.
	var mb_attacker := _make_mon("MBAttacker", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	_chk("S2.08 Mold Breaker bypasses Dazzling's block",
			not AbilityManager.blocks_priority_move(def_dz, null, mb_attacker, quick_attack))
	_chk("S2.09 Mold Breaker does NOT bypass when the attacker isn't the actual attacker of this check " +
			"(sanity: passing null attacker means no bypass context at all)",
			AbilityManager.blocks_priority_move(def_dz, null, null, quick_attack))

	# (vii) Neutralizing Gas suppresses the block.
	_chk("S2.10 Neutralizing Gas suppresses Dazzling's block (ng_active=true)",
			not AbilityManager.blocks_priority_move(def_dz, null, attacker_i, quick_attack, true))


# ── Section 3: priority-positive move blocked — full-battle integration ─────

func _test_section_3_priority_blocked_full_battle() -> void:
	var quick_attack := _load_move(98)
	var dazzling := _load_ability(219)

	var attacker := _make_mon("BattleQAAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(quick_attack)
	var defender := _make_mon("BattleDazzlingDef", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	defender.ability = dazzling
	defender.add_move(quick_attack)

	var fail_events := []
	var ability_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): fail_events.push_back([t, r]))
	bm.ability_triggered.connect(func(p, k): ability_events.push_back([p, k]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))

	_chk("S3.01 move_effect_failed fired with priority_blocked",
			fail_events.any(func(e): return e[0] == attacker and e[1] == "priority_blocked"))
	_chk("S3.02 ability_triggered fired tagged dazzling_family",
			ability_events.any(func(e): return e[0] == defender and e[1] == "dazzling_family"))

	bm.queue_free()


# ── Section 4: priority-zero move NOT blocked — full-battle integration ─────

func _test_section_4_zero_priority_not_blocked_full_battle() -> void:
	var tackle := _load_move(33)
	var dazzling := _load_ability(219)

	var attacker := _make_mon("BattleTackleAttacker", [TypeChart.TYPE_NORMAL], 100, 150, 60, 60, 60, 200)
	attacker.add_move(tackle)
	var defender := _make_mon("BattleDazzlingDef2", [TypeChart.TYPE_NORMAL], 100, 40, 20, 40, 20, 40)
	defender.ability = dazzling
	defender.add_move(tackle)

	var fail_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): fail_events.push_back([t, r]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))

	_chk("S4.01 Dazzling does NOT block a priority-zero move (Tackle)",
			not fail_events.any(func(e): return e[0] == attacker and e[1] == "priority_blocked"))
	_chk("S4.02 real damage was dealt to the Dazzling holder",
			move_executed_events.any(func(e): return e[0] == attacker and e[1] == defender and e[3] > 0))

	bm.queue_free()


# ── Section 5: side-wide protection — full-battle doubles integration ───────

func _test_section_5_side_wide_doubles_full_battle() -> void:
	var quick_attack := _load_move(98)
	var dazzling := _load_ability(219)

	var attacker0 := _make_mon("BattleSWAttacker0", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker0.add_move(quick_attack)
	var attacker1 := _make_mon("BattleSWAttacker1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	attacker1.add_move(quick_attack)

	# Target (idx2, no ability) is the actual move target; its ally (idx3) holds Dazzling.
	var target := _make_mon("BattleSWTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.add_move(quick_attack)
	var dazzling_ally := _make_mon("BattleSWDazzlingAlly", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	dazzling_ally.ability = dazzling
	dazzling_ally.add_move(quick_attack)

	var fail_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): fail_events.push_back([t, r]))

	# combatant indices in doubles: 0,1 = attacker side; 2,3 = target side.
	bm.queue_move_targeted(0, 0, 2)  # Turn 1: attacker0 (idx0) Quick Attacks target (idx2).
	bm.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(target, dazzling_ally))

	_chk("S5.01 the priority move aimed at 'target' failed because its ALLY holds Dazzling (side-wide)",
			fail_events.any(func(e): return e[0] == attacker0 and e[1] == "priority_blocked"))

	bm.queue_free()


# ── Section 6: the holder's OWN priority move is unaffected ─────────────────

func _test_section_6_holder_own_priority_move_unaffected() -> void:
	var quick_attack := _load_move(98)
	var dazzling := _load_ability(219)

	var dazzling_attacker := _make_mon("BattleDZOwnAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	dazzling_attacker.ability = dazzling
	dazzling_attacker.add_move(quick_attack)
	var plain_defender := _make_mon("BattlePlainDef", [TypeChart.TYPE_NORMAL], 100, 40, 20, 40, 20, 40)
	plain_defender.add_move(quick_attack)

	var fail_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): fail_events.push_back([t, r]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(dazzling_attacker), BattleParty.single(plain_defender))

	_chk("S6.01 the Dazzling holder's OWN priority move is NOT blocked",
			not fail_events.any(func(e): return e[0] == dazzling_attacker and e[1] == "priority_blocked"))
	_chk("S6.02 real damage was dealt by the Dazzling holder's Quick Attack",
			move_executed_events.any(func(e): return e[0] == dazzling_attacker and e[1] == plain_defender and e[3] > 0))

	bm.queue_free()


# ── Section 7: ordinary Pokémon (no ability) blocks nothing — negative control ─

func _test_section_7_no_ability_negative_case() -> void:
	var quick_attack := _load_move(98)

	var attacker := _make_mon("BattleNegAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 200)
	attacker.add_move(quick_attack)
	var defender := _make_mon("BattleNegDef", [TypeChart.TYPE_NORMAL], 100, 40, 20, 40, 20, 40)
	defender.add_move(quick_attack)

	var fail_events := []
	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_effect_failed.connect(func(t, r): fail_events.push_back([t, r]))
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))

	_chk("S7.01 an ordinary Pokémon with no ability does not block the priority move",
			not fail_events.any(func(e): return e[0] == attacker and e[1] == "priority_blocked"))
	_chk("S7.02 real damage was dealt",
			move_executed_events.any(func(e): return e[0] == attacker and e[1] == defender and e[3] > 0))

	bm.queue_free()
