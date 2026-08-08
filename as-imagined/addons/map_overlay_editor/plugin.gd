@tool
extends EditorPlugin

## [M27B Step D] Delivers 2D-viewport clicks to a selected MapOverlay.
##
## This plugin exists because a `@tool` Node2D does NOT receive viewport input
## in the 2D editor -- the editor canvas consumes it, and the documented way in
## is `_forward_canvas_gui_input`. Polling `_unhandled_input` from the node
## looks like it should work and silently never fires.
##
## It is also the reason the write half is editor-only for free: a plugin under
## addons/ is not loaded in an exported game, so there is nothing at runtime
## that can call `paint()` even if someone instances the overlay into a shipped
## scene. `paint()` re-checks `Engine.is_editor_hint()` anyway, because that
## second gate is the one that survives this file being removed.

## The save affordance. Painting no longer writes to disk, so this is the ONLY
## deliberate way to persist an edit — and it ships alongside the overlay's own
## dirty banner because either half alone is a trap.
##
## Deliberately the plugin's OWN control rather than leaning on Ctrl+S. The
## normal scene-save path is exactly what put a MapOverlay node into a baked map
## and caused Section N to exist; a button that saves the DATA and nothing else
## cannot make that mistake.
var _save_button: Button = null

var _target: MapOverlay = null

## [M27Q Q3] The entity script/dialogue panel. Its own file, and its own
## EditorInspectorPlugin, because it shares nothing with the painting half
## above: different trigger (selection, not viewport input), different target
## (any OverworldEntity, not a MapOverlay) and no write path at all.
var _entity_inspector: EditorInspectorPlugin = null

## [M27Q Q4] The name-collision checker. A project-level QUESTION, not a
## property of the selection, so it lives on the toolbar beside Save Map Data
## rather than in the Inspector.
var _name_button: Button = null
var _name_dialog: AcceptDialog = null

## [M27Q Q4 follow-up] The overlay toggle.
##
## ⚠️ **THIS EXISTS BECAUSE "REMEMBER TO DELETE IT BEFORE SAVING" IS NOT A
## WORKFLOW, AND IT HAS NOW FAILED TWICE.** Adding a MapOverlay through the
## editor UI gives it an `owner`, and an owned node is written into the baked
## scene by `PackedScene.pack()`. It contaminates TWICE over: the node itself,
## and — because `map_data` is a serialised property pointing at a resource —
## an `ext_resource` line for the map's own `_data.tres`, a dependency the
## baked scene is deliberately built NOT to have (`MapManager` resolves it by
## path convention at load time instead).
##
## A node added from CODE has `owner == null`, and `pack()` skips it along with
## anything its properties reference. That is the same guarantee `[M27D D1]`
## already relies on for entity sprites: "built with no `owner`, so Godot never
## serialises them and a baked scene stays byte-identical whether or not it has
## been opened." Section N is currently the only thing standing between a
## forgotten deletion and a permanently contaminated map; this makes forgetting
## impossible instead of merely detectable.
const OVERLAY_SCENE := "res://scenes/overworld/map_overlay.tscn"
## Distinct from a plain "MapOverlay" so the toggle can never remove a node
## somebody placed deliberately — it only ever owns the one it created.
const TEMP_OVERLAY_NAME := "MapOverlayEditorTemp"

var _overlay_button: Button = null
var _painting := false
var _last_cell := Vector2i(-9999, -9999)
var _dirty := false


func _enter_tree() -> void:
	_save_button = Button.new()
	_save_button.text = "Save Map Data"
	_save_button.tooltip_text = ("Write the selected MapOverlay's MapData to its"
			+ " .tres. Painting only changes memory.")
	_save_button.pressed.connect(_on_save_pressed)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _save_button)
	_save_button.hide()
	_entity_inspector = preload("res://addons/map_overlay_editor/entity_inspector.gd").new()
	add_inspector_plugin(_entity_inspector)

	_name_dialog = preload("res://addons/map_overlay_editor/name_usage_dialog.gd").new()
	EditorInterface.get_base_control().add_child(_name_dialog)
	_name_button = Button.new()
	_name_button.text = "Name Usage"
	_name_button.tooltip_text = ("Is a FLAG_/VAR_/trainer/label name already "
			+ "taken, how often, and where?")
	_name_button.pressed.connect(func() -> void: _name_dialog.popup_fresh())
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _name_button)

	_overlay_button = Button.new()
	_overlay_button.text = "Overlay"
	_overlay_button.toggle_mode = true
	_overlay_button.tooltip_text = ("Add/remove the MapOverlay on the open map. "
			+ "Added from code, so it has no owner and can never be saved into "
			+ "the scene.")
	_overlay_button.toggled.connect(_on_overlay_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _overlay_button)

	# ⚠️ **EVERY CACHE THIS ADDON READS IS SESSION-LIFETIME, AND WITHOUT THIS
	# HOOK THEY GO STALE SILENTLY.** ScriptPreview holds the 8.6 MB script
	# corpus and the 11,596 text rows; InspectorHints holds the class and item
	# lists. All are cached because rebuilding per Inspector query is the shape
	# that became a five-second stall once already — but that means authoring
	# dialogue, re-running gen_map_texts.py, and looking at the panel would
	# show the OLD text, and a newly authored script label would still warn
	# that it does not resolve. That reads as "my authoring did not work".
	# filesystem_changed fires whenever files change on disk, so the next query
	# rebuilds lazily and the staleness window closes.
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(
			_on_filesystem_changed)


