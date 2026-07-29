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

## Exactly how Godot writes them.
const UID_KEY := "uid=\""
const PATH_KEY := "path=\""
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

	# Read BEFORE the save overwrites them -- see _preserve_or_mint_uid().
	# BOTH artifacts need it: the .tres is a real resource other things
	# reference by uid too, and it was losing its own on every bake.
	var prior_uid := _existing_uid(scene_path)
	var prior_data_uid := _existing_uid(data_path)
	var prior_scene_ext := _existing_ext_uids(scene_path)
	var prior_data_ext := _existing_ext_uids(data_path)

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

	# §1.9 re-import guard, second half: hand edits to the SCENE.
	#
	# The cell guard above protects MapData, which records provenance per cell.
	# Entity nodes record none -- a hand-tuned sight_range or movement_type is
	# just a value in the .tscn, and a re-bake would overwrite it in silence.
	if not _forced():
		var diff := _scene_divergence(packed, scene_path, prior_uid, prior_scene_ext)
		if diff != "":
			push_warning("map_baker: %s on disk is not what this bake would "
					% map_name
					+ "produce — refusing to overwrite (use --force).\n" + diff)
			root.free()
			return false

	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("map_baker: could not write %s" % scene_path)
		return false
	_preserve_or_mint_uid(scene_path, prior_uid)
	_restore_ext_resource_uids(scene_path, prior_scene_ext)
	if ResourceSaver.save(src, data_path) != OK:
		push_error("map_baker: could not write %s" % data_path)
		return false
	_preserve_or_mint_uid(data_path, prior_data_uid)
	_restore_ext_resource_uids(data_path, prior_data_ext)

	print("  %-34s %2dx%-3d  atlas=%s" % [map_name, src.width, src.height, src.atlas])
	root.free()
	return true


## Empty when the tracked scene is exactly what this bake would write.
## Otherwise a short, readable account of what differs.
##
## DERIVED, not declared. The obvious alternative — a per-entity `authored`
## flag mirroring MapData's own per-cell provenance — is worse: `@export`
## setters fire on every scene load, so it cannot be set automatically without
## false-positiving, which leaves it manual, and a provenance flag you must
## remember to tick is one that eventually is not. Baking to scratch and
## comparing cannot drift, and it covers added nodes, deleted nodes and moved
## cells as well — not merely the fields someone thought to enumerate.
##
## Same method as scripts/check_bake_diff.py, which remains the standalone
## audit form (it can answer "is this reproducible?" across every map without
## intending to bake). Its own docstring records that nothing was wired into
## the baker; this is that wiring.
##
## THE DIFF TEXT IS THE POINT, not decoration. This check cannot tell a hand
## edit from an importer change — both make the tracked scene stop matching.
## Refusing without saying WHAT changed would make `--force` reflexive, and a
## guard everyone bypasses by habit is worse than none. `sight_range = 3`
## means someone tuned a trainer; a wall of tile data means the importer moved.
func _scene_divergence(packed: PackedScene, scene_path: String,
		prior_uid: String, prior_ext: Dictionary) -> String:
	# A map with nothing on disk has nothing to lose.
	if not FileAccess.file_exists(scene_path):
		return ""

	# Beside the real file, NOT user://: the save has to happen in the same
	# directory for ext-id preservation to behave identically. That is also why
	# _remove_scratch() runs on every exit path — a stray .bakecheck.tscn left in
	# scenes/maps/ would be picked up as a map by anything globbing *.tscn,
	# check_bake_diff.py --all included. (This comment previously claimed the
	# scratch lived in user://, contradicting both the line below it and
	# _remove_scratch()'s own docstring.)
	var scratch := scene_path.get_basename() + ".bakecheck.tscn"

	if ResourceSaver.save(packed, scratch) != OK:
		# Unverifiable is not the same as unchanged. Refuse rather than assume.
		_remove_scratch(scratch)
		return "    (could not write a scratch bake to compare against)"
	# The real save runs both of these afterwards, so the comparison has to as
	# well or every scene would look changed by its own uid handling.
	_preserve_or_mint_uid(scratch, prior_uid)
	_restore_ext_resource_uids(scratch, prior_ext)

	var on_disk := _normalised_scene_text(scene_path)
	var would_write := _normalised_scene_text(scratch)
	_remove_scratch(scratch)

	if on_disk == would_write:
		return ""
	return _first_differences(on_disk, would_write)


