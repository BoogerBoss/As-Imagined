@tool
extends AcceptDialog

## [M27M5c Phase 2] "Attach this map to that one," without a command line.
##
## ⚠️ **CONTAINS NO RULES.** Reciprocal direction and offset, overlap detection,
## the refusal, and the two-sided write all live in `MapAuthoring.connect_maps`
## / `would_overlap`, driven by `m27a_step_resolver_test` section BB. This is
## three inputs and a results label. Same split as `new_map_dialog.gd`,
## `name_usage_dialog.gd` and `entity_inspector.gd`, for the reason `plugin.gd`
## records: this addon has no automated coverage, so a dialog holding no rules
## is one there is nothing to test.
##
## ⚠️ **THE HOST IS THE OPEN MAP, NOT A THIRD DROPDOWN.** `connect_maps` is
## symmetric — it writes both sides — so a host picker would be a second way to
## express the same edit and an invitation to connect two maps while looking at
## a third. `_apply_offset` already makes exactly this assumption for the seam
## editor beside it; this matches it.
##
## **What this adds over `map_creator.tscn --connect`:** a refusal is SHOWN.
## `connect_maps` returns `{ok, reason, overlaps}`, so "would overlap Pewter
## City" arrives in the box with the offending maps named, and the overlay's own
## `_draw_connections` already highlights overlaps in the viewport — so the
## reason and the picture agree. On the CLI that reason scrolls past in a
## console.

## Godot's default "OK" reads as "dismiss" next to a results box, which is
## exactly wrong on the press that writes two files.
const CONNECT_TEXT := "Connect"

## Name -> `MapData.Connection`, mirroring `map_creator.gd`'s own `DIRS`. Only
## the four that stitch: DIVE/EMERGE are real in the data but warp rather than
## stitching geometry (see `MapData.Connection`), so offering them here would
## invent adjacency the chunk loader must never act on.
const DIRS := {
	"NORTH": MapData.Connection.NORTH,
	"SOUTH": MapData.Connection.SOUTH,
	"WEST": MapData.Connection.WEST,
	"EAST": MapData.Connection.EAST,
}

var _host := ""

var _host_label: Label
var _existing: OptionButton
var _remove: Button
var _guest: OptionButton
var _dir: OptionButton
var _offset: SpinBox
var _force: CheckBox
var _results: RichTextLabel

## [Phase 3] The host's current seams, parallel to `_existing`'s item list, as
## `{direction: int, guest: String}`. Held rather than re-parsed from the item
## TEXT — a label is for a human and round-tripping one back into an enum is
## how a display change becomes a wrong deletion.
var _existing_keys: Array[Dictionary] = []