func _exit_tree() -> void:
	if _save_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _save_button)
		_save_button.queue_free()
		_save_button = null
	if _entity_inspector != null:
		remove_inspector_plugin(_entity_inspector)
		_entity_inspector = null
	if _name_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _name_button)
		_name_button.queue_free()
		_name_button = null
	if _name_dialog != null:
		# Parented to the editor base control, so it must be freed explicitly
		# rather than riding the plugin's own teardown.
		_name_dialog.queue_free()
		_name_dialog = null
	if _overlay_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _overlay_button)
		_overlay_button.queue_free()
		_overlay_button = null
	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)


## Drop every cached corpus/name list. Cheap — each rebuilds lazily on next use.
func _on_filesystem_changed() -> void:
	ScriptPreview.reset_cache()
	InspectorHints.clear_caches()


## Add or remove the scratch overlay on whatever map is open.
##
## ⚠️ Never trusts the button's own state to decide what exists. The edited
## scene can change under it, and a stale bool would then either add a second
## overlay or refuse to remove a real one. The scene tree is the truth.
func _on_overlay_toggled(pressed: bool) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_overlay_button.set_pressed_no_signal(false)
		return
	var existing := root.get_node_or_null(TEMP_OVERLAY_NAME)
	if not pressed:
		if existing != null:
			existing.queue_free()
		return
	if existing != null:
		return

	# ⚠️ Refuses on anything that is not a baked map. The overlay reads
	# `MapData`, and the convention `<Map>.tscn` -> `<Map>_data.tres` is the
	# only thing that resolves one — the same convention `MapManager` uses.
	var scene_path := root.scene_file_path
	if not scene_path.begins_with("res://scenes/maps/"):
		push_warning("Overlay: only a baked map under scenes/maps/ has MapData.")
		_overlay_button.set_pressed_no_signal(false)
		return
	var data_path := scene_path.replace(".tscn", "_data.tres")
	if not ResourceLoader.exists(data_path):
		push_warning("Overlay: no MapData at %s." % data_path)
		_overlay_button.set_pressed_no_signal(false)
		return

	# ⚠️ A MapOverlay already sitting in the scene is the CONTAMINATION BUG, not
	# something to add a second one beside. Say so rather than compounding it.
	for c in root.get_children():
		if c is MapOverlay:
			push_warning("Overlay: this scene already contains a MapOverlay "
					+ "node (%s). It is baked in and should be deleted — see "
					+ "m27a section N." % c.name)
			_overlay_button.set_pressed_no_signal(false)
			return

	var node := (load(OVERLAY_SCENE) as PackedScene).instantiate()
	node.name = TEMP_OVERLAY_NAME
	node.map_data = load(data_path)
	# ⚠️ NO `owner` IS SET, AND THAT IS THE ENTIRE MECHANISM. add_child leaves
	# owner null, PackedScene.pack() visits only owned nodes, so neither this
	# node nor the _data.tres its map_data points at can reach the file.
	root.add_child(node)
	# Select it so the paint path is live immediately -- _handles/_edit key on
	# the selection, so an unselected overlay would look inert.
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)


## The one place an edit reaches disk. Reports the real result; a save that
## quietly failed would leave the dirty banner on with no explanation, which is
## the least useful of the three possible states.
func _on_save_pressed() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var err: Error = _target.save_map_data()
	if err == OK:
		print("MapOverlay: saved %s (%d cells still unconfirmed)"
				% [_target.map_data.resource_path, _target.review_count()])
	else:
		push_error("MapOverlay: save FAILED (%d) — nothing was written." % err)
	_target.queue_redraw()


func _handles(object: Object) -> bool:
	return object is MapOverlay


func _edit(object: Object) -> void:
	_target = object as MapOverlay
	_painting = false


