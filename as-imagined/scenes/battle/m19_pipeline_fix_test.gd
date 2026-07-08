extends Node

# [M19-pipeline-fix] Data-pipeline fix test — confirms data/moves.json's two
# extraction bugs are corrected for the FULL definitive affected-move list
# (not just the 3 originally-cited moves), and that unaffected moves are
# bit-identical to before the fix. Pure data-integrity testing, matching
# [M15]'s own testing bar and [M18.5j]'s recent precedent — no battle
# mechanics touched (data/moves.json is a reference dump only; real move
# mechanics live exclusively in gen_moves.py's curated .tres files, which
# this fix does not touch).
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h's
# additionalEffects struct on every move listed below, individually
# re-derived and cross-checked during [M19-pipeline-fix]'s own Step 0 (see
# docs/decisions.md for the full source-line citations).
#
# Bug 1: stat_change_stat/amount/self were only extracted when a move's
# PRIMARY .effect is itself EFFECT_STAT_CHANGE — moves whose stat change is
# a SECONDARY effect (attached to EFFECT_HIT or another primary effect)
# were silently left at -1/0/false. 88 moves affected.
# Bug 2: secondary_chance was only extracted from a plain numeric .chance
# literal — ternary-valued .chance expressions (this project's own
# GEN_LATEST config always resolving the >= GEN_N branch) were silently
# defaulted to 0. A distinct root cause from Bug 1; 12 moves affected, 6
# overlapping with Bug 1's list and 6 independent (status-infliction moves
# with no stat-change involvement at all).

var _pass := 0
var _fail := 0

# move_id: [stat_change_stat, stat_change_amount, stat_change_self]
const STAT_FIXES := {
	51: [3, -1, false], 61: [4, -1, false], 62: [0, -1, false], 94: [3, -1, false],
	130: [1, 1, true], 132: [4, -1, false], 145: [4, -1, false], 189: [5, -1, false],
	190: [5, -1, false], 196: [4, -1, false], 211: [1, 1, true], 229: [4, 1, true],
	231: [1, -1, false], 232: [0, 1, true], 242: [1, -1, false], 247: [3, -1, false],
	249: [1, -1, false], 295: [3, -1, false], 296: [2, -1, false], 306: [1, -1, false],
	309: [0, 1, true], 315: [2, -2, true], 317: [4, -1, false], 330: [5, -1, false],
	341: [4, -1, false], 354: [2, -2, true], 359: [4, -1, true], 405: [3, -1, false],
	411: [3, -1, false], 412: [3, -1, false], 414: [3, -1, false], 426: [5, -1, false],
	429: [5, -1, false], 430: [3, -1, false], 434: [2, -2, true], 437: [2, -2, true],
	451: [2, 1, true], 465: [3, -2, false], 488: [4, 1, true], 490: [4, -1, false],
	491: [3, -2, false], 522: [2, -1, false], 523: [4, -1, false], 527: [4, -1, false],
	534: [1, -1, false], 536: [5, -1, false], 539: [5, -1, false], 549: [4, -1, false],
	552: [2, 1, true], 555: [2, -1, false], 583: [0, -1, false], 585: [2, -1, false],
	591: [1, 2, true], 595: [2, -1, false], 612: [0, 1, true], 628: [4, -1, true],
	642: [0, -1, false], 643: [1, -1, false], 651: [0, -1, false], 654: [1, -1, true],
	659: [2, -2, true], 662: [1, -1, false], 664: [1, -1, false], 676: [6, 1, true],
	706: [4, -1, false], 711: [4, 1, true], 712: [0, -1, false], 715: [3, -1, false],
	716: [1, -1, false], 717: [2, -1, false], 728: [2, 1, true], 734: [2, -1, false],
	751: [1, -1, false], 756: [1, 1, true], 759: [0, -1, false], 760: [2, 1, true],
	768: [4, 1, true], 769: [0, -1, false], 771: [1, -1, false], 774: [4, -1, false],
	783: [3, -2, false], 787: [4, -2, true], 799: [2, 1, true], 800: [4, 1, true],
	810: [4, -1, false], 811: [4, 1, true], 812: [0, -1, false], 833: [2, 1, true],
}

# move_id: corrected secondary_chance
const CHANCE_FIXES := {
	40: 30, 44: 30, 51: 10, 61: 10, 62: 10, 87: 30,
	94: 10, 124: 30, 126: 10, 132: 10, 145: 10, 305: 50,
}