func _init() -> void:
	title = "Map connections"
	min_size = Vector2i(660, 560)
	ok_button_text = CONNECT_TEXT
	# Must NOT close on Connect — a refusal is the interesting outcome and a
	# dialog that vanished would take the reason with it.
	get_ok_button().pressed.connect(_on_connect)

	var box := VBoxContainer.new()
	add_child(box)

	_host_label = Label.new()
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_host_label)

	# --- existing seams, and removing one ---------------------------------
	box.add_child(_hint("Existing connections on this map:"))
	var ex_row := HBoxContainer.new()
	_existing = OptionButton.new()
	_existing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ex_row.add_child(_existing)
	# ⚠️ Its own button rather than a second dialog: this is the same question
	# ("what does this map border?") from the other end, and splitting it would
	# mean two toolbar entries each showing half the picture. Same shape
	# `name_usage_dialog` uses for Check/Audit beside the dialog's own OK.
	_remove = Button.new()
	_remove.text = "Remove"
	_remove.tooltip_text = ("Unlink this seam on BOTH maps. The reciprocal edge "
			+ "on the other map goes too.")
	_remove.pressed.connect(_on_remove)
	ex_row.add_child(_remove)
	box.add_child(ex_row)

	box.add_child(HSeparator.new())
	box.add_child(_hint("Add a new connection:"))

	box.add_child(_hint("Direction is FROM the open map TO the one you pick. "
			+ "The reciprocal edge and offset are derived and written to the "
			+ "other map for you."))

	box.add_child(_label("Connect to"))
	_guest = OptionButton.new()
	box.add_child(_guest)

	var row := HBoxContainer.new()
	row.add_child(_label("Direction"))
	_dir = OptionButton.new()
	for k in DIRS:
		_dir.add_item(k)
	row.add_child(_dir)
	row.add_child(_label("Offset"))
	# Shifts the neighbour along the SHARED edge. Negative is legal and common —
	# 104 of the reference's 266 connections carry a nonzero offset.
	_offset = SpinBox.new()
	_offset.min_value = -400
	_offset.max_value = 400
	_offset.value = 0
	row.add_child(_offset)
	box.add_child(row)

	# ⚠️ Off by default and deliberately blunt in its label. An overlap makes
	# `chunk_owning()` first-match-wins over an UNORDERED Dictionary, so two
	# overlapping chunks answer differently run to run — a bug that reproduces
	# intermittently and points nowhere near itself.
	_force = CheckBox.new()
	_force.text = "Force — link anyway despite an overlap (intermittent bugs)"
	_force.tooltip_text = ("Overlapping chunks make chunk_owning() "
			+ "nondeterministic. Only tick this if you are deliberately "
			+ "rearranging and will fix the overlap next.")
	box.add_child(_force)

	_results = RichTextLabel.new()
	_results.bbcode_enabled = true
	_results.selection_enabled = true
	_results.custom_minimum_size = Vector2(0, 200)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _hint(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## ⚠️ Resolves the host from the OPEN SCENE every time, and re-reads the guest
## list with it. Both change without this dialog being told — `baked_maps()`
## grows whenever a map is baked, and the host changes whenever a different
## scene is opened. Anything cached at plugin start would be a lie by the second
## use.
func popup_fresh() -> void:
	_host = _open_map_name()
	_guest.clear()
	_results.text = ""

	if _host == "":
		_host_label.text = "No map open."
		_say("[color=#dd8888]Open a baked map under scenes/maps/ first — the "
				+ "open map is the one being connected.[/color]")
		_refresh_existing()
		popup_centered()
		return

	_host_label.text = "Connecting FROM:  %s" % _host
	_refresh_existing()
	for m in MapAuthoring.baked_maps(_host):
		_guest.add_item(m)
	if _guest.item_count == 0:
		_say("[color=#ddaa66]No other baked map to connect to.[/color]")

	# ⚠️ **UNSAVED SEAM EDITS ARE A REAL HAZARD HERE, NOT A TIDINESS NOTE.**
	# `connect_maps` reloads both maps through `load()`, which returns Godot's
	# CACHED resource — the very instance the overlay has been mutating — and
	# then saves it. So connecting would silently commit whatever offset nudges
	# were pending, under the guise of adding a seam. Warned rather than
	# blocked: committing them is usually what you wanted anyway, and refusing
	# outright would strand an author with no way forward from inside here.
	var ov := _open_overlay()
	if ov != null and ov.has_unsaved_edits():
		_say("[color=#ddaa66]⚠ The overlay has unsaved edits. Connecting saves "
				+ "this map's data, which will commit them too — press Save Map "
				+ "Data first if you want them separate.[/color]")
	popup_centered()


## [Phase 3] Re-read the host's own seams into the Remove picker.
##
## ⚠️ Read from the `_data.tres`, not from `placed_rects` — that walks the whole
## reachable graph and would list maps two hops out, which are real neighbours
## of SOMETHING but not edges this map can remove.
##
## ⚠️ Each entry is labelled with its DIRECTION AND destination, because
## direction alone does not identify a seam: 3 maps region-wide carry more than
## one connection on a single edge (`SixIsland_WaterPath_Frlg` has three on its
## left), so "WEST" as a label would show three identical rows.
func _refresh_existing() -> void:
	_existing.clear()
	_existing_keys.clear()
	var md := _host_data()
	if md == null:
		_remove.disabled = true
		return
	for c in md.connections:
		var d := int(c.get("direction", -1))
		if not MapAuthoring.OPPOSITE.has(d):
			# DIVE/EMERGE are real in the data but warp rather than stitch, so
			# they are not seams and `disconnect_maps` would refuse them anyway.
			continue
		var raw := str(c.get("map", ""))
		var nb := MapConstants.map_name_for(raw)
		_existing.add_item("%s → %s  (offset %d)"
				% [_dir_name(d), nb if nb != "" else raw, int(c.get("offset", 0))])
		_existing_keys.append({"direction": d, "guest": nb})
	_remove.disabled = _existing_keys.is_empty()
	if _existing_keys.is_empty():
		_existing.add_item("(none)")


func _dir_name(d: int) -> String:
	for k in DIRS:
		if DIRS[k] == d:
			return k
	return "dir %d" % d


func _host_data() -> MapData:
	if _host == "":
		return null
	var p := MapAuthoring.OUT_DIR + _host + "_data.tres"
	return load(p) as MapData if ResourceLoader.exists(p) else null


func _on_remove() -> void:
	if _existing.selected < 0 or _existing.selected >= _existing_keys.size():
		_say("[color=#dd8888]Pick a connection to remove.[/color]")
		return
	var key := _existing_keys[_existing.selected]
	var guest := str(key["guest"])
	if guest == "":
		_say("[color=#dd8888]That seam points at a constant this project cannot "
				+ "resolve to a map, so there is no other side to unlink.[/color]")
		return
	var res := MapAuthoring.disconnect_maps(_host, int(key["direction"]), guest)
	if not bool(res["ok"]):
		_say("[color=#dd8888][b]Not removed[/b] — %s[/color]" % str(res["reason"]))
		return
	var out := "[b][color=#88dd88]Removed[/color][/b]  %s %s → %s\n" \
			% [_host, _dir_name(int(key["direction"])), guest]
	# ⚠️ Says which of the two sides actually went. A drifted pair removing only
	# one side is a DIFFERENT outcome from a clean unlink, and reporting both as
	# "removed" would hide that the data had been inconsistent.
	if int(res["removed_guest"]) == 0:
		out += "[color=#ddaa66]%s[/color]\n" % str(res["reason"])
	else:
		out += "The reciprocal edge on %s went too.\n" % guest
	_say(out)
	_refresh_existing()
	_refresh_overlay()


## The open scene's map name, or "" if what is open is not a baked map. Same
## `res://scenes/maps/` convention `_on_overlay_toggled` and `MapManager` use —
## `<Map>.tscn` is the only thing that resolves a `<Map>_data.tres`.
func _open_map_name() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return ""
	var p := root.scene_file_path
	if not p.begins_with(MapAuthoring.OUT_DIR) or not p.ends_with(".tscn"):
		return ""
	return p.get_file().get_basename()


## The temp overlay on the open scene, if one is toggled on. Null is the normal
## case — connecting does not require an overlay, this is only used to notice
## pending edits.
func _open_overlay() -> MapOverlay:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for c in root.get_children():
		if c is MapOverlay:
			return c as MapOverlay
	return null


func _say(bbcode: String) -> void:
	_results.text = bbcode


func _on_connect() -> void:
	if _host == "":
		_say("[color=#dd8888]No map open.[/color]")
		return
	if _guest.selected < 0:
		_say("[color=#dd8888]Pick a map to connect to.[/color]")
		return
	var guest := _guest.get_item_text(_guest.selected)
	var dir_name := _dir.get_item_text(_dir.selected)
	var direction: int = DIRS[dir_name]
	var offset := int(_offset.value)

	var res := MapAuthoring.connect_maps(_host, direction, guest, offset,
			_force.button_pressed)

	if not bool(res["ok"]):
		var msg := "[color=#dd8888][b]Not linked[/b] — %s[/color]" \
				% str(res["reason"])
		var overlaps: Array = res["overlaps"]
		if not overlaps.is_empty():
			# The overlay draws these highlighted already, so naming them here
			# makes the reason and the picture agree.
			msg += "\n\nOverlapping: %s" % ", ".join(overlaps)
			msg += "\nTry a different offset or edge — or tick Force if you are"
			msg += " deliberately rearranging."
		_say(msg)
		return

	var out := "[b][color=#88dd88]Linked[/color][/b]  %s %s → %s (offset %d)\n" \
			% [_host, dir_name, guest, offset]
	out += "The reciprocal edge on %s was derived and written too.\n" % guest
	if _force.button_pressed and not (res["overlaps"] as Array).is_empty():
		out += "\n[color=#ddaa66]⚠ Forced over an overlap with %s — " \
				% ", ".join(res["overlaps"])
		out += "chunk ownership is now nondeterministic until that is fixed."
		out += "[/color]\n"
	out += "\nBoth _data.tres files are saved. Toggle the Overlay to see the "
	out += "seam drawn, and use connection_offset there to nudge it."
	_say(out)

	_refresh_existing()
	_refresh_overlay()


## The overlay caches placed rects and instances neighbour previews from them;
## adding or removing a seam changes both. Invalidating here is what makes the
## change appear immediately rather than after a reselect — without it a
## successful connect looks like it silently did nothing.
func _refresh_overlay() -> void:
	var ov := _open_overlay()
	if ov != null and ov.has_method("refresh_connections"):
		ov.refresh_connections()
