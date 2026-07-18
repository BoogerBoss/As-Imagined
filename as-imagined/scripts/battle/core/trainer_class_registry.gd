class_name TrainerClassRegistry
extends RefCounted

# [M24a] Convention-based trainer-class loader — mirrors MoveRegistry/
# ItemRegistry/TrainerRegistry exactly.
#
# Files live at: res://data/trainer_classes/trainer_class_NNNN.tres
# where NNNN is trainer_class_id zero-padded to 4 digits — this ID is NOT a
# converter-assigned index; it's the real gTrainerClasses[] array index
# (equivalently, the position of TRAINER_CLASS_XXX in
# include/constants/trainers.h's own enum), reproduced exactly by
# gen_trainer_data.py so this ID never needs to be re-derived or remapped.
#
# 117 entries as of M24a (TRAINER_CLASS_COUNT in the reference source).


static func get_trainer_class(id: int) -> TrainerClassData:
	var path := "res://data/trainer_classes/trainer_class_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("TrainerClassRegistry: no file for trainer_class id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as TrainerClassData
