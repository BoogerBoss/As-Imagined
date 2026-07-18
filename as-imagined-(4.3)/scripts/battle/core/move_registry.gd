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
