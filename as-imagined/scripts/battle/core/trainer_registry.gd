class_name TrainerRegistry
extends RefCounted

# [M24a] Convention-based trainer loader — mirrors MoveRegistry/ItemRegistry
# exactly (see item_registry.gd's own doc comment for the full
# path-convention-vs-preload-dict rationale, unchanged here).
#
# Trainer files live at: res://data/trainers/trainer_NNNN.tres
# where NNNN is trainer_id zero-padded to 4 digits — a STABLE id assigned by
# scripts/gen_trainer_data.py as the sorted-alphabetical index of the
# trainer's own trainer_key (e.g. "TRAINER_BRAWLY_1"), NOT raw file order in
# trainers.party. See docs/m24_recon.md section 1.6/6.4 for the full ID
# stability rationale and its one disclosed caveat (inserting a new trainer
# name could shift subsequent IDs on a future regen).
#
# 854 real trainers as of M24a (TRAINER_NONE, a blank sentinel entry, is
# deliberately excluded — see gen_trainer_data.py's own module doc comment).


static func get_trainer(id: int) -> TrainerData:
	var path := "res://data/trainers/trainer_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("TrainerRegistry: no file for trainer id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as TrainerData


# Convenience lookup by the source's own literal TRAINER_XXXX key (e.g.
# "TRAINER_BRAWLY_1") — the more natural identifier for anything that reads
# back from trainers.party's own naming, since trainer_id itself is an
# opaque, converter-assigned index. Scans the directory once and caches;
# 854 files is cheap enough not to need a persisted index file.
static var _key_to_id: Dictionary = {}
static var _key_index_built: bool = false


static func get_trainer_by_key(trainer_key: String) -> TrainerData:
	if not _key_index_built:
		_build_key_index()
	if not _key_to_id.has(trainer_key):
		push_warning("TrainerRegistry: no trainer with key %s" % trainer_key)
		return null
	return get_trainer(_key_to_id[trainer_key])


static func _build_key_index() -> void:
	_key_to_id.clear()
	var dir := DirAccess.open("res://data/trainers")
	if dir == null:
		_key_index_built = true
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			var data: TrainerData = ResourceLoader.load("res://data/trainers/" + fn) as TrainerData
			if data != null:
				_key_to_id[data.trainer_key] = data.trainer_id
		fn = dir.get_next()
	dir.list_dir_end()
	_key_index_built = true
