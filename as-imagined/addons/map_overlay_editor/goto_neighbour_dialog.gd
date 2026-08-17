@tool
extends AcceptDialog

## "Open the map through that edge," without hunting 421 filenames.
##
## ⚠️ **CONTAINS NO RULES.** Which maps border this one, whether each has a
## scene to open, and how an edge is named all live in
## `MapAuthoring.neighbours_of` / `direction_name`, driven by
## `m27a_step_resolver_test` section BB. This is a list and two buttons. Same
## split as `connect_map_dialog.gd`, `new_map_dialog.gd` and
## `name_usage_dialog.gd`, for the reason `plugin.gd` records: this addon has
## no automated coverage, so a dialog holding no rules is one there is nothing
## to test.
##
## ⚠️ **WHY THIS EXISTS AT ALL: THE FILE LIST STOPPED BEING NAVIGABLE.** With
## the corridor at 32-38 maps, finding a neighbour in the FileSystem dock was
## fine. All 421 Kanto maps are baked now, so "walk east from Route 2" means
## scrolling several hundred filenames to find the one you are already looking
## at the edge of. The connection graph already knows the answer; this is that
## answer as a button.
##
## ⚠️ **UNBAKED AND BROKEN EDGES ARE SHOWN, NOT HIDDEN.** A row whose
## destination has no scene is listed and disabled with the reason, because
## "Route 4 is not baked yet" is the single most useful thing this panel can
## tell an author standing on Route 3's east edge. Silently omitting it would
## make a missing map look like a missing connection, which is a different and
## much more alarming bug.

const OPEN_TEXT := "Open"

var _host := ""

var _host_label: Label
var _list: ItemList
var _open: Button
var _results: RichTextLabel

## Parallel to `_list`'s rows: the `MapAuthoring.neighbours_of` entry each one
## came from. Held rather than parsed back out of the row TEXT — the connect
## dialog's `_existing_keys` records why a label must never be round-tripped.
var _rows: Array[Dictionary] = []


func _init() -> void:
	title = "Go to a bordering map"
	ok_button_text = "Close"
	min_size = Vector2i(460, 380)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_host_label = Label.new()
	root.add_child(_host_label)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 210)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i: int) -> void: _on_open())
	_list.item_selected.connect(func(_i: int) -> void: _refresh_open_button())
	root.add_child(_list)

	_open = Button.new()
	_open.text = OPEN_TEXT
	_open.disabled = true
	_open.pressed.connect(_on_open)
	root.add_child(_open)

	_results = RichTextLabel.new()
	_results.bbcode_enabled = true
	_results.fit_content = true
	_results.custom_minimum_size = Vector2(0, 68)
	root.add_child(_results)


func popup_fresh() -> void:
	_host = _open_map_name()
	_list.clear()
	_rows.clear()
	_results.text = ""

	if _host == "":
		_host_label.text = "No map open."
		_say("[color=#dd8888]Open a baked map under scenes/maps/ first — the "
				+ "open map is the one whose edges are listed.[/color]")
		_refresh_open_button()
		popup_centered()
		return

	_host_label.text = "Edges of:  %s" % _host
	_rows = MapAuthoring.neighbours_of(_host)
	for r in _rows:
		var dir := MapAuthoring.direction_name(int(r["direction"]))
		var label := ""
		if str(r["map"]) == "":
			label = "%-6s  ?  %s  (constant resolves to nothing)" % [
					dir, str(r["constant"])]
		elif not bool(r["openable"]):
			label = "%-6s  %s  (not baked)" % [dir, str(r["map"])]
		else:
			label = "%-6s  %s   offset %d" % [dir, str(r["map"]), int(r["offset"])]
		var idx := _list.add_item(label)
		_list.set_item_disabled(idx, not bool(r["openable"]))

	if _rows.is_empty():
		_say("[color=#ddaa66]This map has no connections at all — it is reached "
				+ "by warp only, like every interior and Viridian Forest.[/color]")

	# ⚠️ **THE SAME HAZARD THE CONNECT DIALOG WARNS ABOUT, ARRIVING FROM THE
	# OTHER SIDE.** Opening another scene discards the in-memory MapData the
	# overlay has been painting into, and the overlay's own edits live there
	# until Save Map Data is pressed. Warned rather than blocked: refusing
	# would strand an author who genuinely wants to abandon a stray nudge.
	var ov := _open_overlay()
	if ov != null and ov.has_unsaved_edits():
		_say("[color=#ddaa66]⚠ The overlay has unsaved edits on this map. "
				+ "Opening another scene DISCARDS them — press Save Map Data "
				+ "first if you meant to keep them.[/color]")

	_refresh_open_button()
	popup_centered()


func _refresh_open_button() -> void:
	var i := _selected_row()
	_open.disabled = i < 0 or not bool(_rows[i]["openable"])


func _selected_row() -> int:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return -1
	var i: int = sel[0]
	return i if i >= 0 and i < _rows.size() else -1


func _on_open() -> void:
	var i := _selected_row()
	if i < 0 or not bool(_rows[i]["openable"]):
		return
	var path := str(_rows[i]["scene_path"])
	hide()
	EditorInterface.open_scene_from_path(path)


func _say(bb: String) -> void:
	_results.text += bb + "\n"


## The open scene, when it is one of the baked maps. Mirrors
## `connect_map_dialog._open_map_name`.
func _open_map_name() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return ""
	var p := root.scene_file_path
	if not p.begins_with(MapAuthoring.OUT_DIR) or not p.ends_with(".tscn"):
		return ""
	return p.get_file().get_basename()


func _open_overlay() -> MapOverlay:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for c in root.get_children():
		if c is MapOverlay:
			return c as MapOverlay
	return null
