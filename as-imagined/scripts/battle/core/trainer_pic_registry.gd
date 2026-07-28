class_name TrainerPicRegistry
extends RefCounted

# [M24a, re-keyed Step 2] Trainer portrait lookup, by upstream's own stem.
#
# **Rule B**: a portrait is referenced by the reference tree's own
# `graphics/trainers/front_pics/<stem>.png` filename stem, copied verbatim —
# "leader_roxanne", "brendan_rs", "channeler_frlg". We never re-slugify: the
# stem's entire value is direct traceability to the exact source file, and a
# naive slug of the `Pic:` string produces "rs_brendan", which is not a file.
#
# Deliberately the opposite of Rule A (trainer keys), which are OUR identifiers
# and so carry an origin suffix we add ourselves. Rule B's `_frlg` suffixes
# exist only because upstream wrote them that way. The asymmetry is a decision
# — see docs/overworld_scope.md's Rule A/B pair.
#
# This replaced `trainer_pic_id` + TrainerPicData + data/trainer_pics/: a second
# minted index carrying the same defect as trainer_id (92.5% of pic ids shift
# once the Kanto pics land, and a stale one renders the WRONG trainer rather
# than failing) plus a 93-file table whose only job was turning that int back
# into a string we already had.
#
# Lookup is a direct path build — no directory scan, no cache — matching
# MoveRegistry/ItemRegistry's own convention.

const PORTRAIT_DIR := "res://assets/sprites/trainers/portraits"

const _PLACEHOLDER_SIZE := 64
static var _placeholder: Texture2D = null


static func path_for(stem: String) -> String:
	return "%s/%s.png" % [PORTRAIT_DIR, stem]


static func has_portrait(stem: String) -> bool:
	return stem != "" and ResourceLoader.exists(path_for(stem))


## Resolve a stem to its texture.
##
## A missing stem fails LOUDLY — a warning naming both the stem and the trainer
## that asked for it, plus a visible placeholder — never a silent null. This
## matters because converting the Kanto roster creates 86 valid `_frlg` stems
## whose PNGs are not pulled yet ([M26B3-1]): exactly the "valid key, missing
## target" shape the trainer blocker had, and it deserves the same visibility
## rather than an invisibly blank portrait slot.
static func get_portrait_texture(stem: String, asked_by: String = "") -> Texture2D:
	if stem == "":
		push_warning("TrainerPicRegistry: empty pic_stem%s" % _attrib(asked_by))
		return _get_placeholder()
	var path := path_for(stem)
	if not ResourceLoader.exists(path):
		push_warning("TrainerPicRegistry: no portrait for stem '%s'%s — expected %s"
				% [stem, _attrib(asked_by), path])
		return _get_placeholder()
	return load(path) as Texture2D


static func _attrib(asked_by: String) -> String:
	return "" if asked_by == "" else " (requested by %s)" % asked_by


## Magenta with a dark border — the conventional "asset missing" signal, and
## the same colour this project's own tile-decode scripts already use for an
## unresolved palette entry.
static func _get_placeholder() -> Texture2D:
	if _placeholder != null:
		return _placeholder
	var img := Image.create(_PLACEHOLDER_SIZE, _PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	for i in range(_PLACEHOLDER_SIZE):
		for p in [Vector2i(i, 0), Vector2i(i, _PLACEHOLDER_SIZE - 1),
				Vector2i(0, i), Vector2i(_PLACEHOLDER_SIZE - 1, i)]:
			img.set_pixelv(p, Color(0.15, 0.0, 0.15, 1.0))
	_placeholder = ImageTexture.create_from_image(img)
	return _placeholder
