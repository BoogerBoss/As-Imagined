@tool
extends EditorInspectorPlugin

## [M27T piece 6] The encounter panel: what a map spawns, and a way to edit it.
##
## ⚠️ **THIS FILE DELIBERATELY CONTAINS NO RULES**, exactly as
## `entity_inspector.gd` beside it does not. Which table a map has, what the
## slots say, whether the tiles and the table disagree, which species match a
## query, what a newly-created table starts as — all of it is `EncounterPreview`,
## driven by `m27h_wild_encounters_test` section I. This side turns Dictionaries
## into Controls. That split is the plugin's own standing rule: this addon is the
## project's one surface with no automated coverage and has already shipped three
## defects, so anything with a decision in it belongs on the other side.
##
## ⚠️ **NO DOCK, AND NO SAVE-ON-EDIT.** The Inspector already resolves selection,
## and every slot edit goes through `EditorProperty`'s own `emit_changed`, which
## buys undo/redo and dirty-marking for free — the thing `[M27M]` had to build by
## hand for the paint path. Nothing here calls `ResourceSaver` except the one
## explicit CREATE button; a write on every keystroke is the ~5 s
## `EditorFileSystem` rescan that made the collision brush unusable.


const _MONO_SIZE := 11
const _DIM := Color(1, 1, 1, 0.55)
const _WARN := Color(1.0, 0.75, 0.25)


func _can_handle(object: Object) -> bool:
	if object is EncounterTable or object is EncounterSlot:
		return true
	# A map root: the scene's own root node, when that scene is a baked map.
	var n := object as Node
	return n != null and EncounterPreview.map_name_of(n.scene_file_path) != ""


## ⚠️ **THE SPECIES FIELD IS INTERCEPTED, WHICH IS THE WHOLE REASON PIECE 5
## MADE A SLOT A RESOURCE.** Godot hands out per-property interception only for
## object properties — this hook cannot exist for an entry in a parallel
## `PackedInt32Array`, which is what the storage would have been otherwise.
func _parse_property(object: Object, type: Variant.Type, name: String,
		hint_type: PropertyHint, hint_string: String,
		usage_flags: int, wide: bool) -> bool:
	if object is EncounterSlot and name == "dex":
		add_property_editor(name, SpeciesPicker.new())
		return true
	return false


func _parse_begin(object: Object) -> void:
	var table := object as EncounterTable
	if table != null:
		_parse_table(table)
		return
	var n := object as Node
	if n == null:
		return
	var map_name := EncounterPreview.map_name_of(n.scene_file_path)
	if map_name != "":
		_parse_map(map_name, n)


## The header on an open table: what its rate actually MEANS.
##
## ⚠️ A rate is a bare 0-100 int, and at Fire Red's denominator it happens to be
## the percentage per step exactly — so saying so turns an opaque number into the
## thing the author is choosing. Derived through `EncounterPreview` rather than
## restated here, so it stays true if the denominator is ever revisited.
func _parse_table(t: EncounterTable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_heading("Encounter table"))
	var pct := EncounterPreview.rate_percent_per_step(t.encounter_rate)
	box.add_child(_dim("Rate %d — about %.1f%% per step" % [t.encounter_rate, pct]))
	var expected := WildEncounters.slot_rates().size()
	var why := t.incomplete_reason(expected)
	if why != "":
		# A table that silently does nothing is the exact failure this layer
		# exists to prevent, so an unusable one says so where it is edited.
		box.add_child(_warn("Not usable yet — %s" % why))
	add_custom_control(box)


func _parse_map(map_name: String, _root: Node) -> void:
	var d := EncounterPreview.digest_for(map_name)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_heading("Wild encounters — %s" % map_name))

	var source := str(d["source"])
	var rate := int(d["encounter_rate"])
	if source == "none":
		box.add_child(_dim("No land table. Nothing spawns here."))
	else:
		var pct := EncounterPreview.rate_percent_per_step(rate)
		box.add_child(_dim("%s · rate %d — about %.1f%% per step"
				% ["authored here" if source == "authored" else "imported",
				rate, pct]))
		var grid := VBoxContainer.new()
		grid.add_theme_constant_override("separation", 0)
		for row in (d["slots"] as Array):
			grid.add_child(_slot_row(row))
		box.add_child(grid)

	# ⚠️ The mismatch check is shown AT THE POINT OF USE, not only in the suite.
	# The authoring order is paint the tiles, then create the table, so the
	# halfway state is what an author is most likely to be looking at.
	var md := _map_data_for(_root)
	var mismatch := EncounterPreview.mismatch_for(map_name, md)
	if mismatch != "":
		box.add_child(_warn(mismatch))

	box.add_child(_button_for(map_name, source))
	add_custom_control(box)


