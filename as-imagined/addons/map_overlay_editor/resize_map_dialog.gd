@tool
extends AcceptDialog

## [M27M5c Phase 4] "Make this map bigger," without a command line.
##
## ⚠️ **CONTAINS NO RULES.** The re-layout, the edge replication, the entity
## move, the reference size ceiling, the overlap refusal and the seam correction
## all live in `MapResize`, driven headlessly by `m27a_step_resolver_test`
## section BH. This is four spinboxes, a budget readout and a results label —
## the same split as `new_map_dialog.gd` and `connect_map_dialog.gd`, for the
## reason `plugin.gd` records: this addon is the project's one surface with no
## automated coverage and has already shipped three defects, so a dialog holding
## no rules is one there is nothing to test.
##
## ⚠️ **FOUR EDGE DELTAS, NOT A WIDTH AND A HEIGHT.** A size box would have to
## ask where the existing map goes inside the new one, and that offset is a
## number a human can get wrong — an offset of (3, 0) against a width that grew
## by 1 is silently a trim on the right by someone who meant a grow on the left.
## Each spinbox here names one edge, so no two inputs can contradict each other
## and the offset is derived rather than entered. Porymap's own Change Dimensions
## is a drag-rectangle with the same expressive range; a viewport drag can be
## added later as a second front-end onto the identical `MapResize.plan` call.

## Godot's default "OK" reads as "dismiss" next to a results box, which is
## exactly wrong on the press that rewrites a map.
const RESIZE_TEXT := "Resize"

## Set by `plugin.gd`: takes (overlay, pre, post, removed_nodes) and puts the
## edit in the editor's undo history.
##
## ⚠️ A dialog cannot reach `EditorPlugin.get_undo_redo()`, and mutating a
## resource outside the undo manager does not merely leave Ctrl+Z doing nothing
## — the history is still live, so the keystroke undoes some UNRELATED earlier
## action while the resize stays applied. Silently wrong is worse than
## unavailable, so this stays a hard dependency rather than a fallback.
var commit: Callable = Callable()

var _map := ""

var _map_label: Label
var _north: SpinBox
var _south: SpinBox
var _west: SpinBox
var _east: SpinBox
var _realign: CheckBox
var _force: CheckBox
var _preview: RichTextLabel
var _results: RichTextLabel


func _init() -> void:
	title = "Resize map"
	min_size = Vector2i(700, 620)
	ok_button_text = RESIZE_TEXT
	# Must NOT close on Resize — a refusal (over the size ceiling, would overlap
	# Pewter City) is the interesting outcome, and a dialog that vanished would
	# take the reason with it.
	get_ok_button().pressed.connect(_on_resize)

	var box := VBoxContainer.new()
	add_child(box)

	_map_label = Label.new()
	_map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_map_label)

	box.add_child(_hint("How much to add or remove on each edge. Positive grows, "
			+ "negative trims. The new size and where the existing map lands are "
			+ "worked out from these — there is no offset to enter."))

	# Laid out as a compass rather than a list, because the inputs ARE
	# directional and a vertical N/S/W/E column makes the author translate
	# "extend upward" into "the first row of four".
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_child(Control.new())
	grid.add_child(_edge_cell("North", "_north"))
	grid.add_child(Control.new())
	grid.add_child(_edge_cell("West", "_west"))
	grid.add_child(Control.new())
	grid.add_child(_edge_cell("East", "_east"))
	grid.add_child(Control.new())
	grid.add_child(_edge_cell("South", "_south"))
	grid.add_child(Control.new())
	box.add_child(grid)

	# Live, because the reference's ceiling is a PRODUCT of the two dimensions
	# and is genuinely close — Diglett's Cave B1F already sits at 92% of it. A
	# budget you can only discover by being refused is one you cannot steer away
	# from.
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.custom_minimum_size = Vector2(0, 90)
	box.add_child(_preview)

	box.add_child(HSeparator.new())

	# ⚠️ ON by default, and the label says what it costs. Growing north or west
	# slides every seam this map has (57.6% of this project's connections carry
	# a nonzero offset), so the default has to be the correct one; the opt-out
	# exists because the write to the OTHER maps is the one thing here Ctrl+Z
	# cannot take back.
	_realign = CheckBox.new()
	_realign.text = "Keep neighbours lined up (writes their .tres now — not undoable)"
	_realign.button_pressed = true
	_realign.tooltip_text = ("Growing north or west moves this map's existing "
			+ "content, so every connection offset has to move with it. This "
			+ "map's own side rides along with Save Map Data; the other maps "
			+ "are written immediately, and each one is named below.")
	box.add_child(_realign)

	# Off by default and deliberately blunt, matching the connect dialog's own
	# force box: an overlap makes `chunk_owning()` first-match-wins over an
	# unordered Dictionary, so it reproduces intermittently and points nowhere
	# near itself.
	_force = CheckBox.new()
	_force.text = "Resize anyway if it would overlap another map"
	_force.tooltip_text = ("Two chunks occupying one cell resolve differently "
			+ "run to run. Only tick this if you are about to move the other "
			+ "map too.")
	box.add_child(_force)

	_results = RichTextLabel.new()
	_results.bbcode_enabled = true
	_results.selection_enabled = true
	_results.custom_minimum_size = Vector2(0, 190)
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_results)


