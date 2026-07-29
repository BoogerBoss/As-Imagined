extends Node

## [M27B Change 1] Bake an imported map into a real .tscn + .tres pair.
##
## The scene becomes the artifact and the JSON becomes a build INPUT, so
## hand-painting is just editing the real scene rather than something the next
## `_ready()` silently overwrites (docs/overworld_scope.md §1.9).
##
## Godot owns its own serialisation here: Python emits JSON, this builds the
## node tree and lets PackedScene/ResourceSaver write it. Hand-authoring
## TileMapLayer cell data from Python would mean generating its binary
## tile_map_data blob, which is exactly the kind of format coupling worth
## avoiding.
##
## Run headless:
##   godot --headless --path <project> scenes/overworld/map_baker.tscn -- <MapName> [...]
## with no arguments it bakes PalletTown_Frlg.

const CELL := 16
const ATLAS_COLS := 32
const MAP_DIR := "res://assets/maps/"
const ATLAS_DIR := "res://assets/map_atlases/"
const OUT_DIR := "res://scenes/maps/"

## Exactly how Godot writes it into a `[gd_scene …]` header.
const UID_KEY := "uid=\""
const PLANE_NAMES := ["ground", "objects", "overhangs"]

# §1.6 routing: layer_type -> [[half, plane], ...]
const ROUTING := {
	0: [[0, 1], [1, 2]],  # NORMAL  : bottom->Objects, top->Overhangs
	1: [[0, 0], [1, 1]],  # COVERED : bottom->Ground,  top->Objects
	2: [[0, 0], [1, 2]],  # SPLIT   : bottom->Ground,  top->Overhangs
}