func _slot_row(row: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = SpriteRegistry.get_icon(int(row["dex"]))
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(icon)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", _MONO_SIZE)
	l.text = "%2d%%  %-18s Lv%d-%d" % [int(row["percent"]), str(row["name"]),
			int(row["min"]), int(row["max"])]
	h.add_child(l)
	return h


## The one button, and what it says depends on what the map already has.
##
## ⚠️ **"TAKE OWNERSHIP" AND "CREATE" ARE THE SAME PATH WITH DIFFERENT SEEDS**,
## which is what makes a from-scratch table an ordinary case rather than a
## special one — see `EncounterPreview.seed_table`.
func _button_for(map_name: String, source: String) -> Button:
	var b := Button.new()
	if source == "authored":
		b.text = "Edit this map's table"
		b.tooltip_text = "Open the .tres in the Inspector."
	elif source == "generated":
		b.text = "Take ownership of this table"
		b.tooltip_text = ("Copy the imported table into data/encounters/ so it "
				+ "can be edited. This map then stops receiving converter fixes.")
	else:
		b.text = "Create a table for this map"
		b.tooltip_text = ("Start a blank table. It will not spawn anything until "
				+ "every slot has a species.")
	b.pressed.connect(_on_pressed.bind(map_name, source))
	return b


func _on_pressed(map_name: String, source: String) -> void:
	var path := EncounterPreview.table_path(map_name)
	if source == "authored":
		var existing := ResourceLoader.load(path)
		if existing != null:
			EditorInterface.edit_resource(existing)
		return

	if ResourceLoader.exists(path):
		# Nothing should reach here — a file on disk means the digest should have
		# said "authored" — so if it does, the cache is stale rather than the
		# author being wrong, and clobbering their table would be the worst
		# possible response.
		push_warning("Encounters: %s already exists; opening it rather than "
				% path + "overwriting.")
		WildEncounters.reset_authored_cache()
		EditorInterface.edit_resource(ResourceLoader.load(path))
		return

	var table := EncounterPreview.seed_table(map_name)
	DirAccess.make_dir_recursive_absolute(WildEncounters.AUTHORED_DIR)
	var err := ResourceSaver.save(table, path)
	if err != OK:
		push_error("Encounters: could not write %s (%d) — nothing was created."
				% [path, err])
		return
	# ⚠️ `take_over_path` after the save is load-bearing, the same way it is in
	# `map_baker`: without it the in-memory instance carries no `resource_path`,
	# so the Inspector would edit an object with no file behind it and every
	# subsequent save would write a fresh copy.
	table.take_over_path(path)
	WildEncounters.reset_authored_cache()
	print("Encounters: created %s" % path)
	EditorInterface.edit_resource(table)


## The map's own `MapData`, by the same convention the Overlay button uses.
func _map_data_for(root: Node) -> MapData:
	if root == null:
		return null
	var data_path := root.scene_file_path.replace(".tscn", "_data.tres")
	if not ResourceLoader.exists(data_path):
		return null
	return ResourceLoader.load(data_path) as MapData


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", _DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _warn(text: String) -> Label:
	var l := Label.new()
	l.text = "⚠ " + text
	l.add_theme_color_override("font_color", _WARN)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A filtered species picker, replacing the `dex` int field.
##
## ⚠️ **A BUTTON PLUS A SEARCH POPUP, NOT AN `OptionButton`, AND THAT IS A REAL
## DECISION RATHER THAN A STYLE ONE.** `entity_inspector.gd` records the same
## call being made the other way for trainers and moves — Godot's enum control
## is a plain `OptionButton` with no typeahead, and a 386-entry scroll popup is
## worse to use than typing a number, which is why those fields stayed raw ints
## and a filtered picker was named as the deferred item that would replace them.
## **This is that picker.**
##
## ⚠️ It also sidesteps the wheel problem the scoping flagged (Porymap's own
## `NoScrollComboBox`): a focused `OptionButton` eats the scroll wheel and
## changes VALUE while you are trying to scroll the Inspector, which silently
## edits data. A `Button` does not consume wheel at all, so the Inspector scrolls
## and nothing changes — the guard is structural rather than an input-handler
## workaround.
class SpeciesPicker extends EditorProperty:
	var _button := Button.new()
	var _popup := PopupPanel.new()
	var _filter := LineEdit.new()
	var _list := ItemList.new()
	## Guards the select -> emit_changed -> _update_property loop.
	var _updating := false

	func _init() -> void:
		_button.clip_text = true
		_button.pressed.connect(_open)
		add_child(_button)
		add_focusable(_button)

		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(260, 320)
		_filter.placeholder_text = "name or dex number"
		_filter.text_changed.connect(func(_t: String) -> void: _refill())
		box.add_child(_filter)
		_list.custom_minimum_size = Vector2(0, 280)
		_list.item_selected.connect(_choose)
		box.add_child(_list)
		_popup.add_child(box)
		add_child(_popup)

	func _update_property() -> void:
		if _updating:
			return
		var dex := int(get_edited_object()[get_edited_property()])
		_button.text = EncounterPreview.species_label(dex)
		_button.icon = SpriteRegistry.get_icon(dex)
		# ⚠️ An unresolved species is COLOURED, not merely worded — a slot
		# pointing at a species this roster does not have must not read like an
		# ordinary row, or it ships.
		if dex > 0 and TrainerData.species_name_for(dex) == "":
			_button.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		else:
			_button.remove_theme_color_override("font_color")

	func _open() -> void:
		_filter.text = ""
		_refill()
		_popup.popup_on_parent(Rect2i(_button.global_position, Vector2i(260, 320)))
		_filter.grab_focus()

	func _refill() -> void:
		_list.clear()
		for row in EncounterPreview.species_matches(_filter.text):
			var r: Dictionary = row
			var idx := _list.add_item("%03d  %s" % [int(r["dex"]), str(r["name"])],
					SpriteRegistry.get_icon(int(r["dex"])))
			_list.set_item_metadata(idx, int(r["dex"]))

	func _choose(index: int) -> void:
		var dex := int(_list.get_item_metadata(index))
		_popup.hide()
		# The guard is what stops `emit_changed` bouncing straight back through
		# `_update_property` and re-entering mid-write.
		_updating = true
		emit_changed(get_edited_property(), dex)
		_updating = false
		_update_property()
