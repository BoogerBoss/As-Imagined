class_name TrainerPicRegistry
extends RefCounted

# [M24a] Convention-based trainer-portrait loader — mirrors MoveRegistry/
# ItemRegistry/TrainerRegistry exactly.
#
# Deliberately a SEPARATE registry from TrainerRegistry, not a convenience
# method on it — see docs/m24_recon.md section 1.4: 854 real trainers share
# only 93 distinct Pic values (e.g. "Swimmer M" alone covers dozens of
# trainers), so trainer identity and portrait identity are two genuinely
# different id spaces, not one conflated with the other.
#
# Files live at: res://data/trainer_pics/trainer_pic_NNNN.tres
# where NNNN is pic_id zero-padded to 4 digits (sorted-alphabetical index of
# the distinct "Pic:" source string, assigned by gen_trainer_data.py).


static func get_trainer_pic(id: int) -> TrainerPicData:
	var path := "res://data/trainer_pics/trainer_pic_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("TrainerPicRegistry: no file for trainer_pic id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as TrainerPicData
