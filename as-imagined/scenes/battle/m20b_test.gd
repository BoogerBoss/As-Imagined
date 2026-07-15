extends Node

# [M20b] Level-up trigger + stat recalculation + move-learning — the last
# major piece of M20's original scope. Builds on M20's pure current_exp
# accumulator (no trigger before this) and M20a's real per-species
# exp_yield/ev_yield_* data.
#
# Full source citations live in docs/decisions.md's `[M20b]` entry and
# docs/m20_recon.md's M20b section — not repeated here in full, only the
# load-bearing facts this suite exists to prove:
#  - Level derivation is a fresh re-scan of the growth-rate curve every
#    time (mirrors source's real GetLevelFromMonExp, pokemon.c:1466-1476),
#    NOT an increment-and-check-once loop — a single Exp award crossing
#    several level thresholds at once must land on the correct final level
#    in one pass.
#  - HP delta on level-up is a flat ADDITIVE increase to current_hp equal
#    to however much max_hp just went up (CalculateMonStats,
#    pokemon.c:1429-1448) — NOT a proportional heal, NOT a full heal, NOT
#    left untouched.
#  - Move-learning mirrors source's 3-way MonTryLearningNewMove branch
#    (Cmd_handlelearnnewmove, battle_script_commands.c:5553-5615):
#    already-known -> no-op; <4 moves -> auto-learn; 4 moves known ->
#    auto-skip UNLESS `_force_move_replacement_slot` is set (this
#    project's M23 UI doesn't exist yet, so this seam is wired now rather
#    than deferred).
#  - Growth rate and learnset are read FRESH from PokemonRegistry by the
#    recipient's CURRENT species.national_dex_num every single level
#    crossed — no caching anywhere — so a future evolution mechanic (M26)
#    needs no rework here.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_single_level_up()
	_test_multi_level_up_in_one_award()
	_test_hp_delta_math()
	_test_no_level_up_negative_control()
	_test_multi_move_per_level()
	_test_auto_learn_under_four_moves()
	_test_already_known_move_skip()
	_test_four_moves_known_skip()
	_test_four_moves_known_forced_replacement()
	_test_evolution_interaction_safety()
	_test_full_battle_integration()

	var total := _pass + _fail
	print("m20b_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Real dex-backed species (growth_rate + learnset only resolve correctly
# for a species PokemonRegistry actually knows about) — unlike
# m20_exp_test.gd's own `_species_from_registry`, this ALSO sets
# national_dex_num, since _check_level_up reads that field directly.
func _species_from_registry(dex: int) -> PokemonSpecies:
	var data: Dictionary = PokemonRegistry.get_species(dex)
	var sp := PokemonSpecies.new()
	sp.species_name = data.get("name", "")
	sp.national_dex_num = dex
	sp.base_hp         = data.get("base_hp", 1)
	sp.base_attack     = data.get("base_atk", 1)
	sp.base_defense    = data.get("base_def", 1)
	sp.base_sp_attack  = data.get("base_spa", 1)
	sp.base_sp_defense = data.get("base_spd", 1)
	sp.base_speed      = data.get("base_spe", 1)
	sp.exp_yield = data.get("exp_yield", 0)
	return sp


# Bulbasaur (dex 1), MediumSlow growth, IVs/EVs pinned to 0 so max_hp is
# hand-computable via _hp_formula: floor((2*45+0+0)*level/100)+level+10.
func _make_bulbasaur(level: int) -> BattlePokemon:
	return BattlePokemon.from_species(_species_from_registry(1), level,
			BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_charizard(level: int) -> BattlePokemon:
	return BattlePokemon.from_species(_species_from_registry(6), level,
			BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _bulbasaur_max_hp(level: int) -> int:
	return int(floor((2.0 * 45 + 0 + 0) * level / 100.0)) + level + 10


# ── Level derivation ──────────────────────────────────────────────────────

func _test_single_level_up() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(8)
	# MediumSlow curve[9] == 419 (source-verified against data/exp_curves.json).
	mon.current_exp = 419
	var levels: Array = []
	bm.level_up.connect(func(_p, lvl): levels.append(lvl))
	bm._check_level_up(mon)
	_chk("single level-up: 8 -> 9 from exactly curve[9] Exp",
			mon.level == 9)
	_chk("single level-up: level_up signal fired exactly once, with new_level=9",
			levels == [9])


func _test_multi_level_up_in_one_award() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(8)
	# curve[8]=314 (starting threshold), curve[12]=973 (source-verified).
	# 973 crosses curve[9]=419, curve[10]=560, curve[11]=742, curve[12]=973
	# all in one jump -- a real multi-level-up-in-one-award scenario.
	mon.current_exp = 973
	var levels: Array = []
	bm.level_up.connect(func(_p, lvl): levels.append(lvl))
	bm._check_level_up(mon)
	_chk("multi level-up: 8 -> 12 in one pass (re-scan derivation, not increment-and-check-once)",
			mon.level == 12)
	_chk("multi level-up: level_up fired once per level crossed, in ascending order",
			levels == [9, 10, 11, 12])


func _test_hp_delta_math() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(8)
	var mh8 := _bulbasaur_max_hp(8)
	var mh12 := _bulbasaur_max_hp(12)
	_chk("HP-delta setup: hand-computed max_hp(8)==25, max_hp(12)==32",
			mh8 == 25 and mh12 == 32)

	# Case 1: current_hp below max before the jump -> gains exactly the
	# max_hp delta, additive (not proportional, not a full heal).
	mon.current_hp = 20
	mon.current_exp = 973  # curve[12], see _test_multi_level_up_in_one_award
	bm._check_level_up(mon)
	_chk("HP delta (below-max case): max_hp is now 32",
			mon.max_hp == 32)
	_chk("HP delta (below-max case): current_hp == 20 + (32-25) == 27 (flat additive, not proportional)",
			mon.current_hp == 27)

	# Case 2: current_hp AT max before the jump -> current_hp also lands
	# exactly at the new max (delta fully applied, clamp is a no-op here).
	var mon2 := _make_bulbasaur(8)
	mon2.current_hp = mh8
	mon2.current_exp = 973
	bm._check_level_up(mon2)
	_chk("HP delta (at-max case): current_hp lands exactly at new max_hp (32), never exceeding it",
			mon2.current_hp == 32 and mon2.max_hp == 32)


func _test_no_level_up_negative_control() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(8)
	mon.current_hp = 10
	mon.current_exp = 418  # one short of curve[9]==419
	var levels: Array = []
	var learned: Array = []
	bm.level_up.connect(func(_p, lvl): levels.append(lvl))
	bm.move_learned.connect(func(_p, _s, _m): learned.append(true))
	bm._check_level_up(mon)
	_chk("negative control: level unchanged (still 8) when Exp is one short of the next threshold",
			mon.level == 8)
	_chk("negative control: max_hp/current_hp untouched",
			mon.max_hp == _bulbasaur_max_hp(8) and mon.current_hp == 10)
	_chk("negative control: no level_up or move_learned signals fired",
			levels.is_empty() and learned.is_empty())


# ── Move-learning ─────────────────────────────────────────────────────────

func _test_multi_move_per_level() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(14)
	mon.add_move(MoveRegistry.get_move(33))  # Tackle (level 1)
	mon.add_move(MoveRegistry.get_move(45))  # Growl (level 4)
	# curve[15]==2035 (source-verified). Bulbasaur's level-15 learnset entry
	# teaches BOTH Poison Powder(77) and Sleep Powder(79) -- the real
	# "Bulbasaur-style multi-move-per-level" case.
	mon.current_exp = 2035
	var learned_ids: Array = []
	bm.move_learned.connect(func(_p, _slot, new_move: MoveData): learned_ids.append(new_move))
	bm._check_level_up(mon)
	_chk("multi-move-per-level: reached level 15",
			mon.level == 15)
	_chk("multi-move-per-level: BOTH Poison Powder and Sleep Powder learned from one level",
			mon.moves.has(MoveRegistry.get_move(77))
			and mon.moves.has(MoveRegistry.get_move(79)))
	_chk("multi-move-per-level: exactly 4 moves known now (2 starting + 2 learned)",
			mon.moves.size() == 4)
	_chk("multi-move-per-level: move_learned fired exactly twice, for the two new moves",
			learned_ids.size() == 2
			and learned_ids.has(MoveRegistry.get_move(77))
			and learned_ids.has(MoveRegistry.get_move(79)))


func _test_auto_learn_under_four_moves() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(6)
	mon.add_move(MoveRegistry.get_move(33))  # Tackle
	# curve[7]==236 (source-verified). Bulbasaur learns Leech Seed(73) at 7.
	mon.current_exp = 236
	bm._check_level_up(mon)
	_chk("auto-learn under 4 moves: Leech Seed learned into the next open slot",
			mon.moves.has(MoveRegistry.get_move(73)) and mon.moves.size() == 2)


func _test_already_known_move_skip() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(6)
	mon.add_move(MoveRegistry.get_move(73))  # already knows Leech Seed early
	mon.current_exp = 236  # curve[7], Bulbasaur's own level-7 entry is Leech Seed
	var learned: Array = []
	bm.move_learned.connect(func(_p, _s, _m): learned.append(true))
	bm._check_level_up(mon)
	_chk("already-known-move: no duplicate added, still exactly 1 move slot used",
			mon.moves.size() == 1)
	_chk("already-known-move: move_learned does NOT fire for a move already known",
			learned.is_empty())


func _test_four_moves_known_skip() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(19)
	for id in [33, 45, 73, 22]:  # Tackle/Growl/Leech Seed/Vine Whip -- 4 moves, none is Razor Leaf
		mon.add_move(MoveRegistry.get_move(id))
	# curve[20]==5460 (source-verified). Bulbasaur learns Razor Leaf(75) at 20.
	mon.current_exp = 5460
	var skipped: Array = []
	var learned: Array = []
	bm.move_learn_skipped.connect(func(_p, move: MoveData): skipped.append(move))
	bm.move_learned.connect(func(_p, _s, _m): learned.append(true))
	bm._check_level_up(mon)
	_chk("4-moves-known, no forced slot: default is auto-skip, moveset untouched",
			mon.moves.size() == 4 and not mon.moves.has(MoveRegistry.get_move(75)))
	_chk("4-moves-known, no forced slot: move_learn_skipped fires for Razor Leaf, move_learned does not",
			skipped.size() == 1 and skipped[0] == MoveRegistry.get_move(75)
			and learned.is_empty())


func _test_four_moves_known_forced_replacement() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(19)
	for id in [33, 45, 73, 22]:
		mon.add_move(MoveRegistry.get_move(id))
	mon.current_exp = 5460  # curve[20], Razor Leaf(75)
	bm._force_move_replacement_slot = 2  # overwrite the Leech Seed slot
	var learned_slots: Array = []
	bm.move_learned.connect(func(_p, slot: int, _m): learned_slots.append(slot))
	bm._check_level_up(mon)
	_chk("4-moves-known, forced slot 2: Razor Leaf overwrote slot 2 (was Leech Seed)",
			mon.moves[2] == MoveRegistry.get_move(75) and mon.moves.size() == 4)
	_chk("4-moves-known, forced slot 2: the other 3 slots are untouched",
			mon.moves[0] == MoveRegistry.get_move(33)
			and mon.moves[1] == MoveRegistry.get_move(45)
			and mon.moves[3] == MoveRegistry.get_move(22))
	_chk("4-moves-known, forced slot 2: current_pp[2] reset to Razor Leaf's own full PP",
			mon.current_pp[2] == MoveRegistry.get_move(75).pp)
	_chk("4-moves-known, forced slot 2: move_learned fired once, reporting slot 2",
			learned_slots == [2])


# ── Evolution-interaction safety ──────────────────────────────────────────
# Confirms species/learnset lookups are re-derived FRESH every call -- no
# stale cache anywhere -- by simulating what a future M26 evolution
# mechanic would do (reassign .species mid-battle) and proving the very
# next level crossed uses the NEW species' growth-rate/learnset, not any
# value carried over from the old one.

func _test_evolution_interaction_safety() -> void:
	var bm := _make_bm()
	var mon := _make_bulbasaur(19)
	mon.current_exp = 4575  # curve[19], Bulbasaur/Charizard are both MediumSlow
	bm._check_level_up(mon)
	_chk("evolution-safety setup: still level 19 (curve[19] is the AT-level-19 threshold, not enough to cross)",
			mon.level == 19)

	# Simulate a mid-battle evolution: species swapped to Charizard (dex 6),
	# same MediumSlow curve so the level-number math is unaffected, but the
	# LEARNSET is completely different (level 20 == Rage(99), not Bulbasaur's
	# own Razor Leaf(75)).
	mon.species = _species_from_registry(6)
	mon.current_exp = 5460  # curve[20]
	bm._check_level_up(mon)
	_chk("evolution-safety: reached level 20 using the NEW species' (Charizard's) growth curve",
			mon.level == 20)
	_chk("evolution-safety: learned Charizard's level-20 move (Rage), not Bulbasaur's (Razor Leaf) -- proves the learnset lookup is re-derived fresh, not cached",
			mon.moves.has(MoveRegistry.get_move(99))
			and not mon.moves.has(MoveRegistry.get_move(75)))


# ── Full-battle integration (real dispatch, not a direct _check_level_up call) ──

func _test_full_battle_integration() -> void:
	var bm := _make_bm()
	var recipient := _make_bulbasaur(8)
	recipient.current_exp = 418  # curve[9]-1, one short of leveling
	recipient.add_move(MoveRegistry.get_move(33))  # Tackle, so it can act

	var fainted := _make_bulbasaur(8)
	fainted.current_hp = 1
	fainted.add_move(MoveRegistry.get_move(33))

	var levels: Array = []
	bm.level_up.connect(func(p, lvl): if p == recipient: levels.append(lvl))

	bm._exp_participants = [[0]]
	bm._parties = [BattleParty.single(recipient), BattleParty.single(fainted)]
	bm._combatants = [recipient, fainted]
	bm._active_per_side = 1

	# B=(64*8)/5=102, A_index==C_index (equal levels) so ratio==1, +1==103.
	# 418+103==521, which crosses curve[9]==419 but not curve[10]==560 --
	# a clean single-level-up driven entirely through the real production
	# call site, not a direct hand-computed _check_level_up invocation.
	bm._award_exp_for_fainted_opponent(fainted)
	_chk("full-battle integration: recipient's current_exp is the real computed award (418+103=521)",
			recipient.current_exp == 521)
	_chk("full-battle integration: level-up fired through the REAL _award_exp_for_fainted_opponent call site",
			levels == [9])
	_chk("full-battle integration: recipient is now level 9",
			recipient.level == 9)