func _make_visible(visible: bool) -> void:
	if _save_button != null:
		_save_button.visible = visible
	if not visible:
		_flush()
		_target = null


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false

	# Click-to-select, checked BEFORE the paint gate on purpose: it is the
	# read-only mode's one interaction, and it must not require arming an edit
	# mode to use. Painting is unreachable from EVENTS mode either way -- the
	# two are mutually exclusive by the conditions here, so a click can never
	# both select a node and write a cell.
	if _target.edit_mode == MapOverlay.EditMode.NONE:
		if _target.mode == MapOverlay.Mode.EVENTS:
			return _select_entity_at(event)
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_painting = true
			_last_cell = Vector2i(-9999, -9999)
			# Captured BEFORE the first cell changes -- this is the state
			# Ctrl+Z returns to. The overlay owns the capture and the "is there anything to
			# capture" rule; this only calls it. See MapOverlay's own comment.
			_target.begin_edit_gesture()
			_paint_at(event.position)
			return true          # swallow it: otherwise the click also re-selects
		_painting = false
		_flush()
		return true

	if event is InputEventMouseMotion and _painting:
		_paint_at(event.position)
		return true

	return false


## Puts the clicked entity in the inspector.
##
## Returns true ONLY when a marker was actually hit. A click on empty ground
## has to fall through to the editor, or the overlay would swallow every click
## in the viewport and you could no longer select anything else while it is the
## edited node -- including the overlay itself.
func _select_entity_at(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return false

	var xf: Transform2D = _target.get_viewport_transform() * _target.get_global_transform()
	var cell: Vector2i = _target.cell_at(xf.affine_inverse() * event.position)

	# Which node to select is decided by MapOverlay.next_in_stack(), not here.
	# That keeps every rule with behaviour in it — cycling, wrap-around, a
	# selection sitting on another cell — on the side a headless suite can
	# reach, and leaves this function with no decision left to get wrong.
	var sel := EditorInterface.get_selection()
	var selected: Array[Node] = sel.get_selected_nodes()
	var current: Node = selected[0] if selected.size() > 0 else null
	var hit: OverworldEntity = _target.next_in_stack(cell, current)
	if hit == null:
		return false

	# Selecting REPLACES the selection rather than adding to it: the overlay is
	# the edited node right now, and leaving it selected alongside would show
	# two inspectors and edit the wrong one.
	sel.clear()
	sel.add_node(hit)
	return true


## Viewport pixel -> the overlay's own local space. Goes through the canvas
## transform rather than assuming a 1:1 mapping, so zoom and scroll are handled
## by Godot rather than by arithmetic here.
func _paint_at(viewport_pos: Vector2) -> void:
	var xf: Transform2D = _target.get_viewport_transform() * _target.get_global_transform()
	var cell: Vector2i = _target.cell_at(xf.affine_inverse() * viewport_pos)
	# Drag fires many events per cell; only act when the cell actually changes,
	# so a drag across 40 cells is 40 edits rather than several hundred.
	if cell == _last_cell:
		return
	_last_cell = cell
	if _target.paint(cell):
		_dirty = true


## Commits the drag as ONE undo step, and saves.
##
## Both are deferred to mouse-up on purpose. Per-cell would write the .tres
## once per cell touched, and — worse — would put forty entries in the undo
## history for one gesture, so Ctrl+Z would walk back through a drag one cell
## at a time. One gesture, one undo step, matching what the hand did.
##
## Routing through EditorUndoRedoManager is what makes this an editor rather
## than a hazard. Mutating a resource outside it does not merely leave Ctrl+Z
## doing nothing: the editor's history is still live, so the keystroke undoes
## some UNRELATED earlier action while the paint stays applied. Silently
## wrong is worse than unavailable.
func _flush() -> void:
	if not _dirty or _target == null or not is_instance_valid(_target):
		_dirty = false
		# Only reachable on the overlay if there IS one -- this branch also
		# covers _target having gone away, which is why it is guarded.
		if _target != null and is_instance_valid(_target):
			_target.end_edit_gesture()
		return
	_dirty = false

	var pre: Dictionary = _target.end_edit_gesture()
	if pre.is_empty():
		# The overlay says there was nothing to capture. Committing anyway
		# would put an action in the history that reverts nothing.
		return
	var post: Dictionary = _target.snapshot_cells()
	var ur := get_undo_redo()
	# Scoped to the overlay so the action lands in the right history.
	ur.create_action("Paint map cells", UndoRedo.MERGE_DISABLE, _target)
	ur.add_do_method(_target, "restore_cells", post)
	ur.add_undo_method(_target, "restore_cells", pre)
	# commit_action() runs the do method, which is what performs the save --
	# idempotent here, since the state it restores is already live.
	ur.commit_action()

	# NO SAVE HERE. It used to print "saved" after every gesture; measured, that
	# write cost 0.17-0.83 ms while the editor spent ~5 s reacting to it, and
	# EditorFileSystem.update_file() did not suppress that. Persisting is now
	# the Save Map Data button's job, and the overlay's banner says when it is
	# owed. Deliberately NOT debounced: a stall that fires whenever you pause to
	# think is worse than one you can predict.
	if _target.map_data == null or _target.map_data.resource_path.is_empty():
		push_error("MapOverlay: this MapData has no resource_path — it is not a "
				+ "saved .tres, so there is nowhere to write the edit.")