## Scratch files live in scenes/maps/ (the save has to happen beside the real
## file for ext-id preservation to behave identically), so leaving one behind
## would put a bogus map where check_bake_diff.py --all and anything else
## globbing *.tscn would find it. Removed on every exit path, including the
## failure ones.
static func _remove_scratch(scratch: String) -> void:
	var g := ProjectSettings.globalize_path(scratch)
	DirAccess.remove_absolute(g)
	# ResourceSaver may drop a .uid sidecar beside it.
	if FileAccess.file_exists(scratch + ".uid"):
		DirAccess.remove_absolute(g + ".uid")


## Scene text with the two per-save labels stripped.
##
## `unique_id` — regenerated on every bake, referenced by nothing. Same strip
## check_bake_diff.py makes, and the reason a byte-reproducible scene otherwise
## shows up as a 200-line diff.
##
## `[ext_resource ... id="1_7t5wp"]` and its `ExtResource("1_7t5wp")` uses —
## this one goes FURTHER than check_bake_diff.py, deliberately, because this
## comparison faces a problem that script never does.
##
## ResourceSaver PRESERVES those ids when overwriting a text scene Godot
## already knows (verified: a real `--force` bake of Route 3 left all six
## untouched) and mints fresh ones when writing a path it does not — and a
## scratch path is never a known resource, since a raw file copy does not
## register one. So the scratch bake differs from the tracked scene in six
## meaningless labels on EVERY map, which would make this guard fire always
## and therefore mean nothing.
##
## Stripping only the random suffix and keeping the ordinal prefix is what
## makes that safe: an ext_resource genuinely added, removed or repointed still
## changes either the numbering or the `path=` on that line, both of which
## survive this.
##
## check_bake_diff.py NOW USES THE SAME THREE RULES. This comment previously
## said it must NOT, on the reasoning that it compares two saves to the same
## path, where the ids are stable and a difference would be real. Measured
## 2026-07-29: false. `sub_resource` ids are assigned per ResourceSaver call in
## process order, so a guarded bake (scratch save first) and a `--force` bake
## produce different sets for a byte-identical scene — deterministic, but a
## record of how many times the saver ran rather than of anything in the map.
## Route1_Frlg had been permanently flagged for four such ids and nothing else.
## The two tools must stay in step; a rule that differed between them is exactly
## how that false positive survived.
static func _normalised_scene_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return _normalise_text(t)


## The rules themselves, split from the file read so they can be driven against
## scratch strings. The guard shipped with no automated coverage at all and is
## now the only thing standing between a re-bake and hand-edited entity data;
## a rule this easy to over-scope needs to be testable without baking anything.
static func _normalise_text(t: String) -> String:
	var uid_re := RegEx.new()
	uid_re.compile(" unique_id=\\d+")
	t = uid_re.sub(t, "", true)
	# Only the three places Godot writes a resource label: the declaration's own
	# ` id="…"`, and the two reference forms. Scoping it this tightly is what
	# makes it safe -- a broad "quoted NAME_suffix" rule could reach a real
	# property value (script_label, graphics_id, a node name), and this cannot.
	# The random suffix goes, the meaningful stem stays, so a genuinely added,
	# removed or repointed resource still shows up.
	const LABELS := [
		[" id=\"([A-Za-z0-9]+)_[a-z0-9]+\"", " id=\"$1\""],
		["ExtResource\\(\"([A-Za-z0-9]+)_[a-z0-9]+\"\\)", "ExtResource(\"$1\")"],
		["SubResource\\(\"([A-Za-z0-9]+)_[a-z0-9]+\"\\)", "SubResource(\"$1\")"],
	]
	for pair in LABELS:
		var re := RegEx.new()
		re.compile(pair[0])
		t = re.sub(t, pair[1], true)
	return t