func _ready() -> void:
	var names: PackedStringArray = _args()
	if names.is_empty():
		names = PackedStringArray(["PalletTown_Frlg"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ok := 0
	for n in names:
		if _bake(n):
			ok += 1
	print("map_baker: %d/%d baked" % [ok, names.size()])
	get_tree().quit()


## Godot 4 routes everything after `--` to get_cmdline_USER_args();
## get_cmdline_args() never sees it. Reading the wrong one meant every bake
## silently fell through to the default and only ever produced Pallet Town —
## with a cheerful "1/1 baked" either way.
func _args() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out.append(a)
	return out


func _forced() -> bool:
	return "--force" in OS.get_cmdline_args() or "--force" in OS.get_cmdline_user_args()


func _bake(map_name: String) -> bool:
	var src := MapData.load_from(MAP_DIR + map_name + ".json")
	if src == null:
		push_error("map_baker: no imported data for %s" % map_name)
		return false

	var scene_path := OUT_DIR + map_name + ".tscn"
	var data_path := OUT_DIR + map_name + "_data.tres"

	# Read BEFORE the save overwrites it -- see _preserve_or_mint_uid().
	var prior_uid := _existing_uid(scene_path)

	# §1.9 re-import guard: never clobber hand-authored work. Per-map by
	# construction, so this is a usage check, not a merge.
	if ResourceLoader.exists(data_path) and not _forced():
		var existing: MapData = load(data_path)
		if existing != null and existing.has_authored_cells():
			push_warning("map_baker: %s has AUTHORED cells — refusing to overwrite (use --force)"
					% map_name)
			return false

	var ts := _build_tileset(src.atlas)
	if ts == null:
		return false

	var root := Node2D.new()
	root.name = map_name

	var layers: Array[TileMapLayer] = []
	for nm in ["Ground", "Objects"]:
		layers.append(_add_layer(root, nm, ts))

	# Entity strata, ordered by source's own sElevationToPriority: lower value
	# draws on top. Priority-2 entities (elevation 0/1/3/5) sit BELOW the
	# overhang plane; priority-1 entities (elevation 4) sit ABOVE it. This is
	# why the split cannot be a simple "upper vs lower" — elevation 5 returns
	# to ground priority.
	var ent_low := Node2D.new()
	ent_low.name = "Entities_P2"
	ent_low.y_sort_enabled = true
	root.add_child(ent_low)

	layers.append(_add_layer(root, "Overhangs", ts))

	var ent_high := Node2D.new()
	ent_high.name = "Entities_P1"
	ent_high.y_sort_enabled = true
	root.add_child(ent_high)

	# paint
	for i in range(src.metatile.size()):
		var mid: int = src.metatile[i]
		var cell := Vector2i(i % src.width, int(i / src.width))
		var coords := Vector2i(mid % ATLAS_COLS, int(mid / ATLAS_COLS))
		var lt: int = src.layer_type[i]
		if not ROUTING.has(lt):
			continue
		for pair in ROUTING[lt]:
			var plane: int = pair[1]
			layers[plane].set_cell(cell, plane, coords)

	_emit_events(root, map_name, ent_low, ent_high)

	# owner must be set on the WHOLE subtree, not just direct children — a node
	# without an owner is silently dropped from the packed scene, which would
	# have left every entity out while still reporting a successful bake.
	for c in root.get_children():
		_set_owner_recursive(c, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("map_baker: pack failed for %s" % map_name)
		return false
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("map_baker: could not write %s" % scene_path)
		return false
	_preserve_or_mint_uid(scene_path, prior_uid)
	if ResourceSaver.save(src, data_path) != OK:
		push_error("map_baker: could not write %s" % data_path)
		return false

	print("  %-34s %2dx%-3d  atlas=%s" % [map_name, src.width, src.height, src.atlas])
	root.free()
	return true


## The UID already on disk, or "" if the scene is new or carries none.
## Must be read BEFORE ResourceSaver.save() overwrites the file.
static func _existing_uid(scene_path: String) -> String:
	if not FileAccess.file_exists(scene_path):
		return ""
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return ""
	var header := f.get_line()
	f.close()
	return _uid_in_header(header)


## Parses `uid="uid://…"` out of a `[gd_scene …]` header line.
static func _uid_in_header(header: String) -> String:
	if not header.begins_with("[gd_scene"):
		return ""
	var i := header.find(UID_KEY)
	if i < 0:
		return ""
	var start := i + UID_KEY.length()
	var end := header.find("\"", start)
	return header.substr(start, end - start) if end > start else ""


## [M27B] Scene UIDs — preserve or mint, never re-mint.
##
## `ResourceSaver.save()` does not write a `uid=` into a scene it saves
## programmatically. The editor DOES mint one when it saves a scene itself —
## which is why PalletTown_Frlg.tscn, the one map opened by hand, already had
## one while the other seven did not. A scene with no UID is invisible to the
## editor's resource pickers, so it cannot be selected as an instanced child.
##
## **The one rule that makes this a fix rather than a new churn source: a UID
## is assigned once per map, forever.** Minting fresh each bake would change
## every scene's identity on every re-bake — the `unique_id` churn problem
## reintroduced one line higher, and worse, because a UID is a reference other
## scenes resolve against. So the existing UID is read off disk first and put
## straight back; a new one is minted only when there genuinely isn't one.
##
## A CHANGED uid is therefore a semantic diff and check_bake_diff.py must not
## normalise it away — under this rule it can only ever mean a bug.
static func _preserve_or_mint_uid(scene_path: String, prior_uid: String) -> void:
	var f := FileAccess.open(scene_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var nl := text.find("\n")
	if nl < 0:
		return
	var header := text.substr(0, nl)
	if not header.begins_with("[gd_scene") or header.contains(UID_KEY):
		return  # not a scene header, or the saver already wrote one

	var uid_text := prior_uid
	if uid_text == "":
		var id := ResourceUID.create_id()
		uid_text = ResourceUID.id_to_text(id)
		if not ResourceUID.has_id(id):
			ResourceUID.add_id(id, scene_path)

	var patched := header.trim_suffix("]") + " %s%s\"]" % [UID_KEY, uid_text]
	var out := FileAccess.open(scene_path, FileAccess.WRITE)
	if out == null:
		push_error("map_baker: could not rewrite header of %s" % scene_path)
		return
	out.store_string(patched + text.substr(nl))
	out.close()


func _set_owner_recursive(n: Node, root: Node) -> void:
	n.owner = root
	for c in n.get_children():
		_set_owner_recursive(c, root)


## Object events become real nodes (docs/overworld_scope.md §32). The importer
## already normalised source's four arrays into one `events` list, so this only
## has to route each record to its node type and container.
##
## Placement matters: npc/trainer/item_ball are DRAWN, so they go into the
## elevation-priority strata the player also moves between; warp/trigger/sign
## are not, so they sit in one flat Triggers container where draw order is
## meaningless.
func _emit_events(root: Node2D, map_name: String, ent_low: Node2D, ent_high: Node2D) -> void:
	var raw: Variant = _load_events(map_name)
	if typeof(raw) != TYPE_ARRAY:
		return

	var triggers := Node2D.new()
	triggers.name = "Triggers"
	root.add_child(triggers)

	var counts := {}
	for item in (raw as Array):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = item
		var node := _build_event_node(e)
		if node == null:
			continue
		var kind := str(e.get("kind", ""))
		# Two strata, keyed by the source's own sElevationToPriority — elevation
		# 4 draws above the overhang plane, but 5 returns to ground level.
		var parent: Node2D = triggers
		if kind in ["npc", "trainer", "item_ball"]:
			parent = ent_high if node.priority() == 1 else ent_low
		parent.add_child(node)
		counts[kind] = int(counts.get(kind, 0)) + 1

	if not counts.is_empty():
		print("    events: %s" % [counts])


func _load_events(map_name: String) -> Variant:
	var f := FileAccess.open(MAP_DIR + map_name + ".json", FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return (parsed as Dictionary).get("events", [])


func _build_event_node(e: Dictionary) -> OverworldEntity:
	var node: OverworldEntity = null
	match str(e.get("kind", "")):
		"npc":
			var n := NPC.new()
			_fill_npc(n, e)
			node = n
		"trainer":
			var t := TrainerNPC.new()
			_fill_npc(t, e)
			t.trainer_key = str(e.get("trainer_key", ""))
			t.sight_range = int(e.get("sight_range", 0))
			node = t
		"item_ball":
			var b := ItemBall.new()
			b.graphics_id = str(e.get("graphics_id", ""))
			b.local_id = str(e.get("local_id", ""))
			node = b
		"warp":
			var w := Warp.new()
			w.dest_map = str(e.get("dest_map", ""))
			w.dest_warp_id = int(str(e.get("dest_warp_id", "0")))
			node = w
		"trigger":
			var g := Trigger.new()
			g.var_name = str(e.get("var", ""))
			g.var_value = int(str(e.get("var_value", "0")))
			node = g
		"sign":
			var s := Sign.new()
			s.bg_type = str(e.get("bg_type", "sign"))
			s.facing = str(e.get("facing", ""))
			s.item = str(e.get("item", ""))
			node = s
		_:
			return null

	node.cell = Vector2i(int(e.get("x", 0)), int(e.get("y", 0)))
	node.elevation = int(e.get("elevation", 3))
	node.visibility_flag = _real_flag(str(e.get("flag", "")))
	node.script_label = str(e.get("script", ""))
	node.name = _node_name(e, node)
	return node


func _fill_npc(n: NPC, e: Dictionary) -> void:
	n.graphics_id = str(e.get("graphics_id", ""))
	n.movement_type = str(e.get("movement_type", ""))
	n.local_id = str(e.get("local_id", ""))


## Source writes a literal "0" in the flag field to mean "no flag" — carrying
## that through verbatim would make every unconditional NPC look flag-gated.
func _real_flag(flag: String) -> String:
	return "" if flag == "0" else flag


## Names are for the editor's own sake, so they lead with the kind and stay
## unique per map — Godot silently renames a collision, which would make an
## authored reference to a node break on the next re-bake.
func _node_name(e: Dictionary, node: OverworldEntity) -> String:
	var kind := str(e.get("kind", "event")).capitalize().replace(" ", "")
	if node is TrainerNPC and (node as TrainerNPC).trainer_key != "":
		kind = (node as TrainerNPC).trainer_key.trim_prefix("TRAINER_").capitalize().replace(" ", "")
	return "%s_%d_%d" % [kind, node.cell.x, node.cell.y]


func _add_layer(root: Node2D, nm: String, ts: TileSet) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.name = nm
	l.tile_set = ts
	root.add_child(l)
	return l


## One TileSet, three atlas sources, shared per tileset PAIR — 421 Kanto maps
## resolve to 60 pairs, so most maps reuse an existing atlas set.
func _build_tileset(atlas: String) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "behavior")
	ts.set_custom_data_layer_type(0, TYPE_INT)

	for sid in range(3):
		var path := "%s%s_%s.png" % [ATLAS_DIR, atlas, PLANE_NAMES[sid]]
		if not ResourceLoader.exists(path):
			push_error("map_baker: missing atlas %s" % path)
			return null
		var tex: Texture2D = load(path)
		var srcatlas := TileSetAtlasSource.new()
		srcatlas.texture = tex
		srcatlas.texture_region_size = Vector2i(CELL, CELL)
		for y in range(int(tex.get_height() / CELL)):
			for x in range(int(tex.get_width() / CELL)):
				srcatlas.create_tile(Vector2i(x, y))
		ts.add_source(srcatlas, sid)
	return ts
