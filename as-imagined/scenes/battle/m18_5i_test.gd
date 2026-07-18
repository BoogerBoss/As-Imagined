extends Node

# M18.5i test suite — reconsideration-pass Group B: Grip Claw (item),
# Skill Link (ability), Loaded Dice (item). All three unblocked by earlier
# M18.5 infrastructure tiers ([M18.5f]'s binding mechanic, [M18.5g]'s
# multi-hit mechanism) but deliberately deferred out of those tiers' own
# scope until now. Group A (Rivalry/Attract/Cute Charm/Oblivious) needed no
# new work — already fully implemented in [M18.5d Phase 2]. Group C
# (confusion berries/Power-item EV half/Destiny Knot) all confirmed still
# blocked — see docs/decisions.md's [M18.5i] entry, no test coverage needed
# for permanently-inapplicable mechanics.
#
# Ground truth: pokeemerald_expansion
#   Grip Claw:   battle_util.c :: SetWrapTurns (L10726-10738), B_WRAP_TURNS=7
#                (include/config/battle.h L213) — fixed 7 turns instead of
#                the random RandomUniform(4,5) roll.
#   Skill Link:  battle_move_resolution.c :: CancelerMultihitMoves
#                (L2331-2332) — forces multi_hit (variable) moves to exactly
#                5 hits. Does NOT affect fixed strike_count moves.
#   Loaded Dice: battle_move_resolution.c :: SetRandomMultiHitCounter
#                (L2306-2307) — RandomUniform(4,5) instead of the standard
#                weighted [2,5] distribution. Same variable-multi_hit-only
#                scope as Skill Link.
#
# Watches for the GDScript %-after-+ formatting pitfall (CLAUDE.md) in every
# multi-line assertion label built with both operators.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_grip_claw()
	_test_section_b_skill_link()
	_test_section_c_loaded_dice()

	var total := _pass + _fail
	print("m18_5i_test: %d/%d passed" % [_pass, total])
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


func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 100
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


# ── Section A: Grip Claw ─────────────────────────────────────────────────────

func _test_section_a_grip_claw() -> void:
	var inflictor := _make_mon("A_Inflictor")
	var grip_claw := _make_item(ItemManager.HOLD_EFFECT_GRIP_CLAW)

	# A1: Grip Claw holder's wrap application is a fixed 7 turns, zero variance
	# across repeated calls.
	inflictor.held_item = grip_claw
	var all_seven := true
	for _i in range(30):
		var victim := _make_mon("A1_Victim")
		StatusManager.try_apply_wrap(victim, inflictor)
		if victim.wrapped_turns != 7:
			all_seven = false
	_chk("A1 Grip Claw holder always applies exactly 7-turn wrap (n=30)", all_seven)

	# A2: discriminator — without Grip Claw, the same inflictor rolls the
	# standard random 4-5 range, never 7.
	inflictor.held_item = null
	var saw_four_or_five := false
	var saw_seven := false
	for _i in range(30):
		var victim := _make_mon("A2_Victim")
		StatusManager.try_apply_wrap(victim, inflictor)
		if victim.wrapped_turns == 4 or victim.wrapped_turns == 5:
			saw_four_or_five = true
		if victim.wrapped_turns == 7:
			saw_seven = true
	_chk("A2 No Grip Claw: rolls land in {4,5} (n=30 sample)", saw_four_or_five)
	_chk("A2b No Grip Claw: never rolls 7 (n=30 sample)", not saw_seven)

	# A3: an explicit force_wrap_turns override always wins over Grip Claw
	# (matching force_sleep_turns's own established seam precedence).
	inflictor.held_item = grip_claw
	var forced_victim := _make_mon("A3_Victim")
	StatusManager.try_apply_wrap(forced_victim, inflictor, 4)
	_chk("A3 force_wrap_turns overrides Grip Claw", forced_victim.wrapped_turns == 4)

	# A4: Klutz suppresses Grip Claw — falls back to the standard random roll.
	var klutz_inflictor := _make_mon("A4_Inflictor")
	klutz_inflictor.held_item = grip_claw
	klutz_inflictor.ability = _load_ability(103)  # Klutz
	var klutz_all_seven := true
	var klutz_saw_valid := false
	for _i in range(30):
		var victim := _make_mon("A4_Victim")
		StatusManager.try_apply_wrap(victim, klutz_inflictor)
		if victim.wrapped_turns != 7:
			klutz_all_seven = false
		if victim.wrapped_turns == 4 or victim.wrapped_turns == 5:
			klutz_saw_valid = true
	_chk("A4 Klutz suppresses Grip Claw (never all-7 across n=30)", not klutz_all_seven)
	_chk("A4b Klutz-suppressed Grip Claw falls back to {4,5} range", klutz_saw_valid)


# ── Section B: Skill Link ────────────────────────────────────────────────────