## A few differing lines, enough to tell a tuned trainer from a moved importer.
## Deliberately capped: the full diff is what check_bake_diff.py is for.
static func _first_differences(a: String, b: String, limit: int = 4) -> String:
	var la := a.split("\n")
	var lb := b.split("\n")
	var out := PackedStringArray()
	var n: int = maxi(la.size(), lb.size())
	for i in range(n):
		var x: String = la[i] if i < la.size() else "<absent>"
		var y: String = lb[i] if i < lb.size() else "<absent>"
		if x == y:
			continue
		# Windowed on the first differing CHARACTER, not the start of the line.
		# Tile blobs and ext_resource lines are long and share a prefix, so
		# head-truncating shows two identical-looking strings and explains
		# nothing -- which is exactly how this renderer first shipped.
		var at := 0
		while at < x.length() and at < y.length() and x[at] == y[at]:
			at += 1
		var from: int = maxi(0, at - 20)
		out.append("    line %d, col %d\n      on disk:    …%s\n      bake would: …%s"
				% [i + 1, at + 1, x.substr(from, 60), y.substr(from, 60)])
		if out.size() >= limit:
			out.append("    ... (run scripts/check_bake_diff.py for the full diff)")
			break
	return "\n".join(out)


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


## Parses `uid="uid://…"` out of a `[gd_scene …]`/`[gd_resource …]` header.
static func _uid_in_header(header: String) -> String:
	if not (header.begins_with("[gd_scene") or header.begins_with("[gd_resource")):
		return ""
	return _quoted_after(header, UID_KEY)


## The quoted value following `key` (which must include its own `="`).
static func _quoted_after(line: String, key: String) -> String:
	var i := line.find(key)
	if i < 0:
		return ""
	var start := i + key.length()
	var end := line.find("\"", start)
	return line.substr(start, end - start) if end > start else ""


## `res://path -> uid://…` for every ext_resource line that carries one.
## Read BEFORE the save, like the header uid.
static func _existing_ext_uids(res_path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(res_path):
		return out
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if not line.begins_with("[ext_resource"):
			continue
		var u := _quoted_after(line, UID_KEY)
		var pth := _quoted_after(line, PATH_KEY)
		if u != "" and pth != "":
			out[pth] = u
	f.close()
	return out


## [M27B] The third and last level of the same UID class.
##
## Levels one and two were the scene header and the .tres header. This is the
## `[ext_resource …]` lines inside them: `ResourceSaver` writes them WITHOUT a
## uid, the editor writes them WITH one, so an editor-touched scene diffed
## against baker output shows permanent churn on every reference line —
## landing exactly where check_bake_diff and git review look, which is the
## same failure the unique_id normalisation exists to prevent.
##
## Deliberately RESTORE-ONLY, never mint. A uid belongs to the resource being
## POINTED AT, not to the scene doing the pointing — its owner is that
## resource's own importer or editor. Inventing one here would be this baker
## asserting an identity it has no authority over, and would write a value
## that disagrees with the real one the moment the editor touches the target.
## Restoring what was already there is the whole job; absent stays absent.
static func _restore_ext_resource_uids(res_path: String, prior: Dictionary) -> void:
	if prior.is_empty():
		return
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n")
	var touched := false
	for i in range(lines.size()):
		var line: String = lines[i]
		if not line.begins_with("[ext_resource") or line.contains(UID_KEY):
			continue
		var pth := _quoted_after(line, PATH_KEY)
		if pth == "" or not prior.has(pth):
			continue
		# Godot writes uid before path; match that so an editor re-save is a
		# no-op rather than a reordering diff.
		var at := line.find(PATH_KEY)
		lines[i] = line.substr(0, at) + "%s%s\" " % [UID_KEY, prior[pth]] + line.substr(at)
		touched = true

	if not touched:
		return
	var out := FileAccess.open(res_path, FileAccess.WRITE)
	if out == null:
		push_error("map_baker: could not rewrite ext_resource uids of %s" % res_path)
		return
	out.store_string("\n".join(lines))
	out.close()


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
	var is_header := (header.begins_with("[gd_scene")
			or header.begins_with("[gd_resource"))
	if not is_header or header.contains(UID_KEY):
		return  # not a resource header, or the saver already wrote one

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
