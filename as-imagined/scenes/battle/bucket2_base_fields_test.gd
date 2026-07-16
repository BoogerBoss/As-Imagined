extends Node

# [M21.5 Bucket 2] Mechanical pass + stratified spot-check on the remaining
# ~238-move roster (the moves NOT already covered by Bucket 1's full-roster
# boolean sweep or Bucket 3's full-roster secondary_effect/chance +
# stat_change_stat/amount sweep). Step 0 confirmed the ONLY genuinely
# uncovered field category for this bucket's real population is the base
# power/accuracy/pp/priority/type/category values themselves -- no prior
# session in this whole arc had ever cross-referenced these against source
# project-wide. (The originally-proposed "is_X dispatch-flag" manual
# spot-check category was confirmed NOT APPLICABLE to Bucket 2's real
# 238-move population -- a grep found exactly one is_X-shaped flag anywhere
# in the whole block, `is_spread`, which is itself a generic targeting flag
# consumed by the doubles spread loop, not a bespoke per-move mechanism.
# Every genuinely bespoke is_X move lives in a DIFFERENT section of
# gen_moves.py -- D1-D4/M19e/M19f/M19-rampage/M19-recharge/etc. -- which is
# Bucket 5's scope, not this one.)
#
# Extended Bucket 1/3's own hardened extraction script (GEN-conditional
# resolution, comment-stripping) with power/accuracy/pp/priority/type/
# category cross-referencing, catching two more real script bugs before
# trusting any result: `category` is stored in gen_moves.py as a symbolic
# PHYS/SPEC/STAT constant, not a bare int (same shape as Bucket 3's own
# SE_* constant bug); and `eval_cond` needed outer-parenthesis stripping to
# resolve ternaries like `(B_UPDATED_MOVE_DATA >= GEN_9) ? 95 : 70` (source
# wraps some but not all ternary conditions in parens).
#
# Final result across all 238 moves: 0 mismatches on accuracy/pp/priority/
# type/category, exactly 2 on power -- Luster Purge(295)/Mist Ball(296),
# both showing `power=9` where source resolves to 95 at this project's own
# GEN_LATEST=GEN_9 config (`(B_UPDATED_MOVE_DATA >= GEN_9) ? 95 : 70`). A
# real transcription typo (a dropped trailing digit), not a GEN-conditional
# resolution artifact -- confirmed by finding the IDENTICAL wrong value
# already hardcoded into m19_secondary_stat_test.gd's own expected-value
# table, meaning the test had been silently validating the wrong number
# since these moves were first implemented.
#
# A follow-up stratified manual spot-check (12 moves spanning punching/
# sleep-status/stat-lower/confusion/spread/thaw/paralysis/self-buff-on-hit
# mechanism shapes, each move's FULL moves_info.h entry read side-by-side
# with its FULL gen_moves.py entry, not just the fields already checked
# programmatically) found ZERO additional defects -- a 0% sample defect
# rate, confirming the existing programmatic coverage (this session's own
# base-field sweep, plus Bucket 1's booleans, Bucket 3's secondary-effect/
# stat-change fields, and M19.5's own already-full-roster ban_flags audit)
# is comprehensive enough that no further manual full-roster pass is
# warranted for this bucket.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_luster_purge_power()
	_test_mist_ball_power()

	var total := _pass + _fail
	print("bucket2_base_fields_test: %d/%d passed" % [_pass, total])
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


# ── Luster Purge(295): power corrected 9->95 ──────────────────────────────

func _test_luster_purge_power() -> void:
	var luster_purge := _load_move(295)
	_chk("Luster Purge(295): the REAL data now carries power=95 (was 9)",
			luster_purge.power == 95)

	var atk := _make_mon("LP_Atk")
	var def := _make_mon("LP_Def")

	# Positive: the real, now-fixed move deals real damage consistent with
	# power=95, not the old power=9.
	var real_dmg: Dictionary = DamageCalculator.calculate(atk, def, luster_purge, 100, false)

	# Negative control: a synthetic move identical in every other respect
	# but pinned at the OLD buggy power=9 deals dramatically less damage —
	# proving this fix has a real, substantial runtime consequence, not
	# just a cosmetic data change.
	var old_buggy_move := MoveData.new()
	old_buggy_move.move_name = "OldLusterPurge"
	old_buggy_move.type = TypeChart.TYPE_PSYCHIC
	old_buggy_move.category = 1
	old_buggy_move.power = 9
	old_buggy_move.accuracy = 100
	old_buggy_move.pp = 5
	var old_dmg: Dictionary = DamageCalculator.calculate(atk, def, old_buggy_move, 100, false)

	_chk("Luster Purge negative control: the fixed power=95 move deals " +
			"substantially more damage than the old buggy power=9 value would " +
			"have (real[%d] vs old[%d])" % [real_dmg["damage"], old_dmg["damage"]],
			real_dmg["damage"] > old_dmg["damage"] * 5)


# ── Mist Ball(296): power corrected 9->95 ─────────────────────────────────

func _test_mist_ball_power() -> void:
	var mist_ball := _load_move(296)
	_chk("Mist Ball(296): the REAL data now carries power=95 (was 9)",
			mist_ball.power == 95)

	var atk := _make_mon("MB_Atk")
	var def := _make_mon("MB_Def")

	var real_dmg: Dictionary = DamageCalculator.calculate(atk, def, mist_ball, 100, false)

	var old_buggy_move := MoveData.new()
	old_buggy_move.move_name = "OldMistBall"
	old_buggy_move.type = TypeChart.TYPE_PSYCHIC
	old_buggy_move.category = 1
	old_buggy_move.power = 9
	old_buggy_move.accuracy = 100
	old_buggy_move.pp = 5
	var old_dmg: Dictionary = DamageCalculator.calculate(atk, def, old_buggy_move, 100, false)

	_chk("Mist Ball negative control: the fixed power=95 move deals " +
			"substantially more damage than the old buggy power=9 value would " +
			"have (real[%d] vs old[%d])" % [real_dmg["damage"], old_dmg["damage"]],
			real_dmg["damage"] > old_dmg["damage"] * 5)
