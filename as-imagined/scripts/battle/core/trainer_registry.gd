class_name TrainerRegistry
extends RefCounted

# [M24a, re-keyed Step 1] Convention-based trainer loader.
#
# **The filename IS the key.** A trainer lives at
# `res://data/trainers/<trainer_key>.tres`, where trainer_key is the canonical,
# origin-suffixed constant — `TRAINER_ROXANNE_1_RSE`, `TRAINER_LASS_ROBIN_FRLG`.
# The suffix rule lives in exactly one place, scripts/trainer_keys.py, and is
# applied at conversion time by every generator that emits or references a key.
#
# There is deliberately NO numeric id. The old `trainer_id` was a
# sorted-alphabetical index this project minted itself, which meant adding a
# second roster renumbered 94.6% of it — rewriting 808 files on a regen and
# silently repointing anything that had stored one. Nothing needs a number;
# anything that wants a count can count the directory.
#
# There is also deliberately no cached key index. Lookup is a direct path
# build, matching MoveRegistry/ItemRegistry's own convention — which also means
# no 854-file scan runs just because an @tool node refreshed its warnings.
#
# Bare, unsuffixed keys do NOT resolve, by design: two spellings per trainer
# would make the origin suffix optional and defeat the point of having it.

const TRAINER_DIR := "res://data/trainers"


static func _path_for(trainer_key: String) -> String:
	return "%s/%s.tres" % [TRAINER_DIR, trainer_key]


static func get_trainer_by_key(trainer_key: String) -> TrainerData:
	var path := _path_for(trainer_key)
	if not ResourceLoader.exists(path):
		push_warning("TrainerRegistry: no trainer with key %s" % trainer_key)
		return null
	return ResourceLoader.load(path) as TrainerData


## True if a trainer with this key exists. Distinct from get_trainer_by_key()
## because a MISS is an expected, meaningful answer here rather than an error —
## an imported Kanto placement legitimately references a key whose data may not
## be converted yet, and TrainerNPC needs to report that as a configuration
## warning without tripping the push_warning above.
static func has_trainer_key(trainer_key: String) -> bool:
	return ResourceLoader.exists(_path_for(trainer_key))


## Every known trainer key, sorted. A plain directory listing — the filenames
## are the keys, so nothing is parsed or loaded to produce this.
static func all_keys() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TRAINER_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			out.append(fn.trim_suffix(".tres"))
		fn = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
