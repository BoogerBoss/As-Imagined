class_name MoveRegistry
extends RefCounted

# Convention-based move loader.
#
# Move files live at:  res://data/moves/move_NNNN.tres
# where NNNN is the move's canonical ID zero-padded to 4 digits, matching
# include/constants/moves.h in pokeemerald_expansion.
#
# Loader approach: path convention.  get_move(id) constructs the path from
# the ID and calls load().  No dictionary or preload table is needed — adding a
# new move is just dropping a correctly-named .tres into data/moves/.  At 20
# files this is indistinguishable from a dictionary approach; at 900 it still
# scales because load() is lazy and Godot caches loaded resources.
#
# The alternative (a preloaded dictionary constant) would embed 900 preload()
# calls at the top of this file.  That bloats startup memory and makes adding a
# move a two-step process (file + dictionary entry).  Convention-based wins.
#
# Validated at ~20 files (Milestone 4 Tier 1).  Re-evaluate if lookup latency
# becomes measurable at full scale; if so, switch to a precomputed path cache
# built at first use via DirAccess.get_files_at("res://data/moves/").


static func get_move(id: int) -> MoveData:
	var path := "res://data/moves/move_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("MoveRegistry: no file for move id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as MoveData


## [M27L L1] The id of a LOADED move, recovered from its path.
##
## ⚠️ **THE PATH IS THE ID, BY THIS FILE'S OWN CONVENTION** — `move_%04d.tres`,
## stated at the top as the whole loader design. So no reverse table is needed
## and, more importantly, none is possible to get out of step: `MoveData` carries
## no id field at all, and adding one would mean regenerating 935 `.tres` files
## to store what the filename already says.
##
## ⚠️ Returns 0 for a hand-built `MoveData.new()`, which has no `resource_path`.
## That is every move fixture in this project's battle tests — real enough to
## matter, so a caller serialising one gets 0 rather than a wrong id.
static func id_of(move: MoveData) -> int:
	if move == null or move.resource_path == "":
		return 0
	var stem := move.resource_path.get_file().get_basename()
	var digits := stem.substr(stem.rfind("_") + 1)
	return int(digits) if digits.is_valid_int() else 0
