class_name ItemRegistry
extends RefCounted

# Convention-based item loader — mirrors MoveRegistry exactly (see that file's own
# doc comment for the full path-convention-vs-preload-dict rationale, unchanged here).
#
# Item files live at:  res://data/items/item_NNNN.tres
# where NNNN is the item's canonical ID zero-padded to 4 digits, matching
# include/constants/items.h in pokeemerald_expansion.
#
# As of this session, only the 40 items scripts/gen_items.py's ITEMS dict lists
# (M18a's Charcoal family / Incenses / Silk Scarf / Fairy Feather / Plates) have a
# .tres file — get_item() on any other ID returns null with a push_warning, same
# as MoveRegistry.get_move() on an unimplemented move ID. Every future M18 sub-tier
# must add its items to gen_items.py and regenerate rather than constructing
# ItemData inline in production code — see docs/decisions.md's item-data-
# infrastructure entry.


static func get_item(id: int) -> ItemData:
	var path := "res://data/items/item_%04d.tres" % id
	if not ResourceLoader.exists(path):
		push_warning("ItemRegistry: no file for item id %d (%s)" % [id, path])
		return null
	return ResourceLoader.load(path) as ItemData
