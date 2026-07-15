extends Node

# [M19.5 Task 3] Full-roster smoke test, Tier A (load-only) — a dedicated,
# standalone, independently-runnable artifact, deliberately NOT folded into
# any other suite, so future sessions have one direct load-integrity check
# to point to rather than "the general sweep happens to touch every move."
#
# Loops every canonical move ID 1-934 and, for each one move_status_table.md
# marks Implemented (i.e. `data/moves/move_%04d.tres` exists on disk — the
# doc's own "Implemented" classification is ITSELF derived from exactly this
# same file-existence check, gen_move_status_table.py's parse_implemented(),
# so scanning the filesystem directly is equivalent by construction and
# self-updating, no ID list to maintain as future sessions add moves), loads
# it via Godot's own `load()` and asserts non-null and genuinely a MoveData
# instance — mirroring item_registry_test.gd's own Section 1 convention of
# one assertion per catalog entry, scaled down to the single combined check
# ("loads, and is the right type") this data actually supports per move.
#
# This did NOT exist before this session. The one thing that looked like it
# — the "PokemonRegistry: smoke test passed — ... 935 moves ..." line every
# other suite prints — operates on data/moves.json via PokemonRegistry
# .get_move(), a completely separate, JSON-backed pipeline with ZERO call
# sites in real battle logic (confirmed by grep during the M19.5 recon).
# `gen_move_status_table.py` also touches every .tres file, but only via
# raw Python text parsing, never through Godot's own `load()` — it can't
# catch a script-class mismatch, a corrupt resource, or anything Godot's
# own resource loader would reject.

var _pass := 0
var _fail := 0

const MIN_ID := 1
const MAX_ID := 934


func _ready() -> void:
	_test_every_implemented_move_loads()

	var total := _pass + _fail
	print("move_smoke_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_every_implemented_move_loads() -> void:
	for id in range(MIN_ID, MAX_ID + 1):
		var path := "res://data/moves/move_%04d.tres" % id
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		_chk("Move %d loads as a valid MoveData instance" % id,
				res != null and res is MoveData)