# Multi-stat moves (schema cannot represent — additionalEffects sets MORE
# THAN ONE stat field at once, e.g. Ancient Power raises all 5 non-HP stats).
# These are NOT simply "-1/0/false" — the pre-existing (pre-this-session)
# extraction already had partial, single-stat data for many of them (a
# separate, older artifact of however the original data was first entered,
# unrelated to and untouched by this fix), so this table pins each one's
# REAL pre-existing value directly rather than assuming a default. What
# matters here is these values are UNCHANGED by this session's fix — the
# schema genuinely cannot represent a 2+-stat entry with a single
# stat_change_stat int, so touching them was correctly out of scope.
const MULTI_STAT_EXCLUDED := {
	74: [0, 1, true], 174: [4, -1, false], 246: [-1, 0, false], 254: [1, 1, true],
	262: [0, -2, false], 276: [-1, 0, false], 318: [-1, 0, false], 321: [0, -1, false],
	322: [1, 1, true], 339: [0, 1, true], 347: [2, 1, true], 349: [0, 1, true],
	370: [-1, 0, false], 455: [1, 1, true], 466: [-1, 0, false], 483: [2, 1, true],
	489: [0, 1, true], 504: [1, -1, true], 508: [0, 1, true], 526: [0, 1, true],
	557: [-1, 0, false], 563: [0, 1, false], 568: [0, -1, false], 575: [0, -1, false],
	599: [0, -1, false], 601: [2, 2, true], 602: [1, 1, true], 620: [-1, 0, false],
	637: [0, 1, true], 669: [0, -1, false], 694: [0, 1, true], 703: [0, 1, true],
	705: [0, 2, false], 739: [0, 1, false], 765: [0, 1, true], 766: [-1, 0, false],
	778: [0, 1, true], 786: [0, 2, false], 796: [0, 2, true], 808: [0, 1, true],
	816: [-1, 0, false],
}

# Unaffected control set — bit-identical to before this fix. Tackle has no
# additionalEffects at all; Growl/Swords Dance/Tail Whip's PRIMARY effect IS
# EFFECT_STAT_CHANGE, the one shape the pre-fix pipeline already handled.
# Growl LOWERS the opponent's Attack (self=false, target=TARGET_BOTH) — not
# a self-buff, despite superficially reading like one.
const UNAFFECTED_CONTROL := {
	33: {"stat_change_stat": -1, "stat_change_amount": 0, "stat_change_self": false, "secondary_chance": 0},   # Tackle
	45: {"stat_change_stat": 0, "stat_change_amount": -1, "stat_change_self": false, "secondary_chance": 0},   # Growl
	14: {"stat_change_stat": 0, "stat_change_amount": 2, "stat_change_self": true, "secondary_chance": 0},     # Swords Dance
	39: {"stat_change_stat": 1, "stat_change_amount": -1, "stat_change_self": false, "secondary_chance": 0},   # Tail Whip
}


func _ready() -> void:
	_test_section_a_stat_fixes()
	_test_section_b_chance_fixes()
	_test_section_c_multi_stat_excluded()
	_test_section_d_unaffected_control()

	var total := _pass + _fail
	print("m19_pipeline_fix_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Section A: the full 88-move stat_change_stat/amount/self fix list ──────

func _test_section_a_stat_fixes() -> void:
	for move_id in STAT_FIXES:
		var expected: Array = STAT_FIXES[move_id]
		var mv: Dictionary = PokemonRegistry.get_move(move_id)
		_chk("A move %d stat_change_stat == %d" % [move_id, expected[0]],
				mv.get("stat_change_stat", -99) == expected[0])
		_chk("A move %d stat_change_amount == %d" % [move_id, expected[1]],
				mv.get("stat_change_amount", -99) == expected[1])
		_chk("A move %d stat_change_self == %s" % [move_id, str(expected[2])],
				mv.get("stat_change_self", not expected[2]) == expected[2])


# ── Section B: the full 12-move secondary_chance fix list ──────────────────

func _test_section_b_chance_fixes() -> void:
	for move_id in CHANCE_FIXES:
		var expected: int = CHANCE_FIXES[move_id]
		var mv: Dictionary = PokemonRegistry.get_move(move_id)
		_chk("B move %d secondary_chance == %d" % [move_id, expected],
				mv.get("secondary_chance", -1) == expected)


# ── Section C: multi-stat moves correctly left untouched ───────────────────

func _test_section_c_multi_stat_excluded() -> void:
	for move_id in MULTI_STAT_EXCLUDED:
		var expected: Array = MULTI_STAT_EXCLUDED[move_id]
		var mv: Dictionary = PokemonRegistry.get_move(move_id)
		_chk("C move %d stat_change_stat unchanged (schema cannot represent multi-stat)" % move_id,
				mv.get("stat_change_stat", -99) == expected[0])
		_chk("C move %d stat_change_amount unchanged" % move_id,
				mv.get("stat_change_amount", -99) == expected[1])
		_chk("C move %d stat_change_self unchanged" % move_id,
				mv.get("stat_change_self", not expected[2]) == expected[2])


# ── Section D: unaffected moves bit-identical to before the fix ────────────

func _test_section_d_unaffected_control() -> void:
	for move_id in UNAFFECTED_CONTROL:
		var expected: Dictionary = UNAFFECTED_CONTROL[move_id]
		var mv: Dictionary = PokemonRegistry.get_move(move_id)
		for key in expected:
			_chk("D move %d %s unchanged" % [move_id, key],
					mv.get(key) == expected[key])