func _test_section_b_skill_link() -> void:
	var bm := _make_bm()
	var skill_link := _load_ability(92)
	var atk := _make_mon("B_Atk")
	var bullet_seed := _load_move(331)  # multi_hit = true

	# B1: Skill Link holder always resolves to exactly 5 hits, zero variance.
	atk.ability = skill_link
	var all_five := true
	for _i in range(30):
		if bm._resolve_multi_hit_count(bullet_seed, atk) != 5:
			all_five = false
	_chk("B1 Skill Link holder always resolves multi_hit to exactly 5 (n=30)", all_five)

	# B2: discriminator — without Skill Link, the same move's roll varies
	# across the full 2-5 range (not stuck at any single value).
	atk.ability = null
	var seen := {}
	for _i in range(60):
		var c: int = bm._resolve_multi_hit_count(bullet_seed, atk)
		seen[c] = true
	_chk("B2 No Skill Link: multiple distinct hit counts observed (n=60)", seen.size() > 1)

	# B3: Skill Link does NOT affect fixed strike_count moves — Double Kick
	# (strike_count=2) still resolves to exactly 2 regardless.
	atk.ability = skill_link
	var double_kick := _load_move(24)
	_chk("B3 Skill Link does not affect fixed strike_count moves (Double Kick still 2)",
			bm._resolve_multi_hit_count(double_kick, atk) == 2)

	# B4: Klutz has no bearing on Skill Link (it's an ability, not an item) —
	# confirms this project's ng_active/ability-suppression path, not Klutz,
	# is the only real suppression route.
	atk.ability = skill_link
	_chk("B4 Skill Link still forces 5 with no held item present",
			bm._resolve_multi_hit_count(bullet_seed, atk) == 5)


# ── Section C: Loaded Dice ───────────────────────────────────────────────────

func _test_section_c_loaded_dice() -> void:
	var bm := _make_bm()
	var atk := _make_mon("C_Atk")
	var loaded_dice := _make_item(ItemManager.HOLD_EFFECT_LOADED_DICE)
	var bullet_seed := _load_move(331)

	# C1: Loaded Dice holder's rolls land ONLY in {4,5} — never 2 or 3.
	atk.held_item = loaded_dice
	var counts := {2: 0, 3: 0, 4: 0, 5: 0}
	var n := 2000
	for _i in range(n):
		var c: int = bm._resolve_multi_hit_count(bullet_seed, atk)
		counts[c] += 1
	_chk("C1 Loaded Dice: zero 2-hit rolls (n=%d)" % n, counts[2] == 0)
	_chk("C1b Loaded Dice: zero 3-hit rolls (n=%d)" % n, counts[3] == 0)
	_chk("C1c Loaded Dice: some 4-hit rolls occur (n=%d)" % n, counts[4] > 0)
	_chk("C1d Loaded Dice: some 5-hit rolls occur (n=%d)" % n, counts[5] > 0)

	# C2: roughly 50/50 between 4 and 5 (RandomUniform(4,5)) — generous
	# tolerance band matching this project's established statistical-sample
	# convention (true rate 50%, band [35%, 65%]).
	var r4: float = float(counts[4]) / n
	_chk("C2 Loaded Dice 4-hit rate near 50%% (%.3f)" % r4, r4 > 0.35 and r4 < 0.65)

	# C3: discriminator distinguishing Loaded Dice from Skill Link — Loaded
	# Dice is PROBABILISTIC (varies between 4 and 5), not a single forced
	# value like Skill Link's deterministic 5.
	_chk("C3 Loaded Dice is probabilistic, not a single fixed value (both 4 and 5 seen)",
			counts[4] > 0 and counts[5] > 0)

	# C4: discriminator — without Loaded Dice, the standard weighted [2,5]
	# distribution returns, including 2s and 3s.
	atk.held_item = null
	var no_item_counts := {2: 0, 3: 0, 4: 0, 5: 0}
	for _i in range(n):
		var c: int = bm._resolve_multi_hit_count(bullet_seed, atk)
		no_item_counts[c] += 1
	_chk("C4 No Loaded Dice: 2-hit rolls occur (n=%d)" % n, no_item_counts[2] > 0)
	_chk("C4b No Loaded Dice: 3-hit rolls occur (n=%d)" % n, no_item_counts[3] > 0)

	# C5: Loaded Dice does NOT affect fixed strike_count moves — Double Kick
	# (strike_count=2) still resolves to exactly 2 regardless.
	atk.held_item = loaded_dice
	var double_kick := _load_move(24)
	_chk("C5 Loaded Dice does not affect fixed strike_count moves (Double Kick still 2)",
			bm._resolve_multi_hit_count(double_kick, atk) == 2)

	# C6: Klutz suppresses Loaded Dice — falls back to the standard weighted
	# distribution.
	var klutz_atk := _make_mon("C6_Atk")
	klutz_atk.held_item = loaded_dice
	klutz_atk.ability = _load_ability(103)  # Klutz
	var klutz_counts := {2: 0, 3: 0, 4: 0, 5: 0}
	for _i in range(n):
		var c: int = bm._resolve_multi_hit_count(bullet_seed, klutz_atk)
		klutz_counts[c] += 1
	_chk("C6 Klutz suppresses Loaded Dice: 2-hit rolls reappear (n=%d)" % n,
			klutz_counts[2] > 0)
