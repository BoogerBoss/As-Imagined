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


func _exit_tree() -> void:
	if _save_button != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _save_button)
		_save_button.queue_free()
		_save_button = null
	if _entity_inspector != null:
		remove_inspector_plugin(_entity_inspector)
		_entity_inspector = null


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
