extends Node

# [M26E4-1] Move-description data-integrity check — the one blocking data
# gap docs/m26_e4_recon.md's own §2.2 found for the Summary screen's
# MOVES-page detail panel, closed by scripts/gen_move_descriptions.py
# bulk-extracting real move descriptions from moves_info.h and patching
# them into gen_moves.py's own MOVES dict (see that script's own header
# comment for the full extraction-methodology writeup, including two real,
# confirmed bugs found and fixed before trusting the output: a naive
# paren-matcher silently truncating ~two thirds of the 37 conditionally-
# worded descriptions at the first branch's own closing paren -- Ice Beam
# is the worked example -- and a GBA line-wrap hyphen ("a full-\nbody
# tackle.") turning into a stray "full- body" once the embedded newline was
# collapsed to a plain space).
#
# Mirrors move_smoke_test.gd's own "scan every ID move_status_table.md
# marks Implemented" convention for the roster-wide integrity pass, plus a
# handful of exact-value spot-checks and discriminating regression guards
# for each of the real extraction bugs this session found and fixed --
# written as the NEGATION (per this project's own standing testing
# discipline) so a regression of the underlying bug fails loudly rather
# than a passing count merely looking plausible.

var _pass := 0
var _fail := 0

const MIN_ID := 1
const MAX_ID := 934


func _ready() -> void:
	_test_every_implemented_move_has_a_description()
	_test_spot_check_exact_values()
	_test_hyphen_wrap_fix_no_stray_space()
	_test_binding_turns_macro_resolved()
	_test_frostbite_false_resolves_to_freeze_wording()
	_test_hail_only_resolves_to_hailstorm_wording()
	_test_no_leftover_preprocessor_or_macro_artifacts()
	_test_no_double_spaces_anywhere()

	var total := _pass + _fail
	print("move_description_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


func _all_implemented_moves() -> Array[MoveData]:
	var out: Array[MoveData] = []
	for id in range(MIN_ID, MAX_ID + 1):
		var path := "res://data/moves/move_%04d.tres" % id
		if not ResourceLoader.exists(path):
			continue
		var move := load(path) as MoveData
		if move != null:
			out.append(move)
	return out


func _test_every_implemented_move_has_a_description() -> void:
	var moves := _all_implemented_moves()
	_chk("all 717 implemented moves found on disk", moves.size() == 717)
	var missing: Array[String] = []
	for move in moves:
		if move.description.strip_edges() == "":
			missing.append(move.move_name)
	_chk("every implemented move has a non-empty description (missing: %s)" % [missing],
			missing.is_empty())


func _test_spot_check_exact_values() -> void:
	_chk("Tackle", MoveRegistry.get_move(33).description == "Charges the foe with a full-body tackle.")
	_chk("Pound", MoveRegistry.get_move(1).description == "Pounds the foe with forelegs or tail.")
	_chk("Disable", MoveRegistry.get_move(50).description == "For 4 turns, prevents foe from using last used move.")
	_chk("Hidden Power", MoveRegistry.get_move(237).description == "The type varies with the user.")
	_chk("Teleport", MoveRegistry.get_move(100).description == "Switches the user out last. Flees when used by wild {PKMN}.")
	_chk("Razor Wind", MoveRegistry.get_move(13).description == "A 2-turn move with a high critical-hit ratio.")


func _test_hyphen_wrap_fix_no_stray_space() -> void:
	# [Real bug found via a bulk scan, not anticipated up front] 7 real
	# moves' own GBA text wraps mid-hyphenated-word; a naive `\n`->" "
	# collapse left a stray space after the hyphen ("full- body").
	var tackle := MoveRegistry.get_move(33).description
	_chk("Tackle reads 'full-body', not 'full- body'", tackle.contains("full-body") and not tackle.contains("full- body"))
	var bullet_punch := MoveRegistry.get_move(418).description
	_chk("Bullet Punch has no stray hyphen-space artifact", not bullet_punch.contains("bul- let"))
	var headbutt := MoveRegistry.get_move(29).description
	_chk("Headbutt has no stray hyphen-space artifact", not headbutt.contains("head- butt"))


func _test_binding_turns_macro_resolved() -> void:
	# Wrap/Bind/Fire Spin/Clamp/etc. embed a bare BINDING_TURNS macro
	# token between two quoted fragments -- confirms it resolved to real
	# text ("4 or 5", matching this project's own already-shipped binding-
	# move duration roll, [M18.5f]) rather than being silently dropped.
	_chk("Wrap resolves the BINDING_TURNS macro to '4 or 5'",
			MoveRegistry.get_move(35).description == "Wraps and squeezes the foe 4 or 5 times with vines, etc.")
	_chk("Bind resolves the BINDING_TURNS macro too",
			MoveRegistry.get_move(20).description.contains("4 or 5 turns"))


func _test_frostbite_false_resolves_to_freeze_wording() -> void:
	# B_USE_FROSTBITE is FALSE in the real reference config, and this
	# project models Freeze only (no STATUS_FROSTBITE anywhere) -- every
	# Frostbite-gated description must resolve to its real #else ("may
	# freeze"/"freezing") wording, not the #if ("frostbite") branch.
	var ice_beam := MoveRegistry.get_move(58).description
	_chk("Ice Beam resolves to the real (non-Frostbite) #else branch",
			ice_beam.contains("freeze") and not ice_beam.contains("frostbite"))
	var ice_punch := MoveRegistry.get_move(8).description
	_chk("Ice Punch resolves to the real (non-Frostbite) #else branch",
			not ice_punch.contains("frostbite"))
	var freeze_dry := MoveRegistry.get_move(573).description
	_chk("Freeze-Dry resolves to the real (non-Frostbite) #else branch",
			freeze_dry.contains("freezing") and not freeze_dry.contains("frostbite"))


func _test_hail_only_resolves_to_hailstorm_wording() -> void:
	# [D2 batch]'s own already-decided Hail-only design (B_PREFERRED_ICE_
	# WEATHER defaults to B_ICE_WEATHER_BOTH in the real reference config)
	# must resolve Hail's own description to its real hailstorm wording,
	# not a snowstorm one.
	var hail := MoveRegistry.get_move(258).description
	_chk("Hail resolves to its real hailstorm wording",
			hail.contains("hailstorm") and not hail.contains("snowstorm"))


func _test_no_leftover_preprocessor_or_macro_artifacts() -> void:
	var moves := _all_implemented_moves()
	var bad: Array[String] = []
	for move in moves:
		var d := move.description
		if d.contains("#if") or d.contains("#else") or d.contains("#endif") \
				or d.contains("COMPOUND_STRING") or d.contains("B_UPDATED") \
				or d.contains("B_USE_FROSTBITE"):
			bad.append(move.move_name)
	_chk("no description contains a leftover preprocessor/macro artifact (found: %s)" % [bad],
			bad.is_empty())


func _test_no_double_spaces_anywhere() -> void:
	var moves := _all_implemented_moves()
	var bad: Array[String] = []
	for move in moves:
		if move.description.contains("  "):
			bad.append(move.move_name)
	_chk("no description contains a double space (found: %s)" % [bad], bad.is_empty())