func _edge_cell(text: String, field: String) -> Control:
	var col := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var s := SpinBox.new()
	s.min_value = -400
	s.max_value = 400
	s.value = 0
	s.value_changed.connect(func(_v: float) -> void: _refresh_preview())
	col.add_child(s)
	set(field, s)
	return col


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _hint(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func popup_fresh() -> void:
	_map = _open_map_name()
	_results.text = ""
	_north.value = 0
	_south.value = 0
	_west.value = 0
	_east.value = 0

	if _map == "":
		_map_label.text = "No map open."
		_say("[color=#dd8888]Open a baked map under scenes/maps/ first — the "
				+ "open map is the one being resized.[/color]")
		_refresh_preview()
		popup_centered()
		return

	# ⚠️ **THE OVERLAY IS REQUIRED, NOT PREFERRED.** A resize changes memory and
	# nothing else; the only path to disk in this addon is the overlay's own
	# Save Map Data button, and the only place the unsaved-edits banner lives is
	# the overlay. Resizing without one would leave an edit nobody could save
	# and nothing on screen saying so.
	var ov := _open_overlay()
	if ov == null:
		_map_label.text = "Resizing:  %s" % _map
		_say("[color=#ddaa66]Toggle [b]Overlay[/b] on first. The resize edits "
				+ "memory, and Save Map Data on the overlay is the only thing "
				+ "that writes it.[/color]")
	else:
		_map_label.text = "Resizing:  %s   (%dx%d)" % [_map,
				ov.map_data.width, ov.map_data.height] if ov.map_data != null \
				else "Resizing:  %s" % _map
	_refresh_preview()
	popup_centered()


## What the current deltas would do, recomputed on every keystroke. Pure — it
## presses `MapResize.plan`, which writes nothing, for the reason that function
## records: a guard living inside the write cannot be shown without performing
## the write.
func _refresh_preview() -> void:
	var ov := _open_overlay()
	if ov == null or ov.map_data == null:
		_preview.text = ""
		return
	var p := MapResize.plan(ov.map_data, int(_north.value), int(_south.value),
			int(_west.value), int(_east.value))
	var size: Vector2i = p["size"]
	if not bool(p["ok"]):
		_preview.text = "[color=#ddaa66]%s[/color]" % str(p["reason"])
		return
	var words := MapResize.data_words(size)
	var pct := int(round(100.0 * words / MapResize.MAX_MAP_DATA_SIZE))
	var old_size: Vector2i = p["old_size"]
	var off: Vector2i = p["offset"]
	var text := "[b]%dx%d → %dx%d[/b]   existing map lands at (%d, %d)\n" \
			% [old_size.x, old_size.y, size.x, size.y, off.x, off.y]
	text += "%d cell(s) added, %d trimmed\n" % [int(p["added"]), int(p["trimmed"])]
	# Named as the reference's own budget rather than a bare number, so a
	# refusal at the ceiling reads as the game's limit and not this tool's.
	text += "map data: %d / %d words (%d%%)" % [words,
			MapResize.MAX_MAP_DATA_SIZE, pct]
	if int(p["trimmed"]) > 0:
		text += "\n[color=#ddaa66]⚠ trimming discards those cells, and any "
		text += "entity standing on them.[/color]"
	_preview.text = text


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


func _say(bbcode: String) -> void:
	_results.text = bbcode


func _on_resize() -> void:
	if _map == "":
		_say("[color=#dd8888]No map open.[/color]")
		return
	var ov := _open_overlay()
	if ov == null or ov.map_data == null:
		_say("[color=#dd8888]Toggle [b]Overlay[/b] on first — there is no live "
				+ "MapData to resize, and nowhere to save one.[/color]")
		return
	if not commit.is_valid():
		_say("[color=#dd8888]No undo hook — the plugin did not wire this dialog "
				+ "up. Refusing rather than editing outside the undo history."
				+ "[/color]")
		return

	var md: MapData = ov.map_data
	var root := ov.entity_root() as Node2D
	var p := MapResize.plan(md, int(_north.value), int(_south.value),
			int(_west.value), int(_east.value))
	if not bool(p["ok"]):
		_say("[color=#dd8888]%s[/color]" % str(p["reason"]))
		return

	var realign := _realign.button_pressed
	var overlaps := MapResize.overlaps_after(_map, md, p, realign)
	if not overlaps.is_empty() and not _force.button_pressed:
		_say(("[color=#dd8888]Refused — this would overlap %s.[/color]\n"
				+ "Two chunks on one cell resolve differently run to run. Move "
				+ "that map first, or tick the override.")
				% ", ".join(overlaps))
		return

	var pre := MapResize.snapshot(md, root)

	# The neighbours FIRST, while `md.connections` still holds the pre-resize
	# offsets this correction is derived from.
	var neighbours := {}
	if realign:
		neighbours = MapResize.realign_neighbours(_map, md, p)

	MapResize.resize_data(md, p)
	var report := MapResize.resize_scene(root, md, p)
	if realign:
		md.connections.assign(MapResize.realigned_connections(md.connections, p))

	var post := MapResize.snapshot(md, root)
	commit.call(ov, pre, post, report["removed"])

	# ⚠️ **WRITES THE .tres ITSELF, DELIBERATELY BREAKING THIS ADDON'S "WRITES
	# HAPPEN ONLY ON EXPLICIT BUTTONS" RULE — Rob's call, 2026-08-13, after the
	# defect that rule caused.**
	#
	# That rule is right for painting, which touches ONE artifact: forget to
	# save and you have simply not saved. A resize touches TWO — the scene and
	# the `_data.tres` — persisted by two different gestures, and saving only
	# the scene writes shifted tiles and entities against unshifted collision.
	# Measured on the first real drive: Pallet Town's picture and its movement
	# rules ended up four rows out of register, the map still loaded, and
	# nothing anywhere said so.
	#
	# So the half that has no other way to reach disk goes now. The scene is
	# still yours to save, but a scene saved alone can no longer misalign
	# anything, because the data it would misalign against is already correct.
	var save_err := ov.save_map_data()

	_say(_report(p, report, overlaps, neighbours, save_err))
	_refresh_preview()


## Everything that happened, in the order it matters. The removed entities and
## the disk writes lead, because those are the two things this tool does that an
## author cannot see by looking at the map.
func _report(p: Dictionary, report: Dictionary, overlaps: Array,
		neighbours: Dictionary, save_err: Error) -> String:
	var out := "[b][color=#88dd88]Resized %s[/color][/b]\n" % _map
	out += MapResize.describe(p, report) + "\n"

	var removed: Array = report["removed"]
	if not removed.is_empty():
		var names := PackedStringArray()
		for n in removed:
			names.append(String(n.name))
		out += ("\n[color=#dd8888]⚠ %d entit(ies) fell outside and were "
				+ "removed:[/color] %s") % [removed.size(), ", ".join(names)]
		# ⚠️ Said explicitly, because it is the one consequence that lands in
		# ANOTHER map. `warp_arrival` matches on the stored `warp_id` VALUE, so
		# nothing gets misrouted — an inbound warp simply finds nothing.
		out += ("\n   Ctrl+Z puts them back. If any was a Warp, arrivals aimed "
				+ "at it from other maps now resolve to nothing.")

	if int(report["unroutable"]) > 0:
		out += ("\n[color=#ddaa66]⚠ %d new cell(s) got a metatile this tileset "
				+ "pair has no routing for and were left unpainted.[/color]") \
				% int(report["unroutable"])

	if not neighbours.is_empty():
		var written: Array = neighbours.get("written", [])
		var missing: Array = neighbours.get("missing", [])
		if not written.is_empty():
			out += "\n\n[b]Written to disk now[/b] (not undoable): %s" \
					% ", ".join(written)
		if not missing.is_empty():
			out += ("\n[color=#ddaa66]⚠ no reciprocal edge found on %s — those "
					+ "seams had already drifted and were left alone.[/color]") \
					% ", ".join(missing)
		if str(neighbours.get("reason", "")) != "":
			out += "\n[color=#dd8888]%s[/color]" % str(neighbours["reason"])
	elif int((p["offset"] as Vector2i).x) != 0 \
			or int((p["offset"] as Vector2i).y) != 0:
		out += ("\n\n[color=#ddaa66]⚠ Neighbour realignment was off, and this "
				+ "resize moved the existing content — any connection offset "
				+ "on this map is now out by that much.[/color]")

	if not overlaps.is_empty():
		out += "\n\n[color=#dd8888]⚠ Overridden — now overlaps %s.[/color]" \
				% ", ".join(overlaps)

	# ⚠️ **THE ONE INSTRUCTION LEFT, AND IT IS NOW EXACTLY ONE.** This used to
	# ask for two saves, and asking for two is what let one be forgotten.
	if save_err != OK:
		out += ("\n\n[color=#dd8888]⚠ THE CELL DATA DID NOT SAVE — %s. Do NOT "
				+ "save the scene: that would persist moved tiles against "
				+ "unmoved collision. Undo instead.[/color]") \
				% error_string(save_err)
	else:
		out += "\n\n[b]The cell data is saved.[/b] Now save the SCENE (Ctrl+S) "
		out += "for the tiles and entities."
		# Undo after this point leaves memory and disk disagreeing, which is the
		# ordinary UNSAVED EDITS state the overlay's own banner already covers —
		# said out loud because the save just happened and reads as final.
		out += "\n[color=#ddaa66]Ctrl+Z still reverts the resize; the .tres will "
		out += "then be ahead of the view until you press Save Map Data.[/color]"
	return out
