extends Node

# [M21.5 Bucket 3] secondary_effect/secondary_chance + stat_change_stat/amount
# full-roster sweep. Extended Bucket 1's own hardened extraction script
# (GEN-conditional resolution, comment-stripping) with two NEW capabilities
# this sweep required: full #if/#elif/#else preprocessor-branch resolution
# (generalizing the ternary-resolution technique to whole blocks, not just
# inline expressions), and structured `additionalEffects`/`STAT_CHANGE_
# EFFECT_PLUS`/`MINUS` block parsing (moveEffect + chance + stat sub-fields,
# brace-matched per CLAUDE.md's own "Stat sub-field enumeration" convention).
#
# Cross-referenced every implemented move's real secondary_effect/chance and
# stat_change_stat/amount (+ extra_stat_change_stats/amounts) against source.
# Final result, after fixing 3 real bugs IN THE EXTRACTION SCRIPT ITSELF
# along the way (symbolic SE_* constant names not resolved as ints; ternary
# expressions inside stat sub-fields like `.defense = COND ? 1 : 0` not
# evaluated; charge-turn-only STAT_PLUS blocks incorrectly compared against
# the generic field instead of being excluded as already-audited via the
# dedicated charge_turn_defense_boost/spatk_boost fields): exactly 3 real,
# confirmed discrepancies out of hundreds of moves checked — Rapid Spin(229)
# missing an entire mechanic, Buzzy Buzz(681)/Sizzly Slide(682) each off by
# one field value.
#
# Rapid Spin(229): source's own additionalEffects block (gated
# `#if B_SPEED_BUFFING_RAPID_SPIN >= GEN_8`, TRUE at this project's
# GEN_LATEST=GEN_9 config) is `MOVE_EFFECT_STAT_PLUS, .speed=1, .self=TRUE,
# .chance=100` -- a guaranteed self Speed+1 on every hit landing, entirely
# unimplemented before this session (is_rapid_spin's own dispatch only
# clears hazards). Fixed via the pre-existing [M19-secondary-stat-on-hit]
# generic damaging-move stat-change mechanism -- the exact shape Torch
# Song(799) already uses for its own guaranteed self SpAtk+1 -- zero new
# dispatch code, pure gen_moves.py data addition.
#
# Buzzy Buzz(681)/Sizzly Slide(682): both had secondary_chance=100 in
# gen_moves.py, but source omits `.chance` entirely for both (unlike
# Nuzzle(609), which explicitly sets `.chance = 100`). `MoveIsAffected
# BySheerForce` (battle_util.c L9536-9546) evaluates `(chance > 0) !=
# sheerForceOverride` -- an absent/0 chance with no override means Sheer
# Force does NOT apply, matching this project's own already-established
# "0 = guaranteed, Sheer-Force-exempt" convention (the Overheat/Draco-
# Meteor-style self-drop family). Corrected to secondary_chance=0.
# Confirmed via this project's own Sheer Force gate
# (`AbilityManager.move_power_modifier_uq412`: `id == ABILITY_SHEER_FORCE
# and move.secondary_chance > 0`) that this value genuinely gates real
# behavior -- Nuzzle (chance=100, unaffected by this fix) is used as the
# positive-control proof that the same test CAN detect a Sheer Force boost
# when one should occur, discriminating a real fix from a vacuous test.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_rapid_spin_speed_boost()
	_test_buzzy_buzz_sheer_force_exempt()
	_test_sizzly_slide_sheer_force_exempt()

	var total := _pass + _fail
	print("bucket3_secondary_sweep_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _dispatch_one_action(atk: BattlePokemon, def: BattlePokemon,
		move: MoveData) -> BattleManager:
	var bm := _make_bm()
	bm._combatants = [atk, def]
	bm._turn_order = [atk, def]
	bm._active_per_side = 1
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_targets = [1, 0]
	bm._chosen_moves = [move, null]
	bm._current_actor_index = 0
	bm._force_hit = true
	bm._phase_move_execution()
	return bm


# ── Rapid Spin(229): the newly-added guaranteed self Speed+1 ──────────────

func _test_rapid_spin_speed_boost() -> void:
	var rapid_spin := _load_move(229)
	var tackle := _load_move(33)

	var atk := _make_mon("RS_Atk")
	var def := _make_mon("RS_Def")
	var bm := _dispatch_one_action(atk, def, rapid_spin)
	_chk("Rapid Spin(229): the REAL data now raises the user's own Speed by 1 " +
			"stage on every hit", atk.stat_stages[BattlePokemon.STAGE_SPEED] == 1)
	bm.queue_free()

	# Negative control: an ordinary damaging move (no stat_change_stat set)
	# raises no stat at all.
	var atk2 := _make_mon("RS_Atk2")
	var def2 := _make_mon("RS_Def2")
	var bm2 := _dispatch_one_action(atk2, def2, tackle)
	_chk("Rapid Spin negative control: Tackle (no stat_change_stat) raises " +
			"no stat", atk2.stat_stages[BattlePokemon.STAGE_SPEED] == 0)
	bm2.queue_free()


# ── Buzzy Buzz(681)/Sizzly Slide(682): Sheer Force exemption ──────────────
# Nuzzle(609) is the positive control proving the SAME test setup correctly
# detects a Sheer Force boost when one is genuinely supposed to happen —
# without it, a test that simply found "no boost" for Buzzy Buzz could be
# vacuously passing for the wrong reason (e.g. a broken Sheer Force check).

func _test_buzzy_buzz_sheer_force_exempt() -> void:
	var sheer_force := _load_ability(125)
	var buzzy_buzz := _load_move(681)
	var nuzzle := _load_move(609)

	var holder := _make_mon("BB_Holder")
	holder.ability = sheer_force
	var target := _make_mon("BB_Target")
	var plain := _make_mon("BB_Plain")

	var bb_holder_mod: int = AbilityManager.move_power_modifier_uq412(holder, buzzy_buzz, 0)
	var bb_plain_mod: int = AbilityManager.move_power_modifier_uq412(plain, buzzy_buzz, 0)
	_chk("Buzzy Buzz(681): Sheer Force does NOT boost it (secondary_chance=0, " +
			"guaranteed & exempt, corrected from the old 100)",
			bb_holder_mod == bb_plain_mod)

	# Positive control: the SAME Sheer Force holder DOES get boosted using
	# Nuzzle (secondary_chance=100, source's own explicit chance, unaffected
	# by this session's fix) — proves the comparison itself is discriminating,
	# not just structurally incapable of detecting a boost.
	var nuzzle_holder_mod: int = AbilityManager.move_power_modifier_uq412(holder, nuzzle, 0)
	var nuzzle_plain_mod: int = AbilityManager.move_power_modifier_uq412(plain, nuzzle, 0)
	_chk("Buzzy Buzz positive control: Sheer Force DOES boost Nuzzle(609, " +
			"secondary_chance=100, unaffected by this fix) with the same setup",
			nuzzle_holder_mod > nuzzle_plain_mod)


func _test_sizzly_slide_sheer_force_exempt() -> void:
	var sheer_force := _load_ability(125)
	var sizzly_slide := _load_move(682)
	var nuzzle := _load_move(609)

	var holder := _make_mon("SS_Holder")
	holder.ability = sheer_force
	var plain := _make_mon("SS_Plain")

	var ss_holder_mod: int = AbilityManager.move_power_modifier_uq412(holder, sizzly_slide, 0)
	var ss_plain_mod: int = AbilityManager.move_power_modifier_uq412(plain, sizzly_slide, 0)
	_chk("Sizzly Slide(682): Sheer Force does NOT boost it (secondary_chance=0, " +
			"guaranteed & exempt, corrected from the old 100)",
			ss_holder_mod == ss_plain_mod)

	var nuzzle_holder_mod: int = AbilityManager.move_power_modifier_uq412(holder, nuzzle, 0)
	var nuzzle_plain_mod: int = AbilityManager.move_power_modifier_uq412(plain, nuzzle, 0)
	_chk("Sizzly Slide positive control: Sheer Force DOES boost Nuzzle(609) " +
			"with the same setup", nuzzle_holder_mod > nuzzle_plain_mod)
